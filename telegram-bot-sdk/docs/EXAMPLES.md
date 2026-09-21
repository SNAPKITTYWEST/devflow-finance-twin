# Telegram Bot SDK — Usage Examples

**License:** GPL-3.0-or-later OR Apache-2.0

All examples assume the environment variables in `.env` are correctly set
(see [INTEGRATION.md](INTEGRATION.md#6-environment-variables-reference)).

---

## Table of Contents

1. [Node.js Examples](#1-nodejs-examples)
2. [Rust Examples](#2-rust-examples)
3. [Haskell Examples](#3-haskell-examples)
4. [Cross-Language Pattern: Shared SQLite State](#4-cross-language-pattern-shared-sqlite-state)
5. [Testing Examples](#5-testing-examples)

---

## 1. Node.js Examples

### 1.1 Minimal Bot (index.js entry point)

```javascript
// node/src/index.js
import 'dotenv/config';
import { Telegraf } from 'telegraf';
import { handleStart }  from './commands/start.mjs';
import { handleHelp }   from './commands/help.mjs';
import { handleScrum }  from './commands/scrum.mjs';
import { handleIssue }  from './commands/issue.mjs';
import { handleAgent }  from './commands/agent.mjs';
import { handleStatus } from './commands/status.mjs';
import { errorHandler } from './middleware/error.mjs';
import { rateLimiter }  from './middleware/rateLimiter.mjs';
import { logger }       from './middleware/logger.mjs';

const bot = new Telegraf(process.env.TELEGRAM_BOT_TOKEN);

// Global middleware (applied to every update).
bot.use(logger);
bot.use(rateLimiter({ windowMs: 60_000, max: 20 }));

// Command registration.
bot.start(handleStart);
bot.help(handleHelp);
bot.command('scrum',  handleScrum);
bot.command('issue',  handleIssue);
bot.command('agent',  handleAgent);
bot.command('status', handleStatus);

// Centralised error handler.
bot.catch(errorHandler);

// Graceful shutdown.
process.once('SIGINT',  () => bot.stop('SIGINT'));
process.once('SIGTERM', () => bot.stop('SIGTERM'));

await bot.launch();
console.log('Bot launched (long-polling)');
```

### 1.2 Scrum Command Handler

```javascript
// node/src/commands/scrum.mjs
import { getScrumBoard } from '../lib/scrum-board.mjs';
import { BotError }      from '../lib/errors.mjs';

const SUB_COMMANDS = new Set(['status', 'create', 'update', 'list', 'assign',
                               'sprint']);

export async function handleScrum(ctx) {
  const [, sub, ...rest] = ctx.message.text.trim().split(/\s+/);

  if (!sub || !SUB_COMMANDS.has(sub)) {
    return ctx.reply(
      'Usage: `/scrum <status|create|update|list|assign|sprint> [args]`',
      { parse_mode: 'Markdown' }
    );
  }

  const board = getScrumBoard(ctx.db);

  switch (sub) {
    case 'status': {
      const sprint = await board.getCurrentSprint();
      if (!sprint) {
        return ctx.reply('No active sprint. Create one with `/scrum sprint new <name>`.',
                         { parse_mode: 'Markdown' });
      }
      const items  = await board.listItems(sprint.id);
      const counts = countByStatus(items);
      const text   = formatSprintStatus(sprint, counts, items);
      return ctx.reply(text, { parse_mode: 'Markdown' });
    }

    case 'create': {
      const title = rest.join(' ');
      if (!title) throw new BotError(400, 'Title is required: /scrum create <title>');
      const item = await board.createItem(sprint.id, title, ctx.from.id);
      return ctx.reply(`Task created: \`${item.id}\` — ${item.title}`,
                       { parse_mode: 'Markdown' });
    }

    case 'update': {
      const [id, newStatus] = rest;
      const VALID = new Set(['todo', 'in-progress', 'done', 'blocked']);
      if (!id || !VALID.has(newStatus)) {
        throw new BotError(400, `Usage: /scrum update <id> <${[...VALID].join('|')}>`);
      }
      await board.updateItemStatus(id, newStatus, ctx.from.id);
      return ctx.reply(`\`${id}\` → *${newStatus}*`, { parse_mode: 'Markdown' });
    }

    default:
      throw new BotError(404, `Unknown subcommand: ${sub}`);
  }
}

function countByStatus(items) {
  return items.reduce((acc, item) => {
    acc[item.status] = (acc[item.status] ?? 0) + 1;
    return acc;
  }, {});
}

function formatSprintStatus(sprint, counts, items) {
  const lines = [
    `*Sprint:* ${sprint.name}`,
    `*Status:* ${sprint.status}`,
    '',
    `📋 Todo: ${counts.todo ?? 0}`,
    `🔄 In progress: ${counts['in-progress'] ?? 0}`,
    `✅ Done: ${counts.done ?? 0}`,
    `🚫 Blocked: ${counts.blocked ?? 0}`,
    '',
    '*Recent items:*',
    ...items.slice(0, 5).map(i => `• \`${i.id}\` ${i.title} [${i.status}]`),
  ];
  return lines.join('\n');
}
```

### 1.3 Agent Command with Ollama

```javascript
// node/src/commands/agent.mjs
import { OllamaClient } from '../lib/ollama.mjs';

const ollama = new OllamaClient({
  baseUrl: process.env.OLLAMA_API_URL,
  model:   process.env.OLLAMA_MODEL,
  timeout: Number(process.env.OLLAMA_TIMEOUT_SECS ?? 60) * 1000,
});

export async function handleAgent(ctx) {
  const query = ctx.message.text.replace(/^\/agent\s*/i, '').trim();

  if (!query) {
    return ctx.reply(
      'Usage: `/agent <your question>`',
      { parse_mode: 'Markdown' }
    );
  }

  // Show typing indicator while Ollama processes.
  await ctx.sendChatAction('typing');

  const history = ctx.session?.conversationHistory ?? [];

  const result = await ollama.generate({
    prompt:  query,
    context: history,
    options: { temperature: 0.7, top_p: 0.9, num_predict: 512 },
  });

  // Persist the turn in session.
  ctx.session ??= {};
  ctx.session.conversationHistory = [
    ...history.slice(-38),                       // keep last 20 pairs
    { role: 'user',      content: query },
    { role: 'assistant', content: result.text },
  ];

  return ctx.reply(result.text, { parse_mode: 'Markdown' });
}
```

### 1.4 Ollama Client Library

```javascript
// node/src/lib/ollama.mjs
export class OllamaClient {
  #baseUrl;
  #model;
  #timeout;

  constructor({ baseUrl, model, timeout = 60_000 }) {
    this.#baseUrl  = baseUrl.replace(/\/$/, '');
    this.#model    = model;
    this.#timeout  = timeout;
  }

  async generate({ prompt, context = [], options = {} }) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.#timeout);

    try {
      const res = await fetch(`${this.#baseUrl}/api/generate`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          model:   this.#model,
          prompt,
          context: context.map(t => `${t.role}: ${t.content}`).join('\n'),
          stream:  false,
          options,
        }),
        signal: controller.signal,
      });

      if (!res.ok) {
        throw new Error(`Ollama responded with HTTP ${res.status}`);
      }

      const json = await res.json();
      return { text: json.response, tokensUsed: json.eval_count ?? 0 };
    } finally {
      clearTimeout(timer);
    }
  }

  async healthCheck() {
    try {
      const res = await fetch(this.#baseUrl, { signal: AbortSignal.timeout(5_000) });
      return res.ok;
    } catch {
      return false;
    }
  }
}
```

---

## 2. Rust Examples

### 2.1 Full-Featured Bot Entry Point

```rust
// rust/examples/full_featured.rs
use std::sync::Arc;
use telegram_bot_sdk::prelude::*;
use telegram_bot_sdk::{
    integrations::{OllamaClient, ScrumBoard},
    state::BotState,
};
use teloxide::prelude::*;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialise structured logging.
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .json()
        .init();

    dotenv::dotenv().ok();

    let config = Config::from_env()?;
    let db     = SqlitePool::connect(&config.database_url).await
                     .map_err(|e| BotError::ConfigError(e.to_string()))?;
    let ollama = OllamaClient::new(&config.ollama_url, &config.ollama_model);
    let board  = ScrumBoard::new(db.clone());

    let state  = Arc::new(BotState::new(db, ollama, board, config));
    let bot    = Bot::from_env();

    tracing::info!("Starting Telegram bot (long-polling)");

    let handler = dptree::entry()
        .branch(Update::filter_message().endpoint(dispatch));

    Dispatcher::builder(bot, handler)
        .dependencies(dptree::deps![state])
        .enable_ctrlc_handler()
        .build()
        .dispatch()
        .await;

    Ok(())
}

async fn dispatch(
    bot:   Bot,
    msg:   Message,
    state: Arc<BotState>,
) -> Result<()> {
    let Some(text) = msg.text() else { return Ok(()); };
    let ctx = Context::from_message(&msg, Arc::clone(&state));

    let response = match extract_command(text) {
        Some("start")  => commands::start::handle(&ctx).await,
        Some("help")   => commands::help::handle(&ctx).await,
        Some("scrum")  => commands::scrum::handle(&ctx).await,
        Some("issue")  => commands::issue::handle(&ctx).await,
        Some("agent")  => commands::agent::handle(&ctx).await,
        Some("status") => commands::status::handle(&ctx).await,
        _              => Ok(Response::error(404, "Unknown command")),
    };

    let resp = response.unwrap_or_else(|e| Response::from_error(e));
    bot.send_message(msg.chat.id, &resp.text)
       .parse_mode(teloxide::types::ParseMode::Markdown)
       .await
       .map_err(|e| BotError::TelegramApi(e.to_string()))?;

    Ok(())
}

fn extract_command(text: &str) -> Option<&str> {
    let token = text.split_whitespace().next()?;
    token.strip_prefix('/')?.split('@').next()
}
```

### 2.2 Scrum Command Handler (Rust)

```rust
// rust/src/commands/scrum.rs
use crate::{
    error::{BotError, Result},
    types::{Action, Context, Response},
};

pub async fn handle(ctx: &Context) -> Result<Response> {
    let args = ctx.args();
    let sub  = args.first().map(|s| s.as_str()).unwrap_or("");

    match sub {
        "status"  => status(ctx).await,
        "create"  => create(ctx, &args[1..]).await,
        "update"  => update(ctx, &args[1..]).await,
        "list"    => list(ctx, args.get(1).map(|s| s.as_str())).await,
        ""        => Ok(Response::text(
            "Usage: `/scrum <status|create|update|list|assign|sprint>`"
        )),
        unknown   => Err(BotError::CommandError(
            format!("Unknown scrum subcommand: {unknown}")
        )),
    }
}

async fn status(ctx: &Context) -> Result<Response> {
    let board  = ctx.state.scrum_board();
    let sprint = board.current_sprint().await?
        .ok_or_else(|| BotError::CommandError(
            "No active sprint. Use `/scrum sprint new <name>`.".into()
        ))?;
    let items = board.list_items(&sprint.id).await?;

    let mut todo = 0u32;
    let mut wip  = 0u32;
    let mut done = 0u32;
    let mut blocked = 0u32;

    for item in &items {
        match item.status.as_str() {
            "todo"        => todo    += 1,
            "in-progress" => wip     += 1,
            "done"        => done    += 1,
            "blocked"     => blocked += 1,
            _             => {}
        }
    }

    let text = format!(
        "*Sprint:* {name}\n\
         Todo: {todo} | In Progress: {wip} | Done: {done} | Blocked: {blocked}",
        name = sprint.name,
    );

    Ok(Response {
        status: "ok".into(),
        text,
        actions: vec![Action::ScrumQuery {
            sprint_id: sprint.id.clone(),
            item_count: items.len() as u32,
        }],
        ..Default::default()
    })
}

async fn create(ctx: &Context, args: &[String]) -> Result<Response> {
    let title = args.join(" ");
    if title.is_empty() {
        return Err(BotError::CommandError("Title required: /scrum create <title>".into()));
    }
    let board  = ctx.state.scrum_board();
    let sprint = board.current_sprint().await?
        .ok_or_else(|| BotError::CommandError("No active sprint".into()))?;
    let item = board.create_item(&sprint.id, &title, ctx.user_id()).await?;

    Ok(Response {
        status: "ok".into(),
        text: format!("Task created: `{}` — {}", item.id, item.title),
        actions: vec![Action::ScrumCreate {
            sprint_id: sprint.id,
            item_id:   item.id.clone(),
            title:     item.title,
        }],
        ..Default::default()
    })
}

async fn update(ctx: &Context, args: &[String]) -> Result<Response> {
    let (id, new_status) = match args {
        [id, status, ..] => (id.clone(), status.clone()),
        _ => return Err(BotError::CommandError(
            "Usage: /scrum update <id> <todo|in-progress|done|blocked>".into()
        )),
    };

    let valid = ["todo", "in-progress", "done", "blocked"];
    if !valid.contains(&new_status.as_str()) {
        return Err(BotError::CommandError(
            format!("Invalid status '{new_status}'. Valid: {}", valid.join(", "))
        ));
    }

    let board = ctx.state.scrum_board();
    let old   = board.update_item_status(&id, &new_status, ctx.user_id()).await?;

    Ok(Response {
        status: "ok".into(),
        text: format!("`{id}` → *{new_status}*"),
        actions: vec![Action::ScrumUpdate {
            item_id:    id,
            old_status: old,
            new_status,
        }],
        ..Default::default()
    })
}

async fn list(ctx: &Context, filter: Option<&str>) -> Result<Response> {
    let board  = ctx.state.scrum_board();
    let sprint = board.current_sprint().await?
        .ok_or_else(|| BotError::CommandError("No active sprint".into()))?;
    let items = board.list_items_filtered(&sprint.id, filter).await?;

    if items.is_empty() {
        return Ok(Response::text("No items match that filter."));
    }

    let lines: Vec<String> = items.iter()
        .take(15)
        .map(|i| format!("• `{}` {} [{}]", i.id, i.title, i.status))
        .collect();

    Ok(Response::text(lines.join("\n")))
}
```

### 2.3 Agent Handler (Rust)

```rust
// rust/src/commands/agent.rs
use crate::{
    error::{BotError, Result},
    types::{Action, Context, Response},
};

pub async fn handle(ctx: &Context) -> Result<Response> {
    let query = ctx.args().join(" ");
    if query.is_empty() {
        return Ok(Response::text("Usage: `/agent <your question>`"));
    }

    let ollama = ctx.state.ollama();
    if !ollama.health_check().await {
        return Err(BotError::LlmError(
            "Ollama is unavailable. Please try again later.".into()
        ));
    }

    let history = ctx.state.get_session(ctx.chat_id()).await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let start   = std::time::Instant::now();

    let result = ollama.generate(crate::integrations::GenerateRequest {
        model:   ctx.state.config().ollama_model.clone(),
        prompt:  query.clone(),
        context: history.clone(),
        options: Default::default(),
        stream:  false,
    }).await?;

    let latency_ms = start.elapsed().as_millis() as u64;

    // Update conversation history (keep last 20 turns = 40 entries).
    let mut new_history = history;
    new_history.push(crate::integrations::Turn { role: "user".into(),      content: query });
    new_history.push(crate::integrations::Turn { role: "assistant".into(), content: result.text.clone() });
    if new_history.len() > 40 {
        new_history.drain(0..new_history.len() - 40);
    }
    ctx.state.set_session(ctx.chat_id(), new_history).await;

    Ok(Response {
        status: "ok".into(),
        text:   result.text,
        actions: vec![Action::AgentInvoke {
            task_id:    task_id.clone(),
            model:      ctx.state.config().ollama_model.clone(),
            latency_ms,
        }],
        metadata: serde_json::json!({
            "agent_id":   "default",
            "task_id":    task_id,
            "latency_ms": latency_ms,
        }),
        ..Default::default()
    })
}
```

---

## 3. Haskell Examples

### 3.1 Main Entry Point

```haskell
-- haskell/app/Main.hs
{-# LANGUAGE OverloadedStrings #-}
module Main where

import Bot          (mkBot)
import Config       (loadConfig)
import State        (initialEnv)
import Control.Exception (SomeException, catch, displayException)
import System.Exit  (exitFailure)

main :: IO ()
main = do
  cfg <- loadConfig           -- reads .env / environment variables
  env <- initialEnv cfg       -- allocates TVars, opens SQLite connection
  bot <- mkBot env
  putStrLn "Telegram bot starting (long-polling)..."
  runBot bot `catch` \(e :: SomeException) -> do
    putStrLn $ "Fatal error: " <> displayException e
    exitFailure
```

### 3.2 Command Dispatcher

```haskell
-- haskell/src/Bot.hs
{-# LANGUAGE OverloadedStrings #-}
module Bot (mkBot, runBot) where

import Commands.Start   qualified as Start
import Commands.Help    qualified as Help
import Commands.Scrum   qualified as Scrum
import Commands.Issue   qualified as Issue
import Commands.Agent   qualified as Agent
import Commands.Status  qualified as Status
import State            (BotEnv(..))
import Types

import Data.Map.Strict  (Map)
import Data.Map.Strict  qualified as Map
import Data.Text        (Text)
import Data.Text        qualified as T
import Telegram.Bot.Simple

type Handler = Context -> IO BotResponse

commandHandlers :: Map Text Handler
commandHandlers = Map.fromList
  [ ("start",  Start.handle)
  , ("help",   Help.handle)
  , ("scrum",  Scrum.handle)
  , ("issue",  Issue.handle)
  , ("agent",  Agent.handle)
  , ("status", Status.handle)
  ]

mkBot :: BotEnv -> IO TelegramBot
mkBot env = do
  token <- pure (envConfig env).botToken
  pure $ TelegramBot
    { botToken    = token
    , botOnUpdate = handleUpdate env
    , botOnError  = logError
    }

handleUpdate :: BotEnv -> Update -> IO ()
handleUpdate env upd =
  case updateMessage upd >>= messageText of
    Nothing   -> pure ()
    Just text -> do
      let ctx  = mkContext upd env
          cmd  = parseCommand text
          args = parseArgs text
      resp <- dispatch ctx cmd args
      sendReply (ctxBot ctx) (ctxChatId ctx) resp

dispatch :: Context -> Maybe Text -> [Text] -> IO BotResponse
dispatch ctx Nothing    _    = pure $ unknownResponse ctx
dispatch ctx (Just cmd) args =
  case Map.lookup cmd commandHandlers of
    Just h  -> h ctx { ctxArgs = args }
    Nothing ->
      if envAgentFallback (ctxEnv ctx)
        then Agent.handle ctx { ctxArgs = args }
        else pure $ errorResponse 404 "Unknown command" "Use /help for available commands."

parseCommand :: Text -> Maybe Text
parseCommand t =
  case T.words t of
    (w:_) | T.isPrefixOf "/" w -> Just . T.toLower . T.drop 1 . T.takeWhile (/= '@') $ w
    _                          -> Nothing

parseArgs :: Text -> [Text]
parseArgs = drop 1 . T.words
```

### 3.3 Scrum Handler (Haskell)

```haskell
-- haskell/src/Commands/Scrum.hs
{-# LANGUAGE OverloadedStrings #-}
module Commands.Scrum (handle) where

import Control.Monad.Trans.Except (ExceptT(..), runExceptT, throwE)
import Data.Text                  (Text)
import Data.Text                  qualified as T
import Types
import State                      (BotEnv(..), ScrumBoard(..))

handle :: Context -> IO BotResponse
handle ctx = do
  result <- runExceptT $ dispatch ctx (ctxArgs ctx)
  pure $ case result of
    Right resp -> resp
    Left  err  -> fromBotError err

dispatch :: Context -> [Text] -> ExceptT BotError IO BotResponse
dispatch ctx args =
  case args of
    ("status":_)    -> scrumStatus  ctx
    ("create":rest) -> scrumCreate  ctx rest
    ("update":rest) -> scrumUpdate  ctx rest
    ("list"  :rest) -> scrumList    ctx rest
    []              -> pure $ helpResponse
    (unknown :_)    -> throwE $ CommandError $ "Unknown subcommand: " <> unknown

scrumStatus :: Context -> ExceptT BotError IO BotResponse
scrumStatus ctx = do
  let board = envScrumBoard (ctxEnv ctx)
  sprint <- ExceptT $ maybe (Left noSprintErr) Right
              <$> currentSprint board
  items  <- ExceptT $ Right <$> listItems board (sprintId sprint)
  let counts = countByStatus items
      text   = formatStatus sprint counts items
  pure BotResponse
    { responseStatus    = "ok"
    , responseText      = text
    , responseActions   = [ScrumQuery (sprintId sprint) (length items)]
    , responseParseMode = "Markdown"
    , responseMetadata  = mempty
    , responseErrorCode = Nothing
    , responseErrorDesc = Nothing
    }

scrumCreate :: Context -> [Text] -> ExceptT BotError IO BotResponse
scrumCreate ctx titleWords = do
  let title = T.unwords titleWords
  when (T.null title) $
    throwE $ CommandError "Title required: /scrum create <title>"
  let board = envScrumBoard (ctxEnv ctx)
  sprint <- ExceptT $ maybe (Left noSprintErr) Right
              <$> currentSprint board
  item   <- ExceptT $ Right <$> createItem board (sprintId sprint) title (ctxUserId ctx)
  pure BotResponse
    { responseStatus  = "ok"
    , responseText    = "Task created: `" <> itemId item <> "` — " <> itemTitle item
    , responseActions = [ScrumCreate (sprintId sprint) (itemId item) (itemTitle item)]
    , responseParseMode = "Markdown"
    , responseMetadata  = mempty
    , responseErrorCode = Nothing
    , responseErrorDesc = Nothing
    }

noSprintErr :: BotError
noSprintErr = CommandError "No active sprint. Use `/scrum sprint new <name>`."

helpResponse :: BotResponse
helpResponse = BotResponse
  { responseStatus    = "ok"
  , responseText      = "Usage: `/scrum <status|create|update|list|assign|sprint>`"
  , responseActions   = []
  , responseParseMode = "Markdown"
  , responseMetadata  = mempty
  , responseErrorCode = Nothing
  , responseErrorDesc = Nothing
  }

formatStatus :: Sprint -> CountByStatus -> [ScrumItem] -> Text
formatStatus sprint counts items = T.unlines $
  [ "*Sprint:* " <> sprintName sprint
  , "Todo: " <> tshow (cTodo counts)
    <> " | In Progress: " <> tshow (cWip counts)
    <> " | Done: " <> tshow (cDone counts)
    <> " | Blocked: " <> tshow (cBlocked counts)
  , ""
  , "*Recent:*"
  ] ++
  map (\i -> "• `" <> itemId i <> "` " <> itemTitle i <> " [" <> itemStatus i <> "]")
      (take 5 items)

tshow :: Show a => a -> Text
tshow = T.pack . show
```

### 3.4 STM Session Store (Haskell)

```haskell
-- haskell/src/State.hs
{-# LANGUAGE OverloadedStrings #-}
module State
  ( BotEnv(..)
  , Session(..)
  , Turn(..)
  , initialEnv
  , getSession
  , putSession
  ) where

import Config         (Config(..))
import Control.Concurrent.STM
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Sequence   (Seq)
import Data.Sequence   qualified as Seq
import Data.Text       (Text)

data Turn = Turn
  { turnRole    :: !Text    -- "user" or "assistant"
  , turnContent :: !Text
  } deriving (Show)

newtype Session = Session { sessionHistory :: Seq Turn }

data BotEnv = BotEnv
  { envSessions   :: TVar (Map Int64 Session)
  , envConfig     :: Config
  , envScrumBoard :: ScrumBoard
  , envOllama     :: OllamaClient
  , envAgentFallback :: Bool
  }

initialEnv :: Config -> IO BotEnv
initialEnv cfg = do
  sessions <- newTVarIO Map.empty
  board    <- openScrumBoard (cfgDatabaseUrl cfg)
  ollama   <- newOllamaClient (cfgOllamaUrl cfg) (cfgOllamaModel cfg)
  pure BotEnv
    { envSessions      = sessions
    , envConfig        = cfg
    , envScrumBoard    = board
    , envOllama        = ollama
    , envAgentFallback = cfgAgentFallback cfg
    }

getSession :: BotEnv -> Int64 -> STM Session
getSession env chatId = do
  m <- readTVar (envSessions env)
  pure $ Map.findWithDefault (Session Seq.empty) chatId m

putSession :: BotEnv -> Int64 -> Session -> STM ()
putSession env chatId sess =
  modifyTVar' (envSessions env) (Map.insert chatId sess)
```

---

## 4. Cross-Language Pattern: Shared SQLite State

When running multiple bots simultaneously (e.g. for A/B testing) they can
share the same SQLite file. All writes go through WAL mode so readers are
never blocked.

```
bot-node  ─┐
bot-rust  ─┼──► /data/sqlite/bot.db (WAL mode)
bot-haskell┘
```

Schema migrations must be idempotent (`CREATE TABLE IF NOT EXISTS`) because
any of the three bots might run them on startup.

Example shared migration:

```sql
-- schema/001_initial.sql
PRAGMA journal_mode=WAL;

CREATE TABLE IF NOT EXISTS sprints (
    id       TEXT PRIMARY KEY,
    name     TEXT NOT NULL,
    status   TEXT NOT NULL DEFAULT 'active',
    created  TEXT NOT NULL DEFAULT (datetime('now')),
    closed   TEXT
);

CREATE TABLE IF NOT EXISTS scrum_items (
    id        TEXT PRIMARY KEY,
    sprint_id TEXT NOT NULL REFERENCES sprints(id) ON DELETE CASCADE,
    title     TEXT NOT NULL,
    status    TEXT NOT NULL DEFAULT 'todo'
                CHECK(status IN ('todo','in-progress','done','blocked')),
    assignee  INTEGER,
    created   TEXT NOT NULL DEFAULT (datetime('now')),
    updated   TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS issues (
    id          TEXT PRIMARY KEY,
    description TEXT NOT NULL,
    priority    TEXT NOT NULL DEFAULT 'medium'
                    CHECK(priority IN ('critical','high','medium','low')),
    status      TEXT NOT NULL DEFAULT 'open'
                    CHECK(status IN ('open','closed','wontfix')),
    reporter    INTEGER NOT NULL,
    assignee    INTEGER,
    created     TEXT NOT NULL DEFAULT (datetime('now')),
    updated     TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS agent_tasks (
    id           TEXT PRIMARY KEY,
    chat_id      INTEGER NOT NULL,
    user_id      INTEGER NOT NULL,
    prompt       TEXT NOT NULL,
    model        TEXT NOT NULL,
    status       TEXT NOT NULL DEFAULT 'pending'
                     CHECK(status IN ('pending','running','complete','failed','cancelled')),
    result_text  TEXT,
    latency_ms   INTEGER,
    created      TEXT NOT NULL DEFAULT (datetime('now')),
    completed    TEXT
);
```

---

## 5. Testing Examples

### 5.1 Running the Integration Tests

```bash
cd telegram-bot-sdk
python -m pytest tests/integration_test.py -v
```

Expected output:

```
tests/integration_test.py::TestMessageFormatCompatibility::test_update_json_structure PASSED
tests/integration_test.py::TestMessageFormatCompatibility::test_user_fields_are_present PASSED
...
tests/integration_test.py::TestMockTelegramAPIServer::test_server_returns_ok_true PASSED
...
40 passed in 0.42s
```

### 5.2 Rust Unit Tests

```bash
cd rust
cargo test -- --nocapture
```

### 5.3 Haskell Tests

```bash
cd haskell
stack test --test-arguments "--color=always"
```

### 5.4 Node.js Tests

```bash
cd node
npm test
```

### 5.5 Mock Telegram API in Tests

Use the `MockTelegramAPI` class from `tests/integration_test.py` to record
what `sendMessage` calls each bot makes:

```python
from tests.integration_test import MockTelegramAPI, BOT_TOKEN
import urllib.request, json

api = MockTelegramAPI(port=19443)
api.start()

# Point your bot at the mock: TELEGRAM_BOT_TOKEN=TEST ... TELEGRAM_API_URL=http://127.0.0.1:19443
# ... trigger a command ...

calls = api.get_calls_for_method("sendMessage")
assert len(calls) == 1
assert "Sprint" in calls[0]["payload"]["text"]

api.stop()
```
