# Telegram Bot SDK — API Reference

**License:** GPL-3.0-or-later OR Apache-2.0

---

## Table of Contents

1. [Command Reference](#1-command-reference)
2. [Message Format Specification](#2-message-format-specification)
3. [Agent Protocol](#3-agent-protocol)
4. [Error Codes](#4-error-codes)
5. [Webhook vs Long-Polling](#5-webhook-vs-long-polling)
6. [Rate Limits](#6-rate-limits)

---

## 1. Command Reference

All commands begin with `/` and are case-insensitive. Arguments are
whitespace-separated. The SDK parses arguments identically across Node.js,
Rust, and Haskell.

### Core Commands

| Command | Arguments | Description |
|---------|-----------|-------------|
| `/start` | — | Initialise the bot session; shows a welcome message |
| `/help` | `[command]` | List all commands or get help for a specific command |
| `/status` | — | Report current bot health and uptime |
| `/ping` | — | Liveness check; responds with `pong` |

### Scrum Board Commands

| Command | Arguments | Description |
|---------|-----------|-------------|
| `/scrum` | `status` | Show the current sprint board |
| `/scrum` | `create <title>` | Create a new story/task |
| `/scrum` | `update <id> <status>` | Move an item to `todo\|in-progress\|done\|blocked` |
| `/scrum` | `list [status]` | List items, optionally filtered by status |
| `/scrum` | `assign <id> <@user>` | Assign an item to a team member |
| `/scrum` | `sprint new <name>` | Open a new sprint |
| `/scrum` | `sprint close` | Close the current sprint and produce a summary |

### Issue Tracker Commands

| Command | Arguments | Description |
|---------|-----------|-------------|
| `/issue` | `log <description>` | Create a new issue |
| `/issue` | `list [priority]` | List open issues; priority is `critical\|high\|medium\|low` |
| `/issue` | `close <id>` | Mark an issue as resolved |
| `/issue` | `assign <id> <@user>` | Assign responsibility |
| `/issue` | `label <id> <label>` | Add a label to an issue |
| `/issue` | `comment <id> <text>` | Append a comment |

### Agent Commands

| Command | Arguments | Description |
|---------|-----------|-------------|
| `/agent` | `query <text>` | Send a natural-language query to the agent |
| `/agent` | `status` | Show active agent tasks |
| `/agent` | `cancel <task-id>` | Cancel a running agent task |
| `/agent` | `history [n]` | Show the last `n` (default 10) agent interactions |
| `/agent` | `config set <key> <val>` | Update a runtime agent configuration key |

---

## 2. Message Format Specification

### 2.1 Telegram Update Wire Format

The SDK accepts standard Telegram Bot API Update objects. Only `message` and
`callback_query` update types are processed; all others are silently ignored.

```json
{
  "update_id": 1000000001,
  "message": {
    "message_id": 42,
    "from": {
      "id": 100200300,
      "first_name": "Alice",
      "last_name": "Dev",
      "username": "alice_dev",
      "is_bot": false,
      "language_code": "en"
    },
    "chat": {
      "id": -1001234567890,
      "type": "group",
      "title": "DevFlow Team"
    },
    "text": "/scrum status",
    "date": 1756735200,
    "entities": [
      { "offset": 0, "length": 6, "type": "bot_command" }
    ]
  }
}
```

**Required fields**: `update_id`, `message.message_id`, `message.from.id`,
`message.chat.id`, `message.text`, `message.date`.

### 2.2 Bot Response Format

Every handler returns a `Response` struct/record/object serialised to JSON
before being forwarded to the Telegram API as `sendMessage`.

```json
{
  "status": "ok",
  "text": "Sprint S-42 has 7 open stories.",
  "parse_mode": "Markdown",
  "actions": [
    {
      "type": "scrum_query",
      "sprint_id": "S-42",
      "item_count": 7
    }
  ],
  "metadata": {
    "latency_ms": 12,
    "handler": "scrum::status",
    "version": "0.1.0"
  }
}
```

**Field definitions**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `status` | `"ok" \| "error"` | yes | Outcome of the command |
| `text` | string | yes | User-visible reply text (Markdown-safe) |
| `parse_mode` | `"Markdown" \| "MarkdownV2" \| "HTML"` | no | Telegram parse mode (default `"Markdown"`) |
| `actions` | `Action[]` | no | Side-effects performed by the handler |
| `metadata` | `object` | no | Diagnostic / instrumentation payload |
| `error_code` | integer | error only | Numeric error code (see §4) |
| `error_description` | string | error only | Human-readable error detail |

### 2.3 Action Objects

Actions communicate what state was mutated. They are included in the response
for auditability and testing; they do not affect the user-facing message.

```json
{
  "type": "scrum_update",
  "sprint_id": "S-42",
  "item_id": "T-99",
  "old_status": "in-progress",
  "new_status": "done",
  "actor_id": 100200300,
  "timestamp": "2026-09-21T12:00:00Z"
}
```

**Common action types**:

| `type` | Produced by | Key fields |
|--------|-------------|------------|
| `scrum_create` | `/scrum create` | `sprint_id`, `item_id`, `title` |
| `scrum_update` | `/scrum update` | `item_id`, `old_status`, `new_status` |
| `scrum_assign` | `/scrum assign` | `item_id`, `assignee_id` |
| `issue_create` | `/issue log` | `issue_id`, `priority` |
| `issue_close` | `/issue close` | `issue_id`, `resolution` |
| `agent_invoke` | `/agent query` | `task_id`, `model`, `latency_ms` |
| `agent_cancel` | `/agent cancel` | `task_id` |

### 2.4 Agent Invocation Payload

When `/agent query` is called, the SDK constructs this payload before
forwarding to Ollama:

```json
{
  "model": "llama2",
  "prompt": "User query text here",
  "context": {
    "user_id": 100200300,
    "chat_id": -1001234567890,
    "conversation_history": [
      { "role": "user", "content": "previous message" },
      { "role": "assistant", "content": "previous reply" }
    ]
  },
  "options": {
    "temperature": 0.7,
    "top_p": 0.9,
    "num_predict": 512
  },
  "stream": false
}
```

---

## 3. Agent Protocol

The Agent Protocol defines how the SDK coordinates multi-turn conversations
and delegates to the Ollama LLM backend.

### 3.1 Task Lifecycle

```
 User sends /agent query
       │
       ▼
 SDK creates AgentTask { id, status: Pending, prompt, context }
       │
       ▼
 AgentTask enqueued ──► Ollama HTTP POST /api/generate
       │
       ▼
 Response received ──► AgentTask { status: Complete, result }
       │
       ▼
 Bot sends reply to user
```

States: `Pending` → `Running` → `Complete | Failed | Cancelled`

### 3.2 Context Preservation

The SDK maintains a per-user, per-chat conversation window (default 20 turns).
Each turn is a `{ role: "user" | "assistant", content: string }` pair.
The window is stored:

- **Node.js**: in-memory `Map<chatId, Turn[]>` with optional file-backed JSON
- **Rust**: `Arc<RwLock<HashMap<ChatId, VecDeque<Turn>>>>`
- **Haskell**: `TVar (Map ChatId (Seq Turn))` via STM

### 3.3 Fallback Behaviour

If Ollama is unreachable the bot responds with error code `503` and does not
retry within the same request. A background health-check probes Ollama every
30 seconds; once the service recovers the bot resumes accepting `/agent` calls.

### 3.4 AgentTask JSON Schema

```json
{
  "task_id": "01J8XYZABCD",
  "status": "complete",
  "prompt": "What is our current burn rate?",
  "model": "llama2",
  "created_at": "2026-09-21T12:00:00Z",
  "completed_at": "2026-09-21T12:00:02.341Z",
  "latency_ms": 2341,
  "result": {
    "text": "Based on the scrum board, the current sprint burn rate is ...",
    "tokens_used": 128
  }
}
```

---

## 4. Error Codes

All error responses carry a numeric `error_code` and a string
`error_description`. The `text` field always contains a safe, user-facing
message that does not leak internal details.

| Code | Constant | Meaning |
|------|----------|---------|
| 400 | `BAD_REQUEST` | Malformed command syntax or missing required argument |
| 401 | `UNAUTHORISED` | Bot token invalid or revoked |
| 403 | `FORBIDDEN` | User lacks permission to execute this command in this chat |
| 404 | `NOT_FOUND` | Command, item, or resource does not exist |
| 409 | `CONFLICT` | Operation conflicts with current state (e.g. duplicate create) |
| 422 | `UNPROCESSABLE` | Arguments are structurally valid but semantically wrong |
| 429 | `RATE_LIMITED` | Telegram API or Ollama rate limit exceeded |
| 500 | `INTERNAL_ERROR` | Unexpected bot-side error (logged server-side) |
| 503 | `SERVICE_UNAVAILABLE` | Downstream service (Ollama / scrum board) unreachable |

### Error Response Example

```json
{
  "status": "error",
  "text": "Item T-99 not found. Use /scrum list to see available items.",
  "parse_mode": "Markdown",
  "error_code": 404,
  "error_description": "ScrumItem T-99 does not exist in sprint S-42"
}
```

---

## 5. Webhook vs Long-Polling

The SDK supports both Telegram update delivery modes.

### Long-Polling (default)

Enabled by default. No external URL required. The bot calls
`getUpdates` with a 30-second timeout and processes each batch sequentially.

```env
TELEGRAM_UPDATE_MODE=polling   # default
TELEGRAM_POLL_TIMEOUT=30
TELEGRAM_POLL_LIMIT=100
```

### Webhook Mode

Requires a publicly reachable HTTPS URL. Set via environment:

```env
TELEGRAM_UPDATE_MODE=webhook
TELEGRAM_WEBHOOK_URL=https://bots.example.com/webhook/mybot
TELEGRAM_WEBHOOK_SECRET=<random 256-bit hex>
```

The SDK registers the webhook automatically on startup via `setWebhook` and
verifies the `X-Telegram-Bot-Api-Secret-Token` header on every incoming request.

---

## 6. Rate Limits

The SDK enforces per-chat rate limiting to comply with Telegram's API limits
and to prevent abuse.

| Limit | Value | Scope |
|-------|-------|-------|
| Messages per second | 30 | Global (all chats combined) |
| Messages per minute per chat | 20 | Per chat |
| `/agent query` per hour per user | 30 | Per user |
| `/scrum` mutations per minute | 10 | Per chat |
| Ollama concurrent requests | 4 | Global |

When a rate limit is hit the bot queues the response and delivers it after the
applicable window expires, rather than dropping the message.
