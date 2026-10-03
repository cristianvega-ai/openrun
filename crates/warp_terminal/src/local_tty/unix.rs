// The code in this file is adapted from the alacritty_terminal crate under the
// Apache license; see: crates/warp_terminal/src/model/LICENSE-ALACRITTY.

//! TTY related functionality.
use std::collections::HashMap;
use std::ffi::OsString;
use std::fs::File;
use std::mem::MaybeUninit;
use std::os::unix::io::{AsRawFd, FromRawFd, RawFd};
use std::path::PathBuf;
use std::{io, ptr};

use anyhow::{Context as _, Result};
use command::blocking::Command;
use itertools::Itertools;
use libc::{self, TIOCSCTTY, c_int, winsize};
use mio::Interest;
use mio::unix::SourceFd;
use nix::pty::openpty;
use nix::sys::termios::{self, InputFlags, SetArg};
use serde::{Deserialize, Serialize};
use signal_hook_mio::v1_0::Signals;
use warp_core::channel::ChannelState;
use warp_core::cli_agent_protocol::{
    CLI_AGENT_PROTOCOL_VERSION, WARP_CLI_AGENT_PROTOCOL_VERSION_ENV, WARP_CLIENT_VERSION_ENV,
};
use warp_core::safe_error;
use warp_errors::report_if_error;
use warpui_core::{AppContext, SingletonEntity};

use super::event_loop::{PTY_TOKEN, SIGNALS_TOKEN};
use super::spawner::{PtyHandle, PtySpawnInfo, PtySpawner};
use super::{ChildEvent, EventedPty, EventedReadWrite, PtyOptions, SizeInfo};
use crate::local_tty::shell::{DirectShellStarter, extra_path_entries, ssh_socket_dir};
use crate::shell::ShellType;

const BASH_HISTORY_SIZE_SENTINEL: &str = "57265949261";

/// Get raw fds for leader/follower ends of a new PTY.
fn make_pty(size: winsize) -> Result<(RawFd, RawFd)> {
    let mut win_size = size;
    win_size.ws_xpixel = 0;
    win_size.ws_ypixel = 0;

    let ends = openpty(Some(&win_size), None).context("openpty failed")?;
    // Configure the two new file descriptors to be closed on exec.  This keeps
    // us from leaking tty fds into spawned shells.  FD_CLOEXEC is _not_ shared
    // across duplicated fds, so when we call `libc::dup2()` below, those fds
    // will _not_ be closed when we exec the shell.
    unsafe {
        libc::fcntl(ends.master, libc::F_SETFD, libc::FD_CLOEXEC);
        libc::fcntl(ends.slave, libc::F_SETFD, libc::FD_CLOEXEC);
    }

    Ok((ends.master, ends.slave))
}

/// The current user's password-database record, resolved for shell/session
/// setup. Fields are owned so the record outlives any transient lookup buffer.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct CurrentUser {
    pub(super) name: String,
    pub(super) dir: String,
    pub(super) shell: String,
}

/// Resolves the current uid's passwd record for shell/session setup with an in-process passwd
/// lookup (`getpwuid_r`, via nix's safe [`nix::unistd::User::from_uid`] wrapper), which resolves
/// directory-service users on macOS too.
///
/// Returns `None` if there is no record; callers then fall back to the ambient environment
/// (`$HOME`/`$USER`) or built-in shell defaults.
pub(super) fn resolve_current_user() -> Option<CurrentUser> {
    let uid = nix::unistd::getuid();
    match nix::unistd::User::from_uid(uid) {
        Ok(Some(user)) => Some(CurrentUser {
            name: user.name,
            dir: user.dir.to_string_lossy().into_owned(),
            shell: user.shell.to_string_lossy().into_owned(),
        }),
        Ok(None) => None,
        Err(err) => {
            safe_error!(
                safe: ("passwd entry lookup failed for uid {uid}: {err}"),
                full: ("passwd entry lookup failed")
            );
            None
        }
    }
}

pub struct Pty {
    pty_handle: Box<dyn PtyHandle>,
    fd: File,
    token: mio::Token,
    signals: Signals,
    signals_token: mio::Token,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PtySpawnResult {
    pub pid: u32,
    pub leader_fd: i32,
}

pub(super) fn spawn(options: PtyOptions) -> Result<PtySpawnInfo> {
    let PtyOptions {
        size,
        window_id,
        shell_starter,
        start_dir,
        env_vars,
        enable_ssh_wrapper,
        reuse_ssh_control_master,
        shell_debug_mode,
        honor_ps1,
        node_version_chip_enabled,
        close_fds,
    } = options;
    let command = build_host_shell_command(
        shell_starter,
        window_id,
        env_vars,
        start_dir,
        enable_ssh_wrapper,
        reuse_ssh_control_master,
        shell_debug_mode,
        honor_ps1,
        node_version_chip_enabled,
    );

    spawn_command_in_pty(command, &size, close_fds)
}

/// Builds the `Command` for a host-shell PTY session: executable, args,
/// environment variables, and startup directory.
///
/// Does not perform any PTY-level setup; hand the returned `Command`
/// to [`spawn_command_in_pty`].
#[allow(clippy::too_many_arguments)]
fn build_host_shell_command(
    shell_starter: DirectShellStarter,
    window_id: Option<usize>,
    env_vars: HashMap<OsString, OsString>,
    start_dir: Option<PathBuf>,
    enable_ssh_wrapper: bool,
    reuse_ssh_control_master: bool,
    shell_debug_mode: bool,
    honor_ps1: bool,
    node_version_chip_enabled: bool,
) -> Command {
    let pw = resolve_current_user();

    log::info!(
        "Starting shell {}",
        shell_starter.logical_shell_path().display()
    );

    let mut builder = Command::new(shell_starter.logical_shell_path());
    for arg in shell_starter.args() {
        builder.arg(arg);
    }

    // Support an overridden home directory for integration tests, which
    // should execute in a more hermetic environment than one where the home
    // directory contains whatever happens to already exist there.
    let home_dir = std::env::var("HOME")
        .ok()
        .or_else(|| pw.as_ref().map(|pw| pw.dir.to_owned()))
        .unwrap_or_else(|| "/".to_owned());

    // Unfortunately process::Command has no facility for using the same fd for in/out/err.
    // The issue is that Stdio wants to close its fd. Previously we tried Stdio::from_raw_fd(follower)
    // for all 3 fds, and hoped that the error on close would be ignored.
    // Unfortunately this triggers a race: due to fd reuse the second and third
    // calls to close() might close a random fd. In practice this caused hangs
    // in the tests. Therefore we do NOT set stdin, stdout, stderr here; instead we
    // do it in the pre_exec hook.
    // Setup shell environment.
    if let Some(user_name) = pw
        .as_ref()
        .map(|pw| pw.name.to_owned())
        .or_else(|| std::env::var("USER").ok())
        .or_else(|| std::env::var("LOGNAME").ok())
    {
        builder.env("LOGNAME", &user_name);
        builder.env("USER", &user_name);
    }
    builder.env("HOME", &home_dir);

    // Specify terminal name and capabilities.
    builder.env("TERM", "xterm-256color");
    builder.env("TERM_PROGRAM", "WarpTerminal");
    // Advertise 24-bit color support.
    builder.env("COLORTERM", "truecolor");

    if let Some(version) = ChannelState::app_version() {
        builder.env("TERM_PROGRAM_VERSION", version);

        // We also insert this warp-specific version so that
        // plugins can do warp-specific version checks without worrying
        // that the version env var might be coming from a different terminal
        // (for ex., in the ssh case).
        builder.env(WARP_CLIENT_VERSION_ENV, version);
    } else {
        // Local builds don't have GIT_RELEASE_TAG, so app_version() is None.
        // Use "local" so plugins can still distinguish this from a missing value.
        builder.env(WARP_CLIENT_VERSION_ENV, "local");
    }

    // Set the `SHELL` environment variable to match the path of the shell we are using.
    // Traditionally, `$SHELL` is meant to match the user's default shell in the passwd database,
    // however we set it to the current shell that is to be `exec`ed. This behavior also matches
    // that of iTerm.
    builder.env("SHELL", shell_starter.logical_shell_path());

    if let Some(window_id) = window_id {
        builder.env("WINDOWID", format!("{window_id}"));
    }

    // Set whether or not we should utilize the SSH wrapper in this shell.
    if enable_ssh_wrapper {
        builder.env("WARP_USE_SSH_WRAPPER", "1");
    } else {
        builder.env("WARP_USE_SSH_WRAPPER", "0");
    }

    // Whether the SSH wrapper should attach to an existing ControlMaster
    // for the destination host instead of always creating its own.
    builder.env(
        "WARP_SSH_REUSE_CONTROL_MASTER",
        if reuse_ssh_control_master { "1" } else { "0" },
    );

    // For integration tests, put SSH control master sockets under the actual
    // home directory, as the length of the path to sockets placed in the
    // integration test home directory can exceed length limits.
    // See: https://stackoverflow.com/questions/35970686
    builder.env("SSH_SOCKET_DIR", ssh_socket_dir());

    // We currently don't support bootstrapping recursive SSH sessions so we will only run the SSH
    // logic if this flag is set.
    builder.env("WARP_IS_LOCAL_SHELL_SESSION", "1");

    // Advertise the protocol version so CLI agent plugins emit structured notifications.
    builder.env(
        WARP_CLI_AGENT_PROTOCOL_VERSION_ENV,
        CLI_AGENT_PROTOCOL_VERSION.to_string(),
    );

    if shell_debug_mode {
        builder.env("WARP_SHELL_DEBUG_MODE", "1");
    }
    if honor_ps1 {
        builder.env("WARP_HONOR_PS1", "1");
    } else {
        builder.env("WARP_HONOR_PS1", "0");
    }

    // Gate the shell's per-prompt `node --version` detection on whether the
    // Node.js Version chip is enabled. The bootstrap treats any value other than
    // "0" as enabled, so we only ever set "0" to disable it.
    builder.env(
        "WARP_PROMPT_NODE_VERSION_ENABLED",
        if node_version_chip_enabled { "1" } else { "0" },
    );

    // Pass through any additional entries to add to PATH.
    let path_append = extra_path_entries()
        .map(|p| p.to_string_lossy().into_owned())
        .join(":");
    builder.env("WARP_PATH_APPEND", path_append);

    if matches!(shell_starter.shell_type(), ShellType::Bash) {
        // Set initial very large values so bash imports the user's existing
        // history without truncating the file or in-memory list on startup.
        builder.env("HISTFILESIZE", BASH_HISTORY_SIZE_SENTINEL);
        builder.env("HISTSIZE", BASH_HISTORY_SIZE_SENTINEL);
        // Set second environment variables that we can use to know whether
        // the user rcfiles set these variables or not.
        builder.env("WARP_INITIAL_HISTFILESIZE", BASH_HISTORY_SIZE_SENTINEL);
        builder.env("WARP_INITIAL_HISTSIZE", BASH_HISTORY_SIZE_SENTINEL);
    }

    // Pass the desired initial working directory as an environment variable
    // and cd at the beginning of bootstrap.  We use this instead of
    // setting the process's initial working directory, as the spawn() will
    // fail if that directory doesn't exist.
    //
    // We could check the validity of the directory here, but that would be
    // a blocking filesystem call on the main thread, and the initial
    // directory could be on a network filesystem; deferring the `cd` to
    // shell bootstrap avoids that.
    if let Some(start_dir) = start_dir {
        builder.env("WARP_INITIAL_WORKING_DIR", start_dir);
    }

    // Apply any caller-provided environment overrides last, so they win.
    for (key, value) in env_vars {
        builder.env(key, value);
    }

    // Set the initial working directory to the user's home directory.  If
    // `start_dir` is Some, we'll attempt to cd to that directory at the
    // start of bootstrap.
    builder.current_dir(home_dir);

    builder
}

/// Wraps a fully-built `Command` in the PTY/`pre_exec` setup: creates the
/// pty pair, applies termios, installs the child process setup hook
/// (signals, stdio, controlling terminal, close_fds), and
/// spawns the command.
fn spawn_command_in_pty(
    mut command: Command,
    size: &SizeInfo,
    close_fds: bool,
) -> Result<PtySpawnInfo> {
    let (leader, follower) = make_pty(size.to_winsize())?;

    // Close the follower at the end of this function.
    // We need to keep it alive long enough for fork().
    let _file = unsafe { File::from_raw_fd(follower) };

    if let Ok(mut termios) = termios::tcgetattr(leader) {
        // Set character encoding to UTF-8.
        termios.input_flags.set(InputFlags::IUTF8, true);
        let _ = termios::tcsetattr(leader, SetArg::TCSANOW, &termios);
    }

    unsafe {
        let fdlimit = libc::sysconf(libc::_SC_OPEN_MAX) as i32;

        command.pre_exec(move || {
            // IMPORTANT: THIS FUNCTION IS RUN AFTER FORK.
            // It must only use async-safe functions. No allocating memory,
            // taking a lock, or anything like that.
            //
            // If any errors are encountered while preparing the child
            // process, we convert them from a platform-level error code to
            // a rust Error, and return that.  Internally, Command passes
            // the error code back to the parent process and exposes that
            // as the result of calling spawn().

            use self::utils::cvt;

            // Reset all signal handlers to their defaults.
            for signal in 1..32 {
                // SIGKILL and SIGSTOP cannot be modified, so skip them.
                if signal == libc::SIGKILL || signal == libc::SIGSTOP {
                    continue;
                }

                // Set the signal handler to the default and check for errors.
                if libc::signal(signal, libc::SIG_DFL) == libc::SIG_ERR {
                    return Err(std::io::Error::last_os_error());
                }
            }

            // Unmask (unblock) all signals.  We need to use MaybeUninit because
            // some platforms define `libc::sigset_t` as an integer type, and
            // others define it as a structure.  The only way we can safely
            // initialize it on all platforms is through `libc::sigemptyset()`.
            let mut signals: MaybeUninit<libc::sigset_t> = MaybeUninit::uninit();
            libc::sigemptyset(signals.as_mut_ptr());
            let signals: libc::sigset_t = signals.assume_init();
            libc::sigprocmask(libc::SIG_SETMASK, &signals, ptr::null_mut());

            // Set up stdin/stdout/stderr.
            cvt(libc::dup2(follower, libc::STDIN_FILENO))?;
            cvt(libc::dup2(follower, libc::STDOUT_FILENO))?;
            cvt(libc::dup2(follower, libc::STDERR_FILENO))?;

            // Create a new process group.
            cvt(libc::setsid())?;

            // Set the controlling terminal.
            // TIOSCTTY changes based on platform and the `ioctl` call is different
            // based on architecture (32/64). So a generic cast is used to make sure
            // there are no issues. To allow such a generic cast the clippy warning
            // is disabled.
            #[allow(clippy::cast_lossless)]
            cvt(libc::ioctl(follower, TIOCSCTTY as _, 0))?;

            // Close all other FDs to avoid leaking any other non-pty FDs
            // into the shell process.  Don't propagate up errors, as most
            // of these won't be active file descriptors, and attempting to
            // close() them produces EINVAL.
            if close_fds {
                for fd in 3..fdlimit {
                    libc::close(fd);
                }
            }

            Ok(())
        });
    }

    let spawned = command.spawn()?;
    Ok(PtySpawnInfo {
        result: PtySpawnResult {
            pid: spawned.id(),
            leader_fd: leader,
        },
        child: spawned,
    })
}

impl Pty {
    /// Create a new pty and return a handle to interact with it.
    pub fn new(options: PtyOptions, ctx: &mut AppContext) -> Result<Self> {
        let size = options.size;
        let shell = options.shell_starter.shell_type();

        // Prepare signal handling before spawning child.
        let signals = Signals::new([signal_hook::consts::SIGCHLD])
            .context("error preparing signal handling")?;

        let (PtySpawnResult { pid, leader_fd }, pty_handle) =
            PtySpawner::handle(ctx).update(ctx, |pty_spawner, _| pty_spawner.spawn_pty(options))?;

        log::info!(
            "Successfully spawned child {} process with pid {}",
            shell.name(),
            pid
        );

        let fd = unsafe {
            // Maybe this should be done outside of this function so nonblocking
            // isn't forced upon consumers. Although maybe it should be?
            set_nonblocking(leader_fd);

            File::from_raw_fd(leader_fd)
        };

        let mut pty = Pty {
            pty_handle,
            fd,
            token: PTY_TOKEN,
            signals,
            signals_token: SIGNALS_TOKEN,
        };
        pty.on_resize(&size);
        Ok(pty)
    }

    pub fn get_pid(&self) -> u32 {
        self.pty_handle.pid()
    }

    pub fn get_fd(&self) -> RawFd {
        self.fd.as_raw_fd()
    }
}

impl EventedReadWrite for Pty {
    type Reader = File;
    type Writer = File;

    #[inline]
    fn register(&mut self, poll: &mio::Poll, interest: mio::Interest) -> io::Result<()> {
        poll.registry()
            .register(&mut SourceFd(&self.fd.as_raw_fd()), self.token, interest)?;

        poll.registry()
            .register(&mut self.signals, self.signals_token, Interest::READABLE)
    }

    #[inline]
    fn reregister(&mut self, poll: &mio::Poll, interest: mio::Interest) -> io::Result<()> {
        poll.registry()
            .reregister(&mut SourceFd(&self.fd.as_raw_fd()), self.token, interest)?;

        poll.registry()
            .reregister(&mut self.signals, self.signals_token, Interest::READABLE)
    }

    #[inline]
    fn deregister(&mut self, poll: &mio::Poll) -> io::Result<()> {
        poll.registry()
            .deregister(&mut SourceFd(&self.fd.as_raw_fd()))?;
        poll.registry().deregister(&mut self.signals)
    }

    #[inline]
    fn reader(&mut self) -> &mut File {
        &mut self.fd
    }

    #[inline]
    fn read_token(&self) -> mio::Token {
        self.token
    }

    #[inline]
    fn writer(&mut self) -> &mut File {
        &mut self.fd
    }

    #[inline]
    fn write_token(&self) -> mio::Token {
        self.token
    }
}

impl EventedPty for Pty {
    #[inline]
    fn next_child_event(&mut self) -> Option<ChildEvent> {
        self.signals.pending().next().and_then(|signal| {
            if signal != signal_hook::consts::SIGCHLD {
                return None;
            }

            match self.pty_handle.has_process_terminated() {
                Ok(true) => Some(ChildEvent::Exited),
                Ok(false) => None,
                Err(e) => {
                    log::warn!("Error checking child process termination: {e:#}");
                    None
                }
            }
        })
    }

    #[inline]
    fn child_event_token(&self) -> mio::Token {
        self.signals_token
    }

    fn on_resize(&mut self, size: &SizeInfo) {
        let win = size.to_winsize();

        let res = unsafe { libc::ioctl(self.fd.as_raw_fd(), libc::TIOCSWINSZ, &win as *const _) };

        if res < 0 {
            panic!("ioctl TIOCSWINSZ failed: {}", io::Error::last_os_error());
        }
    }

    fn kill(mut self) -> Result<()> {
        // Note: on macOS if there is remaining data in the pty, the child process
        // may get stuck in an 'E' (trying to exit) state, and the wait will
        // hang. Closing the pty explicitly fixes it, though the reason is unclear;
        // it appears to be a kernel bug.
        std::mem::drop(self.fd);
        let result = self.pty_handle.kill();
        report_if_error!(result);
        result
    }
}

/// Types that can produce a `libc::winsize`.
pub trait ToWinsize {
    /// Get a `libc::winsize`.
    fn to_winsize(&self) -> winsize;
}

impl ToWinsize for &SizeInfo {
    fn to_winsize(&self) -> winsize {
        winsize {
            ws_row: self.rows as libc::c_ushort,
            ws_col: self.columns as libc::c_ushort,
            ws_xpixel: self.pane_width_px().as_f32() as libc::c_ushort,
            ws_ypixel: self.pane_height_px().as_f32() as libc::c_ushort,
        }
    }
}

unsafe fn set_nonblocking(fd: c_int) {
    unsafe {
        use libc::{F_GETFL, F_SETFL, O_NONBLOCK, fcntl};

        let res = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
        assert_eq!(res, 0);
    }
}

#[cfg(test)]
#[path = "unix_tests.rs"]
mod tests;

/// A set of platform helper utilities copied directly from std::sys.
///
/// See: https://github.com/rust-lang/rust/blob/master/library/std/src/sys/unix/mod.rs
mod utils {
    #[doc(hidden)]
    pub(super) trait IsMinusOne {
        fn is_minus_one(&self) -> bool;
    }

    macro_rules! impl_is_minus_one {
        ($($t:ident)*) => ($(impl IsMinusOne for $t {
            fn is_minus_one(&self) -> bool {
                *self == -1
            }
        })*)
    }

    impl_is_minus_one! { i8 i16 i32 i64 isize }

    /// Checks whether the provided value represents a platform-level error status
    /// and converts it into a [`Result`].
    pub(super) fn cvt<T: IsMinusOne>(t: T) -> std::io::Result<T> {
        if t.is_minus_one() {
            Err(std::io::Error::last_os_error())
        } else {
            Ok(t)
        }
    }
}

#[test]
fn resolve_current_user_returns_running_user() {
    // On the test host the current uid resolves via getpwuid_r, so this should
    // succeed and report a non-empty name.
    if let Some(user) = resolve_current_user() {
        assert!(!user.name.is_empty());
    }
}
