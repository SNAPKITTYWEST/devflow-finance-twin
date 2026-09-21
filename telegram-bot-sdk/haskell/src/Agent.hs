{-# LANGUAGE ExistentialQuantification #-}
-- | Agent framework for the Devflow bot.
-- Provides a Command typeclass with dynamic dispatch, a context type,
-- and an Ollama-powered fallback for unrecognised commands.
module Agent
  ( -- * Command registry
    CommandRegistry (..)
  , emptyRegistry
  , registerCommand
  , lookupCommand
  , registeredNames
    -- * Dispatch
  , dispatch
  , dispatchWithFallback
    -- * Agent context
  , AgentContext (..)
  , mkAgentContext
    -- * Fallback
  , ollamaFallback
  , systemPrompt
  ) where

import           Control.Exception       (SomeException, try)
import           Data.Map.Strict         (Map)
import qualified Data.Map.Strict         as Map
import           Data.Text               (Text)
import qualified Data.Text               as T
import           Lib.Ollama              (OllamaConfig, OllamaMessage (..),
                                          OllamaRole (..), generate)
import           Types                   (BotContext (..), BotError (..),
                                          BotResponse (..), ChatId,
                                          Command (..), CommandName (..),
                                          OllamaError (..), ResponseKind (..))

-- ---------------------------------------------------------------------------
-- CommandRegistry
-- ---------------------------------------------------------------------------

-- | A heterogeneous registry of commands keyed by name.
-- We existentially wrap each command so they can be stored together.
data AnyCommand = forall cmd. Command cmd => AnyCommand cmd

newtype CommandRegistry = CommandRegistry
  { crCommands :: Map CommandName AnyCommand
  }

emptyRegistry :: CommandRegistry
emptyRegistry = CommandRegistry Map.empty

registerCommand :: Command cmd => cmd -> CommandRegistry -> CommandRegistry
registerCommand cmd (CommandRegistry m) =
  CommandRegistry (Map.insert (commandName cmd) (AnyCommand cmd) m)

lookupCommand :: CommandName -> CommandRegistry -> Maybe AnyCommand
lookupCommand name (CommandRegistry m) = Map.lookup name m

registeredNames :: CommandRegistry -> [CommandName]
registeredNames (CommandRegistry m) = Map.keys m

-- ---------------------------------------------------------------------------
-- AgentContext
-- ---------------------------------------------------------------------------

-- | Enhanced context passed to the dispatch pipeline.
data AgentContext = AgentContext
  { acBotCtx    :: BotContext
  , acRegistry  :: CommandRegistry
  , acOllama    :: OllamaConfig
  , acUseFallback :: Bool   -- ^ allow Ollama fallback for unknown commands
  }

mkAgentContext
  :: BotContext
  -> CommandRegistry
  -> OllamaConfig
  -> AgentContext
mkAgentContext ctx reg oCfg = AgentContext
  { acBotCtx      = ctx
  , acRegistry    = reg
  , acOllama      = oCfg
  , acUseFallback = True
  }

-- ---------------------------------------------------------------------------
-- Dispatch
-- ---------------------------------------------------------------------------

-- | Execute a named command.  Returns Left (CommandNotFound name) if the
-- command is not in the registry.
dispatch
  :: AgentContext
  -> CommandName
  -> IO (Either BotError [BotResponse])
dispatch ac name =
  case lookupCommand name (acRegistry ac) of
    Nothing -> pure (Left (CommandNotFound name))
    Just (AnyCommand cmd) -> commandExecute cmd (acBotCtx ac)

-- | Execute a named command; if unknown and fallback is enabled,
-- forward the raw message text to Ollama.
dispatchWithFallback
  :: AgentContext
  -> CommandName
  -> IO (Either BotError [BotResponse])
dispatchWithFallback ac name =
  case lookupCommand name (acRegistry ac) of
    Just (AnyCommand cmd) -> commandExecute cmd (acBotCtx ac)
    Nothing
      | acUseFallback ac ->
          ollamaFallback (acOllama ac) (acBotCtx ac) (ctxRawText (acBotCtx ac))
      | otherwise ->
          pure (Left (CommandNotFound name))

-- ---------------------------------------------------------------------------
-- Ollama fallback
-- ---------------------------------------------------------------------------

-- | The system prompt used when forwarding messages to Ollama.
systemPrompt :: Text
systemPrompt = T.unlines
  [ "You are Devflow, an AI assistant embedded in a Telegram bot."
  , "You help development teams manage sprints, issues, and backlogs."
  , "Be concise, helpful, and direct. Prefer bullet lists when appropriate."
  , "When asked about available commands, mention /sprint, /item, /board,"
  , "/issue, /bug, /resolve, /issues, and /ask."
  , "Do not make up information. If you don't know, say so."
  ]

-- | Send the raw user text to Ollama and wrap the response.
ollamaFallback
  :: OllamaConfig
  -> BotContext
  -> Text              -- ^ raw message text
  -> IO (Either BotError [BotResponse])
ollamaFallback oCfg ctx rawText = do
  result <- try (generate oCfg rawText (Just systemPrompt))
              :: IO (Either SomeException (Either OllamaError Text))
  case result of
    Left ex -> pure . Left . InternalError . T.pack $ show ex
    Right (Left ollamaErr) -> handleOllamaError ctx ollamaErr
    Right (Right responseText) ->
      pure . Right $
        [ BotResponse
            { respChatId  = ctxChatId ctx
            , respText    = responseText
            , respKind    = MarkdownResponse
            , respReplyTo = Nothing
            }
        ]

handleOllamaError :: BotContext -> OllamaError -> IO (Either BotError [BotResponse])
handleOllamaError ctx ollamaErr =
  case ollamaErr of
    OllamaConnectionError msg ->
      -- Graceful degradation: tell the user Ollama is unavailable
      pure . Right $
        [ BotResponse
            { respChatId  = ctxChatId ctx
            , respText    = "AI assistant is currently unavailable. " <>
                            "Please use /help to see available commands."
            , respKind    = TextResponse
            , respReplyTo = Nothing
            }
        ]
    OllamaTimeoutError ->
      pure . Right $
        [ BotResponse
            { respChatId  = ctxChatId ctx
            , respText    = "AI assistant timed out. Please try again."
            , respKind    = TextResponse
            , respReplyTo = Nothing
            }
        ]
    other ->
      pure (Left (OllamaErr other))

-- ---------------------------------------------------------------------------
-- Dynamic dispatch table builder
-- ---------------------------------------------------------------------------

-- | Build a help text listing all registered commands.
registryHelpText :: CommandRegistry -> Text
registryHelpText reg =
  let names = registeredNames reg
      formatName (CommandName n) = "  /" <> n
      lines' = map formatName names
  in "*Available Commands:*\n" <> T.unlines lines'

-- | Return a registry help response.
helpResponse :: AgentContext -> [BotResponse]
helpResponse ac =
  [ BotResponse
      { respChatId  = ctxChatId (acBotCtx ac)
      , respText    = registryHelpText (acRegistry ac)
      , respKind    = MarkdownResponse
      , respReplyTo = Nothing
      }
  ]
