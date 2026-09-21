//! basic_bot.rs — Minimal bot setup example.
//!
//! Shows the smallest possible runnable bot with in-memory state and
//! no LLM integration.
//!
//! Run with:
//!   TELOXIDE_TOKEN=<token> cargo run --example basic_bot

use std::sync::Arc;
use telegram_bot_sdk::{agent::Agent, bot::TelegramBot, state::AppState};

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt().compact().init();
    let _ = dotenv::dotenv();

    let state = AppState::from_env();
    let agent = Arc::new(Agent::new(state.clone()).with_ollama_from_env());

    TelegramBot::from_env(state, agent).run().await;
}
