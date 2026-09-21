//! Shared application state: sprint/issue/session stores behind `Arc<RwLock>`.
//!
//! `AppState` is the single source of truth for all in-memory data.  Every
//! operation that reads or mutates state goes through the async accessor
//! methods so that the underlying `tokio::sync::RwLock` is never held across
//! await points unnecessarily.

use std::collections::HashMap;
use std::sync::Arc;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use tokio::sync::RwLock;
use uuid::Uuid;

use crate::error::{BotError, Result};

// ---------------------------------------------------------------------------
// Domain enumerations
// ---------------------------------------------------------------------------

/// Lifecycle states for a sprint.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum SprintStatus {
    Planning,
    Active,
    Completed,
    Cancelled,
}

impl std::fmt::Display for SprintStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let s = match self {
            SprintStatus::Planning => "Planning",
            SprintStatus::Active => "Active",
            SprintStatus::Completed => "Completed",
            SprintStatus::Cancelled => "Cancelled",
        };
        write!(f, "{}", s)
    }
}

/// Issue workflow states, aligned with typical Kanban columns.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum IssueStatus {
    Backlog,
    Todo,
    InProgress,
    InReview,
    Done,
    Cancelled,
}

impl std::fmt::Display for IssueStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let s = match self {
            IssueStatus::Backlog => "Backlog",
            IssueStatus::Todo => "Todo",
            IssueStatus::InProgress => "In Progress",
            IssueStatus::InReview => "In Review",
            IssueStatus::Done => "Done",
            IssueStatus::Cancelled => "Cancelled",
        };
        write!(f, "{}", s)
    }
}

/// Issue triage priority.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum IssuePriority {
    Low,
    Medium,
    High,
    Critical,
}

impl std::fmt::Display for IssuePriority {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let s = match self {
            IssuePriority::Low => "Low",
            IssuePriority::Medium => "Medium",
            IssuePriority::High => "High",
            IssuePriority::Critical => "Critical",
        };
        write!(f, "{}", s)
    }
}

// ---------------------------------------------------------------------------
// Sprint
// ---------------------------------------------------------------------------

/// A sprint (time-boxed iteration).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Sprint {
    pub id: Uuid,
    pub name: String,
    pub goal: Option<String>,
    pub start_date: DateTime<Utc>,
    pub end_date: DateTime<Utc>,
    /// IDs of issues assigned to this sprint.
    pub issues: Vec<Uuid>,
    pub status: SprintStatus,
    /// Telegram usernames of team members.
    pub team: Vec<String>,
    /// Story points completed (set when sprint is closed).
    pub velocity: Option<f64>,
    pub created_at: DateTime<Utc>,
}

impl Sprint {
    pub fn new(
        name: impl Into<String>,
        start_date: DateTime<Utc>,
        end_date: DateTime<Utc>,
    ) -> Self {
        Self {
            id: Uuid::new_v4(),
            name: name.into(),
            goal: None,
            start_date,
            end_date,
            issues: Vec::new(),
            status: SprintStatus::Planning,
            team: Vec::new(),
            velocity: None,
            created_at: Utc::now(),
        }
    }

    pub fn is_active(&self) -> bool {
        self.status == SprintStatus::Active
    }

    /// Returns the number of days the sprint spans.
    pub fn duration_days(&self) -> i64 {
        (self.end_date - self.start_date).num_days()
    }

    /// Returns the number of days remaining (0 if already past end).
    pub fn days_remaining(&self) -> i64 {
        let now = Utc::now();
        if now >= self.end_date {
            0
        } else {
            (self.end_date - now).num_days()
        }
    }

    /// Idempotently adds an issue ID to this sprint.
    pub fn add_issue(&mut self, issue_id: Uuid) {
        if !self.issues.contains(&issue_id) {
            self.issues.push(issue_id);
        }
    }
}

// ---------------------------------------------------------------------------
// Issue
// ---------------------------------------------------------------------------

/// A trackable issue / task / bug.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Issue {
    pub id: Uuid,
    pub title: String,
    pub description: Option<String>,
    pub status: IssueStatus,
    pub priority: IssuePriority,
    /// Telegram username of the assignee (no '@').
    pub assignee: Option<String>,
    /// Telegram username of the reporter.
    pub reporter: Option<String>,
    pub sprint_id: Option<Uuid>,
    pub story_points: Option<u32>,
    pub labels: Vec<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl Issue {
    pub fn new(title: impl Into<String>) -> Self {
        let now = Utc::now();
        Self {
            id: Uuid::new_v4(),
            title: title.into(),
            description: None,
            status: IssueStatus::Backlog,
            priority: IssuePriority::Medium,
            assignee: None,
            reporter: None,
            sprint_id: None,
            story_points: None,
            labels: Vec::new(),
            created_at: now,
            updated_at: now,
        }
    }

    pub fn with_priority(mut self, priority: IssuePriority) -> Self {
        self.priority = priority;
        self
    }

    pub fn with_assignee(mut self, assignee: impl Into<String>) -> Self {
        self.assignee = Some(assignee.into());
        self
    }

    pub fn with_sprint(mut self, sprint_id: Uuid) -> Self {
        self.sprint_id = Some(sprint_id);
        self
    }

    pub fn with_points(mut self, pts: u32) -> Self {
        self.story_points = Some(pts);
        self
    }

    /// Transition to a new status and stamp `updated_at`.
    pub fn transition(&mut self, new_status: IssueStatus) {
        self.status = new_status;
        self.updated_at = Utc::now();
    }

    pub fn is_complete(&self) -> bool {
        matches!(self.status, IssueStatus::Done | IssueStatus::Cancelled)
    }
}

// ---------------------------------------------------------------------------
// Session
// ---------------------------------------------------------------------------

/// Per-chat conversation session.
///
/// Stores a rolling window of recent interaction context so the agent can
/// make follow-up responses coherent.
#[derive(Debug, Clone)]
pub struct Session {
    pub chat_id: i64,
    pub user_id: Option<i64>,
    pub username: Option<String>,
    /// Rolling context window (most recent entry last).
    pub context: Vec<String>,
    /// The sprint the user was last interacting with.
    pub current_sprint_id: Option<Uuid>,
    pub last_activity: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
}

impl Session {
    pub fn new(chat_id: i64) -> Self {
        let now = Utc::now();
        Self {
            chat_id,
            user_id: None,
            username: None,
            context: Vec::new(),
            current_sprint_id: None,
            last_activity: now,
            created_at: now,
        }
    }

    /// Append a context entry and evict the oldest if over `max` entries.
    pub fn push_context(&mut self, entry: impl Into<String>, max: usize) {
        self.context.push(entry.into());
        if self.context.len() > max {
            let drain = self.context.len() - max;
            self.context.drain(..drain);
        }
        self.last_activity = Utc::now();
    }

    /// Returns true if no activity has been seen within `timeout_secs`.
    /// A `timeout_secs` of 0 means every session is considered stale.
    pub fn is_stale(&self, timeout_secs: i64) -> bool {
        (Utc::now() - self.last_activity).num_seconds() >= timeout_secs
    }
}

// ---------------------------------------------------------------------------
// BotConfig
// ---------------------------------------------------------------------------

/// Runtime configuration for the bot.
#[derive(Debug, Clone)]
pub struct BotConfig {
    /// Telegram bot token from @BotFather.
    pub token: String,
    /// Optional Ollama base URL (e.g. `http://localhost:11434`).
    pub ollama_url: Option<String>,
    /// Ollama model name (default: `llama3.2`).
    pub ollama_model: String,
    /// Optional SQLite DB path (`sqlite:./bot.db` or `:memory:`).
    pub database_url: Option<String>,
    /// How long before an idle session is GC'd (seconds).
    pub session_timeout_secs: i64,
    /// Maximum context entries per session.
    pub max_context_length: usize,
}

impl Default for BotConfig {
    fn default() -> Self {
        Self {
            token: std::env::var("TELEGRAM_BOT_TOKEN")
                .or_else(|_| std::env::var("TELOXIDE_TOKEN"))
                .unwrap_or_default(),
            ollama_url: std::env::var("OLLAMA_URL").ok(),
            ollama_model: std::env::var("OLLAMA_MODEL")
                .unwrap_or_else(|_| "llama3.2".to_string()),
            database_url: std::env::var("DATABASE_URL").ok(),
            session_timeout_secs: 3600,
            max_context_length: 20,
        }
    }
}

// ---------------------------------------------------------------------------
// Inner state (private)
// ---------------------------------------------------------------------------

struct InnerState {
    sprints: HashMap<Uuid, Sprint>,
    issues: HashMap<Uuid, Issue>,
    sessions: HashMap<i64, Session>,
    /// Points to the currently active sprint.
    active_sprint_id: Option<Uuid>,
}

impl InnerState {
    fn new() -> Self {
        Self {
            sprints: HashMap::new(),
            issues: HashMap::new(),
            sessions: HashMap::new(),
            active_sprint_id: None,
        }
    }
}

// ---------------------------------------------------------------------------
// AppState
// ---------------------------------------------------------------------------

/// Thread-safe application state container.
///
/// Constructed once and shared via `Arc<AppState>` across all handlers.
pub struct AppState {
    inner: RwLock<InnerState>,
    pub config: BotConfig,
}

impl AppState {
    /// Create a new `AppState` wrapped in `Arc`.
    pub fn new(config: BotConfig) -> Arc<Self> {
        Arc::new(Self {
            inner: RwLock::new(InnerState::new()),
            config,
        })
    }

    /// Convenience: `AppState::new(BotConfig::default())`.
    pub fn from_env() -> Arc<Self> {
        Self::new(BotConfig::default())
    }

    // -----------------------------------------------------------------------
    // Sprint operations
    // -----------------------------------------------------------------------

    pub async fn create_sprint(&self, sprint: Sprint) -> Result<Sprint> {
        let mut g = self.inner.write().await;
        g.sprints.insert(sprint.id, sprint.clone());
        Ok(sprint)
    }

    pub async fn get_sprint(&self, id: Uuid) -> Result<Sprint> {
        self.inner
            .read()
            .await
            .sprints
            .get(&id)
            .cloned()
            .ok_or_else(|| BotError::StateError(format!("Sprint {} not found", id)))
    }

    /// Return all sprints, sorted by created_at ascending.
    pub async fn list_sprints(&self) -> Vec<Sprint> {
        let mut sprints: Vec<Sprint> = self.inner.read().await.sprints.values().cloned().collect();
        sprints.sort_by_key(|s| s.created_at);
        sprints
    }

    /// Apply `f` to the sprint with the given `id`, returning the updated copy.
    pub async fn update_sprint(&self, id: Uuid, f: impl FnOnce(&mut Sprint)) -> Result<Sprint> {
        let mut g = self.inner.write().await;
        let sprint = g
            .sprints
            .get_mut(&id)
            .ok_or_else(|| BotError::StateError(format!("Sprint {} not found", id)))?;
        f(sprint);
        Ok(sprint.clone())
    }

    /// Returns the first sprint with `SprintStatus::Active`, or `None`.
    pub async fn get_active_sprint(&self) -> Option<Sprint> {
        let g = self.inner.read().await;
        // Prefer the explicit pointer, fall back to scanning.
        g.active_sprint_id
            .and_then(|id| g.sprints.get(&id))
            .or_else(|| g.sprints.values().find(|s| s.status == SprintStatus::Active))
            .cloned()
    }

    /// Set the pinned active sprint.  The sprint must exist.
    pub async fn set_active_sprint(&self, id: Uuid) -> Result<()> {
        let mut g = self.inner.write().await;
        if !g.sprints.contains_key(&id) {
            return Err(BotError::StateError(format!("Sprint {} not found", id)));
        }
        // Mark old active sprint as Planning (so only one is Active).
        if let Some(old_id) = g.active_sprint_id {
            if old_id != id {
                if let Some(s) = g.sprints.get_mut(&old_id) {
                    if s.status == SprintStatus::Active {
                        s.status = SprintStatus::Planning;
                    }
                }
            }
        }
        if let Some(s) = g.sprints.get_mut(&id) {
            s.status = SprintStatus::Active;
        }
        g.active_sprint_id = Some(id);
        Ok(())
    }

    // -----------------------------------------------------------------------
    // Issue operations
    // -----------------------------------------------------------------------

    pub async fn create_issue(&self, issue: Issue) -> Result<Issue> {
        let mut g = self.inner.write().await;
        g.issues.insert(issue.id, issue.clone());
        Ok(issue)
    }

    pub async fn get_issue(&self, id: Uuid) -> Result<Issue> {
        self.inner
            .read()
            .await
            .issues
            .get(&id)
            .cloned()
            .ok_or_else(|| BotError::StateError(format!("Issue {} not found", id)))
    }

    /// Try to find an issue by UUID prefix (first 8 chars is enough for tests/humans).
    pub async fn find_issue_by_prefix(&self, prefix: &str) -> Option<Issue> {
        let prefix_lower = prefix.to_ascii_lowercase();
        self.inner
            .read()
            .await
            .issues
            .values()
            .find(|i| i.id.to_string().to_ascii_lowercase().starts_with(&prefix_lower))
            .cloned()
    }

    pub async fn list_issues(&self) -> Vec<Issue> {
        let mut issues: Vec<Issue> = self.inner.read().await.issues.values().cloned().collect();
        issues.sort_by_key(|i| i.created_at);
        issues
    }

    pub async fn list_issues_by_sprint(&self, sprint_id: Uuid) -> Vec<Issue> {
        self.inner
            .read()
            .await
            .issues
            .values()
            .filter(|i| i.sprint_id == Some(sprint_id))
            .cloned()
            .collect()
    }

    pub async fn list_issues_by_status(&self, status: &IssueStatus) -> Vec<Issue> {
        self.inner
            .read()
            .await
            .issues
            .values()
            .filter(|i| &i.status == status)
            .cloned()
            .collect()
    }

    /// Apply `f` to the issue and stamp `updated_at`.
    pub async fn update_issue(&self, id: Uuid, f: impl FnOnce(&mut Issue)) -> Result<Issue> {
        let mut g = self.inner.write().await;
        let issue = g
            .issues
            .get_mut(&id)
            .ok_or_else(|| BotError::StateError(format!("Issue {} not found", id)))?;
        f(issue);
        issue.updated_at = Utc::now();
        Ok(issue.clone())
    }

    pub async fn delete_issue(&self, id: Uuid) -> Result<Issue> {
        self.inner
            .write()
            .await
            .issues
            .remove(&id)
            .ok_or_else(|| BotError::StateError(format!("Issue {} not found", id)))
    }

    // -----------------------------------------------------------------------
    // Session operations
    // -----------------------------------------------------------------------

    /// Retrieve an existing session or create a fresh one.
    pub async fn get_or_create_session(&self, chat_id: i64) -> Session {
        let mut g = self.inner.write().await;
        g.sessions
            .entry(chat_id)
            .or_insert_with(|| Session::new(chat_id))
            .clone()
    }

    /// Apply `f` to the session for `chat_id`, creating it if needed.
    pub async fn update_session(&self, chat_id: i64, f: impl FnOnce(&mut Session)) {
        let mut g = self.inner.write().await;
        let session = g
            .sessions
            .entry(chat_id)
            .or_insert_with(|| Session::new(chat_id));
        f(session);
    }

    pub async fn get_session(&self, chat_id: i64) -> Option<Session> {
        self.inner.read().await.sessions.get(&chat_id).cloned()
    }

    /// Remove sessions that have been idle for longer than `timeout_secs`.
    /// Returns the number of sessions removed.
    pub async fn cleanup_stale_sessions(&self, timeout_secs: i64) -> usize {
        let mut g = self.inner.write().await;
        let before = g.sessions.len();
        g.sessions.retain(|_, s| !s.is_stale(timeout_secs));
        before - g.sessions.len()
    }

    // -----------------------------------------------------------------------
    // Statistics
    // -----------------------------------------------------------------------

    pub async fn sprint_count(&self) -> usize {
        self.inner.read().await.sprints.len()
    }

    pub async fn issue_count(&self) -> usize {
        self.inner.read().await.issues.len()
    }

    pub async fn session_count(&self) -> usize {
        self.inner.read().await.sessions.len()
    }

    /// Compute total story points completed across all issues in a sprint.
    pub async fn sprint_velocity(&self, sprint_id: Uuid) -> (u32, u32) {
        let g = self.inner.read().await;
        let (mut committed, mut completed) = (0u32, 0u32);
        for issue in g.issues.values().filter(|i| i.sprint_id == Some(sprint_id)) {
            let pts = issue.story_points.unwrap_or(0);
            committed += pts;
            if issue.is_complete() {
                completed += pts;
            }
        }
        (committed, completed)
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Duration;

    fn make_config() -> BotConfig {
        BotConfig {
            token: "test".to_string(),
            ollama_url: None,
            ollama_model: "llama3.2".to_string(),
            database_url: None,
            session_timeout_secs: 3600,
            max_context_length: 20,
        }
    }

    #[tokio::test]
    async fn sprint_crud() {
        let state = AppState::new(make_config());
        let s = Sprint::new("Sprint 1", Utc::now(), Utc::now() + Duration::days(14));
        let created = state.create_sprint(s).await.unwrap();
        assert_eq!(state.sprint_count().await, 1);

        let fetched = state.get_sprint(created.id).await.unwrap();
        assert_eq!(fetched.name, "Sprint 1");

        state.set_active_sprint(created.id).await.unwrap();
        let active = state.get_active_sprint().await.unwrap();
        assert_eq!(active.id, created.id);
    }

    #[tokio::test]
    async fn issue_lifecycle() {
        let state = AppState::new(make_config());
        let mut issue = Issue::new("Fix the bug");
        issue.story_points = Some(3);
        let created = state.create_issue(issue).await.unwrap();

        let updated = state
            .update_issue(created.id, |i| i.transition(IssueStatus::Done))
            .await
            .unwrap();
        assert!(updated.is_complete());
    }

    #[tokio::test]
    async fn session_context_window() {
        let mut session = Session::new(1);
        for i in 0..25 {
            session.push_context(format!("msg {}", i), 20);
        }
        assert_eq!(session.context.len(), 20);
        assert_eq!(session.context[0], "msg 5");
    }
}
