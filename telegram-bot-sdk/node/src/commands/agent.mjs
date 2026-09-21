/**
 * commands/agent.mjs — Agent invocation command
 *
 * Registers the /agent command which dispatches to the AgentFramework.
 * Supports subcommands:
 *  /agent <command> [args...]   — Run a named agent command
 *  /agent list                  — List registered agent commands
 *  /agent help                  — Show usage
 *  /agent status                — Show agent framework status
 */

// ---------------------------------------------------------------------------
// AgentCommand
// ---------------------------------------------------------------------------

export class AgentCommand {
  /** @type {import('../agent.mjs').AgentFramework} */
  #agentFramework;

  /** @param {{ agentFramework: import('../agent.mjs').AgentFramework }} opts */
  constructor({ agentFramework }) {
    this.#agentFramework = agentFramework;
  }

  /**
   * Register the /agent command.
   * @param {import('telegraf').Telegraf} bot
   */
  register(bot) {
    bot.command('agent', (ctx) => this.#handleAgent(ctx));
  }

  // -------------------------------------------------------------------------
  // Handler
  // -------------------------------------------------------------------------

  async #handleAgent(ctx) {
    const rawText = ctx.message?.text ?? '';
    const parts = rawText.replace(/^\/agent\s*/, '').trim().split(/\s+/);
    const sub = parts[0]?.toLowerCase() ?? '';

    try {
      switch (sub) {
        case '':
        case 'help':
          return ctx.reply(this.#helpText(), { parse_mode: 'Markdown' });

        case 'list':
          return ctx.reply(this.#listCommands(), { parse_mode: 'Markdown' });

        case 'status':
          return ctx.reply(this.#statusText(), { parse_mode: 'Markdown' });

        default: {
          // /agent <commandName> [args...]
          const commandName = sub;
          const args = parts.slice(1).join(' ').trim();
          const user = ctx.from?.username ?? String(ctx.from?.id ?? 'unknown');

          await ctx.sendChatAction('typing');

          const result = await this.#agentFramework.execute(commandName, args, {
            userId: String(ctx.from?.id ?? 0),
            username: user,
            chatId: String(ctx.chat?.id ?? 0),
            source: 'telegram',
          });

          return ctx.reply(this.#formatResult(result), { parse_mode: 'Markdown' });
        }
      }
    } catch (err) {
      return ctx.reply(`❌ Agent error: ${err.message}`);
    }
  }

  // -------------------------------------------------------------------------
  // Formatting
  // -------------------------------------------------------------------------

  #formatResult(result) {
    const statusEmoji = result.status === 'success' ? '✅' : result.status === 'error' ? '❌' : '⚠️';
    let msg = `${statusEmoji} *Agent Result*\n\n${result.message}`;

    if (result.metadata && Object.keys(result.metadata).length > 0) {
      const meta = Object.entries(result.metadata)
        .filter(([k]) => k !== 'rawResponse')
        .map(([k, v]) => `  _${k}_: \`${String(v).slice(0, 60)}\``)
        .join('\n');
      if (meta) msg += `\n\n📊 *Metadata*\n${meta}`;
    }

    if (result.durationMs !== undefined) {
      msg += `\n\n⏱ ${result.durationMs}ms`;
    }

    return msg;
  }

  #helpText() {
    const commands = this.#agentFramework.listCommands();
    const cmdList = commands.length > 0
      ? commands.map((c) => `  \`${c.name}\` — ${c.description}`).join('\n')
      : '  _No commands registered_';

    return (
      `🤖 *Agent Framework*\n\n` +
      `*Usage*\n` +
      `\`/agent <command> [args]\` — Execute a command\n` +
      `\`/agent list\` — List all commands\n` +
      `\`/agent status\` — Framework status\n\n` +
      `*Registered Commands*\n${cmdList}\n\n` +
      `_Unknown commands are routed to the Ollama LLM fallback._`
    );
  }

  #listCommands() {
    const commands = this.#agentFramework.listCommands();
    if (commands.length === 0) {
      return '🤖 No agent commands registered yet.';
    }
    const lines = commands.map(
      (c) => `• \`${c.name}\` — ${c.description}`
    );
    return `🤖 *Agent Commands* (${commands.length})\n\n${lines.join('\n')}`;
  }

  #statusText() {
    const status = this.#agentFramework.getStatus();
    const ollamaEmoji = status.ollamaAvailable ? '✅' : '⚠️';
    const ollamaStatus = status.ollamaAvailable
      ? `Available (${status.ollamaModel})`
      : 'Not available (no fallback)';

    return (
      `🤖 *Agent Framework Status*\n\n` +
      `Commands registered: ${status.commandCount}\n` +
      `Executions total: ${status.totalExecutions}\n` +
      `Last execution: ${status.lastExecution ?? 'none'}\n` +
      `${ollamaEmoji} Ollama: ${ollamaStatus}`
    );
  }
}

export default AgentCommand;
