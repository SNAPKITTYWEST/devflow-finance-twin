//! # Telegram Bot SDK
//!
//! A unified, type-safe Telegram bot framework with agent capabilities,
//! scrum/issue integrations, Ollama LLM fallback, and SQLite persistence.
//!
//! ## Quick Start
//!
//! ```no_run
//! use std::sync::Arc;
//! use telegram_bot_sdk::{agent::Agent, bot::TelegramBot, state::AppState};
//!
//! #[tokio::main]
//! async fn main() {
//!     let state = AppState::from_env();
//!     let agent = Arc::new(Agent::new(state.clone()).with_ollama_from_env());
//!     TelegramBot::from_env(state, agent).run().await;
//! }
//! ```

pub mod agent;
pub mod bot;
pub mod commands;
pub mod error;
pub mod integrations;
pub mod state;
pub mod types;

pub use agent::Agent;
pub use bot::TelegramBot;
pub use commands::Command;
pub use error::{BotError, Result};
pub use types::{Context, Response, User};

/// Convenience re-exports for the most common types.
pub mod prelude {
    pub use crate::{
        agent::{Agent, AgentCommand, AgentConfig},
        bot::TelegramBot,
        commands::Command,
        error::{BotError, Result},
        integrations::Integration,
        state::{AppState, BotConfig, Issue, IssueStatus, IssuePriority, Sprint, SprintStatus},
        types::{Context, Message, Response, User},
    };
    pub use async_trait::async_trait;
}
