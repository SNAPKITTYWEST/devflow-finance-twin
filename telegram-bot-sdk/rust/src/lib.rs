//! # Telegram Bot SDK
//!
//! A unified, type-safe Telegram bot framework with agent capabilities,
//! integrations, and fault tolerance.

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

pub mod prelude {
    pub use crate::{
        agent::Agent, bot::TelegramBot, commands::Command, error::Result,
        types::{Context, Response, User},
    };
    pub use async_trait::async_trait;
}
