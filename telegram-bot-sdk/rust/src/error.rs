//! Error types for the Telegram Bot SDK

use thiserror::Error;

/// Error type for bot operations
#[derive(Error, Debug, Clone)]
pub enum BotError {
    /// Telegram API error
    #[error("Telegram API error: {0}")]
    TelegramApi(String),

    /// Command execution error
    #[error("Command error: {0}")]
    CommandError(String),

    /// Agent error
    #[error("Agent error: {0}")]
    AgentError(String),

    /// Integration error
    #[error("Integration error: {0}")]
    IntegrationError(String),

    /// LLM error
    #[error("LLM error: {0}")]
    LlmError(String),

    /// State error
    #[error("State error: {0}")]
    StateError(String),

    /// Configuration error
    #[error("Configuration error: {0}")]
    ConfigError(String),

    /// Serialization error
    #[error("Serialization error: {0}")]
    SerializationError(String),

    /// IO error
    #[error("IO error: {0}")]
    IoError(String),

    /// Unknown error
    #[error("Unknown error: {0}")]
    Unknown(String),
}

impl From<serde_json::Error> for BotError {
    fn from(err: serde_json::Error) -> Self {
        BotError::SerializationError(err.to_string())
    }
}

impl From<std::io::Error> for BotError {
    fn from(err: std::io::Error) -> Self {
        BotError::IoError(err.to_string())
    }
}

impl From<reqwest::Error> for BotError {
    fn from(err: reqwest::Error) -> Self {
        BotError::IntegrationError(err.to_string())
    }
}

impl From<sqlx::Error> for BotError {
    fn from(err: sqlx::Error) -> Self {
        BotError::IntegrationError(err.to_string())
    }
}

impl From<uuid::Error> for BotError {
    fn from(err: uuid::Error) -> Self {
        BotError::SerializationError(err.to_string())
    }
}

/// Specialized Result type for bot operations
pub type Result<T> = std::result::Result<T, BotError>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_creation() {
        let err = BotError::CommandError("test".to_string());
        assert!(err.to_string().contains("Command error"));
    }
}
