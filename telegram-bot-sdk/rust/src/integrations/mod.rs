//! External integration modules.
//!
//! Each sub-module encapsulates a single integration concern:
//! - `ollama` — Local LLM via the Ollama REST API.
//! - `persistence` — SQLite-backed state persistence via sqlx.

pub mod ollama;
pub mod persistence;

pub use ollama::OllamaClient;
pub use persistence::PersistenceStore;

use async_trait::async_trait;
use crate::error::Result;

// ---------------------------------------------------------------------------
// Integration trait
// ---------------------------------------------------------------------------

/// Common health-check interface for all integrations.
#[async_trait]
pub trait Integration: Send + Sync {
    /// Returns the integration name for logging / diagnostics.
    fn name(&self) -> &str;

    /// Performs a lightweight connectivity check.
    /// Returns `Ok(())` if healthy, `Err(...)` otherwise.
    async fn health_check(&self) -> Result<()>;
}

// ---------------------------------------------------------------------------
// IntegrationRegistry
// ---------------------------------------------------------------------------

/// Holds named integration instances so the agent and commands can look them
/// up by name rather than carrying individual fields everywhere.
#[derive(Default)]
pub struct IntegrationRegistry {
    integrations: Vec<Box<dyn Integration>>,
}

impl IntegrationRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// Register an integration.
    pub fn register(&mut self, integration: Box<dyn Integration>) {
        self.integrations.push(integration);
    }

    /// Check health of all registered integrations.  Errors are collected and
    /// returned as a summary string (not short-circuiting).
    pub async fn health_check_all(&self) -> Vec<(String, Result<()>)> {
        let mut results = Vec::new();
        for integration in &self.integrations {
            let result = integration.health_check().await;
            results.push((integration.name().to_owned(), result));
        }
        results
    }

    pub fn len(&self) -> usize {
        self.integrations.len()
    }

    pub fn is_empty(&self) -> bool {
        self.integrations.is_empty()
    }
}
