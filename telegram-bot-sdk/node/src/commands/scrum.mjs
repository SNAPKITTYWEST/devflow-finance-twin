/**
 * commands/scrum.mjs — Scrum board Telegram commands
 *
 * Registers the following commands on the Telegraf bot:
 *  /sprint  [create|list|close|activate|status] [name]
 *  /item    [add|done|start|block|list] [sprint?] [title?]
 *  /board   [sprint?]    — Kanban-style board view
 *  /velocity [sprint?]   — Sprint velocity summary
 *
 * All commands accept the active sprint as default when no sprint ID is given.
 */

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

const STATUS_EMOJI = {
  todo: '⬜',
  'in-progress': '🔵',
  done: '✅',
  blocked: '🔴',
};

const TYPE_EMOJI = {
  story: '📖',
  task: '🔧',
  bug: '🐛',
  spike: '⚡',
};

const SPRINT_STATUS_EMOJI = {
  planned: '📅',
  active: '🚀',
  closed: '🏁',
};

function fmtSprint(sprint) {
  const emoji = SPRINT_STATUS_EMOJI[sprint.status] ?? '📋';
  const closed = sprint.closedAt
    ? ` | Closed: ${sprint.closedAt.slice(0, 10)}`
    : '';
  return `${emoji} *${escMd(sprint.name)}* \`${sprint.id.slice(0, 8)}\`\nStatus: ${sprint.status}${closed}`;
}

function fmtItem(item) {
  const se = STATUS_EMOJI[item.status] ?? '•';
  const te = TYPE_EMOJI[item.type] ?? '•';
  const pts = item.points > 0 ? ` _(${item.points}pt)_` : '';
  const who = item.assignee ? ` @${escMd(item.assignee)}` : '';
  return `${se}${te} ${escMd(item.title)}${pts}${who}`;
}

function escMd(text) {
  // Escape special chars for Telegram MarkdownV2
  return String(text).replace(/[_*[\]()~`>#+=|{}.!\\-]/g, (c) => `\\${c}`);
}

// ---------------------------------------------------------------------------
// Argument parsing helpers
// ---------------------------------------------------------------------------

/**
 * Parse command text: "/sprint create My Sprint"  → { sub: 'create', rest: 'My Sprint' }
 */
function parseArgs(text) {
  const parts = (text ?? '').trim().replace(/^\/\w+\s*/, '').split(/\s+/);
  const sub = parts[0]?.toLowerCase() ?? '';
  const rest = parts.slice(1).join(' ').trim();
  return { sub, rest, parts: parts.slice(1) };
}

// ---------------------------------------------------------------------------
// ScrumCommands
// ---------------------------------------------------------------------------

export class ScrumCommands {
  #board;

  /** @param {{ board: import('../lib/scrum-board.mjs').ScrumBoard }} opts */
  constructor({ board }) {
    this.#board = board;
  }

  /**
   * Register all scrum commands with a Telegraf bot instance.
   * @param {import('telegraf').Telegraf} bot
   */
  register(bot) {
    bot.command('sprint', (ctx) => this.#handleSprint(ctx));
    bot.command('item', (ctx) => this.#handleItem(ctx));
    bot.command('board', (ctx) => this.#handleBoard(ctx));
    bot.command('velocity', (ctx) => this.#handleVelocity(ctx));
  }

  // -------------------------------------------------------------------------
  // /sprint
  // -------------------------------------------------------------------------

  async #handleSprint(ctx) {
    const { sub, rest } = parseArgs(ctx.message?.text);

    try {
      switch (sub) {
        case 'create':
          return ctx.reply(this.#sprintCreate(rest), { parse_mode: 'Markdown' });
        case 'activate':
          return ctx.reply(this.#sprintActivate(rest), { parse_mode: 'Markdown' });
        case 'close':
          return ctx.reply(this.#sprintClose(rest), { parse_mode: 'Markdown' });
        case 'list':
        case '':
          return ctx.reply(this.#sprintList(rest), { parse_mode: 'Markdown' });
        case 'status':
          return ctx.reply(this.#sprintStatus(rest), { parse_mode: 'Markdown' });
        default:
          return ctx.reply(this.#sprintHelp(), { parse_mode: 'Markdown' });
      }
    } catch (err) {
      return ctx.reply(`❌ ${err.message}`);
    }
  }

  #sprintCreate(name) {
    if (!name) return '⚠️ Usage: `/sprint create <name>`';
    const sprint = this.#board.createSprint({ name });
    return (
      `✅ Sprint created!\n\n` +
      `${fmtSprint(sprint)}\n\n` +
      `Use \`/sprint activate ${sprint.id.slice(0, 8)}\` to start it.`
    );
  }

  #sprintActivate(idOrName) {
    const sprint = this.#resolveSprint(idOrName);
    const activated = this.#board.activateSprint(sprint.id);
    return `🚀 Sprint *${escMd(activated.name)}* is now active!`;
  }

  #sprintClose(idOrName) {
    const sprint = this.#resolveSprint(idOrName);
    const closed = this.#board.closeSprint(sprint.id);
    const { completed, committed, percentage } = this.#board.getVelocity(closed.id);
    return (
      `🏁 Sprint *${escMd(closed.name)}* closed\\.\n\n` +
      `Velocity: ${completed}/${committed} pts \\(${percentage}%\\)`
    );
  }

  #sprintList(statusFilter) {
    const validStatuses = ['active', 'planned', 'closed'];
    const status = validStatuses.includes(statusFilter) ? statusFilter : undefined;
    const sprints = this.#board.listSprints({ status });

    if (sprints.length === 0) {
      return status
        ? `No ${status} sprints found. Use \`/sprint create <name>\` to start one.`
        : 'No sprints yet. Use `/sprint create <name>` to start one.';
    }

    const lines = sprints.map((s) => fmtSprint(s));
    return `*Sprints* (${sprints.length})\n\n${lines.join('\n\n')}`;
  }

  #sprintStatus(idOrName) {
    const sprint = this.#resolveSprint(idOrName);
    const { committed, completed, percentage } = this.#board.getVelocity(sprint.id);
    const items = this.#board.listItems(sprint.id);

    const statusCounts = { todo: 0, 'in-progress': 0, done: 0, blocked: 0 };
    for (const item of items) statusCounts[item.status]++;

    return (
      `${fmtSprint(sprint)}\n\n` +
      `📊 *Progress*: ${completed}/${committed} pts (${percentage}%)\n` +
      `⬜ Todo: ${statusCounts.todo}\n` +
      `🔵 In-progress: ${statusCounts['in-progress']}\n` +
      `✅ Done: ${statusCounts.done}\n` +
      `🔴 Blocked: ${statusCounts.blocked}`
    );
  }

  #sprintHelp() {
    return (
      `*Sprint Commands*\n\n` +
      `\`/sprint create <name>\` — Create a new sprint\n` +
      `\`/sprint list [status]\` — List sprints\n` +
      `\`/sprint activate <id>\` — Activate a sprint\n` +
      `\`/sprint close <id>\` — Close a sprint\n` +
      `\`/sprint status [id]\` — Sprint status`
    );
  }

  // -------------------------------------------------------------------------
  // /item
  // -------------------------------------------------------------------------

  async #handleItem(ctx) {
    const { sub, rest, parts } = parseArgs(ctx.message?.text);

    try {
      switch (sub) {
        case 'add':
          return ctx.reply(await this.#itemAdd(parts), { parse_mode: 'Markdown' });
        case 'done':
          return ctx.reply(this.#itemDone(parts[0]), { parse_mode: 'Markdown' });
        case 'start':
          return ctx.reply(this.#itemStart(parts[0]), { parse_mode: 'Markdown' });
        case 'block':
          return ctx.reply(this.#itemBlock(parts[0]), { parse_mode: 'Markdown' });
        case 'list':
        case '':
          return ctx.reply(this.#itemList(parts[0]), { parse_mode: 'Markdown' });
        default:
          return ctx.reply(this.#itemHelp(), { parse_mode: 'Markdown' });
      }
    } catch (err) {
      return ctx.reply(`❌ ${err.message}`);
    }
  }

  async #itemAdd(parts) {
    // /item add [sprint-id] <title>
    // If first part matches a sprint ID, use it; otherwise use active sprint
    let sprintId;
    let titleParts = parts;

    const firstPart = parts[0];
    const matchedSprint = this.#tryResolveSprint(firstPart);
    if (matchedSprint) {
      sprintId = matchedSprint.id;
      titleParts = parts.slice(1);
    } else {
      const active = this.#board.getActiveSprint();
      if (!active) throw new Error('No active sprint. Specify a sprint ID.');
      sprintId = active.id;
    }

    const title = titleParts.join(' ').trim();
    if (!title) throw new Error('Usage: `/item add [sprint-id] <title>`');

    const item = this.#board.addItem({ sprintId, title });
    const sprint = this.#board.getSprint(sprintId);

    return (
      `✅ Item added to *${escMd(sprint.name)}*\n\n` +
      `${fmtItem(item)}\n` +
      `ID: \`${item.id.slice(0, 8)}\``
    );
  }

  #itemDone(itemId) {
    if (!itemId) throw new Error('Usage: `/item done <item-id>`');
    const item = this.#resolveItem(itemId);
    const updated = this.#board.completeItem(item.id);
    return `✅ *${escMd(updated.title)}* marked as done!`;
  }

  #itemStart(itemId) {
    if (!itemId) throw new Error('Usage: `/item start <item-id>`');
    const item = this.#resolveItem(itemId);
    const updated = this.#board.startItem(item.id);
    return `🔵 *${escMd(updated.title)}* is now in-progress.`;
  }

  #itemBlock(itemId) {
    if (!itemId) throw new Error('Usage: `/item block <item-id>`');
    const item = this.#resolveItem(itemId);
    const updated = this.#board.blockItem(item.id);
    return `🔴 *${escMd(updated.title)}* marked as blocked.`;
  }

  #itemList(sprintIdOrEmpty) {
    let sprintId;
    if (sprintIdOrEmpty) {
      sprintId = this.#resolveSprint(sprintIdOrEmpty).id;
    } else {
      const active = this.#board.getActiveSprint();
      if (!active) throw new Error('No active sprint. Specify a sprint ID.');
      sprintId = active.id;
    }

    const items = this.#board.listItems(sprintId);
    if (items.length === 0) return 'No items in this sprint yet.';

    const sprint = this.#board.getSprint(sprintId);
    const lines = items.map((i) => `${fmtItem(i)} \`${i.id.slice(0, 8)}\``);
    return `*Items in ${escMd(sprint.name)}*\n\n${lines.join('\n')}`;
  }

  #itemHelp() {
    return (
      `*Item Commands*\n\n` +
      `\`/item add [sprint-id] <title>\` — Add item\n` +
      `\`/item list [sprint-id]\` — List items\n` +
      `\`/item start <id>\` — Start item\n` +
      `\`/item done <id>\` — Complete item\n` +
      `\`/item block <id>\` — Block item`
    );
  }

  // -------------------------------------------------------------------------
  // /board
  // -------------------------------------------------------------------------

  async #handleBoard(ctx) {
    const { rest } = parseArgs(ctx.message?.text);
    try {
      let sprintId;
      if (rest) {
        sprintId = this.#resolveSprint(rest).id;
      } else {
        const active = this.#board.getActiveSprint();
        if (!active) return ctx.reply('No active sprint. Use `/sprint activate <id>`.');
        sprintId = active.id;
      }

      const { sprint, columns, velocity } = this.#board.getBoardView(sprintId);

      const render = (items) =>
        items.length === 0
          ? '_empty_'
          : items.map((i) => `  ${fmtItem(i)}`).join('\n');

      const msg =
        `📋 *Board: ${escMd(sprint.name)}*\n\n` +
        `⬜ *Todo* (${columns.todo.length})\n${render(columns.todo)}\n\n` +
        `🔵 *In-Progress* (${columns['in-progress'].length})\n${render(columns['in-progress'])}\n\n` +
        `✅ *Done* (${columns.done.length})\n${render(columns.done)}\n\n` +
        `🔴 *Blocked* (${columns.blocked.length})\n${render(columns.blocked)}\n\n` +
        `⚡ *Velocity*: ${velocity} pts completed`;

      return ctx.reply(msg, { parse_mode: 'Markdown' });
    } catch (err) {
      return ctx.reply(`❌ ${err.message}`);
    }
  }

  // -------------------------------------------------------------------------
  // /velocity
  // -------------------------------------------------------------------------

  async #handleVelocity(ctx) {
    const { rest } = parseArgs(ctx.message?.text);
    try {
      let sprintId;
      if (rest) {
        sprintId = this.#resolveSprint(rest).id;
      } else {
        const active = this.#board.getActiveSprint();
        if (!active) return ctx.reply('No active sprint.');
        sprintId = active.id;
      }

      const sprint = this.#board.getSprint(sprintId);
      const { committed, completed, percentage } = this.#board.getVelocity(sprintId);

      const bar = buildProgressBar(percentage);
      return ctx.reply(
        `⚡ *Velocity: ${escMd(sprint.name)}*\n\n` +
          `${bar} ${percentage}%\n` +
          `Completed: ${completed} / ${committed} story points`,
        { parse_mode: 'Markdown' }
      );
    } catch (err) {
      return ctx.reply(`❌ ${err.message}`);
    }
  }

  // -------------------------------------------------------------------------
  // Resolution helpers
  // -------------------------------------------------------------------------

  #resolveSprint(idOrName) {
    const sprint = this.#tryResolveSprint(idOrName);
    if (!sprint) throw new Error(`Sprint not found: "${idOrName}"`);
    return sprint;
  }

  #tryResolveSprint(idOrName) {
    if (!idOrName) return null;
    const all = this.#board.listSprints();
    // Try exact ID match (prefix)
    const byId = all.find((s) => s.id.startsWith(idOrName));
    if (byId) return byId;
    // Try case-insensitive name match
    const byName = all.find(
      (s) => s.name.toLowerCase() === idOrName.toLowerCase()
    );
    return byName ?? null;
  }

  #resolveItem(idOrTitle) {
    // Search across all sprints
    const sprints = this.#board.listSprints();
    for (const sprint of sprints) {
      const items = this.#board.listItems(sprint.id);
      const found = items.find(
        (i) =>
          i.id.startsWith(idOrTitle) ||
          i.title.toLowerCase() === idOrTitle.toLowerCase()
      );
      if (found) return found;
    }
    throw new Error(`Item not found: "${idOrTitle}"`);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function buildProgressBar(pct, len = 10) {
  const filled = Math.round((pct / 100) * len);
  return '█'.repeat(filled) + '░'.repeat(len - filled);
}

export default ScrumCommands;
