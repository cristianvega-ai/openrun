use warp_core::settings::Setting as _;
use warpui::{App, SingletonEntity};

use super::*;
use crate::terminal::CLIAgent;
use crate::terminal::cli_agent_sessions::{
    CLIAgentInputState, CLIAgentSession, CLIAgentSessionContext, CLIAgentSessionStatus,
};
use crate::terminal::model::ansi::{BootstrappedValue, Handler as _, InitShellValue};
use crate::test_util::add_window_with_terminal;
use crate::test_util::terminal::initialize_app_for_terminal_view;

fn simulate_long_running_command(view: &mut TerminalView) {
    let mut model = view.model.lock();
    model.init_shell(InitShellValue {
        session_id: 0.into(),
        shell: "zsh".to_owned(),
        ..Default::default()
    });
    model.bootstrapped(BootstrappedValue {
        shell: "zsh".to_owned(),
        ..Default::default()
    });
    model.simulate_long_running_block("ssh localhost", "Password:");
}

fn start_cli_agent_session(view: &TerminalView, ctx: &mut ViewContext<TerminalView>) {
    let view_id = view.view_id();
    CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
        sessions.set_session(
            view_id,
            CLIAgentSession {
                agent: CLIAgent::Claude,
                status: CLIAgentSessionStatus::InProgress,
                session_context: CLIAgentSessionContext::default(),
                input_state: CLIAgentInputState::Closed,
                should_auto_toggle_input: false,
                listener: None,
                draft_text: None,
                received_rich_notification: false,
            },
            ctx,
        );
    });
}

#[test]
fn footer_is_not_rendered_for_regular_long_running_commands() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal = add_window_with_terminal(&mut app, None);

        terminal.update(&mut app, |view, ctx| {
            simulate_long_running_command(view);
            view.maybe_show_use_agent_footer_in_blocklist(ctx);

            assert!(!view.should_render_use_agent_footer(ctx));
            let model = view.model.lock();
            let active_block_index = model.block_list().active_block_index();
            assert!(
                model
                    .block_list()
                    .last_non_hidden_rich_content_block_after_block(Some(active_block_index))
                    .is_none()
            );
        });
    })
}

#[test]
fn footer_is_rendered_while_a_cli_agent_session_is_active() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal = add_window_with_terminal(&mut app, None);

        terminal.update(&mut app, |view, ctx| {
            simulate_long_running_command(view);
            start_cli_agent_session(view, ctx);
            view.maybe_show_use_agent_footer_in_blocklist(ctx);

            assert!(view.should_render_use_agent_footer(ctx));
            let model = view.model.lock();
            let active_block_index = model.block_list().active_block_index();
            let rendered_footer_view_id = model
                .block_list()
                .last_non_hidden_rich_content_block_after_block(Some(active_block_index))
                .map(|(_, item)| item.view_id);
            assert_eq!(rendered_footer_view_id, Some(view.use_agent_footer.id()));
        });
    })
}

#[test]
fn footer_respects_the_cli_agent_footer_setting() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal = add_window_with_terminal(&mut app, None);

        terminal.update(&mut app, |view, ctx| {
            simulate_long_running_command(view);
            start_cli_agent_session(view, ctx);
            CLIAgentSettings::handle(ctx).update(ctx, |settings, ctx| {
                let _ = settings
                    .should_render_cli_agent_footer
                    .set_value(false, ctx);
            });
            view.maybe_show_use_agent_footer_in_blocklist(ctx);

            assert!(!view.should_render_use_agent_footer(ctx));
        });
    })
}

#[test]
fn footer_button_toggles_the_cli_agent_rich_input() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal = add_window_with_terminal(&mut app, None);

        terminal.update(&mut app, |view, ctx| {
            simulate_long_running_command(view);
            start_cli_agent_session(view, ctx);
            assert!(!view.has_active_cli_agent_input_session(ctx));

            view.handle_use_agent_footer_event(&UseAgentToolbarEvent::OpenRichInput, ctx);
        });
        terminal.read(&app, |view, ctx| {
            assert!(view.has_active_cli_agent_input_session(ctx));
            assert!(
                view.input_mode_model()
                    .as_ref(ctx)
                    .is_prompt_input_enabled()
            );
        });

        terminal.update(&mut app, |view, ctx| {
            view.handle_use_agent_footer_event(&UseAgentToolbarEvent::OpenRichInput, ctx);
        });
        terminal.read(&app, |view, ctx| {
            assert!(!view.has_active_cli_agent_input_session(ctx));
            assert!(
                !view
                    .input_mode_model()
                    .as_ref(ctx)
                    .is_prompt_input_enabled()
            );
        });
    })
}

#[test]
fn footer_hide_event_closes_the_rich_input_and_restores_shell_mode() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal = add_window_with_terminal(&mut app, None);

        terminal.update(&mut app, |view, ctx| {
            simulate_long_running_command(view);
            start_cli_agent_session(view, ctx);
            view.open_cli_agent_rich_input(CLIAgentInputEntrypoint::FooterButton, ctx);
            assert!(view.has_active_cli_agent_input_session(ctx));
        });
        terminal.read(&app, |view, ctx| {
            assert!(
                view.input_mode_model()
                    .as_ref(ctx)
                    .is_prompt_input_enabled()
            );
        });

        terminal.update(&mut app, |view, ctx| {
            view.handle_use_agent_footer_event(&UseAgentToolbarEvent::HideRichInput, ctx);
            assert!(!view.has_active_cli_agent_input_session(ctx));
        });
        terminal.read(&app, |view, ctx| {
            assert!(
                !view
                    .input_mode_model()
                    .as_ref(ctx)
                    .is_prompt_input_enabled()
            );
        });
    })
}

#[test]
fn test_rich_input_submit_strategy_for_oh_my_pi() {
    assert_eq!(
        rich_input_submit_strategy(CLIAgent::OhMyPi),
        RichInputSubmitStrategy::BracketedPaste
    );
}

/// Hermes interprets embedded newlines as submit actions when text is written
/// directly. Bracketed paste preserves them as part of one input payload.
#[test]
fn test_rich_input_submit_strategy_for_hermes_uses_bracketed_paste() {
    assert_eq!(
        rich_input_submit_strategy(CLIAgent::Hermes),
        RichInputSubmitStrategy::BracketedPaste
    );
}
