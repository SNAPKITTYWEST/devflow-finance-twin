/**
 * agent.mjs — Agent command framework
 *
 * The AgentFramework manages a registry of named command handlers. When a command
 * is invoked via /agent <name> [args], the framework:
 *
 *  1. Looks up the handler in the registry
 *  2. Builds a rich execution context (userId, history, metadata)
 *  3. Executes the handler with timeout protection
 *  4. Falls back to the Ollama LLM for unknown commands
 *  5. Tracks execution metadata (duration, success/failure, usage stats)
 *
 * Built-in commands registered by default:
 *  ping, echo, time, whoami, help
 */

import { OllamaClient, OllamaConnectionError } from './lib/ollama.mjs';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/**
 * @typedef {'success' | 'error' | 'fallback'} AgentStatus
 *
 * @typedef {Object} AgentContext
 * @property {string} userId
 * @property {string} username
 * @property {string} chatId
 * @property {string} source
 * @property {Array<{command: string, args: string, timestamp: string}>} history
 *
 * @typedef {Object} AgentResult
 * @property {AgentStatus} status
 * @property {string} message
 * @property {number} durationMs
 * @property {Record<string, unknown>} metadata
 *
 * @typedef {Object} CommandDefinition
 * @property {string} name
 * @property {string} description
 * @property {(args: string, ctx: AgentContext) => Promise<AgentResult>} handler
 */

// ---------------------------------------------------------------------------
// AgentFramework
// ---------------------------------------------------------------------------

export class AgentFramework {
  /** @type {Map<string, CommandDefinition>} */
  #registry = new Map();

  /** @type {Map<string, Array<{command: string, args: string, timestamp: string}>>} */
  #contextHistory = new Map();

  /** @type {number} */
  #totalExecutions = 0;

  /** @type {string|null} */
  #lastExecution = null;

  /** @type {OllamaClient|null} */
  #ollama;

  /** @type {number} Max command execution time in ms */
  #timeoutMs;

  /** @type {number} Max history entries kept per user */
  #maxHistoryLen;

  /**
   * @param {{
   *   ollama?: OllamaClient,
   *   timeoutMs?: number,
   *   maxHistoryLen?: number
   * }} opts
   */
  constructor({ ollama = null, timeoutMs = 15_000, maxHistoryLen = 20 } = {}) {
    this.#ollama = ollama;
    this.#timeoutMs = timeoutMs;
    this.#maxHistoryLen = maxHistoryLen;

    // Register built-in commands
    this.#registerBuiltins();
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /**
   * Register a command handler.
   * @param {string} name
   * @param {string} description
   * @param {(args: string, ctx: AgentContext) => Promise<AgentResult>} handler
   */
  register(name, description, handler) {
    if (!name || typeof name !== 'string') throw new Error('Command name is required');
    if (typeof handler !== 'function') throw new Error('Command handler must be a function');
    this.#registry.set(name.toLowerCase(), { name: name.toLowerCase(), description, handler });
  }

  /**
   * Unregister a command.
   * @param {string} name
   */
  unregister(name) {
    this.#registry.delete(name.toLowerCase());
  }

  /**
   * List all registered commands.
   * @returns {Array<{ name: string, description: string }>}
   */
  listCommands() {
    return Array.from(this.#registry.values()).map(({ name, description }) => ({
      name,
      description,
    }));
  }

  /**
   * Execute a command by name.
   *
   * @param {string} commandName
   * @param {string} args
   * @param {{ userId: string, username: string, chatId: string, source: string }} ctxInput
   * @returns {Promise<AgentResult>}
   */
  async execute(commandName, args, ctxInput) {
    const start = Date.now();
    const name = commandName.toLowerCase();

    // Build context with history
    const history = this.#getHistory(ctxInput.userId);
    const ctx = { ...ctxInput, history };

    // Track the call
    this.#totalExecutions++;
    this.#lastExecution = new Date().toISOString();
    this.#pushHistory(ctxInput.userId, { command: name, args, timestamp: this.#lastExecution });

    // Attempt handler lookup
    const def = this.#registry.get(name);

    if (def) {
      return this.#runWithTimeout(def, args, ctx, start);
    }

    // Unknown command — fall back to Ollama
    return this.#ollamaFallback(commandName, args, ctx, start);
  }

  /**
   * Get the framework's runtime status.
   */
  getStatus() {
    return {
      commandCount: this.#registry.size,
      totalExecutions: this.#totalExecutions,
      lastExecution: this.#lastExecution,
      ollamaAvailable: this.#ollama !== null,
      ollamaModel: this.#ollama?.model ?? null,
    };
  }

  // -------------------------------------------------------------------------
  // Execution
  // -------------------------------------------------------------------------

  async #runWithTimeout(def, args, ctx, start) {
    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        resolve({
          status: 'error',
          message: `Command \`${def.name}\` timed out after ${this.#timeoutMs}ms.`,
          durationMs: Date.now() - start,
          metadata: { command: def.name, timeout: true },
        });
      }, this.#timeoutMs);

      def
        .handler(args, ctx)
        .then((result) => {
          clearTimeout(timer);
          resolve({
            ...result,
            durationMs: Date.now() - start,
            metadata: { ...(result.metadata ?? {}), command: def.name },
          });
        })
        .catch((err) => {
          clearTimeout(timer);
          resolve({
            status: 'error',
            message: `Error in \`${def.name}\`: ${err.message}`,
            durationMs: Date.now() - start,
            metadata: { command: def.name, error: err.message },
          });
        });
    });
  }

  async #ollamaFallback(commandName, args, ctx, start) {
    if (!this.#ollama) {
      return {
        status: 'error',
        message: `Unknown command: \`${commandName}\`. No LLM fallback configured.`,
        durationMs: Date.now() - start,
        metadata: { command: commandName, fallback: false },
      };
    }

    try {
      const prompt = this.#buildFallbackPrompt(commandName, args, ctx);
      const result = await this.#ollama.generate(prompt, {
        system:
          'You are an AI assistant in a Telegram bot. The user sent an unrecognised command. ' +
          'Interpret their intent and respond helpfully. Be brief (under 500 chars).',
      });

      return {
        status: 'fallback',
        message: result.text.trim() || 'No response from LLM.',
        durationMs: Date.now() - start,
        metadata: {
          command: commandName,
          fallback: true,
          model: result.model,
          llmDurationMs: result.durationMs,
        },
      };
    } catch (err) {
      if (err instanceof OllamaConnectionError) {
        return {
          status: 'error',
          message:
            `Unknown command: \`${commandName}\`. ` +
            'Ollama is not running — start it with `ollama serve`.',
          durationMs: Date.now() - start,
          metadata: { command: commandName, fallback: false },
        };
      }
      return {
        status: 'error',
        message: `Unknown command: \`${commandName}\`. LLM fallback failed: ${err.message}`,
        durationMs: Date.now() - start,
        metadata: { command: commandName, fallback: false, error: err.message },
      };
    }
  }

  #buildFallbackPrompt(commandName, args, ctx) {
    const historyLines = ctx.history
      .slice(-5)
      .map((h) => `  - /${h.command} ${h.args}`)
      .join('\n');

    return (
      `User @${ctx.username} sent an unknown bot command: /${commandName} ${args}\n\n` +
      (historyLines ? `Recent command history:\n${historyLines}\n\n` : '') +
      `Please interpret what the user might want and provide a helpful response.`
    );
  }

  // -------------------------------------------------------------------------
  // History management
  // -------------------------------------------------------------------------

  #getHistory(userId) {
    return this.#contextHistory.get(userId) ?? [];
  }

  #pushHistory(userId, entry) {
    const history = this.#getHistory(userId);
    history.push(entry);
    if (history.length > this.#maxHistoryLen) {
      history.splice(0, history.length - this.#maxHistoryLen);
    }
    this.#contextHistory.set(userId, history);
  }

  // -------------------------------------------------------------------------
  // Built-in commands
  // -------------------------------------------------------------------------

  #registerBuiltins() {
    this.register('ping', 'Check if the agent is responsive', async (_args, _ctx) => ({
      status: 'success',
      message: 'pong 🏓',
      metadata: { serverTime: new Date().toISOString() },
    }));

    this.register('echo', 'Echo back the provided arguments', async (args, _ctx) => ({
      status: 'success',
      message: args || '(nothing to echo)',
      metadata: { length: args.length },
    }));

    this.register('time', 'Return the current server time', async (_args, _ctx) => {
      const now = new Date();
      return {
        status: 'success',
        message: `Current server time: *${now.toUTCString()}*`,
        metadata: { timestamp: now.toISOString(), unixMs: now.getTime() },
      };
    });

    this.register('whoami', 'Return your Telegram user info', async (_args, ctx) => ({
      status: 'success',
      message: `You are @${ctx.username} (ID: ${ctx.userId}) in chat ${ctx.chatId}.`,
      metadata: { userId: ctx.userId, username: ctx.username, chatId: ctx.chatId },
    }));

    this.register('history', 'Show your recent command history', async (_args, ctx) => {
      const history = ctx.history.slice(-10);
      if (history.length === 0) {
        return { status: 'success', message: 'No command history yet.', metadata: {} };
      }
      const lines = history
        .map((h, i) => `${i + 1}. \`/${h.command}\` ${h.args} — ${h.timestamp.slice(11, 19)} UTC`)
        .join('\n');
      return {
        status: 'success',
        message: `*Your recent commands:*\n\n${lines}`,
        metadata: { count: history.length },
      };
    });

    this.register('help', 'List all available agent commands', async (_args, _ctx) => {
      const commands = this.listCommands();
      const lines = commands.map((c) => `• \`${c.name}\` — ${c.description}`).join('\n');
      return {
        status: 'success',
        message: `*Available Agent Commands*\n\n${lines}`,
        metadata: { commandCount: commands.length },
      };
    });
  }
}

export default AgentFramework;
