//! Core Telegram bot — `TelegramBot` wraps a teloxide `Dispatcher`.
//!
//! Architecture:
//! - `TelegramBot::run()` starts the long-poll update loop.
//! - `BotCommand` (derives `BotCommands`) lists the slash commands visible
//!   in the Telegram UI.
//! - `handle_command` dispatches to the relevant command module.
//! - `handle_message` routes free-text to the `Agent` dispatcher.
//! - Both handlers share `Arc<AppState>` and `Arc<Agent>` via dptree deps.

use std::sync::Arc;

use teloxide::prelude::*;
use teloxide::utils::command::BotCommands;
use tracing::{debug, error, info, warn};

use crate::agent::Agent;
use crate::commands::scrum::ScrumDispatcher;
use crate::commands::issue::IssueDispatcher;
use crate::error::Result;
use crate::state::AppState;
use crate::types::{
    Context,
    Message as BotMessage,
    Response,
    User as BotUser,
};

// ---------------------------------------------------------------------------
// BotCommand enum (defines the /command list shown in Telegram)
// ---------------------------------------------------------------------------

#[derive(BotCommands, Clone, Debug)]
#[command(rename_rule = "lowercase", description = "DevFlow Finance Twin — Commands")]
pub enum BotCommand {
    #[command(description = "Start the bot and show a welcome message")]
    Start,
    #[command(description = "Show all available commands")]
    Help,
    #[command(description = "Sprint management: create, list, activate, complete, status")]
    Sprint,
    #[command(description = "Issue tracking: create, list, update, close, show")]
    Issue,
    #[command(description = "Daily standup report for the active sprint")]
    Standup,
    #[command(description = "Sprint velocity metrics")]
    Velocity,
    #[command(description = "Ask the AI agent a question")]
    Ask,
    #[command(description = "Active sprint at-a-glance status")]
    Status,
    #[command(description = "Bot and integration health check")]
    Health,
}

// ---------------------------------------------------------------------------
// TelegramBot
// ---------------------------------------------------------------------------

/// The main bot struct.  Construct once, call `run()` to start polling.
pub struct TelegramBot {
    bot: Bot,
    state: Arc<AppState>,
    agent: Arc<Agent>,
}

impl TelegramBot {
    /// Build from an explicit token string.
    pub fn new(token: impl Into<String>, state: Arc<AppState>, agent: Arc<Agent>) -> Self {
        Self {
            bot: Bot::new(token),
            state,
            agent,
        }
    }

    /// Build reading `TELOXIDE_TOKEN` (or `TELEGRAM_BOT_TOKEN`) from env.
    pub fn from_env(state: Arc<AppState>, agent: Arc<Agent>) -> Self {
        let token = std::env::var("TELOXIDE_TOKEN")
            .or_else(|_| std::env::var("TELEGRAM_BOT_TOKEN"))
            .unwrap_or_default();
        Self::new(token, state, agent)
    }

    /// Start the Telegram long-poll loop.  Blocks until Ctrl-C or error.
    pub async fn run(self) {
        info!("Starting Telegram bot...");

        let handler = Update::filter_message()
            .branch(
                dptree::entry()
                    .filter_command::<BotCommand>()
                    .endpoint(handle_command),
            )
            .endpoint(handle_message);

        Dispatcher::builder(self.bot.clone(), handler)
            .dependencies(dptree::deps![
                Arc::clone(&self.state),
                Arc::clone(&self.agent)
            ])
            .enable_ctrlc_handler()
            .build()
            .dispatch()
            .await;

        info!("Bot stopped.");
    }

    /// Returns a reference to the underlying `teloxide::Bot`.
    pub fn bot(&self) -> &Bot {
        &self.bot
    }

    pub fn state(&self) -> Arc<AppState> {
        self.state.clone()
    }

    pub fn agent(&self) -> Arc<Agent> {
        self.agent.clone()
    }
}

// ---------------------------------------------------------------------------
// Conversion helpers
// ---------------------------------------------------------------------------

/// Convert a teloxide `Message` into our SDK `Context`.
fn to_context(msg: &teloxide::types::Message) -> Context {
    let from = msg.from().map(|u| BotUser {
        id: u.id.0 as i64,
        username: u.username.clone(),
        first_name: u.first_name.clone(),
        last_name: u.last_name.clone(),
        is_bot: u.is_bot,
        language_code: u.language_code.clone(),
    });

    let bot_msg = BotMessage {
        id: msg.id.0,
        text: msg.text().map(str::to_owned),
        from: from.clone(),
        chat_id: msg.chat.id.0,
        date: msg.date,
        reply_to: None,
    };

    Context::new(bot_msg)
}

/// Send a `Response` back to a Telegram chat, handling all variants.
async fn send_response(bot: &Bot, chat_id: ChatId, response: Response) -> ResponseResult<()> {
    match response {
        Response::Text(text) => {
            bot.send_message(chat_id, text).await?;
        }
        Response::Markdown(text) => {
            // Telegram MarkdownV2 requires escaped special chars; send as plain if it errors.
            if let Err(e) = bot
                .send_message(chat_id, &text)
                .parse_mode(teloxide::types::ParseMode::MarkdownV2)
                .await
            {
                warn!("MarkdownV2 send failed ({}), retrying as plain text", e);
                bot.send_message(chat_id, text).await?;
            }
        }
        Response::Html(text) => {
            bot.send_message(chat_id, text)
                .parse_mode(teloxide::types::ParseMode::Html)
                .await?;
        }
        Response::Error(text) => {
            bot.send_message(chat_id, format!("Error: {}", text)).await?;
        }
        Response::Empty => {}
        Response::MultipleMessages(messages) => {
            for msg in messages {
                Box::pin(send_response(bot, chat_id, msg)).await?;
            }
        }
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

/// Handles Telegram slash commands recognised by `BotCommand`.
async fn handle_command(
    bot: Bot,
    msg: teloxide::types::Message,
    cmd: BotCommand,
    state: Arc<AppState>,
    agent: Arc<Agent>,
) -> ResponseResult<()> {
    let chat_id = msg.chat.id;
    let ctx = to_context(&msg);
    let text = msg.text().unwrap_or("").to_owned();

    // Record session activity.
    state
        .update_session(chat_id.0, |s| {
            s.push_context(format!("cmd: {}", text), state.config.max_context_length);
        })
        .await;

    // Parse arguments (everything after the command name).
    let parts: Vec<&str> = text.split_whitespace().collect();
    let args: &[&str] = if parts.len() > 1 { &parts[1..] } else { &[] };

    let result = match cmd {
        BotCommand::Start => handle_start(&ctx, &state).await,
        BotCommand::Help => handle_help(&ctx).await,
        BotCommand::Sprint => ScrumDispatcher::new(state.clone()).dispatch(&ctx, args).await,
        BotCommand::Issue => IssueDispatcher::new(state.clone()).dispatch(&ctx, args).await,
        BotCommand::Standup => ScrumDispatcher::new(state.clone()).standup(&ctx).await,
        BotCommand::Velocity => ScrumDispatcher::new(state.clone()).velocity(&ctx).await,
        BotCommand::Status => ScrumDispatcher::new(state.clone()).status(&ctx).await,
        BotCommand::Ask => {
            let query = args.join(" ");
            if query.is_empty() {
                Ok(Response::text("Usage: /ask <your question>"))
            } else {
                agent.dispatch(&ctx, &query).await
            }
        }
        BotCommand::Health => handle_health(&ctx, &state, &agent).await,
    };

    let response = match result {
        Ok(r) => r,
        Err(e) => {
            error!("Command handler error: {}", e);
            Response::error(format!("{}", e))
        }
    };

    send_response(&bot, chat_id, response).await
}

/// Handles non-command free-text messages — routes them to the Agent.
async fn handle_message(
    bot: Bot,
    msg: teloxide::types::Message,
    state: Arc<AppState>,
    agent: Arc<Agent>,
) -> ResponseResult<()> {
    let chat_id = msg.chat.id;

    let text = match msg.text() {
        Some(t) if !t.starts_with('/') => t.to_owned(),
        _ => return Ok(()),   // Ignore commands that weren't parsed (other bots, etc.)
    };

    let ctx = to_context(&msg);
    debug!("Free-text in chat {}: {} chars", chat_id, text.len());

    state
        .update_session(chat_id.0, |s| {
            s.push_context(format!("user: {}", text), state.config.max_context_length);
        })
        .await;

    let response = agent
        .dispatch(&ctx, &text)
        .await
        .unwrap_or_else(|e| Response::error(e.to_string()));

    send_response(&bot, chat_id, response).await
}

// ---------------------------------------------------------------------------
// Built-in command implementations
// ---------------------------------------------------------------------------

async fn handle_start(ctx: &Context, state: &AppState) -> Result<Response> {
    let name = ctx
        .user
        .as_ref()
        .map(|u| u.display_name())
        .unwrap_or_else(|| "there".to_string());

    let sprint_count = state.sprint_count().await;
    let issue_count = state.issue_count().await;
    let active = state.get_active_sprint().await;

    let sprint_line = match active {
        Some(s) => format!("Active sprint: {} ({} days left)", s.name, s.days_remaining()),
        None => "No active sprint".to_string(),
    };

    Ok(Response::text(format!(
        "Hi {}, welcome to DevFlow Finance Twin!\n\n\
         I help you manage sprints, track issues, and run scrum ceremonies.\n\n\
         Stats:\n\
         - Sprints: {}\n\
         - Issues: {}\n\
         - {}\n\n\
         Type /help to see all commands.",
        name, sprint_count, issue_count, sprint_line,
    )))
}

async fn handle_help(_ctx: &Context) -> Result<Response> {
    Ok(Response::text(BotCommand::descriptions().to_string()))
}

async fn handle_health(_ctx: &Context, state: &AppState, agent: &Agent) -> Result<Response> {
    let sprint_count = state.sprint_count().await;
    let issue_count = state.issue_count().await;
    let session_count = state.session_count().await;

    let llm_status = if agent.has_ollama() {
        "Ollama: configured"
    } else {
        "Ollama: not configured"
    };

    Ok(Response::text(format!(
        "Health Check — OK\n\
         Sprints: {}\n\
         Issues: {}\n\
         Sessions: {}\n\
         {}",
        sprint_count, issue_count, session_count, llm_status,
    )))
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

    #[tokio::test]
    async fn start_handler_returns_welcome() {
        let state = make_state();
        let ctx = Context::new(Message::new(1, 1, "/start"));
        let resp = handle_start(&ctx, &state).await.unwrap();
        assert!(resp.as_str().contains("DevFlow"));
    }

    #[tokio::test]
    async fn help_handler_lists_commands() {
        let ctx = Context::new(Message::new(1, 1, "/help"));
        let resp = handle_help(&ctx).await.unwrap();
        // BotCommands::descriptions() output contains command names.
        assert!(resp.as_str().to_lowercase().contains("sprint")
            || resp.as_str().contains("/sprint"));
    }
}
