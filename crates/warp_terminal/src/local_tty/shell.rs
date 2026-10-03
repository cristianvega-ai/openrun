use std::ffi::OsString;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use warp_core::channel::{Channel, ChannelState};
use warp_core::session_id::SessionId;
use warp_errors::report_error;
use warp_util::path::{resolve_executable, warp_shell_path};

use crate::bootstrap::{generate_session_id, init_shell_script_for_shell};
use crate::shell::{ShellLaunchData, ShellName, ShellType};

pub const ZSH_SHELL_PATH: &str = "/bin/zsh";
pub const BASH_SHELL_PATH: &str = "/bin/bash";
pub const FISH_SHELL_PATH: &str = "/bin/fish";

pub trait AvailableShell {
    fn get_valid_shell_path_and_type(&self) -> Option<ShellLaunchData>;
}

/// Returns an iterator of additional PATH entries to append to the shell's PATH.
/// This includes `$APP_PATH/Contents/Resources/bin`, in which we put a wrapper around the Warp CLI,
/// and is empty when the app is not running from a bundle.
pub fn extra_path_entries() -> impl Iterator<Item = PathBuf> {
    use itertools::Either;

    if let Some(resources_path) = warp_core::paths::bundled_resources_dir() {
        let bin_path = resources_path.join("bin");
        Either::Left(std::iter::once(bin_path))
    } else {
        Either::Right(std::iter::empty())
    }
}

/// Returns `true` if the given `path_or_command` is a valid, executable command or path to a
/// executable binary for one of Warp's supported shell types (bash, fish, zsh).
pub fn is_valid_path_or_command_for_supported_shell(path_or_command: &str) -> bool {
    supported_shell_path_and_type(path_or_command).is_some()
}

impl ShellStarterSource {
    /// Constructs the shell binary (and corresponding arguments) used to spawn a shell process for
    /// a new top-level session.
    ///
    /// Returns an enum indicating the source from which the shell was determined. If the fallback
    /// default shell is used, also includes the requested but unsupported shell information.
    pub fn init(preferred_shell: impl AvailableShell) -> Option<Self> {
        if let Some(ShellLaunchData::Executable {
            executable_path,
            shell_type,
        }) = preferred_shell.get_valid_shell_path_and_type()
        {
            let session_id = generate_session_id();
            let args = arguments_for_session_spawning_command(
                executable_path.to_string_lossy().as_ref(),
                shell_type,
                session_id,
            );
            return Some(Self::Override(DirectShellStarter {
                args,
                shell_path: executable_path,
                shell_type,
                session_id,
            }));
        }

        if let Some(warp_shell_env_var) = warp_shell_path() {
            let (warp_shell_path, shell_type) = supported_shell_path_and_type(&warp_shell_env_var)
                .unwrap_or_else(|| {
                    panic!("Cannot spawn shell; $WARP_SHELL_PATH is invalid: {warp_shell_env_var}")
                });
            let session_id = generate_session_id();
            let args = arguments_for_session_spawning_command(
                warp_shell_path.as_path().to_string_lossy().as_ref(),
                shell_type,
                session_id,
            );
            return Some(Self::Environment(DirectShellStarter {
                args,
                shell_path: warp_shell_path,
                shell_type,
                session_id,
            }));
        }

        Self::compute_fallback_shell()
    }

    fn compute_fallback_shell() -> Option<Self> {
        let pw_shell_path = super::unix::resolve_current_user().map(|user| user.shell);
        if pw_shell_path.is_none() {
            report_error!(
                "could not resolve the current user (getpwuid, getent, and /etc/passwd all failed)",
                extra: { "uid" => %nix::unistd::getuid().as_raw() }
            );
        }
        if let Some((resolved_pw_shell_path, shell_type)) = pw_shell_path
            .as_deref()
            .and_then(supported_shell_path_and_type)
        {
            let session_id = generate_session_id();
            let args = arguments_for_session_spawning_command(
                resolved_pw_shell_path.as_path().to_string_lossy().as_ref(),
                shell_type,
                session_id,
            );
            return Some(Self::UserDefault(DirectShellStarter {
                args,
                shell_path: resolved_pw_shell_path,
                shell_type,
                session_id,
            }));
        }
        let (resolved_default_shell_path, shell_type) = if let Some(shell_path_and_type) =
            supported_shell_path_and_type(ZSH_SHELL_PATH)
        {
            shell_path_and_type
        } else if let Some(shell_path_and_type) = supported_shell_path_and_type(BASH_SHELL_PATH) {
            shell_path_and_type
        } else if let Some(shell_path_and_type) = supported_shell_path_and_type(FISH_SHELL_PATH) {
            shell_path_and_type
        } else {
            log::warn!(
                "Did not find valid binaries when attempting to load fallback shell (not bash, fish, or zsh)."
            );
            return None;
        };

        let session_id = generate_session_id();
        let args = arguments_for_session_spawning_command(
            resolved_default_shell_path
                .as_path()
                .to_string_lossy()
                .as_ref(),
            shell_type,
            session_id,
        );
        Some(Self::Fallback {
            starter: DirectShellStarter {
                args,
                shell_path: resolved_default_shell_path,
                shell_type,
                session_id,
            },
        })
    }
}

/// Wraps up a shell type and the command to start it.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DirectShellStarter {
    shell_type: ShellType,
    shell_path: PathBuf,

    /// Arguments to be passed to the shell binary at [`shell_path`] when spawning a new Warp
    /// session.
    args: Vec<OsString>,

    /// The client-generated session ID for the shell bootstrap. For shells
    /// whose init script is passed in command args, this ID is already embedded
    /// in `args`. For zsh, `TerminalManager::enqueue_init_script`
    /// injects this same ID immediately before PTY creation.
    session_id: SessionId,
}

#[derive(Debug)]
pub enum ShellStarterSource {
    /// The user chose the path by setting a custom shell path in settings.
    Override(DirectShellStarter),
    /// The user chose the path to the shell by setting the `WARP_SHELL_PATH` environment variable.
    Environment(DirectShellStarter),
    /// The default shell for the user (as indicated by the user's passwd entry on UNIX).
    UserDefault(DirectShellStarter),
    /// We weren't able to find a shell that could be bootstrapped for the user.
    Fallback { starter: DirectShellStarter },
}

impl ShellStarterSource {
    #[cfg(any(test, feature = "test-util"))]
    pub fn shell_type(&self) -> ShellType {
        match self {
            Self::Override(starter) => starter.shell_type(),
            Self::Environment(starter) => starter.shell_type(),
            Self::UserDefault(starter) => starter.shell_type(),
            Self::Fallback { starter, .. } => starter.shell_type(),
        }
    }

    pub fn name(&self) -> ShellName {
        let starter = match self {
            Self::Override(starter)
            | Self::Environment(starter)
            | Self::UserDefault(starter)
            | Self::Fallback { starter } => starter,
        };
        ShellName::MoreDescriptive(starter.shell_type().name().to_owned())
    }
}

impl From<ShellStarterSource> for DirectShellStarter {
    fn from(value: ShellStarterSource) -> Self {
        match value {
            ShellStarterSource::Override(starter)
            | ShellStarterSource::Environment(starter)
            | ShellStarterSource::UserDefault(starter)
            | ShellStarterSource::Fallback { starter } => starter,
        }
    }
}

impl DirectShellStarter {
    #[cfg(any(test, feature = "test-util"))]
    pub fn new_for_test(shell_type: ShellType, shell_path: PathBuf, args: Vec<OsString>) -> Self {
        Self {
            shell_type,
            shell_path,
            args,
            session_id: generate_session_id(),
        }
    }

    pub fn shell_path(&self) -> &Path {
        &self.shell_path
    }

    /// Returns the logical path to the shell binary referred to by this `ShellStarter's`
    /// `ShellPath`.
    pub fn logical_shell_path(&self) -> &Path {
        self.shell_path.as_ref()
    }

    pub fn shell_type(&self) -> ShellType {
        self.shell_type
    }

    pub fn args(&self) -> &Vec<OsString> {
        &self.args
    }

    /// Returns the client-generated session ID for this shell bootstrap.
    pub fn session_id(&self) -> SessionId {
        self.session_id
    }
}

/// If the given `path_or_command` resolves to a supported shell binary, returns a tuple
/// containing the resolved path to the binary and the corresponding `ShellType`. Else, returns
/// None.
pub fn supported_shell_path_and_type(path_or_command: &str) -> Option<(PathBuf, ShellType)> {
    resolve_executable(path_or_command)
        .and_then(|resolved_path| parse_shell_type_from_path(resolved_path.as_ref()))
}

/// If the given `path` is a supported shell binary, returns a tuple containing
/// the path and the corresponding `ShellType`. This function does not validate
/// that the path exists or is executable.
fn parse_shell_type_from_path(path: &Path) -> Option<(PathBuf, ShellType)> {
    path.file_name()
        .and_then(|file_name| file_name.to_str().and_then(ShellType::from_name))
        .map(|shell_type| (path.to_path_buf(), shell_type))
}

fn arguments_for_session_spawning_command(
    resolved_shell_path: &str,
    shell_type: ShellType,
    session_id: SessionId,
) -> Vec<OsString> {
    // Note we typically go through bash so that we can launch the user's shell
    // with a leading '-', making it a login shell.
    match shell_type {
        ShellType::Zsh => {
            // The --no-rcs option executes the minimal level of startup files so we can
            // take over. The one exception: "Commands are first read from /etc/zshenv; this cannot be overridden."
            // The -g option sets the HIST_IGNORE_SPACE option, which ignores a command from history if it
            // begins with a space. We use this to hide Warp bootstrap commands from the history.
            vec![
                "-c".to_owned().into(),
                format!("exec -a -zsh '{resolved_shell_path}' -g --no-rcs").into(),
            ]
        }
        ShellType::Bash => {
            /*
             * There are many layers of bash happening here
             * 1. We pass the command we want to be running to bash -c to ensure the shell
             * is interpreting the arguments, rather than passing literal strings
             * 2. Make a call to exec when we launch the subshell. From FreeBSD porter's
             * handbook:  "The exec statement replaces the shell process with the
             * specified program. If exec is omitted, the shell process remains
             * in memory while the program is executing, and needlessly consumes system resources."
             * 3. The rcfile option reads the startup script from a file
             * 4. Process substitution i.e. <() send the output of a process via
             * /dev/fd/<n> (or temp files if this is unavailable) to another process
             * 5. Send an InitShell message to Warp through escape sequences.
             * The warp_send_message function is inlined here.
             * 6. We disable PS2 and the line editor to work around a gnarly bug involving
             * garbage being inserted in every line. We further disable PS1 and echo'ing
             * in order to show nothing to the user when we input characters. We later
             * restore the echo'ing in the bootstrap script.
             *
             * TODO(zheng) Add error handling
             */
            vec![
                "-c".to_owned().into(),
                // Keep this command up-to-date with the one in the bootstrap script
                // Notice the first level of escaping is the double-brackets in the macro string {{}}
                format!(
                    r#"exec -a bash '{}' --rcfile <(echo '{}')"#,
                    resolved_shell_path,
                    init_shell_script_for_shell(ShellType::Bash, &crate::ASSETS, session_id)
                )
                .into(),
            ]
        }
        ShellType::Fish => {
            // For now, we are going to plug the init cmd into single quotes.
            // Note it contains single quotes and there is no way to escape a single quote,
            // so instead we exit single quotes, emit an (escaped) quote, and re-enter them.
            //
            // TODO: we should eventually refactor this and build the init cmd up so that
            // we don't need to do complicated escaping.
            // We should also probably store the hex encoded json as a static string
            // rather than computing it at runtime for each shell we start.
            vec![
                // fish sources configuration files whenever it's invoked,
                // including in non-interactive mode (i.e. '-c'). This differs
                // from other shells like zsh, so we have to explicitly tell fish
                // to not source config files.
                //
                // There's an open GH issue against fish contesting this behaviour:
                // https://github.com/fish-shell/fish-shell/issues/5394.
                "--no-config".to_owned().into(),
                "-c".to_owned().into(),
                format!(
                    // We do _not_ specify `--no-config` here because
                    // we want fish to source config files for us (we don't
                    // manually do so in the bootstrap script like we do for zsh, for example).
                    // `-f no-mark-prompt` disables OSC 133 (the non-standard FinalTerm escape codes).
                    // Fish's implementation of this breaks Warp by emitting `OSC 133 A` but not
                    // `OSC 133 B` afterwards, which we have assumed. This is a temporary workaround.
                    r#"exec '{}' -f no-mark-prompt --login --init-command '{}'"#,
                    resolved_shell_path,
                    init_shell_script_for_shell(ShellType::Fish, &crate::ASSETS, session_id)
                )
                .into(),
            ]
        }
        ShellType::PowerShell => {
            vec![
                // When PowerShell starts a session, it writes "PowerShell <version>" to the PTY. This
                // option suppresses that message.
                "-NoLogo".to_owned().into(),
                // Skip RC files. We load these manually later.
                "-NoProfile".to_owned().into(),
                // Normally, passing the "-Command" option causes the shell to exit after executing
                // those commands. Passing "-NoExit" suppresses that so PowerShell remains interactive
                // afterwards.
                "-NoExit".to_owned().into(),
                // This arg must be last, as everything positioned after the "-Command" flag is treated
                // as the value for this arg.
                "-Command".to_owned().into(),
                init_shell_script_for_shell(ShellType::PowerShell, &crate::ASSETS, session_id)
                    .into(),
            ]
        }
    }
}

pub fn ssh_socket_dir() -> String {
    let mut socket_dir = if ChannelState::channel() == Channel::Integration {
        std::env::var("ORIGINAL_HOME").unwrap_or("~".into())
    } else {
        "~".into()
    };
    socket_dir.push_str("/.ssh");
    socket_dir
}

#[cfg(test)]
#[path = "shell_tests.rs"]
mod tests;
