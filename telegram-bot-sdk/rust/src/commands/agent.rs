//! Agent invocation command — `/ask`.
//!
//! Routes free-text queries to the `Agent` dispatcher which either matches a
//! named command or falls back to Ollama for natural-language answers.

use std::sync::Arc;
use async_trait::async_trait;

use crate::commands::Command;
use crate::error::{BotError, Result};
use crate::types::{Context, Response};

// ---------------------------------------------------------------------------
// AskCommand — /ask
// ---------------------------------------------------------------------------

/// Passes the full argument string to an `AgentDispatch` callback.
///
/// `AgentDispatch` is a simple `Fn` trait-object so we don't need to import
/// the full `Agent` here, avoiding a circular dependency between the
/// `commands` and `agent` modules.
pub type AgentDispatch = Arc<dyn Fn(Context, String) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Response>> + Send>> + Send + Sync>;

pub struct AskCommand {
    dispatch: AgentDispatch,
}

impl AskCommand {
    pub fn new(dispatch: AgentDispatch) -> Self {
        Self { dispatch }
    }
}

#[async_trait]
impl Command for AskCommand {
    fn name(&self) -> &str { "ask" }
    fn description(&self) -> &str { "Ask the AI agent a question" }
    fn usage(&self) -> &str { "<question>" }
    fn aliases(&self) -> &[&str] { &["ai", "query"] }

    async fn execute(&self, ctx: &Context, args: &[&str]) -> Result<Response> {
        if args.is_empty() {
            return Ok(Response::text(
                "What would you like to ask? Usage: /ask <your question>",
            ));
        }
        let query = args.join(" ");
        (self.dispatch)(ctx.clone(), query).await
    }
}

// ---------------------------------------------------------------------------
// ModelInfoCommand — /model
// ---------------------------------------------------------------------------

/// Shows which LLM model is configured.
pub struct ModelInfoCommand {
    model_name: String,
    base_url: String,
}

impl ModelInfoCommand {
    pub fn new(model_name: impl Into<String>, base_url: impl Into<String>) -> Self {
        Self {
            model_name: model_name.into(),
            base_url: base_url.into(),
        }
    }
}

#[async_trait]
impl Command for ModelInfoCommand {
    fn name(&self) -> &str { "model" }
    fn description(&self) -> &str { "Show the configured LLM model" }

    async fn execute(&self, _ctx: &Context, _args: &[&str]) -> Result<Response> {
        Ok(Response::text(format!(
            "LLM Configuration:\nModel: {}\nEndpoint: {}",
            self.model_name, self.base_url
        )))
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::Message;

    fn make_dispatch() -> AgentDispatch {
        Arc::new(|_ctx, query| {
            Box::pin(async move {
                Ok(Response::text(format!("echo: {}", query)))
            })
        })
    }

    #[tokio::test]
    async fn ask_echoes_via_dispatch() {
        let cmd = AskCommand::new(make_dispatch());
        let ctx = Context::new(Message::new(1, 1, "/ask what is scrum"));
        let resp = cmd.execute(&ctx, &["what", "is", "scrum"]).await.unwrap();
        assert_eq!(resp.as_str(), "echo: what is scrum");
    }

    #[tokio::test]
    async fn ask_empty_gives_hint() {
        let cmd = AskCommand::new(make_dispatch());
        let ctx = Context::new(Message::new(1, 1, "/ask"));
        let resp = cmd.execute(&ctx, &[]).await.unwrap();
        assert!(resp.as_str().contains("Usage"));
    }
}
