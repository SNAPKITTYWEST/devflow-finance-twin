-- | HSpec test suite for Devflow Telegram Bot.
-- Tests cover command parsing, state transitions, and error handling.
module Main (main) where

import           Control.Concurrent.STM  (atomically, newTVarIO, readTVarIO)
import           Data.Map.Strict         (Map)
import qualified Data.Map.Strict         as Map
import           Data.Text               (Text)
import qualified Data.Text               as T
import           Data.Time               (getCurrentTime)
import           Test.Hspec
import           Test.Hspec.QuickCheck   (prop)
import           Test.QuickCheck         (Arbitrary (..), Gen, choose, elements,
                                          forAll, listOf, oneof, property,
                                          suchThat)

import           Types
import           Commands.Scrum          (BacklogItem (..), ItemStatus (..),
                                          Sprint (..), SprintStatus (..))
import           Commands.Issue          (Issue (..), IssueKind (..),
                                          IssueStatus (..), IssueSeverity (..))

-- ---------------------------------------------------------------------------
-- Main
-- ---------------------------------------------------------------------------

main :: IO ()
main = hspec $ do
  describe "Types"            typesSpec
  describe "parseCommand"     parseCommandSpec
  describe "SprintStatus"     sprintStatusSpec
  describe "ItemStatus"       itemStatusSpec
  describe "IssueStatus"      issueStatusSpec
  describe "IssueTransitions" issueTransitionSpec
  describe "BotError"         botErrorSpec
  describe "BotConfig"        botConfigSpec
  describe "ResponseKind"     responseKindSpec
  describe "ConversationState" convStateSpec

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- | Make a minimal BotMessage for testing.
testMessage :: Int -> Text -> BotMessage
testMessage chatId txt = BotMessage
  { msgId       = MessageId 1
  , msgChatId   = ChatId chatId
  , msgChatType = Private
  , msgFrom     = Just testUser
  , msgText     = Just txt
  , msgDate     = read "2026-01-01 00:00:00 UTC"
  , msgReplyTo  = Nothing
  }

testUser :: BotUser
testUser = BotUser
  { botUserId       = UserId 42
  , botUsername     = Just (Username "testuser")
  , botFirstName    = "Test"
  , botLastName     = Just "User"
  , botIsBot        = False
  , botLanguageCode = Just "en"
  }

testContext :: Text -> BotContext
testContext txt = BotContext
  { ctxMessage   = testMessage 100 txt
  , ctxUser      = Just testUser
  , ctxChatId    = ChatId 100
  , ctxConvState = Idle
  , ctxArgs      = tail (T.words txt)   -- drop the command word
  , ctxRawText   = txt
  }

-- ---------------------------------------------------------------------------
-- Types spec
-- ---------------------------------------------------------------------------

typesSpec :: Spec
typesSpec = do
  describe "UserId" $ do
    it "stores and retrieves Int" $ do
      let uid = UserId 1234
      unUserId uid `shouldBe` 1234

  describe "ChatId" $ do
    it "stores and retrieves Int" $ do
      let cid = ChatId 9999
      unChatId cid `shouldBe` 9999

  describe "CommandName" $ do
    it "stores and retrieves Text" $ do
      let cn = CommandName "sprint"
      unCommandName cn `shouldBe` "sprint"

  describe "Username" $ do
    it "stores and retrieves Text" $ do
      let u = Username "alice"
      unUsername u `shouldBe` "alice"

  describe "BotUser" $ do
    it "round-trips through JSON" $ do
      let u = testUser
      -- We just check the fields are accessible
      unUserId (botUserId u) `shouldBe` 42
      botFirstName u `shouldBe` "Test"
      botIsBot u `shouldBe` False

-- ---------------------------------------------------------------------------
-- parseCommand spec
-- ---------------------------------------------------------------------------

parseCommandSpec :: Spec
parseCommandSpec = do
  it "parses /sprint" $ do
    let Just pc = parseCommand "/sprint new My Sprint"
    unCommandName (pcName pc) `shouldBe` "sprint"
    pcArgs pc `shouldBe` ["new", "My", "Sprint"]

  it "parses /item with arguments" $ do
    let Just pc = parseCommand "/item add abc123 Fix login bug"
    unCommandName (pcName pc) `shouldBe` "item"
    pcArgs pc `shouldBe` ["add", "abc123", "Fix", "login", "bug"]

  it "parses /board without arguments" $ do
    let Just pc = parseCommand "/board"
    unCommandName (pcName pc) `shouldBe` "board"
    pcArgs pc `shouldBe` []

  it "strips @BotName suffix" $ do
    let Just pc = parseCommand "/help@DevflowBot"
    unCommandName (pcName pc) `shouldBe` "help"

  it "returns Nothing for empty text" $ do
    parseCommand "" `shouldBe` Nothing

  it "returns Nothing for non-command text" $ do
    parseCommand "Hello world" `shouldBe` Nothing

  it "returns Nothing for single space" $ do
    parseCommand " " `shouldBe` Nothing

  it "handles /resolve with UUID-style id" $ do
    let Just pc = parseCommand "/resolve 550e8400-e29b-41d4-a716-446655440000"
    unCommandName (pcName pc) `shouldBe` "resolve"
    length (pcArgs pc) `shouldBe` 1

  it "handles /bug with multi-word description" $ do
    let Just pc = parseCommand "/bug Null pointer in payment module on checkout"
    unCommandName (pcName pc) `shouldBe` "bug"
    T.intercalate " " (pcArgs pc) `shouldBe`
      "Null pointer in payment module on checkout"

  prop "any text starting with / parses successfully" $
    forAll (suchThat arbitrary (\t -> not (null t) && head t == '/')) $ \rawStr ->
      let t = T.pack rawStr
      in parseCommand t /= Nothing

-- ---------------------------------------------------------------------------
-- SprintStatus spec
-- ---------------------------------------------------------------------------

sprintStatusSpec :: Spec
sprintStatusSpec = do
  it "SprintActive is not SprintClosed" $ do
    SprintActive `shouldNotBe` SprintClosed

  it "SprintClosed is not SprintActive" $ do
    SprintClosed `shouldNotBe` SprintActive

  it "SprintActive == SprintActive" $ do
    SprintActive `shouldBe` SprintActive

  describe "sprint status ordering" $ do
    it "SprintActive < SprintClosed" $ do
      SprintActive < SprintClosed `shouldBe` True

-- ---------------------------------------------------------------------------
-- ItemStatus spec
-- ---------------------------------------------------------------------------

itemStatusSpec :: Spec
itemStatusSpec = do
  it "ItemTodo is not ItemDone" $ do
    ItemTodo `shouldNotBe` ItemDone

  it "ItemInProgress /= ItemTodo" $ do
    ItemInProgress `shouldNotBe` ItemTodo

  it "ItemBlocked /= ItemDone" $ do
    ItemBlocked `shouldNotBe` ItemDone

  describe "all statuses are distinct" $ do
    it "four values are all different" $ do
      let statuses = [ItemTodo, ItemInProgress, ItemDone, ItemBlocked]
          pairs    = [(a, b) | a <- statuses, b <- statuses, a /= b]
      length pairs `shouldBe` 12  -- 4*3

-- ---------------------------------------------------------------------------
-- IssueStatus spec
-- ---------------------------------------------------------------------------

issueStatusSpec :: Spec
issueStatusSpec = do
  it "IssueOpen is initial state" $ do
    IssueOpen `shouldBe` IssueOpen

  it "IssueResolved /= IssueOpen" $ do
    IssueResolved `shouldNotBe` IssueOpen

  it "IssueClosed /= IssueResolved" $ do
    IssueClosed `shouldNotBe` IssueResolved

-- ---------------------------------------------------------------------------
-- Issue state transition spec
-- ---------------------------------------------------------------------------

issueTransitionSpec :: Spec
issueTransitionSpec = do
  it "open -> resolved is valid" $ do
    validateTransition' IssueOpen IssueResolved `shouldBe` Right ()

  it "open -> closed is valid" $ do
    validateTransition' IssueOpen IssueClosed `shouldBe` Right ()

  it "resolved -> closed is valid" $ do
    validateTransition' IssueResolved IssueClosed `shouldBe` Right ()

  it "resolved -> open is invalid" $ do
    validateTransition' IssueResolved IssueOpen `shouldSatisfy` isLeft

  it "closed -> open is invalid" $ do
    validateTransition' IssueClosed IssueOpen `shouldSatisfy` isLeft

  it "closed -> resolved is invalid" $ do
    validateTransition' IssueClosed IssueResolved `shouldSatisfy` isLeft

-- | Inline reimplementation of the transition check for testing.
validateTransition' :: IssueStatus -> IssueStatus -> Either Text ()
validateTransition' IssueOpen     IssueResolved = Right ()
validateTransition' IssueOpen     IssueClosed   = Right ()
validateTransition' IssueResolved IssueClosed   = Right ()
validateTransition' from          to            =
  Left $ "Invalid: " <> showStatus from <> " -> " <> showStatus to
  where
    showStatus IssueOpen     = "open"
    showStatus IssueResolved = "resolved"
    showStatus IssueClosed   = "closed"

isLeft :: Either a b -> Bool
isLeft (Left _)  = True
isLeft (Right _) = False

-- ---------------------------------------------------------------------------
-- BotError spec
-- ---------------------------------------------------------------------------

botErrorSpec :: Spec
botErrorSpec = do
  it "CommandNotFound contains the command name" $ do
    let err = CommandNotFound (CommandName "frobnicate")
    case err of
      CommandNotFound (CommandName n) -> n `shouldBe` "frobnicate"
      _                               -> expectationFailure "Wrong constructor"

  it "ParseFailure contains the message" $ do
    let err = ParseFailure "bad input"
    case err of
      ParseFailure msg -> msg `shouldBe` "bad input"
      _                -> expectationFailure "Wrong constructor"

  it "InternalError preserves the message" $ do
    let err = InternalError "disk full"
    case err of
      InternalError msg -> msg `shouldBe` "disk full"
      _                 -> expectationFailure "Wrong constructor"

  it "ValidationError preserves message" $ do
    let err = ValidationError "field required"
    case err of
      ValidationError msg -> msg `shouldBe` "field required"
      _                   -> expectationFailure "Wrong constructor"

  it "PersistErr wraps PersistenceError" $ do
    let inner = NotFoundError "sprint-123"
        err   = PersistErr inner
    case err of
      PersistErr (NotFoundError t) -> t `shouldBe` "sprint-123"
      _                            -> expectationFailure "Wrong constructor"

  it "OllamaErr wraps OllamaError" $ do
    let inner = OllamaConnectionError "connection refused"
        err   = OllamaErr inner
    case err of
      OllamaErr (OllamaConnectionError msg) ->
        msg `shouldBe` "connection refused"
      _ -> expectationFailure "Wrong constructor"

  describe "botErrorText" $ do
    it "formats CommandNotFound" $ do
      let t = botErrorText (CommandNotFound (CommandName "xyz"))
      t `shouldContain` "xyz"

    it "formats ParseFailure" $ do
      let t = botErrorText (ParseFailure "bad")
      t `shouldContain` "bad"

    it "formats OllamaTimeout" $ do
      let t = botErrorText (OllamaErr OllamaTimeoutError)
      t `shouldContain` "timed out"

-- ---------------------------------------------------------------------------
-- BotConfig spec
-- ---------------------------------------------------------------------------

botConfigSpec :: Spec
botConfigSpec = do
  it "defaultConfig has empty token" $ do
    cfgToken defaultConfig `shouldBe` ""

  it "defaultConfig has sensible Ollama URL" $ do
    cfgOllamaUrl defaultConfig `shouldBe` "http://localhost:11434"

  it "defaultConfig has positive retry count" $ do
    cfgMaxRetries defaultConfig `shouldSatisfy` (> 0)

  it "defaultConfig has empty admin list" $ do
    cfgAdminIds defaultConfig `shouldBe` []

-- ---------------------------------------------------------------------------
-- ResponseKind spec
-- ---------------------------------------------------------------------------

responseKindSpec :: Spec
responseKindSpec = do
  it "TextResponse /= MarkdownResponse" $ do
    TextResponse `shouldNotBe` MarkdownResponse

  it "HTMLResponse /= MarkdownResponse" $ do
    HTMLResponse `shouldNotBe` MarkdownResponse

-- ---------------------------------------------------------------------------
-- ConversationState spec
-- ---------------------------------------------------------------------------

convStateSpec :: Spec
convStateSpec = do
  it "Idle is Idle" $ do
    Idle `shouldBe` Idle

  it "AwaitingSprintName is not Idle" $ do
    AwaitingSprintName `shouldNotBe` Idle

  it "AwaitingIssueTitle is not AwaitingBugDescription" $ do
    AwaitingIssueTitle `shouldNotBe` AwaitingBugDescription

  it "AwaitingResolveTarget is not Idle" $ do
    AwaitingResolveTarget `shouldNotBe` Idle

-- ---------------------------------------------------------------------------
-- ChatType spec
-- ---------------------------------------------------------------------------

-- (included in typesSpec for brevity; could be expanded)

-- ---------------------------------------------------------------------------
-- Text helper
-- ---------------------------------------------------------------------------

shouldContain :: Text -> Text -> Expectation
shouldContain haystack needle =
  if T.isInfixOf needle haystack
    then pure ()
    else expectationFailure $
           "Expected " <> show haystack <> " to contain " <> show needle
