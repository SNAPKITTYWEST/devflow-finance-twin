-- | Core bot module.
-- Bot type with STM state, command dispatch table, message handler,
-- error recovery, and graceful shutdown.
module Bot
  ( -- * Bot state
    BotState (..)
  , initBotState
    -- * Bot runner
  , runBot
  , stopBot
    -- * Message handling
  , handleUpdate
  , handleCallbackQuery
    -- * Command setup
  , buildRegistry
  ) where

import           Control.Concurrent       (threadDelay)
import           Control.Concurrent.Async (Async, async, cancel, waitCatch)
import           Control.Concurrent.STM   (STM, TVar, atomically, newTVarIO,
                                           readTVar, readTVarIO, writeTVar)
import           Control.Exception        (SomeException, bracket, catch, try)
import           Data.Map.Strict          (Map)
import qualified Data.Map.Strict          as Map
import           Data.Text                (Text)
import qualified Data.Text                as T
import           Data.Time                (getCurrentTime)
import           System.IO                (hPutStrLn, stderr)

import           Agent                    (AgentContext (..), CommandRegistry,
                                           dispatch, dispatchWithFallback,
                                           emptyRegistry, mkAgentContext,
                                           ollamaFallback, registerCommand)
import           Commands.Issue           (IssueState (..), handleBug,
                                           handleIssue, handleListIssues,
                                           handleResolve, newIssueState)
import           Commands.Scrum           (ScrumState (..), handleBoard,
                                           handleItem, handleSprint,
                                           newScrumState)
import           Lib.Ollama               (OllamaConfig (..), defaultOllamaConfig)
import           Lib.Persistence          (DbHandle, closeDb, openDb,
                                           runMigrations)
import           Types                    (BotConfig (..), BotContext (..),
                                           BotError (..), BotMessage (..),
                                           BotResponse (..), BotUser (..),
                                           ChatId (..), Command (..),
                                           CommandName (..), ConversationState (..),
                                           MessageId (..), OllamaError (..),
                                           ParsedCommand (..), ResponseKind (..),
                                           UserId (..), allHelpText, botErrorText,
                                           defaultConfig, parseCommand)

-- ---------------------------------------------------------------------------
-- Bot state
-- ---------------------------------------------------------------------------

-- | Global mutable state held in STM.
data BotState = BotState
  { bsConfig       :: BotConfig
  , bsDb           :: DbHandle
  , bsScrumState   :: ScrumState
  , bsIssueState   :: IssueState
  , bsRegistry     :: CommandRegistry
  , bsOllama       :: OllamaConfig
  , bsConvStates   :: TVar (Map Int ConversationState)  -- chat_id -> state
  , bsMessageCount :: TVar Int
  , bsErrorCount   :: TVar Int
  , bsRunning      :: TVar Bool
  }

-- | Initialize all bot state. Opens DB, runs migrations.
initBotState :: BotConfig -> IO (Either Text BotState)
initBotState cfg = do
  dbResult <- openDb (cfgDbPath cfg)
  case dbResult of
    Left pe -> pure . Left $ "DB open failed: " <> T.pack (show pe)
    Right db -> do
      migResult <- runMigrations db
      case migResult of
        Left me -> do
          closeDb db
          pure . Left $ "Migration failed: " <> T.pack (show me)
        Right () -> do
          scrumSt   <- newScrumState
          issueSt   <- newIssueState
          convStates <- newTVarIO Map.empty
          msgCount  <- newTVarIO 0
          errCount  <- newTVarIO 0
          running   <- newTVarIO True
          let oCfg = defaultOllamaConfig
                { ollamaBaseUrl = cfgOllamaUrl cfg
                , ollamaModel   = cfgOllamaModel cfg
                }
              reg  = buildRegistryWith db scrumSt issueSt
          pure . Right $ BotState
            { bsConfig       = cfg
            , bsDb           = db
            , bsScrumState   = scrumSt
            , bsIssueState   = issueSt
            , bsRegistry     = reg
            , bsOllama       = oCfg
            , bsConvStates   = convStates
            , bsMessageCount = msgCount
            , bsErrorCount   = errCount
            , bsRunning      = running
            }

-- ---------------------------------------------------------------------------
-- Command registration
-- ---------------------------------------------------------------------------

-- | Build the full command registry with all handlers wired in.
buildRegistryWith :: DbHandle -> ScrumState -> IssueState -> CommandRegistry
buildRegistryWith db scrum issues =
  registerCommand (SprintCmd    db scrum)
  . registerCommand (ItemCmd    db scrum)
  . registerCommand (BoardCmd   db scrum)
  . registerCommand (IssueCmd   db issues)
  . registerCommand (BugCmd     db issues)
  . registerCommand (ResolveCmd db issues)
  . registerCommand (IssuesCmd  db issues)
  . registerCommand HelpCmd
  $ emptyRegistry

-- Also re-export for Agent module (avoids circular import)
buildRegistry :: DbHandle -> ScrumState -> IssueState -> CommandRegistry
buildRegistry = buildRegistryWith

-- ---------------------------------------------------------------------------
-- Command newtype wrappers (Command instances)
-- ---------------------------------------------------------------------------

data SprintCmd = SprintCmd DbHandle ScrumState

instance Command SprintCmd where
  commandName    _ = CommandName "sprint"
  commandHelp    _ = "Manage sprints: /sprint new <name> | list | close <id> | active"
  commandExecute (SprintCmd db ss) ctx = handleSprint db ss ctx

data ItemCmd = ItemCmd DbHandle ScrumState

instance Command ItemCmd where
  commandName    _ = CommandName "item"
  commandHelp    _ = "Manage backlog items: /item add <sprint_id> <desc> | list <sprint_id> | done <id>"
  commandExecute (ItemCmd db ss) ctx = handleItem db ss ctx

data BoardCmd = BoardCmd DbHandle ScrumState

instance Command BoardCmd where
  commandName    _ = CommandName "board"
  commandHelp    _ = "Show the sprint board: /board [sprint_id]"
  commandExecute (BoardCmd db ss) ctx = handleBoard db ss ctx

data IssueCmd = IssueCmd DbHandle IssueState

instance Command IssueCmd where
  commandName    _ = CommandName "issue"
  commandHelp    _ = "Create an issue: /issue <title>"
  commandExecute (IssueCmd db is) ctx = handleIssue db is ctx

data BugCmd = BugCmd DbHandle IssueState

instance Command BugCmd where
  commandName    _ = CommandName "bug"
  commandHelp    _ = "Report a bug: /bug <description>"
  commandExecute (BugCmd db is) ctx = handleBug db is ctx

data ResolveCmd = ResolveCmd DbHandle IssueState

instance Command ResolveCmd where
  commandName    _ = CommandName "resolve"
  commandHelp    _ = "Resolve an issue: /resolve <id>"
  commandExecute (ResolveCmd db is) ctx = handleResolve db is ctx

data IssuesCmd = IssuesCmd DbHandle IssueState

instance Command IssuesCmd where
  commandName    _ = CommandName "issues"
  commandHelp    _ = "List issues: /issues [open|resolved|all]"
  commandExecute (IssuesCmd db is) ctx = handleListIssues db is ctx

data HelpCmd = HelpCmd

instance Command HelpCmd where
  commandName    _ = CommandName "help"
  commandHelp    _ = "Show this help message"
  commandExecute _ ctx = pure . Right $
    [ BotResponse
        { respChatId  = ctxChatId ctx
        , respText    = allHelpText
        , respKind    = MarkdownResponse
        , respReplyTo = Nothing
        }
    ]

-- ---------------------------------------------------------------------------
-- Message handling
-- ---------------------------------------------------------------------------

-- | Handle a single Telegram update (message or callback).
handleUpdate :: BotState -> BotMessage -> IO [BotResponse]
handleUpdate bs msg = do
  atomically $ modifyTVarInt (bsMessageCount bs) (+1)
  case msgText msg of
    Nothing   -> pure []  -- no text, ignore
    Just txt  ->
      case parseCommand txt of
        Just pc  -> handleCommandMessage bs msg pc
        Nothing -> handlePlainMessage  bs msg txt

-- | Handle a message that starts with '/'.
handleCommandMessage
  :: BotState
  -> BotMessage
  -> ParsedCommand
  -> IO [BotResponse]
handleCommandMessage bs msg pc = do
  convState <- getConvState bs (unChatId (msgChatId msg))
  let ctx = BotContext
        { ctxMessage   = msg
        , ctxUser      = msgFrom msg
        , ctxChatId    = msgChatId msg
        , ctxConvState = convState
        , ctxArgs      = pcArgs pc
        , ctxRawText   = pcRaw pc
        }
      ac  = mkAgentContext ctx (bsRegistry bs) (bsOllama bs)
  result <- dispatchWithFallback ac (pcName pc)
  case result of
    Left botErr -> do
      atomically $ modifyTVarInt (bsErrorCount bs) (+1)
      logError bs (show botErr)
      pure [errorResponse (msgChatId msg) botErr]
    Right resps -> pure resps

-- | Handle a plain-text message (not a command).
-- Forwards to Ollama if not in a special conversation state.
handlePlainMessage :: BotState -> BotMessage -> Text -> IO [BotResponse]
handlePlainMessage bs msg txt = do
  convState <- getConvState bs (unChatId (msgChatId msg))
  case convState of
    Idle -> do
      -- Forward to Ollama
      let ctx = BotContext
            { ctxMessage   = msg
            , ctxUser      = msgFrom msg
            , ctxChatId    = msgChatId msg
            , ctxConvState = Idle
            , ctxArgs      = []
            , ctxRawText   = txt
            }
          ac = mkAgentContext ctx (bsRegistry bs) (bsOllama bs)
      result <- ollamaFallback (bsOllama bs) ctx txt
      case result of
        Left botErr -> pure [errorResponse (msgChatId msg) botErr]
        Right resps -> pure resps
    _ ->
      -- In a conversation state — produce a prompt based on state
      pure [convStatePrompt (msgChatId msg) convState txt]

-- | Handle a callback query (inline keyboard button press).
handleCallbackQuery :: BotState -> ChatId -> Text -> IO [BotResponse]
handleCallbackQuery bs chatId callbackData = do
  let resp = BotResponse
        { respChatId  = chatId
        , respText    = "Callback received: " <> callbackData
        , respKind    = TextResponse
        , respReplyTo = Nothing
        }
  pure [resp]

-- ---------------------------------------------------------------------------
-- Conversation state helpers
-- ---------------------------------------------------------------------------

getConvState :: BotState -> Int -> IO ConversationState
getConvState bs chatId = do
  m <- readTVarIO (bsConvStates bs)
  pure $ Map.findWithDefault Idle chatId m

setConvState :: BotState -> Int -> ConversationState -> IO ()
setConvState bs chatId st =
  atomically $ do
    m <- readTVar (bsConvStates bs)
    writeTVar (bsConvStates bs) (Map.insert chatId st m)

clearConvState :: BotState -> Int -> IO ()
clearConvState bs chatId = setConvState bs chatId Idle

-- ---------------------------------------------------------------------------
-- Error / conversation response helpers
-- ---------------------------------------------------------------------------

errorResponse :: ChatId -> BotError -> BotResponse
errorResponse cid botErr = BotResponse
  { respChatId  = cid
  , respText    = botErrorText botErr
  , respKind    = TextResponse
  , respReplyTo = Nothing
  }

convStatePrompt :: ChatId -> ConversationState -> Text -> BotResponse
convStatePrompt cid (AwaitingSprintName) _ = BotResponse
  { respChatId  = cid
  , respText    = "Please enter the sprint name."
  , respKind    = TextResponse
  , respReplyTo = Nothing
  }
convStatePrompt cid (AwaitingItemDescription _) _ = BotResponse
  { respChatId  = cid
  , respText    = "Please enter the item description."
  , respKind    = TextResponse
  , respReplyTo = Nothing
  }
convStatePrompt cid AwaitingIssueTitle _ = BotResponse
  { respChatId  = cid
  , respText    = "Please enter the issue title."
  , respKind    = TextResponse
  , respReplyTo = Nothing
  }
convStatePrompt cid AwaitingBugDescription _ = BotResponse
  { respChatId  = cid
  , respText    = "Please describe the bug."
  , respKind    = TextResponse
  , respReplyTo = Nothing
  }
convStatePrompt cid AwaitingResolveTarget _ = BotResponse
  { respChatId  = cid
  , respText    = "Please provide the issue ID to resolve."
  , respKind    = TextResponse
  , respReplyTo = Nothing
  }
convStatePrompt cid Idle _ = BotResponse
  { respChatId  = cid
  , respText    = ""
  , respKind    = TextResponse
  , respReplyTo = Nothing
  }

-- ---------------------------------------------------------------------------
-- Bot runner
-- ---------------------------------------------------------------------------

-- | Run the bot polling loop until the running flag is cleared.
-- This is the top-level loop; actual Telegram API polling is handled
-- by telegram-bot-simple in Main.hs.
runBot :: BotState -> IO ()
runBot bs = do
  logInfo bs "Bot starting."
  loop
  logInfo bs "Bot stopped."
  where
    loop = do
      running <- readTVarIO (bsRunning bs)
      if running
        then do
          -- The actual polling happens in Main.hs via telegram-bot-simple.
          -- This loop handles periodic maintenance.
          threadDelay 60_000_000  -- 60 seconds
          logInfo bs "Heartbeat: bot running."
          loop
        else pure ()

-- | Signal the bot to stop.
stopBot :: BotState -> IO ()
stopBot bs = do
  logInfo bs "Stopping bot..."
  atomically $ writeTVar (bsRunning bs) False
  closeDb (bsDb bs)

-- ---------------------------------------------------------------------------
-- Error recovery
-- ---------------------------------------------------------------------------

-- | Retry an IO action up to N times with exponential backoff.
withRetry :: Int -> Int -> IO (Either BotError a) -> IO (Either BotError a)
withRetry maxRetries delayMs action = go 0
  where
    go n
      | n >= maxRetries = action
      | otherwise = do
          result <- action
          case result of
            Right v  -> pure (Right v)
            Left err ->
              case isRetryable err of
                False -> pure (Left err)
                True  -> do
                  threadDelay (delayMs * 1000 * (2 ^ n))
                  go (n + 1)

isRetryable :: BotError -> Bool
isRetryable (OllamaErr OllamaTimeoutError)         = True
isRetryable (OllamaErr (OllamaConnectionError _))  = True
isRetryable _                                       = False

-- ---------------------------------------------------------------------------
-- Logging helpers
-- ---------------------------------------------------------------------------

logInfo :: BotState -> String -> IO ()
logInfo bs msg = do
  now <- getCurrentTime
  hPutStrLn stderr $ "[INFO] " <> show now <> " " <> msg

logError :: BotState -> String -> IO ()
logError bs msg = do
  now <- getCurrentTime
  hPutStrLn stderr $ "[ERROR] " <> show now <> " " <> msg

-- ---------------------------------------------------------------------------
-- STM utility
-- ---------------------------------------------------------------------------

modifyTVarInt :: TVar Int -> (Int -> Int) -> STM ()
modifyTVarInt tv f = do
  v <- readTVar tv
  writeTVar tv (f v)
