//! Issue tracking command handlers.
//!
//! Commands:
//!  - `/issue create <title> [--priority low|medium|high|critical] [--points N]`
//!  - `/issue list [--sprint id] [--status status] [--assignee user]`
//!  - `/issue update <id-prefix> [--status ...] [--assignee ...] [--points N]`
//!  - `/issue close <id-prefix>`
//!  - `/issue show <id-prefix>`

use std::sync::Arc;
use async_trait::async_trait;
use tracing::info;

use crate::commands::Command;
use crate::error::{BotError, Result};
use crate::state::{AppState, Issue, IssueStatus, IssuePriority};
use crate::types::{Context, Response};

// ---------------------------------------------------------------------------
// IssueCommand — /issue
// ---------------------------------------------------------------------------

pub struct IssueCommand {
    state: Arc<AppState>,
}

impl IssueCommand {
    pub fn new(state: Arc<AppState>) -> Self {
        Self { state }
    }
}

#[async_trait]
impl Command for IssueCommand {
    fn name(&self) -> &str { "issue" }
    fn description(&self) -> &str { "Issue tracking" }
    fn usage(&self) -> &str { "[create|list|update|close|show] [args]" }

    async fn execute(&self, ctx: &Context, args: &[&str]) -> Result<Response> {
        let sub = args.first().copied().unwrap_or("list");
        let rest = if args.len() > 1 { &args[1..] } else { &[] as &[&str] };
        match sub {
            "create" | "new" | "add" => self.create(ctx, rest).await,
            "list" | "ls" => self.list(ctx, rest).await,
            "update" | "edit" => self.update(ctx, rest).await,
            "close" | "done" | "complete" => self.close(ctx, rest).await,
            "show" | "info" | "get" => self.show(ctx, rest).await,
            "assign" => self.assign(ctx, rest).await,
            "help" | _ => Ok(Response::text(self.issue_help())),
        }
    }
}

impl IssueCommand {
    // -----------------------------------------------------------------------
    // create
    // -----------------------------------------------------------------------

    async fn create(&self, ctx: &Context, args: &[&str]) -> Result<Response> {
        if args.is_empty() {
            return Ok(Response::text(
                "Usage: /issue create <title> [--priority low|medium|high|critical] [--points N] [--sprint id]\n\
                 Example: /issue create \"Fix login bug\" --priority high --points 3",
            ));
        }

        // First non-flag arg is the title.
        let mut title_parts = Vec::new();
        let mut priority = IssuePriority::Medium;
        let mut story_points: Option<u32> = None;
        let mut sprint_prefix: Option<&str> = None;
        let mut assignee: Option<&str> = None;

        let mut i = 0;
        while i < args.len() {
            match args[i] {
                "--priority" | "-p" => {
                    i += 1;
                    priority = parse_priority(args.get(i).copied().unwrap_or("medium"));
                }
                "--points" | "--sp" => {
                    i += 1;
                    story_points = args.get(i).and_then(|s| s.parse().ok());
                }
                "--sprint" | "-s" => {
                    i += 1;
                    sprint_prefix = args.get(i).copied();
                }
                "--assignee" | "-a" => {
                    i += 1;
                    assignee = args.get(i).copied();
                }
                other => title_parts.push(other),
            }
            i += 1;
        }

        let title = title_parts.join(" ");
        if title.trim().is_empty() {
            return Err(BotError::CommandError("Issue title cannot be empty".to_string()));
        }

        let mut issue = Issue::new(title.trim());
        issue.priority = priority;
        issue.story_points = story_points;
        issue.reporter = ctx.user.as_ref().and_then(|u| u.username.clone());
        issue.assignee = assignee.map(|a| a.trim_start_matches('@').to_string());

        // Resolve sprint
        if let Some(prefix) = sprint_prefix {
            let sprints = self.state.list_sprints().await;
            if let Some(s) = sprints.iter().find(|s| s.id.to_string().starts_with(prefix)) {
                issue.sprint_id = Some(s.id);
            }
        } else if let Some(active) = self.state.get_active_sprint().await {
            issue.sprint_id = Some(active.id);
        }

        let id_short = issue.id.to_string()[..8].to_owned();
        let created = self.state.create_issue(issue).await?;

        // Add the issue to the sprint's issue list
        if let Some(sid) = created.sprint_id {
            let _ = self.state.update_sprint(sid, |s| {
                s.add_issue(created.id);
            }).await;
        }

        info!("Issue created: {} ({})", created.title, created.id);
        Ok(Response::text(format!(
            "Issue created!\n\
             ID: {}\n\
             Title: {}\n\
             Priority: {}\n\
             Points: {}\n\
             Sprint: {}",
            id_short,
            created.title,
            created.priority,
            created.story_points.map(|p| p.to_string()).unwrap_or_else(|| "-".to_string()),
            created.sprint_id.map(|id| id.to_string()[..8].to_string()).unwrap_or_else(|| "none".to_string()),
        )))
    }

    // -----------------------------------------------------------------------
    // list
    // -----------------------------------------------------------------------

    async fn list(&self, _ctx: &Context, args: &[&str]) -> Result<Response> {
        let mut sprint_filter: Option<String> = None;
        let mut status_filter: Option<IssueStatus> = None;
        let mut assignee_filter: Option<String> = None;

        let mut i = 0;
        while i < args.len() {
            match args[i] {
                "--sprint" | "-s" => {
                    i += 1;
                    sprint_filter = args.get(i).map(|s| s.to_string());
                }
                "--status" => {
                    i += 1;
                    status_filter = args.get(i).map(|s| parse_status(s));
                }
                "--assignee" | "-a" => {
                    i += 1;
                    assignee_filter = args.get(i).map(|s| s.trim_start_matches('@').to_string());
                }
                _ => {}
            }
            i += 1;
        }

        let all_issues = self.state.list_issues().await;
        let mut issues: Vec<_> = all_issues.iter().collect();

        // Apply sprint filter
        if let Some(ref prefix) = sprint_filter {
            let sprints = self.state.list_sprints().await;
            if let Some(sprint) = sprints.iter().find(|s| {
                s.id.to_string().starts_with(prefix.as_str()) || s.name == prefix.as_str()
            }) {
                let sid = sprint.id;
                issues.retain(|i| i.sprint_id == Some(sid));
            }
        } else {
            // Default: show active sprint issues if available
            if let Some(active) = self.state.get_active_sprint().await {
                if sprint_filter.is_none() && status_filter.is_none() {
                    issues.retain(|i| i.sprint_id == Some(active.id));
                }
            }
        }

        // Apply status filter
        if let Some(ref status) = status_filter {
            issues.retain(|i| &i.status == status);
        }

        // Apply assignee filter
        if let Some(ref assignee) = assignee_filter {
            issues.retain(|i| {
                i.assignee.as_deref().map(|a| a == assignee.as_str()).unwrap_or(false)
            });
        }

        if issues.is_empty() {
            return Ok(Response::text("No issues found."));
        }

        let mut lines = vec![format!("Issues ({}):", issues.len())];
        for issue in issues {
            let status_icon = status_icon(&issue.status);
            let pts = issue.story_points.map(|p| format!("[{}pt]", p)).unwrap_or_default();
            let assignee = issue.assignee.as_deref().map(|a| format!(" @{}", a)).unwrap_or_default();
            lines.push(format!(
                "{} [{}] {} {}{}",
                status_icon,
                &issue.id.to_string()[..8],
                issue.title,
                pts,
                assignee,
            ));
        }
        Ok(Response::text(lines.join("\n")))
    }

    // -----------------------------------------------------------------------
    // update
    // -----------------------------------------------------------------------

    async fn update(&self, _ctx: &Context, args: &[&str]) -> Result<Response> {
        let id_prefix = args.first().copied().ok_or_else(|| {
            BotError::CommandError("Usage: /issue update <id> [--status ...] [--assignee ...] [--points N]".to_string())
        })?;

        let issue = self
            .state
            .find_issue_by_prefix(id_prefix)
            .await
            .ok_or_else(|| BotError::StateError(format!("Issue '{}' not found", id_prefix)))?;

        let mut new_status: Option<IssueStatus> = None;
        let mut new_assignee: Option<String> = None;
        let mut new_points: Option<u32> = None;
        let mut new_priority: Option<IssuePriority> = None;

        let mut i = 1;
        while i < args.len() {
            match args[i] {
                "--status" | "-s" => {
                    i += 1;
                    new_status = args.get(i).map(|s| parse_status(s));
                }
                "--assignee" | "-a" => {
                    i += 1;
                    new_assignee = args.get(i).map(|s| s.trim_start_matches('@').to_string());
                }
                "--points" | "--sp" => {
                    i += 1;
                    new_points = args.get(i).and_then(|s| s.parse().ok());
                }
                "--priority" | "-p" => {
                    i += 1;
                    new_priority = args.get(i).map(|s| parse_priority(s));
                }
                _ => {}
            }
            i += 1;
        }

        let updated = self.state.update_issue(issue.id, |iss| {
            if let Some(status) = new_status.take() {
                iss.status = status;
            }
            if let Some(assignee) = new_assignee.take() {
                iss.assignee = Some(assignee);
            }
            if let Some(pts) = new_points.take() {
                iss.story_points = Some(pts);
            }
            if let Some(priority) = new_priority.take() {
                iss.priority = priority;
            }
        }).await?;

        Ok(Response::text(format!(
            "Issue updated: [{}] {}\nStatus: {}\nPriority: {}\nAssignee: {}\nPoints: {}",
            &updated.id.to_string()[..8],
            updated.title,
            updated.status,
            updated.priority,
            updated.assignee.as_deref().unwrap_or("unassigned"),
            updated.story_points.map(|p| p.to_string()).unwrap_or_else(|| "-".to_string()),
        )))
    }

    // -----------------------------------------------------------------------
    // close
    // -----------------------------------------------------------------------

    async fn close(&self, _ctx: &Context, args: &[&str]) -> Result<Response> {
        let id_prefix = args.first().copied().ok_or_else(|| {
            BotError::CommandError("Usage: /issue close <id>".to_string())
        })?;

        let issue = self
            .state
            .find_issue_by_prefix(id_prefix)
            .await
            .ok_or_else(|| BotError::StateError(format!("Issue '{}' not found", id_prefix)))?;

        let updated = self.state.update_issue(issue.id, |i| {
            i.status = IssueStatus::Done;
        }).await?;

        info!("Issue closed: {} ({})", updated.title, updated.id);
        Ok(Response::text(format!(
            "Issue closed: [{}] {}",
            &updated.id.to_string()[..8],
            updated.title,
        )))
    }

    // -----------------------------------------------------------------------
    // show
    // -----------------------------------------------------------------------

    async fn show(&self, _ctx: &Context, args: &[&str]) -> Result<Response> {
        let id_prefix = args.first().copied().ok_or_else(|| {
            BotError::CommandError("Usage: /issue show <id>".to_string())
        })?;

        let issue = self
            .state
            .find_issue_by_prefix(id_prefix)
            .await
            .ok_or_else(|| BotError::StateError(format!("Issue '{}' not found", id_prefix)))?;

        Ok(Response::text(format!(
            "Issue: {}\n\
             ID: {}\n\
             Status: {}\n\
             Priority: {}\n\
             Story Points: {}\n\
             Assignee: {}\n\
             Reporter: {}\n\
             Sprint: {}\n\
             Labels: {}\n\
             Created: {}\n\
             Updated: {}\n\
             {}",
            issue.title,
            &issue.id.to_string()[..8],
            issue.status,
            issue.priority,
            issue.story_points.map(|p| p.to_string()).unwrap_or_else(|| "—".to_string()),
            issue.assignee.as_deref().unwrap_or("unassigned"),
            issue.reporter.as_deref().unwrap_or("unknown"),
            issue.sprint_id.map(|id| id.to_string()[..8].to_string()).unwrap_or_else(|| "none".to_string()),
            if issue.labels.is_empty() { "none".to_string() } else { issue.labels.join(", ") },
            issue.created_at.format("%Y-%m-%d %H:%M UTC"),
            issue.updated_at.format("%Y-%m-%d %H:%M UTC"),
            issue.description.as_deref().map(|d| format!("\n{}", d)).unwrap_or_default(),
        )))
    }

    // -----------------------------------------------------------------------
    // assign
    // -----------------------------------------------------------------------

    async fn assign(&self, _ctx: &Context, args: &[&str]) -> Result<Response> {
        let id_prefix = args.first().copied().ok_or_else(|| {
            BotError::CommandError("Usage: /issue assign <id> <@username>".to_string())
        })?;
        let assignee = args.get(1).copied().ok_or_else(|| {
            BotError::CommandError("Usage: /issue assign <id> <@username>".to_string())
        })?;

        let issue = self
            .state
            .find_issue_by_prefix(id_prefix)
            .await
            .ok_or_else(|| BotError::StateError(format!("Issue '{}' not found", id_prefix)))?;

        let clean_assignee = assignee.trim_start_matches('@').to_string();
        let updated = self.state.update_issue(issue.id, |i| {
            i.assignee = Some(clean_assignee.clone());
        }).await?;

        Ok(Response::text(format!(
            "Assigned [{}] {} to @{}",
            &updated.id.to_string()[..8],
            updated.title,
            clean_assignee,
        )))
    }

    fn issue_help(&self) -> String {
        "Issue Commands:\n\
         /issue create <title> [--priority p] [--points N] — Create issue\n\
         /issue list [--sprint id] [--status s] [--assignee a] — List issues\n\
         /issue show <id> — Show issue details\n\
         /issue update <id> [--status s] [--assignee a] [--points N] — Update\n\
         /issue close <id> — Mark as done\n\
         /issue assign <id> <@user> — Assign to user"
            .to_string()
    }
}

// ---------------------------------------------------------------------------
// IssueDispatcher — convenience facade used by bot.rs
// ---------------------------------------------------------------------------

pub struct IssueDispatcher {
    state: Arc<AppState>,
}

impl IssueDispatcher {
    pub fn new(state: Arc<AppState>) -> Self {
        Self { state }
    }

    pub async fn dispatch(&self, ctx: &Context, args: &[&str]) -> Result<Response> {
        IssueCommand::new(self.state.clone()).execute(ctx, args).await
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn parse_priority(s: &str) -> IssuePriority {
    match s.to_ascii_lowercase().as_str() {
        "low" | "l" => IssuePriority::Low,
        "high" | "h" => IssuePriority::High,
        "critical" | "crit" | "c" => IssuePriority::Critical,
        _ => IssuePriority::Medium,
    }
}

fn parse_status(s: &str) -> IssueStatus {
    match s.to_ascii_lowercase().replace('-', "").replace('_', "").as_str() {
        "todo" => IssueStatus::Todo,
        "inprogress" | "progress" | "wip" => IssueStatus::InProgress,
        "inreview" | "review" => IssueStatus::InReview,
        "done" | "complete" | "completed" => IssueStatus::Done,
        "cancelled" | "canceled" => IssueStatus::Cancelled,
        _ => IssueStatus::Backlog,
    }
}

fn status_icon(status: &IssueStatus) -> &'static str {
    match status {
        IssueStatus::Backlog => "  ",
        IssueStatus::Todo => "[ ]",
        IssueStatus::InProgress => "[~]",
        IssueStatus::InReview => "[R]",
        IssueStatus::Done => "[x]",
        IssueStatus::Cancelled => "[/]",
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

    fn ctx() -> Context {
        Context::new(Message::new(1, 1, "/issue"))
    }

    #[tokio::test]
    async fn create_and_list() {
        let state = make_state();
        let cmd = IssueCommand::new(state.clone());

        cmd.execute(&ctx(), &["create", "Bug in auth", "--priority", "high"])
            .await
            .unwrap();
        cmd.execute(&ctx(), &["create", "Refactor DB", "--points", "5"])
            .await
            .unwrap();

        // List without active sprint returns all when filtering is off
        let resp = cmd.execute(&ctx(), &["list", "--status", "backlog"]).await.unwrap();
        assert!(resp.as_str().contains("Bug in auth") || resp.as_str().contains("Refactor DB"));
    }

    #[tokio::test]
    async fn close_issue() {
        let state = make_state();
        let cmd = IssueCommand::new(state.clone());

        cmd.execute(&ctx(), &["create", "Flaky test"]).await.unwrap();
        let issues = state.list_issues().await;
        let prefix = &issues[0].id.to_string()[..8];

        let resp = cmd.execute(&ctx(), &["close", prefix]).await.unwrap();
        assert!(resp.as_str().contains("closed"));
    }

    #[test]
    fn parse_priority_cases() {
        assert_eq!(parse_priority("critical"), IssuePriority::Critical);
        assert_eq!(parse_priority("LOW"), IssuePriority::Low);
        assert_eq!(parse_priority("anything"), IssuePriority::Medium);
    }
}
