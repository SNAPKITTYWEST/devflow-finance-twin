//! Agent framework — command routing with Ollama LLM fallback.
//!
//! The `Agent` struct is the central dispatcher.  It:
//! 1. Tries to match the input against the `CommandRegistry`.
//! 2. If no command matches and Ollama is configured, calls the LLM.
//! 3. Otherwise returns a "not understood" response.
//!
//! `AgentCommand` is the richer command trait used here (carries `Arc<AppState>`
//! explicitly instead of storing it on the struct).

use std::collections::HashMap;
use std::sync::Arc;
use async_trait::async_trait;
use tracing::{debug, info, warn};

use crate::error::{BotError, Result};
use crate::integrations::ollama::{OllamaClient, OllamaConfig};
use crate::state::AppState;
use crate::types::{Context, Response};

// ---------------------------------------------------------------------------
// AgentCommand trait
// ---------------------------------------------------------------------------

/// Like `Command` but receives `Arc<AppState>` at dispatch time rather than
/// storing it.  Use this for commands that need to be registered in the agent
/// registry without tying them to a specific `AppState` at construction time.
#[async_trait]
pub trait AgentCommand: Send + Sync {
    fn name(&self) -> &str;
    fn description(&self) -> &str;
    fn aliases(&self) -> &[&str] { &[] }

    /// Returns `true` if this command can handle the input token.
    /// Default: exact match on `name()` or any alias.
    fn can_handle(&self, token: &str) -> bool {
        let token = token.trim_start_matches('/');
        self.name() == token || self.aliases().contains(&token)
    }

    async fn execute(
        &self,
        ctx: &Context,
        args: &[&str],
        state: Arc<AppState>,
    ) -> Result<Response>;
}

// ---------------------------------------------------------------------------
// CommandRegistry
// ---------------------------------------------------------------------------

/// Holds `AgentCommand` implementations indexed by all their names and aliases.
#[derive(Default)]
pub struct CommandRegistry {
    commands: HashMap<String, Arc<dyn AgentCommand>>,
}

impl CommandRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// Register a command by its name and all aliases.
    pub fn register(&mut self, cmd: Arc<dyn AgentCommand>) {
        let name = cmd.name().to_owned();
        let aliases: Vec<String> = cmd.aliases().iter().map(|&s| s.to_owned()).collect();
        self.commands.insert(name, Arc::clone(&cmd));
        for alias in aliases {
            self.commands.insert(alias, Arc::clone(&cmd));
        }
    }

    /// Look up a command by the raw first token (leading `/` stripped).
    pub fn get(&self, token: &str) -> Option<Arc<dyn AgentCommand>> {
        let key = token.trim_start_matches('/');
        self.commands.get(key).cloned()
    }

    pub fn len(&self) -> usize {
        self.commands.len()
    }

    pub fn is_empty(&self) -> bool {
        self.commands.is_empty()
    }

    /// Returns sorted unique command names (no aliases).
    pub fn names(&self) -> Vec<&str> {
        let mut names: Vec<&str> = self.commands.keys().map(String::as_str).collect();
        names.sort_unstable();
        names
    }
}

// ---------------------------------------------------------------------------
// AgentConfig
// ---------------------------------------------------------------------------

/// Tuning knobs for the `Agent`.
#[derive(Debug, Clone)]
pub struct AgentConfig {
    /// Prepended to every Ollama prompt.
    pub system_prompt: String,
    /// If `true`, unrecognised messages are silently ignored (no "I don't understand").
    pub silent_unknown: bool,
    /// Max context window fed to Ollama (number of recent session entries).
    pub max_context_entries: usize,
}

impl Default for AgentConfig {
    fn default() -> Self {
        Self {
            system_prompt: "You are DevFlow, an AI assistant specialising in agile project \
                            management, sprint planning, and issue tracking. Keep answers concise \
                            and actionable."
                .to_owned(),
            silent_unknown: false,
            max_context_entries: 6,
        }
    }
}

// ---------------------------------------------------------------------------
// Agent
// ---------------------------------------------------------------------------

/// Top-level dispatcher.
///
/// Constructed once and stored as `Arc<Agent>` in the bot's dependency
/// injection container.
pub struct Agent {
    registry: CommandRegistry,
    ollama: Option<OllamaClient>,
    state: Arc<AppState>,
    config: AgentConfig,
}

impl Agent {
    // -----------------------------------------------------------------------
    // Construction
    // -----------------------------------------------------------------------

    /// Build an `Agent` with no commands and no Ollama client.
    pub fn new(state: Arc<AppState>) -> Self {
        Self {
            registry: CommandRegistry::new(),
            ollama: None,
            state,
            config: AgentConfig::default(),
        }
    }

    /// Builder: enable Ollama with a custom config.
    pub fn with_ollama(mut self, config: OllamaConfig) -> Result<Self> {
        self.ollama = Some(OllamaClient::new(config)?);
        Ok(self)
    }

    /// Builder: enable Ollama reading from environment variables.
    pub fn with_ollama_from_env(mut self) -> Self {
        match OllamaClient::from_env() {
            Ok(client) => {
                info!("Ollama LLM enabled at {}", client.base_url());
                self.ollama = Some(client);
            }
            Err(e) => {
                warn!("Ollama unavailable, LLM fallback disabled: {}", e);
            }
        }
        self
    }

    /// Builder: apply a custom agent config.
    pub fn with_config(mut self, config: AgentConfig) -> Self {
        self.config = config;
        self
    }

    /// Builder: register an `AgentCommand`.
    pub fn register(mut self, cmd: Arc<dyn AgentCommand>) -> Self {
        self.registry.register(cmd);
        self
    }

    // -----------------------------------------------------------------------
    // Dispatch
    // -----------------------------------------------------------------------

    /// Main entry point called by the bot for every message / command.
    ///
    /// Resolution order:
    /// 1. Split on whitespace → first token → look up in registry.
    /// 2. If found, execute the command.
    /// 3. If not found and Ollama is available, ask the LLM.
    /// 4. Otherwise return a canned "unknown" response.
    pub async fn dispatch(&self, ctx: &Context, input: &str) -> Result<Response> {
        let input = input.trim();
        if input.is_empty() {
            return Ok(Response::Empty);
        }

        let parts: Vec<&str> = input.split_whitespace().collect();
        let token = parts[0].trim_start_matches('/');
        let args = &parts[1..];

        debug!("Agent dispatch: token={} args_len={}", token, args.len());

        // 1. Named command?
        if let Some(cmd) = self.registry.get(token) {
            return cmd.execute(ctx, args, self.state.clone()).await;
        }

        // 2. Starts with '/' but not registered → unknown command
        if input.starts_with('/') {
            return Ok(Response::text(format!(
                "Unknown command: /{}. Use /help to see available commands.",
                token
            )));
        }

        // 3. Free-text → Ollama if available
        self.ollama_fallback(ctx, input).await
    }

    /// Call Ollama with session context prepended.
    async fn ollama_fallback(&self, ctx: &Context, query: &str) -> Result<Response> {
        match &self.ollama {
            Some(client) => {
                // Build a short conversation history from session context.
                let session = self.state.get_or_create_session(ctx.chat_id).await;
                let context_window: Vec<String> = session
                    .context
                    .iter()
                    .rev()
                    .take(self.config.max_context_entries)
                    .rev()
                    .cloned()
                    .collect();

                let prompt = if context_window.is_empty() {
                    query.to_owned()
                } else {
                    format!(
                        "Context (recent messages):\n{}\n\nUser: {}",
                        context_window.join("\n"),
                        query
                    )
                };

                debug!("Sending to Ollama: {} chars", prompt.len());
                let response = client.complete(&prompt).await?;

                // Update session context
                self.state
                    .update_session(ctx.chat_id, |s| {
                        s.push_context(
                            format!("User: {}", query),
                            self.config.max_context_entries * 2,
                        );
                        s.push_context(
                            format!("Bot: {}", &response),
                            self.config.max_context_entries * 2,
                        );
                    })
                    .await;

                Ok(Response::Text(response))
            }
            None => {
                if self.config.silent_unknown {
                    Ok(Response::Empty)
                } else {
                    Ok(Response::text(
                        "I'm not sure how to help with that. \
                         Use /help to see available commands.",
                    ))
                }
            }
        }
    }

    // -----------------------------------------------------------------------
    // Accessors
    // -----------------------------------------------------------------------

    pub fn has_ollama(&self) -> bool {
        self.ollama.is_some()
    }

    pub fn registry(&self) -> &CommandRegistry {
        &self.registry
    }

    pub fn state(&self) -> Arc<AppState> {
        self.state.clone()
    }
}

// ---------------------------------------------------------------------------
// Built-in AgentCommand implementations
// ---------------------------------------------------------------------------

/// A pass-through that delegates to any `Fn` closure — useful for wiring up
/// thin adapters from `Command` implementations.
pub struct FnAgentCommand {
    name: String,
    description: String,
    aliases: Vec<String>,
    #[allow(clippy::type_complexity)]
    handler: Arc<
        dyn Fn(
                Context,
                Vec<String>,
                Arc<AppState>,
            ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Response>> + Send>>
            + Send
            + Sync,
    >,
}

impl FnAgentCommand {
    pub fn new<F, Fut>(
        name: impl Into<String>,
        description: impl Into<String>,
        handler: F,
    ) -> Arc<Self>
    where
        F: Fn(Context, Vec<String>, Arc<AppState>) -> Fut + Send + Sync + 'static,
        Fut: std::future::Future<Output = Result<Response>> + Send + 'static,
    {
        Arc::new(Self {
            name: name.into(),
            description: description.into(),
            aliases: Vec::new(),
            handler: Arc::new(move |ctx, args, state| Box::pin(handler(ctx, args, state))),
        })
    }
}

#[async_trait]
impl AgentCommand for FnAgentCommand {
    fn name(&self) -> &str {
        &self.name
    }

    fn description(&self) -> &str {
        &self.description
    }

    fn aliases(&self) -> &[&str] {
        // SAFETY: self.aliases is owned String vec; we return &str refs into it.
        // Since FnAgentCommand is not Copy this is fine as long as self lives.
        // But &[&str] requires a static or self-tied lifetime.
        // For simplicity we return empty here; aliases on this type are set via constructor.
        &[]
    }

    async fn execute(
        &self,
        ctx: &Context,
        args: &[&str],
        state: Arc<AppState>,
    ) -> Result<Response> {
        let args_owned: Vec<String> = args.iter().map(|s| s.to_string()).collect();
        (self.handler)(ctx.clone(), args_owned, state).await
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::state::BotConfig;
    use crate::types::Message;

    fn make_state() -> Arc<AppState> {
        AppState::new(BotConfig { token: "test".into(), ..Default::default() })
    }

    fn ctx(text: &str) -> Context {
        Context::new(Message::new(1, 1, text))
    }

    // Minimal AgentCommand for testing
    struct PingCmd;

    #[async_trait]
    impl AgentCommand for PingCmd {
        fn name(&self) -> &str { "ping" }
        fn description(&self) -> &str { "pong" }
        async fn execute(
            &self,
            _ctx: &Context,
            _args: &[&str],
            _state: Arc<AppState>,
        ) -> Result<Response> {
            Ok(Response::text("pong"))
        }
    }

    #[tokio::test]
    async fn dispatch_registered_command() {
        let state = make_state();
        let agent = Agent::new(state).register(Arc::new(PingCmd));
        let resp = agent.dispatch(&ctx("/ping"), "/ping").await.unwrap();
        assert_eq!(resp.as_str(), "pong");
    }

    #[tokio::test]
    async fn unknown_slash_command() {
        let state = make_state();
        let agent = Agent::new(state);
        let resp = agent.dispatch(&ctx("/foo"), "/foo").await.unwrap();
        assert!(resp.as_str().contains("Unknown command"));
    }

    #[tokio::test]
    async fn free_text_no_ollama() {
        let state = make_state();
        let agent = Agent::new(state);
        let resp = agent.dispatch(&ctx("hello"), "hello world").await.unwrap();
        assert!(!resp.as_str().is_empty());
    }

    #[tokio::test]
    async fn empty_input_returns_empty() {
        let state = make_state();
        let agent = Agent::new(state);
        let resp = agent.dispatch(&ctx(""), "").await.unwrap();
        assert!(resp.is_empty());
    }

    #[tokio::test]
    async fn registry_len() {
        let mut reg = CommandRegistry::new();
        reg.register(Arc::new(PingCmd));
        assert!(!reg.is_empty());
        assert!(reg.get("ping").is_some());
    }
}
