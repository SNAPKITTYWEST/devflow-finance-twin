//! full_featured.rs — Complete working example of the Telegram Bot SDK.
//!
//! Demonstrates:
//! - AppState construction with BotConfig from environment
//! - Agent setup with Ollama fallback
//! - Custom AgentCommand registration via FnAgentCommand
//! - Persistence store (SQLite) with startup load and periodic flush
//! - Bot wiring and long-poll dispatch loop
//!
//! Run with:
//!   TELOXIDE_TOKEN=<token> cargo run --example full_featured
//!
//! Optional env vars:
//!   OLLAMA_URL=http://localhost:11434
//!   OLLAMA_MODEL=llama3.2
//!   DATABASE_URL=sqlite:./bot.db
//!   RUST_LOG=info

use std::sync::Arc;
use anyhow::Result;
use tracing::{info, warn, error};
use tracing_subscriber::{fmt, EnvFilter};

use telegram_bot_sdk::{
    agent::{Agent, AgentConfig, FnAgentCommand},
    bot::TelegramBot,
    integrations::{
        persistence::PersistenceStore,
        IntegrationRegistry,
    },
    state::{AppState, BotConfig, Sprint, Issue, IssuePriority},
    types::Response,
};

#[tokio::main]
async fn main() -> Result<()> {
    // -----------------------------------------------------------------------
    // Logging
    // -----------------------------------------------------------------------
    fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new("telegram_bot_sdk=debug,info")),
        )
        .compact()
        .init();

    info!("DevFlow Finance Twin — starting up");

    // -----------------------------------------------------------------------
    // Load .env if present
    // -----------------------------------------------------------------------
    let _ = dotenv::dotenv();

    // -----------------------------------------------------------------------
    // Config + AppState
    // -----------------------------------------------------------------------
    let config = BotConfig::default();
    if config.token.is_empty() {
        anyhow::bail!("TELOXIDE_TOKEN or TELEGRAM_BOT_TOKEN is not set");
    }

    let state = AppState::new(config.clone());

    // -----------------------------------------------------------------------
    // Optional persistence — load from disk on startup
    // -----------------------------------------------------------------------
    let persistence: Option<PersistenceStore> = match &config.database_url {
        Some(url) => match PersistenceStore::connect(url).await {
            Ok(store) => {
                info!("Persistence store connected: {}", url);
                let sprints = store.load_sprints().await?;
                let issues = store.load_issues().await?;
                info!("Loaded {} sprints, {} issues from disk", sprints.len(), issues.len());

                for sprint in sprints {
                    let _ = state.create_sprint(sprint).await;
                }
                for issue in issues {
                    let _ = state.create_issue(issue).await;
                }
                Some(store)
            }
            Err(e) => {
                warn!("Persistence unavailable: {}", e);
                None
            }
        },
        None => {
            info!("DATABASE_URL not set — using in-memory state only");
            None
        }
    };

    // -----------------------------------------------------------------------
    // Seed demo data (only when no data exists)
    // -----------------------------------------------------------------------
    seed_demo_data(&state).await;

    // -----------------------------------------------------------------------
    // Integration registry
    // -----------------------------------------------------------------------
    let mut integrations = IntegrationRegistry::new();
    if let Some(ref ps) = persistence {
        integrations.register(Box::new(ps.clone()));
    }

    // -----------------------------------------------------------------------
    // Build the agent — first set up Ollama, then register commands
    // -----------------------------------------------------------------------

    // Step 1: build the base with Ollama (if available).
    let agent_base = Agent::new(state.clone()).with_ollama_from_env();

    // Step 2: configure and register commands.
    let agent_config = AgentConfig {
        system_prompt: "You are DevFlow, an agile project management AI. \
                        Help with sprints, issues, standups, and retrospectives. \
                        Be concise and practical."
            .to_owned(),
        silent_unknown: false,
        max_context_entries: 8,
    };

    // /ping — health check command
    let ping_cmd = FnAgentCommand::new(
        "ping",
        "Health check — replies with pong",
        |_ctx, _args, _state| async move { Ok(Response::text("pong")) },
    );

    // /summary — project overview
    let summary_state = state.clone();
    let summary_cmd = FnAgentCommand::new(
        "summary",
        "Brief project summary",
        move |_ctx, _args, _s| {
            let s = summary_state.clone();
            async move {
                let sprint_count = s.sprint_count().await;
                let issue_count = s.issue_count().await;
                let active_line = s
                    .get_active_sprint()
                    .await
                    .map(|sp| format!("Active: {} ({} days left)", sp.name, sp.days_remaining()))
                    .unwrap_or_else(|| "No active sprint".to_owned());
                Ok(Response::text(format!(
                    "Project Summary\nSprints: {}\nIssues: {}\n{}",
                    sprint_count, issue_count, active_line
                )))
            }
        },
    );

    let agent = Arc::new(
        agent_base
            .with_config(agent_config)
            .register(ping_cmd)
            .register(summary_cmd),
    );

    // -----------------------------------------------------------------------
    // Health check on startup
    // -----------------------------------------------------------------------
    let results = integrations.health_check_all().await;
    for (name, result) in &results {
        match result {
            Ok(_) => info!("Integration '{}': OK", name),
            Err(e) => warn!("Integration '{}': DEGRADED — {}", name, e),
        }
    }

    info!(
        "Agent ready — LLM: {}, Sprints: {}, Issues: {}",
        if agent.has_ollama() { "Ollama" } else { "none" },
        state.sprint_count().await,
        state.issue_count().await,
    );

    // -----------------------------------------------------------------------
    // Periodic persistence flush (background task)
    // -----------------------------------------------------------------------
    if let Some(store) = persistence {
        let flush_state = state.clone();
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(std::time::Duration::from_secs(300));
            loop {
                interval.tick().await;
                if let Err(e) = store.flush_state(&flush_state).await {
                    error!("Flush error: {}", e);
                } else {
                    info!("Periodic state flush complete");
                }
                let removed = flush_state
                    .cleanup_stale_sessions(flush_state.config.session_timeout_secs)
                    .await;
                if removed > 0 {
                    info!("Removed {} stale sessions", removed);
                }
            }
        });
    }

    // -----------------------------------------------------------------------
    // Start the bot (blocks until Ctrl-C)
    // -----------------------------------------------------------------------
    info!("Connecting to Telegram...");
    TelegramBot::from_env(state, agent).run().await;

    Ok(())
}

// ---------------------------------------------------------------------------
// Demo data seeding
// ---------------------------------------------------------------------------

async fn seed_demo_data(state: &AppState) {
    use chrono::{Duration, Utc};

    if state.sprint_count().await > 0 {
        return; // already seeded
    }

    info!("Seeding demo sprint and issues...");

    let now = Utc::now();
    let sprint = Sprint::new("Demo Sprint 1", now - Duration::days(3), now + Duration::days(11));
    let sprint_id = sprint.id;

    if let Ok(created) = state.create_sprint(sprint).await {
        let _ = state.set_active_sprint(created.id).await;

        let demo_issues = vec![
            Issue::new("Set up CI pipeline")
                .with_priority(IssuePriority::High)
                .with_points(5)
                .with_sprint(sprint_id),
            Issue::new("Implement OAuth2 login")
                .with_priority(IssuePriority::High)
                .with_points(8)
                .with_sprint(sprint_id),
            Issue::new("Write unit tests for auth module")
                .with_priority(IssuePriority::Medium)
                .with_points(3)
                .with_sprint(sprint_id),
            Issue::new("Fix flaky integration tests")
                .with_priority(IssuePriority::Medium)
                .with_points(2)
                .with_sprint(sprint_id),
        ];

        for issue in demo_issues {
            let _ = state.create_issue(issue).await;
        }

        info!("Demo sprint created with 4 issues");
    }
}
