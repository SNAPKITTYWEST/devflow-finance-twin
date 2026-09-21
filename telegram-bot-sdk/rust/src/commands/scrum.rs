//! Scrum-related command handlers.
//!
//! Commands:
//!  - `/sprint [create|list|activate|complete|status] [args...]`
//!  - `/standup` — generate a daily standup summary
//!  - `/velocity [sprint-id-prefix]` — sprint velocity report
//!  - `/status` — active sprint status at a glance
//!
//! All commands hold an `Arc<AppState>` so they can read/write shared state.

use std::sync::Arc;
use async_trait::async_trait;
use chrono::{Duration, Utc};
use tracing::info;

use crate::commands::Command;
use crate::error::{BotError, Result};
use crate::state::{AppState, Sprint, SprintStatus};
use crate::types::{Context, Response};

// ---------------------------------------------------------------------------
// SprintCommand — /sprint
// ---------------------------------------------------------------------------

/// Handles all `/sprint` subcommands.
pub struct SprintCommand {
    state: Arc<AppState>,
}

impl SprintCommand {
    pub fn new(state: Arc<AppState>) -> Self {
        Self { state }
    }
}

#[async_trait]
impl Command for SprintCommand {
    fn name(&self) -> &str { "sprint" }
    fn description(&self) -> &str { "Sprint management" }
    fn usage(&self) -> &str { "[create|list|activate|complete|status] [args]" }

    async fn execute(&self, ctx: &Context, args: &[&str]) -> Result<Response> {
        let sub = args.first().copied().unwrap_or("list");
        match sub {
            "create" | "new" => self.create(ctx, &args[1..]).await,
            "list" | "ls" => self.list(ctx).await,
            "activate" | "start" => self.activate(ctx, &args[1..]).await,
            "complete" | "close" | "done" => self.complete(ctx, &args[1..]).await,
            "status" | "info" => self.status(ctx, &args[1..]).await,
            "help" | _ => Ok(Response::text(self.sprint_help())),
        }
    }
}

impl SprintCommand {
    async fn create(&self, ctx: &Context, args: &[&str]) -> Result<Response> {
        if args.is_empty() {
            return Ok(Response::text(
                "Usage: /sprint create <name> [duration_days]\n\
                 Example: /sprint create Sprint-42 14",
            ));
        }

        let name = args[0];
        let days: i64 = args.get(1).and_then(|s| s.parse().ok()).unwrap_or(14);
        let now = Utc::now();
        let sprint = Sprint::new(name, now, now + Duration::days(days));
        let id_short = sprint.id.to_string()[..8].to_owned();
        let created = self.state.create_sprint(sprint).await?;

        info!("Sprint created: {} ({})", created.name, created.id);
        Ok(Response::text(format!(
            "Sprint '{}' created!\n\
             ID: {}\n\
             Duration: {} days\n\
             Start: {}\n\
             End: {}\n\n\
             Use /sprint activate {} to start it.",
            created.name,
            id_short,
            days,
            created.start_date.format("%Y-%m-%d"),
            created.end_date.format("%Y-%m-%d"),
            id_short,
        )))
    }

    async fn list(&self, _ctx: &Context) -> Result<Response> {
        let sprints = self.state.list_sprints().await;
        if sprints.is_empty() {
            return Ok(Response::text(
                "No sprints yet. Use /sprint create <name> to create one.",
            ));
        }

        let mut lines = vec!["Sprints:".to_string()];
        for s in &sprints {
            let marker = if s.status == SprintStatus::Active { " [ACTIVE]" } else { "" };
            lines.push(format!(
                "  [{}] {} — {}{}",
                &s.id.to_string()[..8],
                s.name,
                s.status,
                marker,
            ));
        }
        Ok(Response::text(lines.join("\n")))
    }

    async fn activate(&self, _ctx: &Context, args: &[&str]) -> Result<Response> {
        let prefix = args.first().copied().unwrap_or("");
        if prefix.is_empty() {
            return Ok(Response::text("Usage: /sprint activate <id-prefix>"));
        }

        let sprints = self.state.list_sprints().await;
        let sprint = sprints
            .iter()
            .find(|s| s.id.to_string().starts_with(prefix) || s.name == prefix)
            .ok_or_else(|| BotError::StateError(format!("Sprint '{}' not found", prefix)))?;

        let id = sprint.id;
        self.state.set_active_sprint(id).await?;
        info!("Sprint activated: {}", sprint.name);

        Ok(Response::text(format!(
            "Sprint '{}' is now ACTIVE!\n\
             Duration: {} days\n\
             Ends: {}",
            sprint.name,
            sprint.duration_days(),
            sprint.end_date.format("%Y-%m-%d"),
        )))
    }

    async fn complete(&self, _ctx: &Context, args: &[&str]) -> Result<Response> {
        let prefix = args.first().copied();
        let sprint = if let Some(p) = prefix {
            let sprints = self.state.list_sprints().await;
            sprints
                .into_iter()
                .find(|s| s.id.to_string().starts_with(p) || s.name == p)
                .ok_or_else(|| BotError::StateError(format!("Sprint '{}' not found", p)))?
        } else {
            self.state
                .get_active_sprint()
                .await
                .ok_or_else(|| BotError::StateError("No active sprint".to_string()))?
        };

        let id = sprint.id;
        let (committed, completed) = self.state.sprint_velocity(id).await;
        let pct = if committed > 0 { completed * 100 / committed } else { 0 };

        self.state
            .update_sprint(id, |s| {
                s.status = SprintStatus::Completed;
                s.velocity = Some(completed as f64);
            })
            .await?;

        info!("Sprint completed: {}", sprint.name);
        Ok(Response::text(format!(
            "Sprint '{}' completed!\n\
             Story points: {}/{} ({}%)\n\
             Velocity: {} pts",
            sprint.name, completed, committed, pct, completed
        )))
    }

    async fn status(&self, _ctx: &Context, args: &[&str]) -> Result<Response> {
        let prefix = args.first().copied();
        let sprint = if let Some(p) = prefix {
            let sprints = self.state.list_sprints().await;
            sprints
                .into_iter()
                .find(|s| s.id.to_string().starts_with(p) || s.name == p)
                .ok_or_else(|| BotError::StateError(format!("Sprint '{}' not found", p)))?
        } else {
            self.state
                .get_active_sprint()
                .await
                .ok_or_else(|| BotError::StateError("No active sprint".to_string()))?
        };

        let issues = self.state.list_issues_by_sprint(sprint.id).await;
        let done = issues.iter().filter(|i| i.is_complete()).count();
        let (committed, completed) = self.state.sprint_velocity(sprint.id).await;
        let pct = if committed > 0 { completed * 100 / committed } else { 0 };

        Ok(Response::text(format!(
            "Sprint: {}\n\
             Status: {}\n\
             Days remaining: {}\n\
             Issues: {}/{} done\n\
             Story points: {}/{} ({}%)",
            sprint.name,
            sprint.status,
            sprint.days_remaining(),
            done,
            issues.len(),
            completed,
            committed,
            pct,
        )))
    }

    fn sprint_help(&self) -> String {
        "Sprint Commands:\n\
         /sprint create <name> [days] — Create a new sprint\n\
         /sprint list — List all sprints\n\
         /sprint activate <id> — Activate a sprint\n\
         /sprint complete [id] — Complete a sprint\n\
         /sprint status [id] — Sprint details"
            .to_string()
    }
}

// ---------------------------------------------------------------------------
// StandupCommand — /standup
// ---------------------------------------------------------------------------

/// Generates a daily standup digest: what was done, what's in progress,
/// what's blocked, for the active sprint.
pub struct StandupCommand {
    state: Arc<AppState>,
}

impl StandupCommand {
    pub fn new(state: Arc<AppState>) -> Self {
        Self { state }
    }
}

#[async_trait]
impl Command for StandupCommand {
    fn name(&self) -> &str { "standup" }
    fn description(&self) -> &str { "Generate daily standup report for the active sprint" }

    async fn execute(&self, _ctx: &Context, _args: &[&str]) -> Result<Response> {
        let sprint = self.state
            .get_active_sprint()
            .await
            .ok_or_else(|| BotError::StateError("No active sprint".to_string()))?;

        let issues = self.state.list_issues_by_sprint(sprint.id).await;

        use crate::state::IssueStatus;
        let done: Vec<_> = issues
            .iter()
            .filter(|i| i.status == IssueStatus::Done)
            .collect();
        let in_progress: Vec<_> = issues
            .iter()
            .filter(|i| i.status == IssueStatus::InProgress)
            .collect();
        let blocked: Vec<_> = issues
            .iter()
            .filter(|i| i.status == IssueStatus::InReview)
            .collect();
        let todo: Vec<_> = issues
            .iter()
            .filter(|i| i.status == IssueStatus::Todo || i.status == IssueStatus::Backlog)
            .collect();

        let fmt_issues = |items: &[&crate::state::Issue]| -> String {
            if items.is_empty() {
                return "  (none)".to_string();
            }
            items
                .iter()
                .map(|i| {
                    let assignee = i
                        .assignee
                        .as_deref()
                        .map(|a| format!(" (@{})", a))
                        .unwrap_or_default();
                    let pts = i.story_points.map(|p| format!(" [{}pt]", p)).unwrap_or_default();
                    format!("  - {}{}{}", i.title, pts, assignee)
                })
                .collect::<Vec<_>>()
                .join("\n")
        };

        let (committed, completed) = self.state.sprint_velocity(sprint.id).await;
        let pct = if committed > 0 { completed * 100 / committed } else { 0 };

        Ok(Response::text(format!(
            "Daily Standup — {}\n\
             Date: {}\n\
             Days remaining: {}\n\
             Velocity: {}/{} pts ({}%)\n\n\
             DONE:\n{}\n\n\
             IN PROGRESS:\n{}\n\n\
             TODO:\n{}\n\n\
             BLOCKED:\n{}",
            sprint.name,
            Utc::now().format("%Y-%m-%d"),
            sprint.days_remaining(),
            completed, committed, pct,
            fmt_issues(&done),
            fmt_issues(&in_progress),
            fmt_issues(&todo),
            fmt_issues(&blocked),
        )))
    }
}

// ---------------------------------------------------------------------------
// VelocityCommand — /velocity
// ---------------------------------------------------------------------------

pub struct VelocityCommand {
    state: Arc<AppState>,
}

impl VelocityCommand {
    pub fn new(state: Arc<AppState>) -> Self {
        Self { state }
    }
}

#[async_trait]
impl Command for VelocityCommand {
    fn name(&self) -> &str { "velocity" }
    fn description(&self) -> &str { "Show sprint velocity metrics" }
    fn usage(&self) -> &str { "[sprint-id]" }

    async fn execute(&self, _ctx: &Context, args: &[&str]) -> Result<Response> {
        let sprint = if let Some(prefix) = args.first().copied() {
            let sprints = self.state.list_sprints().await;
            sprints
                .into_iter()
                .find(|s| s.id.to_string().starts_with(prefix) || s.name == prefix)
                .ok_or_else(|| BotError::StateError(format!("Sprint '{}' not found", prefix)))?
        } else {
            self.state
                .get_active_sprint()
                .await
                .ok_or_else(|| BotError::StateError("No active sprint".to_string()))?
        };

        let (committed, completed) = self.state.sprint_velocity(sprint.id).await;
        let pct = if committed > 0 { completed * 100 / committed } else { 0u32 };
        let bar = progress_bar(pct as usize, 20);

        Ok(Response::text(format!(
            "Velocity — {}\n\
             {} {}%\n\
             Completed: {} / {} story points\n\
             Status: {}",
            sprint.name,
            bar,
            pct,
            completed,
            committed,
            sprint.status,
        )))
    }
}

// ---------------------------------------------------------------------------
// ScrumDispatcher — convenience facade used by bot.rs
// ---------------------------------------------------------------------------

/// Thin dispatcher that instantiates the right scrum command and executes it.
/// Used by `bot.rs` to avoid importing every command struct individually.
pub struct ScrumDispatcher {
    state: Arc<AppState>,
}

impl ScrumDispatcher {
    pub fn new(state: Arc<AppState>) -> Self {
        Self { state }
    }

    pub async fn dispatch(&self, ctx: &Context, args: &[&str]) -> Result<Response> {
        SprintCommand::new(self.state.clone()).execute(ctx, args).await
    }

    pub async fn standup(&self, ctx: &Context) -> Result<Response> {
        StandupCommand::new(self.state.clone()).execute(ctx, &[]).await
    }

    pub async fn velocity(&self, ctx: &Context) -> Result<Response> {
        VelocityCommand::new(self.state.clone()).execute(ctx, &[]).await
    }

    pub async fn status(&self, ctx: &Context) -> Result<Response> {
        SprintCommand::new(self.state.clone()).execute(ctx, &["status"]).await
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn progress_bar(pct: usize, width: usize) -> String {
    let filled = (pct.min(100) * width) / 100;
    let empty = width.saturating_sub(filled);
    format!("[{}{}]", "#".repeat(filled), ".".repeat(empty))
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
        AppState::new(BotConfig {
            token: "test".into(),
            ..Default::default()
        })
    }

    fn ctx() -> Context {
        Context::new(Message::new(1, 1, "/sprint"))
    }

    #[tokio::test]
    async fn sprint_create_and_list() {
        let state = make_state();
        let cmd = SprintCommand::new(state.clone());

        let resp = cmd.execute(&ctx(), &["create", "Alpha", "7"]).await.unwrap();
        assert!(resp.as_str().contains("Alpha"));

        let list = cmd.execute(&ctx(), &["list"]).await.unwrap();
        assert!(list.as_str().contains("Alpha"));
    }

    #[tokio::test]
    async fn standup_no_active_sprint_error() {
        let state = make_state();
        let cmd = StandupCommand::new(state);
        let result = cmd.execute(&ctx(), &[]).await;
        assert!(result.is_err());
    }

    #[test]
    fn progress_bar_100() {
        let bar = progress_bar(100, 10);
        assert_eq!(bar, "[##########]");
    }

    #[test]
    fn progress_bar_0() {
        let bar = progress_bar(0, 10);
        assert_eq!(bar, "[..........]");
    }
}
