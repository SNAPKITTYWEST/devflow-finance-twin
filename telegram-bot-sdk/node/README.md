# DevFlow Telegram Bot — Node.js Reference Implementation

Node.js/ESM reference implementation of the Telegram Bot SDK, built on
[Telegraf](https://telegraf.js.org/) with Ollama LLM fallback, Scrum board
management, issue tracking, and a pluggable agent command framework.

---

## Quick Start

```bash
cd node
npm install

# Copy the example env file and fill in your token
cp .env.example .env
# Edit .env: set BOT_TOKEN to the token from @BotFather

npm start
```

---

## Requirements

| Dependency    | Version  | Purpose                              |
|---------------|----------|--------------------------------------|
| Node.js       | ≥ 18.0   | Native ESM, `fetch`, `AbortController` |
| npm           | ≥ 9.0    | Package management                    |
| Ollama        | optional | LLM fallback (`ollama serve`)         |

---

## Environment Variables

| Variable                 | Default                        | Description                        |
|--------------------------|--------------------------------|------------------------------------|
| `BOT_TOKEN`              | **required**                   | Telegram bot token from @BotFather |
| `OLLAMA_HOST`            | `http://localhost:11434`       | Ollama API base URL                |
| `OLLAMA_MODEL`           | `llama2`                       | Default Ollama model               |
| `DB_PATH`                | _(in-memory)_                  | SQLite database path               |
| `LOG_LEVEL`              | `info`                         | Log verbosity                      |
| `RATE_LIMIT_TOKENS`      | `5`                            | Tokens per user per interval       |
| `RATE_LIMIT_INTERVAL_MS` | `10000`                        | Rate limit refill interval (ms)    |

---

## Bot Commands

### Scrum Board

| Command                         | Description                        |
|---------------------------------|------------------------------------|
| `/sprint create <name>`         | Create a new sprint                |
| `/sprint list [status]`         | List sprints (active/planned/closed)|
| `/sprint activate <id>`         | Start a sprint                     |
| `/sprint close <id>`            | Close a sprint                     |
| `/sprint status [id]`           | Show sprint progress               |
| `/item add [sprint-id] <title>` | Add item to sprint                 |
| `/item list [sprint-id]`        | List sprint items                  |
| `/item start <id>`              | Move item to in-progress           |
| `/item done <id>`               | Mark item complete                 |
| `/item block <id>`              | Mark item as blocked               |
| `/board [sprint-id]`            | Kanban board view                  |
| `/velocity [sprint-id]`         | Sprint velocity report             |

### Issue Tracking

| Command                         | Description                        |
|---------------------------------|------------------------------------|
| `/issue list [status]`          | List issues (default: open)        |
| `/issue add <title>`            | Create a new issue                 |
| `/issue get <id>`               | Show issue details                 |
| `/issue close <id>`             | Close an issue                     |
| `/issue reopen <id>`            | Reopen an issue                    |
| `/issue assign <id> @user`      | Assign issue to user               |
| `/bug <title> [| description]`  | Quick bug report                   |
| `/resolve <id>`                 | Resolve an issue                   |

### Agent Framework

| Command                   | Description                            |
|---------------------------|----------------------------------------|
| `/agent help`             | Show agent help                        |
| `/agent list`             | List registered agent commands         |
| `/agent status`           | Show framework status                  |
| `/agent <command> [args]` | Execute an agent command               |
| `/agent ping`             | Built-in: ping/pong                    |
| `/agent echo <text>`      | Built-in: echo back text               |
| `/agent time`             | Built-in: current server time          |
| `/agent whoami`           | Built-in: Telegram user info           |
| `/agent history`          | Built-in: recent command history       |

> **Tip**: Unknown `/agent` commands fall back to Ollama LLM automatically.

---

## Architecture

```
src/
├── index.js              Entry point — loads .env, boots bot
├── bot.mjs               DevFlowBot class (Telegraf wrapper)
│   ├── RateLimiter       Token-bucket rate limiting per user
│   ├── Middleware stack   Logging → rate limit → error handling
│   └── Command registry  Wires up all command modules
├── agent.mjs             AgentFramework — command registry + Ollama fallback
├── commands/
│   ├── scrum.mjs         /sprint /item /board /velocity
│   ├── issue.mjs         /issue /bug /resolve
│   └── agent.mjs         /agent dispatcher
└── lib/
    ├── ollama.mjs         Ollama HTTP client (streaming + retry)
    ├── scrum-board.mjs    In-memory sprint/item store with CRUD
    └── persistence.mjs    SQLite backend + in-memory fallback
```

---

## Extending with Custom Agent Commands

Register additional commands on the bot's agent framework:

```js
import { DevFlowBot } from './src/bot.mjs';

const bot = new DevFlowBot({ token: process.env.BOT_TOKEN });

// Register a custom agent command
bot.agent.register('deploy', 'Trigger a deployment', async (args, ctx) => {
  const env = args || 'staging';
  // ... your deployment logic here ...
  return {
    status: 'success',
    message: `Deployment to ${env} triggered by @${ctx.username}`,
    metadata: { env, triggeredBy: ctx.userId },
  };
});

await bot.launch();
```

---

## Persistence

By default the bot runs with in-memory state (everything is lost on restart).
Set `DB_PATH` in `.env` to enable SQLite persistence:

```env
DB_PATH=./data/bot-state.db
```

The directory is created automatically. All sprint, item, and issue data is
stored in the `kv_store` table using JSON serialization.

---

## Development

```bash
# Watch mode (restarts on file changes)
npm run dev

# Run tests
npm test
```

---

## Docker

```dockerfile
FROM node:20-slim
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY src ./src
ENV BOT_TOKEN=""
ENV OLLAMA_HOST="http://ollama:11434"
CMD ["node", "src/index.js"]
```

```yaml
# docker-compose.yml
version: "3.9"
services:
  bot:
    build: .
    env_file: .env
    volumes:
      - ./data:/app/data
  ollama:
    image: ollama/ollama
    volumes:
      - ollama_data:/root/.ollama
volumes:
  ollama_data:
```

---

## License

GPL-3.0-or-later — see root `LICENSE` file.
