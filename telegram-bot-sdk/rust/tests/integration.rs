//! Integration tests for the Telegram Bot SDK.
//!
//! Tests are grouped by component:
//! - State management
//! - Command dispatch (scrum + issue)
//! - Agent routing
//! - Persistence round-trips
//!
//! All tests use in-process state; no real Telegram token or Ollama instance
//! is required.

use std::sync::Arc;
use chrono::{Duration, Utc};
use telegram_bot_sdk::{
    agent::{Agent, AgentCommand, CommandRegistry, FnAgentCommand},
    commands::{
        issue::IssueCommand,
        scrum::{SprintCommand, StandupCommand, VelocityCommand},
        Command,
    },
    error::Result,
    integrations::persistence::PersistenceStore,
    state::{AppState, BotConfig, Issue, IssueStatus, IssuePriority, Sprint, SprintStatus},
    types::{Context, Message, Response, User},
};
use async_trait::async_trait;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn test_config() -> BotConfig {
    BotConfig {
        token: "test_token_integration".into(),
        ollama_url: None,
        ollama_model: "llama3.2".into(),
        database_url: None,
        session_timeout_secs: 3600,
        max_context_length: 20,
    }
}

fn make_state() -> Arc<AppState> {
    AppState::new(test_config())
}

fn make_ctx(text: &str) -> Context {
    let mut msg = Message::new(1, 100, text);
    msg.from = Some(User {
        id: 42,
        username: Some("testuser".into()),
        first_name: "Test".into(),
        last_name: Some("User".into()),
        is_bot: false,
        language_code: Some("en".into()),
    });
    Context::new(msg)
}

async fn make_sprint_in_state(state: &Arc<AppState>, name: &str) -> Sprint {
    let sprint = Sprint::new(name, Utc::now(), Utc::now() + Duration::days(14));
    state.create_sprint(sprint).await.unwrap()
}

// ---------------------------------------------------------------------------
// State tests
// ---------------------------------------------------------------------------

mod state_tests {
    use super::*;

    #[tokio::test]
    async fn create_and_retrieve_sprint() {
        let state = make_state();
        let sprint = make_sprint_in_state(&state, "State-Sprint-1").await;
        let retrieved = state.get_sprint(sprint.id).await.unwrap();
        assert_eq!(retrieved.name, "State-Sprint-1");
        assert_eq!(retrieved.status, SprintStatus::Planning);
    }

    #[tokio::test]
    async fn active_sprint_tracking() {
        let state = make_state();
        let s1 = make_sprint_in_state(&state, "S1").await;
        let s2 = make_sprint_in_state(&state, "S2").await;

        state.set_active_sprint(s1.id).await.unwrap();
        let active = state.get_active_sprint().await.unwrap();
        assert_eq!(active.id, s1.id);

        // Switching active sprint should demote the old one
        state.set_active_sprint(s2.id).await.unwrap();
        let new_active = state.get_active_sprint().await.unwrap();
        assert_eq!(new_active.id, s2.id);
    }

    #[tokio::test]
    async fn issue_create_list_delete() {
        let state = make_state();

        let issue = Issue::new("Integration test issue")
            .with_priority(IssuePriority::High)
            .with_points(3);
        let created = state.create_issue(issue).await.unwrap();
        assert_eq!(state.issue_count().await, 1);

        let deleted = state.delete_issue(created.id).await.unwrap();
        assert_eq!(deleted.title, "Integration test issue");
        assert_eq!(state.issue_count().await, 0);
    }

    #[tokio::test]
    async fn issue_prefix_search() {
        let state = make_state();
        let issue = Issue::new("Findable issue").with_priority(IssuePriority::Low);
        let created = state.create_issue(issue).await.unwrap();

        let prefix = &created.id.to_string()[..8];
        let found = state.find_issue_by_prefix(prefix).await.unwrap();
        assert_eq!(found.id, created.id);
    }

    #[tokio::test]
    async fn sprint_velocity_calculation() {
        let state = make_state();
        let sprint = make_sprint_in_state(&state, "Velocity Sprint").await;

        let mut done_issue = Issue::new("Done task").with_points(5).with_sprint(sprint.id);
        done_issue.status = IssueStatus::Done;
        let mut wip_issue = Issue::new("WIP task").with_points(3).with_sprint(sprint.id);

        state.create_issue(done_issue).await.unwrap();
        state.create_issue(wip_issue).await.unwrap();

        let (committed, completed) = state.sprint_velocity(sprint.id).await;
        assert_eq!(committed, 8);   // 5 + 3
        assert_eq!(completed, 5);  // only the Done issue
    }

    #[tokio::test]
    async fn session_lifecycle() {
        let state = make_state();
        let session = state.get_or_create_session(999).await;
        assert_eq!(session.chat_id, 999);
        assert!(session.context.is_empty());

        state.update_session(999, |s| {
            s.push_context("hello", 20);
            s.push_context("world", 20);
        }).await;

        let updated = state.get_session(999).await.unwrap();
        assert_eq!(updated.context.len(), 2);
    }

    #[tokio::test]
    async fn stale_session_cleanup() {
        let state = make_state();
        state.get_or_create_session(1).await;
        state.get_or_create_session(2).await;
        assert_eq!(state.session_count().await, 2);

        // With a 0-second timeout every session is stale
        let removed = state.cleanup_stale_sessions(0).await;
        assert_eq!(removed, 2);
        assert_eq!(state.session_count().await, 0);
    }
}

// ---------------------------------------------------------------------------
// Scrum command tests
// ---------------------------------------------------------------------------

mod scrum_tests {
    use super::*;

    #[tokio::test]
    async fn sprint_create_command() {
        let state = make_state();
        let cmd = SprintCommand::new(state.clone());
        let ctx = make_ctx("/sprint create Alpha 10");

        let resp = cmd.execute(&ctx, &["create", "Alpha", "10"]).await.unwrap();
        assert!(resp.as_str().contains("Alpha"));
        assert_eq!(state.sprint_count().await, 1);
    }

    #[tokio::test]
    async fn sprint_list_empty() {
        let state = make_state();
        let cmd = SprintCommand::new(state.clone());
        let ctx = make_ctx("/sprint list");

        let resp = cmd.execute(&ctx, &["list"]).await.unwrap();
        assert!(resp.as_str().contains("No sprints"));
    }

    #[tokio::test]
    async fn sprint_activate_and_status() {
        let state = make_state();
        let sprint = make_sprint_in_state(&state, "StatusSprint").await;
        let prefix = sprint.id.to_string()[..8].to_string();

        let cmd = SprintCommand::new(state.clone());
        let ctx = make_ctx("/sprint activate");

        let activate_resp = cmd.execute(&ctx, &["activate", &prefix]).await.unwrap();
        assert!(activate_resp.as_str().contains("ACTIVE"));

        let status_resp = cmd.execute(&ctx, &["status"]).await.unwrap();
        assert!(status_resp.as_str().contains("StatusSprint"));
    }

    #[tokio::test]
    async fn sprint_complete() {
        let state = make_state();
        let sprint = make_sprint_in_state(&state, "CompleteSprint").await;
        state.set_active_sprint(sprint.id).await.unwrap();

        let cmd = SprintCommand::new(state.clone());
        let ctx = make_ctx("/sprint complete");

        let resp = cmd.execute(&ctx, &["complete"]).await.unwrap();
        assert!(resp.as_str().contains("completed"));

        let updated = state.get_sprint(sprint.id).await.unwrap();
        assert_eq!(updated.status, SprintStatus::Completed);
    }

    #[tokio::test]
    async fn standup_with_issues() {
        let state = make_state();
        let sprint = make_sprint_in_state(&state, "StandupSprint").await;
        state.set_active_sprint(sprint.id).await.unwrap();

        let mut done = Issue::new("Done").with_points(2).with_sprint(sprint.id);
        done.status = IssueStatus::Done;
        let todo = Issue::new("Todo").with_points(3).with_sprint(sprint.id);

        state.create_issue(done).await.unwrap();
        state.create_issue(todo).await.unwrap();

        let cmd = StandupCommand::new(state.clone());
        let ctx = make_ctx("/standup");

        let resp = cmd.execute(&ctx, &[]).await.unwrap();
        let text = resp.as_str();
        assert!(text.contains("StandupSprint"));
        assert!(text.contains("DONE"));
        assert!(text.contains("TODO"));
    }

    #[tokio::test]
    async fn velocity_command() {
        let state = make_state();
        let sprint = make_sprint_in_state(&state, "VeloSprint").await;
        state.set_active_sprint(sprint.id).await.unwrap();

        let mut done = Issue::new("Done task").with_points(5).with_sprint(sprint.id);
        done.status = IssueStatus::Done;
        state.create_issue(done).await.unwrap();

        let cmd = VelocityCommand::new(state.clone());
        let ctx = make_ctx("/velocity");
        let resp = cmd.execute(&ctx, &[]).await.unwrap();
        assert!(resp.as_str().contains("5"));
    }
}

// ---------------------------------------------------------------------------
// Issue command tests
// ---------------------------------------------------------------------------

mod issue_tests {
    use super::*;

    #[tokio::test]
    async fn issue_create_with_flags() {
        let state = make_state();
        let cmd = IssueCommand::new(state.clone());
        let ctx = make_ctx("/issue create Fix auth --priority high --points 5");

        let resp = cmd
            .execute(&ctx, &["create", "Fix auth", "--priority", "high", "--points", "5"])
            .await
            .unwrap();

        assert!(resp.as_str().contains("Fix auth"));
        assert_eq!(state.issue_count().await, 1);

        let issues = state.list_issues().await;
        assert_eq!(issues[0].priority, IssuePriority::High);
        assert_eq!(issues[0].story_points, Some(5));
    }

    #[tokio::test]
    async fn issue_show() {
        let state = make_state();
        let issue = Issue::new("Show me").with_priority(IssuePriority::Critical);
        let created = state.create_issue(issue).await.unwrap();
        let prefix = created.id.to_string()[..8].to_string();

        let cmd = IssueCommand::new(state.clone());
        let ctx = make_ctx("/issue show");
        let resp = cmd.execute(&ctx, &["show", &prefix]).await.unwrap();
        assert!(resp.as_str().contains("Show me"));
        assert!(resp.as_str().contains("Critical"));
    }

    #[tokio::test]
    async fn issue_update_status_and_points() {
        let state = make_state();
        let issue = Issue::new("Updatable").with_points(3);
        let created = state.create_issue(issue).await.unwrap();
        let prefix = created.id.to_string()[..8].to_string();

        let cmd = IssueCommand::new(state.clone());
        let ctx = make_ctx("/issue update");
        let resp = cmd
            .execute(
                &ctx,
                &["update", &prefix, "--status", "inprogress", "--points", "5"],
            )
            .await
            .unwrap();

        assert!(resp.as_str().contains("In Progress"));

        let updated = state.get_issue(created.id).await.unwrap();
        assert_eq!(updated.status, IssueStatus::InProgress);
        assert_eq!(updated.story_points, Some(5));
    }

    #[tokio::test]
    async fn issue_assign() {
        let state = make_state();
        let issue = Issue::new("Assign me");
        let created = state.create_issue(issue).await.unwrap();
        let prefix = created.id.to_string()[..8].to_string();

        let cmd = IssueCommand::new(state.clone());
        let ctx = make_ctx("/issue assign");
        let resp = cmd.execute(&ctx, &["assign", &prefix, "@alice"]).await.unwrap();
        assert!(resp.as_str().contains("alice"));

        let updated = state.get_issue(created.id).await.unwrap();
        assert_eq!(updated.assignee.as_deref(), Some("alice"));
    }

    #[tokio::test]
    async fn issue_close_changes_status() {
        let state = make_state();
        let issue = Issue::new("Close me");
        let created = state.create_issue(issue).await.unwrap();
        let prefix = created.id.to_string()[..8].to_string();

        let cmd = IssueCommand::new(state.clone());
        let ctx = make_ctx("/issue close");
        cmd.execute(&ctx, &["close", &prefix]).await.unwrap();

        let updated = state.get_issue(created.id).await.unwrap();
        assert_eq!(updated.status, IssueStatus::Done);
        assert!(updated.is_complete());
    }
}

// ---------------------------------------------------------------------------
// Agent dispatcher tests
// ---------------------------------------------------------------------------

mod agent_tests {
    use super::*;

    struct EchoCommand;

    #[async_trait]
    impl AgentCommand for EchoCommand {
        fn name(&self) -> &str { "echo" }
        fn description(&self) -> &str { "Echo back the args" }
        fn aliases(&self) -> &[&str] { &["e"] }

        async fn execute(
            &self,
            _ctx: &Context,
            args: &[&str],
            _state: Arc<AppState>,
        ) -> Result<Response> {
            Ok(Response::text(args.join(" ")))
        }
    }

    #[tokio::test]
    async fn dispatch_registered_command() {
        let state = make_state();
        let agent = Agent::new(state).register(Arc::new(EchoCommand));
        let ctx = make_ctx("/echo hello world");
        let resp = agent.dispatch(&ctx, "/echo hello world").await.unwrap();
        assert_eq!(resp.as_str(), "hello world");
    }

    #[tokio::test]
    async fn dispatch_by_alias() {
        let state = make_state();
        let agent = Agent::new(state).register(Arc::new(EchoCommand));
        let ctx = make_ctx("/e foo");
        let resp = agent.dispatch(&ctx, "/e foo").await.unwrap();
        assert_eq!(resp.as_str(), "foo");
    }

    #[tokio::test]
    async fn unknown_slash_returns_help_hint() {
        let state = make_state();
        let agent = Agent::new(state);
        let ctx = make_ctx("/nonexistent");
        let resp = agent.dispatch(&ctx, "/nonexistent").await.unwrap();
        assert!(resp.as_str().contains("Unknown"));
    }

    #[tokio::test]
    async fn free_text_without_ollama_returns_fallback() {
        let state = make_state();
        let agent = Agent::new(state);
        let ctx = make_ctx("What is the velocity of my sprint?");
        let resp = agent
            .dispatch(&ctx, "What is the velocity of my sprint?")
            .await
            .unwrap();
        assert!(!resp.is_empty());
    }

    #[tokio::test]
    async fn fn_agent_command_works() {
        let state = make_state();
        let cmd = FnAgentCommand::new("greet", "Say hello", |_ctx, _args, _state| async move {
            Ok(Response::text("Hello from FnAgentCommand!"))
        });
        let agent = Agent::new(state).register(Arc::new(cmd) as _);
        let ctx = make_ctx("/greet");
        let resp = agent.dispatch(&ctx, "/greet").await.unwrap();
        assert_eq!(resp.as_str(), "Hello from FnAgentCommand!");
    }

    #[tokio::test]
    async fn command_registry_lookup() {
        let mut reg = CommandRegistry::new();
        reg.register(Arc::new(EchoCommand));
        assert!(reg.get("echo").is_some());
        assert!(reg.get("/echo").is_some());  // strip leading '/'
        assert!(reg.get("e").is_some());       // alias
        assert!(reg.get("unknown").is_none());
    }
}

// ---------------------------------------------------------------------------
// Persistence tests
// ---------------------------------------------------------------------------

mod persistence_tests {
    use super::*;

    #[tokio::test]
    async fn sprint_and_issue_round_trip() {
        let store = PersistenceStore::in_memory().await.unwrap();

        let sprint = Sprint::new("Persist Sprint", Utc::now(), Utc::now() + Duration::days(7));
        store.save_sprint(&sprint).await.unwrap();

        let issue = Issue::new("Persist Issue")
            .with_sprint(sprint.id)
            .with_points(8)
            .with_priority(IssuePriority::High);
        store.save_issue(&issue).await.unwrap();

        let (sc, ic) = store.row_counts().await.unwrap();
        assert_eq!(sc, 1);
        assert_eq!(ic, 1);

        let loaded_sprints = store.load_sprints().await.unwrap();
        assert_eq!(loaded_sprints[0].name, "Persist Sprint");

        let loaded_issues = store.load_issues().await.unwrap();
        assert_eq!(loaded_issues[0].title, "Persist Issue");
        assert_eq!(loaded_issues[0].story_points, Some(8));
    }

    #[tokio::test]
    async fn flush_state_to_db() {
        let store = PersistenceStore::in_memory().await.unwrap();
        let state = make_state();

        // Create data in state
        let sprint = Sprint::new("Flush Sprint", Utc::now(), Utc::now() + Duration::days(14));
        state.create_sprint(sprint).await.unwrap();
        let issue = Issue::new("Flush Issue");
        state.create_issue(issue).await.unwrap();

        // Flush to DB
        store.flush_state(&state).await.unwrap();

        let (sc, ic) = store.row_counts().await.unwrap();
        assert_eq!(sc, 1);
        assert_eq!(ic, 1);
    }

    #[tokio::test]
    async fn health_check_passes() {
        use telegram_bot_sdk::integrations::Integration;
        let store = PersistenceStore::in_memory().await.unwrap();
        assert!(store.health_check().await.is_ok());
    }
}

// ---------------------------------------------------------------------------
// Type / Response tests
// ---------------------------------------------------------------------------

mod types_tests {
    use super::*;
    use telegram_bot_sdk::types::{Message, User};

    #[test]
    fn user_display_name() {
        let u = User { id: 1, username: Some("bob".into()), first_name: "Bob".into(),
            last_name: None, is_bot: false, language_code: None };
        assert_eq!(u.display_name(), "@bob");
        assert_eq!(u.mention(), "@bob");
    }

    #[test]
    fn message_command_parsing() {
        let m = Message::new(1, 1, "/issue create Something --priority high");
        assert!(m.is_command());
        assert_eq!(m.command_name(), Some("issue"));
        assert_eq!(m.command_args(), "create Something --priority high");
    }

    #[test]
    fn response_display_variants() {
        assert_eq!(Response::text("hi").to_string(), "hi");
        assert_eq!(Response::error("oops").to_string(), "oops");
        assert!(Response::Empty.is_empty());
    }

    #[test]
    fn context_metadata() {
        let msg = Message::new(1, 77, "hi");
        let ctx = Context::new(msg).with_metadata("key", "value");
        assert_eq!(ctx.metadata.get("key").map(String::as_str), Some("value"));
        assert_eq!(ctx.chat_id, 77);
    }
}
