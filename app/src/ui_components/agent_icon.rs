//! Source-facing helper that centralizes the derivation of the agent-icon shape
//! ([`IconWithStatusVariant`]) from the CLI-agent session model. The invariant it
//! enforces: a CLI agent session renders as the same brand color and glyph regardless of
//! which surface is rendering it (vertical tabs, pane header, notifications mailbox).
//!
//! The pure inner function in this module is exercised directly by the tests in
//! `agent_icon_tests.rs`.
use warpui::{AppContext, SingletonEntity};

use crate::terminal::CLIAgent;
use crate::terminal::cli_agent_sessions::CLIAgentSessionsModel;
use crate::terminal::view::TerminalView;
use crate::ui_components::agent_status::AgentStatus;
use crate::ui_components::icon_with_status::IconWithStatusVariant;

/// Returns the agent-icon variant for a live [`TerminalView`], or `None` when the terminal is
/// not running a CLI agent session with a known agent (plain terminal / shell), in which case
/// the caller renders a plain-terminal indicator. Plugin-backed sessions surface rich status;
/// command-detected sessions don't.
pub(crate) fn terminal_view_agent_icon_variant(
    terminal_view: &TerminalView,
    app: &AppContext,
) -> Option<IconWithStatusVariant> {
    let session = CLIAgentSessionsModel::as_ref(app).session(terminal_view.id())?;
    cli_session_icon_variant(&CLISessionInputs {
        agent: session.agent,
        has_listener: session.listener.is_some(),
        status: session.status.to_agent_status(),
        supports_rich_status: session.supports_rich_status(),
    })
}

/// CLI-session-derived inputs for the icon derivation.
struct CLISessionInputs {
    agent: CLIAgent,
    /// Whether the session is backed by a plugin listener. Plugin-backed sessions report
    /// rich status; command-detected sessions only know that an agent is running.
    has_listener: bool,
    status: AgentStatus,
    /// Whether the agent's session handler exposes rich status (plugin-backed handlers report
    /// rich status; Codex's OSC 9 handler does not).
    supports_rich_status: bool,
}

/// Pure derivation from primitive inputs to an [`IconWithStatusVariant`]. A session with a
/// known (non-Unknown) agent gets its brand icon; status is only meaningful when the session
/// is plugin-backed and the handler exposes rich status.
fn cli_session_icon_variant(session: &CLISessionInputs) -> Option<IconWithStatusVariant> {
    if matches!(session.agent, CLIAgent::Unknown) {
        return None;
    }
    let status = (session.has_listener && session.supports_rich_status).then_some(session.status);
    Some(IconWithStatusVariant::CLIAgent {
        agent: session.agent,
        status,
    })
}

#[cfg(test)]
#[path = "agent_icon_tests.rs"]
mod tests;
