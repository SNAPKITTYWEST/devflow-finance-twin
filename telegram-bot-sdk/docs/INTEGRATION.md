# Telegram Bot SDK — Integration Guide

**License:** GPL-3.0-or-later OR Apache-2.0

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Scrum Board Setup](#2-scrum-board-setup)
3. [Issue Tracker Configuration](#3-issue-tracker-configuration)
4. [Ollama Configuration](#4-ollama-configuration)
5. [SQLite Setup](#5-sqlite-setup)
6. [Environment Variables Reference](#6-environment-variables-reference)
7. [Docker Compose Deployment](#7-docker-compose-deployment)
8. [Health Checks and Monitoring](#8-health-checks-and-monitoring)
9. [Extending with Custom Integrations](#9-extending-with-custom-integrations)

---

## 1. Prerequisites

| Dependency | Minimum Version | Purpose |
|------------|-----------------|---------|
| Telegram bot token | — | Obtain from [@BotFather](https://t.me/BotFather) |
| Docker Engine | 24.0 | Container orchestration |
| Docker Compose | 2.20 | Multi-service orchestration |
| Ollama | 0.1.30 | Local LLM inference |
| SQLite | 3.39 | Persistent state storage |

For source builds without Docker:

| Runtime | Minimum Version |
|---------|-----------------|
| Node.js | 20 LTS |
| npm | 10 |
| Rust | 1.85 (stable) |
| GHC | 9.6 |
| Stack | 2.13 |

---

## 2. Scrum Board Setup

### 2.1 Initialise the Database

All three bots share the same SQLite database. Run the migration once before
starting any bot:

```bash
# Using the Node.js bot's built-in migration script
cd node
npm run db:migrate

# Or apply the schema directly
sqlite3 /data/sqlite/bot.db < ../schema/scrum.sql
```

The schema creates:
- `sprints` — sprint records
- `scrum_items` — stories, tasks, bugs
- `item_comments` — threaded comments
- `sprint_members` — team member registry

### 2.2 Create the First Sprint

Once a bot is running, open a Telegram chat with it:

```
/scrum sprint new "Sprint 1 — Foundations"
```

The bot responds:

```
Sprint created: S-1 "Sprint 1 — Foundations"
Status: active
Start: 2026-09-21
```

### 2.3 Add Team Members

```
/scrum member add @alice
/scrum member add @bob
/scrum member list
```

### 2.4 Common Scrum Workflow

```
# Create stories
/scrum create "User can authenticate via OAuth"
/scrum create "Dashboard renders finance chart"

# Assign and progress
/scrum assign T-1 @alice
/scrum update T-1 in-progress

# Daily standup summary
/scrum status

# Close sprint at end of iteration
/scrum sprint close
```

### 2.5 External Scrum Board (Optional)

If your team uses Jira, Linear, or GitHub Projects, set the
`SCRUM_BOARD_BACKEND` environment variable:

```env
SCRUM_BOARD_BACKEND=jira
JIRA_BASE_URL=https://your-org.atlassian.net
JIRA_EMAIL=bot@your-org.com
JIRA_API_TOKEN=<token>
JIRA_PROJECT_KEY=DFT
```

Supported backends: `sqlite` (default), `jira`, `linear`, `github`.

---

## 3. Issue Tracker Configuration

### 3.1 SQLite-Backed Issue Tracker (Default)

No extra configuration needed. Issues are stored in the same SQLite database
as scrum items.

```
/issue log "Login button not responding on mobile Safari"
/issue list
/issue list critical
/issue close I-1
```

### 3.2 Linking Issues to Scrum Items

```
/issue link I-3 T-7
```

Creates a bidirectional reference. The scrum board shows linked issues; the
issue detail shows the blocking story.

### 3.3 Priority Levels

| Priority | Meaning | SLA |
|----------|---------|-----|
| `critical` | Production down | 1 hour |
| `high` | Major feature broken | 4 hours |
| `medium` | Non-blocking degradation | 1 business day |
| `low` | Nice-to-fix / cosmetic | Next sprint |

Priority is set at creation time:

```
/issue log --priority high "Payment form rejects valid cards"
```

Default priority is `medium`.

### 3.4 GitHub Issues Integration (Optional)

```env
ISSUE_BACKEND=github
GITHUB_TOKEN=ghp_...
GITHUB_OWNER=SNAPKITTYWEST
GITHUB_REPO=devflow-finance-twin
```

With this backend, `/issue log` creates a real GitHub issue and `/issue close`
closes it via the API.

---

## 4. Ollama Configuration

### 4.1 Installing Ollama

```bash
# macOS / Linux
curl -fsSL https://ollama.ai/install.sh | sh

# Pull a model
ollama pull llama2
# or for a smaller footprint:
ollama pull llama2:7b
# or for better coding tasks:
ollama pull codellama
```

### 4.2 Connecting the Bots to Ollama

Set these environment variables (`.env` file or Docker Compose):

```env
OLLAMA_API_URL=http://localhost:11434
OLLAMA_MODEL=llama2
OLLAMA_TIMEOUT_SECS=60
OLLAMA_MAX_CONCURRENT=4
```

When running via Docker Compose, the Ollama container is accessible at
`http://ollama:11434` inside the `bot_net` network (this is already set as the
default in `docker-compose.yml`).

### 4.3 Choosing a Model

| Model | Size | Best for | Notes |
|-------|------|----------|-------|
| `llama2` | 3.8 GB | General queries | Good balance of speed and quality |
| `llama2:7b` | 3.8 GB | Same as above | Explicit 7B tag |
| `llama2:13b` | 7.3 GB | Better reasoning | Slower, needs more VRAM |
| `codellama` | 3.8 GB | Code questions | Tuned for code tasks |
| `mistral` | 4.1 GB | Instructions | Good instruction following |
| `phi` | 1.6 GB | Low-resource | Fast, lower quality |

### 4.4 GPU Acceleration

Uncomment the `deploy.resources` block in `docker-compose.yml` to enable
NVIDIA GPU pass-through for Ollama:

```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          capabilities: [gpu]
```

Requires `nvidia-container-toolkit` installed on the host.

### 4.5 Ollama Health Check

The bots probe Ollama on startup and every 30 seconds thereafter. The health
check result is visible via:

```
/status
```

Sample output:

```
Bot status: operational
Ollama: reachable (model: llama2, latency: 42ms)
Database: connected (bot.db, 1.2 MB)
Active agent tasks: 0
Uptime: 3h 22m
```

### 4.6 Disabling Ollama

If you do not need LLM features, set:

```env
AGENT_ENABLED=false
```

The `/agent` command will return a friendly message instead of error 503.

---

## 5. SQLite Setup

### 5.1 Database Location

By default, the database is stored at `/data/sqlite/bot.db`. In Docker Compose
this path is inside the `sqlite_data` named volume, shared by all three bots.

Override the path:

```env
DATABASE_URL=sqlite:///path/to/custom/bot.db
```

### 5.2 WAL Mode

All bots open SQLite in WAL (Write-Ahead Logging) mode for concurrent read
performance. This is set automatically on first connection.

### 5.3 Backup

```bash
# Live backup (safe while bots are running)
sqlite3 /data/sqlite/bot.db ".backup /backup/bot-$(date +%Y%m%d).db"

# Or use the built-in VACUUM INTO
sqlite3 /data/sqlite/bot.db "VACUUM INTO '/backup/bot-$(date +%Y%m%d).db'"
```

Schedule this via cron or a Compose healthcheck sidecar.

---

## 6. Environment Variables Reference

Copy `.env.example` from the SDK root and fill in your values:

```env
# ── Required ──────────────────────────────────────────────────────────────
TELEGRAM_BOT_TOKEN=<your BotFather token>

# ── Optional — defaults shown ─────────────────────────────────────────────
LOG_LEVEL=info                          # trace | debug | info | warn | error
DATABASE_URL=sqlite:///data/sqlite/bot.db

OLLAMA_API_URL=http://ollama:11434
OLLAMA_MODEL=llama2
OLLAMA_TIMEOUT_SECS=60
OLLAMA_MAX_CONCURRENT=4

AGENT_ENABLED=true
AGENT_CONTEXT_WINDOW=20                 # turns to keep per conversation

ALLOWED_CHAT_IDS=                       # comma-separated; empty = allow all
SCRUM_BOARD_BACKEND=sqlite              # sqlite | jira | linear | github
ISSUE_BACKEND=sqlite                    # sqlite | github

# ── Rust-specific ─────────────────────────────────────────────────────────
RUST_LOG=telegram_bot_sdk=info,reqwest=warn

# ── Node.js-specific ──────────────────────────────────────────────────────
NODE_ENV=production
PORT=3000

# ── Haskell-specific ──────────────────────────────────────────────────────
GHC_RTS_FLAGS="-N4 -H256m"             # green threads = 4, initial heap 256 MB
```

---

## 7. Docker Compose Deployment

### 7.1 Quick Start (all three bots)

```bash
cd telegram-bot-sdk
cp ../.env.example ../.env
# Edit ../.env with your TELEGRAM_BOT_TOKEN

docker compose -f docker/docker-compose.yml up --build
```

### 7.2 Single-Bot Mode

```bash
# Start only the Rust bot + Ollama
docker compose -f docker/docker-compose.yml up bot-rust ollama
```

### 7.3 With Admin UI

```bash
docker compose -f docker/docker-compose.yml --profile with-admin up
```

Exposes sqlite-web at `http://localhost:18080`.

### 7.4 Production Deployment Checklist

- [ ] `TELEGRAM_BOT_TOKEN` stored in a Docker secret, not a plain env var
- [ ] SQLite volume backed up off-host daily
- [ ] Ollama model pre-pulled before starting (`docker exec ollama ollama pull llama2`)
- [ ] `ALLOWED_CHAT_IDS` set to limit access to your team's chats
- [ ] Log rotation configured (`max-size`, `max-file` in compose file)
- [ ] Health checks passing for all three bots before routing traffic
- [ ] Container images tagged with a version (`IMAGE_TAG=0.1.0`)

---

## 8. Health Checks and Monitoring

### 8.1 HTTP Health Endpoint

Each bot exposes `GET /healthz` on its `PORT`. Response:

```json
{
  "status": "ok",
  "version": "0.1.0",
  "uptime_seconds": 12345,
  "ollama": "reachable",
  "database": "connected"
}
```

Returns HTTP 200 when healthy, 503 when degraded.

### 8.2 Prometheus Metrics

Enable with `METRICS_ENABLED=true`. Exposed at `/metrics` (Prometheus text
format):

```
bot_messages_total{command="/scrum",status="ok"} 142
bot_messages_total{command="/agent",status="ok"} 38
bot_messages_total{command="unknown",status="error"} 7
bot_agent_latency_seconds_bucket{le="1.0"} 25
bot_agent_latency_seconds_bucket{le="5.0"} 38
bot_ollama_up 1
bot_db_connections_active 2
```

### 8.3 Log Format

All bots emit structured JSON logs (one object per line):

```json
{
  "timestamp": "2026-09-21T12:00:00.123Z",
  "level": "info",
  "service": "bot-rust",
  "chat_id": -1001234567890,
  "user_id": 100200300,
  "command": "/scrum",
  "latency_ms": 8,
  "message": "command handled successfully"
}
```

---

## 9. Extending with Custom Integrations

### 9.1 Adding a New Command (Node.js)

Create `node/src/commands/mycommand.mjs`:

```javascript
export async function handleMyCommand(ctx) {
  const args = ctx.message.text.split(' ').slice(1);
  // ... business logic ...
  return {
    status: 'ok',
    text: `Result: ${args.join(' ')}`,
    parseMode: 'Markdown',
    actions: [{ type: 'my_command_executed', args }],
    metadata: { handler: 'mycommand' },
  };
}
```

Register it in `node/src/bot.mjs`:

```javascript
import { handleMyCommand } from './commands/mycommand.mjs';
bot.command('mycommand', handleMyCommand);
```

### 9.2 Adding a New Command (Rust)

```rust
// src/commands/my_command.rs
use crate::{error::Result, types::{Context, Response, Action}};

pub async fn handle(ctx: &Context) -> Result<Response> {
    let args: Vec<&str> = ctx.args();
    Ok(Response {
        status: "ok".into(),
        text: format!("Result: {}", args.join(" ")),
        parse_mode: "Markdown".into(),
        actions: vec![Action::custom("my_command_executed")],
        metadata: serde_json::json!({ "handler": "my_command" }),
        ..Default::default()
    })
}
```

Register in `src/bot.rs`:

```rust
dispatcher.add_command("mycommand", commands::my_command::handle);
```

### 9.3 Adding a New Command (Haskell)

```haskell
-- src/Commands/MyCommand.hs
module Commands.MyCommand (handle) where

import Types (Context(..), BotResponse(..), Action(..))

handle :: Context -> IO BotResponse
handle ctx = do
  let args = ctxArgs ctx
  pure BotResponse
    { responseStatus    = "ok"
    , responseText      = "Result: " <> unwords args
    , responseParseMode = "Markdown"
    , responseActions   = [CustomAction "my_command_executed" mempty]
    , responseMetadata  = object ["handler" .= ("my_command" :: Text)]
    , responseErrorCode = Nothing
    , responseErrorDesc = Nothing
    }
```

Register in `src/Bot.hs`:

```haskell
commandHandlers :: Map Text Handler
commandHandlers = fromList
  [ ("mycommand", Commands.MyCommand.handle)
  , ...existing handlers...
  ]
```
