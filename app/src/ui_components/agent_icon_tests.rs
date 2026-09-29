use super::{CLISessionInputs, cli_session_icon_variant};
use crate::terminal::CLIAgent;
use crate::ui_components::agent_status::AgentStatus;
use crate::ui_components::icon_with_status::IconWithStatusVariant;

/// Projection of the fields we care about. [`IconWithStatusVariant`] itself can't derive
/// `PartialEq` because `NeutralElement` carries a `Box<dyn Element>`.
fn cli_fields(variant: Option<IconWithStatusVariant>) -> Option<(CLIAgent, Option<AgentStatus>)> {
    match variant? {
        IconWithStatusVariant::CLIAgent { agent, status } => Some((agent, status)),
        IconWithStatusVariant::OzAgent { .. }
        | IconWithStatusVariant::Neutral { .. }
        | IconWithStatusVariant::NeutralElement { .. } => {
            panic!("a CLI agent session must only produce the CLI agent variant")
        }
    }
}

fn session(
    agent: CLIAgent,
    has_listener: bool,
    status: AgentStatus,
    supports_rich_status: bool,
) -> CLISessionInputs {
    CLISessionInputs {
        agent,
        has_listener,
        status,
        supports_rich_status,
    }
}

#[test]
fn plugin_backed_session_shows_status() {
    assert_eq!(
        cli_fields(cli_session_icon_variant(&session(
            CLIAgent::Claude,
            true,
            AgentStatus::InProgress,
            true
        ))),
        Some((CLIAgent::Claude, Some(AgentStatus::InProgress)))
    );
    assert_eq!(
        cli_fields(cli_session_icon_variant(&session(
            CLIAgent::Claude,
            true,
            AgentStatus::Blocked,
            true
        ))),
        Some((CLIAgent::Claude, Some(AgentStatus::Blocked)))
    );
}

#[test]
fn command_detected_session_hides_status() {
    assert_eq!(
        cli_fields(cli_session_icon_variant(&session(
            CLIAgent::Claude,
            false,
            AgentStatus::InProgress,
            false
        ))),
        Some((CLIAgent::Claude, None))
    );
}

#[test]
fn session_without_rich_status_support_hides_status() {
    assert_eq!(
        cli_fields(cli_session_icon_variant(&session(
            CLIAgent::Codex,
            true,
            AgentStatus::Success,
            false
        ))),
        Some((CLIAgent::Codex, None))
    );
}

#[test]
fn unknown_agent_renders_no_agent_icon() {
    assert!(
        cli_session_icon_variant(&session(
            CLIAgent::Unknown,
            true,
            AgentStatus::InProgress,
            true
        ))
        .is_none()
    );
}
