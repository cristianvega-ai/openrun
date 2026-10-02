//! OS-level network denial for the subprocesses of local command executors.
//!
//! Completion generators run automatically while the user types, so a tool that goes online by
//! itself must not be able to. The offline environment table (`offline_environment.rs`) switches
//! off the implicit network use of the tools it knows; this layer denies the network to whatever
//! it does not know, in the kernel:
//!
//! The command runs under `sandbox-exec` with a profile that denies every IP connection
//! (loopback included) and keeps Unix sockets. The profile also closes the two ways a sandboxed
//! process can still have the system talk for it: DNS (`mDNSResponder` answers a lookup by
//! querying the network, which was verified to leak the looked-up name) and background
//! `NSURLSession` transfers (`nsurlsessiond` makes the request, which was verified to reach a
//! loopback canary from inside the sandbox).
//!
//! Applying the sandbox fails closed: if it cannot be applied the command is not run.
//!
//! Limits, stated plainly: this stops tools that go online by themselves, it is not a boundary
//! against hostile code. Unix sockets stay allowed, so a local daemon that makes network requests
//! for its client (a container engine pulling an image, an SSH control master) is not stopped.
//! File access is unchanged, and the macOS profile is a deny list for the delegation paths
//! named above, not an exhaustive list of every system service.

use anyhow::Result;
use command::r#async::Command;

/// Whether a local executor denies the network to its subprocesses.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum NetworkSandbox {
    /// Subprocesses run sandboxed or not at all.
    Enforced,
    /// Subprocesses run as before, without a sandbox.
    Unavailable,
    /// Tests of the other layers: subprocesses run unsandboxed.
    #[cfg(test)]
    Off,
    /// Tests of the fail-closed path: use this macOS tool path instead of `/usr/bin/sandbox-exec`.
    #[cfg(test)]
    EnforcedWithTool(std::path::PathBuf),
}

impl NetworkSandbox {
    pub const fn platform_default() -> Self {
        Self::Enforced
    }

    /// Whether commands run through this executor cannot reach an IP network.
    pub fn isolates_network(&self) -> bool {
        match self {
            Self::Enforced => true,
            Self::Unavailable => false,
            #[cfg(test)]
            Self::Off => false,
            #[cfg(test)]
            Self::EnforcedWithTool(_) => true,
        }
    }
}

impl NetworkSandbox {
    fn is_enforced(&self) -> bool {
        match self {
            Self::Enforced => true,
            Self::Unavailable => false,
            #[cfg(test)]
            Self::Off => false,
            #[cfg(test)]
            Self::EnforcedWithTool(_) => true,
        }
    }
}

/// Creates the command that runs `program` in a new process group, inside the network sandbox
/// when `sandbox` asks for it. Fails when the sandbox is required and cannot be set up.
pub fn command_for(
    sandbox: &NetworkSandbox,
    program: &str,
) -> anyhow::Result<command::r#async::Command> {
    if sandbox.is_enforced() {
        return sandboxed_command(sandbox, program);
    }
    Ok(command::r#async::Command::new_with_process_group(program))
}

/// When set in a test or integration-test build, the process tree already runs under a profile
/// that denies the network (see `sandboxed_command`).
#[cfg(any(test, feature = "integration_tests"))]
const OUTER_SANDBOX_VARIABLE: &str = "WARP_NETWORK_SANDBOX_BY_PARENT";

/// The macOS sandbox tool.
pub const SANDBOX_EXEC: &str = "/usr/bin/sandbox-exec";

/// The sandbox profile. Later rules win in the sandbox profile language.
pub const MACOS_PROFILE: &str = r#"(version 1)
(allow default)
(deny network* (remote ip))
(allow network* (remote unix-socket))
(deny network-outbound (literal "/private/var/run/mDNSResponder") (literal "/var/run/mDNSResponder"))
(deny mach-lookup (global-name "com.apple.dnssd.service") (global-name-prefix "com.apple.nsurlsessiond"))
"#;

/// Builds the command that runs `shell_program` with the network denied. The caller adds the
/// shell's arguments. Fails when the sandbox cannot be set up, which means the command must not
/// run.
pub fn sandboxed_command(sandbox: &NetworkSandbox, shell_program: &str) -> Result<Command> {
    use anyhow::anyhow;

    // The offline proof runs the whole test process tree under one `sandbox-exec` profile
    // (script/offline_sandbox_macos), and a sandboxed process cannot apply a second profile
    // (`sandbox_apply` fails with EPERM, the kernel reports `forbidden-sandbox-reinit`). The
    // profile of the proof denies the same accesses, so the commands run directly in it. The
    // switch exists only in test and integration-test builds; a release build always sandboxes.
    #[cfg(any(test, feature = "integration_tests"))]
    if matches!(sandbox, NetworkSandbox::Enforced)
        && std::env::var_os(OUTER_SANDBOX_VARIABLE).is_some()
    {
        return Ok(Command::new_with_process_group(shell_program));
    }
    let tool = match sandbox {
        #[cfg(test)]
        NetworkSandbox::EnforcedWithTool(path) => path.as_path(),
        _ => std::path::Path::new(SANDBOX_EXEC),
    };
    if !tool.is_file() {
        return Err(anyhow!(
            "refusing to run a completion command without its network sandbox: {} is missing",
            tool.display()
        ));
    }
    let mut command = Command::new_with_process_group(tool);
    command.arg("-p").arg(MACOS_PROFILE).arg(shell_program);
    Ok(command)
}

#[cfg(test)]
#[path = "network_sandbox_tests.rs"]
mod tests;
