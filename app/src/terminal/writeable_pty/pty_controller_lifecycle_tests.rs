use std::sync::Arc;

use parking_lot::{FairMutex, Mutex};
use warpui::App;

use super::*;
use crate::terminal::event_listener::ChannelEventListener;
use crate::terminal::model::StartCommandOutcome;
use crate::terminal::model::ansi::{Handler, PreexecValue};
use crate::terminal::model::session::{SessionId, SessionInfo, Sessions};

#[derive(Clone, Default)]
struct TestEventLoopSender {
    messages: Arc<Mutex<Vec<Message>>>,
}

impl EventLoopSender for TestEventLoopSender {
    fn send(&self, message: Message) -> Result<(), EventLoopSendError> {
        self.messages.lock().push(message);
        Ok(())
    }
}

fn terminal_model() -> Arc<FairMutex<TerminalModel>> {
    Arc::new(FairMutex::new(TerminalModel::mock(
        None,
        Some(ChannelEventListener::new_for_test()),
    )))
}

#[test]
fn rejected_and_coalesced_starts_do_not_mutate_controller_or_write_bytes() {
    App::test((), |mut app| async move {
        let model = terminal_model();
        let (model_events_tx, model_events_rx) = async_channel::unbounded();
        let (_executor_command_tx, executor_command_rx) = async_channel::unbounded();
        let sessions = app.add_model(|_| Sessions::new_for_test());
        let model_events =
            app.add_model(|ctx| ModelEventDispatcher::new(model_events_rx, sessions.clone(), ctx));
        let line_editor_status =
            app.add_model(|ctx| LineEditorStatus::new(model_events.clone(), sessions.clone(), ctx));
        let sender = TestEventLoopSender::default();
        let controller = app.add_model(|ctx| {
            PtyController::new(
                sender.clone(),
                model_events,
                line_editor_status,
                sessions,
                executor_command_rx,
                model.clone(),
                ctx,
            )
        });
        controller.update(&mut app, |controller, _| {
            controller.pending_writes.push_back(PtyWrite::Bytes {
                bytes: b"existing-pending-write".to_vec().into(),
            });
        });

        assert_eq!(
            model.lock().start_command_execution(),
            StartCommandOutcome::Accepted
        );
        let coalesced = controller.update(&mut app, |controller, ctx| {
            controller.write_command("coalesced", ShellType::Zsh, ctx)
        });
        assert_eq!(coalesced, StartCommandOutcome::Coalesced);
        controller.read(&app, |controller, _| {
            assert!(!controller.is_user_command_executing);
            assert_eq!(controller.pending_writes.len(), 1);
        });
        assert!(sender.messages.lock().is_empty());

        model.lock().preexec(PreexecValue {
            command: "running".to_owned(),
            session_id: None,
        });
        let rejected = controller.update(&mut app, |controller, ctx| {
            controller.write_command("rejected", ShellType::Zsh, ctx)
        });
        assert_eq!(rejected, StartCommandOutcome::RejectedExecuting);
        controller.read(&app, |controller, _| {
            assert!(!controller.is_user_command_executing);
            assert_eq!(controller.pending_writes.len(), 1);
        });
        assert!(sender.messages.lock().is_empty());

        drop(model_events_tx);
    });
}

#[test]
fn native_shell_completions_queues_the_generator_command_for_the_active_sessions_shell() {
    App::test((), |mut app| async move {
        let model = terminal_model();
        let (model_events_tx, model_events_rx) = async_channel::unbounded();
        let (_executor_command_tx, executor_command_rx) = async_channel::unbounded();
        let mut sessions = Sessions::new_for_test();
        let session_id = SessionId::from(42);
        sessions.register_session_for_test(
            SessionInfo::new_for_test()
                .with_id(session_id)
                .with_shell_type(ShellType::Fish),
        );
        let sessions = app.add_model(|_| sessions);
        let model_events = app.add_model(|ctx| {
            let mut dispatcher = ModelEventDispatcher::new(model_events_rx, sessions.clone(), ctx);
            dispatcher.set_active_session_id(session_id);
            dispatcher
        });
        let line_editor_status =
            app.add_model(|ctx| LineEditorStatus::new(model_events.clone(), sessions.clone(), ctx));
        let sender = TestEventLoopSender::default();
        let controller = app.add_model(|ctx| {
            PtyController::new(
                sender.clone(),
                model_events,
                line_editor_status,
                sessions,
                executor_command_rx,
                model,
                ctx,
            )
        });

        let (results_tx, _results_rx) = async_channel::unbounded();
        controller.update(&mut app, |controller, ctx| {
            controller.run_native_shell_completions("git ch".to_owned(), results_tx, ctx);
        });

        // The line editor isn't active by default, so the write should still be queued rather
        // than sent to the event loop.
        assert!(sender.messages.lock().is_empty());
        controller.read(&app, |controller, _| {
            assert_eq!(controller.pending_writes.len(), 1);
            let Some(PtyWrite::RunNativeShellCompletions {
                command,
                shell_type,
                ..
            }) = controller.pending_writes.front()
            else {
                panic!("expected a queued RunNativeShellCompletions write");
            };
            assert_eq!(*shell_type, ShellType::Fish);
            assert_eq!(
                command,
                " warp_run_generator_command_native_completions 676974206368"
            );
        });

        drop(model_events_tx);
    });
}

#[test]
fn native_shell_completions_reports_no_matches_without_an_active_session() {
    App::test((), |mut app| async move {
        let model = terminal_model();
        let (model_events_tx, model_events_rx) = async_channel::unbounded();
        let (_executor_command_tx, executor_command_rx) = async_channel::unbounded();
        let sessions = app.add_model(|_| Sessions::new_for_test());
        let model_events =
            app.add_model(|ctx| ModelEventDispatcher::new(model_events_rx, sessions.clone(), ctx));
        let line_editor_status =
            app.add_model(|ctx| LineEditorStatus::new(model_events.clone(), sessions.clone(), ctx));
        let sender = TestEventLoopSender::default();
        let controller = app.add_model(|ctx| {
            PtyController::new(
                sender.clone(),
                model_events,
                line_editor_status,
                sessions,
                executor_command_rx,
                model,
                ctx,
            )
        });

        let (results_tx, results_rx) = async_channel::unbounded();
        controller.update(&mut app, |controller, ctx| {
            controller.run_native_shell_completions("git ch".to_owned(), results_tx, ctx);
        });

        let (completions, replacement_span) = results_rx
            .try_recv()
            .expect("should immediately receive empty results");
        assert!(completions.is_empty());
        assert!(replacement_span.is_none());
        controller.read(&app, |controller, _| {
            assert!(controller.pending_writes.is_empty());
        });
        assert!(sender.messages.lock().is_empty());

        drop(model_events_tx);
    });
}

#[test]
fn rejected_queued_in_band_start_is_cancelled_without_writing_bytes() {
    App::test((), |mut app| async move {
        let model = terminal_model();
        model.lock().start_command_execution();
        model.lock().preexec(PreexecValue {
            command: "running".to_owned(),
            session_id: None,
        });

        let (model_events_tx, model_events_rx) = async_channel::unbounded();
        let (_executor_command_tx, executor_command_rx) = async_channel::unbounded();
        let sessions = app.add_model(|_| Sessions::new_for_test());
        let model_events =
            app.add_model(|ctx| ModelEventDispatcher::new(model_events_rx, sessions.clone(), ctx));
        let line_editor_status =
            app.add_model(|ctx| LineEditorStatus::new(model_events.clone(), sessions.clone(), ctx));
        let sender = TestEventLoopSender::default();
        let controller = app.add_model(|ctx| {
            PtyController::new(
                sender.clone(),
                model_events,
                line_editor_status.clone(),
                sessions,
                executor_command_rx,
                model.clone(),
                ctx,
            )
        });
        let (cancel_tx, cancel_rx) = async_channel::unbounded();

        controller.update(&mut app, |controller, ctx| {
            controller.queue_in_band_command(
                "rejected-in-band",
                ShellType::Zsh,
                "command-id".to_owned(),
                cancel_tx,
                ctx,
            );
            let write = controller
                .pending_writes
                .pop_front()
                .expect("The inactive line editor should leave the in-band command queued.");
            assert!(!controller.send_write_to_event_loop(write, ctx));
        });

        assert_eq!(
            cancel_rx
                .try_recv()
                .expect("The rejected in-band command should be cancelled.")
                .command_id,
            "command-id"
        );
        assert!(sender.messages.lock().is_empty());
        line_editor_status.read(&app, |line_editor_status, _| {
            assert!(!line_editor_status.is_line_editor_active());
        });
        drop(model_events_tx);
    });
}

#[test]
fn reporting_requests_carry_the_current_prompt_instead_of_mutating_output_state() {
    for (shell_type, expected_key) in [
        (ShellType::Zsh, Some(*b"\x1bi")),
        (ShellType::PowerShell, Some(*b"\x1b1")),
        (ShellType::Bash, None),
    ] {
        App::test((), |mut app| async move {
            let model = terminal_model();
            {
                let mut model = model.lock();
                let blocks = model.block_list_mut();
                blocks.bootstrapped(crate::terminal::model::ansi::BootstrappedValue::default());
                blocks.command_finished(Default::default());
                blocks.prompt_only_precmd(Default::default());
            }
            let block = model.lock().input_reporting_block().unwrap();
            let (model_events_tx, model_events_rx) = async_channel::unbounded();
            let (_executor_command_tx, executor_command_rx) = async_channel::unbounded();
            let mut sessions = Sessions::new_for_test();
            let session_id = SessionId::from(42);
            sessions.register_session_for_test(
                SessionInfo::new_for_test()
                    .with_id(session_id)
                    .with_shell_type(shell_type),
            );
            let sessions = app.add_model(|_| sessions);
            let model_events = app.add_model(|ctx| {
                let mut dispatcher =
                    ModelEventDispatcher::new(model_events_rx, sessions.clone(), ctx);
                dispatcher.set_active_session_id(session_id);
                dispatcher
            });
            let status = app.add_model(|ctx| {
                LineEditorStatus::new(model_events.clone(), sessions.clone(), ctx)
            });
            let sender = TestEventLoopSender::default();
            let controller = app.add_model(|ctx| {
                PtyController::new(
                    sender.clone(),
                    model_events,
                    status.clone(),
                    sessions,
                    executor_command_rx,
                    model.clone(),
                    ctx,
                )
            });
            status.update(&mut app, |status, ctx| status.mark_active_for_test(ctx));
            let messages = sender.messages.lock();
            match expected_key {
                Some(expected_key) => assert!(
                    matches!(messages.as_slice(), [Message::InputReportingKey { key, block: got, .. }] if *key == expected_key && got == &block)
                ),
                None => assert!(messages.is_empty()),
            }
            drop(messages);
            model.lock().start_command_execution();
            assert!(model.lock().input_reporting_block().is_none());
            controller.update(&mut app, |controller, ctx| {
                controller
                    .send_write_to_event_loop(PtyWrite::InputReportingKey { key: *b"\x1bi" }, ctx);
            });
            assert_eq!(
                sender.messages.lock().len(),
                usize::from(expected_key.is_some()),
                "no reporting key may be sent after command submission"
            );
            drop(model_events_tx);
        });
    }
}

#[test]
fn a_user_command_queued_before_prompt_activation_runs_without_a_reporting_block() {
    for outstanding_report in [false, true] {
        App::test((), |mut app| async move {
            let model = terminal_model();
            {
                let mut model = model.lock();
                let blocks = model.block_list_mut();
                blocks.bootstrapped(Default::default());
                blocks.command_finished(Default::default());
                blocks.prompt_only_precmd(Default::default());
            }
            let (_model_events_tx, model_events_rx) = async_channel::unbounded();
            let (_executor_command_tx, executor_command_rx) = async_channel::unbounded();
            let mut sessions = Sessions::new_for_test();
            let id = SessionId::from(42);
            sessions.register_session_for_test(
                SessionInfo::new_for_test()
                    .with_id(id)
                    .with_shell_type(ShellType::Zsh),
            );
            let sessions = app.add_model(|_| sessions);
            let events = app.add_model(|ctx| {
                let mut dispatcher =
                    ModelEventDispatcher::new(model_events_rx, sessions.clone(), ctx);
                dispatcher.set_active_session_id(id);
                dispatcher
            });
            let status =
                app.add_model(|ctx| LineEditorStatus::new(events.clone(), sessions.clone(), ctx));
            let sender = TestEventLoopSender::default();
            let controller = app.add_model(|ctx| {
                PtyController::new(
                    sender.clone(),
                    events,
                    status.clone(),
                    sessions,
                    executor_command_rx,
                    model.clone(),
                    ctx,
                )
            });

            let previous_done = if outstanding_report {
                status.update(&mut app, |status, ctx| status.mark_active_for_test(ctx));
                let done = match &sender.messages.lock()[0] {
                    Message::InputReportingKey { done, .. } => done.clone(),
                    other => panic!("expected an outstanding report: {other:?}"),
                };
                status.update(&mut app, |status, ctx| status.did_execute_command(ctx));
                Some(done)
            } else {
                None
            };
            let before = sender.messages.lock().len();

            assert_eq!(
                controller.update(&mut app, |controller, ctx| {
                    controller.write_command("printf queued-user-command", ShellType::Zsh, ctx)
                }),
                StartCommandOutcome::Accepted
            );
            assert_eq!(sender.messages.lock().len(), before);
            assert!(model.lock().input_reporting_block().is_none());
            status.update(&mut app, |status, ctx| status.mark_active_for_test(ctx));

            {
                let messages = sender.messages.lock();
                let [Message::Input(bytes)] = &messages[before..] else {
                    panic!("the queued user command was not written: {messages:?}");
                };
                assert!(
                    bytes
                        .windows(b"queued-user-command".len())
                        .any(|part| part == b"queued-user-command")
                );
            }
            controller.read(&app, |controller, _| {
                assert!(controller.pending_writes.is_empty())
            });
            if let Some(done) = previous_done {
                done.try_send(false).unwrap();
                warpui::r#async::Timer::after(std::time::Duration::from_millis(20)).await;
                controller.read(&app, |controller, _| {
                    assert!(!controller.reporting_pending);
                    assert!(controller.reporting_required);
                });
                assert_eq!(sender.messages.lock().len(), before + 1);
            }
        });
    }
}

#[test]
fn queued_in_band_commands_wait_for_the_reporting_write_and_a_timeout_preserves_typeahead() {
    for first_write_succeeds in [true, false] {
        App::test((), |mut app| async move {
            let model = terminal_model();
            {
                let mut model = model.lock();
                let blocks = model.block_list_mut();
                blocks.bootstrapped(Default::default());
                blocks.command_finished(Default::default());
                blocks.prompt_only_precmd(Default::default());
            }
            let (model_events_tx, model_events_rx) = async_channel::unbounded();
            let (_executor_command_tx, executor_command_rx) = async_channel::unbounded();
            let mut sessions = Sessions::new_for_test();
            let id = SessionId::from(42);
            sessions.register_session_for_test(
                SessionInfo::new_for_test()
                    .with_id(id)
                    .with_shell_type(ShellType::Zsh),
            );
            let sessions = app.add_model(|_| sessions);
            let events = app.add_model(|ctx| {
                let mut dispatcher =
                    ModelEventDispatcher::new(model_events_rx, sessions.clone(), ctx);
                dispatcher.set_active_session_id(id);
                dispatcher
            });
            let status =
                app.add_model(|ctx| LineEditorStatus::new(events.clone(), sessions.clone(), ctx));
            let sender = TestEventLoopSender::default();
            let controller = app.add_model(|ctx| {
                PtyController::new(
                    sender.clone(),
                    events,
                    status.clone(),
                    sessions,
                    executor_command_rx,
                    model.clone(),
                    ctx,
                )
            });
            controller.update(&mut app, |controller, ctx| {
                controller.queue_in_band_command(
                    "in-band",
                    ShellType::Zsh,
                    "id".to_owned(),
                    async_channel::unbounded().0,
                    ctx,
                )
            });
            status.update(&mut app, |status, ctx| status.mark_active_for_test(ctx));
            assert!(model.lock().input_reporting_block().is_some());
            assert_eq!(
                sender.messages.lock().len(),
                1,
                "the command must stay queued while the event loop has not written the reporting key"
            );
            let done = match &sender.messages.lock()[0] {
                Message::InputReportingKey { done, .. } => done.clone(),
                other => panic!("{other:?}"),
            };
            done.try_send(first_write_succeeds).unwrap();
            warpui::r#async::Timer::after(std::time::Duration::from_millis(20)).await;
            if !first_write_succeeds {
                assert_eq!(
                    sender.messages.lock().len(),
                    1,
                    "a timeout cannot send a kill-buffer chord"
                );
                assert!(model.lock().input_reporting_block().is_some());
                controller.update(&mut app, |controller, ctx| {
                    controller.queue_in_band_command(
                        "second",
                        ShellType::Zsh,
                        "id-2".to_owned(),
                        async_channel::unbounded().0,
                        ctx,
                    );
                    controller.run_native_shell_completions(
                        "third".to_owned(),
                        async_channel::unbounded().0,
                        ctx,
                    );
                });
                assert_eq!(
                    sender.messages.lock().len(),
                    1,
                    "new queue entries cannot bypass the failed report"
                );
                assert!(model.lock().input_reporting_block().is_some());
                status.update(&mut app, |status, ctx| status.mark_active_for_test(ctx));
                let done = match &sender.messages.lock()[1] {
                    Message::InputReportingKey { done, .. } => done.clone(),
                    other => panic!("{other:?}"),
                };
                done.try_send(true).unwrap();
                warpui::r#async::Timer::after(std::time::Duration::from_millis(20)).await;
            }
            assert!(model.lock().input_reporting_block().is_none());
            assert!(matches!(
                sender.messages.lock().last(),
                Some(Message::Input(_))
            ));
            drop(model_events_tx);
        });
    }
}
