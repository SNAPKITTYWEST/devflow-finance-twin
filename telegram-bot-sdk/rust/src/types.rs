//! Common types used throughout the Telegram Bot SDK.
//!
//! Defines the core Message/User/Context data model, the Response enum,
//! and the Command trait that all command handlers implement.

use std::collections::HashMap;
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::error::Result;

// ---------------------------------------------------------------------------
// User
// ---------------------------------------------------------------------------

/// A Telegram user, deserialized from the bot's incoming updates.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct User {
    /// Telegram user ID (i64 to avoid sign issues with large IDs).
    pub id: i64,
    /// Optional @username (no leading @).
    pub username: Option<String>,
    pub first_name: String,
    pub last_name: Option<String>,
    pub is_bot: bool,
    pub language_code: Option<String>,
}

impl User {
    /// Construct a minimal user for tests / direct creation.
    pub fn new(id: i64, first_name: impl Into<String>) -> Self {
        Self {
            id,
            username: None,
            first_name: first_name.into(),
            last_name: None,
            is_bot: false,
            language_code: None,
        }
    }

    /// Returns @username if set, otherwise "FirstName LastName".
    pub fn display_name(&self) -> String {
        if let Some(ref u) = self.username {
            format!("@{}", u)
        } else if let Some(ref ln) = self.last_name {
            format!("{} {}", self.first_name, ln)
        } else {
            self.first_name.clone()
        }
    }

    /// Returns the @mention string used in Telegram messages.
    pub fn mention(&self) -> String {
        match &self.username {
            Some(u) => format!("@{}", u),
            None => self.first_name.clone(),
        }
    }
}

impl std::fmt::Display for User {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.display_name())
    }
}

// ---------------------------------------------------------------------------
// Message
// ---------------------------------------------------------------------------

/// A Telegram message carried through the handler pipeline.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    /// Telegram message ID (unique per chat).
    pub id: i32,
    /// Text content of the message, if any.
    pub text: Option<String>,
    /// The sender; None for channel posts.
    pub from: Option<User>,
    /// Chat where the message was sent.
    pub chat_id: i64,
    /// UTC timestamp of the message.
    pub date: DateTime<Utc>,
    /// The message this is a reply to, if any.
    pub reply_to: Option<Box<Message>>,
}

impl Message {
    /// Convenience constructor for plain-text messages.
    pub fn new(id: i32, chat_id: i64, text: impl Into<String>) -> Self {
        Self {
            id,
            text: Some(text.into()),
            from: None,
            chat_id,
            date: Utc::now(),
            reply_to: None,
        }
    }

    /// Returns the text or empty string.
    pub fn text(&self) -> &str {
        self.text.as_deref().unwrap_or("")
    }

    /// Returns true if the message text starts with '/'.
    pub fn is_command(&self) -> bool {
        self.text.as_deref().map_or(false, |t| t.starts_with('/'))
    }

    /// Parses the first whitespace-separated token as the command name (without '/').
    pub fn command_name(&self) -> Option<&str> {
        let text = self.text.as_deref()?;
        if !text.starts_with('/') {
            return None;
        }
        let word = text.split_whitespace().next()?;
        // Strip the leading '/' and any @BotName suffix
        Some(word.trim_start_matches('/').split('@').next().unwrap_or(word))
    }

    /// Returns everything after the command name (i.e. the arguments string).
    pub fn command_args(&self) -> &str {
        let text = self.text.as_deref().unwrap_or("");
        match text.find(char::is_whitespace) {
            Some(pos) => text[pos..].trim(),
            None => "",
        }
    }
}

// ---------------------------------------------------------------------------
// Context
// ---------------------------------------------------------------------------

/// Execution context passed to every command handler.
///
/// Carries the triggering message, the resolved user, the chat ID, a
/// per-request session UUID, and an arbitrary metadata map for middleware
/// to attach extra data.
#[derive(Debug, Clone)]
pub struct Context {
    pub message: Message,
    pub user: Option<User>,
    pub chat_id: i64,
    /// Per-request ID — useful for distributed tracing / audit logs.
    pub request_id: Uuid,
    /// Arbitrary key/value metadata attached by middleware.
    pub metadata: HashMap<String, String>,
}

impl Context {
    /// Build a Context from a Message, extracting the user and chat_id.
    pub fn new(message: Message) -> Self {
        let chat_id = message.chat_id;
        let user = message.from.clone();
        Self {
            message,
            user,
            chat_id,
            request_id: Uuid::new_v4(),
            metadata: HashMap::new(),
        }
    }

    /// Builder helper for attaching metadata.
    pub fn with_metadata(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.metadata.insert(key.into(), value.into());
        self
    }

    /// Returns the text of the underlying message.
    pub fn text(&self) -> &str {
        self.message.text()
    }

    /// Returns a display name for the sender, or "Unknown".
    pub fn sender_name(&self) -> &str {
        self.user
            .as_ref()
            .map(|u| u.first_name.as_str())
            .unwrap_or("Unknown")
    }
}

// ---------------------------------------------------------------------------
// Response
// ---------------------------------------------------------------------------

/// All the ways a command can reply to the user.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Response {
    /// Plain text, sent as-is.
    Text(String),
    /// Telegram MarkdownV2 formatted text.
    Markdown(String),
    /// HTML formatted text.
    Html(String),
    /// No reply at all (silent handling).
    Empty,
    /// An error message to show the user.
    Error(String),
    /// Multiple messages sent in sequence.
    MultipleMessages(Vec<Response>),
}

impl Response {
    pub fn text(s: impl Into<String>) -> Self {
        Self::Text(s.into())
    }

    pub fn markdown(s: impl Into<String>) -> Self {
        Self::Markdown(s.into())
    }

    pub fn html(s: impl Into<String>) -> Self {
        Self::Html(s.into())
    }

    pub fn error(s: impl Into<String>) -> Self {
        Self::Error(s.into())
    }

    pub fn is_empty(&self) -> bool {
        matches!(self, Self::Empty)
    }

    /// Returns the inner text regardless of formatting mode.
    pub fn as_str(&self) -> &str {
        match self {
            Self::Text(s) | Self::Markdown(s) | Self::Html(s) | Self::Error(s) => s.as_str(),
            Self::Empty => "",
            Self::MultipleMessages(_) => "[multiple messages]",
        }
    }
}

impl std::fmt::Display for Response {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

impl From<String> for Response {
    fn from(s: String) -> Self {
        Self::Text(s)
    }
}

impl From<&str> for Response {
    fn from(s: &str) -> Self {
        Self::Text(s.to_owned())
    }
}

// ---------------------------------------------------------------------------
// Command trait
// ---------------------------------------------------------------------------

/// The core trait every command handler must implement.
///
/// Commands carry their own state (e.g. `Arc<AppState>`) as struct fields, so
/// the `execute` signature only needs the invocation context and the raw
/// argument tokens that follow the command name.
#[async_trait]
pub trait Command: Send + Sync {
    /// The primary command name, e.g. "sprint".
    fn name(&self) -> &str;

    /// One-line description shown in /help.
    fn description(&self) -> &str;

    /// Optional usage hint shown next to the description.
    fn usage(&self) -> &str {
        ""
    }

    /// Alternative names that also trigger this command.
    fn aliases(&self) -> &[&str] {
        &[]
    }

    /// Execute the command and return a `Response`.
    ///
    /// `args` is the whitespace-split slice of tokens after the command name.
    async fn execute(&self, ctx: &Context, args: &[&str]) -> Result<Response>;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn user_display_name_with_username() {
        let u = User {
            id: 1,
            username: Some("alice".into()),
            first_name: "Alice".into(),
            last_name: None,
            is_bot: false,
            language_code: None,
        };
        assert_eq!(u.display_name(), "@alice");
    }

    #[test]
    fn user_display_name_fallback() {
        let u = User::new(2, "Bob");
        assert_eq!(u.display_name(), "Bob");
    }

    #[test]
    fn message_command_parsing() {
        let m = Message::new(1, 100, "/sprint create My Sprint");
        assert!(m.is_command());
        assert_eq!(m.command_name(), Some("sprint"));
        assert_eq!(m.command_args(), "create My Sprint");
    }

    #[test]
    fn response_display() {
        let r = Response::text("hello");
        assert_eq!(r.to_string(), "hello");
        assert!(!r.is_empty());
        assert!(Response::Empty.is_empty());
    }

    #[test]
    fn context_construction() {
        let msg = Message::new(1, 42, "/help");
        let ctx = Context::new(msg.clone());
        assert_eq!(ctx.chat_id, 42);
        assert_eq!(ctx.text(), "/help");
    }
}
