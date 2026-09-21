-- | Issue and bug tracking commands.
-- Handles /issue, /bug, /resolve, and /issues.
module Commands.Issue
  ( -- * Command handlers
    handleIssue
  , handleBug
  , handleResolve
  , handleListIssues
    -- * ADTs
  , Issue (..)
  , IssueKind (..)
  , IssueStatus (..)
  , IssueSeverity (..)
    -- * STM state
  , IssueState (..)
  , newIssueState
  ) where

import           Control.Concurrent.STM  (TVar, atomically, modifyTVar',
                                          newTVarIO, readTVarIO)
import           Data.Map.Strict         (Map)
import qualified Data.Map.Strict         as Map
import           Data.Text               (Text)
import qualified Data.Text               as T
import           Data.Time               (getCurrentTime)
import           Lib.Persistence         (DbHandle, IssueRow (..),
                                          insertIssue, listIssues, resolveIssue)
import           Types                   (BotContext (..), BotError (..),
                                          BotResponse (..), BotUser (..),
                                          ChatId (..), MessageId,
                                          PersistenceError (..), ResponseKind (..),
                                          UserId (..))

-- ---------------------------------------------------------------------------
-- ADTs
-- ---------------------------------------------------------------------------

data IssueKind = KindIssue | KindBug
  deriving (Show, Eq, Ord)

issueKindToText :: IssueKind -> Text
issueKindToText KindIssue = "issue"
issueKindToText KindBug   = "bug"

issueKindFromText :: Text -> IssueKind
issueKindFromText "bug" = KindBug
issueKindFromText _     = KindIssue

issueKindLabel :: IssueKind -> Text
issueKindLabel KindIssue = "[ISSUE]"
issueKindLabel KindBug   = "[BUG]  "

data IssueStatus = IssueOpen | IssueResolved | IssueClosed
  deriving (Show, Eq, Ord)

issueStatusToText :: IssueStatus -> Text
issueStatusToText IssueOpen     = "open"
issueStatusToText IssueResolved = "resolved"
issueStatusToText IssueClosed   = "closed"

issueStatusFromText :: Text -> IssueStatus
issueStatusFromText "resolved" = IssueResolved
issueStatusFromText "closed"   = IssueClosed
issueStatusFromText _          = IssueOpen

issueStatusLabel :: IssueStatus -> Text
issueStatusLabel IssueOpen     = "OPEN"
issueStatusLabel IssueResolved = "RESOLVED"
issueStatusLabel IssueClosed   = "CLOSED"

data IssueSeverity = SeverityLow | SeverityMedium | SeverityHigh | SeverityCritical
  deriving (Show, Eq, Ord)

issueSeverityFromText :: Text -> IssueSeverity
issueSeverityFromText "low"      = SeverityLow
issueSeverityFromText "high"     = SeverityHigh
issueSeverityFromText "critical" = SeverityCritical
issueSeverityFromText _          = SeverityMedium

issueSeverityToText :: IssueSeverity -> Text
issueSeverityToText SeverityLow      = "low"
issueSeverityToText SeverityMedium   = "medium"
issueSeverityToText SeverityHigh     = "high"
issueSeverityToText SeverityCritical = "critical"

data Issue = Issue
  { issueId         :: Text
  , issueChatId     :: Int
  , issueTitle      :: Text
  , issueDesc       :: Maybe Text
  , issueKind       :: IssueKind
  , issueStatus     :: IssueStatus
  , issueSeverity   :: IssueSeverity
  , issueReporter   :: Maybe Int
  , issueCreatedAt  :: Text
  , issueResolvedAt :: Maybe Text
  } deriving (Show, Eq)

issueFromRow :: IssueRow -> Issue
issueFromRow r = Issue
  { issueId         = irowId r
  , issueChatId     = irowChatId r
  , issueTitle      = irowTitle r
  , issueDesc       = irowDesc r
  , issueKind       = issueKindFromText     (irowKind r)
  , issueStatus     = issueStatusFromText   (irowStatus r)
  , issueSeverity   = issueSeverityFromText (irowSeverity r)
  , issueReporter   = irowReporter r
  , issueCreatedAt  = irowCreatedAt r
  , issueResolvedAt = irowResolvedAt r
  }

-- ---------------------------------------------------------------------------
-- STM state
-- ---------------------------------------------------------------------------

-- | Per-chat in-memory issue cache.
data IssueState = IssueState
  { isIssues :: TVar (Map Text Issue)       -- issue_id -> Issue
  , isByChat :: TVar (Map Int [Text])       -- chat_id  -> [issue_id]
  }

newIssueState :: IO IssueState
newIssueState = IssueState
  <$> newTVarIO Map.empty
  <*> newTVarIO Map.empty

-- | Cache an issue in the STM state.
cacheIssue :: IssueState -> Issue -> IO ()
cacheIssue is issue = atomically $ do
  modifyTVar' (isIssues is) (Map.insert (issueId issue) issue)
  modifyTVar' (isByChat  is) $
    Map.insertWith (++) (issueChatId issue) [issueId issue]

-- | Update an issue's status in the STM cache.
cacheResolve :: IssueState -> Text -> IO ()
cacheResolve is iid = atomically $
  modifyTVar' (isIssues is) $
    Map.adjust (\i -> i { issueStatus = IssueResolved }) iid

-- ---------------------------------------------------------------------------
-- Response helpers
-- ---------------------------------------------------------------------------

textResponse :: BotContext -> Text -> BotResponse
textResponse ctx t = BotResponse
  { respChatId  = ctxChatId ctx
  , respText    = t
  , respKind    = MarkdownResponse
  , respReplyTo = Nothing
  }

ok :: BotContext -> Text -> Either BotError [BotResponse]
ok ctx t = Right [textResponse ctx t]

err :: BotError -> Either BotError [BotResponse]
err = Left

-- ---------------------------------------------------------------------------
-- Issue state transitions
-- ---------------------------------------------------------------------------

-- | Legal status transitions for an issue.
-- Returns Left if the transition is not permitted.
validateTransition :: IssueStatus -> IssueStatus -> Either Text ()
validateTransition IssueOpen     IssueResolved = Right ()
validateTransition IssueOpen     IssueClosed   = Right ()
validateTransition IssueResolved IssueClosed   = Right ()
validateTransition from          to            =
  Left $ "Cannot transition from " <> issueStatusLabel from
      <> " to " <> issueStatusLabel to

-- ---------------------------------------------------------------------------
-- /issue handler
-- ---------------------------------------------------------------------------

-- Usage: /issue <title text>
handleIssue
  :: DbHandle
  -> IssueState
  -> BotContext
  -> IO (Either BotError [BotResponse])
handleIssue db is ctx =
  case ctxArgs ctx of
    [] -> pure . ok ctx $ "Usage: /issue <title>\nExample: /issue Login page throws 500"
    _  -> createIssue db is ctx KindIssue (T.unwords (ctxArgs ctx)) Nothing

-- ---------------------------------------------------------------------------
-- /bug handler
-- ---------------------------------------------------------------------------

-- Usage: /bug <description>
handleBug
  :: DbHandle
  -> IssueState
  -> BotContext
  -> IO (Either BotError [BotResponse])
handleBug db is ctx =
  case ctxArgs ctx of
    [] -> pure . ok ctx $ "Usage: /bug <description>\nExample: /bug Null pointer in payment flow"
    _  -> createIssue db is ctx KindBug (T.unwords (ctxArgs ctx)) Nothing

-- ---------------------------------------------------------------------------
-- Shared issue creation logic
-- ---------------------------------------------------------------------------

createIssue
  :: DbHandle
  -> IssueState
  -> BotContext
  -> IssueKind
  -> Text          -- ^ title / description
  -> Maybe Text    -- ^ optional extra detail
  -> IO (Either BotError [BotResponse])
createIssue db is ctx kind title mDesc = do
  let chatId     = unChatId (ctxChatId ctx)
      reporterId = fmap ((\(UserId uid) -> uid) . botUserId) (ctxUser ctx)
  result <- insertIssue db chatId title mDesc (issueKindToText kind) reporterId
  case result of
    Left pe  -> pure . err $ PersistErr pe
    Right iid -> do
      now <- getCurrentTime
      let issue = Issue
            { issueId         = iid
            , issueChatId     = chatId
            , issueTitle      = title
            , issueDesc       = mDesc
            , issueKind       = kind
            , issueStatus     = IssueOpen
            , issueSeverity   = SeverityMedium
            , issueReporter   = reporterId
            , issueCreatedAt  = show now
            , issueResolvedAt = Nothing
            }
      cacheIssue is issue
      pure . ok ctx $
        issueKindLabel kind
        <> " filed.\n*Title:* " <> title
        <> "\nID: `" <> iid <> "`"
        <> "\nStatus: " <> issueStatusLabel IssueOpen

-- ---------------------------------------------------------------------------
-- /resolve handler
-- ---------------------------------------------------------------------------

-- Usage: /resolve <issue_id>
handleResolve
  :: DbHandle
  -> IssueState
  -> BotContext
  -> IO (Either BotError [BotResponse])
handleResolve db is ctx =
  case ctxArgs ctx of
    []       -> pure . ok ctx $ "Usage: /resolve <issue_id>"
    (iid:_)  -> resolveIssueCmd db is ctx iid

resolveIssueCmd
  :: DbHandle
  -> IssueState
  -> BotContext
  -> Text          -- ^ issue id
  -> IO (Either BotError [BotResponse])
resolveIssueCmd db is ctx iid = do
  -- Look up current state from cache first
  cachedIssues <- readTVarIO (isIssues is)
  case Map.lookup iid cachedIssues of
    Just issue ->
      case validateTransition (issueStatus issue) IssueResolved of
        Left transErr -> pure . err $ ValidationError transErr
        Right () -> doResolve db is ctx iid
    Nothing ->
      -- Not in cache — attempt anyway (may have been persisted by another session)
      doResolve db is ctx iid

doResolve
  :: DbHandle
  -> IssueState
  -> BotContext
  -> Text
  -> IO (Either BotError [BotResponse])
doResolve db is ctx iid = do
  result <- resolveIssue db iid
  case result of
    Left pe -> pure . err $ PersistErr pe
    Right () -> do
      cacheResolve is iid
      pure . ok ctx $
        "Issue `" <> T.take 8 iid <> "...` resolved."

-- ---------------------------------------------------------------------------
-- /issues handler
-- ---------------------------------------------------------------------------

-- Usage: /issues [open|resolved|all]
handleListIssues
  :: DbHandle
  -> IssueState
  -> BotContext
  -> IO (Either BotError [BotResponse])
handleListIssues db _ ctx = do
  let chatId = unChatId (ctxChatId ctx)
  let mFilter = case ctxArgs ctx of
        ("open" : _)     -> Just "open"
        ("resolved" : _) -> Just "resolved"
        ("all" : _)      -> Nothing
        []               -> Just "open"
        _                -> Just "open"
  result <- listIssues db chatId mFilter
  case result of
    Left pe -> pure . err $ PersistErr pe
    Right [] -> pure . ok ctx $ "No issues found."
    Right rows ->
      let issues = map issueFromRow rows
          render i =
            issueKindLabel (issueKind i)
            <> " [" <> issueStatusLabel (issueStatus i) <> "] "
            <> issueTitle i
            <> " (`" <> T.take 8 (issueId i) <> "`)"
          ls = map render issues
      in pure . ok ctx $
           "*Issues:*\n" <> T.unlines ls

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

-- | Safely extract the Int from a ChatId.
unChatIdInt :: ChatId -> Int
unChatIdInt (ChatId n) = n
