# Telegram Bot SDK — Architecture

**License:** GPL-3.0-or-later OR Apache-2.0

---

## Table of Contents

1. [Multi-Language Protocol](#1-multi-language-protocol)
2. [State Management](#2-state-management)
3. [Concurrency Models](#3-concurrency-models)
4. [Command Routing Pipeline](#4-command-routing-pipeline)
5. [Error Handling Strategy](#5-error-handling-strategy)
6. [Integration Layer](#6-integration-layer)
7. [Security Model](#7-security-model)

---

## 1. Multi-Language Protocol

### 1.1 Canonical Data Types

All three implementations are required to produce and consume identical JSON
shapes. The canonical types are specified in [API.md](API.md). Each language
maps them as follows:

| Concept | Node.js | Rust | Haskell |
|---------|---------|------|---------|
| Update | `TelegramUpdate` interface | `teloxide::types::Update` | `Update` from `telegram-bot-simple` |
| Response | `BotResponse` interface | `Response` struct | `BotResponse` record |
| Error | `BotError` class | `BotError` enum (`thiserror`) | `BotError` ADT |
| Action | `Action` interface | `Action` enum | `Action` sum type |
| Metadata | `Record<string,unknown>` | `HashMap<String,Value>` | `Map Text Value` |

### 1.2 JSON Serialisation Conventions

To ensure that the Python integration tests (and any future cross-language
consumer) can parse responses from all three bots without branching:

- **Field names**: Node.js and Haskell use `camelCase`; Rust uses `snake_case`.
  The integration tests normalise these via `ResponseNormaliser`.
- **Dates**: Always ISO-8601 strings in UTC (`2026-09-21T12:00:00Z`).
- **IDs**: Always JSON strings, never bare integers (avoids JavaScript
  64-bit integer precision loss).
- **Enum variants**: lowercase snake_case strings (`"in_progress"`, not
  `"InProgress"` or `"IN_PROGRESS"`).

### 1.3 Protocol Versioning

A `version` field in `metadata` carries the SDK version string (semver). If a
future version introduces a breaking change to the response schema, the version
field allows consumers to adapt.

```json
{ "metadata": { "version": "0.1.0", "handler": "scrum::status" } }
```

---

## 2. State Management

Each implementation stores three categories of state:

| Category | Lifetime | Description |
|----------|----------|-------------|
| **Session** | Per user/chat, in-memory | Conversation history for agent context window |
| **Board** | Persistent (SQLite) | Scrum items, issues, sprint metadata |
| **Config** | Process lifetime | Bot token, Ollama URL, feature flags |

### 2.1 Node.js State

```
┌──────────────────────────────────────────────┐
│  Bot process                                  │
│                                               │
│  sessionStore: Map<ChatId, Session>           │
│    └─ conversation history (in-memory)        │
│                                               │
│  persistence.mjs                             │
│    └─ SQLite via better-sqlite3               │
│         ├─ scrum_items table                  │
│         ├─ issues table                       │
│         └─ agent_tasks table                  │
└──────────────────────────────────────────────┘
```

State is not replicated; a single process owns it. For multi-instance
deployments, promote SQLite to PostgreSQL and move session state to Redis.

### 2.2 Rust State

```rust
/// Shared application state, cloned (Arc) into every update handler.
pub struct BotState {
    pub sessions:   Arc<RwLock<HashMap<ChatId, Session>>>,
    pub db:         Arc<SqlitePool>,
    pub ollama:     Arc<OllamaClient>,
    pub config:     Arc<Config>,
    pub agent_tasks: Arc<Mutex<HashMap<TaskId, AgentTask>>>,
}
```

`Arc<RwLock<_>>` is used for the session map (many concurrent readers, rare
writes). The database pool (`sqlx::SqlitePool`) handles its own connection-level
locking. `parking_lot::Mutex` is preferred over `std::sync::Mutex` for its
smaller overhead and poison-free semantics.

### 2.3 Haskell State

```haskell
data BotEnv = BotEnv
  { envSessions   :: TVar (Map ChatId Session)
  , envDb         :: Connection          -- single SQLite connection + WAL
  , envOllama     :: OllamaClient
  , envConfig     :: Config
  , envAgentTasks :: TVar (Map TaskId AgentTask)
  }
```

`TVar` from `Control.Concurrent.STM` provides composable, lock-free state
mutations. All handlers run in `ReaderT BotEnv IO`, threading the environment
implicitly via `ask`.

---

## 3. Concurrency Models

### 3.1 Node.js — Event Loop + async/await

Node.js processes one event at a time on the V8 event loop. All I/O is
non-blocking. The Telegraf framework dispatches updates serially in the order
they arrive from `getUpdates`, but each update handler is an async function so
I/O (Ollama, SQLite) does not block other handlers.

```
getUpdates polling
      │
      ▼
Telegraf middleware chain (sequential per update)
      │
      ├─► /start handler (sync, instant)
      ├─► /scrum handler (async, SQLite read)
      └─► /agent handler (async, Ollama HTTP)
```

**Backpressure**: if the event loop is saturated, `getUpdates` batches pile
up. The long-poll timeout (30 s) provides natural pacing.

### 3.2 Rust — Tokio async runtime

The Rust bot uses `tokio` with a multi-threaded executor (`tokio::main` macro
defaults to a thread pool sized to the number of CPU cores). Each update is
spawned as an independent `tokio::task`, so updates are processed concurrently.

```
getUpdates long-poll (tokio::spawn)
      │
      └─► per-update task (tokio::spawn)
            ├─ command parse (sync, zero-cost)
            ├─ state lock (RwLock, non-blocking)
            ├─ SQLite query (sqlx async)
            └─ Ollama request (reqwest async)
```

Concurrent state access is safe because `Arc<RwLock<_>>` allows many
simultaneous readers and serialises writers. The SQLite pool allows up to
`SQLITE_MAX_CONNECTIONS` (default 5) concurrent queries.

### 3.3 Haskell — GHC green threads + STM

GHC's runtime multiplexes lightweight green threads across OS threads (via
`+RTS -N`). The telegram-bot-simple framework forks a green thread per update.

```
getUpdates loop (green thread)
      │
      └─► forkIO per update
            ├─ command parse (pure, lazy)
            ├─ STM transaction (atomically)
            ├─ SQLite query (sqlite-simple)
            └─ Ollama HTTP (http-client)
```

STM transactions compose: a handler can read the session map and write an
agent task atomically without holding any locks manually. If two threads
contend, STM retries the transaction automatically.

### 3.4 Concurrency Comparison

| Property | Node.js | Rust | Haskell |
|----------|---------|------|---------|
| Unit of concurrency | Micro-task / Promise | `tokio::Task` | Green thread |
| Parallelism | Single-threaded (GIL-free) | Multi-core | Multi-core (`-N`) |
| Shared state primitive | Closure over `Map` | `Arc<RwLock<T>>` | `TVar<T>` (STM) |
| Blocking I/O | Non-blocking by default | `tokio::spawn_blocking` | `forkIO` + async |
| Deadlock risk | Low (no explicit locks) | Low (lock ordering) | None (STM retries) |

---

## 4. Command Routing Pipeline

All three implementations share the same logical pipeline:

```
Incoming Update
      │
      ▼
1. Parse & validate Update JSON
      │
      ▼
2. Authenticate sender (chat_id allowlist / role check)
      │
      ▼
3. Extract command token and arguments
      │
      ▼
4. Rate-limit check (per-user, per-chat)
      │
      ▼
5. Dispatch to command handler
      │
      ├─ Known command → handler(ctx) → Response
      └─ Unknown command → 404 Error Response
                │
                └─ [if AGENT_FALLBACK=true] → /agent handler
      │
      ▼
6. Serialise Response
      │
      ▼
7. sendMessage via Telegram API
      │
      ▼
8. Record audit log entry (SQLite)
```

### 4.1 Middleware / Interceptors

Before reaching a handler, each update passes through middleware:

| Middleware | Node.js | Rust | Haskell |
|------------|---------|------|---------|
| Request logging | `telegraf.use(logger)` | `tracing` span | `logInfo` |
| Auth check | `telegraf.use(authMiddleware)` | `before_handler` | `withAuth` |
| Rate limiter | `telegraf.use(rateLimiter)` | `rate_limit_check` | `checkRateLimit` |
| Error boundary | `telegraf.catch` | `Result` propagation | `catchE` / `SomeException` |

---

## 5. Error Handling Strategy

### 5.1 Error Categories

```
BotError
├── TelegramApiError    — HTTP 4xx/5xx from Telegram
├── CommandError        — bad syntax, missing args
├── AuthError           — forbidden user/chat
├── RateLimitError      — too many requests
├── IntegrationError    — scrum board / issue tracker
├── LlmError            — Ollama unreachable or returned garbage
├── StateError          — database / lock failure
├── ConfigError         — missing env vars at startup
└── InternalError       — unexpected panics / exceptions
```

### 5.2 Handling Per Language

**Node.js**: Every async handler is wrapped in a `try/catch`. Caught errors are
converted to `BotError` objects and forwarded to the central error handler,
which serialises them as error responses.

**Rust**: Handlers return `Result<Response, BotError>`. The dispatcher pattern-
matches on `Err(e)` and converts it to an error response. No panics in handler
code; only `unwrap()` is banned in library code (enforced by Clippy lint
`clippy::unwrap_used`).

**Haskell**: Handlers run in `ExceptT BotError (ReaderT BotEnv IO)`. The
dispatcher uses `runExceptT` and maps `Left err` to an error response. GHC
exceptions (`SomeException`) from third-party libraries are caught with
`try @SomeException` and wrapped in `InternalError`.

### 5.3 User-Facing Error Messages

Error messages sent to users are always:
- Written in plain language (no stack traces, no internal paths).
- Actionable: they tell the user what to do next.
- Consistent: same error code → same message template across all languages.

---

## 6. Integration Layer

```
┌─────────────────────────────────────────────────────┐
│                    Bot Process                       │
│                                                      │
│  Commands ──► Integrations                           │
│                  ├── OllamaClient   (HTTP REST)      │
│                  ├── ScrumBoard     (SQLite / REST)  │
│                  └── IssueTracker   (SQLite / REST)  │
└─────────────────────────────────────────────────────┘
         │                │                │
         ▼                ▼                ▼
     Ollama API      SQLite file      External API
     :11434          bot.db           (optional)
```

### 6.1 Ollama Client

The OllamaClient is a thin HTTP wrapper that:
- Sends `POST /api/generate` with the prompt + context.
- Enforces a per-request timeout (default 60 s).
- Exposes a `health_check()` method used by the background probe.
- Supports streaming mode (`stream: true`) for long responses.

### 6.2 ScrumBoard Integration

Backed by SQLite by default. Schema:

```sql
CREATE TABLE sprints (
    id       TEXT PRIMARY KEY,
    name     TEXT NOT NULL,
    status   TEXT NOT NULL DEFAULT 'active',
    created  TEXT NOT NULL,
    closed   TEXT
);

CREATE TABLE scrum_items (
    id        TEXT PRIMARY KEY,
    sprint_id TEXT NOT NULL REFERENCES sprints(id),
    title     TEXT NOT NULL,
    status    TEXT NOT NULL DEFAULT 'todo',
    assignee  INTEGER,
    created   TEXT NOT NULL,
    updated   TEXT NOT NULL
);
```

---

## 7. Security Model

| Concern | Mitigation |
|---------|------------|
| Token exposure | Never logged; loaded from env var only |
| Unauthenticated callers | `ALLOWED_CHAT_IDS` env var allowlist |
| Webhook spoofing | `X-Telegram-Bot-Api-Secret-Token` validation |
| SQL injection | Parameterised queries everywhere |
| LLM prompt injection | User input sanitised before forwarding to Ollama |
| Container escape | Runs as non-root UID; read-only filesystem where possible |
| Dependency supply chain | Cargo.lock / package-lock.json committed; `cargo audit` in CI |
