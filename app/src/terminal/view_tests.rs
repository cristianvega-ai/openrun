use std::cell::RefCell;
use std::pin::pin;
use std::rc::Rc;
use std::sync::Arc;

use repo_metadata::DirectoryWatcher;
use repo_metadata::repositories::DetectedRepositories;
use warp_terminal::model::escape_sequences::{BRACKETED_PASTE_END, BRACKETED_PASTE_START, C0};
use warp_util::local_or_remote_path::LocalOrRemotePath;
use warp_util::standardized_path::StandardizedPath;
use warpui::notification::UserNotification;
use warpui::{App, EntityIdSet, Presenter, WindowInvalidation};

use super::*;
use crate::context_chips::prompt::{Prompt, PromptConfiguration};
use crate::editor::AutosuggestionLocation;
use crate::pane_group::focus_state::PaneGroupFocusState;
use crate::pane_group::{BackingView, TerminalPaneId};
use crate::settings::import::model::ImportedConfigModel;
use crate::settings::{
    AppEditorSettings, CLIAgentSettings, RightClickBehavior, WarpPromptSeparator,
};
use crate::tab::NewSessionMenuItem;
use crate::terminal::alt_screen::should_intercept_mouse;
use crate::terminal::block_list_element::{SnackbarPoint, SnackbarTranslationMode};
use crate::terminal::block_list_viewport::{ClampingMode, ScrollLines};
use crate::terminal::cli_agent_sessions::event::{
    CLIAgentEvent, CLIAgentEventPayload, CLIAgentEventSource, CLIAgentEventType,
};
use crate::terminal::cli_agent_sessions::listener::CLIAgentSessionListener;
use crate::terminal::cli_agent_sessions::{
    CLIAgentInputState, CLIAgentSession, CLIAgentSessionContext, CLIAgentSessionStatus,
    CLIAgentSessionsModel,
};
use crate::terminal::input::{InputConfig, InputType};
use crate::terminal::local_shell::LocalShellState;
use crate::terminal::model::ansi::{self, BootstrappedValue, InitShellValue, PreexecValue};
use crate::terminal::model::blocks::{TotalIndex, insert_block};
use crate::terminal::model::grid::Dimensions as _;
use crate::terminal::model::terminal_model::WithinBlock;
use crate::terminal::session_settings::SessionSettings;
use crate::terminal::{CLIAgent, MockTerminalManager, TerminalModel, should_right_click_paste};
use crate::test_util::github_cli::CountingGitHubCli;
use crate::test_util::terminal::{
    add_window_with_id_and_terminal, initialize_app_for_terminal_view,
};
use crate::test_util::{add_window_with_terminal, assert_eventually};
use crate::view_components::find::FindWithinBlockState;
use crate::workspace::WorkspaceAction;
use crate::workspace::view::tests::{initialize_app as initialize_workspace_app, mock_workspace};

#[test]
fn focus_reporting_writes_focus_events_in_normal_screen() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal = add_window_with_terminal(&mut app, None);
        let pty_writes: Rc<RefCell<Vec<Vec<u8>>>> = Rc::new(RefCell::new(Vec::new()));
        let writes = pty_writes.clone();

        app.update(|ctx| {
            ctx.subscribe_to_view(&terminal, move |_, event, _| {
                if let Event::WriteBytesToPty { bytes } = event {
                    writes.borrow_mut().push(bytes.to_vec());
                }
            });
        });

        terminal.update(&mut app, |view, ctx| {
            let mut model = view.model.lock();
            model.simulate_long_running_block("python3 /tmp/warp_focus_test.py", "");
            assert!(!model.is_alt_screen_active());
            ansi::Handler::set_mode(&mut *model, ansi::Mode::ReportFocusInOut);
            assert!(model.is_term_mode_set(TermMode::FOCUS_IN_OUT));
            drop(model);
            assert!(view.should_report_focus(ctx));

            view.maybe_report_focus_out(ctx);
            view.maybe_report_focus_in(ctx);
        });

        assert_eq!(
            *pty_writes.borrow(),
            vec![
                escape_sequences::EscCodes::FOCUS_OUT.to_vec(),
                escape_sequences::EscCodes::FOCUS_IN.to_vec(),
            ]
        );
    })
}

#[test]
fn should_right_click_paste_true_only_without_shift_when_setting_enabled() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal = add_window_with_terminal(&mut app, None);

        SelectionSettings::handle(&app).update(&mut app, |settings, ctx| {
            let _ = settings
                .right_click_behavior
                .set_value(RightClickBehavior::Paste, ctx);
        });

        terminal.update(&mut app, |_view, ctx| {
            assert!(
                should_right_click_paste(false, ctx),
                "a bare right-click should paste once the setting is enabled"
            );
            assert!(
                !should_right_click_paste(true, ctx),
                "Shift+right-click should always reveal the context menu, even with the setting enabled"
            );
        });
    })
}

/// Right-clicking a long-running block that owns the mouse (SGR mouse reporting on) must forward
/// the raw click to the PTY as a mouse report, under both `right_click_behavior` values -- it must
/// never fall through to Paste or the block list's own context menu.
#[test]
fn block_list_right_click_forwards_to_pty_when_long_running_block_owns_mouse() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let (window_id, terminal) = add_window_with_id_and_terminal(&mut app, None);

        let pty_writes: Rc<RefCell<Vec<Vec<u8>>>> = Rc::new(RefCell::new(Vec::new()));
        let writes = pty_writes.clone();
        app.update(|ctx| {
            ctx.subscribe_to_view(&terminal, move |_, event, _| {
                if let Event::WriteBytesToPty { bytes } = event {
                    writes.borrow_mut().push(bytes.to_vec());
                }
            });
        });

        let mut updated = EntityIdSet::default();
        updated.insert(app.root_view_id(window_id).unwrap());
        let invalidation = WindowInvalidation {
            updated,
            ..Default::default()
        };
        let presenter = Rc::new(RefCell::new(Presenter::new(window_id)));

        let size_info = terminal.update(&mut app, |view, ctx| {
            let mut model = view.model.lock();
            model.simulate_long_running_block("cmd", "output");
            model.set_mode(ansi::Mode::SgrMouse);
            model.set_mode(ansi::Mode::ReportMouseClicks);
            assert!(!model.is_alt_screen_active());
            assert!(
                !should_intercept_mouse(&model, false, ctx),
                "the running command should own the mouse with SGR reporting enabled"
            );
            *view.size_info
        });

        macro_rules! rerender {
            () => {
                app.update(enclose!((presenter, invalidation) move |ctx| {
                    presenter
                        .borrow_mut()
                        .invalidate(invalidation, ctx);
                    presenter.borrow_mut().build_scene(
                        vec2f(size_info.pane_width_px, size_info.pane_height_px),
                        1.,
                        None,
                        ctx,
                    );
                }));
            };
        }

        // The block list is pinned to the bottom of the pane by default, so a lone, short block
        // sits just above the input box rather than at the top of the viewport.
        let position = vec2f(
            2. * size_info.cell_width_px.as_f32(),
            size_info.pane_height_px - 3. * size_info.cell_height_px.as_f32(),
        );

        for right_click_behavior in [RightClickBehavior::ContextMenu, RightClickBehavior::Paste] {
            SelectionSettings::handle(&app).update(&mut app, |settings, ctx| {
                let _ = settings
                    .right_click_behavior
                    .set_value(right_click_behavior, ctx);
            });
            pty_writes.borrow_mut().clear();

            rerender!();
            app.update(enclose!((presenter) move |ctx| {
                ctx.simulate_window_event(
                    warpui::Event::RightMouseDown {
                        position,
                        cmd: false,
                        shift: false,
                        click_count: 1,
                    },
                    window_id,
                    presenter.clone(),
                );
            }));

            let writes = pty_writes.borrow();
            assert_eq!(
                writes.len(),
                1,
                "exactly one raw mouse report should reach the PTY under {right_click_behavior:?}, got {writes:?}"
            );
            assert!(
                writes[0].starts_with(b"\x1b[<2;"),
                "expected an SGR right-button-press mouse report under {right_click_behavior:?}, got {:?}",
                writes[0]
            );
        }

        // The input box must never have received a paste from either right-click.
        let input = terminal.read(&app, |terminal, _ctx| terminal.input().clone());
        input.read(&app, |input, ctx| {
            assert_eq!(
                input.buffer_text(ctx),
                "",
                "a long-running block's right-click must never be treated as Paste"
            );
        });
    })
}

#[test]
fn block_list_shift_right_click_opens_context_menu_when_right_click_pastes() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let (window_id, terminal) = add_window_with_id_and_terminal(&mut app, None);

        let pty_writes: Rc<RefCell<Vec<Vec<u8>>>> = Rc::new(RefCell::new(Vec::new()));
        let writes = pty_writes.clone();
        app.update(|ctx| {
            ctx.subscribe_to_view(&terminal, move |_, event, _| {
                if let Event::WriteBytesToPty { bytes } = event {
                    writes.borrow_mut().push(bytes.to_vec());
                }
            });
        });

        let mut updated = EntityIdSet::default();
        updated.insert(app.root_view_id(window_id).unwrap());
        let invalidation = WindowInvalidation {
            updated,
            ..Default::default()
        };
        let presenter = Rc::new(RefCell::new(Presenter::new(window_id)));

        let size_info = terminal.update(&mut app, |view, ctx| {
            let mut model = view.model.lock();
            model.simulate_long_running_block("cmd", "output");
            assert!(!model.is_alt_screen_active());
            // No mouse reporting is enabled, so Warp -- not the running command -- owns this
            // right-click regardless of Shift.
            assert!(should_intercept_mouse(&model, false, ctx));
            *view.size_info
        });

        SelectionSettings::handle(&app).update(&mut app, |settings, ctx| {
            let _ = settings
                .right_click_behavior
                .set_value(RightClickBehavior::Paste, ctx);
        });

        macro_rules! rerender {
            () => {
                app.update(enclose!((presenter, invalidation) move |ctx| {
                    presenter
                        .borrow_mut()
                        .invalidate(invalidation, ctx);
                    presenter.borrow_mut().build_scene(
                        vec2f(size_info.pane_width_px, size_info.pane_height_px),
                        1.,
                        None,
                        ctx,
                    );
                }));
            };
        }

        // Same position as the long-running block above: a lone, short block sitting just
        // above the input box.
        let position = vec2f(
            2. * size_info.cell_width_px.as_f32(),
            size_info.pane_height_px - 3. * size_info.cell_height_px.as_f32(),
        );

        let input = terminal.read(&app, |terminal, _ctx| terminal.input().clone());
        let input_text_before = input.read(&app, |input, ctx| input.buffer_text(ctx));
        assert!(!terminal.read(&app, |view, _ctx| view.is_context_menu_open()));

        rerender!();
        app.update(enclose!((presenter) move |ctx| {
            ctx.simulate_window_event(
                warpui::Event::RightMouseDown {
                    position,
                    cmd: false,
                    shift: true,
                    click_count: 1,
                },
                window_id,
                presenter.clone(),
            );
        }));

        assert!(
            terminal.read(&app, |view, _ctx| view.is_context_menu_open()),
            "Shift+right-click must open the block's context menu, even when right-click-pastes is enabled"
        );
        assert!(
            pty_writes.borrow().is_empty(),
            "Shift+right-click must never paste to the PTY, got {:?}",
            pty_writes.borrow()
        );
        input.read(&app, |input, ctx| {
            assert_eq!(
                input.buffer_text(ctx),
                input_text_before,
                "Shift+right-click must never paste into the input box"
            );
        });
    })
}

#[test]
fn alt_screen_shift_right_click_opens_context_menu_when_right_click_pastes() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let (window_id, terminal) = add_window_with_id_and_terminal(&mut app, None);

        let pty_writes: Rc<RefCell<Vec<Vec<u8>>>> = Rc::new(RefCell::new(Vec::new()));
        let writes = pty_writes.clone();
        app.update(|ctx| {
            ctx.subscribe_to_view(&terminal, move |_, event, _| {
                if let Event::WriteBytesToPty { bytes } = event {
                    writes.borrow_mut().push(bytes.to_vec());
                }
            });
        });

        let mut updated = EntityIdSet::default();
        updated.insert(app.root_view_id(window_id).unwrap());
        let invalidation = WindowInvalidation {
            updated,
            ..Default::default()
        };
        let presenter = Rc::new(RefCell::new(Presenter::new(window_id)));

        let size_info = terminal.update(&mut app, |view, ctx| {
            let mut model = view.model.lock();
            model.set_mode(ansi::Mode::SwapScreen {
                save_cursor_and_clear_screen: true,
            });
            assert!(model.is_alt_screen_active());
            // No mouse reporting is enabled, so Warp -- not the alt-screen application -- owns
            // this right-click, with or without Shift.
            assert!(should_intercept_mouse(&model, false, ctx));
            assert!(should_intercept_mouse(&model, true, ctx));
            *view.size_info
        });

        SelectionSettings::handle(&app).update(&mut app, |settings, ctx| {
            let _ = settings
                .right_click_behavior
                .set_value(RightClickBehavior::Paste, ctx);
        });

        macro_rules! rerender {
            () => {
                app.update(enclose!((presenter, invalidation) move |ctx| {
                    presenter
                        .borrow_mut()
                        .invalidate(invalidation, ctx);
                    presenter.borrow_mut().build_scene(
                        vec2f(size_info.pane_width_px, size_info.pane_height_px),
                        1.,
                        None,
                        ctx,
                    );
                }));
            };
        }

        let position = vec2f(
            2. * size_info.cell_width_px.as_f32(),
            2. * size_info.cell_height_px.as_f32() - 1.,
        );

        let input = terminal.read(&app, |terminal, _ctx| terminal.input().clone());
        let input_text_before = input.read(&app, |input, ctx| input.buffer_text(ctx));
        assert!(!terminal.read(&app, |view, _ctx| view.is_context_menu_open()));

        rerender!();
        app.update(enclose!((presenter) move |ctx| {
            ctx.simulate_window_event(
                warpui::Event::RightMouseDown {
                    position,
                    cmd: false,
                    shift: true,
                    click_count: 1,
                },
                window_id,
                presenter.clone(),
            );
        }));

        assert!(
            terminal.read(&app, |view, _ctx| view.is_context_menu_open()),
            "Shift+right-click must open the alt-screen context menu, even when right-click-pastes is enabled"
        );
        assert!(
            pty_writes.borrow().is_empty(),
            "Shift+right-click must never paste to the PTY, got {:?}",
            pty_writes.borrow()
        );
        input.read(&app, |input, ctx| {
            assert_eq!(
                input.buffer_text(ctx),
                input_text_before,
                "Shift+right-click must never paste into the input box"
            );
        });
    })
}

#[test]
fn input_shift_right_click_opens_context_menu_when_right_click_pastes() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let (window_id, terminal) = add_window_with_id_and_terminal(&mut app, None);

        let pty_writes: Rc<RefCell<Vec<Vec<u8>>>> = Rc::new(RefCell::new(Vec::new()));
        let writes = pty_writes.clone();
        app.update(|ctx| {
            ctx.subscribe_to_view(&terminal, move |_, event, _| {
                if let Event::WriteBytesToPty { bytes } = event {
                    writes.borrow_mut().push(bytes.to_vec());
                }
            });
        });

        let mut updated = EntityIdSet::default();
        updated.insert(app.root_view_id(window_id).unwrap());
        let invalidation = WindowInvalidation {
            updated,
            ..Default::default()
        };
        let presenter = Rc::new(RefCell::new(Presenter::new(window_id)));

        let size_info = terminal.read(&app, |view, _ctx| *view.size_info);

        SelectionSettings::handle(&app).update(&mut app, |settings, ctx| {
            let _ = settings
                .right_click_behavior
                .set_value(RightClickBehavior::Paste, ctx);
        });

        macro_rules! rerender {
            () => {
                app.update(enclose!((presenter, invalidation) move |ctx| {
                    presenter
                        .borrow_mut()
                        .invalidate(invalidation, ctx);
                    presenter.borrow_mut().build_scene(
                        vec2f(size_info.pane_width_px, size_info.pane_height_px),
                        1.,
                        None,
                        ctx,
                    );
                }));
            };
        }

        // The input box is docked to the very bottom of the pane, below the block list.
        let position = vec2f(
            2. * size_info.cell_width_px.as_f32(),
            size_info.pane_height_px - 0.5 * size_info.cell_height_px.as_f32(),
        );

        let input = terminal.read(&app, |terminal, _ctx| terminal.input().clone());
        let input_text_before = input.read(&app, |input, ctx| input.buffer_text(ctx));
        assert!(!terminal.read(&app, |view, _ctx| view.is_context_menu_open()));

        rerender!();
        app.update(enclose!((presenter) move |ctx| {
            ctx.simulate_window_event(
                warpui::Event::RightMouseDown {
                    position,
                    cmd: false,
                    shift: true,
                    click_count: 1,
                },
                window_id,
                presenter.clone(),
            );
        }));

        assert!(
            terminal.read(&app, |view, _ctx| view.is_context_menu_open()),
            "Shift+right-click on the input box must open its context menu, even when right-click-pastes is enabled"
        );
        assert!(
            pty_writes.borrow().is_empty(),
            "Shift+right-click must never paste to the PTY, got {:?}",
            pty_writes.borrow()
        );
        input.read(&app, |input, ctx| {
            assert_eq!(
                input.buffer_text(ctx),
                input_text_before,
                "Shift+right-click must never paste into the input box"
            );
        });
    })
}

#[test]
fn waterfall_background_right_click_honors_right_click_pastes_setting() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let (window_id, terminal) = add_window_with_id_and_terminal(&mut app, None);

        terminal.update(&mut app, |_view, ctx| {
            InputModeSettings::handle(ctx).update(ctx, |input_mode_settings, ctx| {
                let _ = input_mode_settings
                    .input_mode
                    .set_value(InputMode::Waterfall, ctx);
            });
        });

        SelectionSettings::handle(&app).update(&mut app, |settings, ctx| {
            let _ = settings
                .right_click_behavior
                .set_value(RightClickBehavior::Paste, ctx);
        });

        app.update(|ctx| {
            ctx.clipboard().write(ClipboardContent::plain_text(
                "waterfall-paste-test".to_string(),
            ));
        });

        let mut updated = EntityIdSet::default();
        updated.insert(app.root_view_id(window_id).unwrap());
        let invalidation = WindowInvalidation {
            updated,
            ..Default::default()
        };
        let presenter = Rc::new(RefCell::new(Presenter::new(window_id)));

        let size_info = terminal.read(&app, |view, _ctx| *view.size_info);

        macro_rules! rerender {
            () => {
                app.update(enclose!((presenter, invalidation) move |ctx| {
                    presenter
                        .borrow_mut()
                        .invalidate(invalidation, ctx);
                    presenter.borrow_mut().build_scene(
                        vec2f(size_info.pane_width_px, size_info.pane_height_px),
                        1.,
                        None,
                        ctx,
                    );
                }));
            };
        }

        // With no blocks, both the block content height and the input's saved position height
        // are zero, so any position within the pane satisfies "outside the block"; pick a point
        // near the bottom of the pane, comfortably inside its bounds.
        let position = vec2f(
            2. * size_info.cell_width_px.as_f32(),
            size_info.pane_height_px - 0.1,
        );

        let input = terminal.read(&app, |terminal, _ctx| terminal.input().clone());
        assert!(!terminal.read(&app, |view, _ctx| view.is_context_menu_open()));

        rerender!();
        app.update(enclose!((presenter) move |ctx| {
            ctx.simulate_window_event(
                warpui::Event::RightMouseDown {
                    position,
                    cmd: false,
                    shift: false,
                    click_count: 1,
                },
                window_id,
                presenter.clone(),
            );
        }));

        assert!(
            !terminal.read(&app, |view, _ctx| view.is_context_menu_open()),
            "a bare right-click on the waterfall background must paste, not open the context menu"
        );
        input.read(&app, |input, ctx| {
            assert_eq!(
                input.buffer_text(ctx),
                "waterfall-paste-test",
                "a bare right-click on the waterfall background must paste the clipboard into the input"
            );
        });

        // Reset the input, then confirm Shift still reveals the context menu instead.
        input.update(&mut app, |input, ctx| {
            input.replace_buffer_content("", ctx);
        });

        rerender!();
        app.update(enclose!((presenter) move |ctx| {
            ctx.simulate_window_event(
                warpui::Event::RightMouseDown {
                    position,
                    cmd: false,
                    shift: true,
                    click_count: 1,
                },
                window_id,
                presenter.clone(),
            );
        }));

        assert!(
            terminal.read(&app, |view, _ctx| view.is_context_menu_open()),
            "Shift+right-click on the waterfall background must open the context menu, even when right-click-pastes is enabled"
        );
        input.read(&app, |input, ctx| {
            assert_eq!(
                input.buffer_text(ctx),
                "",
                "Shift+right-click must never paste into the input box"
            );
        });
    })
}

#[test]
fn submit_cli_agent_rich_input_restores_previous_input_config() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        CLIAgentSettings::handle(&app).update(&mut app, |settings, ctx| {
            let _ = settings
                .auto_dismiss_rich_input_after_submit
                .set_value(true, ctx);
        });

        let terminal = add_window_with_terminal(&mut app, None);

        terminal.update(&mut app, |view, ctx| {
            view.input.update(ctx, |input, ctx| {
                input
                    .input_mode_model()
                    .update(ctx, |input_mode_model, ctx| {
                        input_mode_model.set_input_config(
                            InputConfig {
                                input_type: InputType::Shell,
                            },
                            ctx,
                        );
                    });
            });

            CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
                sessions.set_session(
                    view.view_id,
                    CLIAgentSession {
                        agent: CLIAgent::Droid,
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

            view.open_cli_agent_rich_input(ctx);
            assert!(view.has_active_cli_agent_input_session(ctx));

            view.submit_cli_agent_rich_input("hello!".to_owned(), ctx);
            assert!(!view.has_active_cli_agent_input_session(ctx));
        });

        terminal.read(&app, |view, ctx| {
            let input = view.input.as_ref(ctx);
            let input_mode_model = input.input_mode_model().as_ref(ctx);

            assert_eq!(
                input_mode_model.input_config(),
                InputConfig {
                    input_type: InputType::Shell,
                }
            );
            assert!(input.editor().as_ref(ctx).buffer_text(ctx).is_empty());
        });
    })
}

#[test]
fn unregister_cli_agent_session_restores_previous_input_config() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);

        terminal.update(&mut app, |view, ctx| {
            view.input.update(ctx, |input, ctx| {
                input
                    .input_mode_model()
                    .update(ctx, |input_mode_model, ctx| {
                        input_mode_model.set_input_config(
                            InputConfig {
                                input_type: InputType::Shell,
                            },
                            ctx,
                        );
                    });
            });

            CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
                sessions.set_session(
                    view.view_id,
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

            view.open_cli_agent_rich_input(ctx);
            assert!(view.has_active_cli_agent_input_session(ctx));

            CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
                sessions.remove_session(view.view_id, ctx);
            });
            assert!(!view.has_active_cli_agent_input_session(ctx));
            assert!(
                CLIAgentSessionsModel::as_ref(ctx)
                    .session(view.view_id)
                    .is_none()
            );
        });

        terminal.read(&app, |view, ctx| {
            let input = view.input.as_ref(ctx);
            let input_mode_model = input.input_mode_model().as_ref(ctx);

            assert_eq!(
                input_mode_model.input_config(),
                InputConfig {
                    input_type: InputType::Shell,
                }
            );
            assert!(input.editor().as_ref(ctx).buffer_text(ctx).is_empty());
        });
    })
}

#[test]
fn command_first_word_and_suffix_preserves_leading_whitespace() {
    assert_eq!(
        command_first_word_and_suffix("  myssh arg"),
        Some(("myssh", " arg"))
    );
}

#[test]
fn command_first_word_and_suffix_handles_alias_without_args() {
    assert_eq!(
        command_first_word_and_suffix("  myssh"),
        Some(("myssh", ""))
    );
}

fn assert_block_has_find_match(find_model: &TerminalFindModel, block_index: BlockIndex) {
    let has_match = [GridType::PromptAndCommand, GridType::Output]
        .into_iter()
        .any(|grid_type| {
            find_model
                .async_find_controller
                .matches_for_block_grid(block_index, grid_type)
                .is_some_and(|matches| !matches.is_empty())
        });
    assert!(has_match, "Expected a find match in block {block_index:?}");
}

fn focused_find_match_block_index(find_model: &TerminalFindModel) -> Option<BlockIndex> {
    match find_model.focused_block_list_match()? {
        BlockListMatch::CommandBlock(grid_match) => Some(grid_match.block_index),
        BlockListMatch::RichContent { .. } => None,
    }
}

/// Runs `update` on the terminal view, then waits for the find it may have started to finish
/// scanning.
async fn update_and_wait_for_find(
    app: &mut App,
    terminal: &ViewHandle<TerminalView>,
    update: impl FnOnce(&mut TerminalView, &mut ViewContext<TerminalView>),
) {
    terminal.update(app, update);
    assert_eventually!(
        200 => terminal.read(app, |view, ctx| {
            !view.find_model.as_ref(ctx).is_async_find_scanning()
        }),
        "Find should finish scanning"
    );
}

fn visible_find_match_count(app: &App, terminal: &ViewHandle<TerminalView>) -> usize {
    terminal.read(app, |view, ctx| {
        view.find_model.as_ref(ctx).visible_block_list_match_count()
    })
}

impl TerminalView {
    fn is_top_of_active_block_in_viewport(
        &self,
        model: &TerminalModel,
        input_mode: InputMode,
        app: &AppContext,
    ) -> bool {
        let active_block_index = model.block_list().active_block_index();
        let viewport = self.viewport_state(model.block_list(), input_mode, app);
        viewport.is_block_in_view(active_block_index, BlockVisibilityMode::TopOfBlockVisible)
    }

    fn scroll_top_in_lines(
        &self,
        model: &TerminalModel,
        input_mode: InputMode,
        app: &AppContext,
    ) -> Lines {
        let viewport = self.viewport_state(model.block_list(), input_mode, app);
        viewport.scroll_top_in_lines()
    }

    fn is_vertically_scrollable(&self, app: &AppContext) -> bool {
        let total_block_heights = self
            .model
            .lock()
            .block_list()
            .block_heights()
            .summary()
            .height;
        let visible_rows = self.content_element_height_lines(app);
        heights_approx_gt(total_block_heights, visible_rows)
    }
}

fn read_from_clipboard(ctx: &mut ViewContext<TerminalView>) -> String {
    TerminalView::read_from_clipboard(Some(ShellFamily::Posix), ctx)
}

#[test]
fn test_insert() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal = add_window_with_terminal(&mut app, None);

        let select_text = |view: &mut TerminalView, ctx: &mut ViewContext<TerminalView>| {
            {
                let mut model = view.model.lock();
                model.start_command_execution();
                let blocks = model.block_list_mut();
                blocks.input('f');
                blocks.linefeed();
                blocks.preexec(PreexecValue::default());
                blocks.on_finish_byte_processing(&ansi::ProcessorInput::new(&[]));
            }
            view.begin_block_text_selection(
                BlockListPoint::new(1.0, 1),
                Side::Right,
                SelectionType::Semantic,
                Vector2F::zero(),
                ctx,
            );
            view.end_text_selection(ctx);
        };
        let assert_input_text_eq = |app: &mut App, expected_text: &str| {
            terminal.read(app, |view, _ctx| {
                view.input.read(app, |view, ctx| {
                    assert_eq!(view.buffer_text(ctx), String::from(expected_text));
                });
            });
        };
        let assert_selected_blocks_cardinality_eq =
            |app: &mut App, expected_cardinality: BlockSelectionCardinality| {
                terminal.read(app, |view, _ctx| {
                    assert_eq!(
                        view.selected_blocks.cardinality().as_keymap_context_value(),
                        expected_cardinality.as_keymap_context_value()
                    );
                });
            };
        let assert_selected_text_eq = |app: &mut App, expected_text: Option<String>| {
            terminal.update(app, |view, ctx| {
                let semantic_selection = SemanticSelection::as_ref(ctx);
                let model = view.model.lock();
                let context_selected_text =
                    model.selection_to_string(semantic_selection, false, ctx);
                assert_eq!(context_selected_text, expected_text);
            });
        };

        // Nothing selected
        terminal.update(&mut app, |view, ctx| {
            view.focus_terminal(ctx);
            view.typed_characters_on_terminal("hello", ctx);
        });
        assert_input_text_eq(&mut app, "hello");
        assert_selected_blocks_cardinality_eq(&mut app, BlockSelectionCardinality::None);
        assert_selected_text_eq(&mut app, None);

        // Block selected: typing keeps the selection so it can be attached as context.
        terminal.update(&mut app, |view, ctx| {
            view.selected_blocks.reset_to_single(BlockIndex::zero());
            view.focus_terminal(ctx);
            view.typed_characters_on_terminal("_this", ctx);
        });
        assert_input_text_eq(&mut app, "hello_this");
        assert_selected_blocks_cardinality_eq(&mut app, BlockSelectionCardinality::One);
        assert_selected_text_eq(&mut app, None);

        // Text selected: typing keeps the selection so it can be attached as context.
        terminal.update(&mut app, |view, ctx| {
            select_text(view, ctx);
            view.focus_terminal(ctx);
            view.typed_characters_on_terminal("_is", ctx);
        });
        assert_input_text_eq(&mut app, "hello_this_is");
        assert_selected_blocks_cardinality_eq(&mut app, BlockSelectionCardinality::None);
        assert_selected_text_eq(&mut app, Some("f".to_owned()));
    })
}

const BODY_PREFIX: &str = "Latest output: ";

/// Regression test. Tests the "Insert into Input" functionality from the context menu.
#[test]
fn test_insert_into_input() {
    // Note that this is defined as a unit test rather than an integration test since it requires precise selections
    // (where we don't want UI updates making the test brittle, due to hardcoded mouse positions).
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal = add_window_with_terminal(&mut app, None);

        // TODO: Potentially explore if we can re-use helpers from `input_test.rs` (`select_first_command_line_of_block` and `insert_dummy_block`).
        terminal.update(&mut app, |terminal_view, ctx| {
            {
                let mut terminal_model = terminal_view.model.lock();
                let blocks = terminal_model.block_list_mut();
                // Add two lines to the command grid and output grid in a new block.
                let block_index = insert_block(blocks, "cmd_a\ncmd_b\n", "output_a\noutput_b\n");
                let block = blocks.block_at(block_index).expect("block should exist");
                // Selections are inclusive of endpoint, hence we need to identify the last column to select the first command.
                let block_command_columns =
                    block.prompt_and_command_grid().grid_handler().columns();
                let command_grid_offset = block.command_grid_offset();
                // Create a selection that just spans the first line of the command grid in the block.
                blocks.start_selection(
                    BlockListPoint::new(command_grid_offset, 0),
                    SelectionType::Simple,
                    Side::Left,
                );
                blocks.update_selection(
                    BlockListPoint::new(command_grid_offset, block_command_columns),
                    Side::Right,
                );
                let selection = blocks.selection();
                assert!(selection.is_some());
            }

            terminal_view.context_menu_insert_selected_text(ctx);
        });

        let input = terminal.read(&app, |terminal, _ctx| terminal.input().clone());
        // Confirm that the input box has the correct text (the first line of the command grid was selected above).
        input.read(&app, |input, ctx| {
            assert_eq!(input.buffer_text(ctx), "cmd_a");
        });
    });
}

#[test]
fn test_copy_on_select() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        // Add some text and make sure we update the selection
        terminal.update(&mut app, |view, ctx| {
            {
                let mut model = view.model.lock();
                model.start_command_execution();
                let blocks = model.block_list_mut();

                blocks.input('f');
                blocks.input('o');
                blocks.input('o');

                blocks.linefeed();

                blocks.preexec(PreexecValue::default());

                blocks.on_finish_byte_processing(&ansi::ProcessorInput::new(&[]));
            }

            view.begin_block_text_selection(
                BlockListPoint::new(1.0, 1),
                Side::Right,
                SelectionType::Semantic,
                Vector2F::zero(),
                ctx,
            );

            let selection_settings = SelectionSettings::as_ref(ctx);
            assert!(selection_settings.copy_on_select_enabled());
            assert_eq!("", &read_from_clipboard(ctx));
            view.end_text_selection(ctx);
            assert_eq!("foo", &read_from_clipboard(ctx));
        });
    })
}

#[test]
fn test_alt_screen_copy_on_select() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.update(&mut app, |view, ctx| {
            {
                // Enter alt screen and add text
                let mut model = view.model.lock();
                model.set_mode(ansi::Mode::SwapScreen {
                    save_cursor_and_clear_screen: true,
                });
                assert!(model.is_alt_screen_active());

                model.alt_screen_mut().input('h');
            }
            // Ensure copy on select is enabled
            let selection_settings = SelectionSettings::as_ref(ctx);
            assert!(selection_settings.copy_on_select_enabled());

            // Select input
            view.begin_alt_selection(Point::new(0, 0), Side::Left, SelectionType::Simple, ctx);
            assert_eq!("", &read_from_clipboard(ctx));
            view.update_alt_selection(Point::new(0, 2), Side::Left, &Lines::zero(), ctx);
            view.end_alt_selection(ctx);
            // Ensure selection is copied
            assert_eq!("h", &read_from_clipboard(ctx));
        });
    })
}

#[test]
fn test_alt_screen_select_with_sgr_mouse() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let (window_id, terminal) = add_window_with_id_and_terminal(&mut app, None);

        let mut updated = EntityIdSet::default();
        updated.insert(app.root_view_id(window_id).unwrap());
        let invalidation = WindowInvalidation {
            updated,
            ..Default::default()
        };
        let presenter = Rc::new(RefCell::new(Presenter::new(window_id)));

        let semantic_selection = SemanticSelection::mock(true, "");

        let size_info = terminal.update(&mut app, |view, ctx| {
            {
                // Enter alt screen and enable SGR Mouse
                let mut model = view.model.lock();
                model.set_mode(ansi::Mode::SwapScreen {
                    save_cursor_and_clear_screen: true,
                });
                model.set_mode(ansi::Mode::SgrMouse);
                assert!(model.is_alt_screen_active());
                assert!(!should_intercept_mouse(&model, false, ctx));
                assert!(should_intercept_mouse(&model, true, ctx));

                // Write a bunch of characters into the alt screen.
                // ABCDEFG
                // HIJKLMN
                // OPQRSTU
                // VWXYZ[\
                // ]^_`abc
                // defghij
                // klmnopq
                // rstuvwx
                // yz{|}~
                // € ‚ƒ„…†
                // ‡ˆ‰Š‹Œ
                let mut ascii: u8 = 65;
                for _ in 0..view.size_info.rows {
                    for _ in 0..view.size_info.columns {
                        model.alt_screen_mut().input(ascii as char);
                        ascii += 1;
                    }
                }

                *view.size_info
            }
        });

        // We need to manually trigger re-renders to ensure the AltScreenElement is recreated, e.g.
        // so its `is_terminal_selecting` property will be up-to-date.
        macro_rules! rerender {
            ($app:ident, $presenter:expr_2021, $invalidation:expr_2021, $size_info:expr_2021) => {
                app.update(enclose!((presenter, invalidation) move |ctx| {
                    presenter
                        .borrow_mut()
                        .invalidate(invalidation, ctx);
                    presenter.borrow_mut().build_scene(
                        vec2f(size_info.pane_width_px, size_info.pane_height_px),
                        1.,
                        None,
                        ctx,
                    );
                }));
            }
        }

        // The start and end positions corresponds to 'J'
        // and 'a' in the grid, respectively.
        //
        // We adjust the vertical coordinates to account for padding
        // in the alt-screen.
        let start_position = vec2f(
            2. * size_info.cell_width_px.as_f32(),
            2. * size_info.cell_height_px.as_f32() - 1.,
        );
        let end_position = vec2f(
            5. * size_info.cell_width_px.as_f32(),
            5. * size_info.cell_height_px.as_f32() - 1.,
        );

        // Simulate a mouse drag from the "J" to the "a" cell.
        rerender!(app, presenter, invalidation, size_info);
        app.update(enclose!((presenter) move |ctx| {
            ctx.simulate_window_event(
                warpui::Event::LeftMouseDown {
                    position: start_position,
                    modifiers: Default::default(),
                    click_count: 1,
                    is_first_mouse: false,
                },
                window_id,
                presenter.clone(),
            );
        }));
        rerender!(app, presenter, invalidation, size_info);
        app.update(enclose!((presenter) move |ctx| {
            ctx.simulate_window_event(
                warpui::Event::LeftMouseDragged {
                    position: end_position,
                    modifiers: Default::default(),
                },
                window_id,
                presenter.clone(),
            );
        }));
        rerender!(app, presenter, invalidation, size_info);
        app.update(enclose!((presenter) move |ctx| {
            ctx.simulate_window_event(
                warpui::Event::LeftMouseUp {
                    position: end_position,
                    modifiers: Default::default(),
                },
                window_id,
                presenter.clone(),
            );
        }));

        // No selection should've occurred as we aren't intercepting mouse events.
        terminal.read(&app, |view, ctx| {
            let selected_text =
                view.model
                    .lock()
                    .selection_to_string(&semantic_selection, false, ctx);
            assert_eq!(selected_text, None);
        });

        // This time, hold Shift key for all mouse events.
        rerender!(app, presenter, invalidation, size_info);
        app.update(enclose!((presenter) move |ctx| {
            ctx.simulate_window_event(
                warpui::Event::LeftMouseDown {
                    position: start_position,
                    modifiers: ModifiersState {
                        shift: true,
                        ..Default::default()
                    },
                    click_count: 1,
                    is_first_mouse: false,
                },
                window_id,
                presenter.clone(),
            );
        }));
        rerender!(app, presenter, invalidation, size_info);
        app.update(enclose!((presenter) move |ctx| {
            ctx.simulate_window_event(
                warpui::Event::LeftMouseDragged {
                    position: end_position,
                    modifiers: ModifiersState {
                        shift: true,
                        ..Default::default()
                    },
                },
                window_id,
                presenter.clone(),
            );
        }));
        rerender!(app, presenter, invalidation, size_info);
        app.update(enclose!((presenter) move |ctx| {
            ctx.simulate_window_event(
                warpui::Event::LeftMouseUp {
                    position: end_position,
                    modifiers: ModifiersState {
                        shift: true,
                        ..Default::default()
                    },
                },
                window_id,
                presenter.clone(),
            );
        }));

        // This time we expect a selection since the Shift key had been held for this mouse drag.
        terminal.read(&app, |view, ctx| {
            let selected_text =
                view.model
                    .lock()
                    .selection_to_string(&semantic_selection, false, ctx);
            assert_eq!(selected_text.as_ref().unwrap(), "JKLMNOPQRSTUVWXYZ[\\]^_`a");
        });
    })
}

// Regression test on find bar selection crash.
#[test]
fn test_find_bar_select() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        // Add some text and make sure we update the selection
        terminal.update(&mut app, |view, ctx| {
            // Mock a block with content 'foo g'.
            {
                let mut model = view.model.lock();
                model.start_command_execution();
                let blocks = model.block_list_mut();

                blocks.input('f');
                blocks.input('o');
                blocks.input('o');

                blocks.input(' ');
                blocks.input('g');

                blocks.linefeed();

                blocks.preexec(PreexecValue::default());

                blocks.on_finish_byte_processing(&ansi::ProcessorInput::new(&[]));
            }

            // Select 'foo'.
            view.begin_block_text_selection(
                BlockListPoint::new(1.0, 1),
                Side::Right,
                SelectionType::Semantic,
                Vector2F::zero(),
                ctx,
            );

            let selection_settings = SelectionSettings::as_ref(ctx);
            assert!(selection_settings.copy_on_select_enabled());
            assert_eq!("", &read_from_clipboard(ctx));
            view.end_text_selection(ctx);
            assert_eq!("foo", &read_from_clipboard(ctx));

            // Show find bar. The find bar should have selected text 'foo' in its editor.
            view.show_find_bar(ctx);
            view.find_bar.read(ctx, |find, ctx| {
                find.editor().read(ctx, |editor, ctx| {
                    assert_eq!("foo".to_string(), editor.selected_text(ctx));
                })
            });

            // Now select 'foo g'.
            view.begin_block_text_selection(
                BlockListPoint::new(1.0, 1),
                Side::Right,
                SelectionType::Lines,
                Vector2F::zero(),
                ctx,
            );

            let selection_settings = SelectionSettings::as_ref(ctx);
            assert!(selection_settings.copy_on_select_enabled());
            assert_eq!("foo", &read_from_clipboard(ctx));
            view.end_text_selection(ctx);
            assert_eq!("foo g", &read_from_clipboard(ctx));

            // Show find bar. The find bar should have selected text 'foo g' in its editor.
            view.show_find_bar(ctx);
            view.find_bar.read(ctx, |find, ctx| {
                find.editor().read(ctx, |editor, ctx| {
                    assert_eq!("foo g".to_string(), editor.selected_text(ctx));
                })
            });
        });
    })
}

#[test]
fn test_viewport_iter_most_recent_at_bottom() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.update(&mut app, |view, ctx| {
            let mut model = view.model.lock();
            model.simulate_block("ls", "foo");
            model.simulate_block("echo multiline", "bar\nhey");
            let viewport = view.viewport_state(model.block_list(), InputMode::PinnedToBottom, ctx);
            let mut iter = viewport.iter();
            let first_block = iter.next().expect("item 1");
            assert_eq!(
                Some(std::convert::Into::<BlockIndex>::into(1)),
                first_block.block_index
            );
            assert_eq!(
                std::convert::Into::<TotalIndex>::into(1),
                first_block.entry_index
            );
            assert!(first_block.block_height_item.height().into_lines() > Lines::zero());
            assert_eq!(
                Some(std::convert::Into::<BlockIndex>::into(1)),
                viewport.topmost_visible_block()
            );

            let second_block = iter.next().expect("item 2");
            assert_eq!(
                Some(std::convert::Into::<BlockIndex>::into(2)),
                second_block.block_index
            );
            assert_eq!(
                std::convert::Into::<TotalIndex>::into(2),
                second_block.entry_index
            );
            assert!(
                second_block.block_height_item.height() > first_block.block_height_item.height()
            );
            assert!(viewport.is_block_in_view(
                std::convert::Into::<BlockIndex>::into(2),
                BlockVisibilityMode::TopOfBlockVisible
            ));

            // The empty active block has no height, so the viewport skips it.
            assert!(iter.next().is_none());
        });
    })
}

#[test]
fn test_viewport_iter_most_recent_at_top() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.update(&mut app, |view, ctx: &mut ViewContext<'_, TerminalView>| {
            let mut model = view.model.lock();
            model.simulate_block("ls", "foo");
            model.simulate_block("echo multiline", "bar\nhey");
            let viewport = view.viewport_state(model.block_list(), InputMode::PinnedToTop, ctx);
            let mut iter = viewport.iter();
            let echo_block = iter.next().expect("item 2");
            assert_eq!(
                Some(std::convert::Into::<BlockIndex>::into(2)),
                echo_block.block_index
            );
            assert_eq!(
                std::convert::Into::<TotalIndex>::into(2),
                echo_block.entry_index
            );
            assert!(echo_block.block_height_item.height().into_lines() > Lines::zero());
            assert_eq!(Pixels::zero(), viewport.offset_to_top_of_first_block(ctx));
            assert_eq!(
                Some(std::convert::Into::<BlockIndex>::into(2)),
                viewport.topmost_visible_block()
            );
            assert!(viewport.is_block_in_view(
                std::convert::Into::<BlockIndex>::into(2),
                BlockVisibilityMode::TopOfBlockVisible
            ));

            let ls_block = iter.next().expect("item 1");
            assert_eq!(
                Some(std::convert::Into::<BlockIndex>::into(1)),
                ls_block.block_index
            );
            assert_eq!(
                std::convert::Into::<TotalIndex>::into(1),
                ls_block.entry_index
            );
            assert!(
                echo_block.block_height_item.height().as_f64()
                    > ls_block.block_height_item.height().as_f64()
            );
        });
    })
}

#[test]
fn test_viewport_most_recent_at_top() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.update(&mut app, |view, ctx| {
            let mut model = view.model.lock();
            model.simulate_block("ls", "foo");
            model.simulate_block("echo multiline", "bar\nhey");
            let viewport = view.viewport_state(model.block_list(), InputMode::PinnedToTop, ctx);
            // Most recent block should be visible.
            let topmost_visible_block = viewport.topmost_visible_block().unwrap();
            assert!(viewport.is_block_in_view(
                topmost_visible_block,
                BlockVisibilityMode::TopOfBlockVisible
            ));
            assert_eq!(Pixels::zero(), viewport.offset_to_top_of_first_block(ctx));
            assert_eq!(0., viewport.scroll_top_in_lines().as_f64());
            assert!(matches!(
                viewport.next_scroll_position(
                    ScrollPositionUpdate::AfterScrollEvent {
                        scroll_delta: 1.0.into_lines()
                    },
                    ctx
                ),
                ScrollPosition::FixedAtPosition { .. }
            ));
            assert_eq!(
                Lines::zero(),
                viewport.top_of_block_in_lines(topmost_visible_block)
            );
            assert!(matches!(
                viewport.scroll_position_at_bottom_of_block(topmost_visible_block),
                ScrollPosition::FollowsBottomOfMostRecentBlock
            ));
            let block_list_point = viewport
                .screen_coord_to_blocklist_point(
                    vec2f(0., 0.),
                    SnackbarPoint {
                        coord: vec2f(0., 0.),
                        translation_mode: SnackbarTranslationMode::WithinSnackbar,
                    },
                    ClampingMode::ClampToGrid,
                )
                .unwrap();
            assert_eq!(
                Some(2.into()),
                viewport.block_index_from_point(block_list_point)
            );
        });
    })
}

#[test]
fn test_scroll_fixed_to_bottom() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.read(&app, |view, _| {
            assert_eq!(
                view.scroll_position(),
                ScrollPosition::FollowsBottomOfMostRecentBlock
            );
        });
        terminal.update(&mut app, |view, ctx| {
            {
                let mut model = view.model.lock();
                // Put in enough blocks so that the view should be scrollable
                for _ in 0..100 {
                    model.simulate_block("ls", "foo");
                }
            }
            assert!(view.is_vertically_scrollable(ctx));
            assert_eq!(
                view.scroll_position(),
                ScrollPosition::FollowsBottomOfMostRecentBlock
            );
            view.scroll(1.0.into_lines(), ctx);

            let expected_scroll_top = {
                let model = view.model.lock();
                model.block_list().block_heights().summary().height
                    - view.content_element_height_lines(ctx)
                    - 1.0.into_lines()
            };
            assert_eq!(
                view.scroll_position(),
                ScrollPosition::FixedAtPosition {
                    scroll_lines: ScrollLines::ScrollTop(expected_scroll_top)
                },
            );
            // Now add to the active block and make sure we don't scroll
            {
                let mut model = view.model.lock();
                model.simulate_cmd("test");
            }
            {
                let mut model = view.model.lock();
                for _ in 0..100 {
                    model.linefeed();
                }
            }
            assert_eq!(
                view.scroll_position(),
                ScrollPosition::FixedAtPosition {
                    scroll_lines: ScrollLines::ScrollTop(expected_scroll_top)
                },
            );
        });
    })
}

#[test]
fn test_scroll_to_row() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.update(&mut app, |view, ctx| {
            {
                let mut model = view.model.lock();
                // Put in enough blocks so that the view should be scrollable
                for _ in 0..50 {
                    model.simulate_block("ls", "foo\nfie\nfay\nfoe\nfum");
                }
            }

            assert!(view.is_vertically_scrollable(ctx));
            assert_eq!(
                view.scroll_position(),
                ScrollPosition::FollowsBottomOfMostRecentBlock
            );

            // Scroll upwards (no snackbar)
            let a = BlockListPoint::new(30.0, 0);
            view.scroll_to_row_if_not_visible(a.row.into_lines(), ctx);
            assert_eq!(
                view.scroll_position(),
                ScrollPosition::FixedAtPosition {
                    scroll_lines: ScrollLines::ScrollTop(30.0.into_lines())
                }
            );

            // Don't scroll at all
            let b = BlockListPoint::new(38.0, 0);
            view.scroll_to_row_if_not_visible(b.row.into_lines(), ctx);
            assert_eq!(
                view.scroll_position(),
                ScrollPosition::FixedAtPosition {
                    scroll_lines: ScrollLines::ScrollTop(30.0.into_lines())
                }
            );

            // Scroll downwards
            let c = BlockListPoint::new(100.0, 0);
            view.scroll_to_row_if_not_visible(c.row.into_lines(), ctx);
            assert_eq!(
                view.scroll_position(),
                ScrollPosition::FixedAtPosition {
                    scroll_lines: ScrollLines::ScrollTop(90.5.into_lines())
                }
            );
        });
    })
}

#[test]
fn test_stable_scrolling_during_grid_truncation() {
    App::test((), |mut app| async move {
        const MAX_GRID_SIZE: usize = 50;
        const INPUT_MODE: InputMode = InputMode::PinnedToBottom;

        initialize_app_for_terminal_view(&mut app);
        let terminal = add_window_with_terminal(&mut app, None);

        // Note: this test is done in a single `update` to prevent
        // any changes in the presenter's position cache throughout.
        terminal.update(&mut app, |view, ctx| {
            // Set up the block list by creating a long-running
            // block that spans the entire viewport.
            {
                let mut model = view.model.lock();
                model.update_max_grid_size(MAX_GRID_SIZE);

                // Create a dummy, finished block and a long-running block.
                model.simulate_block("ls", "foo");
                model.simulate_long_running_block("cat", "");
                assert!(
                    model
                        .block_list()
                        .active_block()
                        .is_active_and_long_running()
                );

                // Add enough newlines so that the long-running block spans at
                // least the viewport and surely exceeds the grid size.
                let mut i = 0;
                while view.is_top_of_active_block_in_viewport(&model, INPUT_MODE, ctx)
                    || i < MAX_GRID_SIZE * 2
                {
                    model.process_bytes("\n");
                    i += 1;
                }
            }

            // Scroll up one line.
            assert_eq!(
                view.scroll_position(),
                ScrollPosition::FollowsBottomOfMostRecentBlock
            );
            view.scroll(1.into_lines(), ctx);
            assert!(matches!(
                view.scroll_position(),
                ScrollPosition::FixedWithinLongRunningBlock { .. }
            ));

            // Introduce new lines and make sure the scroll-top is adjusted as expected.
            {
                let mut model = view.model.lock();
                let active_block_index = model.block_list().active_block_index();
                let scroll_top_before_scrolling = view.scroll_top_in_lines(&model, INPUT_MODE, ctx);

                // To get to the top of the block, we need 50 lines for output grid and
                // then one line for command grid.
                for i in 1..=(MAX_GRID_SIZE + 1) {
                    model.process_bytes("\n");

                    let actual_scroll_top = view.scroll_top_in_lines(&model, INPUT_MODE, ctx);
                    let expected_scroll_top = scroll_top_before_scrolling - i.into_lines();
                    assert_eq!(actual_scroll_top, expected_scroll_top);
                }

                // Flush one full line in case the top of the block doesn't perfectly
                // line up with full lines (e.g. due to padding).
                model.process_bytes("\n");

                // Any remaining newlines should not move the scroll-top;
                // it should be "locked" at the top of the block.
                for _ in 0..MAX_GRID_SIZE {
                    model.process_bytes("\n");

                    let viewport = view.viewport_state(model.block_list(), INPUT_MODE, ctx);
                    let actual_scroll_top = viewport.scroll_top_in_lines();
                    let expected_scroll_top = viewport.top_of_block_in_lines(active_block_index);
                    assert_eq!(actual_scroll_top, expected_scroll_top);
                }
            }

            // Scroll up one line, bringing the previous block into the viewport.
            view.scroll(1.into_lines(), ctx);
            assert!(matches!(
                view.scroll_position(),
                ScrollPosition::FixedAtPosition { .. }
            ));

            // Introduce newlines and make sure the scroll-top does _not_ change anymore.
            {
                let mut model = view.model.lock();
                let scroll_top_before_newlines = view.scroll_top_in_lines(&model, INPUT_MODE, ctx);

                for _ in 0..MAX_GRID_SIZE {
                    model.process_bytes("\n");

                    let new_scroll_top = view.scroll_top_in_lines(&model, INPUT_MODE, ctx);
                    assert_eq!(scroll_top_before_newlines, new_scroll_top);
                }
            }
        });
    })
}

#[test]
fn test_clear_buffer() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.update(&mut app, |view, ctx| {
            {
                let mut model = view.model.lock();
                for _ in 0..10 {
                    model.simulate_block("ls", "foo");
                }

                assert!(!model.block_list().blocks().is_empty());
            }

            view.bookmark_block(&BlockIndex::zero(), ctx);
            view.clear_buffer(ctx);

            {
                let model = view.model.lock();

                // There should be only one precmd block.
                assert_eq!(model.block_list().blocks().len(), 1);
                assert_eq!(view.bookmarked_blocks.len(), 0);
            }
        });
    })
}

#[test]
fn test_context_menu_includes_clear_when_block_list_non_empty() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.update(&mut app, |view, ctx| {
            {
                let mut model = view.model.lock();
                model.simulate_block("ls", "foo");
                assert!(!model.is_block_list_empty());
            }

            let menu_source = BlockListMenuSource::OutsideBlockRightClick {
                position_in_terminal_view: Vector2F::zero(),
            };
            let items = view.context_menu_items(&menu_source, ctx);
            let labels: Vec<&str> = items
                .iter()
                .filter_map(|item| item.fields().map(|fields| fields.label()))
                .collect();
            assert!(
                labels.contains(&"Clear Blocks"),
                "Expected `Clear Blocks` menu item, got {labels:?}"
            );
        });
    })
}

#[test]
fn test_context_menu_omits_clear_when_block_list_empty() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.update(&mut app, |view, ctx| {
            {
                let model = view.model.lock();
                assert!(model.is_block_list_empty());
            }

            let menu_source = BlockListMenuSource::OutsideBlockRightClick {
                position_in_terminal_view: Vector2F::zero(),
            };
            let items = view.context_menu_items(&menu_source, ctx);
            let labels: Vec<&str> = items
                .iter()
                .filter_map(|item| item.fields().map(|fields| fields.label()))
                .collect();
            assert!(
                !labels.contains(&"Clear Blocks"),
                "Did not expect `Clear Blocks` menu item when block list is empty, got {labels:?}"
            );
        });
    })
}

#[test]
fn test_context_menu_omits_clear_for_text_right_click() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.update(&mut app, |view, ctx| {
            {
                let mut model = view.model.lock();
                model.simulate_block("ls", "foo");
                assert!(!model.is_block_list_empty());
            }

            let menu_source = BlockListMenuSource::RegularTextRightClick {
                position_in_terminal_view: Vector2F::zero(),
            };
            let items = view.context_menu_items(&menu_source, ctx);
            let labels: Vec<&str> = items
                .iter()
                .filter_map(|item| item.fields().map(|fields| fields.label()))
                .collect();
            assert!(
                !labels.contains(&"Clear Blocks"),
                "Did not expect `Clear Blocks` in text-selection right-click menu, got {labels:?}"
            );
        });
    })
}

#[test]
fn test_clear_buffer_clears_autosuggestion() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.update(&mut app, |view, ctx| {
            // Set a next command suggestion (empty input)
            view.input.update(ctx, |input, ctx| {
                input.editor().update(ctx, |editor, ctx| {
                    editor.set_autosuggestion(
                        "git status",
                        AutosuggestionLocation::EndOfBuffer,
                        ctx,
                    );
                });
            });

            // Verify autosuggestion is present
            view.input.read(ctx, |input, ctx| {
                input.editor().read(ctx, |editor, _ctx| {
                    assert!(
                        editor.active_autosuggestion(),
                        "Autosuggestion should be active before clear_buffer"
                    );
                });
            });

            // Clear the buffer
            view.clear_buffer(ctx);

            // Verify autosuggestion is cleared
            view.input.read(ctx, |input, ctx| {
                input.editor().read(ctx, |editor, _ctx| {
                    assert!(
                        !editor.active_autosuggestion(),
                        "Autosuggestion should be cleared after clear_buffer"
                    );
                });
            });
        });
    })
}

#[test]
fn test_bookmark_blocks_navigation() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.update(&mut app, |view, ctx| {
            {
                let mut model = view.model.lock();
                for _ in 0..10 {
                    model.simulate_block("ls", "foo");
                }

                assert!(!model.block_list().blocks().is_empty());
            }

            view.bookmark_block(&BlockIndex::zero(), ctx);
            view.bookmark_block(&BlockIndex::from(1), ctx);
            view.bookmark_block(&BlockIndex::from(4), ctx);

            view.bookmark_up(ctx);
            assert_eq!(view.selected_blocks.tail(), Some(4.into()));
            view.bookmark_down(ctx);
            assert_eq!(view.selected_blocks.tail(), Some(0.into()));
            view.bookmark_up(ctx);
            assert_eq!(view.selected_blocks.tail(), Some(4.into()));
            view.bookmark_up(ctx);
            assert_eq!(view.selected_blocks.tail(), Some(1.into()));
            view.bookmark_up(ctx);
            assert_eq!(view.selected_blocks.tail(), Some(0.into()));
            view.bookmark_down(ctx);
            assert_eq!(view.selected_blocks.tail(), Some(1.into()));
            view.bookmark_down(ctx);
            assert_eq!(view.selected_blocks.tail(), Some(4.into()));
        });
    })
}

fn run_navigation_test(input_mode: InputMode) {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.read(&app, |view, _ctx| {
            assert_eq!(
                view.scroll_position(),
                ScrollPosition::FollowsBottomOfMostRecentBlock
            );
        });
        terminal.update(&mut app, |view, ctx| {
            InputModeSettings::handle(ctx).update(ctx, |input_mode_settings, ctx| {
                let _ = input_mode_settings.input_mode.set_value(input_mode, ctx);
            });

            {
                let mut model = view.model.lock();
                // Put in enough blocks so that the view should be scrollable
                for _ in 0..100 {
                    model.simulate_block("ls", "foo");
                }

                // Put in one block that is larger than the viewport height.
                model.simulate_block("ls", "foo\n".repeat(100).as_str())
            }

            assert!(view.is_vertically_scrollable(ctx));
            assert_eq!(
                view.scroll_position(),
                ScrollPosition::FollowsBottomOfMostRecentBlock
            );

            view.select_most_recent_blocks(1, ctx);
            assert_eq!(view.selected_blocks.tail(), Some(101.into()));

            view.select_less_recent_block(false /* is_shift_down */, ctx);
            assert_eq!(view.selected_blocks.tail(), Some(100.into()));

            view.select_more_recent_block(
                true,  /* is_cmd_down */
                false, /* is_shift_down */
                ctx,
            );
            assert_ne!(
                view.scroll_position(),
                ScrollPosition::FollowsBottomOfMostRecentBlock
            );
            assert_eq!(view.selected_blocks.tail(), Some(101.into()));

            view.select_more_recent_block(
                true,  /* is_cmd_down */
                false, /* is_shift_down */
                ctx,
            );
            if input_mode.is_inverted_blocklist() {
                // In the inverted case, we intentionally align to the
                // top of the most recent block here, not to its bottom
                assert!(matches!(
                    view.scroll_position(),
                    ScrollPosition::FixedAtPosition { .. }
                ));
            } else {
                assert_eq!(
                    view.scroll_position(),
                    ScrollPosition::FollowsBottomOfMostRecentBlock
                );
            }
            assert_eq!(view.selected_blocks.tail(), Some(101.into()));

            view.select_more_recent_block(
                true,  /* is_cmd_down */
                false, /* is_shift_down */
                ctx,
            );
            assert_eq!(view.selected_blocks.tail(), None);
        });
    });
}

#[test]
fn test_navigate_blocks() {
    run_navigation_test(InputMode::PinnedToBottom);
}

// #[test]
// fn test_navigate_blocks_inverted_blocklist() {
//     run_navigation_test(InputMode::PinnedToTop);
// }

#[test]
fn test_not_bootstrapped() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.update(&mut app, |view, ctx| {
            let model = view.model.lock();
            assert!(view.is_input_box_visible(&model, ctx));
            drop(model);

            assert_eq!(view.active_session_path_if_local(ctx), None);
        });
    })
}

#[test]
fn test_block_select() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);

        terminal.update(&mut app, |view, ctx| {
            view.selected_blocks
                .toggle(10.into(), Some(11.into()), Some(9.into()));

            let single_mouse_down = BlockSelectAction::MouseDown(Some(1.into()));
            // On Mac, we use cmd-click to toggle block selections, but
            // we use ctrl-click on non-Mac platforms.
            let single_mouse_up = if cfg!(target_os = "macos") {
                BlockSelectAction::MouseUp {
                    block_index: 1.into(),
                    is_ctrl_down: false,
                    is_cmd_down: true,
                    is_shift_down: false,
                }
            } else {
                BlockSelectAction::MouseUp {
                    block_index: 1.into(),
                    is_ctrl_down: true,
                    is_cmd_down: false,
                    is_shift_down: false,
                }
            };
            view.block_select(&single_mouse_down, true, ctx);
            view.block_select(&single_mouse_up, true, ctx);
            assert!(view.selected_blocks.is_selected(1.into()));
            assert!(view.selected_blocks.is_selected(10.into()));

            let range_mouse_down = BlockSelectAction::MouseDown(Some(5.into()));
            let range_mouse_up = BlockSelectAction::MouseUp {
                block_index: 5.into(),
                is_ctrl_down: false,
                is_cmd_down: false,
                is_shift_down: true,
            };
            view.block_select(&range_mouse_down, true, ctx);
            view.block_select(&range_mouse_up, true, ctx);
            assert!(!view.selected_blocks.is_selected(10.into()));
            assert_eq!(view.selected_blocks_pivot_index(), Some(1.into()));
            assert_eq!(view.selected_blocks_tail_index(), Some(5.into()));
        });
    })
}

#[test]
fn test_select_all_blocks() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.update(&mut app, |view, ctx| {
            {
                let mut model = view.model.lock();
                // Put in enough blocks so that the view should be scrollable
                for _ in 0..100 {
                    model.simulate_block("ls", "foo");
                }
            }
            assert!(view.is_vertically_scrollable(ctx));

            view.select_all_blocks(ctx);
            assert_eq!(view.selected_blocks_pivot_index().unwrap(), 1.into());
            assert_eq!(view.selected_blocks_tail_index().unwrap(), 100.into());
            for i in 1..100 {
                assert!(view.selected_blocks.is_selected(i.into()));
            }
        });
    })
}

#[test]
fn test_expand_selection_above_and_below() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.update(&mut app, |view, ctx| {
            {
                let mut model = view.model.lock();
                // Put in enough blocks so that the view should be scrollable
                for _ in 0..100 {
                    model.simulate_block("ls", "foo");
                }
            }
            assert!(view.is_vertically_scrollable(ctx));

            // helper to ensure indices are all selected
            fn assert_all_selected(selected_blocks: &SelectedBlocks, indices: Vec<BlockIndex>) {
                for &idx in indices.iter() {
                    assert!(selected_blocks.is_selected(idx));
                }
            }

            view.selected_blocks
                .toggle(5.into(), Some(6.into()), Some(4.into()));
            assert_all_selected(&view.selected_blocks, vec![5.into()]);

            view.select_more_recent_block(
                false, /* is_cmd_down */
                true,  /* is_shift_down */
                ctx,
            );
            assert_all_selected(&view.selected_blocks, vec![5.into(), 6.into()]);

            view.select_more_recent_block(
                false, /* is_cmd_down */
                true,  /* is_shift_down */
                ctx,
            );
            assert_all_selected(&view.selected_blocks, vec![5.into(), 6.into(), 7.into()]);

            view.select_less_recent_block(true /* is_shift_down */, ctx);
            assert_all_selected(&view.selected_blocks, vec![5.into(), 6.into()]);

            view.select_less_recent_block(true /* is_shift_down */, ctx);
            assert_all_selected(&view.selected_blocks, vec![5.into()]);

            view.select_less_recent_block(true /* is_shift_down */, ctx);
            assert_all_selected(&view.selected_blocks, vec![5.into(), 4.into()]);

            view.select_more_recent_block(
                false, /* is_cmd_down */
                true,  /* is_shift_down */
                ctx,
            );
            assert_all_selected(&view.selected_blocks, vec![5.into()]);
        });
    })
}

#[test]
fn test_copy_blocks() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.update(&mut app, |view, ctx| {
            let (first_command, first_output) = ("ls", "foo");
            let (second_command, second_output) = ("pwd", "bar");

            {
                let mut model = view.model.lock();
                model.simulate_block(first_command, first_output);
                model.simulate_block(second_command, second_output);
            }

            // select a single block
            view.selected_blocks.toggle(2.into(), None, Some(1.into()));

            // test copy for a single block
            view.copy_blocks(BlockEntity::Command, ctx);
            assert_eq!(read_from_clipboard(ctx), second_command.to_string());

            view.copy_blocks(BlockEntity::Output, ctx);
            assert_eq!(read_from_clipboard(ctx), second_output.to_string());

            view.copy_blocks(BlockEntity::CommandAndOutput, ctx);
            assert_eq!(
                read_from_clipboard(ctx),
                format!("{second_command}\n{second_output}")
            );

            // select another block (in reverse)
            view.selected_blocks.toggle(1.into(), Some(2.into()), None);

            // test copy semantics for multiple blocks
            view.copy_blocks(BlockEntity::Command, ctx);
            let expected_commands_str = format!("{first_command}\n{second_command}");
            assert_eq!(read_from_clipboard(ctx), expected_commands_str);

            view.copy_blocks(BlockEntity::Output, ctx);
            let expected_outputs_str = format!("{first_output}\n{second_output}");
            assert_eq!(read_from_clipboard(ctx), expected_outputs_str);

            view.copy_blocks(BlockEntity::CommandAndOutput, ctx);
            let expected_both_str =
                format!("{first_command}\n{first_output}\n{second_command}\n{second_output}");
            assert_eq!(read_from_clipboard(ctx), expected_both_str);
        });
    })
}

#[test]
fn test_reinput_blocks() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.update(&mut app, |view, ctx| {
            let (first_command, first_output) = ("ls", "foo");
            let (second_command, second_output) = ("pwd", "bar");

            {
                let mut model = view.model.lock();
                model.simulate_block(first_command, first_output);
                model.simulate_block(second_command, second_output);
            }

            // test reinput command for single block
            view.selected_blocks.toggle(2.into(), None, Some(1.into()));
            view.reinput_commands(false /* as_root */, ctx);
            assert_eq!(view.input().as_ref(ctx).buffer_text(ctx), second_command);

            view.selected_blocks.reset();
            view.selected_blocks.toggle(2.into(), None, Some(1.into()));
            view.reinput_commands(true /* as_root */, ctx);
            assert_eq!(
                view.input().as_ref(ctx).buffer_text(ctx),
                format!("sudo {second_command}")
            );

            // test reinput commands for multiple blocks (selected in reverse)
            view.selected_blocks.reset();
            view.selected_blocks.toggle(2.into(), None, Some(1.into()));
            view.selected_blocks.toggle(1.into(), Some(2.into()), None);
            view.reinput_commands(false /* as_root */, ctx);
            assert_eq!(
                view.input().as_ref(ctx).buffer_text(ctx),
                format!("{first_command}\n{second_command}")
            );

            view.selected_blocks.reset();
            view.selected_blocks.toggle(2.into(), None, Some(1.into()));
            view.selected_blocks.toggle(1.into(), Some(2.into()), None);
            view.reinput_commands(true /* as_root */, ctx);
            assert_eq!(
                view.input().as_ref(ctx).buffer_text(ctx),
                format!("sudo {first_command}\nsudo {second_command}")
            );
        });
    })
}

fn run_find_test(input_mode: InputMode) {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.update(&mut app, |view, ctx| {
            InputModeSettings::handle(ctx).update(ctx, |input_mode_settings, ctx| {
                let _ = input_mode_settings.input_mode.set_value(input_mode, ctx);
            });

            let (first_command, first_output) = ("ls", "foo");
            let (second_command, second_output) = ("pwd", "foobar foo beans");
            let (third_command, third_output) = ("fools", "baz");

            {
                let mut model = view.model.lock();
                model.simulate_block(first_command, first_output);
                model.simulate_block(second_command, second_output);
                model.simulate_block(third_command, third_output);
            }

            view.show_find_bar(ctx);

            // Test without find_in_block enabled (results should be selection-agnostic)
            view.find_bar.update(ctx, |view, _ctx| {
                view.display_find_within_block = FindWithinBlockState::Disabled;
            });
        });

        // find when no block is selected
        update_and_wait_for_find(&mut app, &terminal, |view, ctx| {
            view.handle_find_event(
                &FindEvent::Update {
                    query: Some("foo".to_string()),
                },
                ctx,
            );
        })
        .await;
        assert_eq!(visible_find_match_count(&app, &terminal), 4);
        terminal.read(&app, |view, ctx| {
            assert_eq!(
                focused_find_match_block_index(view.find_model.as_ref(ctx)),
                Some(3.into())
            );
        });
        update_and_wait_for_find(&mut app, &terminal, |view, ctx| {
            view.handle_find_event(
                &FindEvent::NextMatch {
                    direction: FindDirection::Down,
                },
                ctx,
            );
        })
        .await;
        terminal.read(&app, |view, ctx| {
            let focused_block_index = focused_find_match_block_index(view.find_model.as_ref(ctx));
            if input_mode.is_inverted_blocklist() {
                // should go "down" to middle block
                assert_eq!(focused_block_index, Some(2.into()));
            } else {
                // should loop to earliest block
                assert_eq!(focused_block_index, Some(1.into()));
            }
        });

        // find when a single block is selected
        update_and_wait_for_find(&mut app, &terminal, |view, ctx| {
            view.selected_blocks.reset_to_single(2.into());
            view.handle_find_event(
                &FindEvent::Update {
                    query: Some("ls".to_string()),
                },
                ctx,
            );
        })
        .await;
        assert_eq!(visible_find_match_count(&app, &terminal), 2);
        terminal.read(&app, |view, ctx| {
            assert_block_has_find_match(view.find_model.as_ref(ctx), 1.into());
            assert_block_has_find_match(view.find_model.as_ref(ctx), 3.into());
        });

        // Test with find_in_block enabled
        terminal.update(&mut app, |view, ctx| {
            view.find_bar.update(ctx, |view, _ctx| {
                view.display_find_within_block = FindWithinBlockState::Enabled;
            });
        });

        // find when no block is selected. There is nothing to scan, so the find never reports
        // that it finished; the result is available immediately.
        terminal.update(&mut app, |view, ctx| {
            view.selected_blocks.reset();
            view.handle_find_event(
                &FindEvent::Update {
                    query: Some("foo".to_string()),
                },
                ctx,
            );
        });
        assert_eq!(visible_find_match_count(&app, &terminal), 0);

        // find when a single block is selected
        update_and_wait_for_find(&mut app, &terminal, |view, ctx| {
            view.selected_blocks.reset_to_single(2.into());
            view.handle_find_event(
                &FindEvent::Update {
                    query: Some("pwd".to_string()),
                },
                ctx,
            );
        })
        .await;
        assert_eq!(visible_find_match_count(&app, &terminal), 1);
        terminal.read(&app, |view, ctx| {
            assert_block_has_find_match(view.find_model.as_ref(ctx), 2.into());
        });

        // find when multiple blocks are selected, and find in block is enabled
        update_and_wait_for_find(&mut app, &terminal, |view, ctx| {
            view.selected_blocks.toggle(3.into(), Some(2.into()), None);
            view.handle_find_event(
                &FindEvent::Update {
                    query: Some("foo".to_string()),
                },
                ctx,
            );
        })
        .await;
        assert_eq!(visible_find_match_count(&app, &terminal), 3);
        terminal.read(&app, |view, ctx| {
            assert_block_has_find_match(view.find_model.as_ref(ctx), 2.into());
            assert_block_has_find_match(view.find_model.as_ref(ctx), 3.into());
        });
    })
}

#[test]
fn test_find_in_blocks() {
    run_find_test(InputMode::PinnedToBottom);
}

#[test]
fn test_find_in_blocks_inverted_blocklist() {
    run_find_test(InputMode::PinnedToTop);
}

#[test]
fn test_case_sensitive_find() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.update(&mut app, |view, ctx| {
            let (first_command, first_output) = ("ls", "foo");
            let (second_command, second_output) = ("pwd", "fOObar");
            let (third_command, third_output) = ("FoOls", "baz");

            {
                let mut model = view.model.lock();
                model.simulate_block(first_command, first_output);
                model.simulate_block(second_command, second_output);
                model.simulate_block(third_command, third_output);
            }

            view.show_find_bar(ctx);
        });

        // Test without case sensitivity enabled (no blocks enabled)
        update_and_wait_for_find(&mut app, &terminal, |view, ctx| {
            view.handle_find_event(
                &FindEvent::Update {
                    query: Some("fOO".to_string()),
                },
                ctx,
            );
        })
        .await;
        assert_eq!(visible_find_match_count(&app, &terminal), 3);

        // Test without case sensitivity enabled, but with find in block
        update_and_wait_for_find(&mut app, &terminal, |view, ctx| {
            view.find_bar.update(ctx, |view, _ctx| {
                view.display_find_within_block = FindWithinBlockState::Enabled;
            });
            view.selected_blocks.reset_to_single(1.into());
            view.update_find_selection(ctx);
        })
        .await;
        assert_eq!(visible_find_match_count(&app, &terminal), 1);
        terminal.read(&app, |view, ctx| {
            assert_block_has_find_match(view.find_model.as_ref(ctx), 1.into());
        });

        // Test with case sensitivity enabled (one block enabled)
        update_and_wait_for_find(&mut app, &terminal, |view, ctx| {
            view.handle_find_event(
                &FindEvent::ToggleCaseSensitivity {
                    is_case_sensitive: true,
                },
                ctx,
            );
            view.selected_blocks.reset_to_single(1.into());
            view.update_find_selection(ctx);
        })
        .await;
        assert_eq!(visible_find_match_count(&app, &terminal), 0);

        update_and_wait_for_find(&mut app, &terminal, |view, ctx| {
            view.selected_blocks.reset_to_single(2.into());
            view.update_find_selection(ctx);
        })
        .await;
        assert_eq!(visible_find_match_count(&app, &terminal), 1);
        terminal.read(&app, |view, ctx| {
            assert_block_has_find_match(view.find_model.as_ref(ctx), 2.into());
        });

        // Test with case sensitivity enabled (no blocks enabled)
        update_and_wait_for_find(&mut app, &terminal, |view, ctx| {
            view.selected_blocks.reset();
            view.find_bar.update(ctx, |view, _ctx| {
                view.display_find_within_block = FindWithinBlockState::Disabled;
            });
        })
        .await;
        assert_eq!(visible_find_match_count(&app, &terminal), 1);
        terminal.read(&app, |view, ctx| {
            assert_block_has_find_match(view.find_model.as_ref(ctx), 2.into());
        });

        // Change regex to mismatch case sensitivity across all blocks
        update_and_wait_for_find(&mut app, &terminal, |view, ctx| {
            view.handle_find_event(
                &FindEvent::Update {
                    query: Some("FOO".to_string()),
                },
                ctx,
            );
        })
        .await;
        assert_eq!(visible_find_match_count(&app, &terminal), 0);
    })
}

#[test]
fn test_find_bar_prefix_search() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.update(&mut app, |view, ctx| {
            let (command_1, output_1) = ("echo foo", "foo");
            let (command_2, output_2) = ("echo bar foo", "bar foo");

            {
                let mut model = view.model.lock();
                model.simulate_block(command_1, output_1);
                model.simulate_block(command_2, output_2);
            }

            view.show_find_bar(ctx);
        });

        // Test without regex enabled
        update_and_wait_for_find(&mut app, &terminal, |view, ctx| {
            view.handle_find_event(
                &FindEvent::Update {
                    query: Some("^foo".to_string()),
                },
                ctx,
            );
        })
        .await;
        assert_eq!(visible_find_match_count(&app, &terminal), 0);

        update_and_wait_for_find(&mut app, &terminal, |view, ctx| {
            view.handle_find_event(
                &FindEvent::ToggleRegexSearch {
                    is_regex_enabled: true,
                },
                ctx,
            );
        })
        .await;
        assert_eq!(visible_find_match_count(&app, &terminal), 1);
    });
}

#[test]
fn test_create_notification_shorter_than_max() {
    let command = "cargo run";
    let output = "error: failed to find directory";
    let command_succeeded = false;
    let block_duration = Duration::new(4, 2);

    let trigger = NotificationsTrigger::LongRunningCommand(command_succeeded, block_duration);

    let actual_content =
        trigger.create_notification_content(command.to_string(), output.to_string());

    let expected_title = format!("'{command}' failed after 4s");
    let expected_body = format!("{BODY_PREFIX}{output}");

    assert_eq!(actual_content.title, expected_title);
    assert_eq!(actual_content.body, expected_body);
}

#[test]
fn test_create_notification_as_long_as_max() {
    let expected_title_suffix = " finished after 4s";
    let max_command_len = UserNotification::MAX_TITLE_LENGTH - expected_title_suffix.len() - 2;
    let command = "a".repeat(max_command_len);

    let max_output_len = UserNotification::MAX_BODY_LENGTH - BODY_PREFIX.len();
    let output = "a".repeat(max_output_len);

    let command_succeeded = true;
    let block_duration = Duration::new(4, 2);

    let trigger = NotificationsTrigger::LongRunningCommand(command_succeeded, block_duration);

    let actual_content =
        trigger.create_notification_content(command.to_string(), output.to_string());

    let expected_title = format!("'{command}'{expected_title_suffix}");
    let expected_body = format!("{BODY_PREFIX}{output}");

    assert_eq!(actual_content.title, expected_title);
    assert_eq!(actual_content.body, expected_body);
}

#[test]
fn test_create_notification_longer_than_max() {
    let expected_title_suffix = " finished after 4s";
    let max_command_len = UserNotification::MAX_TITLE_LENGTH - expected_title_suffix.len() - 2;
    let command = "a".repeat(max_command_len + 1);

    let max_output_len = UserNotification::MAX_BODY_LENGTH - BODY_PREFIX.len();
    let output = "a".repeat(max_output_len + 1);

    let command_succeeded = true;
    let block_duration = Duration::new(4, 2);

    let trigger = NotificationsTrigger::LongRunningCommand(command_succeeded, block_duration);

    let actual_content =
        trigger.create_notification_content(command.to_string(), output.to_string());

    let expected_title = format!(
        "'{}...'{expected_title_suffix}",
        &command[..max_command_len - 3]
    );
    let expected_body = format!("{BODY_PREFIX}...{}", &output[..max_output_len - 3]);

    assert_eq!(actual_content.title, expected_title);
    assert_eq!(actual_content.body, expected_body);
}

#[test]
fn test_create_notification_char_boundaries_respected() {
    let expected_title_suffix = " finished after 4s";
    let max_command_len = UserNotification::MAX_TITLE_LENGTH - expected_title_suffix.len() - 2;
    let command = "😊".repeat(max_command_len + 1);

    let output = "error: failed to find directory";
    let command_succeeded = true;
    let block_duration = Duration::new(4, 2);

    let trigger = NotificationsTrigger::LongRunningCommand(command_succeeded, block_duration);

    let actual_content = trigger.create_notification_content(command, output.to_string());

    let expected_command_prefix = "😊".repeat(max_command_len - 3);
    let expected_title = format!("'{expected_command_prefix}...'{expected_title_suffix}",);
    assert_eq!(actual_content.title, expected_title);
}

#[test]
fn test_banner_for_incompatible_plugins() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal =
            MockTerminalManager::create_new_terminal_view_window_for_test(&mut app, None);

        SessionSettings::handle(&app).update(&mut app, |session_settings, ctx| {
            let _ = session_settings.honor_ps1.set_value(true, ctx);
        });

        terminal.update(&mut app, |view, _ctx| {
            let mut model = view.model.lock();
            model.init_shell(InitShellValue {
                session_id: 0.into(),
                shell: "zsh".to_owned(),
                ..Default::default()
            });
            model.bootstrapped(BootstrappedValue {
                shell: "zsh".to_owned(),
                shell_plugins: Some(HashSet::from(["p10k_unsupported".to_string()])),
                ..Default::default()
            });
        });

        // This is asynchronous because we're waiting for the bootstrap event
        // to be sent from the terminal model to the terminal view.
        assert_eventually!(
            200 => terminal.read(&app, |view, _ctx| view
                .is_incompatible_configuration_banner_open),
            "Banner did not open in time"
        );
    })
}

/// Regression test: the slow-bootstrap banner used to persist
/// indefinitely when shell integration never sent the bootstrap signal
/// (e.g. the user's shell `exec`s into `expect` before Warp's integration
/// runs). The auto-dismiss timer scheduled when the banner opens must
/// eventually close it.
#[test]
fn test_slow_bootstrap_banner_auto_dismisses() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal =
            MockTerminalManager::create_new_terminal_view_window_for_test(&mut app, None);

        // Open the banner directly and schedule a short-duration auto-dismiss
        // timer. We bypass `on_bootstrap_failed_timer_complete` (which itself
        // waits the 7-second bootstrap timeout) to keep this test fast — the
        // important behavior under test is the auto-dismiss path.
        terminal.update(&mut app, |view, ctx| {
            view.is_slow_bootstrap_banner_open = true;
            view.slow_bootstrap_banner_auto_dismiss_handle = Some(
                view.start_slow_bootstrap_banner_auto_dismiss_timer(Duration::from_millis(50), ctx),
            );
        });

        assert!(terminal.read(&app, |view, _ctx| view.is_slow_bootstrap_banner_open));

        assert_eventually!(
            200 => terminal.read(&app, |view, _ctx| !view.is_slow_bootstrap_banner_open
                && view.slow_bootstrap_banner_auto_dismiss_handle.is_none()),
            "Slow bootstrap banner did not auto-dismiss"
        );
    })
}

/// Regression test: when the banner is dismissed by another path
/// (manual user dismissal or a successful bootstrap event), any pending
/// auto-dismiss timer should be aborted so it can't fire after the fact.
#[test]
fn test_hide_slow_bootstrap_banner_aborts_pending_auto_dismiss() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal =
            MockTerminalManager::create_new_terminal_view_window_for_test(&mut app, None);

        terminal.update(&mut app, |view, ctx| {
            view.is_slow_bootstrap_banner_open = true;
            view.slow_bootstrap_banner_auto_dismiss_handle =
                Some(view.start_slow_bootstrap_banner_auto_dismiss_timer(
                    // Long enough that the timer can't fire before we hide.
                    Duration::from_secs(60),
                    ctx,
                ));
            view.hide_slow_bootstrap_banner(ctx);
        });

        terminal.read(&app, |view, _ctx| {
            assert!(!view.is_slow_bootstrap_banner_open);
            assert!(view.slow_bootstrap_banner_auto_dismiss_handle.is_none());
        });
    })
}

// Regression test for GH#3548 / GH#6093: the "Seems like your completions are not
// working" banner must offer a permanent "Don't show me again" dismissal that is
// persisted, while the "x" close button keeps its existing per-session behavior.
#[test]
fn test_control_master_banner_permanent_dismissal_persists() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal =
            MockTerminalManager::create_new_terminal_view_window_for_test(&mut app, None);

        terminal.update(&mut app, |view, ctx| {
            // Temporary dismissal (the "x" button) clears the banner for this session
            // but must not persist a "don't show again" preference.
            view.control_master_error_banner_state.is_open = true;
            view.handle_controlmaster_error_banner_event(
                &BannerEvent::Dismiss(DismissalType::Temporary),
                ctx,
            );
            assert!(!view.control_master_error_banner_state.is_open);
            assert!(!view.control_master_error_banner_suppressed);
            assert_eq!(
                ctx.private_user_preferences()
                    .read_value(CONTROL_MASTER_BANNER_SUPPRESSED_KEY)
                    .unwrap(),
                None,
                "temporary dismissal should not persist a preference"
            );

            // Permanent dismissal ("Don't show me again") clears the banner and persists
            // the choice so it never reopens.
            view.control_master_error_banner_state.is_open = true;
            view.handle_controlmaster_error_banner_event(
                &BannerEvent::Dismiss(DismissalType::Permanent),
                ctx,
            );
            assert!(!view.control_master_error_banner_state.is_open);
            assert!(view.control_master_error_banner_suppressed);
            assert_eq!(
                ctx.private_user_preferences()
                    .read_value(CONTROL_MASTER_BANNER_SUPPRESSED_KEY)
                    .unwrap(),
                Some("true".to_owned()),
                "permanent dismissal should persist a preference"
            );
        });
    })
}

// Regression test for GH#3548 / GH#6093: once the banner has been permanently
// dismissed it must not reopen on subsequent sessions.
#[test]
fn test_control_master_banner_suppressed_does_not_reopen() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal =
            MockTerminalManager::create_new_terminal_view_window_for_test(&mut app, None);

        terminal.update(&mut app, |view, _ctx| {
            // With no prior dismissal, the banner may open.
            view.control_master_error_banner_suppressed = false;
            assert!(view.should_open_control_master_banner());

            // Once permanently dismissed it must never reopen.
            view.control_master_error_banner_suppressed = true;
            assert!(!view.should_open_control_master_banner());
        });
    })
}

#[test]
fn test_bash_vim_banner_already_shown() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal =
            MockTerminalManager::create_new_terminal_view_window_for_test(&mut app, None);

        // Ensure the terminal is the active session.
        terminal.update(&mut app, |view, ctx| {
            let terminal_pane_id = TerminalPaneId::dummy_terminal_pane_id();
            let focus_state = ctx.add_model(|_| {
                PaneGroupFocusState::new(terminal_pane_id.into(), Some(terminal_pane_id), false)
            });
            let focus_handle = PaneFocusHandle::new(terminal_pane_id.into(), focus_state);
            view.set_focus_handle(focus_handle, ctx);
        });

        // The banner has already been shown and dismissed.
        VimBannerSettings::handle(&app).update(&mut app, |banner_settings, ctx| {
            let _ = banner_settings
                .vim_keybindings_banner_state
                .set_value(BannerState::Dismissed, ctx);
        });

        // Ensure Warp's vim keybindings are off.
        AppEditorSettings::handle(&app).update(&mut app, |editor_settings, ctx| {
            let _ = editor_settings.vim_mode.set_value(false, ctx);
        });

        // Bootstrap a bash session with vi mode enabled.
        terminal.update(&mut app, |view, _ctx| {
            let mut model = view.model.lock();
            model.init_shell(InitShellValue {
                session_id: 0.into(),
                shell: "bash".to_owned(),
                ..Default::default()
            });
            model.bootstrapped(BootstrappedValue {
                shell: "bash".to_owned(),
                shell_options: Some(HashSet::from(["vi_mode".to_string()])),
                ..Default::default()
            });
        });

        // This is asynchronous because we're waiting for the bootstrap event
        // to be sent from the terminal model to the terminal view.
        assert_eventually!(
            // Since the user already dismissed the banner, it should not
            // be shown again.
            terminal.read(&app, |terminal, _terminal_ctx| {
                terminal.inline_banners_state.vim_banner_state.is_none()
            }),
            "Banner should not have opened"
        );
    })
}

#[test]
fn test_bash_vim_banner_on() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal =
            MockTerminalManager::create_new_terminal_view_window_for_test(&mut app, None);

        // Ensure the terminal is the active session.
        terminal.update(&mut app, |view, ctx| {
            let terminal_pane_id = TerminalPaneId::dummy_terminal_pane_id();
            let focus_state = ctx.add_model(|_| {
                PaneGroupFocusState::new(terminal_pane_id.into(), Some(terminal_pane_id), false)
            });
            let focus_handle = PaneFocusHandle::new(terminal_pane_id.into(), focus_state);
            view.set_focus_handle(focus_handle, ctx);
        });

        // Ensure the banner has never been shown.
        VimBannerSettings::handle(&app).update(&mut app, |banner_settings, ctx| {
            let _ = banner_settings
                .vim_keybindings_banner_state
                .set_value(BannerState::NotDismissed, ctx);
        });

        // Ensure Warp's vim keybindings are off.
        AppEditorSettings::handle(&app).update(&mut app, |editor_settings, ctx| {
            let _ = editor_settings.vim_mode.set_value(false, ctx);
        });

        // Bootstrap a bash session with vi mode enabled.
        terminal.update(&mut app, |view, _ctx| {
            let mut model = view.model.lock();
            model.init_shell(InitShellValue {
                session_id: 0.into(),
                shell: "bash".to_owned(),
                ..Default::default()
            });
            model.bootstrapped(BootstrappedValue {
                shell: "bash".to_owned(),
                shell_options: Some(HashSet::from(["vi_mode".to_string()])),
                ..Default::default()
            });
        });

        // This is asynchronous because we're waiting for the bootstrap event
        // to be sent from the terminal model to the terminal view.
        assert_eventually!(
            // The vim keybinding banner should display.
            200 => terminal.read(&app, |terminal, _terminal_ctx| {
                terminal.inline_banners_state.vim_banner_state.is_some()
            }),
            "Banner did not open in time"
        );
    })
}

#[test]
fn test_bash_vim_banner_off() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal =
            MockTerminalManager::create_new_terminal_view_window_for_test(&mut app, None);

        // Ensure the terminal is the active session.
        terminal.update(&mut app, |view, ctx| {
            let terminal_pane_id = TerminalPaneId::dummy_terminal_pane_id();
            let focus_state = ctx.add_model(|_| {
                PaneGroupFocusState::new(terminal_pane_id.into(), Some(terminal_pane_id), false)
            });
            let focus_handle = PaneFocusHandle::new(terminal_pane_id.into(), focus_state);
            view.set_focus_handle(focus_handle, ctx);
        });

        // Ensure the banner has never been shown.
        VimBannerSettings::handle(&app).update(&mut app, |banner_settings, ctx| {
            let _ = banner_settings
                .vim_keybindings_banner_state
                .set_value(BannerState::NotDismissed, ctx);
        });

        // Ensure Warp's vim keybindings are on.
        AppEditorSettings::handle(&app).update(&mut app, |editor_settings, ctx| {
            let _ = editor_settings.vim_mode.set_value(true, ctx);
        });

        // Bootstrap a bash session with vi mode enabled.
        terminal.update(&mut app, |view, _ctx| {
            let mut model = view.model.lock();
            model.init_shell(InitShellValue {
                session_id: 0.into(),
                shell: "bash".to_owned(),
                ..Default::default()
            });
            model.bootstrapped(BootstrappedValue {
                shell: "bash".to_owned(),
                shell_options: Some(HashSet::from(["vi_mode".to_string()])),
                ..Default::default()
            });
        });

        // This is asynchronous because we're waiting for the bootstrap event
        // to be sent from the terminal model to the terminal view.
        assert_eventually!(
            // The vim keybinding banner should NOT display
            // because the user already has vim keybindings turned on.
            terminal.read(&app, |terminal, _terminal_ctx| {
                terminal.inline_banners_state.vim_banner_state.is_none()
            }),
            "Banner should not have opened"
        );
    })
}

#[test]
fn test_zsh_vim_banner_on() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal =
            MockTerminalManager::create_new_terminal_view_window_for_test(&mut app, None);

        // Ensure the terminal is the active session.
        terminal.update(&mut app, |view, ctx| {
            let terminal_pane_id = TerminalPaneId::dummy_terminal_pane_id();
            let focus_state = ctx.add_model(|_| {
                PaneGroupFocusState::new(terminal_pane_id.into(), Some(terminal_pane_id), false)
            });
            let focus_handle = PaneFocusHandle::new(terminal_pane_id.into(), focus_state);
            view.set_focus_handle(focus_handle, ctx);
        });

        // Ensure the banner has never been shown.
        VimBannerSettings::handle(&app).update(&mut app, |banner_settings, ctx| {
            let _ = banner_settings
                .vim_keybindings_banner_state
                .set_value(BannerState::NotDismissed, ctx);
        });

        // Ensure Warp's vim keybindings are off.
        AppEditorSettings::handle(&app).update(&mut app, |editor_settings, ctx| {
            let _ = editor_settings.vim_mode.set_value(false, ctx);
        });

        // Bootstrap a zsh session with vi mode enabled.
        terminal.update(&mut app, |view, _ctx| {
            let mut model = view.model.lock();
            model.init_shell(InitShellValue {
                session_id: 0.into(),
                shell: "zsh".to_owned(),
                ..Default::default()
            });
            model.bootstrapped(BootstrappedValue {
                shell: "zsh".to_owned(),
                shell_plugins: Some(HashSet::from(["vi".to_string()])),
                ..Default::default()
            });
        });

        // This is asynchronous because we're waiting for the bootstrap event
        // to be sent from the terminal model to the terminal view.
        assert_eventually!(
            // The vim keybinding banner should display.
            200 => terminal.read(&app, |terminal, _terminal_ctx| {
                terminal.inline_banners_state.vim_banner_state.is_some()
            }),
            "Banner did not open in time"
        );
    })
}

#[test]
fn test_zsh_vim_banner_off() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal =
            MockTerminalManager::create_new_terminal_view_window_for_test(&mut app, None);

        // Ensure the terminal is the active session.
        terminal.update(&mut app, |view, ctx| {
            let terminal_pane_id = TerminalPaneId::dummy_terminal_pane_id();
            let focus_state = ctx.add_model(|_| {
                PaneGroupFocusState::new(terminal_pane_id.into(), Some(terminal_pane_id), false)
            });
            let focus_handle = PaneFocusHandle::new(terminal_pane_id.into(), focus_state);
            view.set_focus_handle(focus_handle, ctx);
        });

        // Ensure the banner has never been shown.
        VimBannerSettings::handle(&app).update(&mut app, |banner_settings, ctx| {
            let _ = banner_settings
                .vim_keybindings_banner_state
                .set_value(BannerState::NotDismissed, ctx);
        });

        // Ensure Warp's vim keybindings are on.
        AppEditorSettings::handle(&app).update(&mut app, |editor_settings, ctx| {
            let _ = editor_settings.vim_mode.set_value(true, ctx);
        });

        // Bootstrap a zsh session with vi mode enabled.
        terminal.update(&mut app, |view, _ctx| {
            let mut model = view.model.lock();
            model.init_shell(InitShellValue {
                session_id: 0.into(),
                shell: "zsh".to_owned(),
                ..Default::default()
            });
            model.bootstrapped(BootstrappedValue {
                shell: "zsh".to_owned(),
                shell_plugins: Some(HashSet::from(["vi".to_string()])),
                ..Default::default()
            });
        });

        // This is asynchronous because we're waiting for the bootstrap event
        // to be sent from the terminal model to the terminal view.
        assert_eventually!(
            // The vim keybinding banner should NOT display
            // because the user already has vim keybindings turned on.
            terminal.read(&app, |terminal, _terminal_ctx| {
                terminal.inline_banners_state.vim_banner_state.is_none()
            }),
            "Banner should not have opened"
        );
    })
}

#[test]
fn test_fish_vim_banner_on() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal =
            MockTerminalManager::create_new_terminal_view_window_for_test(&mut app, None);

        // Ensure the terminal is the active session.
        terminal.update(&mut app, |view, ctx| {
            let terminal_pane_id = TerminalPaneId::dummy_terminal_pane_id();
            let focus_state = ctx.add_model(|_| {
                PaneGroupFocusState::new(terminal_pane_id.into(), Some(terminal_pane_id), false)
            });
            let focus_handle = PaneFocusHandle::new(terminal_pane_id.into(), focus_state);
            view.set_focus_handle(focus_handle, ctx);
        });

        // Ensure Warp's vim keybindings are off.
        AppEditorSettings::handle(&app).update(&mut app, |editor_settings, ctx| {
            let _ = editor_settings.vim_mode.set_value(false, ctx);
        });

        // Bootstrap a fish session with vi mode enabled.
        terminal.update(&mut app, |view, _ctx| {
            let mut model = view.model.lock();
            model.init_shell(InitShellValue {
                session_id: 0.into(),
                shell: "fish".to_owned(),
                ..Default::default()
            });
            model.bootstrapped(BootstrappedValue {
                shell: "fish".to_owned(),
                shell_options: Some(HashSet::from(["vi_mode".to_string()])),
                ..Default::default()
            });
        });

        // This is asynchronous because we're waiting for the bootstrap event
        // to be sent from the terminal model to the terminal view.
        assert_eventually!(
            // The vim keybinding banner should display.
            200 => terminal.read(&app, |terminal, _terminal_ctx| {
                terminal.inline_banners_state.vim_banner_state.is_some()
            }),
            "Banner did not open in time"
        );
    })
}

#[test]
fn test_fish_vim_banner_off() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal =
            MockTerminalManager::create_new_terminal_view_window_for_test(&mut app, None);

        // Ensure the terminal is the active session.
        terminal.update(&mut app, |view, ctx| {
            let terminal_pane_id = TerminalPaneId::dummy_terminal_pane_id();
            let focus_state = ctx.add_model(|_| {
                PaneGroupFocusState::new(terminal_pane_id.into(), Some(terminal_pane_id), false)
            });
            let focus_handle = PaneFocusHandle::new(terminal_pane_id.into(), focus_state);
            view.set_focus_handle(focus_handle, ctx);
        });

        // Ensure Warp's vim keybindings are on.
        AppEditorSettings::handle(&app).update(&mut app, |editor_settings, ctx| {
            let _ = editor_settings.vim_mode.set_value(true, ctx);
        });

        // Bootstrap a fish session with vi mode enabled.
        terminal.update(&mut app, |view, _ctx| {
            let mut model = view.model.lock();
            model.init_shell(InitShellValue {
                session_id: 0.into(),
                shell: "fish".to_owned(),
                ..Default::default()
            });
            model.bootstrapped(BootstrappedValue {
                shell: "fish".to_owned(),
                shell_options: Some(HashSet::from(["vi_mode".to_string()])),
                ..Default::default()
            });
        });

        // This is asynchronous because we're waiting for the bootstrap event
        // to be sent from the terminal model to the terminal view.
        assert_eventually!(
            // The vim keybinding banner should NOT display
            // because the user already has vim keybindings turned on.
            terminal.read(&app, |terminal, _terminal_ctx| {
                terminal.inline_banners_state.vim_banner_state.is_none()
            }),
            "Banner should not have opened"
        );
    })
}

#[test]
fn test_prompt_context_menu_items_for_ps1() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal = add_window_with_terminal(&mut app, None);

        SessionSettings::handle(&app).update(&mut app, |session_settings, ctx| {
            let _ = session_settings.honor_ps1.set_value(true, ctx);
        });

        terminal.read(&app, |view, ctx| {
            let items = view.prompt_context_menu_items(ctx);
            let len = items.len();
            assert_eq!(len, 3);
            assert_eq!(items[0].fields().unwrap().label(), "Copy prompt");
            assert!(items[1].is_separator());
            assert_eq!(items[2].fields().unwrap().label(), "Edit prompt");
            assert!(!items[2].fields().unwrap().is_disabled());
        });
    })
}

#[test]
fn test_prompt_context_menu_items_for_context_chips() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.update(&mut app, |view, ctx| {
            let model = view.model.lock();
            view.current_prompt.update(ctx, |prompt, ctx| {
                let PromptType::Dynamic { prompt } = prompt else {
                    return;
                };
                prompt.update(ctx, |prompt, ctx| {
                    prompt.update_context(model.block_list().active_block(), ctx)
                });
            })
        });

        // Set the prompt to something we can actually read for.
        let prompt = Prompt::handle(&app);
        prompt.update(&mut app, |prompt, ctx| {
            prompt
                .update(
                    [ContextChipKind::Time12],
                    false,
                    WarpPromptSeparator::None,
                    ctx,
                )
                .expect("updating prompt to time chip failed");
        });

        let session_settings = SessionSettings::handle(&app);
        session_settings.update(&mut app, |settings, ctx| {
            // Force a toggle so the change event fires.
            let _ = settings.honor_ps1.set_value(true, ctx);
            let _ = settings.honor_ps1.set_value(false, ctx);
        });

        terminal.read(&app, |view, ctx| {
            let items: Vec<MenuItem<TerminalAction>> = view.prompt_context_menu_items(ctx);
            assert_eq!(items.len(), 5);

            // We expect the prompt menu items to be something like the following when context chips are used:
            // Copy prompt
            // ------------
            // <context chip specific actions>
            // ------------
            // Edit prompt
            assert_eq!(items[0].fields().unwrap().label(), "Copy prompt");
            assert!(items[1].is_separator());
            assert_eq!(
                items[2].fields().unwrap().label(),
                "Copy Time (12-hour format)"
            );
            assert!(items[3].is_separator());
            assert_eq!(items[4].fields().unwrap().label(), "Edit prompt");
            assert!(!items[4].fields().unwrap().is_disabled());
        });
    })
}

#[test]
fn test_prompt_context_menu_items_for_no_context_chips() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.update(&mut app, |view, ctx| {
            let model = view.model.lock();
            view.current_prompt.update(ctx, |prompt, ctx| {
                let PromptType::Dynamic { prompt } = prompt else {
                    return;
                };
                prompt.update(ctx, |prompt, ctx| {
                    prompt.update_context(model.block_list().active_block(), ctx)
                });
            })
        });

        let session_settings = SessionSettings::handle(&app);
        session_settings.update(&mut app, |settings, ctx| {
            let _ = settings.honor_ps1.set_value(false, ctx);
        });

        terminal.read(&app, |view, ctx| {
            let items: Vec<MenuItem<TerminalAction>> = view.prompt_context_menu_items(ctx);
            assert_eq!(items.len(), 3);

            // We expect the prompt menu items to be something like the following when no context chips exist:
            // Copy prompt
            // ------------
            // Edit prompt
            assert_eq!(items[0].fields().unwrap().label(), "Copy prompt");
            assert!(items[1].is_separator());
            assert_eq!(items[2].fields().unwrap().label(), "Edit prompt");
            assert!(!items[2].fields().unwrap().is_disabled());
        });
    })
}

#[test]
fn test_link_at_range_trims_zero_width_spaces() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal = add_window_with_terminal(&mut app, None);

        // NOTE: this has two zero-width spaces, one after the '(', and one before the ')'
        let input_url = "(\u{200b}https://example.com\u{200b})";
        // NOTE: the final character in this string is a zero-width space
        let non_escaped_url = "https://example.com\u{200b}";
        let escaped_url = "https://example.com";

        terminal.update(&mut app, |view, _ctx| {
            view.model.lock().simulate_block(
                r"printf '(%bhttps://example.com%b)\n' '\U200b' '\U200b'",
                input_url,
            );
        });

        terminal.read(&app, |view, ctx| {
            let model = view.model.lock();

            let block = view
                .viewport_state(model.block_list(), InputMode::PinnedToBottom, ctx)
                .iter()
                .next()
                .expect("blocklist should have at least one item");

            let point = WithinModel::BlockList(WithinBlock::new(
                // I picked the point 0, 4 b/c it seemed to work. It's not clear to me
                // why 4 works when numbers like 9 do not. Either way, this is just to
                // get the actual url out (passing 9 fails on url_at_point), and does
                // not matter for testing link_at_range.
                Point::new(0, 4),
                block.block_index.expect("block index should exist"),
                crate::terminal::GridType::Output,
            ));

            let url = model
                .url_at_point(&point)
                .expect("url at the designated point should exist");

            // Assert that string_at_range preserves the ZW Space
            assert_eq!(
                model.string_at_range(&url, RespectObfuscatedSecrets::No),
                non_escaped_url
            );

            // Assert that link_at_range removes the ZW Space
            assert_eq!(
                model.link_at_range(&url, RespectObfuscatedSecrets::No),
                escaped_url
            );
        });
    })
}

#[test]
fn test_scroll_position_doesnt_change_when_block_finished() {
    use futures_lite::StreamExt;

    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal = add_window_with_terminal(&mut app, None);

        let (tx, rx) = async_channel::bounded(1);
        app.update(|ctx| {
            ctx.subscribe_to_view(&terminal, move |_, event, _| {
                if let Event::BlockCompleted { block, .. } = event {
                    let output = std::str::from_utf8(&block.stylized_output).unwrap();
                    if output.trim() == "lr" {
                        tx.try_send(()).expect("Can send over channel");
                    }
                }
            });
        });

        let scroll_position_before_finished = terminal.update(&mut app, |view, ctx| {
            // Finish a lengthy block.
            view.model.lock().simulate_block("ls", &"\n".repeat(1000));
            assert!(view.is_vertically_scrollable(ctx));
            assert_eq!(
                view.scroll_position(),
                ScrollPosition::FollowsBottomOfMostRecentBlock
            );

            // Start long-running block.
            view.model.lock().simulate_long_running_block("", "lr");

            // Before the block is finished, scroll up.
            view.scroll(1.0.into_lines(), ctx);
            let scroll_position_before_finished = view.scroll_position();
            assert!(matches!(
                scroll_position_before_finished,
                ScrollPosition::FixedAtPosition { .. }
            ));

            // Finish the block.
            view.model.lock().finish_block();

            scroll_position_before_finished
        });

        // Wait until the terminal view acknowledges the block as completed.
        assert!(pin!(rx).next().await.is_some());

        // Make sure the scroll position is unchanged when the block finishes.
        terminal.read(&app, |view, _| {
            let scroll_position_after_finished = view.scroll_position();
            assert_eq!(
                scroll_position_before_finished,
                scroll_position_after_finished
            );
        });
    })
}

/// Sets up a CLI agent session, opens rich input, submits `text`, and returns
/// the terminal handle and the collected PTY writes.
#[allow(clippy::type_complexity)]
fn submit_rich_input_and_collect_pty_writes(
    app: &mut App,
    agent: CLIAgent,
    text: &str,
) -> (ViewHandle<TerminalView>, Rc<RefCell<Vec<Vec<u8>>>>) {
    let terminal = add_window_with_terminal(app, None);
    let pty_writes: Rc<RefCell<Vec<Vec<u8>>>> = Rc::new(RefCell::new(Vec::new()));
    let writes = pty_writes.clone();
    app.update(|ctx| {
        ctx.subscribe_to_view(&terminal, move |_, event, _| {
            if let Event::WriteBytesToPty { bytes } = event {
                writes.borrow_mut().push(bytes.to_vec());
            }
        });
    });

    terminal.update(app, |view, ctx| {
        CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
            sessions.set_session(
                view.view_id,
                CLIAgentSession {
                    agent,
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

        view.open_cli_agent_rich_input(ctx);
        assert!(view.has_active_cli_agent_input_session(ctx));

        view.submit_cli_agent_rich_input(text.to_owned(), ctx);
    });

    (terminal, pty_writes)
}

fn open_cli_agent_rich_input_for_agent(app: &mut App, agent: CLIAgent) -> ViewHandle<TerminalView> {
    open_cli_agent_rich_input_for_agent_with_window_id(app, agent).1
}

fn open_cli_agent_rich_input_for_agent_with_window_id(
    app: &mut App,
    agent: CLIAgent,
) -> (WindowId, ViewHandle<TerminalView>) {
    let (window_id, terminal) = add_window_with_id_and_terminal(app, None);
    terminal.update(app, |view, ctx| {
        CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
            sessions.set_session(
                view.view_id,
                CLIAgentSession {
                    agent,
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

        view.open_cli_agent_rich_input(ctx);
        assert!(view.has_active_cli_agent_input_session(ctx));
    });
    (window_id, terminal)
}

/// Verifies that Ctrl-G closes CLI agent rich input when dispatched from the
/// focused editor context. This is a regression test where the
/// keybinding only matched the terminal context, not the embedded editor.
#[test]
fn ctrl_g_closes_cli_agent_rich_input_when_editor_is_focused() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        app.add_singleton_model(ImportedConfigModel::new);
        // Register keybindings so keystroke dispatch can match the Ctrl-G binding.
        app.update(|ctx| {
            crate::terminal::init(ctx);
            crate::editor::init(ctx);
        });

        let (window_id, terminal) =
            open_cli_agent_rich_input_for_agent_with_window_id(&mut app, CLIAgent::OpenCode);

        // Dispatch Ctrl-G through the focused editor's responder chain.
        let (input_id, editor_id) = terminal.read(&app, |view, ctx| {
            let input = view.input.clone();
            let editor = input.as_ref(ctx).editor().clone();
            (input.id(), editor.id())
        });
        let handled = app
            .dispatch_keystroke(
                window_id,
                &[terminal.id(), input_id, editor_id],
                &warpui::keymap::Keystroke::parse("ctrl-g").expect("valid keystroke"),
                false,
            )
            .expect("dispatch should succeed");

        assert!(handled, "ctrl-g should be handled from the focused editor");
        terminal.read(&app, |view, ctx| {
            assert!(
                !view.has_active_cli_agent_input_session(ctx),
                "rich input should be closed after Ctrl-G"
            );
        });
    })
}

/// Verifies that Ctrl-G closes CLI agent rich input when dispatched from the
/// terminal context alone (no editor in the responder chain). Regression test
/// where the keybinding only opened rich input but did not close it
/// in scenarios where focus was outside the embedded editor and the active
/// block had transitioned out of `LongRunningCommand` — for example, when the
/// CLI agent has paused waiting for user input.
#[test]
fn ctrl_g_closes_cli_agent_rich_input_from_terminal_context() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        app.add_singleton_model(ImportedConfigModel::new);
        // Register keybindings so keystroke dispatch can match the Ctrl-G binding.
        app.update(|ctx| {
            crate::terminal::init(ctx);
            crate::editor::init(ctx);
        });

        let (window_id, terminal) =
            open_cli_agent_rich_input_for_agent_with_window_id(&mut app, CLIAgent::OpenCode);

        // Dispatch Ctrl-G with only the terminal view in the responder chain.
        // This simulates the case where focus is not on the embedded editor
        // (e.g., on the block list) and the previous Case 1 / Case 2 predicates
        // would both fail to match.
        let handled = app
            .dispatch_keystroke(
                window_id,
                &[terminal.id()],
                &warpui::keymap::Keystroke::parse("ctrl-g").expect("valid keystroke"),
                false,
            )
            .expect("dispatch should succeed");

        assert!(
            handled,
            "ctrl-g should be handled from the terminal context when rich input is open"
        );
        terminal.read(&app, |view, ctx| {
            assert!(
                !view.has_active_cli_agent_input_session(ctx),
                "rich input should be closed after Ctrl-G from terminal context"
            );
        });
    })
}

/// Verifies that Ctrl-G is a true toggle: opens then closes rich input from
/// the terminal context. Regression test.
#[test]
fn ctrl_g_toggles_cli_agent_rich_input_from_terminal_context() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        app.add_singleton_model(ImportedConfigModel::new);
        app.update(|ctx| {
            crate::terminal::init(ctx);
            crate::editor::init(ctx);
        });

        // Start with rich input open, then close via Ctrl-G, then re-open via
        // direct call (Ctrl-G open path requires LongRunningCommand which is
        // tricky to simulate in a unit test), then close via Ctrl-G again.
        let (window_id, terminal) =
            open_cli_agent_rich_input_for_agent_with_window_id(&mut app, CLIAgent::OpenCode);

        let keystroke = warpui::keymap::Keystroke::parse("ctrl-g").expect("valid keystroke");

        // First close: rich input is open → Ctrl-G should close.
        let handled = app
            .dispatch_keystroke(window_id, &[terminal.id()], &keystroke, false)
            .expect("dispatch should succeed");
        assert!(handled, "first ctrl-g should be handled (close)");
        terminal.read(&app, |view, ctx| {
            assert!(
                !view.has_active_cli_agent_input_session(ctx),
                "rich input should be closed after first Ctrl-G"
            );
        });

        // Re-open programmatically (mirrors the user re-triggering open via
        // Ctrl-G in a long-running context).
        terminal.update(&mut app, |view, ctx| {
            view.open_cli_agent_rich_input(ctx);
            assert!(view.has_active_cli_agent_input_session(ctx));
        });

        // Second close: rich input is open again → Ctrl-G should close again.
        let handled = app
            .dispatch_keystroke(window_id, &[terminal.id()], &keystroke, false)
            .expect("dispatch should succeed");
        assert!(handled, "second ctrl-g should be handled (close again)");
        terminal.read(&app, |view, ctx| {
            assert!(
                !view.has_active_cli_agent_input_session(ctx),
                "rich input should be closed after second Ctrl-G"
            );
        });
    })
}

#[test]
fn cli_agent_rich_input_hint_text_mentions_active_cli_agent() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        for (agent, expected_hint_text) in [
            (CLIAgent::Claude, "Enter prompt for Claude Code..."),
            (CLIAgent::Gemini, "Enter prompt for Gemini..."),
            (CLIAgent::Codex, "Enter prompt for Codex..."),
            (CLIAgent::Unknown, "Tell the agent what to build..."),
        ] {
            let terminal = open_cli_agent_rich_input_for_agent(&mut app, agent);
            terminal.read(&app, |view, ctx| {
                let placeholder_text = view
                    .input
                    .as_ref(ctx)
                    .editor()
                    .as_ref(ctx)
                    .placeholder_text("");
                assert_eq!(placeholder_text, Some(expected_hint_text));
            });
        }
    })
}

#[test]
fn cli_agent_rich_input_shell_mode_uses_run_commands_hint_text() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = open_cli_agent_rich_input_for_agent(&mut app, CLIAgent::Claude);
        terminal.update(&mut app, |view, ctx| {
            view.input.update(ctx, |input, ctx| {
                input
                    .input_mode_model()
                    .update(ctx, |input_mode_model, ctx| {
                        input_mode_model.set_input_config(
                            InputConfig {
                                input_type: InputType::Shell,
                            },
                            ctx,
                        );
                    });
                input.set_zero_state_hint_text(ctx);
            });
        });
        terminal.read(&app, |view, ctx| {
            let placeholder_text = view
                .input
                .as_ref(ctx)
                .editor()
                .as_ref(ctx)
                .placeholder_text("");
            assert_eq!(placeholder_text, Some("Run commands"));
        });
    })
}

#[test]
fn submit_cli_agent_rich_input_codex_uses_bracketed_paste() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let (_terminal, pty_writes) =
            submit_rich_input_and_collect_pty_writes(&mut app, CLIAgent::Codex, "hello");

        let writes = pty_writes.borrow();
        // BracketedPaste: first write is ESC[200~ + text + ESC[201~, second is \r.
        assert_eq!(
            writes.len(),
            2,
            "expected 2 PTY writes, got {}",
            writes.len()
        );

        let mut expected_paste =
            Vec::with_capacity(BRACKETED_PASTE_START.len() + 5 + BRACKETED_PASTE_END.len());
        expected_paste.extend_from_slice(BRACKETED_PASTE_START);
        expected_paste.extend_from_slice(b"hello");
        expected_paste.extend_from_slice(BRACKETED_PASTE_END);
        assert_eq!(writes[0], expected_paste);
        assert_eq!(writes[1], b"\r");
    })
}

/// Verifies that multi-line Hermes rich input is delivered as a single bracketed
/// paste payload with a standalone \r submit. Embedded newlines must remain
/// inside the paste instead of triggering separate submissions.
#[test]
fn submit_cli_agent_rich_input_hermes_multiline_uses_bracketed_paste() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let (_terminal, pty_writes) =
            submit_rich_input_and_collect_pty_writes(&mut app, CLIAgent::Hermes, "line1\nline2");

        let writes = pty_writes.borrow();
        // BracketedPaste: first write is ESC[200~ + both lines + ESC[201~, second is \r.
        // The embedded \n between lines must NOT split into a separate write or trigger
        // a second submission.
        assert_eq!(
            writes.len(),
            2,
            "expected 2 PTY writes (paste payload + submit \r), got {}: {:?}",
            writes.len(),
            writes
        );

        let mut expected_paste =
            Vec::with_capacity(BRACKETED_PASTE_START.len() + 11 + BRACKETED_PASTE_END.len());
        expected_paste.extend_from_slice(BRACKETED_PASTE_START);
        expected_paste.extend_from_slice(b"line1\nline2");
        expected_paste.extend_from_slice(BRACKETED_PASTE_END);
        assert_eq!(
            writes[0], expected_paste,
            "first write should be the full bracketed paste payload"
        );
        assert_eq!(
            writes[1], b"\r",
            "second write should be the standalone submit \r"
        );
    })
}

#[test]
fn submit_cli_agent_rich_input_opencode_defers_enter_and_close() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let (_terminal, pty_writes) =
            submit_rich_input_and_collect_pty_writes(&mut app, CLIAgent::OpenCode, "hello");

        // Immediately after submit, only the text should have been written;
        // the \r is sent after a short delay.
        assert_eq!(pty_writes.borrow().len(), 1);
        assert_eq!(pty_writes.borrow()[0], b"hello");

        // Wait for the delayed \r to arrive.
        assert_eventually!(
            100 => pty_writes.borrow().len() == 2,
            "carriage return should be written after delay"
        );
        assert_eq!(pty_writes.borrow()[1], b"\r");
    })
}

#[test]
fn attach_path_as_context_routes_to_open_cli_agent_rich_input() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = open_cli_agent_rich_input_for_agent(&mut app, CLIAgent::Claude);
        let pty_writes: Rc<RefCell<Vec<Vec<u8>>>> = Rc::new(RefCell::new(Vec::new()));
        let writes = pty_writes.clone();
        app.update(|ctx| {
            ctx.subscribe_to_view(&terminal, move |_, event, _| {
                if let Event::WriteBytesToPty { bytes } = event {
                    writes.borrow_mut().push(bytes.to_vec());
                }
            });
        });

        terminal.update(&mut app, |view, ctx| {
            view.attach_path_as_context(std::path::Path::new("src/main.rs"), ctx);
        });

        terminal.read(&app, |view, ctx| {
            assert_eq!(view.input.as_ref(ctx).buffer_text(ctx), "src/main.rs");
        });
        assert!(
            pty_writes.borrow().is_empty(),
            "context should be inserted into rich input instead of written to PTY"
        );
    })
}
#[test]
fn drag_drop_image_in_cli_agent_long_running_command_pastes_via_clipboard() {
    // Regression test: dropping an image file into a tab where a CLI agent
    // (e.g. Claude Code) is the foreground long-running process should
    // mirror the Cmd+V image-paste path — write the image to the system
    // clipboard and send the agent's paste keystroke to the PTY — instead
    // of shell-escaping the path and typing it into the agent's prompt.
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        // The new path actually reads the file off disk, so we need a real
        // file. Bytes don't have to be a valid PNG.
        let mut image_path = std::env::temp_dir();
        image_path.push(format!(
            "warp-test-cli-agent-drop-{}.png",
            std::process::id()
        ));
        std::fs::write(&image_path, b"fake-png-bytes").expect("write tmp image");
        let image_path_str = image_path.to_string_lossy().into_owned();

        let terminal = add_window_with_terminal(&mut app, None);

        let pty_writes: Rc<RefCell<Vec<Vec<u8>>>> = Rc::new(RefCell::new(Vec::new()));
        let writes = pty_writes.clone();
        app.update(|ctx| {
            ctx.subscribe_to_view(&terminal, move |_, event, _| {
                if let Event::WriteBytesToPty { bytes } = event {
                    writes.borrow_mut().push(bytes.to_vec());
                }
            });
        });

        terminal.update(&mut app, |view, ctx| {
            CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
                sessions.set_session(
                    view.view_id,
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

            // The CLI-agent paste branch is gated on the active block being
            // long-running (the agent's TUI). Without a long-running block
            // we'd fall through to the regular image-attach flow.
            {
                let mut model = view.model.lock();
                model.simulate_long_running_block("claude", "");
                assert!(
                    model
                        .block_list()
                        .active_block()
                        .is_active_and_long_running()
                );
            }

            view.drag_and_drop_files(&[image_path_str], ctx);
        });

        // The paste flow is async (off-thread file read, then hop back to
        // the view to write the clipboard + paste keystroke). Wait for the
        // single PTY write of the platform-appropriate paste byte: 0x16
        // (Ctrl+V) on macOS/Linux, or `ESC v` on Windows. Without the fix
        // a shell-escaped path string is written here instead.
        let expected_paste_bytes: Vec<u8> = if cfg!(windows) {
            vec![0x1b, b'v']
        } else {
            vec![0x16]
        };
        assert_eventually!(
            pty_writes.borrow().len() == 1 && pty_writes.borrow()[0] == expected_paste_bytes,
            "expected single paste-keystroke PTY write {:?}; got {:?}",
            expected_paste_bytes,
            pty_writes.borrow()
        );

        std::fs::remove_file(&image_path).ok();
    })
}

#[test]
fn paste_raw_image_clipboard_in_cli_agent_sends_correct_bytes() {
    fn run_for_agent(agent: CLIAgent) {
        App::test((), move |mut app| async move {
            initialize_app_for_terminal_view(&mut app);

            let terminal = add_window_with_terminal(&mut app, None);

            let pty_writes: Rc<RefCell<Vec<Vec<u8>>>> = Rc::new(RefCell::new(Vec::new()));
            let writes = pty_writes.clone();
            app.update(|ctx| {
                ctx.subscribe_to_view(&terminal, move |_, event, _| {
                    if let Event::WriteBytesToPty { bytes } = event {
                        writes.borrow_mut().push(bytes.to_vec());
                    }
                });
            });

            terminal.update(&mut app, |view, ctx| {
                CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
                    sessions.set_session(
                        view.view_id,
                        CLIAgentSession {
                            agent,
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

                {
                    let mut model = view.model.lock();
                    model.simulate_long_running_block(agent.command_prefix(), "");
                    model.set_mode(ansi::Mode::BracketedPaste);
                }

                // Write image-only data to the clipboard (no text, no paths).
                ctx.clipboard().write(ClipboardContent {
                    images: Some(vec![warpui::clipboard::ImageData {
                        data: vec![0x89, 0x50, 0x4E, 0x47], // PNG magic bytes
                        mime_type: "image/png".to_string(),
                        filename: None,
                    }]),
                    ..Default::default()
                });

                view.handle_action(&TerminalAction::Paste, ctx);
            });

            let writes = pty_writes.borrow();
            assert_eq!(
                writes.len(),
                1,
                "expected 1 PTY write, got {}",
                writes.len()
            );

            if cfg!(windows) {
                if agent == CLIAgent::Claude {
                    assert_eq!(writes[0], vec![C0::ESC, b'v']);
                } else {
                    let mut expected = Vec::new();
                    expected.extend_from_slice(BRACKETED_PASTE_START);
                    expected.extend_from_slice(BRACKETED_PASTE_END);
                    assert_eq!(writes[0], expected);
                }
            } else {
                assert_eq!(writes[0], vec![C0::SYN]);
            }
        })
    }

    run_for_agent(CLIAgent::Claude);
    run_for_agent(CLIAgent::OpenCode);
    run_for_agent(CLIAgent::Codex);
}

#[test]
fn submit_without_auto_dismiss_keeps_rich_input_open() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        // auto_dismiss defaults to false — leave it off.

        let terminal = add_window_with_terminal(&mut app, None);

        terminal.update(&mut app, |view, ctx| {
            CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
                sessions.set_session(
                    view.view_id,
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

            view.open_cli_agent_rich_input(ctx);
            assert!(view.has_active_cli_agent_input_session(ctx));

            view.submit_cli_agent_rich_input("hello".to_owned(), ctx);

            // Rich input stays open because auto_dismiss is off.
            assert!(view.has_active_cli_agent_input_session(ctx));
        });

        // Buffer should still be cleared even though rich input is open.
        terminal.read(&app, |view, ctx| {
            let input = view.input.as_ref(ctx);
            assert!(input.editor().as_ref(ctx).buffer_text(ctx).is_empty());
        });
    })
}

#[test]
fn submit_with_plugin_and_auto_toggle_keeps_rich_input_open() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        // auto_toggle_rich_input defaults to true.
        // Turn on auto_dismiss too — it should be overridden by auto_toggle.
        CLIAgentSettings::handle(&app).update(&mut app, |settings, ctx| {
            let _ = settings
                .auto_dismiss_rich_input_after_submit
                .set_value(true, ctx);
        });

        let terminal = add_window_with_terminal(&mut app, None);

        terminal.update(&mut app, |view, ctx| {
            // Create a session with a plugin listener and should_auto_toggle_input.
            let listener = ctx.add_model(|ctx| {
                CLIAgentSessionListener::new(
                    view.view_id,
                    CLIAgent::Claude,
                    &view.model_events_handle,
                    ctx,
                )
            });
            CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
                sessions.set_session(
                    view.view_id,
                    CLIAgentSession {
                        agent: CLIAgent::Claude,
                        status: CLIAgentSessionStatus::InProgress,
                        session_context: CLIAgentSessionContext::default(),
                        input_state: CLIAgentInputState::Closed,
                        should_auto_toggle_input: true,
                        listener: Some(listener),
                        draft_text: None,
                        received_rich_notification: true,
                    },
                    ctx,
                );
            });

            view.open_cli_agent_rich_input(ctx);
            assert!(view.has_active_cli_agent_input_session(ctx));

            view.submit_cli_agent_rich_input("hello".to_owned(), ctx);

            // Rich input stays open because auto_toggle + plugin takes precedence.
            assert!(view.has_active_cli_agent_input_session(ctx));
        });
    })
}

#[test]
fn submit_with_plugin_but_auto_toggle_off_respects_auto_dismiss() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        CLIAgentSettings::handle(&app).update(&mut app, |settings, ctx| {
            let _ = settings.auto_toggle_rich_input.set_value(false, ctx);
            let _ = settings
                .auto_dismiss_rich_input_after_submit
                .set_value(true, ctx);
        });

        let terminal = add_window_with_terminal(&mut app, None);

        terminal.update(&mut app, |view, ctx| {
            let listener = ctx.add_model(|ctx| {
                CLIAgentSessionListener::new(
                    view.view_id,
                    CLIAgent::Claude,
                    &view.model_events_handle,
                    ctx,
                )
            });
            CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
                sessions.set_session(
                    view.view_id,
                    CLIAgentSession {
                        agent: CLIAgent::Claude,
                        status: CLIAgentSessionStatus::InProgress,
                        session_context: CLIAgentSessionContext::default(),
                        input_state: CLIAgentInputState::Closed,
                        should_auto_toggle_input: true,
                        listener: Some(listener),
                        draft_text: None,
                        received_rich_notification: false,
                    },
                    ctx,
                );
            });

            view.open_cli_agent_rich_input(ctx);
            assert!(view.has_active_cli_agent_input_session(ctx));

            view.submit_cli_agent_rich_input("hello".to_owned(), ctx);
        });

        // auto_toggle is off, so auto_dismiss closes rich input.
        // Claude uses DelayedEnter, so the close happens after a timer.
        assert_eventually!(
            100 => terminal.read(&app, |view, ctx| !view
                .has_active_cli_agent_input_session(ctx)),
            "Rich input should be closed after submit with auto_dismiss"
        );
    })
}

#[test]
fn status_blocked_auto_closes_rich_input() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        // auto_toggle_rich_input defaults to true.

        let terminal = add_window_with_terminal(&mut app, None);

        terminal.update(&mut app, |view, ctx| {
            let listener = ctx.add_model(|ctx| {
                CLIAgentSessionListener::new(
                    view.view_id,
                    CLIAgent::Claude,
                    &view.model_events_handle,
                    ctx,
                )
            });
            CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
                sessions.set_session(
                    view.view_id,
                    CLIAgentSession {
                        agent: CLIAgent::Claude,
                        status: CLIAgentSessionStatus::InProgress,
                        session_context: CLIAgentSessionContext::default(),
                        input_state: CLIAgentInputState::Closed,
                        should_auto_toggle_input: true,
                        listener: Some(listener),
                        draft_text: None,
                        received_rich_notification: false,
                    },
                    ctx,
                );
            });

            view.open_cli_agent_rich_input(ctx);
            assert!(view.has_active_cli_agent_input_session(ctx));

            // Simulate a PermissionRequest event → status transitions to Blocked.
            CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
                sessions.update_from_event(
                    view.view_id,
                    &CLIAgentEvent {
                        source: CLIAgentEventSource::RichPlugin,
                        v: 1,
                        agent: CLIAgent::Claude,
                        event: CLIAgentEventType::PermissionRequest,
                        session_id: None,
                        cwd: None,
                        project: None,
                        payload: CLIAgentEventPayload {
                            summary: Some("Approve?".to_owned()),
                            ..Default::default()
                        },
                    },
                    ctx,
                );
            });
        });

        // The StatusChanged event is delivered to the terminal view, which
        // auto-closes rich input because the agent is blocked.
        terminal.read(&app, |view, ctx| {
            assert!(!view.has_active_cli_agent_input_session(ctx));
        });

        // should_auto_toggle_input is preserved so auto-open can fire later.
        terminal.read(&app, |_view, ctx| {
            let session = CLIAgentSessionsModel::as_ref(ctx).session(_view.view_id);
            assert!(session.unwrap().should_auto_toggle_input);
        });
    })
}

#[test]
fn status_in_progress_auto_opens_rich_input_after_blocked() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);

        terminal.update(&mut app, |view, ctx| {
            let listener = ctx.add_model(|ctx| {
                CLIAgentSessionListener::new(
                    view.view_id,
                    CLIAgent::Claude,
                    &view.model_events_handle,
                    ctx,
                )
            });
            CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
                sessions.set_session(
                    view.view_id,
                    CLIAgentSession {
                        agent: CLIAgent::Claude,
                        status: CLIAgentSessionStatus::InProgress,
                        session_context: CLIAgentSessionContext::default(),
                        input_state: CLIAgentInputState::Closed,
                        should_auto_toggle_input: true,
                        listener: Some(listener),
                        draft_text: None,
                        received_rich_notification: false,
                    },
                    ctx,
                );
            });

            // Open rich input, then simulate blocked → closed automatically.
            view.open_cli_agent_rich_input(ctx);
            CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
                sessions.update_from_event(
                    view.view_id,
                    &CLIAgentEvent {
                        source: CLIAgentEventSource::RichPlugin,
                        v: 1,
                        agent: CLIAgent::Claude,
                        event: CLIAgentEventType::PermissionRequest,
                        session_id: None,
                        cwd: None,
                        project: None,
                        payload: CLIAgentEventPayload {
                            summary: Some("Approve?".to_owned()),
                            ..Default::default()
                        },
                    },
                    ctx,
                );
            });
        });

        // Rich input should be auto-closed from the blocked status.
        terminal.read(&app, |view, ctx| {
            assert!(!view.has_active_cli_agent_input_session(ctx));
        });

        // Simulate permission replied → status transitions back to InProgress.
        terminal.update(&mut app, |view, ctx| {
            CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
                sessions.update_from_event(
                    view.view_id,
                    &CLIAgentEvent {
                        source: CLIAgentEventSource::RichPlugin,
                        v: 1,
                        agent: CLIAgent::Claude,
                        event: CLIAgentEventType::PermissionReplied,
                        session_id: None,
                        cwd: None,
                        project: None,
                        payload: CLIAgentEventPayload::default(),
                    },
                    ctx,
                );
            });
        });

        // Rich input should auto-open because should_auto_toggle_input was preserved.
        terminal.read(&app, |view, ctx| {
            assert!(view.has_active_cli_agent_input_session(ctx));
        });
    })
}

// Regression test:
// Codex's listener doesn't emit Blocked-state events (it only forwards opaque
// OSC 9 notifications as Stop), so auto-toggling rich input would trap arrow
// keys when Codex shows interactive option menus. Auto-toggle must not fire
// for agents whose handlers report `supports_rich_status() == false`.
#[test]
fn codex_status_change_does_not_auto_open_rich_input() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        // auto_toggle_rich_input defaults to true.

        let terminal = add_window_with_terminal(&mut app, None);

        terminal.update(&mut app, |view, ctx| {
            let listener = ctx.add_model(|ctx| {
                CLIAgentSessionListener::new(
                    view.view_id,
                    CLIAgent::Codex,
                    &view.model_events_handle,
                    ctx,
                )
            });
            CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
                sessions.set_session(
                    view.view_id,
                    CLIAgentSession {
                        agent: CLIAgent::Codex,
                        status: CLIAgentSessionStatus::InProgress,
                        session_context: CLIAgentSessionContext::default(),
                        input_state: CLIAgentInputState::Closed,
                        should_auto_toggle_input: true,
                        listener: Some(listener),
                        draft_text: None,
                        received_rich_notification: false,
                    },
                    ctx,
                );
            });

            // Rich input starts closed. Simulating a Stop event (the only
            // status Codex's handler ever emits) must not re-open it,
            // because the user may be navigating Codex's option menus.
            assert!(!view.has_active_cli_agent_input_session(ctx));
            CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
                sessions.update_from_event(
                    view.view_id,
                    &CLIAgentEvent {
                        source: CLIAgentEventSource::CodexOsc9Fallback,
                        v: 1,
                        agent: CLIAgent::Codex,
                        event: CLIAgentEventType::Stop,
                        session_id: None,
                        cwd: None,
                        project: None,
                        payload: CLIAgentEventPayload {
                            query: Some("Agent turn complete".to_owned()),
                            ..Default::default()
                        },
                    },
                    ctx,
                );
            });
        });

        terminal.read(&app, |view, ctx| {
            assert!(!view.has_active_cli_agent_input_session(ctx));
        });
    })
}

#[test]
fn rich_input_auto_opens_in_prompt_mode_when_a_cli_agent_starts() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        CLIAgentSettings::handle(&app).update(&mut app, |settings, ctx| {
            let _ = settings
                .auto_open_rich_input_on_cli_agent_start
                .set_value(true, ctx);
            let _ = settings.should_render_cli_agent_footer.set_value(true, ctx);
        });

        let terminal = add_window_with_terminal(&mut app, None);

        terminal.read(&app, |view, ctx| {
            assert!(!view.has_active_cli_agent_input_session(ctx));
            assert_eq!(
                view.input_mode_model().as_ref(ctx).input_type(),
                InputType::Shell
            );
        });

        terminal.update(&mut app, |view, ctx| {
            view.register_cli_agent_listener_without_session_start_event(CLIAgent::Claude, ctx);
        });

        terminal.read(&app, |view, ctx| {
            assert!(view.has_active_cli_agent_input_session(ctx));
            assert_eq!(
                view.input_mode_model().as_ref(ctx).input_type(),
                InputType::Prompt
            );
        });

        // Closing the composer hands the input back to the shell.
        terminal.update(&mut app, |view, ctx| {
            view.close_cli_agent_rich_input_and_disable_auto_toggle(ctx);
        });
        terminal.read(&app, |view, ctx| {
            assert!(!view.has_active_cli_agent_input_session(ctx));
            assert_eq!(
                view.input_mode_model().as_ref(ctx).input_type(),
                InputType::Shell
            );
        });
    })
}

#[test]
fn rich_input_does_not_auto_open_when_the_setting_is_disabled() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        CLIAgentSettings::handle(&app).update(&mut app, |settings, ctx| {
            let _ = settings
                .auto_open_rich_input_on_cli_agent_start
                .set_value(false, ctx);
        });

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.update(&mut app, |view, ctx| {
            view.register_cli_agent_listener_without_session_start_event(CLIAgent::Claude, ctx);
        });

        terminal.read(&app, |view, ctx| {
            assert!(!view.has_active_cli_agent_input_session(ctx));
            assert_eq!(
                view.input_mode_model().as_ref(ctx).input_type(),
                InputType::Shell
            );
        });
    })
}

#[test]
fn manual_dismiss_disables_auto_toggle_for_session() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);

        terminal.update(&mut app, |view, ctx| {
            let listener = ctx.add_model(|ctx| {
                CLIAgentSessionListener::new(
                    view.view_id,
                    CLIAgent::Claude,
                    &view.model_events_handle,
                    ctx,
                )
            });
            CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
                sessions.set_session(
                    view.view_id,
                    CLIAgentSession {
                        agent: CLIAgent::Claude,
                        status: CLIAgentSessionStatus::InProgress,
                        session_context: CLIAgentSessionContext::default(),
                        input_state: CLIAgentInputState::Closed,
                        should_auto_toggle_input: true,
                        listener: Some(listener),
                        draft_text: None,
                        received_rich_notification: false,
                    },
                    ctx,
                );
            });

            view.open_cli_agent_rich_input(ctx);
            assert!(view.has_active_cli_agent_input_session(ctx));

            // Manual dismiss via the "disable auto-toggle" path (Escape / Ctrl-G / footer).
            view.close_cli_agent_rich_input_and_disable_auto_toggle(ctx);
            assert!(!view.has_active_cli_agent_input_session(ctx));
        });

        // should_auto_toggle_input should now be false.
        terminal.read(&app, |view, ctx| {
            let session = CLIAgentSessionsModel::as_ref(ctx).session(view.view_id);
            assert!(!session.unwrap().should_auto_toggle_input);
        });

        // A status change to InProgress should NOT auto-open rich input.
        terminal.update(&mut app, |view, ctx| {
            // First move to Blocked so we can transition back.
            CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
                sessions.update_from_event(
                    view.view_id,
                    &CLIAgentEvent {
                        source: CLIAgentEventSource::RichPlugin,
                        v: 1,
                        agent: CLIAgent::Claude,
                        event: CLIAgentEventType::PermissionRequest,
                        session_id: None,
                        cwd: None,
                        project: None,
                        payload: CLIAgentEventPayload {
                            summary: Some("Approve?".to_owned()),
                            ..Default::default()
                        },
                    },
                    ctx,
                );
            });
            CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
                sessions.update_from_event(
                    view.view_id,
                    &CLIAgentEvent {
                        source: CLIAgentEventSource::RichPlugin,
                        v: 1,
                        agent: CLIAgent::Claude,
                        event: CLIAgentEventType::PermissionReplied,
                        session_id: None,
                        cwd: None,
                        project: None,
                        payload: CLIAgentEventPayload::default(),
                    },
                    ctx,
                );
            });
        });

        // Rich input should remain closed.
        terminal.read(&app, |view, ctx| {
            assert!(!view.has_active_cli_agent_input_session(ctx));
        });
    })
}

#[test]
fn close_cli_agent_rich_input_saves_draft_and_reopen_restores_it() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = open_cli_agent_rich_input_for_agent(&mut app, CLIAgent::Claude);

        // Type some text into the composer.
        terminal.update(&mut app, |view, ctx| {
            view.input.update(ctx, |input, ctx| {
                input.replace_buffer_content("work in progress", ctx);
            });
        });

        // Close the composer — the buffer text should be saved as a draft.
        terminal.update(&mut app, |view, ctx| {
            view.close_cli_agent_rich_input(ctx);
            assert!(!view.has_active_cli_agent_input_session(ctx));
        });

        terminal.read(&app, |view, ctx| {
            let session = CLIAgentSessionsModel::as_ref(ctx)
                .session(view.view_id)
                .expect("session should exist");
            assert_eq!(
                session.draft_text.as_deref(),
                Some("work in progress"),
                "draft should be saved on close"
            );
        });

        // Reopen — draft should be restored into the buffer and consumed.
        terminal.update(&mut app, |view, ctx| {
            view.open_cli_agent_rich_input(ctx);
            assert!(view.has_active_cli_agent_input_session(ctx));
        });

        terminal.read(&app, |view, ctx| {
            assert_eq!(
                view.input.as_ref(ctx).buffer_text(ctx),
                "work in progress",
                "draft should be restored on reopen"
            );
            let session = CLIAgentSessionsModel::as_ref(ctx)
                .session(view.view_id)
                .expect("session should exist");
            assert_eq!(
                session.draft_text, None,
                "draft should be consumed after restore"
            );
        });
    })
}

#[test]
fn submit_cli_agent_rich_input_clears_draft() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        CLIAgentSettings::handle(&app).update(&mut app, |settings, ctx| {
            // Keep the input open after submit so we can inspect the buffer.
            let _ = settings
                .auto_dismiss_rich_input_after_submit
                .set_value(false, ctx);
        });

        let terminal = open_cli_agent_rich_input_for_agent(&mut app, CLIAgent::Claude);

        terminal.update(&mut app, |view, ctx| {
            view.submit_cli_agent_rich_input("hello agent".to_owned(), ctx);
            // Input stays open because auto-dismiss is off.
            assert!(view.has_active_cli_agent_input_session(ctx));
        });

        terminal.read(&app, |view, ctx| {
            let session = CLIAgentSessionsModel::as_ref(ctx)
                .session(view.view_id)
                .expect("session should exist");
            assert_eq!(
                session.draft_text, None,
                "draft should be cleared after submit"
            );
            assert!(
                view.input.as_ref(ctx).buffer_text(ctx).is_empty(),
                "buffer should be empty after submit"
            );
        });
    })
}

#[test]
fn close_cli_agent_rich_input_with_empty_buffer_stores_no_draft() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = open_cli_agent_rich_input_for_agent(&mut app, CLIAgent::Claude);

        // Close immediately without typing anything.
        terminal.update(&mut app, |view, ctx| {
            view.close_cli_agent_rich_input(ctx);
            assert!(!view.has_active_cli_agent_input_session(ctx));
        });

        terminal.read(&app, |view, ctx| {
            let session = CLIAgentSessionsModel::as_ref(ctx)
                .session(view.view_id)
                .expect("session should exist");
            assert_eq!(
                session.draft_text, None,
                "no draft should be stored for empty buffer"
            );
        });
    })
}

/// Regression test for the async-find branch.
///
/// Closing the find bar must clear stale rich content block highlights without dropping
/// the saved query options on the async-find path. `open_find_bar` reads
/// `active_find_options` to restore the previous query; if `close_find_bar`
/// routes through `clear_matches → AsyncFindController::clear_results`, that
/// helper resets `current_find_options` and reopening the find bar starts
/// from a blank query instead of the previous one.
#[test]
fn close_find_bar_preserves_options_on_async_find_path() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal = add_window_with_terminal(&mut app, None);

        let needle_options = || FindOptions {
            query: Some("needle".to_owned().into()),
            ..Default::default()
        };

        terminal.update(&mut app, |view, ctx| {
            view.show_find_bar(ctx);
            view.run_find(needle_options(), ctx);
        });

        // The async controller should have saved the active query.
        assert_eq!(
            terminal.read(&app, |view, ctx| view
                .find_model
                .as_ref(ctx)
                .active_find_options()
                .map(|o| o.query.clone())),
            Some(needle_options().query),
            "running find on the async path must save the active query"
        );

        // Closing the find bar must NOT drop the saved query — otherwise
        // the next `open_find_bar` would start blank instead of restoring
        // the previous search.
        terminal.update(&mut app, |view, ctx| {
            view.close_find_bar(ctx);
        });

        assert_eq!(
            terminal.read(&app, |view, ctx| view
                .find_model
                .as_ref(ctx)
                .active_find_options()
                .map(|o| o.query.clone())),
            Some(needle_options().query),
            "closing the find bar must preserve the saved query on the async path"
        );
    })
}

#[test]
#[cfg(target_os = "linux")]
fn copy_forwards_etx_to_pty_on_linux_alt_screen_without_warp_selection() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        let pty_writes: Rc<RefCell<Vec<Vec<u8>>>> = Rc::new(RefCell::new(Vec::new()));
        let writes = pty_writes.clone();
        app.update(|ctx| {
            ctx.subscribe_to_view(&terminal, move |_, event, _| {
                if let Event::WriteBytesToPty { bytes } = event {
                    writes.borrow_mut().push(bytes.to_vec());
                }
            });
        });

        terminal.update(&mut app, |view, ctx| {
            // Enter the alt screen (a fullscreen TUI is in control) and add no
            // Warp-visible selection of any kind.
            {
                let mut model = view.model.lock();
                model.set_mode(ansi::Mode::SwapScreen {
                    save_cursor_and_clear_screen: true,
                });
                assert!(model.is_alt_screen_active());
            }
            assert_eq!("", &read_from_clipboard(ctx));

            // No CLI-subagent / error-screen / grid / input-editor / block
            // selection exists, so `copy()` reaches the new fallback. The clipboard
            // is written synchronously, but `WriteBytesToPty` events are dispatched
            // after the update closure returns, so the PTY-write assertion is made
            // outside the closure (mirroring `ctrl_c_after_stop_takeover_cancels_conversation`).
            view.handle_action(&TerminalAction::Copy, ctx);

            assert_eq!(
                read_from_clipboard(ctx),
                "",
                "Copy must not write anything to the clipboard when Warp has no selection"
            );
        });

        assert_eq!(
            *pty_writes.borrow(),
            vec![vec![C0::ETX]],
            "Copy on Linux alt screen with no Warp selection must forward exactly one ETX byte to the PTY"
        );
    })
}

#[test]
fn copy_does_not_forward_when_alt_screen_has_warp_selection() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        let pty_writes: Rc<RefCell<Vec<Vec<u8>>>> = Rc::new(RefCell::new(Vec::new()));
        let writes = pty_writes.clone();
        app.update(|ctx| {
            ctx.subscribe_to_view(&terminal, move |_, event, _| {
                if let Event::WriteBytesToPty { bytes } = event {
                    writes.borrow_mut().push(bytes.to_vec());
                }
            });
        });

        terminal.update(&mut app, |view, ctx| {
            {
                // Enter the alt screen and add text the user will select in Warp.
                let mut model = view.model.lock();
                model.set_mode(ansi::Mode::SwapScreen {
                    save_cursor_and_clear_screen: true,
                });
                assert!(model.is_alt_screen_active());

                model.alt_screen_mut().input('h');
            }

            // Make a Warp-owned alt-screen selection (the path that copies today).
            view.begin_alt_selection(Point::new(0, 0), Side::Left, SelectionType::Simple, ctx);
            view.update_alt_selection(Point::new(0, 2), Side::Left, &Lines::zero(), ctx);
            view.end_alt_selection(ctx);
            // `end_alt_selection` copies via copy-on-select, so the clipboard now
            // holds the selected text. Reset the PTY-write recorder so the only
            // writes observed below come from the explicit Copy dispatch.
            pty_writes.borrow_mut().clear();
            assert_eq!("h", &read_from_clipboard(ctx));

            view.handle_action(&TerminalAction::Copy, ctx);

            assert_eq!(
                read_from_clipboard(ctx),
                "h",
                "Copy must still copy the Warp alt-screen selection to the clipboard"
            );
        });

        assert!(
            pty_writes.borrow().is_empty(),
            "Copy must not forward ETX to the PTY when a Warp alt-screen selection was copied"
        );
    })
}

#[test]
fn copy_does_not_forward_on_normal_screen() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        let pty_writes: Rc<RefCell<Vec<Vec<u8>>>> = Rc::new(RefCell::new(Vec::new()));
        let writes = pty_writes.clone();
        app.update(|ctx| {
            ctx.subscribe_to_view(&terminal, move |_, event, _| {
                if let Event::WriteBytesToPty { bytes } = event {
                    writes.borrow_mut().push(bytes.to_vec());
                }
            });
        });

        terminal.update(&mut app, |view, ctx| {
            // Normal screen: no alt screen, no selection of any kind.
            assert!(!view.model.lock().is_alt_screen_active());
            assert_eq!("", &read_from_clipboard(ctx));

            view.handle_action(&TerminalAction::Copy, ctx);

            assert_eq!(
                read_from_clipboard(ctx),
                "",
                "Copy must not write anything to the clipboard on the normal screen with no selection"
            );
        });

        assert!(
            pty_writes.borrow().is_empty(),
            "Copy must not write anything to the PTY on the normal screen with no selection"
        );
    })
}

#[test]
fn active_cli_agent_ignores_non_agent_long_running_command() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);

        let terminal = add_window_with_terminal(&mut app, None);
        terminal.update(&mut app, |view, _| {
            view.model.lock().simulate_long_running_block("vim", "");
        });

        terminal.read(&app, |view, ctx| {
            assert_eq!(CLIAgent::detect("vim", None, None), None);
            assert_eq!(
                view.active_cli_agent(ctx),
                None,
                "a non-agent long-running command must not be a review destination"
            );
        });
    });
}

/// A child linked to its parent only via a legacy server conversation token
/// in `parent_agent_id` (no explicit parent conversation id, no run id) must
/// still resolve the parent through the history model's canonical
/// resolution, yielding the same back-button label as an id-linked child.

#[test]
fn visible_bootstrap_block_leaves_focus_on_tab_rename_editor() {
    App::test((), |mut app| async move {
        initialize_workspace_app(&mut app);
        let workspace = mock_workspace(&mut app);
        let (window, terminal) = workspace.update(&mut app, |workspace, ctx| {
            workspace.rename_tab(0, ctx);
            let terminal = workspace
                .active_tab_pane_group()
                .as_ref(ctx)
                .active_session_view(ctx)
                .expect("tab should contain a terminal");
            (ctx.window_id(), terminal)
        });
        assert!(workspace.read(&app, |workspace, ctx| {
            workspace.is_inline_rename_editor_focused(ctx)
        }));
        let focused_before = app.focused_view_id(window);

        terminal.update(&mut app, |view, ctx| {
            view.handle_terminal_event(&ModelEvent::VisibleBootstrapBlock, ctx);
        });

        assert_eq!(app.focused_view_id(window), focused_before);
        assert!(workspace.read(&app, |workspace, ctx| {
            workspace.is_inline_rename_editor_focused(ctx)
        }));
    });
}

#[test]
fn visible_bootstrap_block_leaves_focus_on_tab_group_rename_editor() {
    App::test((), |mut app| async move {
        initialize_workspace_app(&mut app);
        let workspace = mock_workspace(&mut app);
        let (window, terminal, group_id) = workspace.update(&mut app, |workspace, ctx| {
            workspace.handle_action(
                &WorkspaceAction::SelectNewSessionMenuItem(NewSessionMenuItem::CreateNewTabGroup),
                ctx,
            );
            let group_id = workspace.tabs[0]
                .group_id
                .expect("active tab should be assigned to the new group");
            let terminal = workspace
                .active_tab_pane_group()
                .as_ref(ctx)
                .active_session_view(ctx)
                .expect("new tab group should contain a terminal");
            (ctx.window_id(), terminal, group_id)
        });
        workspace.update(&mut app, |workspace, ctx| {
            workspace.rename_tab_group(group_id, ctx);
        });
        assert!(workspace.read(&app, |workspace, ctx| {
            workspace.is_inline_rename_editor_focused(ctx)
        }));
        let focused_before = app.focused_view_id(window);

        terminal.update(&mut app, |view, ctx| {
            view.handle_terminal_event(&ModelEvent::VisibleBootstrapBlock, ctx);
        });

        assert_eq!(app.focused_view_id(window), focused_before);
        assert!(workspace.read(&app, |workspace, ctx| {
            workspace.is_inline_rename_editor_focused(ctx)
        }));
    });
}

/// Makes `path` a git repository whose current branch is `main`, so the repo has a branch name
/// and the pull request lookup (`gh pr view` for the branch) has something to look up.
fn init_git_repo_on_branch(path: &Path) {
    let repository = git2::Repository::init(path).expect("init the repo");
    repository
        .set_head("refs/heads/main")
        .expect("point HEAD at main");
    let signature = git2::Signature::now("Test", "test@example.invalid").expect("signature");
    let tree_id = repository
        .treebuilder(None)
        .and_then(|builder| builder.write())
        .expect("empty tree");
    let tree = repository.find_tree(tree_id).expect("find the empty tree");
    repository
        .commit(Some("HEAD"), &signature, &signature, "fixture", &tree, &[])
        .expect("first commit");
}

/// Registers a fresh directory as a watched git repository and returns its
/// canonical path, so `GitRepoModels` can build models for it.
fn register_watched_repo(app: &mut App) -> (tempfile::TempDir, PathBuf) {
    let temp_dir = tempfile::TempDir::new().expect("temp dir");
    let repo = dunce::canonicalize(temp_dir.path()).expect("canonical repo path");
    init_git_repo_on_branch(&repo);
    let standardized =
        StandardizedPath::from_local_canonicalized(repo.as_path()).expect("standardized path");
    DetectedRepositories::handle(app).update(app, |repos, _| {
        repos.insert_test_repo_root(standardized.clone());
    });
    DirectoryWatcher::handle(app).update(app, |watcher, ctx| {
        watcher
            .add_directory(standardized, ctx)
            .expect("watch the repo directory");
    });
    (temp_dir, repo)
}

/// A terminal in a watched repo whose `gh` calls are counted instead of run.
fn terminal_in_repo_with_counting_gh(
    app: &mut App,
    prompt_chips: Vec<ContextChipKind>,
) -> (
    tempfile::TempDir,
    ViewHandle<TerminalView>,
    Arc<CountingGitHubCli>,
) {
    terminal_in_repo_with_counting_gh_and_prompt(app, |app| {
        Prompt::handle(app).update(app, |prompt, ctx| {
            prompt
                .update(prompt_chips, false, WarpPromptSeparator::None, ctx)
                .expect("set the prompt chips");
        });
    })
}

/// Like [`terminal_in_repo_with_counting_gh`], with the prompt left to `set_up_prompt`.
fn terminal_in_repo_with_counting_gh_and_prompt(
    app: &mut App,
    set_up_prompt: impl FnOnce(&mut App),
) -> (
    tempfile::TempDir,
    ViewHandle<TerminalView>,
    Arc<CountingGitHubCli>,
) {
    initialize_app_for_terminal_view(app);
    app.add_singleton_model(|_| LocalShellState::NotLoaded);
    let gh = Arc::new(CountingGitHubCli::default());
    GitRepoModels::handle(app).update(app, |models, _| {
        models.set_github_cli_for_test(gh.clone());
    });
    set_up_prompt(app);
    let (temp_dir, repo) = register_watched_repo(app);
    let terminal = add_window_with_terminal(app, None);
    terminal.update(app, |view, ctx| {
        view.current_repo_path = Some(LocalOrRemotePath::Local(repo));
        view.update_git_status_subscription(ctx);
    });
    (temp_dir, terminal, gh)
}

#[test]
fn repo_terminal_without_a_pr_chip_never_starts_gh() {
    App::test((), |mut app| async move {
        let (_repo, terminal, gh) = terminal_in_repo_with_counting_gh(
            &mut app,
            vec![ContextChipKind::WorkingDirectory, ContextChipKind::Username],
        );

        terminal.read(&app, |view, ctx| {
            assert!(!view.needs_pr_info(ctx));
            assert!(!view.should_subscribe_to_git_status(ctx));
            assert!(view.git_repo_status.is_none());
            assert!(view.github_repo_model.is_none());
        });

        warpui::r#async::Timer::after(std::time::Duration::from_millis(200)).await;
        assert_eq!(gh.total_lookups(), 0, "no chip means no `gh` process");
    });
}

/// Replaces the mock prompt with one that reads the user's saved prompt setting, the way the app does at startup.
fn use_prompt_from_saved_settings(app: &mut App) {
    Prompt::handle(app).update(app, |prompt, ctx| *prompt = Prompt::new(ctx));
}

#[test]
fn unset_prompt_setting_in_a_repo_never_starts_gh() {
    App::test((), |mut app| async move {
        let (_repo, terminal, gh) =
            terminal_in_repo_with_counting_gh_and_prompt(&mut app, use_prompt_from_saved_settings);

        app.read(|ctx| {
            let saved = &SessionSettings::as_ref(ctx).saved_prompt;
            assert!(!saved.is_value_explicitly_set());
            assert!(
                !Prompt::as_ref(ctx)
                    .chip_kinds()
                    .contains(&ContextChipKind::GithubPullRequest)
            );
        });
        terminal.read(&app, |view, ctx| {
            assert!(!view.needs_pr_info(ctx));
            assert!(view.github_repo_model.is_none());
            assert!(
                view.git_repo_status.is_some(),
                "the default prompt's git chips still read the local repository"
            );
        });

        warpui::r#async::Timer::after(std::time::Duration::from_millis(200)).await;
        assert_eq!(
            gh.total_lookups(),
            0,
            "a default setup must not run `gh` on its own"
        );
    });
}

#[test]
fn saved_prompt_with_the_pr_chip_starts_gh_after_a_restart() {
    App::test((), |mut app| async move {
        let (_repo, terminal, gh) = terminal_in_repo_with_counting_gh_and_prompt(&mut app, |app| {
            SessionSettings::handle(app).update(app, |settings, ctx| {
                settings
                    .saved_prompt
                    .set_value(
                        PromptConfiguration::from_chips(
                            [
                                ContextChipKind::WorkingDirectory,
                                ContextChipKind::GithubPullRequest,
                            ],
                            false,
                            WarpPromptSeparator::None,
                        )
                        .into(),
                        ctx,
                    )
                    .expect("save the prompt");
            });
            use_prompt_from_saved_settings(app);
        });

        terminal.read(&app, |view, ctx| {
            assert!(view.needs_pr_info(ctx));
            assert!(view.github_repo_model.is_some());
        });
        assert_eventually!(
            200 => gh.repository_lookups() >= 1,
            "a saved PR chip keeps looking up the repository"
        );
    });
}

#[test]
fn open_cli_agent_rich_input_in_a_repo_does_not_start_gh() {
    App::test((), |mut app| async move {
        let (_repo, terminal, gh) = terminal_in_repo_with_counting_gh(
            &mut app,
            vec![ContextChipKind::WorkingDirectory, ContextChipKind::Username],
        );

        // An open rich input in a repo used to force git and PR polling.
        terminal.update(&mut app, |view, ctx| {
            CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
                sessions.set_session(
                    view.view_id,
                    CLIAgentSession {
                        agent: CLIAgent::Droid,
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
            view.open_cli_agent_rich_input(ctx);
            assert!(view.has_active_cli_agent_input_session(ctx));
        });
        terminal.update(&mut app, |view, ctx| {
            view.update_git_status_subscription(ctx)
        });

        terminal.read(&app, |view, ctx| {
            assert!(
                view.input_mode_model.as_ref(ctx).is_prompt_input_enabled(),
                "the rich input must be open for this test to cover the old trigger"
            );
            assert!(
                !view.needs_pr_info(ctx),
                "the default CLI-agent footer has no PR chip"
            );
            assert!(view.github_repo_model.is_none());
        });

        warpui::r#async::Timer::after(std::time::Duration::from_millis(200)).await;
        assert_eq!(gh.total_lookups(), 0);
    });
}

#[test]
fn git_branch_chip_reads_local_git_but_never_runs_gh() {
    App::test((), |mut app| async move {
        let (_repo, terminal, gh) = terminal_in_repo_with_counting_gh(
            &mut app,
            vec![
                ContextChipKind::WorkingDirectory,
                ContextChipKind::GitDiffStats,
            ],
        );

        terminal.read(&app, |view, ctx| {
            assert!(view.should_subscribe_to_git_status(ctx));
            assert!(!view.needs_pr_info(ctx));
            assert!(view.git_repo_status.is_some());
            assert!(view.github_repo_model.is_none());
        });

        warpui::r#async::Timer::after(std::time::Duration::from_millis(200)).await;
        assert_eq!(gh.total_lookups(), 0, "local git chips must not call `gh`");
    });
}

#[test]
fn pr_chip_starts_gh_and_removing_it_stops_gh() {
    App::test((), |mut app| async move {
        let (_repo, terminal, gh) = terminal_in_repo_with_counting_gh(
            &mut app,
            vec![
                ContextChipKind::WorkingDirectory,
                ContextChipKind::GithubPullRequest,
            ],
        );

        terminal.read(&app, |view, ctx| {
            assert!(view.needs_pr_info(ctx));
            assert!(view.github_repo_model.is_some());
        });
        assert_eventually!(
            200 => gh.repository_lookups() >= 1,
            "a visible PR chip must look up the repository"
        );

        Prompt::handle(&app).update(&mut app, |prompt, ctx| {
            prompt
                .update(
                    [ContextChipKind::WorkingDirectory],
                    false,
                    WarpPromptSeparator::None,
                    ctx,
                )
                .expect("remove the PR chip");
        });
        // The mock prompt does not forward settings changes, so re-evaluate
        // the way the view does on `PromptEvent::Changed`.
        terminal.update(&mut app, |view, ctx| {
            view.update_git_status_subscription(ctx)
        });
        terminal.read(&app, |view, ctx| {
            assert!(!view.needs_pr_info(ctx));
            assert!(view.github_repo_model.is_none());
            assert!(view.git_repo_status.is_none());
        });
    });
}

#[test]
fn terminal_outside_a_repo_never_needs_pr_info() {
    App::test((), |mut app| async move {
        let (_repo, terminal, gh) =
            terminal_in_repo_with_counting_gh(&mut app, vec![ContextChipKind::GithubPullRequest]);

        terminal.update(&mut app, |view, ctx| {
            view.current_repo_path = None;
            view.update_git_status_subscription(ctx);
            assert!(!view.needs_pr_info(ctx));
            assert!(!view.should_subscribe_to_git_status(ctx));
            assert!(view.github_repo_model.is_none());
        });
        let lookups_at_leave = gh.total_lookups();
        warpui::r#async::Timer::after(std::time::Duration::from_millis(100)).await;
        assert_eq!(gh.total_lookups(), lookups_at_leave);
    });
}

/// A workspace whose only tab is a terminal in a watched repo with a PR chip in the prompt,
/// with `gh` counted instead of run.
fn workspace_with_pr_chip_terminal_in_repo(
    app: &mut App,
) -> (
    tempfile::TempDir,
    ViewHandle<crate::workspace::Workspace>,
    ViewHandle<TerminalView>,
    Arc<CountingGitHubCli>,
) {
    initialize_workspace_app(app);
    app.add_singleton_model(|_| LocalShellState::NotLoaded);
    let gh = Arc::new(CountingGitHubCli::default());
    GitRepoModels::handle(app).update(app, |models, _| {
        models.set_github_cli_for_test(gh.clone());
    });
    Prompt::handle(app).update(app, |prompt, ctx| {
        prompt
            .update(
                [
                    ContextChipKind::WorkingDirectory,
                    ContextChipKind::GithubPullRequest,
                ],
                false,
                WarpPromptSeparator::None,
                ctx,
            )
            .expect("set the prompt chips");
    });
    let (temp_dir, repo) = register_watched_repo(app);
    let workspace = mock_workspace(app);
    let terminal = active_tab_terminal(app, &workspace);
    terminal.update(app, |view, ctx| {
        view.current_repo_path = Some(LocalOrRemotePath::Local(repo));
        view.hidden_pr_info_grace = std::time::Duration::from_millis(60);
        view.update_git_status_subscription(ctx);
    });
    terminal.read(app, |view, ctx| {
        assert!(view.needs_pr_info(ctx));
        assert!(view.github_repo_model.is_some());
    });
    (temp_dir, workspace, terminal, gh)
}

fn active_tab_terminal(
    app: &App,
    workspace: &ViewHandle<crate::workspace::Workspace>,
) -> ViewHandle<TerminalView> {
    workspace.read(app, |workspace, ctx| {
        workspace
            .active_tab_pane_group()
            .as_ref(ctx)
            .active_session_view(ctx)
            .expect("the active tab has a terminal")
    })
}

fn holds_github_model(app: &App, terminal: &ViewHandle<TerminalView>) -> bool {
    terminal.read(app, |view, _| view.github_repo_model.is_some())
}

/// What decides whether a terminal holds the PR model, for the message of a failed assertion.
fn pr_info_state(app: &App, terminal: &ViewHandle<TerminalView>) -> String {
    terminal.read(app, |view, ctx| {
        format!(
            "repo={:?} git_status={} model={} needs_pr_info={} on_screen={} shown={} release_pending={}",
            view.current_repo_path,
            view.git_repo_status.is_some(),
            view.github_repo_model.is_some(),
            view.needs_pr_info(ctx),
            view.pr_info_on_screen(ctx),
            view.pane_is_shown(ctx),
            view.pending_pr_info_release.is_some(),
        )
    })
}

#[test]
fn background_tab_releases_the_pr_model_after_the_grace_period() {
    App::test((), |mut app| async move {
        let (_repo, workspace, terminal, gh) = workspace_with_pr_chip_terminal_in_repo(&mut app);
        assert_eventually!(
            200 => gh.repository_lookups() >= 1,
            "a selected tab with a PR chip looks up the repository"
        );

        workspace.update(&mut app, |workspace, ctx| {
            workspace.handle_action(&WorkspaceAction::AddDefaultTab, ctx);
        });
        assert_eq!(workspace.read(&app, |w, _| w.active_tab_index()), 1);
        terminal.read(&app, |view, ctx| {
            assert!(!view.pr_info_on_screen(ctx));
            assert!(view.needs_pr_info(ctx), "the layout still has the chip");
        });
        assert!(
            holds_github_model(&app, &terminal),
            "the handle is kept during the grace period"
        );

        assert_eventually!(
            400 => !holds_github_model(&app, &terminal),
            "a background tab must release its `gh` model after the grace period"
        );
        let lookups_when_released = gh.total_lookups();
        warpui::r#async::Timer::after(std::time::Duration::from_millis(150)).await;
        assert_eq!(
            gh.total_lookups(),
            lookups_when_released,
            "a released background tab runs no `gh`"
        );
    });
}

#[test]
fn selecting_the_tab_again_after_the_grace_period_refreshes_immediately() {
    App::test((), |mut app| async move {
        let (_repo, workspace, terminal, gh) = workspace_with_pr_chip_terminal_in_repo(&mut app);
        workspace.update(&mut app, |workspace, ctx| {
            workspace.handle_action(&WorkspaceAction::AddDefaultTab, ctx);
        });
        assert_eventually!(
            400 => !holds_github_model(&app, &terminal),
            "the background tab releases its model"
        );
        let repository_lookups = gh.repository_lookups();

        workspace.update(&mut app, |workspace, ctx| {
            workspace.handle_action(&WorkspaceAction::ActivateTab(0), ctx);
        });
        assert!(holds_github_model(&app, &terminal));
        assert_eventually!(
            200 => gh.repository_lookups() > repository_lookups,
            "showing the tab again must look up GitHub immediately"
        );
    });
}

#[test]
fn switching_back_within_the_grace_period_keeps_the_same_model() {
    App::test((), |mut app| async move {
        let (_repo, workspace, terminal, gh) = workspace_with_pr_chip_terminal_in_repo(&mut app);
        terminal.update(&mut app, |view, _| {
            view.hidden_pr_info_grace = std::time::Duration::from_secs(60);
        });
        assert_eventually!(
            200 => gh.repository_lookups() >= 1,
            "the selected tab looks up the repository"
        );
        let model_id = terminal.read(&app, |view, _| {
            view.github_repo_model.as_ref().map(|m| m.id())
        });
        let lookups = gh.total_lookups();

        for _ in 0..3 {
            workspace.update(&mut app, |workspace, ctx| {
                workspace.handle_action(&WorkspaceAction::AddDefaultTab, ctx);
                workspace.handle_action(&WorkspaceAction::ActivateTab(0), ctx);
            });
        }

        assert_eq!(
            terminal.read(&app, |view, _| view
                .github_repo_model
                .as_ref()
                .map(|m| m.id())),
            model_id
        );
        assert_eq!(
            gh.total_lookups(),
            lookups,
            "flipping tabs within the grace period must not restart `gh`"
        );
    });
}

#[test]
fn vertical_tabs_pr_badges_keep_background_tabs_polling() {
    use crate::workspace::tab_settings::TabSettings;

    App::test((), |mut app| async move {
        let (_repo, workspace, terminal, _gh) = workspace_with_pr_chip_terminal_in_repo(&mut app);
        enable_vertical_tabs_with_expanded_rows(&mut app);
        workspace.update(&mut app, |workspace, ctx| {
            workspace.handle_action(&WorkspaceAction::AddDefaultTab, ctx);
        });

        terminal.read(&app, |view, ctx| assert!(view.pr_info_on_screen(ctx)));
        warpui::r#async::Timer::after(std::time::Duration::from_millis(200)).await;
        assert!(
            holds_github_model(&app, &terminal),
            "the vertical tabs panel shows this tab's PR badge"
        );

        TabSettings::handle(&app).update(&mut app, |settings, ctx| {
            settings
                .vertical_tabs_show_pr_link
                .set_value(false, ctx)
                .expect("hide PR badges");
        });
        terminal.read(&app, |view, ctx| assert!(!view.pr_info_on_screen(ctx)));
        assert_eventually!(
            400 => !holds_github_model(&app, &terminal),
            "without PR badges the background tab releases its model"
        );

        TabSettings::handle(&app).update(&mut app, |settings, ctx| {
            settings
                .vertical_tabs_show_pr_link
                .set_value(true, ctx)
                .expect("show PR badges");
        });
        terminal.read(&app, |view, ctx| assert!(view.pr_info_on_screen(ctx)));
        assert!(
            holds_github_model(&app, &terminal),
            "showing the badges again acquires the model: {}",
            pr_info_state(&app, &terminal)
        );
    });
}

#[test]
fn hidden_tab_does_not_stop_a_visible_tab_in_the_same_repo() {
    App::test((), |mut app| async move {
        let (_repo, workspace, first, gh) = workspace_with_pr_chip_terminal_in_repo(&mut app);
        let repo = first.read(&app, |view, _| view.current_repo_path.clone());
        workspace.update(&mut app, |workspace, ctx| {
            workspace.handle_action(&WorkspaceAction::AddDefaultTab, ctx);
        });
        let second = active_tab_terminal(&app, &workspace);
        second.update(&mut app, |view, ctx| {
            view.current_repo_path = repo;
            view.update_git_status_subscription(ctx);
        });
        assert!(holds_github_model(&app, &second));
        assert_eventually!(
            400 => !holds_github_model(&app, &first),
            "the hidden tab releases its handle"
        );

        assert!(
            holds_github_model(&app, &second),
            "the shared model stays alive for the selected tab"
        );
        let lookups = gh.repository_lookups();
        assert!(lookups >= 1);
        second.read(&app, |view, ctx| assert!(view.pr_info_on_screen(ctx)));
    });
}

fn enable_vertical_tabs_with_expanded_rows(app: &mut App) {
    use crate::workspace::tab_settings::{TabSettings, VerticalTabsViewMode};

    TabSettings::handle(app).update(app, |settings, ctx| {
        settings
            .use_vertical_tabs
            .set_value(true, ctx)
            .expect("enable vertical tabs");
        settings
            .vertical_tabs_view_mode
            .set_value(VerticalTabsViewMode::Expanded, ctx)
            .expect("show expanded rows");
    });
}

fn enter_alt_screen(app: &mut App, terminal: &ViewHandle<TerminalView>) {
    terminal.update(app, |view, ctx| {
        view.model.lock().process_bytes("\u{1b}[?1049h");
        view.handle_terminal_event(
            &ModelEvent::TerminalModeSwapped(TerminalMode::AltScreen),
            ctx,
        );
    });
}

fn leave_alt_screen(app: &mut App, terminal: &ViewHandle<TerminalView>) {
    terminal.update(app, |view, ctx| {
        view.model.lock().process_bytes("\u{1b}[?1049l");
        view.handle_terminal_event(
            &ModelEvent::TerminalModeSwapped(TerminalMode::BlockList),
            ctx,
        );
    });
}

fn start_long_running_command(app: &mut App, terminal: &ViewHandle<TerminalView>) {
    terminal.update(app, |view, ctx| {
        {
            let mut model = view.model.lock();
            model.block_list_mut().set_bootstrapped();
            model.simulate_long_running_block("sleep 600", "");
        }
        view.handle_terminal_event(
            &ModelEvent::AfterBlockStarted {
                block_id: crate::terminal::model::block::BlockId::new(),
                command: "sleep 600".to_owned(),
                is_for_in_band_command: false,
            },
            ctx,
        );
    });
}

fn finish_command(app: &mut App, terminal: &ViewHandle<TerminalView>) {
    terminal.update(app, |view, ctx| {
        view.model.lock().finish_block();
        view.handle_terminal_event(
            &ModelEvent::AfterBlockCompleted(AfterBlockCompletedEvent {
                block_type: BlockType::Static,
            }),
            ctx,
        );
    });
}

/// A terminal without a workspace (so no real shell is started and nothing resets its model) in
/// a watched repo with a PR chip in the prompt, with `gh` counted instead of run and a short grace
/// period before a hidden terminal releases its model.
fn repo_terminal_with_pr_chip(
    app: &mut App,
) -> (
    tempfile::TempDir,
    ViewHandle<TerminalView>,
    Arc<CountingGitHubCli>,
) {
    let (repo, terminal, gh) = terminal_in_repo_with_counting_gh(
        app,
        vec![
            ContextChipKind::WorkingDirectory,
            ContextChipKind::GithubPullRequest,
        ],
    );
    terminal.update(app, |view, _| {
        view.hidden_pr_info_grace = std::time::Duration::from_millis(60);
    });
    terminal.read(app, |view, ctx| {
        assert!(view.needs_pr_info(ctx));
        assert!(view.github_repo_model.is_some());
    });
    (repo, terminal, gh)
}

#[test]
fn prompt_in_the_selected_tab_keeps_polling_past_the_grace_period() {
    App::test((), |mut app| async move {
        let (_repo, terminal, gh) = repo_terminal_with_pr_chip(&mut app);
        assert_eventually!(
            600 => gh.repository_lookups() >= 1 && gh.pr_lookups() >= 1,
            "the first lookups of the repository and the pull request have run"
        );
        let model_id = terminal.read(&app, |view, _| {
            view.github_repo_model.as_ref().map(|m| m.id())
        });

        warpui::r#async::Timer::after(std::time::Duration::from_millis(250)).await;

        terminal.read(&app, |view, ctx| {
            assert!(view.pr_info_on_screen(ctx));
            assert!(view.pending_pr_info_release.is_none());
        });
        assert_eq!(
            terminal.read(&app, |view, _| view
                .github_repo_model
                .as_ref()
                .map(|m| m.id())),
            model_id,
            "a shown prompt keeps its model for as long as it is shown"
        );
    });
}

#[test]
fn alt_screen_releases_the_pr_model_and_leaving_it_looks_up_at_once() {
    App::test((), |mut app| async move {
        // Only the short grace is shortened: the long one must not be what releases the model.
        let (_repo, terminal, gh) = repo_terminal_with_pr_chip(&mut app);
        assert_eventually!(
            600 => gh.repository_lookups() >= 1 && gh.pr_lookups() >= 1,
            "the first lookups of the repository and the pull request have run"
        );

        enter_alt_screen(&mut app, &terminal);
        terminal.read(&app, |view, ctx| {
            assert!(view.model.lock().is_alt_screen_active());
            assert!(view.pane_is_shown(ctx), "the tab is still selected");
            assert!(
                !view.pr_info_on_screen(ctx),
                "the alt screen hides the prompt"
            );
        });
        assert_eventually!(
            400 => !holds_github_model(&app, &terminal),
            "an alt-screen program must not keep `gh` polling"
        );
        let lookups_when_released = gh.total_lookups();
        let repository_lookups = gh.repository_lookups();
        warpui::r#async::Timer::after(std::time::Duration::from_millis(150)).await;
        assert_eq!(gh.total_lookups(), lookups_when_released);

        leave_alt_screen(&mut app, &terminal);
        terminal.read(&app, |view, ctx| assert!(view.pr_info_on_screen(ctx)));
        assert!(holds_github_model(&app, &terminal));
        assert_eventually!(
            200 => gh.repository_lookups() > repository_lookups,
            "leaving the alt screen looks up GitHub at once"
        );
    });
}

#[test]
fn running_command_releases_the_pr_model_after_the_grace_period() {
    App::test((), |mut app| async move {
        let (_repo, terminal, gh) = repo_terminal_with_pr_chip(&mut app);
        terminal.update(&mut app, |view, _| {
            view.hidden_pr_info_command_grace = std::time::Duration::from_millis(60);
        });
        assert_eventually!(
            600 => gh.repository_lookups() >= 1 && gh.pr_lookups() >= 1,
            "the first lookups of the repository and the pull request have run"
        );

        start_long_running_command(&mut app, &terminal);
        terminal.read(&app, |view, ctx| {
            let model = view.model.lock();
            assert!(!model.is_alt_screen_active());
            assert!(
                !view.is_input_box_visible(&model, ctx),
                "a running command hides the prompt"
            );
        });
        assert_eventually!(
            600 => !holds_github_model(&app, &terminal),
            "a running command must not keep `gh` polling"
        );
        let lookups_when_released = gh.total_lookups();
        warpui::r#async::Timer::after(std::time::Duration::from_millis(150)).await;
        assert_eq!(gh.total_lookups(), lookups_when_released);
    });
}

#[test]
fn command_that_finishes_within_the_grace_period_starts_no_gh() {
    App::test((), |mut app| async move {
        let (_repo, terminal, gh) = repo_terminal_with_pr_chip(&mut app);
        assert_eventually!(
            600 => gh.repository_lookups() >= 1 && gh.pr_lookups() >= 1,
            "the first lookups of the repository and the pull request have run"
        );
        warpui::r#async::Timer::after(std::time::Duration::from_millis(100)).await;
        let model_id = terminal.read(&app, |view, _| {
            view.github_repo_model.as_ref().map(|m| m.id())
        });
        let lookups = gh.total_lookups();

        start_long_running_command(&mut app, &terminal);
        warpui::r#async::Timer::after(std::time::Duration::from_millis(200)).await;
        terminal.read(&app, |view, ctx| {
            assert!(!view.pr_info_on_screen(ctx));
            assert!(view.pending_pr_info_release.is_some());
        });
        finish_command(&mut app, &terminal);
        warpui::r#async::Timer::after(std::time::Duration::from_millis(200)).await;

        terminal.read(&app, |view, ctx| {
            assert!(view.pr_info_on_screen(ctx));
            assert!(view.pending_pr_info_release.is_none());
        });
        assert_eq!(
            terminal.read(&app, |view, _| view
                .github_repo_model
                .as_ref()
                .map(|m| m.id())),
            model_id
        );
        assert_eq!(
            gh.total_lookups(),
            lookups,
            "a short command must not restart `gh`"
        );
    });
}

#[test]
fn command_that_outlasts_the_grace_period_costs_one_lookup_pair_when_it_finishes() {
    App::test((), |mut app| async move {
        let (_repo, terminal, gh) = repo_terminal_with_pr_chip(&mut app);
        terminal.update(&mut app, |view, _| {
            view.hidden_pr_info_command_grace = std::time::Duration::from_millis(60);
        });
        assert_eventually!(
            600 => gh.repository_lookups() >= 1 && gh.pr_lookups() >= 1,
            "the prompt looks up the repository and, once the branch is known, the pull request"
        );
        warpui::r#async::Timer::after(std::time::Duration::from_millis(100)).await;
        let (repository_at_start, pr_at_start) = (gh.repository_lookups(), gh.pr_lookups());
        assert!(
            repository_at_start >= 1 && pr_at_start >= 1,
            "a fresh start looks up both the repository and the pull request"
        );

        start_long_running_command(&mut app, &terminal);
        assert_eventually!(
            600 => !holds_github_model(&app, &terminal),
            "the model is released while the command runs"
        );
        warpui::r#async::Timer::after(std::time::Duration::from_millis(150)).await;
        assert_eq!(gh.repository_lookups(), repository_at_start);
        assert_eq!(gh.pr_lookups(), pr_at_start);

        finish_command(&mut app, &terminal);
        assert!(holds_github_model(&app, &terminal));
        assert_eventually!(
            400 => gh.repository_lookups() == repository_at_start * 2
                && gh.pr_lookups() == pr_at_start * 2,
            "finishing the command looks up GitHub once, as a fresh start does"
        );
        warpui::r#async::Timer::after(std::time::Duration::from_millis(150)).await;
        assert_eq!(gh.repository_lookups(), repository_at_start * 2);
        assert_eq!(gh.pr_lookups(), pr_at_start * 2);
    });
}

#[test]
fn release_grace_constants_are_thirty_seconds_and_three_minutes() {
    use crate::code_review::github_repo_model::{
        HIDDEN_CONSUMER_GRACE_PERIOD, RUNNING_COMMAND_GRACE_PERIOD,
    };

    assert_eq!(
        HIDDEN_CONSUMER_GRACE_PERIOD,
        std::time::Duration::from_secs(30)
    );
    assert_eq!(
        RUNNING_COMMAND_GRACE_PERIOD,
        std::time::Duration::from_secs(180)
    );
}

#[test]
fn production_grace_is_short_for_alt_screen_and_long_for_a_plain_running_command() {
    use crate::code_review::github_repo_model::{
        HIDDEN_CONSUMER_GRACE_PERIOD, RUNNING_COMMAND_GRACE_PERIOD,
    };

    App::test((), |mut app| async move {
        // No test overrides: the grace periods are the ones the app ships with.
        let (_repo, terminal, gh) = terminal_in_repo_with_counting_gh(
            &mut app,
            vec![
                ContextChipKind::WorkingDirectory,
                ContextChipKind::GithubPullRequest,
            ],
        );
        assert_eventually!(
            600 => gh.repository_lookups() >= 1 && gh.pr_lookups() >= 1,
            "the first lookups of the repository and the pull request have run"
        );
        let grace = |app: &App| terminal.read(app, |view, ctx| view.pr_info_release_grace(ctx));
        let scheduled = |app: &App| {
            terminal.read(app, |view, _| {
                view.pending_pr_info_release.as_ref().map(|p| p.grace)
            })
        };

        enter_alt_screen(&mut app, &terminal);
        assert_eq!(
            grace(&app),
            HIDDEN_CONSUMER_GRACE_PERIOD,
            "alt screen: 30 s"
        );
        assert_eq!(
            scheduled(&app),
            Some(HIDDEN_CONSUMER_GRACE_PERIOD),
            "the release is scheduled with the 30 s grace"
        );
        assert!(
            holds_github_model(&app, &terminal),
            "and only when it elapses"
        );

        leave_alt_screen(&mut app, &terminal);
        assert_eq!(
            scheduled(&app),
            None,
            "leaving the alt screen cancels the release"
        );

        start_long_running_command(&mut app, &terminal);
        assert_eventually!(
            200 => scheduled(&app).is_some(),
            "a running command schedules a release"
        );
        assert_eq!(
            grace(&app),
            RUNNING_COMMAND_GRACE_PERIOD,
            "plain command: 3 min"
        );
        assert_eq!(scheduled(&app), Some(RUNNING_COMMAND_GRACE_PERIOD));

        enter_alt_screen(&mut app, &terminal);
        assert_eq!(
            scheduled(&app),
            Some(HIDDEN_CONSUMER_GRACE_PERIOD),
            "a command that goes full-screen is rescheduled to the 30 s grace"
        );

        leave_alt_screen(&mut app, &terminal);
        finish_command(&mut app, &terminal);
        assert_eq!(scheduled(&app), None);
        assert!(holds_github_model(&app, &terminal));
    });
}

#[test]
fn production_grace_for_a_background_tab_is_short_even_while_a_command_runs() {
    use crate::code_review::github_repo_model::HIDDEN_CONSUMER_GRACE_PERIOD;

    App::test((), |mut app| async move {
        let (_repo, workspace, terminal, _gh) = workspace_with_pr_chip_terminal_in_repo(&mut app);
        terminal.update(&mut app, |view, _| {
            view.hidden_pr_info_grace = HIDDEN_CONSUMER_GRACE_PERIOD;
        });
        workspace.update(&mut app, |workspace, ctx| {
            workspace.handle_action(&WorkspaceAction::AddDefaultTab, ctx);
        });
        terminal.read(&app, |view, ctx| {
            assert!(!view.pane_is_shown(ctx));
            assert_eq!(
                view.pr_info_release_grace(ctx),
                HIDDEN_CONSUMER_GRACE_PERIOD
            );
            assert_eq!(
                view.pending_pr_info_release.as_ref().map(|p| p.grace),
                Some(HIDDEN_CONSUMER_GRACE_PERIOD)
            );
        });
    });
}

#[test]
fn cli_agent_footer_with_a_pr_chip_keeps_polling_in_the_alt_screen() {
    use crate::terminal::session_settings::CLIAgentToolbarChipSelection;
    use crate::terminal::view::cli_agent_footer::toolbar_item::CLIAgentToolbarItemKind;

    App::test((), |mut app| async move {
        let (_repo, terminal, gh) = repo_terminal_with_pr_chip(&mut app);
        Prompt::handle(&app).update(&mut app, |prompt, ctx| {
            prompt
                .update(
                    [ContextChipKind::WorkingDirectory],
                    false,
                    WarpPromptSeparator::None,
                    ctx,
                )
                .expect("remove the PR chip from the prompt");
        });
        app.update(|ctx| {
            CLIAgentSettings::handle(ctx).update(ctx, |settings, ctx| {
                let _ = settings.should_render_cli_agent_footer.set_value(true, ctx);
            });
            SessionSettings::handle(ctx).update(ctx, |settings, ctx| {
                settings
                    .cli_agent_footer_chip_selection
                    .set_value(
                        CLIAgentToolbarChipSelection::Custom {
                            left: vec![CLIAgentToolbarItemKind::ContextChip(
                                ContextChipKind::GithubPullRequest,
                            )]
                            .into(),
                            right: vec![].into(),
                        },
                        ctx,
                    )
                    .expect("put the PR chip in the footer");
            });
        });
        terminal.update(&mut app, |view, _| {
            view.hidden_pr_info_command_grace = std::time::Duration::from_millis(60);
        });
        start_cli_agent_session(&mut app, &terminal);
        terminal.update(&mut app, |view, ctx| {
            view.update_git_status_subscription(ctx);
        });
        terminal.read(&app, |view, ctx| {
            assert!(!view.prompt_has_pr_chip(ctx));
            assert!(view.cli_agent_footer_has_pr_chip(ctx));
            assert!(view.github_repo_model.is_some());
        });
        assert_eventually!(
            600 => gh.repository_lookups() >= 1 && gh.pr_lookups() >= 1,
            "the first lookups of the repository and the pull request have run"
        );

        enter_alt_screen(&mut app, &terminal);
        warpui::r#async::Timer::after(std::time::Duration::from_millis(250)).await;
        terminal.read(&app, |view, ctx| {
            assert!(!view.is_input_box_visible(&view.model.lock(), ctx));
            assert!(
                view.pr_info_on_screen(ctx),
                "the footer stays on screen in the alt screen"
            );
        });
        assert!(holds_github_model(&app, &terminal));
    });
}

#[test]
fn vertical_tabs_badges_keep_an_alt_screen_background_tab_polling() {
    App::test((), |mut app| async move {
        let (_repo, workspace, terminal, _gh) = workspace_with_pr_chip_terminal_in_repo(&mut app);
        terminal.update(&mut app, |view, _| {
            view.hidden_pr_info_command_grace = std::time::Duration::from_millis(60);
        });
        enable_vertical_tabs_with_expanded_rows(&mut app);
        workspace.update(&mut app, |workspace, ctx| {
            workspace.handle_action(&WorkspaceAction::AddDefaultTab, ctx);
        });

        enter_alt_screen(&mut app, &terminal);
        warpui::r#async::Timer::after(std::time::Duration::from_millis(250)).await;
        terminal.read(&app, |view, ctx| {
            assert!(view.pr_badge_on_screen(ctx));
            assert!(
                view.pr_info_on_screen(ctx),
                "the badge shows the PR whatever the prompt does"
            );
        });
        assert!(holds_github_model(&app, &terminal));
    });
}

#[test]
fn vertical_tabs_rows_without_a_pr_badge_do_not_keep_background_tabs_polling() {
    use crate::workspace::tab_settings::{
        TabSettings, VerticalTabsDisplayGranularity, VerticalTabsTabItemMode, VerticalTabsViewMode,
    };

    App::test((), |mut app| async move {
        let (_repo, workspace, terminal, _gh) = workspace_with_pr_chip_terminal_in_repo(&mut app);
        enable_vertical_tabs_with_expanded_rows(&mut app);
        workspace.update(&mut app, |workspace, ctx| {
            workspace.handle_action(&WorkspaceAction::AddDefaultTab, ctx);
        });
        let on_screen = |app: &App| terminal.read(app, |view, ctx| view.pr_info_on_screen(ctx));
        assert!(on_screen(&app), "expanded rows show the badge");

        TabSettings::handle(&app).update(&mut app, |settings, ctx| {
            settings
                .vertical_tabs_view_mode
                .set_value(VerticalTabsViewMode::Compact, ctx)
                .expect("compact rows");
        });
        assert!(!on_screen(&app), "compact rows show no PR badge");
        assert_eventually!(
            400 => !holds_github_model(&app, &terminal),
            "so a background tab polls no longer"
        );

        TabSettings::handle(&app).update(&mut app, |settings, ctx| {
            settings
                .vertical_tabs_display_granularity
                .set_value(VerticalTabsDisplayGranularity::Tabs, ctx)
                .expect("tab rows");
            settings
                .vertical_tabs_tab_item_mode
                .set_value(VerticalTabsTabItemMode::Summary, ctx)
                .expect("summary rows");
        });
        assert!(
            on_screen(&app),
            "summary rows list the PR whatever the row mode"
        );
        assert!(
            holds_github_model(&app, &terminal),
            "and the tab is re-acquired at once"
        );

        TabSettings::handle(&app).update(&mut app, |settings, ctx| {
            settings
                .vertical_tabs_tab_item_mode
                .set_value(VerticalTabsTabItemMode::FocusedSession, ctx)
                .expect("focused session rows");
        });
        assert!(!on_screen(&app), "compact focused-session rows show none");
        TabSettings::handle(&app).update(&mut app, |settings, ctx| {
            settings
                .vertical_tabs_view_mode
                .set_value(VerticalTabsViewMode::Expanded, ctx)
                .expect("expanded rows");
            settings
                .vertical_tabs_show_pr_link
                .set_value(false, ctx)
                .expect("hide the PR link");
        });
        assert!(
            !on_screen(&app),
            "expanded rows hide the badge when PR link is off"
        );
    });
}

#[test]
fn focused_session_rows_show_only_the_focused_panes_pr_badge() {
    use crate::workspace::tab_settings::{
        TabSettings, VerticalTabsDisplayGranularity, VerticalTabsTabItemMode,
    };

    App::test((), |mut app| async move {
        let (_repo, workspace, first, _gh) = workspace_with_pr_chip_terminal_in_repo(&mut app);
        let repo = first.read(&app, |view, _| view.current_repo_path.clone());
        let pane_group = workspace.read(&app, |w, _| w.active_tab_pane_group().clone());
        pane_group.update(&mut app, |group, ctx| {
            group.add_terminal_pane(crate::pane_group::Direction::Right, None, ctx);
        });
        let second = pane_group.read(&app, |group, ctx| {
            group
                .terminal_view_at_pane_index(1, ctx)
                .expect("a second terminal")
        });
        second.update(&mut app, |view, ctx| {
            view.current_repo_path = repo;
            view.update_git_status_subscription(ctx);
        });
        enable_vertical_tabs_with_expanded_rows(&mut app);
        workspace.update(&mut app, |workspace, ctx| {
            workspace.handle_action(&WorkspaceAction::AddDefaultTab, ctx);
        });
        let badge = |app: &App, terminal: &ViewHandle<TerminalView>| {
            terminal.read(app, |view, ctx| view.pr_badge_on_screen(ctx))
        };
        assert!(
            badge(&app, &first) && badge(&app, &second),
            "pane rows show every badge"
        );

        TabSettings::handle(&app).update(&mut app, |settings, ctx| {
            settings
                .vertical_tabs_display_granularity
                .set_value(VerticalTabsDisplayGranularity::Tabs, ctx)
                .expect("tab rows");
            settings
                .vertical_tabs_tab_item_mode
                .set_value(VerticalTabsTabItemMode::FocusedSession, ctx)
                .expect("focused session rows");
        });
        let focused_is_second = second.read(&app, |view, ctx| {
            view.focus_handle
                .as_ref()
                .is_some_and(|handle| handle.is_focused(ctx))
        });
        assert_eq!(badge(&app, &second), focused_is_second);
        assert_eq!(badge(&app, &first), !focused_is_second);
    });
}

#[test]
fn maximized_pane_releases_the_pr_model_of_its_hidden_sibling() {
    use crate::pane_group::PaneGroupAction;

    App::test((), |mut app| async move {
        let (_repo, workspace, first, gh) = workspace_with_pr_chip_terminal_in_repo(&mut app);
        let repo = first.read(&app, |view, _| view.current_repo_path.clone());
        let pane_group = workspace.read(&app, |w, _| w.active_tab_pane_group().clone());
        pane_group.update(&mut app, |group, ctx| {
            group.add_terminal_pane(crate::pane_group::Direction::Right, None, ctx);
        });
        let second = pane_group.read(&app, |group, ctx| {
            group
                .terminal_view_at_pane_index(1, ctx)
                .expect("a second terminal")
        });
        second.update(&mut app, |view, ctx| {
            view.current_repo_path = repo.clone();
            view.update_git_status_subscription(ctx);
        });
        // The panes run real shells. When one has bootstrapped, repo detection replaces the
        // terminal's `current_repo_path` with the repository of the shell's own directory, which
        // is none here, and the PR model is dropped. On the Linux runner with zsh that happened in
        // the middle of the checks below in 85 of 100 runs (stress run 36954466501). Let it happen
        // first, up to 10 s, then put the repository back.
        let mut waited_ticks = 0;
        while waited_ticks < 2000
            && ![&first, &second].iter().all(|terminal| {
                terminal.read(&app, |view, _| {
                    view.model.lock().block_list().is_bootstrapped()
                        && view.current_repo_path != repo
                })
            })
        {
            warpui::r#async::Timer::after(std::time::Duration::from_millis(5)).await;
            waited_ticks += 1;
        }
        for terminal in [&first, &second] {
            terminal.update(&mut app, |view, ctx| {
                view.current_repo_path = repo.clone();
                view.update_git_status_subscription(ctx);
            });
        }
        for terminal in [&first, &second] {
            terminal.read(&app, |view, ctx| assert!(view.pr_info_on_screen(ctx)));
        }
        assert_eventually!(
            600 => gh.repository_lookups() >= 1 && gh.pr_lookups() >= 1,
            "the split panes look up the repository and, once the branch is known, the pull request"
        );
        warpui::r#async::Timer::after(std::time::Duration::from_millis(100)).await;

        pane_group.update(&mut app, |group, ctx| {
            group.handle_action(&PaneGroupAction::ToggleMaximizePane, ctx);
        });
        let hidden = if first.read(&app, |view, ctx| view.pane_is_shown(ctx)) {
            &second
        } else {
            &first
        };
        let shown = if std::ptr::eq(hidden, &first) {
            &second
        } else {
            &first
        };
        hidden.read(&app, |view, ctx| assert!(!view.pr_info_on_screen(ctx)));
        shown.read(&app, |view, ctx| assert!(view.pr_info_on_screen(ctx)));
        assert_eventually!(
            400 => !holds_github_model(&app, hidden),
            "the pane a maximized sibling covers releases its model"
        );
        assert!(
            holds_github_model(&app, shown),
            "the shown pane keeps its model"
        );

        let (repository_lookups, pr_lookups) = (gh.repository_lookups(), gh.pr_lookups());
        warpui::r#async::Timer::after(std::time::Duration::from_millis(150)).await;
        assert_eq!(
            (gh.repository_lookups(), gh.pr_lookups()),
            (repository_lookups, pr_lookups),
            "nothing polls while the pane is covered"
        );

        pane_group.update(&mut app, |group, ctx| {
            group.handle_action(&PaneGroupAction::ToggleMaximizePane, ctx);
        });
        hidden.read(&app, |view, ctx| assert!(view.pr_info_on_screen(ctx)));
        // The view re-acquires the model when it handles the pane group's
        // `PrInfoVisibilityChanged` event, not inside the action that un-maximizes. Asserting it
        // at once failed in CI (run 36949795721, `Unit tests`), so wait for it as the release
        // above is waited for.
        assert_eventually!(
            400 => holds_github_model(&app, hidden),
            "un-maximizing re-acquires it; hidden: {}; shown: {}",
            pr_info_state(&app, hidden),
            pr_info_state(&app, shown)
        );
        // The shown pane kept the shared model alive, so re-acquiring it is a single `gh pr view`
        // refresh and no new repository lookup.
        assert_eventually!(
            200 => gh.pr_lookups() == pr_lookups + 1,
            "restoring the pane refreshes the pull request once"
        );
        warpui::r#async::Timer::after(std::time::Duration::from_millis(200)).await;
        assert_eq!(gh.pr_lookups(), pr_lookups + 1, "and only once");
        assert_eq!(
            gh.repository_lookups(),
            repository_lookups,
            "the repository is not looked up again"
        );
    });
}

#[test]
fn two_shown_terminals_in_the_same_repo_share_one_model() {
    App::test((), |mut app| async move {
        let (_repo, workspace, first, gh) = workspace_with_pr_chip_terminal_in_repo(&mut app);
        let repo = first.read(&app, |view, _| view.current_repo_path.clone());
        enable_vertical_tabs_with_expanded_rows(&mut app);
        assert_eventually!(
            200 => gh.repository_lookups() >= 1,
            "the first tab looks up the repository"
        );
        warpui::r#async::Timer::after(std::time::Duration::from_millis(100)).await;
        let repository_lookups = gh.repository_lookups();

        workspace.update(&mut app, |workspace, ctx| {
            workspace.handle_action(&WorkspaceAction::AddDefaultTab, ctx);
        });
        let second = active_tab_terminal(&app, &workspace);
        second.update(&mut app, |view, ctx| {
            view.current_repo_path = repo;
            view.update_git_status_subscription(ctx);
        });

        for terminal in [&first, &second] {
            terminal.read(&app, |view, ctx| assert!(view.pr_info_on_screen(ctx)));
        }
        let model_of = |terminal: &ViewHandle<TerminalView>| {
            terminal.read(&app, |view, _| {
                view.github_repo_model.as_ref().map(|m| m.id())
            })
        };
        assert!(model_of(&first).is_some());
        assert_eq!(
            model_of(&first),
            model_of(&second),
            "both tabs hold one model"
        );
        warpui::r#async::Timer::after(std::time::Duration::from_millis(100)).await;
        assert_eq!(
            gh.repository_lookups(),
            repository_lookups,
            "the second consumer does not look the repository up again"
        );
    });
}

fn record_pty_writes(
    app: &mut App,
    terminal: &ViewHandle<TerminalView>,
) -> Rc<RefCell<Vec<Vec<u8>>>> {
    let pty_writes: Rc<RefCell<Vec<Vec<u8>>>> = Rc::new(RefCell::new(Vec::new()));
    let writes = pty_writes.clone();
    app.update(|ctx| {
        ctx.subscribe_to_view(terminal, move |_, event, _| {
            if let Event::WriteBytesToPty { bytes } = event {
                writes.borrow_mut().push(bytes.to_vec());
            }
        });
    });
    pty_writes
}

fn start_cli_agent_session(app: &mut App, terminal: &ViewHandle<TerminalView>) {
    terminal.update(app, |view, ctx| {
        CLIAgentSessionsModel::handle(ctx).update(ctx, |sessions, ctx| {
            sessions.set_session(
                view.view_id,
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
    });
}

#[test]
fn send_to_cli_agent_without_a_session_sends_nothing() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal = add_window_with_terminal(&mut app, None);
        let pty_writes = record_pty_writes(&mut app, &terminal);

        let routing = terminal.update(&mut app, |view, ctx| {
            view.try_send_text_to_cli_agent_or_rich_input("review this".to_owned(), ctx)
        });

        assert_eq!(routing, None);
        assert!(pty_writes.borrow().is_empty());
        terminal.read(&app, |view, ctx| {
            assert!(view.input.as_ref(ctx).buffer_text(ctx).is_empty());
        });
    });
}

#[test]
fn send_to_cli_agent_writes_to_the_pty_while_the_rich_input_is_closed() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal = add_window_with_terminal(&mut app, None);
        start_cli_agent_session(&mut app, &terminal);
        let pty_writes = record_pty_writes(&mut app, &terminal);

        let routing = terminal.update(&mut app, |view, ctx| {
            assert!(!view.is_cli_agent_rich_input_open(ctx));
            view.try_send_text_to_cli_agent_or_rich_input("review this".to_owned(), ctx)
        });

        assert_eq!(routing, Some(CliAgentRouting::Pty));
        assert_eq!(*pty_writes.borrow(), vec![b"review this".to_vec()]);
        terminal.read(&app, |view, ctx| {
            assert!(view.input.as_ref(ctx).buffer_text(ctx).is_empty());
        });
    });
}

#[test]
fn send_to_cli_agent_appends_to_the_rich_input_while_it_is_open() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal = open_cli_agent_rich_input_for_agent(&mut app, CLIAgent::Claude);
        let pty_writes = record_pty_writes(&mut app, &terminal);

        let routing = terminal.update(&mut app, |view, ctx| {
            view.try_send_text_to_cli_agent_or_rich_input("review this".to_owned(), ctx)
        });

        assert_eq!(routing, Some(CliAgentRouting::RichInput));
        assert!(pty_writes.borrow().is_empty());
        terminal.read(&app, |view, ctx| {
            assert_eq!(view.input.as_ref(ctx).buffer_text(ctx), "review this");
        });
    });
}

#[test]
fn send_diff_hunk_to_cli_agent_writes_the_hunk_location_to_the_pty() {
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal = add_window_with_terminal(&mut app, None);
        start_cli_agent_session(&mut app, &terminal);
        let pty_writes = record_pty_writes(&mut app, &terminal);

        let routing = terminal.update(&mut app, |view, ctx| {
            view.send_diff_hunk_to_cli_agent_or_rich_input("src/lib.rs", 3, 9, 4, 1, ctx)
        });

        assert_eq!(routing, Some(CliAgentRouting::Pty));
        assert_eq!(
            *pty_writes.borrow(),
            vec![b"src/lib.rs L3-L9 (+4 -1) -- run `git diff` to see the full context.".to_vec()]
        );
    });
}
