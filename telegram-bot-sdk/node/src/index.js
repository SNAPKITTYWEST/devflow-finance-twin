/**
 * index.js — Entry point for the DevFlow Telegram Bot (Node.js / ESM)
 *
 * Loads environment variables via dotenv, validates required config,
 * then boots the DevFlowBot. The module graph is pure ESM; dotenv is loaded
 * via dynamic import so config is available before other imports resolve.
 */

import { createRequire } from 'module';
import { existsSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// ---------------------------------------------------------------------------
// Load .env — must happen before importing bot.mjs so env vars are present
// ---------------------------------------------------------------------------

const require = createRequire(import.meta.url);

const envCandidates = [
  resolve(__dirname, '..', '.env'),       // node/.env  (preferred)
  resolve(__dirname, '..', '..', '.env'), // repo root .env (fallback)
  resolve(process.cwd(), '.env'),         // cwd .env (last resort)
];

const envLoaded = envCandidates.find((p) => existsSync(p));
if (envLoaded) {
  require('dotenv').config({ path: envLoaded });
  console.info(`[startup] Loaded env from: ${envLoaded}`);
} else {
  require('dotenv').config();
}

// ---------------------------------------------------------------------------
// Validate required environment
// ---------------------------------------------------------------------------

const BOT_TOKEN = process.env.BOT_TOKEN;
if (!BOT_TOKEN) {
  console.error(
    '\n[startup] ERROR: BOT_TOKEN is not set.\n' +
      'Steps to fix:\n' +
      '  1. Copy .env.example to .env\n' +
      '  2. Set BOT_TOKEN=<your token> (get one from @BotFather)\n' +
      '  3. Run: npm start\n'
  );
  process.exit(1);
}

// Log runtime configuration (mask sensitive parts of the token)
const maskedToken =
  BOT_TOKEN.slice(0, 8) + '...' + BOT_TOKEN.slice(-4);

console.info('[startup] BOT_TOKEN    :', maskedToken);
console.info('[startup] OLLAMA_HOST  :', process.env.OLLAMA_HOST ?? 'http://localhost:11434 (default)');
console.info('[startup] OLLAMA_MODEL :', process.env.OLLAMA_MODEL ?? 'llama2 (default)');
console.info('[startup] DB_PATH      :', process.env.DB_PATH ?? '(in-memory)');
console.info('[startup] LOG_LEVEL    :', process.env.LOG_LEVEL ?? 'info (default)');
console.info('[startup] Node.js      :', process.version);
console.info('[startup] Platform     :', process.platform, process.arch);

// ---------------------------------------------------------------------------
// Boot bot
// ---------------------------------------------------------------------------

import('./bot.mjs')
  .then(async ({ DevFlowBot }) => {
    const bot = new DevFlowBot({
      token: BOT_TOKEN,
      dbPath: process.env.DB_PATH || undefined,
      ollamaHost: process.env.OLLAMA_HOST,
      ollamaModel: process.env.OLLAMA_MODEL,
    });

    bot
      .onReady(() => {
        console.info('[startup] Bot is live. Send /start in Telegram to begin.');
        console.info('[startup] Press Ctrl+C to stop.');
      })
      .onError((err, ctx) => {
        const user = ctx?.from?.username ?? `user:${ctx?.from?.id ?? 'unknown'}`;
        console.error(`[error] Unhandled error from ${user}:`, err.message);
        if (process.env.LOG_LEVEL === 'debug') {
          console.error(err.stack);
        }
      });

    await bot.launch();
  })
  .catch((err) => {
    console.error('[startup] Fatal error during bot launch:', err.message);
    if (process.env.LOG_LEVEL === 'debug') console.error(err.stack);
    process.exit(1);
  });
