//! Unit tests for [`InputModeModel`].
//!
//! The rich input composer of a third-party CLI agent is the only way into prompt input, so
//! these tests drive the model through [`CLIAgentSessionsModel`] the same way the terminal view
//! does.

use warpui::{App, EntityId, ModelHandle, SingletonEntity};

use super::*;
use crate::terminal::CLIAgent;
use crate::terminal::cli_agent_sessions::{
    CLIAgentSession, CLIAgentSessionContext, CLIAgentSessionStatus,
};

const PROMPT: InputConfig = InputConfig {
    input_type: InputType::Prompt,
};
const SHELL: InputConfig = InputConfig {
    input_type: InputType::Shell,
};

fn build_input_mode_model(app: &mut App, surface_id: EntityId) -> ModelHandle<InputModeModel> {
    app.add_singleton_model(|_| CLIAgentSessionsModel::new());
    app.add_model(|ctx| InputModeModel::new(surface_id, ctx))
}

fn start_cli_agent_session(app: &mut App, surface_id: EntityId) {
    CLIAgentSessionsModel::handle(app).update(app, |sessions, ctx| {
        sessions.set_session(
            surface_id,
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

fn open_rich_input(app: &mut App, surface_id: EntityId, previous: InputConfig) {
    CLIAgentSessionsModel::handle(app).update(app, |sessions, ctx| {
        sessions.open_input(surface_id, previous, true, ctx);
    });
}

fn close_rich_input(app: &mut App, surface_id: EntityId) {
    CLIAgentSessionsModel::handle(app).update(app, |sessions, ctx| {
        sessions.close_input(surface_id, false, ctx);
    });
}

fn input_config(app: &App, model: &ModelHandle<InputModeModel>) -> InputConfig {
    model.read(app, |model, _| model.input_config())
}

#[test]
fn starts_in_shell_input() {
    App::test((), |mut app| async move {
        let model = build_input_mode_model(&mut app, EntityId::new());
        assert_eq!(input_config(&app, &model), SHELL);
        model.read(&app, |model, _| {
            assert!(!model.is_prompt_input_enabled());
        });
    });
}

#[test]
fn prompt_input_is_rejected_without_an_open_rich_input() {
    App::test((), |mut app| async move {
        let surface_id = EntityId::new();
        let model = build_input_mode_model(&mut app, surface_id);

        model.update(&mut app, |model, ctx| {
            model.set_input_config(PROMPT, ctx);
            model.set_input_type(InputType::Prompt, ctx);
        });
        assert_eq!(input_config(&app, &model), SHELL);

        // A CLI agent session alone does not open the composer.
        start_cli_agent_session(&mut app, surface_id);
        model.update(&mut app, |model, ctx| {
            model.set_input_type(InputType::Prompt, ctx);
        });
        assert_eq!(input_config(&app, &model), SHELL);
    });
}

#[test]
fn prompt_input_is_accepted_while_the_rich_input_is_open() {
    App::test((), |mut app| async move {
        let surface_id = EntityId::new();
        let model = build_input_mode_model(&mut app, surface_id);
        start_cli_agent_session(&mut app, surface_id);
        open_rich_input(&mut app, surface_id, SHELL);

        model.update(&mut app, |model, ctx| {
            model.set_input_config(PROMPT, ctx);
        });
        assert_eq!(input_config(&app, &model), PROMPT);
        model.read(&app, |model, _| {
            assert!(model.is_prompt_input_enabled());
        });
    });
}

#[test]
fn prompt_input_is_rejected_for_another_surfaces_rich_input() {
    App::test((), |mut app| async move {
        let surface_id = EntityId::new();
        let other_surface_id = EntityId::new();
        let model = build_input_mode_model(&mut app, surface_id);
        start_cli_agent_session(&mut app, other_surface_id);
        open_rich_input(&mut app, other_surface_id, SHELL);

        model.update(&mut app, |model, ctx| {
            model.set_input_config(PROMPT, ctx);
        });
        assert_eq!(input_config(&app, &model), SHELL);
    });
}

#[test]
fn closing_the_rich_input_restores_the_previous_config() {
    App::test((), |mut app| async move {
        let surface_id = EntityId::new();
        let model = build_input_mode_model(&mut app, surface_id);
        start_cli_agent_session(&mut app, surface_id);
        model.update(&mut app, |model, ctx| {
            model.set_input_config(SHELL, ctx);
        });
        open_rich_input(&mut app, surface_id, SHELL);

        model.update(&mut app, |model, ctx| {
            model.set_input_config(PROMPT, ctx);
        });
        assert_eq!(input_config(&app, &model), PROMPT);

        close_rich_input(&mut app, surface_id);
        assert_eq!(input_config(&app, &model), SHELL);
    });
}

#[test]
fn bash_mode_toggle_inside_the_rich_input_round_trips_and_restores_on_close() {
    App::test((), |mut app| async move {
        let surface_id = EntityId::new();
        let model = build_input_mode_model(&mut app, surface_id);
        start_cli_agent_session(&mut app, surface_id);
        open_rich_input(&mut app, surface_id, SHELL);

        model.update(&mut app, |model, ctx| {
            model.set_input_config(PROMPT, ctx);
        });
        // The `!` prefix switches to shell input inside the composer.
        model.update(&mut app, |model, ctx| {
            model.set_input_config(SHELL, ctx);
        });
        assert_eq!(input_config(&app, &model), SHELL);
        // Exiting bash mode returns to the prompt while the composer is open.
        model.update(&mut app, |model, ctx| {
            model.set_input_config(PROMPT, ctx);
        });
        assert_eq!(input_config(&app, &model), PROMPT);

        close_rich_input(&mut app, surface_id);
        assert_eq!(input_config(&app, &model), SHELL);
    });
}

#[test]
fn other_surfaces_rich_input_events_do_not_change_the_config() {
    App::test((), |mut app| async move {
        let surface_id = EntityId::new();
        let other_surface_id = EntityId::new();
        let model = build_input_mode_model(&mut app, surface_id);
        start_cli_agent_session(&mut app, other_surface_id);

        open_rich_input(&mut app, other_surface_id, SHELL);
        close_rich_input(&mut app, other_surface_id);

        assert_eq!(input_config(&app, &model), SHELL);
    });
}

#[test]
fn emits_events_only_for_what_changed() {
    App::test((), |mut app| async move {
        let surface_id = EntityId::new();
        let model = build_input_mode_model(&mut app, surface_id);
        start_cli_agent_session(&mut app, surface_id);
        open_rich_input(&mut app, surface_id, SHELL);

        let events = std::rc::Rc::new(std::cell::RefCell::new(Vec::new()));
        let recorded = events.clone();
        app.update(|ctx| {
            ctx.subscribe_to_model(&model, move |_, event, _| {
                recorded.borrow_mut().push(event.clone());
            });
        });

        model.update(&mut app, |model, ctx| {
            model.set_input_config(PROMPT, ctx);
            // Setting the same config again is a no-op.
            model.set_input_config(PROMPT, ctx);
        });

        let events = events.borrow();
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].config, PROMPT);
    });
}

#[test]
fn persisted_ai_input_type_restores_as_shell() {
    let restored = InputConfig::from_persisted(r#"{"input_type":"AI","is_locked":true}"#)
        .expect("legacy config should parse");
    assert_eq!(restored, SHELL);

    let restored = InputConfig::from_persisted(r#"{"input_type":"AI","is_locked":false}"#)
        .expect("legacy config should parse");
    assert_eq!(restored, SHELL);
}

#[test]
fn persisted_shell_and_prompt_input_types_restore_as_shell() {
    for input_type in ["Shell", "Prompt"] {
        let json = format!(r#"{{"input_type":"{input_type}","is_locked":true}}"#);
        assert_eq!(InputConfig::from_persisted(&json), Some(SHELL));
    }
}

#[test]
fn persisted_config_restores_as_shell_and_rejects_malformed_json() {
    assert_eq!(
        InputConfig::from_persisted(r#"{"input_type":"AI"}"#),
        Some(SHELL)
    );
    assert_eq!(InputConfig::from_persisted("not json"), None);
}

#[test]
fn serialized_config_round_trips_through_the_persisted_form() {
    let json = serde_json::to_string(&PROMPT).unwrap();
    assert_eq!(InputConfig::from_persisted(&json), Some(SHELL));
    let json = serde_json::to_string(&SHELL).unwrap();
    assert_eq!(InputConfig::from_persisted(&json), Some(SHELL));
}
