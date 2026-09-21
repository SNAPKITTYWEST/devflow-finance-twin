//! Command subsystem.
//!
//! Re-exports the `Command` trait from `types` (the canonical definition used
//! throughout the library) and provides a `CommandDispatcher` that routes
//! an incoming text string to the matching registered command.

pub mod agent;
pub mod issue;
pub mod scrum;

// Re-export the trait from types so `crate::commands::Command` works.
pub use crate::types::Command;

use std::collections::HashMap;
use std::sync::Arc;
use tracing::{debug, warn};

use crate::error::{BotError, Result};
use crate::types::{Context, Response};

// ---------------------------------------------------------------------------
// CommandDispatcher
// ---------------------------------------------------------------------------

/// Central registry and dispatcher for `Command` implementations.
///
/// Commands are registered by name (and aliases).  On dispatch the input
/// string is split on whitespace; the first token is matched against the
/// registry and the remainder is passed as the `args` slice.
pub struct CommandDispatcher {
    commands: HashMap<String, Arc<dyn Command>>,
}

impl CommandDispatcher {
    pub fn new() -> Self {
        Self {
            commands: HashMap::new(),
        }
    }

    /// Register a command.  Automatically registers all aliases too.
    pub fn register(&mut self, cmd: Arc<dyn Command>) {
        let name = cmd.name().to_owned();
        debug!("Registering command: {}", name);
        let aliases: Vec<String> = cmd.aliases().iter().map(|&s| s.to_owned()).collect();
        self.commands.insert(name, Arc::clone(&cmd));
        for alias in aliases {
            self.commands.insert(alias, Arc::clone(&cmd));
        }
    }

    /// Register a boxed command (convenience).
    pub fn register_boxed(&mut self, cmd: Box<dyn Command>) {
        self.register(Arc::from(cmd));
    }

    /// Returns `true` if the dispatcher has a handler for `name`.
    pub fn has(&self, name: &str) -> bool {
        self.commands.contains_key(name)
    }

    /// Returns the names of all *primary* registered commands (no aliases).
    pub fn command_names(&self) -> Vec<&str> {
        self.commands.keys().map(String::as_str).collect()
    }

    /// Dispatch an input string.
    ///
    /// The first whitespace-separated token is stripped of a leading `/` and
    /// used as the command name.  The remainder is passed as `args`.
    ///
    /// Returns `Err(BotError::CommandError)` if no matching command is found.
    pub async fn dispatch(&self, ctx: &Context, input: &str) -> Result<Response> {
        let input = input.trim();
        let parts: Vec<&str> = input.split_whitespace().collect();
        let (cmd_name, args) = match parts.split_first() {
            Some((first, rest)) => {
                let name = first.trim_start_matches('/');
                // Strip @BotName suffix if present.
                let name = name.split('@').next().unwrap_or(name);
                (name, rest as &[&str])
            }
            None => return Ok(Response::Empty),
        };

        match self.commands.get(cmd_name) {
            Some(cmd) => {
                debug!("Dispatching to command: {}", cmd.name());
                cmd.execute(ctx, args).await
            }
            None => {
                warn!("Unknown command: {}", cmd_name);
                Err(BotError::CommandError(format!(
                    "Unknown command: /{}",
                    cmd_name
                )))
            }
        }
    }

    /// Try dispatch — like `dispatch` but returns `None` for unknown commands
    /// instead of an error.  The agent uses this to decide whether to fall
    /// back to Ollama.
    pub async fn try_dispatch(&self, ctx: &Context, input: &str) -> Option<Result<Response>> {
        let parts: Vec<&str> = input.trim().split_whitespace().collect();
        let cmd_name = parts.first().map(|s| s.trim_start_matches('/'))?;
        let cmd_name = cmd_name.split('@').next().unwrap_or(cmd_name);
        let cmd = self.commands.get(cmd_name)?;
        let args = if parts.len() > 1 { &parts[1..] } else { &[] as &[&str] };
        Some(cmd.execute(ctx, args).await)
    }

    /// Build a `/help` response listing all registered commands.
    pub fn help_text(&self) -> String {
        let mut lines: Vec<String> = self
            .commands
            .values()
            .map(|c| {
                let usage = if c.usage().is_empty() {
                    String::new()
                } else {
                    format!(" {}", c.usage())
                };
                format!("/{}{} — {}", c.name(), usage, c.description())
            })
            .collect();
        lines.sort();
        lines.dedup();
        lines.join("\n")
    }
}

impl Default for CommandDispatcher {
    fn default() -> Self {
        Self::new()
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use async_trait::async_trait;

    struct EchoCmd;

    #[async_trait]
    impl Command for EchoCmd {
        fn name(&self) -> &str { "echo" }
        fn description(&self) -> &str { "Echo the args" }
        fn aliases(&self) -> &[&str] { &["e"] }
        async fn execute(&self, _ctx: &Context, args: &[&str]) -> Result<Response> {
            Ok(Response::text(args.join(" ")))
        }
    }

    fn dummy_ctx() -> Context {
        use crate::types::Message;
        let msg = Message::new(1, 42, "/echo hello world");
        Context::new(msg)
    }

    #[tokio::test]
    async fn dispatch_by_name() {
        let mut d = CommandDispatcher::new();
        d.register(Arc::new(EchoCmd));
        let ctx = dummy_ctx();
        let resp = d.dispatch(&ctx, "/echo hello world").await.unwrap();
        assert_eq!(resp.as_str(), "hello world");
    }

    #[tokio::test]
    async fn dispatch_by_alias() {
        let mut d = CommandDispatcher::new();
        d.register(Arc::new(EchoCmd));
        let ctx = dummy_ctx();
        let resp = d.dispatch(&ctx, "/e test").await.unwrap();
        assert_eq!(resp.as_str(), "test");
    }

    #[tokio::test]
    async fn unknown_command_is_error() {
        let d = CommandDispatcher::new();
        let ctx = dummy_ctx();
        let result = d.dispatch(&ctx, "/unknown").await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn try_dispatch_none_for_unknown() {
        let d = CommandDispatcher::new();
        let ctx = dummy_ctx();
        assert!(d.try_dispatch(&ctx, "/unknown").await.is_none());
    }
}
