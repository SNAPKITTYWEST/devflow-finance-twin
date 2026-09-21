/**
 * bot.mjs — Main Telegraf bot class
 *
 * Responsibilities:
 *  - Bootstrap Telegraf with token from environment
 *  - Register all command modules (scrum, issue, agent)
 *  - Install error-handling middleware
 *  - Per-user rate limiting (token bucket, 30 msgs/sec global Telegram limit)
 *  - Graceful shutdown on SIGTERM/SIGINT
 *  - Lifecycle hooks: onReady, onError
 */

import { Telegraf } from 'telegraf';
import { ScrumCommands } from './commands/scrum.mjs';
import { IssueCommands } from './commands/issue.mjs';
import { AgentCommand } from './commands/agent.mjs';
import { AgentFramework } from './agent.mjs';
import { OllamaClient } from './lib/ollama.mjs';
import ScrumBoard from './lib/scrum-board.mjs';
import PersistenceManager from './lib/persistence.mjs';

// ---------------------------------------------------------------------------
// Rate limiter — token bucket per user
// ---------------------------------------------------------------------------

class RateLimiter {
  /**
   * @param {{
   *   tokensPerInterval: number,   // Tokens added per refill
   *   intervalMs: number,          // Refill interval in milliseconds
   *   bucketSize: number           // Max tokens per user
   * }} opts
   */
  constructor({ tokensPerInterval = 5, intervalMs = 10_000, bucketSize = 10 } = {}) {
    this.tokensPerInterval = tokensPerInterval;
    this.intervalMs = intervalMs;
    this.bucketSize = bucketSize;
    /** @type {Map<string, { tokens: number, lastRefill: number }>} */
    this.buckets = new Map();

    // Periodic cleanup to avoid unbounded memory growth
    this._cleanupInterval = setInterval(() => this.#cleanup(), 5 * 60 * 1000);
    this._cleanupInterval.unref?.();
  }

  /**
   * Consume a token for a user. Returns true if allowed, false if rate-limited.
   * @param {string} userId
   * @returns {boolean}
   */
  consume(userId) {
    const now = Date.now();
    let bucket = this.buckets.get(userId);

    if (!bucket) {
      bucket = { tokens: this.bucketSize - 1, lastRefill: now };
      this.buckets.set(userId, bucket);
      return true;
    }

    // Refill tokens based on elapsed time
    const elapsed = now - bucket.lastRefill;
    const refillAmount = Math.floor(elapsed / this.intervalMs) * this.tokensPerInterval;
    if (refillAmount > 0) {
      bucket.tokens = Math.min(this.bucketSize, bucket.tokens + refillAmount);
      bucket.lastRefill = now;
    }

    if (bucket.tokens <= 0) return false;
    bucket.tokens--;
    return true;
  }

  /** Check remaining tokens without consuming. */
  remaining(userId) {
    return this.buckets.get(userId)?.tokens ?? this.bucketSize;
  }

  #cleanup() {
    const cutoff = Date.now() - 10 * 60 * 1000; // Remove buckets idle for 10 min
    for (const [id, bucket] of this.buckets) {
      if (bucket.lastRefill < cutoff) this.buckets.delete(id);
    }
  }

  stop() {
    clearInterval(this._cleanupInterval);
  }
}

// ---------------------------------------------------------------------------
// DevFlowBot
// ---------------------------------------------------------------------------

export class DevFlowBot {
  /** @type {import('telegraf').Telegraf|null} */
  #bot = null;

  /** @type {PersistenceManager} */
  #persistence;

  /** @type {ScrumBoard} */
  #board;

  /** @type {AgentFramework} */
  #agent;

  /** @type {OllamaClient|null} */
  #ollama;

  /** @type {RateLimiter} */
  #rateLimiter;

  /** @type {boolean} */
  #started = false;

  /** @type {(bot: DevFlowBot) => void | null} */
  #onReadyCallback = null;

  /** @type {(err: Error, ctx?: unknown) => void | null} */
  #onErrorCallback = null;

  /**
   * @param {{
   *   token?: string,
   *   dbPath?: string,
   *   ollamaHost?: string,
   *   ollamaModel?: string,
   *   rateLimitTokens?: number,
   *   rateLimitIntervalMs?: number,
   * }} opts
   */
  constructor({
    token = process.env.BOT_TOKEN,
    dbPath = process.env.DB_PATH,
    ollamaHost = process.env.OLLAMA_HOST ?? 'http://localhost:11434',
    ollamaModel = process.env.OLLAMA_MODEL ?? 'llama2',
    rateLimitTokens = 5,
    rateLimitIntervalMs = 10_000,
  } = {}) {
    if (!token) {
      throw new Error(
        'BOT_TOKEN is required. Set it in your .env file or pass it as the token option.'
      );
    }

    // Persistence
    this.#persistence = PersistenceManager.create({ dbPath });

    // Scrum board
    this.#board = new ScrumBoard({ persistence: this.#persistence });

    // Ollama client (non-fatal if unavailable)
    this.#ollama = new OllamaClient({ host: ollamaHost, model: ollamaModel });

    // Agent framework
    this.#agent = new AgentFramework({ ollama: this.#ollama });

    // Rate limiter
    this.#rateLimiter = new RateLimiter({
      tokensPerInterval: rateLimitTokens,
      intervalMs: rateLimitIntervalMs,
      bucketSize: rateLimitTokens * 2,
    });

    // Telegraf instance
    this.#bot = new Telegraf(token);

    // Wire up middleware and commands
    this.#setupMiddleware();
    this.#setupCommands();
    this.#setupMessageHandler();
  }

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /** @param {(bot: DevFlowBot) => void} cb */
  onReady(cb) {
    this.#onReadyCallback = cb;
    return this;
  }

  /** @param {(err: Error, ctx?: unknown) => void} cb */
  onError(cb) {
    this.#onErrorCallback = cb;
    return this;
  }

  /**
   * Start the bot using long polling.
   * Registers SIGTERM/SIGINT handlers for graceful shutdown.
   */
  async launch() {
    if (this.#started) throw new Error('Bot already started');
    this.#started = true;

    // Graceful shutdown
    const shutdown = async (signal) => {
      console.info(`[bot] Received ${signal}, shutting down gracefully…`);
      this.#rateLimiter.stop();
      this.#bot.stop(signal);
      this.#persistence.close();
      process.exit(0);
    };

    process.once('SIGTERM', () => shutdown('SIGTERM'));
    process.once('SIGINT', () => shutdown('SIGINT'));

    console.info('[bot] Starting bot…');
    await this.#bot.launch();

    if (this.#onReadyCallback) {
      this.#onReadyCallback(this);
    }

    // Log bot info
    const me = await this.#bot.telegram.getMe().catch(() => null);
    if (me) {
      console.info(`[bot] Running as @${me.username} (ID: ${me.id})`);
    }
  }

  /**
   * Stop the bot (for programmatic control / tests).
   */
  stop() {
    this.#rateLimiter.stop();
    this.#bot?.stop();
    this.#persistence.close();
  }

  /**
   * Expose the underlying Telegraf instance for advanced usage.
   */
  get telegraf() {
    return this.#bot;
  }

  /** Expose the agent framework so external code can register commands. */
  get agent() {
    return this.#agent;
  }

  // -------------------------------------------------------------------------
  // Middleware
  // -------------------------------------------------------------------------

  #setupMiddleware() {
    // Logging middleware
    this.#bot.use(async (ctx, next) => {
      const username = ctx.from?.username ?? ctx.from?.id ?? 'unknown';
      const msgText =
        ctx.message?.text ?? ctx.callbackQuery?.data ?? '[no text]';
      const ts = new Date().toISOString();
      console.info(`[bot][${ts}] @${username}: ${msgText.slice(0, 80)}`);
      await next();
    });

    // Rate limiting middleware
    this.#bot.use(async (ctx, next) => {
      const userId = String(ctx.from?.id ?? 0);
      if (!this.#rateLimiter.consume(userId)) {
        console.warn(`[bot] Rate limit hit for user ${userId}`);
        await ctx.reply('⏱ You are sending too many requests. Please slow down.').catch(() => {});
        return;
      }
      await next();
    });

    // Error handling middleware
    this.#bot.catch((err, ctx) => {
      const username = ctx.from?.username ?? ctx.from?.id ?? 'unknown';
      console.error(`[bot] Unhandled error for @${username}:`, err);
      if (this.#onErrorCallback) {
        this.#onErrorCallback(err, ctx);
      }
      ctx
        .reply('❌ An unexpected error occurred. Please try again.')
        .catch(() => {});
    });
  }

  // -------------------------------------------------------------------------
  // Commands
  // -------------------------------------------------------------------------

  #setupCommands() {
    // /start
    this.#bot.command('start', (ctx) => {
      const name = ctx.from?.first_name ?? 'there';
      return ctx.reply(
        `👋 Hello, *${name}*\\! I'm *DevFlow Bot* — your Agile development companion\\.\n\n` +
          `*Commands*\n` +
          `\`/sprint\` — Sprint management\n` +
          `\`/item\` — Sprint items\n` +
          `\`/board\` — Kanban board view\n` +
          `\`/issue\` — Issue tracking\n` +
          `\`/bug\` — Quick bug report\n` +
          `\`/agent\` — AI agent commands\n` +
          `\`/help\` — Full help\n\n` +
          `_Powered by Ollama + Telegraf_`,
        { parse_mode: 'MarkdownV2' }
      );
    });

    // /help
    this.#bot.command('help', (ctx) => {
      return ctx.reply(
        `*DevFlow Bot — Help*\n\n` +
          `*Scrum*\n` +
          `\`/sprint create <name>\` — Create sprint\n` +
          `\`/sprint list\` — List sprints\n` +
          `\`/sprint activate <id>\` — Activate sprint\n` +
          `\`/sprint close <id>\` — Close sprint\n` +
          `\`/item add <title>\` — Add item to active sprint\n` +
          `\`/item list\` — List items\n` +
          `\`/item done <id>\` — Complete item\n` +
          `\`/board\` — Board view\n` +
          `\`/velocity\` — Sprint velocity\n\n` +
          `*Issues*\n` +
          `\`/issue list\` — List issues\n` +
          `\`/issue add <title>\` — New issue\n` +
          `\`/bug <title>\` — Quick bug report\n` +
          `\`/resolve <id>\` — Resolve issue\n\n` +
          `*Agent*\n` +
          `\`/agent help\` — Agent help\n` +
          `\`/agent list\` — List agent commands\n` +
          `\`/agent <cmd> [args]\` — Run agent command\n\n` +
          `_Tip: Unknown /agent commands fall back to Ollama LLM_`,
        { parse_mode: 'Markdown' }
      );
    });

    // Register scrum commands
    const scrumCmds = new ScrumCommands({ board: this.#board });
    scrumCmds.register(this.#bot);

    // Register issue commands
    const issueCmds = new IssueCommands({ persistence: this.#persistence });
    issueCmds.register(this.#bot);

    // Register agent command
    const agentCmd = new AgentCommand({ agentFramework: this.#agent });
    agentCmd.register(this.#bot);
  }

  // -------------------------------------------------------------------------
  // Generic message handler
  // -------------------------------------------------------------------------

  #setupMessageHandler() {
    this.#bot.on('text', async (ctx) => {
      const text = ctx.message?.text ?? '';

      // Skip commands (already handled above)
      if (text.startsWith('/')) return;

      // For plain messages, try to be helpful with a lightweight LLM response
      if (!this.#ollama) {
        return ctx.reply(
          '💬 Send a /help command to see what I can do. LLM chat is disabled (no Ollama configured).'
        );
      }

      try {
        await ctx.sendChatAction('typing');

        const result = await this.#ollama.generate(text, {
          system:
            'You are DevFlow Bot, a helpful Telegram bot for Agile development. ' +
            'You assist with sprint planning, issue tracking, and Agile best practices. ' +
            'Keep replies brief and actionable (under 500 characters). ' +
            'If the user seems to want a specific command, suggest the relevant /command.',
        });

        const reply = result.text.trim();
        if (reply) {
          return ctx.reply(reply);
        }
      } catch (err) {
        console.warn('[bot] LLM message handler failed:', err.message);
        return ctx.reply(
          '💬 I\'m not sure how to respond to that. Try /help to see available commands.'
        );
      }
    });
  }
}

export default DevFlowBot;
