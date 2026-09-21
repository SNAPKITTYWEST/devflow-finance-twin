-- | Scrum / sprint management commands.
-- Handles /sprint, /item, and /board.
module Commands.Scrum
  ( -- * Command handlers
    handleSprint
  , handleItem
  , handleBoard
    -- * ADTs
  , Sprint (..)
  , SprintStatus (..)
  , BacklogItem (..)
  , ItemStatus (..)
    -- * STM state
  , ScrumState (..)
  , newScrumState
  ) where

import           Control.Concurrent.STM  (STM, TVar, atomically, modifyTVar',
                                          newTVarIO, readTVar, readTVarIO,
                                          writeTVar)
import           Data.Map.Strict         (Map)
import qualified Data.Map.Strict         as Map
import           Data.Text               (Text)
import qualified Data.Text               as T
import           Data.Time               (UTCTime, getCurrentTime)
import           Data.UUID               (UUID)
import qualified Data.UUID               as UUID
import qualified Data.UUID.V4            as UUID4
import           Lib.Persistence         (DbHandle, ItemRow (..), SprintRow (..),
                                          closeSprint, insertItem, insertSprint,
                                          listItems, listSprints, updateItemStatus)
import           Types                   (BotContext (..), BotError (..),
                                          BotResponse (..), ChatId (..),
                                          MessageId, PersistenceError (..),
                                          ResponseKind (..))

-- ---------------------------------------------------------------------------
-- ADTs
-- ---------------------------------------------------------------------------

data SprintStatus = SprintActive | SprintClosed
  deriving (Show, Eq, Ord)

sprintStatusFromText :: Text -> SprintStatus
sprintStatusFromText "closed" = SprintClosed
sprintStatusFromText _        = SprintActive

sprintStatusToText :: SprintStatus -> Text
sprintStatusToText SprintActive = "active"
sprintStatusToText SprintClosed = "closed"

data Sprint = Sprint
  { sprintId        :: Text
  , sprintName      :: Text
  , sprintChatId    :: Int
  , sprintStatus    :: SprintStatus
  , sprintCreatedAt :: Text
  , sprintClosedAt  :: Maybe Text
  } deriving (Show, Eq)

sprintFromRow :: SprintRow -> Sprint
sprintFromRow r = Sprint
  { sprintId        = srId r
  , sprintName      = srName r
  , sprintChatId    = srChatId r
  , sprintStatus    = sprintStatusFromText (srStatus r)
  , sprintCreatedAt = srCreatedAt r
  , sprintClosedAt  = srClosedAt r
  }

data ItemStatus = ItemTodo | ItemInProgress | ItemDone | ItemBlocked
  deriving (Show, Eq, Ord)

itemStatusFromText :: Text -> ItemStatus
itemStatusFromText "in_progress" = ItemInProgress
itemStatusFromText "done"        = ItemDone
itemStatusFromText "blocked"     = ItemBlocked
itemStatusFromText _             = ItemTodo

itemStatusToText :: ItemStatus -> Text
itemStatusToText ItemTodo       = "todo"
itemStatusToText ItemInProgress = "in_progress"
itemStatusToText ItemDone       = "done"
itemStatusToText ItemBlocked    = "blocked"

itemStatusEmoji :: ItemStatus -> Text
itemStatusEmoji ItemTodo       = "[TODO]"
itemStatusEmoji ItemInProgress = "[WIP] "
itemStatusEmoji ItemDone       = "[DONE]"
itemStatusEmoji ItemBlocked    = "[BLK] "

data BacklogItem = BacklogItem
  { itemId          :: Text
  , itemSprintId    :: Text
  , itemDescription :: Text
  , itemStatus      :: ItemStatus
  , itemAssignee    :: Maybe Text
  , itemCreatedAt   :: Text
  , itemUpdatedAt   :: Text
  } deriving (Show, Eq)

itemFromRow :: ItemRow -> BacklogItem
itemFromRow r = BacklogItem
  { itemId          = irId r
  , itemSprintId    = irSprintId r
  , itemDescription = irDescription r
  , itemStatus      = itemStatusFromText (irStatus r)
  , itemAssignee    = irAssignee r
  , itemCreatedAt   = irCreatedAt r
  , itemUpdatedAt   = irUpdatedAt r
  }

-- ---------------------------------------------------------------------------
-- STM state
-- ---------------------------------------------------------------------------

-- | In-memory cache of sprints/items for fast board rendering.
-- All mutations go through both STM (cache) and SQLite (persistence).
data ScrumState = ScrumState
  { ssActiveSprint :: TVar (Map Int Text)        -- chat_id -> active sprint_id
  , ssSprints      :: TVar (Map Text Sprint)     -- sprint_id -> Sprint
  , ssItems        :: TVar (Map Text [BacklogItem]) -- sprint_id -> items
  }

newScrumState :: IO ScrumState
newScrumState = ScrumState
  <$> newTVarIO Map.empty
  <*> newTVarIO Map.empty
  <*> newTVarIO Map.empty

-- | Load sprints from DB into STM cache for a given chat.
loadSprintsForChat :: DbHandle -> ScrumState -> Int -> IO ()
loadSprintsForChat db ss chatId = do
  result <- listSprints db chatId
  case result of
    Left _   -> pure ()
    Right rows -> do
      let sprints = map sprintFromRow rows
      atomically $ do
        modifyTVar' (ssSprints ss) $ \m ->
          foldr (\s acc -> Map.insert (sprintId s) s acc) m sprints
        -- Track latest active sprint per chat
        let active = filter ((== SprintActive) . sprintStatus) sprints
        case active of
          (s:_) -> modifyTVar' (ssActiveSprint ss) (Map.insert chatId (sprintId s))
          []    -> pure ()

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
-- /sprint handler
-- ---------------------------------------------------------------------------

-- Subcommands: new <name> | list | close <id> | active
handleSprint
  :: DbHandle
  -> ScrumState
  -> BotContext
  -> IO (Either BotError [BotResponse])
handleSprint db ss ctx =
  case ctxArgs ctx of
    ("new" : nameParts) -> cmdSprintNew db ss ctx (T.unwords nameParts)
    ["list"]            -> cmdSprintList db ss ctx
    ("close" : sid : _) -> cmdSprintClose db ss ctx sid
    ["active"]          -> cmdSprintActive ss ctx
    []                  -> cmdSprintList db ss ctx
    _                   -> pure . ok ctx $
      "Usage: /sprint new <name> | /sprint list | /sprint close <id> | /sprint active"

cmdSprintNew
  :: DbHandle -> ScrumState -> BotContext -> Text
  -> IO (Either BotError [BotResponse])
cmdSprintNew _ _ ctx "" =
  pure . err $ ValidationError "Sprint name cannot be empty."
cmdSprintNew db ss ctx name = do
  let chatId = unChatId (ctxChatId ctx)
  result <- insertSprint db chatId name
  case result of
    Left pe  -> pure . err $ PersistErr pe
    Right sid -> do
      now <- getCurrentTime
      let sprint = Sprint
            { sprintId        = sid
            , sprintName      = name
            , sprintChatId    = chatId
            , sprintStatus    = SprintActive
            , sprintCreatedAt = show now
            , sprintClosedAt  = Nothing
            }
      atomically $ do
        modifyTVar' (ssSprints ss) (Map.insert sid sprint)
        modifyTVar' (ssActiveSprint ss) (Map.insert chatId sid)
      pure . ok ctx $
        "Sprint created.\n*" <> name <> "*\nID: `" <> sid <> "`"

cmdSprintList
  :: DbHandle -> ScrumState -> BotContext
  -> IO (Either BotError [BotResponse])
cmdSprintList db _ ctx = do
  let chatId = unChatId (ctxChatId ctx)
  result <- listSprints db chatId
  case result of
    Left pe -> pure . err $ PersistErr pe
    Right [] -> pure . ok ctx $ "No sprints found. Use /sprint new <name> to create one."
    Right rows ->
      let sprints = map sprintFromRow rows
          renderSprint s =
            ( if sprintStatus s == SprintActive then "[A] " else "[C] " )
            <> sprintName s
            <> " (`" <> T.take 8 (sprintId s) <> "...`)"
          lines' = map renderSprint sprints
      in pure . ok ctx $ "*Sprints:*\n" <> T.unlines lines'

cmdSprintClose
  :: DbHandle -> ScrumState -> BotContext -> Text
  -> IO (Either BotError [BotResponse])
cmdSprintClose db ss ctx sid = do
  result <- closeSprint db sid
  case result of
    Left pe -> pure . err $ PersistErr pe
    Right () -> do
      atomically $ modifyTVar' (ssSprints ss) $
        Map.adjust (\s -> s { sprintStatus = SprintClosed }) sid
      pure . ok ctx $ "Sprint `" <> T.take 8 sid <> "...` closed."

cmdSprintActive :: ScrumState -> BotContext -> IO (Either BotError [BotResponse])
cmdSprintActive ss ctx = do
  let chatId = unChatId (ctxChatId ctx)
  active <- readTVarIO (ssActiveSprint ss)
  case Map.lookup chatId active of
    Nothing  -> pure . ok ctx $ "No active sprint. Use /sprint new <name>."
    Just sid -> do
      sprints <- readTVarIO (ssSprints ss)
      case Map.lookup sid sprints of
        Nothing -> pure . ok ctx $ "Active sprint ID: `" <> sid <> "`"
        Just s  -> pure . ok ctx $
          "*Active Sprint:* " <> sprintName s <> "\nID: `" <> sprintId s <> "`"

-- ---------------------------------------------------------------------------
-- /item handler
-- ---------------------------------------------------------------------------

-- Subcommands: add <sprint_id> <desc...> | list <sprint_id> | done <item_id>
handleItem
  :: DbHandle
  -> ScrumState
  -> BotContext
  -> IO (Either BotError [BotResponse])
handleItem db ss ctx =
  case ctxArgs ctx of
    ("add"  : sid : descParts) -> cmdItemAdd db ss ctx sid (T.unwords descParts)
    ("list" : sid : _)         -> cmdItemList db ss ctx sid
    ("done" : iid : _)         -> cmdItemDone db ss ctx iid
    ("wip"  : iid : _)         -> cmdItemWip  db ss ctx iid
    _                          -> pure . ok ctx $
      "Usage: /item add <sprint_id> <desc> | /item list <sprint_id> | /item done <id>"

cmdItemAdd
  :: DbHandle -> ScrumState -> BotContext -> Text -> Text
  -> IO (Either BotError [BotResponse])
cmdItemAdd _ _ ctx _ "" =
  pure . err $ ValidationError "Item description cannot be empty."
cmdItemAdd db ss ctx sprintId desc = do
  result <- insertItem db sprintId desc
  case result of
    Left pe  -> pure . err $ PersistErr pe
    Right iid -> do
      now <- getCurrentTime
      let item = BacklogItem
            { itemId          = iid
            , itemSprintId    = sprintId
            , itemDescription = desc
            , itemStatus      = ItemTodo
            , itemAssignee    = Nothing
            , itemCreatedAt   = show now
            , itemUpdatedAt   = show now
            }
      atomically $ modifyTVar' (ssItems ss) $
        Map.insertWith (++) sprintId [item]
      pure . ok ctx $
        "Item added to sprint.\nDescription: " <> desc
        <> "\nID: `" <> iid <> "`"

cmdItemList
  :: DbHandle -> ScrumState -> BotContext -> Text
  -> IO (Either BotError [BotResponse])
cmdItemList db _ ctx sprintId = do
  result <- listItems db sprintId
  case result of
    Left pe -> pure . err $ PersistErr pe
    Right [] -> pure . ok ctx $ "No items in this sprint yet."
    Right rows ->
      let items  = map itemFromRow rows
          render i =
            itemStatusEmoji (itemStatus i)
            <> " " <> itemDescription i
            <> " (`" <> T.take 8 (itemId i) <> "`)"
          ls = map render items
      in pure . ok ctx $
           "*Backlog Items:*\n" <> T.unlines ls

cmdItemDone
  :: DbHandle -> ScrumState -> BotContext -> Text
  -> IO (Either BotError [BotResponse])
cmdItemDone db ss ctx iid = do
  result <- updateItemStatus db iid "done"
  case result of
    Left pe -> pure . err $ PersistErr pe
    Right () -> do
      updateItemCache ss iid ItemDone
      pure . ok ctx $ "Item `" <> T.take 8 iid <> "` marked done."

cmdItemWip
  :: DbHandle -> ScrumState -> BotContext -> Text
  -> IO (Either BotError [BotResponse])
cmdItemWip db ss ctx iid = do
  result <- updateItemStatus db iid "in_progress"
  case result of
    Left pe -> pure . err $ PersistErr pe
    Right () -> do
      updateItemCache ss iid ItemInProgress
      pure . ok ctx $ "Item `" <> T.take 8 iid <> "` marked in-progress."

-- | Update an item's status in the STM cache.
updateItemCache :: ScrumState -> Text -> ItemStatus -> IO ()
updateItemCache ss iid newStatus =
  atomically $ modifyTVar' (ssItems ss) $
    Map.map (map (\i ->
      if itemId i == iid
        then i { itemStatus = newStatus }
        else i))

-- ---------------------------------------------------------------------------
-- /board handler
-- ---------------------------------------------------------------------------

handleBoard
  :: DbHandle
  -> ScrumState
  -> BotContext
  -> IO (Either BotError [BotResponse])
handleBoard db ss ctx =
  case ctxArgs ctx of
    (sid : _) -> renderBoard db ctx sid
    []        -> do
      let chatId = unChatId (ctxChatId ctx)
      active <- readTVarIO (ssActiveSprint ss)
      case Map.lookup chatId active of
        Nothing  -> pure . ok ctx $ "No active sprint. Use /sprint new <name>."
        Just sid -> renderBoard db ctx sid

renderBoard
  :: DbHandle -> BotContext -> Text
  -> IO (Either BotError [BotResponse])
renderBoard db ctx sid = do
  itemsResult <- listItems db sid
  case itemsResult of
    Left pe -> pure . err $ PersistErr pe
    Right rows ->
      let items = map itemFromRow rows
          todo  = filter ((== ItemTodo)       . itemStatus) items
          wip   = filter ((== ItemInProgress) . itemStatus) items
          done  = filter ((== ItemDone)        . itemStatus) items
          blk   = filter ((== ItemBlocked)     . itemStatus) items
          renderItem i = "  - " <> itemDescription i
          section hdr is
            | null is   = ""
            | otherwise = "*" <> hdr <> "*\n" <> T.unlines (map renderItem is)
          board =
            "*Sprint Board* (`" <> T.take 8 sid <> "...`)\n\n"
            <> section "To Do"       todo
            <> section "In Progress" wip
            <> section "Done"        done
            <> section "Blocked"     blk
      in pure . ok ctx $ board
