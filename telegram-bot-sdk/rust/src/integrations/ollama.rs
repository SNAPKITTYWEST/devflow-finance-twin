//! Ollama REST API client.
//!
//! Provides an async client for the Ollama `/api/generate` and
//! `/api/chat` endpoints used as the LLM fallback in the agent dispatcher.
//!
//! The client is cheaply cloneable (`Arc` internally) and safe to share
//! across Tokio tasks.

use async_trait::async_trait;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tracing::{debug, warn};

use crate::error::{BotError, Result};
use super::Integration;

// ---------------------------------------------------------------------------
// Request / response types
// ---------------------------------------------------------------------------

/// Body for `POST /api/generate`.
#[derive(Debug, Serialize)]
struct GenerateRequest<'a> {
    model: &'a str,
    prompt: &'a str,
    stream: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    system: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    options: Option<GenerateOptions>,
}

#[derive(Debug, Serialize)]
struct GenerateOptions {
    temperature: f32,
    num_predict: i32,
}

/// Body for `POST /api/chat`.
#[derive(Debug, Serialize)]
struct ChatRequest<'a> {
    model: &'a str,
    messages: Vec<ChatMessage<'a>>,
    stream: bool,
}

#[derive(Debug, Serialize)]
struct ChatMessage<'a> {
    role: &'a str,
    content: &'a str,
}

/// Successful response from `/api/generate`.
#[derive(Debug, Deserialize)]
struct GenerateResponse {
    response: String,
    done: bool,
    #[serde(default)]
    eval_count: u64,
    #[serde(default)]
    eval_duration: u64,
}

/// Successful response from `/api/chat`.
#[derive(Debug, Deserialize)]
struct ChatResponse {
    message: ChatResponseMessage,
    done: bool,
}

#[derive(Debug, Deserialize)]
struct ChatResponseMessage {
    role: String,
    content: String,
}

/// Partial model info from `/api/tags`.
#[derive(Debug, Deserialize)]
struct TagsResponse {
    models: Vec<ModelInfo>,
}

#[derive(Debug, Deserialize)]
struct ModelInfo {
    name: String,
    size: u64,
}

// ---------------------------------------------------------------------------
// OllamaClient
// ---------------------------------------------------------------------------

/// Configuration for the Ollama client.
#[derive(Debug, Clone)]
pub struct OllamaConfig {
    /// Base URL, e.g. `http://localhost:11434`.
    pub base_url: String,
    /// Model to use for completions, e.g. `llama3.2`.
    pub model: String,
    /// System prompt prepended to every generation.
    pub system_prompt: Option<String>,
    /// Sampling temperature (0.0 – 1.0).
    pub temperature: f32,
    /// Maximum tokens to generate.
    pub max_tokens: i32,
    /// HTTP timeout.
    pub timeout: Duration,
}

impl Default for OllamaConfig {
    fn default() -> Self {
        Self {
            base_url: "http://localhost:11434".to_owned(),
            model: "llama3.2".to_owned(),
            system_prompt: Some(
                "You are DevFlow, an AI assistant that helps software teams with project \
                 management, scrum ceremonies, and issue tracking. Be concise and helpful."
                    .to_owned(),
            ),
            temperature: 0.7,
            max_tokens: 512,
            timeout: Duration::from_secs(30),
        }
    }
}

/// Async Ollama REST client.  Clone is cheap (`Arc` inside reqwest `Client`).
#[derive(Debug, Clone)]
pub struct OllamaClient {
    http: Client,
    config: OllamaConfig,
}

impl OllamaClient {
    /// Build from config.
    pub fn new(config: OllamaConfig) -> Result<Self> {
        let http = Client::builder()
            .timeout(config.timeout)
            .build()
            .map_err(|e| BotError::IntegrationError(format!("reqwest build: {}", e)))?;
        Ok(Self { http, config })
    }

    /// Build with defaults, reading `OLLAMA_URL` and `OLLAMA_MODEL` from env.
    pub fn from_env() -> Result<Self> {
        let mut cfg = OllamaConfig::default();
        if let Ok(url) = std::env::var("OLLAMA_URL") {
            cfg.base_url = url;
        }
        if let Ok(model) = std::env::var("OLLAMA_MODEL") {
            cfg.model = model;
        }
        Self::new(cfg)
    }

    /// Low-level generate call (`/api/generate`).
    pub async fn generate(&self, prompt: &str) -> Result<String> {
        let url = format!("{}/api/generate", self.config.base_url);
        let req = GenerateRequest {
            model: &self.config.model,
            prompt,
            stream: false,
            system: self.config.system_prompt.as_deref(),
            options: Some(GenerateOptions {
                temperature: self.config.temperature,
                num_predict: self.config.max_tokens,
            }),
        };

        debug!("Ollama generate: model={} prompt_len={}", self.config.model, prompt.len());

        let resp = self
            .http
            .post(&url)
            .json(&req)
            .send()
            .await
            .map_err(|e| BotError::LlmError(format!("HTTP error: {}", e)))?;

        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            return Err(BotError::LlmError(format!(
                "Ollama returned {}: {}",
                status, body
            )));
        }

        let gen: GenerateResponse = resp
            .json()
            .await
            .map_err(|e| BotError::LlmError(format!("Parse error: {}", e)))?;

        debug!(
            "Ollama done={} eval_count={} eval_duration_ms={}",
            gen.done,
            gen.eval_count,
            gen.eval_duration / 1_000_000
        );

        Ok(gen.response.trim().to_owned())
    }

    /// Chat-style completion (`/api/chat`).
    pub async fn chat(&self, history: &[(&str, &str)]) -> Result<String> {
        let url = format!("{}/api/chat", self.config.base_url);

        let mut messages = Vec::new();
        if let Some(ref sys) = self.config.system_prompt {
            messages.push(ChatMessage { role: "system", content: sys.as_str() });
        }
        for (role, content) in history {
            messages.push(ChatMessage { role, content });
        }

        let req = ChatRequest {
            model: &self.config.model,
            messages,
            stream: false,
        };

        let resp = self
            .http
            .post(&url)
            .json(&req)
            .send()
            .await
            .map_err(|e| BotError::LlmError(format!("HTTP error: {}", e)))?;

        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            return Err(BotError::LlmError(format!(
                "Ollama chat returned {}: {}",
                status, body
            )));
        }

        let chat: ChatResponse = resp
            .json()
            .await
            .map_err(|e| BotError::LlmError(format!("Parse error: {}", e)))?;

        Ok(chat.message.content.trim().to_owned())
    }

    /// Convenience wrapper: single-turn completion.
    pub async fn complete(&self, prompt: &str) -> Result<String> {
        self.generate(prompt).await
    }

    /// Returns the list of locally available model names.
    pub async fn list_models(&self) -> Result<Vec<String>> {
        let url = format!("{}/api/tags", self.config.base_url);
        let resp = self
            .http
            .get(&url)
            .send()
            .await
            .map_err(|e| BotError::LlmError(format!("HTTP error: {}", e)))?;

        if !resp.status().is_success() {
            return Err(BotError::LlmError(format!(
                "Ollama tags returned {}",
                resp.status()
            )));
        }

        let tags: TagsResponse = resp
            .json()
            .await
            .map_err(|e| BotError::LlmError(format!("Parse error: {}", e)))?;

        Ok(tags.models.iter().map(|m| m.name.clone()).collect())
    }

    pub fn base_url(&self) -> &str {
        &self.config.base_url
    }

    pub fn model(&self) -> &str {
        &self.config.model
    }
}

#[async_trait]
impl Integration for OllamaClient {
    fn name(&self) -> &str {
        "ollama"
    }

    async fn health_check(&self) -> Result<()> {
        let url = format!("{}/api/tags", self.config.base_url);
        match self.http.get(&url).send().await {
            Ok(resp) if resp.status().is_success() => Ok(()),
            Ok(resp) => Err(BotError::IntegrationError(format!(
                "Ollama health check returned {}",
                resp.status()
            ))),
            Err(e) => {
                warn!("Ollama health check failed: {}", e);
                Err(BotError::IntegrationError(format!(
                    "Ollama unreachable: {}",
                    e
                )))
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn client_builds_with_defaults() {
        let client = OllamaClient::new(OllamaConfig::default());
        assert!(client.is_ok());
        let c = client.unwrap();
        assert_eq!(c.model(), "llama3.2");
        assert!(c.base_url().starts_with("http://"));
    }

    #[test]
    fn config_from_env() {
        // Just verify it doesn't panic when env vars are absent.
        let _ = OllamaClient::from_env();
    }
}
