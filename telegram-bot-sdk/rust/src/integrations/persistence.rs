//! SQLite persistence layer via sqlx.
//!
//! `PersistenceStore` wraps a `SqlitePool` and provides methods to flush the
//! in-memory `AppState` to disk and to reload it on startup.  All queries use
//! the runtime API (`sqlx::query`) rather than the compile-time macro variants
//! so that no `DATABASE_URL` is required at build time.

use async_trait::async_trait;
use sqlx::{Row, SqlitePool};
use tracing::{debug, info, warn};
use uuid::Uuid;

use crate::error::{BotError, Result};
use crate::state::{AppState, Issue, IssueStatus, IssuePriority, Sprint, SprintStatus};
use super::Integration;

// ---------------------------------------------------------------------------
// PersistenceStore
// ---------------------------------------------------------------------------

/// Wraps a `SqlitePool` with helper methods for persisting bot state.
#[derive(Debug, Clone)]
pub struct PersistenceStore {
    pool: SqlitePool,
}

impl PersistenceStore {
    /// Connect to (or create) a SQLite database at `db_url`.
    ///
    /// `db_url` examples:
    /// - `sqlite:./bot.db`
    /// - `sqlite::memory:`
    pub async fn connect(db_url: &str) -> Result<Self> {
        let pool = SqlitePool::connect(db_url)
            .await
            .map_err(|e| BotError::IntegrationError(format!("SQLite connect: {}", e)))?;
        let store = Self { pool };
        store.run_migrations().await?;
        info!("Persistence store ready ({})", db_url);
        Ok(store)
    }

    /// Create an in-memory database for testing.
    pub async fn in_memory() -> Result<Self> {
        Self::connect("sqlite::memory:").await
    }

    /// Apply the schema (idempotent — uses `CREATE TABLE IF NOT EXISTS`).
    async fn run_migrations(&self) -> Result<()> {
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS sprints (
                id          TEXT PRIMARY KEY NOT NULL,
                name        TEXT NOT NULL,
                goal        TEXT,
                start_date  TEXT NOT NULL,
                end_date    TEXT NOT NULL,
                status      TEXT NOT NULL DEFAULT 'Planning',
                velocity    REAL,
                created_at  TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS issues (
                id            TEXT PRIMARY KEY NOT NULL,
                title         TEXT NOT NULL,
                description   TEXT,
                status        TEXT NOT NULL DEFAULT 'Backlog',
                priority      TEXT NOT NULL DEFAULT 'Medium',
                assignee      TEXT,
                reporter      TEXT,
                sprint_id     TEXT,
                story_points  INTEGER,
                labels        TEXT NOT NULL DEFAULT '[]',
                created_at    TEXT NOT NULL,
                updated_at    TEXT NOT NULL,
                FOREIGN KEY (sprint_id) REFERENCES sprints(id)
            );

            CREATE INDEX IF NOT EXISTS idx_issues_sprint ON issues(sprint_id);
            CREATE INDEX IF NOT EXISTS idx_issues_status ON issues(status);
            "#,
        )
        .execute(&self.pool)
        .await
        .map_err(|e| BotError::IntegrationError(format!("Migration error: {}", e)))?;

        debug!("Database schema applied");
        Ok(())
    }

    // -----------------------------------------------------------------------
    // Sprint persistence
    // -----------------------------------------------------------------------

    /// Upsert a sprint into the `sprints` table.
    pub async fn save_sprint(&self, sprint: &Sprint) -> Result<()> {
        sqlx::query(
            r#"
            INSERT INTO sprints (id, name, goal, start_date, end_date, status, velocity, created_at)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
            ON CONFLICT(id) DO UPDATE SET
                name        = excluded.name,
                goal        = excluded.goal,
                start_date  = excluded.start_date,
                end_date    = excluded.end_date,
                status      = excluded.status,
                velocity    = excluded.velocity
            "#,
        )
        .bind(sprint.id.to_string())
        .bind(&sprint.name)
        .bind(&sprint.goal)
        .bind(sprint.start_date.to_rfc3339())
        .bind(sprint.end_date.to_rfc3339())
        .bind(sprint.status.to_string())
        .bind(sprint.velocity)
        .bind(sprint.created_at.to_rfc3339())
        .execute(&self.pool)
        .await
        .map_err(|e| BotError::IntegrationError(format!("Save sprint: {}", e)))?;

        Ok(())
    }

    /// Load all sprints from the database.
    pub async fn load_sprints(&self) -> Result<Vec<Sprint>> {
        let rows = sqlx::query("SELECT * FROM sprints ORDER BY created_at ASC")
            .fetch_all(&self.pool)
            .await
            .map_err(|e| BotError::IntegrationError(format!("Load sprints: {}", e)))?;

        let mut sprints = Vec::with_capacity(rows.len());
        for row in rows {
            let id_str: String = row.try_get("id").map_err(map_row_err)?;
            let status_str: String = row.try_get("status").map_err(map_row_err)?;
            let start_str: String = row.try_get("start_date").map_err(map_row_err)?;
            let end_str: String = row.try_get("end_date").map_err(map_row_err)?;
            let created_str: String = row.try_get("created_at").map_err(map_row_err)?;

            let sprint = Sprint {
                id: Uuid::parse_str(&id_str)
                    .map_err(|e| BotError::IntegrationError(format!("UUID parse: {}", e)))?,
                name: row.try_get("name").map_err(map_row_err)?,
                goal: row.try_get("goal").map_err(map_row_err)?,
                start_date: chrono::DateTime::parse_from_rfc3339(&start_str)
                    .map_err(|e| BotError::IntegrationError(format!("Date parse: {}", e)))?
                    .with_timezone(&chrono::Utc),
                end_date: chrono::DateTime::parse_from_rfc3339(&end_str)
                    .map_err(|e| BotError::IntegrationError(format!("Date parse: {}", e)))?
                    .with_timezone(&chrono::Utc),
                status: parse_sprint_status(&status_str),
                velocity: row.try_get("velocity").map_err(map_row_err)?,
                created_at: chrono::DateTime::parse_from_rfc3339(&created_str)
                    .map_err(|e| BotError::IntegrationError(format!("Date parse: {}", e)))?
                    .with_timezone(&chrono::Utc),
                issues: Vec::new(), // populated below via issues table
                team: Vec::new(),
            };
            sprints.push(sprint);
        }
        Ok(sprints)
    }

    /// Delete a sprint by ID.
    pub async fn delete_sprint(&self, id: Uuid) -> Result<()> {
        sqlx::query("DELETE FROM sprints WHERE id = ?1")
            .bind(id.to_string())
            .execute(&self.pool)
            .await
            .map_err(|e| BotError::IntegrationError(format!("Delete sprint: {}", e)))?;
        Ok(())
    }

    // -----------------------------------------------------------------------
    // Issue persistence
    // -----------------------------------------------------------------------

    /// Upsert an issue into the `issues` table.
    pub async fn save_issue(&self, issue: &Issue) -> Result<()> {
        let labels_json = serde_json::to_string(&issue.labels)
            .map_err(|e| BotError::SerializationError(e.to_string()))?;

        sqlx::query(
            r#"
            INSERT INTO issues
                (id, title, description, status, priority, assignee, reporter,
                 sprint_id, story_points, labels, created_at, updated_at)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
            ON CONFLICT(id) DO UPDATE SET
                title        = excluded.title,
                description  = excluded.description,
                status       = excluded.status,
                priority     = excluded.priority,
                assignee     = excluded.assignee,
                reporter     = excluded.reporter,
                sprint_id    = excluded.sprint_id,
                story_points = excluded.story_points,
                labels       = excluded.labels,
                updated_at   = excluded.updated_at
            "#,
        )
        .bind(issue.id.to_string())
        .bind(&issue.title)
        .bind(&issue.description)
        .bind(issue.status.to_string())
        .bind(issue.priority.to_string())
        .bind(&issue.assignee)
        .bind(&issue.reporter)
        .bind(issue.sprint_id.map(|id| id.to_string()))
        .bind(issue.story_points.map(|p| p as i64))
        .bind(&labels_json)
        .bind(issue.created_at.to_rfc3339())
        .bind(issue.updated_at.to_rfc3339())
        .execute(&self.pool)
        .await
        .map_err(|e| BotError::IntegrationError(format!("Save issue: {}", e)))?;

        Ok(())
    }

    /// Load all issues from the database.
    pub async fn load_issues(&self) -> Result<Vec<Issue>> {
        let rows = sqlx::query("SELECT * FROM issues ORDER BY created_at ASC")
            .fetch_all(&self.pool)
            .await
            .map_err(|e| BotError::IntegrationError(format!("Load issues: {}", e)))?;

        let mut issues = Vec::with_capacity(rows.len());
        for row in rows {
            let id_str: String = row.try_get("id").map_err(map_row_err)?;
            let status_str: String = row.try_get("status").map_err(map_row_err)?;
            let priority_str: String = row.try_get("priority").map_err(map_row_err)?;
            let created_str: String = row.try_get("created_at").map_err(map_row_err)?;
            let updated_str: String = row.try_get("updated_at").map_err(map_row_err)?;
            let labels_json: String = row.try_get("labels").map_err(map_row_err)?;
            let sprint_id_str: Option<String> = row.try_get("sprint_id").map_err(map_row_err)?;
            let story_points_raw: Option<i64> =
                row.try_get("story_points").map_err(map_row_err)?;

            let issue = Issue {
                id: Uuid::parse_str(&id_str)
                    .map_err(|e| BotError::IntegrationError(format!("UUID: {}", e)))?,
                title: row.try_get("title").map_err(map_row_err)?,
                description: row.try_get("description").map_err(map_row_err)?,
                status: parse_issue_status(&status_str),
                priority: parse_issue_priority(&priority_str),
                assignee: row.try_get("assignee").map_err(map_row_err)?,
                reporter: row.try_get("reporter").map_err(map_row_err)?,
                sprint_id: sprint_id_str
                    .as_deref()
                    .and_then(|s| Uuid::parse_str(s).ok()),
                story_points: story_points_raw.map(|p| p as u32),
                labels: serde_json::from_str(&labels_json).unwrap_or_default(),
                created_at: chrono::DateTime::parse_from_rfc3339(&created_str)
                    .map_err(|e| BotError::IntegrationError(format!("Date parse: {}", e)))?
                    .with_timezone(&chrono::Utc),
                updated_at: chrono::DateTime::parse_from_rfc3339(&updated_str)
                    .map_err(|e| BotError::IntegrationError(format!("Date parse: {}", e)))?
                    .with_timezone(&chrono::Utc),
            };
            issues.push(issue);
        }
        Ok(issues)
    }

    /// Delete an issue by ID.
    pub async fn delete_issue(&self, id: Uuid) -> Result<()> {
        sqlx::query("DELETE FROM issues WHERE id = ?1")
            .bind(id.to_string())
            .execute(&self.pool)
            .await
            .map_err(|e| BotError::IntegrationError(format!("Delete issue: {}", e)))?;
        Ok(())
    }

    // -----------------------------------------------------------------------
    // Snapshot helpers
    // -----------------------------------------------------------------------

    /// Flush all in-memory state to disk.
    pub async fn flush_state(&self, state: &AppState) -> Result<()> {
        let sprints = state.list_sprints().await;
        for sprint in &sprints {
            self.save_sprint(sprint).await?;
        }
        let issues = state.list_issues().await;
        for issue in &issues {
            self.save_issue(issue).await?;
        }
        info!("Flushed {} sprints, {} issues", sprints.len(), issues.len());
        Ok(())
    }

    /// Return a count of persisted rows for diagnostics.
    pub async fn row_counts(&self) -> Result<(i64, i64)> {
        let sprint_count: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM sprints")
                .fetch_one(&self.pool)
                .await
                .map_err(|e| BotError::IntegrationError(format!("Count: {}", e)))?;
        let issue_count: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM issues")
                .fetch_one(&self.pool)
                .await
                .map_err(|e| BotError::IntegrationError(format!("Count: {}", e)))?;
        Ok((sprint_count, issue_count))
    }
}

#[async_trait]
impl Integration for PersistenceStore {
    fn name(&self) -> &str {
        "sqlite"
    }

    async fn health_check(&self) -> Result<()> {
        sqlx::query("SELECT 1")
            .execute(&self.pool)
            .await
            .map(|_| ())
            .map_err(|e| BotError::IntegrationError(format!("SQLite health: {}", e)))
    }
}

// ---------------------------------------------------------------------------
// Parsing helpers
// ---------------------------------------------------------------------------

fn map_row_err(e: sqlx::Error) -> BotError {
    BotError::IntegrationError(format!("Row decode: {}", e))
}

fn parse_sprint_status(s: &str) -> SprintStatus {
    match s {
        "Active" => SprintStatus::Active,
        "Completed" => SprintStatus::Completed,
        "Cancelled" => SprintStatus::Cancelled,
        _ => SprintStatus::Planning,
    }
}

fn parse_issue_status(s: &str) -> IssueStatus {
    match s {
        "Todo" => IssueStatus::Todo,
        "In Progress" => IssueStatus::InProgress,
        "In Review" => IssueStatus::InReview,
        "Done" => IssueStatus::Done,
        "Cancelled" => IssueStatus::Cancelled,
        _ => IssueStatus::Backlog,
    }
}

fn parse_issue_priority(s: &str) -> IssuePriority {
    match s {
        "Low" => IssuePriority::Low,
        "High" => IssuePriority::High,
        "Critical" => IssuePriority::Critical,
        _ => IssuePriority::Medium,
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::{Duration, Utc};

    #[tokio::test]
    async fn schema_creates_without_error() {
        let store = PersistenceStore::in_memory().await.unwrap();
        let (sc, ic) = store.row_counts().await.unwrap();
        assert_eq!(sc, 0);
        assert_eq!(ic, 0);
    }

    #[tokio::test]
    async fn sprint_round_trip() {
        let store = PersistenceStore::in_memory().await.unwrap();
        let sprint = Sprint::new("Test Sprint", Utc::now(), Utc::now() + Duration::days(14));
        store.save_sprint(&sprint).await.unwrap();

        let loaded = store.load_sprints().await.unwrap();
        assert_eq!(loaded.len(), 1);
        assert_eq!(loaded[0].name, "Test Sprint");
    }

    #[tokio::test]
    async fn issue_round_trip() {
        let store = PersistenceStore::in_memory().await.unwrap();
        let mut issue = Issue::new("Fix critical bug");
        issue.priority = IssuePriority::Critical;
        issue.story_points = Some(5);
        store.save_issue(&issue).await.unwrap();

        let loaded = store.load_issues().await.unwrap();
        assert_eq!(loaded.len(), 1);
        assert_eq!(loaded[0].title, "Fix critical bug");
        assert_eq!(loaded[0].story_points, Some(5));
    }

    #[tokio::test]
    async fn issue_upsert() {
        let store = PersistenceStore::in_memory().await.unwrap();
        let mut issue = Issue::new("Flaky test");
        store.save_issue(&issue).await.unwrap();

        issue.transition(IssueStatus::Done);
        store.save_issue(&issue).await.unwrap();

        let loaded = store.load_issues().await.unwrap();
        assert_eq!(loaded.len(), 1);
        assert_eq!(loaded[0].status.to_string(), "Done");
    }
}
