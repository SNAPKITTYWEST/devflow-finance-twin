-- | Shared types for the Devflow Telegram Bot.
-- All core ADTs, typeclasses, and error types live here.
module Types
  ( -- * User types
    BotUser (..)
  , UserId (..)
  , Username (..)
    -- * Message types
  , BotMessage (..)
  , MessageId (..)
  , ChatId (..)
  , ChatType (..)
    -- * Context
  , BotContext (..)
  , ConversationState (..)
    -- * Command typeclass
  , Command (..)
  , CommandName (..)
  , ParsedCommand (..)
  , parseCommand
    -- * Response types
  , BotResponse (..)
  , ResponseKind (..)
    -- * Error types
  , BotError (..)
  , PersistenceError (..)
  , OllamaError (..)
    -- * Config
  , BotConfig (..)
  , defaultConfig
    -- * Formatting utilities
  , botErrorText
  , allHelpText
  ) where

import           Data.Aeson       (FromJSON (..), ToJSON (..), object, withObject,
                                   (.!=), (.:), (.:?), (.=))
import           Data.Map.Strict  (Map)
import qualified Data.Map.Strict  as Map
import           Data.Text        (Text)
import qualified Data.Text        as T
import           Data.Time        (UTCTime)
import           Data.UUID        (UUID)

-- ---------------------------------------------------------------------------
-- Newtypes
-- ---------------------------------------------------------------------------

newtype UserId   = UserId   { unUserId   :: Int    } deriving (Show, Eq, Ord)
newtype Username = Username { unUsername :: Text   } deriving (Show, Eq, Ord)
newtype MessageId = MessageId { unMessageId :: Int } deriving (Show, Eq, Ord)
newtype ChatId    = ChatId    { unChatId    :: Int } deriving (Show, Eq, Ord)
newtype CommandName = CommandName { unCommandName :: Text } deriving (Show, Eq, Ord)

-- ---------------------------------------------------------------------------
-- User
-- ---------------------------------------------------------------------------

data BotUser = BotUser
  { botUserId        :: UserId
  , botUsername      :: Maybe Username
  , botFirstName     :: Text
  , botLastName      :: Maybe Text
  , botIsBot         :: Bool
  , botLanguageCode  :: Maybe Text
  } deriving (Show, Eq)

instance ToJSON BotUser where
  toJSON u = object
    [ "id"            .= unUserId (botUserId u)
    , "username"      .= fmap unUsername (botUsername u)
    , "first_name"    .= botFirstName u
    , "last_name"     .= botLastName u
    , "is_bot"        .= botIsBot u
    , "language_code" .= botLanguageCode u
    ]

instance FromJSON BotUser where
  parseJSON = withObject "BotUser" $ \o -> BotUser
    <$> (UserId   <$> o .:  "id")
    <*> (fmap Username <$> o .:? "username")
    <*> o .: "first_name"
    <*> o .:? "last_name"
    <*> o .:? "is_bot" .!= False
    <*> o .:? "language_code"

-- ---------------------------------------------------------------------------
-- Chat
-- ---------------------------------------------------------------------------

data ChatType
  = Private
  | Group
  | Supergroup
  | Channel
  deriving (Show, Eq, Ord)

instance ToJSON ChatType where
  toJSON Private    = "private"
  toJSON Group      = "group"
  toJSON Supergroup = "supergroup"
  toJSON Channel    = "channel"

instance FromJSON ChatType where
  parseJSON v = do
    t <- parseJSON v
    case (t :: Text) of
      "private"    -> pure Private
      "group"      -> pure Group
      "supergroup" -> pure Supergroup
      "channel"    -> pure Channel
      other        -> fail $ "Unknown chat type: " <> T.unpack other

-- ---------------------------------------------------------------------------
-- Message
-- ---------------------------------------------------------------------------

data BotMessage = BotMessage
  { msgId        :: MessageId
  , msgChatId    :: ChatId
  , msgChatType  :: ChatType
  , msgFrom      :: Maybe BotUser
  , msgText      :: Maybe Text
  , msgDate      :: UTCTime
  , msgReplyTo   :: Maybe MessageId
  } deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Context
-- ---------------------------------------------------------------------------

-- | Per-chat conversation state.
data ConversationState
  = Idle
  | AwaitingSprintName
  | AwaitingItemDescription UUID   -- ^ the sprint to add the item to
  | AwaitingIssueTitle
  | AwaitingBugDescription
  | AwaitingResolveTarget
  deriving (Show, Eq)

data BotContext = BotContext
  { ctxMessage      :: BotMessage
  , ctxUser         :: Maybe BotUser
  , ctxChatId       :: ChatId
  , ctxConvState    :: ConversationState
  , ctxArgs         :: [Text]
  , ctxRawText      :: Text
  } deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Command typeclass
-- ---------------------------------------------------------------------------

-- | Any command must be able to produce a name, help text, and handle a context.
class Command cmd where
  commandName    :: cmd -> CommandName
  commandHelp    :: cmd -> Text
  -- | Execute returns either an error or a list of responses.
  commandExecute :: cmd -> BotContext -> IO (Either BotError [BotResponse])

-- ---------------------------------------------------------------------------
-- ParsedCommand
-- ---------------------------------------------------------------------------

data ParsedCommand = ParsedCommand
  { pcName :: CommandName
  , pcArgs :: [Text]
  , pcRaw  :: Text
  } deriving (Show, Eq)

-- | Parse a message text into a command + arguments.
-- Returns Nothing if the message does not start with '/'.
parseCommand :: Text -> Maybe ParsedCommand
parseCommand txt
  | T.null txt = Nothing
  | T.head txt /= '/' = Nothing
  | otherwise =
      let parts   = T.words txt
          cmdFull = T.tail (head parts)           -- strip leading '/'
          cmdBase = T.takeWhile (/= '@') cmdFull  -- strip @BotName suffix
          args    = tail parts
      in Just ParsedCommand
           { pcName = CommandName cmdBase
           , pcArgs = args
           , pcRaw  = txt
           }

-- ---------------------------------------------------------------------------
-- Response types
-- ---------------------------------------------------------------------------

data ResponseKind
  = TextResponse
  | MarkdownResponse
  | HTMLResponse
  deriving (Show, Eq)

data BotResponse = BotResponse
  { respChatId  :: ChatId
  , respText    :: Text
  , respKind    :: ResponseKind
  , respReplyTo :: Maybe MessageId
  } deriving (Show, Eq)

-- Smart constructors
textReply :: ChatId -> Text -> BotResponse
textReply cid t = BotResponse cid t TextResponse Nothing

markdownReply :: ChatId -> Text -> BotResponse
markdownReply cid t = BotResponse cid t MarkdownResponse Nothing

replyTo :: MessageId -> BotResponse -> BotResponse
replyTo mid resp = resp { respReplyTo = Just mid }

-- These are exported for use in command modules
_textReply :: ChatId -> Text -> BotResponse
_textReply = textReply

_markdownReply :: ChatId -> Text -> BotResponse
_markdownReply = markdownReply

_replyTo :: MessageId -> BotResponse -> BotResponse
_replyTo = replyTo

-- ---------------------------------------------------------------------------
-- Error types
-- ---------------------------------------------------------------------------

data PersistenceError
  = SchemaError   Text
  | QueryError    Text
  | NotFoundError Text
  | MigrationError Text
  deriving (Show, Eq)

data OllamaError
  = OllamaConnectionError Text
  | OllamaParseError      Text
  | OllamaTimeoutError
  | OllamaModelNotFound   Text
  deriving (Show, Eq)

data BotError
  = CommandNotFound   CommandName
  | ParseFailure      Text
  | PersistErr        PersistenceError
  | OllamaErr         OllamaError
  | InternalError     Text
  | PermissionDenied  Text
  | ValidationError   Text
  deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Config
-- ---------------------------------------------------------------------------

data BotConfig = BotConfig
  { cfgToken         :: Text
  , cfgOllamaUrl     :: Text
  , cfgOllamaModel   :: Text
  , cfgDbPath        :: FilePath
  , cfgAdminIds      :: [UserId]
  , cfgMaxRetries    :: Int
  , cfgRetryDelayMs  :: Int
  , cfgLogLevel      :: Text
  } deriving (Show, Eq)

defaultConfig :: BotConfig
defaultConfig = BotConfig
  { cfgToken        = ""
  , cfgOllamaUrl    = "http://localhost:11434"
  , cfgOllamaModel  = "llama3.2"
  , cfgDbPath       = "devflow.db"
  , cfgAdminIds     = []
  , cfgMaxRetries   = 3
  , cfgRetryDelayMs = 1000
  , cfgLogLevel     = "INFO"
  }

instance FromJSON BotConfig where
  parseJSON = withObject "BotConfig" $ \o -> BotConfig
    <$> o .:  "token"
    <*> o .:? "ollama_url"   .!= "http://localhost:11434"
    <*> o .:? "ollama_model" .!= "llama3.2"
    <*> o .:? "db_path"      .!= "devflow.db"
    <*> (fmap (map UserId) <$> o .:? "admin_ids") .!= []
    <*> o .:? "max_retries"    .!= 3
    <*> o .:? "retry_delay_ms" .!= 1000
    <*> o .:? "log_level"      .!= "INFO"

instance ToJSON BotConfig where
  toJSON c = object
    [ "token"          .= cfgToken c
    , "ollama_url"     .= cfgOllamaUrl c
    , "ollama_model"   .= cfgOllamaModel c
    , "db_path"        .= cfgDbPath c
    , "admin_ids"      .= map unUserId (cfgAdminIds c)
    , "max_retries"    .= cfgMaxRetries c
    , "retry_delay_ms" .= cfgRetryDelayMs c
    , "log_level"      .= cfgLogLevel c
    ]

-- ---------------------------------------------------------------------------
-- Utility: build an error map
-- ---------------------------------------------------------------------------

-- | Human-readable error messages for the bot to send back to users.
formatBotError :: BotError -> Text
formatBotError err = case err of
  CommandNotFound (CommandName n) ->
    "Unknown command: /" <> n <> ". Use /help to see available commands."
  ParseFailure msg ->
    "Could not parse your input: " <> msg
  PersistErr (SchemaError msg) ->
    "Database schema error: " <> msg
  PersistErr (QueryError msg) ->
    "Database query failed: " <> msg
  PersistErr (NotFoundError msg) ->
    "Not found: " <> msg
  PersistErr (MigrationError msg) ->
    "Migration error: " <> msg
  OllamaErr (OllamaConnectionError msg) ->
    "Could not reach Ollama: " <> msg
  OllamaErr (OllamaParseError msg) ->
    "Ollama returned unexpected data: " <> msg
  OllamaErr OllamaTimeoutError ->
    "Ollama request timed out."
  OllamaErr (OllamaModelNotFound m) ->
    "Ollama model not found: " <> m
  InternalError msg ->
    "Internal error: " <> msg
  PermissionDenied msg ->
    "Permission denied: " <> msg
  ValidationError msg ->
    "Validation error: " <> msg

-- Export for use in other modules
botErrorText :: BotError -> Text
botErrorText = formatBotError

-- Help text map: command name -> description
helpEntries :: Map Text Text
helpEntries = Map.fromList
  [ ("sprint",  "Manage sprints: /sprint new <name> | /sprint list | /sprint close <id>")
  , ("item",    "Manage backlog items: /item add <sprint_id> <desc> | /item list <sprint_id>")
  , ("board",   "Show the sprint board: /board [sprint_id]")
  , ("issue",   "Create an issue: /issue <title>")
  , ("bug",     "Report a bug: /bug <description>")
  , ("resolve", "Resolve an issue or bug: /resolve <id>")
  , ("ask",     "Ask the AI assistant: /ask <question>")
  , ("help",    "Show this help message")
  ]

-- | Format help as Markdown.
formatHelp :: Text
formatHelp = T.unlines $
  [ "*Devflow Bot Commands*", "" ] ++
  map (\(cmd, desc) -> "  /" <> cmd <> " — " <> desc) (Map.toList helpEntries)

-- Export
allHelpText :: Text
allHelpText = formatHelp
