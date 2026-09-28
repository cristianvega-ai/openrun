use settings::Setting as _;
use warpui::{App, EntityId, SingletonEntity};

use super::*;
use crate::terminal::cli_agent_sessions::{
    CLIAgentInputState, CLIAgentSession, CLIAgentSessionContext, CLIAgentSessionStatus,
};
use crate::terminal::session_settings::CLIAgentToolbarChipSelection;
use crate::test_util::add_window_with_terminal;
use crate::test_util::terminal::initialize_app_for_terminal_view;

fn claude_session() -> CLIAgentSession {
    CLIAgentSession {
        agent: CLIAgent::Claude,
        status: CLIAgentSessionStatus::InProgress,
        session_context: CLIAgentSessionContext::default(),
        input_state: CLIAgentInputState::Closed,
        should_auto_toggle_input: false,
        listener: None,
        draft_text: None,
        received_rich_notification: false,
    }
}

fn rendered_child_ids(footer: &CLIAgentFooter, ctx: &AppContext) -> Vec<EntityId> {
    footer.render(ctx).debug_child_view_ids()
}

#[test]
fn default_layout_renders_the_cli_controls() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal = add_window_with_terminal(&mut app, None);
        let footer = terminal.read(&app, |view, ctx| {
            view.input().as_ref(ctx).cli_agent_footer().clone()
        });

        app.update(|ctx| {
            let view_id = terminal.id();
            CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
                sessions.set_session(view_id, claude_session(), ctx);
            });
        });

        footer.read(&app, |footer, ctx| {
            let child_ids = rendered_child_ids(footer, ctx);
            assert!(child_ids.contains(&footer.file_button.id()));
            assert!(child_ids.contains(&footer.rich_input_button.id()));
            assert!(child_ids.contains(&footer.settings_button.id()));
        });
    });
}

#[test]
fn custom_layout_only_renders_the_chosen_controls() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal = add_window_with_terminal(&mut app, None);
        let footer = terminal.read(&app, |view, ctx| {
            view.input().as_ref(ctx).cli_agent_footer().clone()
        });

        app.update(|ctx| {
            let view_id = terminal.id();
            CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
                sessions.set_session(view_id, claude_session(), ctx);
            });
            SessionSettings::handle(ctx).update(ctx, |settings, ctx| {
                settings
                    .cli_agent_footer_chip_selection
                    .set_value(
                        CLIAgentToolbarChipSelection::Custom {
                            left: vec![CLIAgentToolbarItemKind::Settings].into(),
                            right: vec![].into(),
                        },
                        ctx,
                    )
                    .unwrap();
            });
        });

        footer.read(&app, |footer, ctx| {
            let child_ids = rendered_child_ids(footer, ctx);
            assert!(child_ids.contains(&footer.settings_button.id()));
            assert!(!child_ids.contains(&footer.file_button.id()));
            assert!(!child_ids.contains(&footer.rich_input_button.id()));
        });
    });
}
