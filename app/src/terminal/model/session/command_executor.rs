#[cfg(test)]
mod git_completion_tests;
#[cfg(test)]
mod git_version_gate_tests;
mod in_band_command_executor;
mod local_command_executor;
mod network_sandbox;
mod offline_environment;
#[cfg(test)]
mod restored_generators_tests;
#[cfg(test)]
mod test_support;
use std::collections::HashMap;
mod noop_command_executor;
mod remote_command_executor;
mod shared;

use std::any::Any;
use std::fmt::Debug;
use std::sync::Arc;

use anyhow::Result;
use async_channel::{Receiver, Sender};
use async_trait::async_trait;
pub use in_band_command_executor::{
    InBandCommand, InBandCommandCancelledEvent, InBandCommandExecutor, InBandCommandOutputReceiver,
    is_in_band_command,
};
pub use local_command_executor::LocalCommandExecutor;
pub use noop_command_executor::NoOpCommandExecutor;
pub use remote_command_executor::RemoteCommandExecutor;
pub use shared::{
    ExecutorCommandEvent, serialize_variables_for_shell, shell_escape_single_quotes,
    shell_quote_arg,
};
use warp_completer::completer::CommandOutput;
use warpui::ModelContext;

use super::SessionInfo;
use crate::terminal::event::ExecutedExecutorCommandEvent;
use crate::terminal::model::session::Sessions;
use crate::terminal::shell::Shell;

/// Trait to be implemented by structs that execute command in context that emulates or actually is
/// identical to the active terminal session's context. `CommandExecutor` is commonly used to
/// execute generator commands to power completions, syntax highlighting, and autosuggestions.
#[async_trait]
pub trait CommandExecutor: Send + Sync + Debug {
    /// Executes the given command from the given `current_directory_path` with $PATH set to
    /// `path_env_var` and with the given environment variables.
    async fn execute_command(
        &self,
        command: &str,
        shell: &Shell,
        current_directory_path: Option<&str>,
        environment_variables: Option<HashMap<String, String>>,
    ) -> Result<CommandOutput>;

    /// Cancels in-progress commands.
    ///
    /// Some implementations may not need to explicitly cancel command execution, so a default
    /// implementation is given.
    fn cancel_active_commands(&self) {}

    /// Allows us to downcast an executor to check what command execution method is used by a
    /// session.
    fn as_any(&self) -> &dyn Any;

    /// Whether the backing executor for the session supports execution of commands in parallel.
    fn supports_parallel_command_execution(&self) -> bool;

    /// Whether every command this executor runs is kept from reaching an IP network by the
    /// operating system (macOS sandbox profile), so that a command that
    /// starts a networking tool still cannot connect. False unless an executor says otherwise:
    /// commands that run in the user's own shell or on another host are not isolated.
    fn network_isolated(&self) -> bool {
        false
    }
}

pub fn new_command_executor_for_session(
    session_info: &SessionInfo,
    executor_command_tx: &Sender<ExecutorCommandEvent>,
    in_band_command_output_rx: Receiver<ExecutedExecutorCommandEvent>,
    ctx: &mut ModelContext<Sessions>,
) -> Arc<dyn CommandExecutor> {
    new_command_executor_for_local_tty_session(
        session_info,
        executor_command_tx,
        in_band_command_output_rx,
        ctx,
    )
}

fn new_command_executor_for_local_tty_session(
    session_info: &SessionInfo,
    executor_command_tx: &Sender<ExecutorCommandEvent>,
    in_band_command_output_rx: Receiver<ExecutedExecutorCommandEvent>,
    ctx: &mut ModelContext<Sessions>,
) -> Arc<dyn CommandExecutor> {
    use settings::Setting as _;
    use warpui::SingletonEntity as _;

    use super::IsSSHWrapperSession;
    use crate::settings::DebugSettings;
    use crate::terminal::model::session::{BootstrapSessionType, ShellLaunchData};

    let debug_settings = DebugSettings::as_ref(ctx);
    let are_in_band_generators_for_all_sessions_enabled_debug_setting = debug_settings
        .are_in_band_generators_for_all_sessions_enabled
        .value();
    let should_force_disable_in_band_generators =
        debug_settings.force_disable_in_band_generators.value();

    let is_ssh_wrapper_session = matches!(
        &session_info.is_ssh_wrapper_session,
        IsSSHWrapperSession::Yes { .. }
    );

    let shell_needs_in_band_executor = session_info.shell.force_in_band_command_executor();
    let force_use_in_band_generators = shell_needs_in_band_executor
        || *are_in_band_generators_for_all_sessions_enabled_debug_setting;

    match &session_info.session_type {
        BootstrapSessionType::Local if !force_use_in_band_generators => {
            let shell_type = session_info.shell.shell_type();

            log::info!("creating a local executor!");
            match &session_info.launch_data {
                Some(ShellLaunchData::Executable {
                    executable_path, ..
                }) => Arc::new(LocalCommandExecutor::new(
                    Some(executable_path.to_owned()),
                    shell_type,
                )),
                None => Arc::new(LocalCommandExecutor::new(None, shell_type)),
            }
        }
        BootstrapSessionType::WarpifiedRemote
            if is_ssh_wrapper_session && !force_use_in_band_generators =>
        {
            if let IsSSHWrapperSession::Yes { socket_path, .. } =
                &session_info.is_ssh_wrapper_session
            {
                log::info!("creating a ControlMaster-based ssh executor!");
                Arc::new(RemoteCommandExecutor::new(socket_path.clone()))
            } else {
                unreachable!(
                    "Unreachable because of match! above. Unfortunately if let guards in rust are still experimental."
                )
            }
        }
        _ => {
            if *should_force_disable_in_band_generators {
                // The user has manually disabled in-band generators via command
                // modifying 'user defaults', so pass a no-op command executor.
                //
                // This code path exists as a fail-safe for disabling in-band
                // generators if some unforeseen severe issue surfaces during or
                // shortly after subshells launch. The setting that triggers this
                // codepath is only accessible via a user defaults command that a Warp
                // engineer would have given to the user via some first-hand
                // correspondence (e.g. GitHub issues).
                log::info!("creating a no-op executor!");
                Arc::new(NoOpCommandExecutor::new())
            } else {
                log::info!("creating an in-band command executor!");
                let (in_band_command_cancelled_tx, in_band_command_cancelled_rx) =
                    async_channel::unbounded();
                let executor = Arc::new(InBandCommandExecutor::new(
                    executor_command_tx.clone(),
                    in_band_command_cancelled_tx.clone(),
                ));
                let executor_clone = executor.clone();
                ctx.spawn_stream_local(
                    in_band_command_output_rx,
                    move |_, event, _| executor_clone.handle_executed_command_event(event),
                    |_, _| {}, /* on_done */
                );
                let executor_clone = executor.clone();
                ctx.spawn_stream_local(
                    in_band_command_cancelled_rx,
                    move |_, event, _| executor_clone.handle_cancelled_in_band_command_event(event),
                    |_, _| {}, /* on_done */
                );
                executor
            }
        }
    }
}

#[cfg(any(test, feature = "test-util"))]
pub mod testing {
    use anyhow::anyhow;
    use command::r#async::Command;
    use warp_completer::completer::CommandOutput;

    use super::*;
    use crate::terminal::shell::ShellType;

    /// Implementation of `CommandExecutor` for use in tests. This implementation simply executes
    /// the given command in a bash subprocess.
    #[derive(Debug, Default)]
    pub struct TestCommandExecutor {}

    #[async_trait]
    impl CommandExecutor for TestCommandExecutor {
        async fn execute_command(
            &self,
            command: &str,
            shell: &Shell,
            current_directory_path: Option<&str>,
            environment_variables: Option<HashMap<String, String>>,
        ) -> Result<CommandOutput> {
            let mut command_process = Command::new(match shell.shell_type() {
                ShellType::PowerShell => "pwsh",
                _ => "bash",
            });

            // Set environment variables, including $PATH.
            if let Some(environment_variables) = environment_variables {
                command_process.envs(&environment_variables);
            }

            // Set the current dir, if any.
            if let Some(current_directory_path) = current_directory_path {
                command_process.current_dir(current_directory_path);
            }

            command_process
                .arg("-c")
                .arg(command)
                .output()
                .await
                .map(|output| output.into())
                .map_err(|e| anyhow!(e))
        }

        fn as_any(&self) -> &dyn Any {
            self
        }

        fn supports_parallel_command_execution(&self) -> bool {
            false
        }
    }
}
