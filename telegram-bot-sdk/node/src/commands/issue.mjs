/**
 * commands/issue.mjs — Issue tracking Telegram commands
 *
 * Commands:
 *  /issue  [list|add|get|close] [args]  — Issue management
 *  /bug    <title> [description]         — Quick bug report shorthand
 *  /resolve <issue-id>                   — Mark issue as resolved
 */

import { v4 as uuidv4 } from 'uuid';

// ---------------------------------------------------------------------------
// Domain types
// ---------------------------------------------------------------------------

/**
 * @typedef {'open' | 'in-progress' | 'resolved' | 'closed' | 'wontfix'} IssueStatus
 * @typedef {'bug' | 'feature' | 'question' | 'docs' | 'security'} IssueType
 * @typedef {'critical' | 'high' | 'medium' | 'low'} IssuePriority
 */

/**
 * @typedef {Object} Issue
 * @property {string} id
 * @property {string} title
 * @property {string} description
 * @property {IssueStatus} status
 * @property {IssueType} type
 * @property {IssuePriority} priority
 * @property {string} reportedBy  Telegram username or user ID
 * @property {string|null} assignee
 * @property {string} createdAt
 * @property {string|null} resolvedAt
 * @property {string[]} labels
 * @property {Array<{author: string, text: string, timestamp: string}>} comments
 */

// ---------------------------------------------------------------------------
// IssueTracker (in-process store used by IssueCommands)
// ---------------------------------------------------------------------------

class IssueTracker {
  /** @type {Map<string, Issue>} */
  #issues = new Map();

  /** @type {import('../lib/persistence.mjs').PersistenceManager|null} */
  #persistence;

  /** @param {{ persistence?: import('../lib/persistence.mjs').PersistenceManager }} opts */
  constructor({ persistence = null } = {}) {
    this.#persistence = persistence;
    if (persistence) this.#load();
  }

  #save() {
    if (!this.#persistence) return;
    this.#persistence.save('issues', Object.fromEntries(this.#issues));
  }

  #load() {
    const data = this.#persistence.load('issues');
    if (!data) return;
    for (const [k, v] of Object.entries(data)) {
      this.#issues.set(k, v);
    }
  }

  /**
   * @param {{ title: string, description?: string, type?: IssueType,
   *           priority?: IssuePriority, reportedBy: string }} opts
   * @returns {Issue}
   */
  create({ title, description = '', type = 'bug', priority = 'medium', reportedBy }) {
    if (!title?.trim()) throw new Error('Issue title is required');
    const id = uuidv4();
    /** @type {Issue} */
    const issue = {
      id,
      title: title.trim(),
      description: description.trim(),
      status: 'open',
      type,
      priority,
      reportedBy,
      assignee: null,
      createdAt: new Date().toISOString(),
      resolvedAt: null,
      labels: [],
      comments: [],
    };
    this.#issues.set(id, issue);
    this.#save();
    return issue;
  }

  /** @param {string} id @returns {Issue|null} */
  get(id) {
    // Support short IDs (first 8 chars)
    for (const [k, v] of this.#issues) {
      if (k === id || k.startsWith(id)) return v;
    }
    return null;
  }

  /**
   * @param {{ status?: IssueStatus, type?: IssueType, priority?: IssuePriority }} opts
   * @returns {Issue[]}
   */
  list({ status, type, priority } = {}) {
    let issues = Array.from(this.#issues.values());
    if (status) issues = issues.filter((i) => i.status === status);
    if (type) issues = issues.filter((i) => i.type === type);
    if (priority) issues = issues.filter((i) => i.priority === priority);
    return issues.sort(
      (a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
    );
  }

  /** @param {string} id @returns {Issue} */
  resolve(id) {
    const issue = this.#require(id);
    issue.status = 'resolved';
    issue.resolvedAt = new Date().toISOString();
    this.#save();
    return issue;
  }

  /** @param {string} id @returns {Issue} */
  close(id) {
    const issue = this.#require(id);
    issue.status = 'closed';
    this.#save();
    return issue;
  }

  /** @param {string} id @returns {Issue} */
  reopen(id) {
    const issue = this.#require(id);
    issue.status = 'open';
    issue.resolvedAt = null;
    this.#save();
    return issue;
  }

  /**
   * @param {string} id
   * @param {Partial<Issue>} patch
   * @returns {Issue}
   */
  update(id, patch) {
    const issue = this.#require(id);
    const forbidden = ['id', 'createdAt', 'reportedBy'];
    for (const k of forbidden) delete patch[k];
    Object.assign(issue, patch);
    this.#save();
    return issue;
  }

  /**
   * @param {string} id
   * @param {{ author: string, text: string }} comment
   * @returns {Issue}
   */
  addComment(id, { author, text }) {
    const issue = this.#require(id);
    issue.comments.push({ author, text, timestamp: new Date().toISOString() });
    this.#save();
    return issue;
  }

  #require(id) {
    const issue = this.get(id);
    if (!issue) throw new Error(`Issue not found: ${id}`);
    return issue;
  }
}

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

const STATUS_EMOJI = {
  open: '🔴',
  'in-progress': '🔵',
  resolved: '✅',
  closed: '⬛',
  wontfix: '🚫',
};

const PRIORITY_EMOJI = {
  critical: '🚨',
  high: '🔥',
  medium: '⚠️',
  low: '💡',
};

const TYPE_EMOJI = {
  bug: '🐛',
  feature: '✨',
  question: '❓',
  docs: '📄',
  security: '🔒',
};

function escMd(text) {
  return String(text).replace(/[_*[\]()~`>#+=|{}.!\\-]/g, (c) => `\\${c}`);
}

function fmtIssue(issue, short = false) {
  const se = STATUS_EMOJI[issue.status] ?? '•';
  const pe = PRIORITY_EMOJI[issue.priority] ?? '';
  const te = TYPE_EMOJI[issue.type] ?? '';
  const id = `\`${issue.id.slice(0, 8)}\``;

  if (short) {
    return `${se}${pe}${te} ${escMd(issue.title)} ${id}`;
  }

  const assignee = issue.assignee ? `\nAssignee: @${escMd(issue.assignee)}` : '';
  const reporter = `\nReporter: ${escMd(issue.reportedBy)}`;
  const created = `\nCreated: ${issue.createdAt.slice(0, 10)}`;
  const resolved = issue.resolvedAt
    ? `\nResolved: ${issue.resolvedAt.slice(0, 10)}`
    : '';
  const desc = issue.description
    ? `\n\n${escMd(issue.description.slice(0, 300))}`
    : '';

  return (
    `${se} *${escMd(issue.title)}* ${id}\n` +
    `Type: ${te} ${issue.type} | Priority: ${pe} ${issue.priority}${assignee}${reporter}${created}${resolved}${desc}`
  );
}

// ---------------------------------------------------------------------------
// IssueCommands
// ---------------------------------------------------------------------------

export class IssueCommands {
  #tracker;

  /** @param {{ persistence?: import('../lib/persistence.mjs').PersistenceManager }} opts */
  constructor({ persistence } = {}) {
    this.#tracker = new IssueTracker({ persistence });
  }

  /**
   * Register all issue commands with a Telegraf bot.
   * @param {import('telegraf').Telegraf} bot
   */
  register(bot) {
    bot.command('issue', (ctx) => this.#handleIssue(ctx));
    bot.command('bug', (ctx) => this.#handleBug(ctx));
    bot.command('resolve', (ctx) => this.#handleResolve(ctx));
  }

  // -------------------------------------------------------------------------
  // /issue
  // -------------------------------------------------------------------------

  async #handleIssue(ctx) {
    const rawText = ctx.message?.text ?? '';
    const parts = rawText.replace(/^\/\w+\s*/, '').trim().split(/\s+/);
    const sub = parts[0]?.toLowerCase() ?? '';

    try {
      switch (sub) {
        case 'add':
        case 'new': {
          const title = parts.slice(1).join(' ').trim();
          if (!title) return ctx.reply('Usage: `/issue add <title>`', { parse_mode: 'Markdown' });
          const reporter = ctx.from?.username ?? String(ctx.from?.id ?? 'unknown');
          const issue = this.#tracker.create({ title, reportedBy: reporter });
          return ctx.reply(
            `✅ Issue created\\!\n\n${fmtIssue(issue)}`,
            { parse_mode: 'Markdown' }
          );
        }

        case 'get':
        case 'show': {
          const id = parts[1];
          if (!id) return ctx.reply('Usage: `/issue get <id>`', { parse_mode: 'Markdown' });
          const issue = this.#tracker.get(id);
          if (!issue) return ctx.reply(`Issue not found: ${id}`);
          return ctx.reply(fmtIssue(issue), { parse_mode: 'Markdown' });
        }

        case 'close': {
          const id = parts[1];
          if (!id) return ctx.reply('Usage: `/issue close <id>`', { parse_mode: 'Markdown' });
          const issue = this.#tracker.close(id);
          return ctx.reply(`⬛ Issue *${escMd(issue.title)}* closed.`, { parse_mode: 'Markdown' });
        }

        case 'reopen': {
          const id = parts[1];
          if (!id) return ctx.reply('Usage: `/issue reopen <id>`', { parse_mode: 'Markdown' });
          const issue = this.#tracker.reopen(id);
          return ctx.reply(`🔴 Issue *${escMd(issue.title)}* reopened.`, { parse_mode: 'Markdown' });
        }

        case 'assign': {
          const id = parts[1];
          const assignee = parts[2]?.replace('@', '');
          if (!id || !assignee) return ctx.reply('Usage: `/issue assign <id> <@user>`', { parse_mode: 'Markdown' });
          const issue = this.#tracker.update(id, { assignee });
          return ctx.reply(`👤 Issue assigned to @${escMd(assignee)}.`, { parse_mode: 'Markdown' });
        }

        case 'list':
        case '': {
          const statusFilter = parts[1];
          const validStatuses = ['open', 'in-progress', 'resolved', 'closed', 'wontfix'];
          const status = validStatuses.includes(statusFilter) ? statusFilter : 'open';
          const issues = this.#tracker.list({ status });

          if (issues.length === 0) {
            return ctx.reply(`No ${status} issues found.`);
          }

          const lines = issues
            .slice(0, 15)
            .map((i) => fmtIssue(i, true));
          const more = issues.length > 15 ? `\n_...and ${issues.length - 15} more_` : '';
          return ctx.reply(
            `*Issues (${status})* — ${issues.length} total\n\n${lines.join('\n')}${more}`,
            { parse_mode: 'Markdown' }
          );
        }

        default:
          return ctx.reply(this.#issueHelp(), { parse_mode: 'Markdown' });
      }
    } catch (err) {
      return ctx.reply(`❌ ${err.message}`);
    }
  }

  // -------------------------------------------------------------------------
  // /bug
  // -------------------------------------------------------------------------

  async #handleBug(ctx) {
    const rawText = ctx.message?.text ?? '';
    const content = rawText.replace(/^\/\w+\s*/, '').trim();

    if (!content) {
      return ctx.reply(
        '🐛 *Report a bug*\n\nUsage: `/bug <title> | <description>`\n\nExample:\n`/bug Login fails on mobile | The login button is unresponsive on iOS 17`',
        { parse_mode: 'Markdown' }
      );
    }

    const [title, ...descParts] = content.split('|');
    const description = descParts.join('|').trim();
    const reporter = ctx.from?.username ?? String(ctx.from?.id ?? 'unknown');

    try {
      const issue = this.#tracker.create({
        title: title.trim(),
        description,
        type: 'bug',
        priority: 'high',
        reportedBy: reporter,
      });

      return ctx.reply(
        `🐛 Bug reported\\!\n\n${fmtIssue(issue)}`,
        { parse_mode: 'Markdown' }
      );
    } catch (err) {
      return ctx.reply(`❌ ${err.message}`);
    }
  }

  // -------------------------------------------------------------------------
  // /resolve
  // -------------------------------------------------------------------------

  async #handleResolve(ctx) {
    const rawText = ctx.message?.text ?? '';
    const id = rawText.replace(/^\/\w+\s*/, '').trim();

    if (!id) {
      return ctx.reply('Usage: `/resolve <issue-id>`', { parse_mode: 'Markdown' });
    }

    try {
      const issue = this.#tracker.resolve(id);
      return ctx.reply(
        `✅ Issue *${escMd(issue.title)}* resolved\\!`,
        { parse_mode: 'Markdown' }
      );
    } catch (err) {
      return ctx.reply(`❌ ${err.message}`);
    }
  }

  // -------------------------------------------------------------------------
  // Help
  // -------------------------------------------------------------------------

  #issueHelp() {
    return (
      `*Issue Tracking Commands*\n\n` +
      `\`/issue list [status]\` — List issues (default: open)\n` +
      `\`/issue add <title>\` — Create a new issue\n` +
      `\`/issue get <id>\` — Show issue details\n` +
      `\`/issue close <id>\` — Close an issue\n` +
      `\`/issue reopen <id>\` — Reopen an issue\n` +
      `\`/issue assign <id> @user\` — Assign issue\n` +
      `\`/bug <title> [| description]\` — Quick bug report\n` +
      `\`/resolve <id>\` — Resolve an issue`
    );
  }
}

export default IssueCommands;
