use std::any::Any;
use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use anyhow::{Result, anyhow};
use async_trait::async_trait;
use parking_lot::Mutex;
use warp_completer::completer::{CommandExitStatus, CommandOutput};
use warpui::elements::Empty;
use warpui::platform::WindowStyle;
use warpui::{App, AppContext, Element, Entity, ModelHandle, TypedActionView, View, ViewContext};

use super::command_executor::testing::TestCommandExecutor;
use super::command_executor::{CommandExecutor, ExecuteCommandOptions};
use super::{BootstrapSessionType, Session, SessionId, SessionInfo, Sessions, SessionsEvent};
use crate::terminal::shell::Shell;

struct TestView {
    events: Vec<SessionsEvent>,
}

impl Entity for TestView {
    type Event = usize;
}

impl View for TestView {
    fn render<'a>(&self, _: &AppContext) -> Box<dyn Element> {
        Empty::new().finish()
    }

    fn ui_name() -> &'static str {
        "TestView"
    }
}

impl TypedActionView for TestView {
    type Action = ();
}

impl TestView {
    fn new(model: ModelHandle<Sessions>, ctx: &mut ViewContext<Self>) -> Self {
        ctx.subscribe_to_model(&model, |me, _, event, _| {
            me.events.push(event.to_owned());
        });
        Self { events: Vec::new() }
    }
}

#[test]
fn test_set_env_var_emits_event() {
    App::test((), |mut app| async move {
        let model_handle = app.add_model(|_| Sessions::new_for_test());
        let session_id: SessionId = 0.into();
        let (_, view_handle) = app.add_window(WindowStyle::NotStealFocus, |ctx| {
            TestView::new(model_handle.clone(), ctx)
        });
        view_handle.read(&app, |view, _ctx| {
            assert!(view.events.is_empty());
        });
        model_handle.update(&mut app, |sessions, ctx| {
            let new_vars = HashMap::from_iter([("foo".to_string(), "bar".to_string())]);
            sessions.set_env_vars_for_session(session_id, new_vars, ctx)
        });

        view_handle.read(&app, |view, _ctx| {
            assert_eq!(view.events.len(), 1);
            let expected_session_id = session_id;
            let event = view.events.first().expect("checked length already");
            if let SessionsEvent::EnvironmentVariablesUpdated { session_id } = event {
                assert_eq!(*session_id, expected_session_id);
            } else {
                assert!(matches!(
                    event,
                    SessionsEvent::EnvironmentVariablesUpdated { .. }
                ));
            }
        });
    });
}

#[test]
fn test_set_env_var_emits_no_event_when_no_change() {
    App::test((), |mut app| async move {
        let model_handle = app.add_model(|_| Sessions::new_for_test());
        let session_id: SessionId = 0.into();
        let (_, view_handle) = app.add_window(WindowStyle::NotStealFocus, |ctx| {
            TestView::new(model_handle.clone(), ctx)
        });
        view_handle.read(&app, |view, _ctx| {
            assert!(view.events.is_empty());
        });
        model_handle.update(&mut app, |sessions, ctx| {
            let new_vars = HashMap::from_iter([("foo".to_string(), "bar".to_string())]);
            sessions.set_env_vars_for_session(session_id, new_vars, ctx)
        });

        view_handle.read(&app, |view, _ctx| {
            assert_eq!(view.events.len(), 1);
        });

        model_handle.update(&mut app, |sessions, ctx| {
            let new_vars = HashMap::from_iter([("foo".to_string(), "bar".to_string())]);
            sessions.set_env_vars_for_session(session_id, new_vars, ctx)
        });

        view_handle.read(&app, |view, _ctx| {
            assert_eq!(view.events.len(), 1);
        });
    });
}

#[test]
fn test_malicious_histfile_path_does_not_execute_injected_commands() {
    App::test((), |_app| async move {
        // If escaping is missing, `touch /tmp/warp_injection_test` would execute
        // as a side effect of reading history.
        let marker = "/tmp/warp_injection_test";
        // Clean up in case a previous broken run left the marker.
        let _ = std::fs::remove_file(marker);

        let malicious_histfile = format!("/tmp/x'; touch {marker}; echo '");

        let session_info = SessionInfo::new_for_test()
            .with_session_type(BootstrapSessionType::WarpifiedRemote)
            .with_histfile(Some(malicious_histfile));
        let session = Session::new(session_info, Arc::new(TestCommandExecutor::default()));

        // read_history for a WarpifiedRemote session calls read_history_from_file,
        // which builds `cat '{escaped_path}'` and executes it via TestCommandExecutor
        let _ = session.read_history(false).await;

        assert!(
            !std::path::Path::new(marker).exists(),
            "Injected command executed — escaping regression!"
        );
    });
}

#[cfg(not(windows))]
#[test]
fn can_resolve_cwd_to_native_path_accepts_posix_path() {
    let session = Session::test();
    assert!(session.can_resolve_cwd_to_native_path("/Users/foo/bar"));
}

#[cfg(windows)]
#[test]
fn can_resolve_cwd_to_native_path_accepts_windows_drive_path() {
    let session = Session::test();
    assert!(session.can_resolve_cwd_to_native_path(r"E:\CLAUDE-BASE"));
}

#[cfg(windows)]
#[test]
fn can_resolve_cwd_to_native_path_rejects_unix_encoded_path_on_windows() {
    let session_info =
        SessionInfo::new_for_test().with_shell_type(crate::terminal::shell::ShellType::Bash);
    let session = Session::new(session_info, Arc::new(TestCommandExecutor::default()));
    assert!(!session.can_resolve_cwd_to_native_path("/E:/CLAUDE-BASE"));
}

#[cfg(windows)]
#[test]
fn powershell_read_command_embeds_escaped_path_without_args() {
    use std::ffi::{OsStr, OsString};

    use super::powershell_read_all_text_command;

    // The path is embedded directly inside a single-quoted PowerShell literal.
    let raw = r"C:\Users\dev\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt";
    let command = powershell_read_all_text_command(OsStr::new(raw));
    assert_eq!(
        command,
        OsString::from(format!("[System.IO.File]::ReadAllText('{raw}')"))
    );

    // A single quote in the path is doubled so it can't terminate the literal.
    let command = powershell_read_all_text_command(OsStr::new(r"C:\o'brien\history.txt"));
    assert_eq!(
        command,
        OsString::from(r"[System.IO.File]::ReadAllText('C:\o''brien\history.txt')")
    );
}

/// What a [`ScriptedExecutor`] does for one call of `execute_command`.
enum Scripted {
    /// Output of a command that was killed: a failure status and no output.
    Killed,
    /// The command could not be run at all.
    CannotRun,
    /// Output of a successful command.
    Output(&'static str),
    /// Waits until `cancel_active_commands` is called, then behaves like [`Scripted::Killed`].
    HangUntilCancelled,
}

/// A [`CommandExecutor`] that answers each call from a script and counts the calls.
#[derive(Debug)]
struct ScriptedExecutor {
    script: Mutex<VecDeque<Scripted>>,
    calls: AtomicUsize,
    started: (async_channel::Sender<()>, async_channel::Receiver<()>),
    cancelled: (async_channel::Sender<()>, async_channel::Receiver<()>),
}

impl std::fmt::Debug for Scripted {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Scripted")
    }
}

impl ScriptedExecutor {
    fn new(script: impl IntoIterator<Item = Scripted>) -> Arc<Self> {
        Arc::new(Self {
            script: Mutex::new(script.into_iter().collect()),
            calls: AtomicUsize::new(0),
            started: async_channel::unbounded(),
            cancelled: async_channel::unbounded(),
        })
    }

    fn calls(&self) -> usize {
        self.calls.load(Ordering::SeqCst)
    }
}

fn killed_output() -> CommandOutput {
    CommandOutput {
        stdout: Vec::new(),
        stderr: Vec::new(),
        status: CommandExitStatus::Failure,
        exit_code: None,
    }
}

#[async_trait]
impl CommandExecutor for ScriptedExecutor {
    async fn execute_command(
        &self,
        _command: &str,
        _shell: &Shell,
        _current_directory_path: Option<&str>,
        _environment_variables: Option<HashMap<String, String>>,
        _execute_command_options: ExecuteCommandOptions,
    ) -> Result<CommandOutput> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        let next = self.script.lock().pop_front();
        match next.expect("the script ran out of answers") {
            Scripted::Killed => Ok(killed_output()),
            Scripted::CannotRun => Err(anyhow!("cannot run")),
            Scripted::Output(stdout) => Ok(CommandOutput {
                stdout: stdout.as_bytes().to_vec(),
                stderr: Vec::new(),
                status: CommandExitStatus::Success,
                exit_code: None,
            }),
            Scripted::HangUntilCancelled => {
                self.started.0.send(()).await.unwrap();
                self.cancelled.1.recv().await.unwrap();
                Ok(killed_output())
            }
        }
    }

    fn as_any(&self) -> &dyn Any {
        self
    }

    fn supports_parallel_command_execution(&self) -> bool {
        true
    }

    fn cancel_active_commands(&self) {
        let _ = self.cancelled.0.try_send(());
    }
}

fn names(session: &Session) -> HashSet<&str> {
    assert!(
        session.has_loaded_external_commands(),
        "the executables should be loaded"
    );
    session.executable_names().collect()
}

#[test]
fn listing_cancelled_with_the_sessions_commands_is_run_again() {
    App::test((), |_app| async move {
        let executor =
            ScriptedExecutor::new([Scripted::HangUntilCancelled, Scripted::Output("ls\ncat\n")]);
        let session = Session::new(SessionInfo::new_for_test(), executor.clone());

        let cancel = async {
            executor.started.1.recv().await.unwrap();
            session.cancel_active_commands();
        };
        futures::join!(session.load_external_commands(), cancel);

        assert_eq!(executor.calls(), 2);
        assert_eq!(names(&session), HashSet::from(["ls", "cat"]));
    });
}

#[test]
fn listing_that_failed_once_is_run_again() {
    App::test((), |_app| async move {
        let executor = ScriptedExecutor::new([
            Scripted::Killed,
            Scripted::CannotRun,
            Scripted::Output("git\n"),
        ]);
        let session = Session::new(SessionInfo::new_for_test(), executor.clone());

        session.load_external_commands().await;

        assert_eq!(executor.calls(), 3);
        assert_eq!(names(&session), HashSet::from(["git"]));
    });
}

#[test]
fn listing_that_never_succeeds_is_not_stored_as_empty() {
    App::test((), |_app| async move {
        let executor =
            ScriptedExecutor::new([Scripted::Killed, Scripted::CannotRun, Scripted::Killed]);
        let session = Session::new(SessionInfo::new_for_test(), executor.clone());

        session.load_external_commands().await;
        // Waiting again returns at once: the listing is attempted once per session.
        session.load_external_commands().await;

        assert_eq!(executor.calls(), 3);
        assert!(!session.has_loaded_external_commands());
        assert!(session.has_attempted_to_load_external_commands());
    });
}

#[test]
fn listing_that_succeeds_with_no_output_is_stored_as_empty() {
    App::test((), |_app| async move {
        let executor = ScriptedExecutor::new([Scripted::Output("")]);
        let session = Session::new(SessionInfo::new_for_test(), executor.clone());

        session.load_external_commands().await;

        assert_eq!(executor.calls(), 1);
        assert!(session.has_loaded_external_commands());
        assert!(names(&session).is_empty());
    });
}
