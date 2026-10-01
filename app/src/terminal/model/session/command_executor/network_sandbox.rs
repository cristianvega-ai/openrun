//! OS-level network denial for the subprocesses of local command executors.
//!
//! Completion generators run automatically while the user types, so a tool that goes online by
//! itself must not be able to. The offline environment table (`offline_environment.rs`) switches
//! off the implicit network use of the tools it knows; this layer denies the network to whatever
//! it does not know, in the kernel:
//!
//! * macOS: the command runs under `sandbox-exec` with a profile that denies every IP
//!   connection (loopback included) and keeps Unix sockets. The profile also closes the two
//!   ways a sandboxed process can still have the system talk for it: DNS (`mDNSResponder` answers
//!   a lookup by querying the network, which was verified to leak the looked-up name) and
//!   background `NSURLSession` transfers (`nsurlsessiond` makes the request, which was verified
//!   to reach a loopback canary from inside the sandbox).
//! * Linux: a seccomp filter installed between `fork` and `exec` makes `socket(2)` fail for every
//!   address family except `AF_UNIX` and `AF_NETLINK`, and denies `io_uring_setup(2)`, which
//!   could open sockets without `socket(2)`. Filters survive `exec` and are inherited by every
//!   child.
//! * Other platforms: there is no unprivileged sandbox. Executors report that the network is not
//!   isolated and the generator policy keeps network-capable generators off.
//!
//! Applying the sandbox fails closed: if it cannot be applied the command is not run.
//!
//! Limits, stated plainly: this stops tools that go online by themselves, it is not a boundary
//! against hostile code. Unix sockets stay allowed, so a local daemon that makes network requests
//! for its client (a container engine pulling an image, an SSH control master) is not stopped.
//! File access is unchanged, and the macOS profile is a deny list for the delegation paths
//! named above, not an exhaustive list of every system service.

#[cfg(any(target_os = "macos", target_os = "linux"))]
use anyhow::Result;
#[cfg(any(target_os = "macos", target_os = "linux"))]
use command::r#async::Command;

/// Whether a local executor denies the network to its subprocesses.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum NetworkSandbox {
    /// Subprocesses run sandboxed or not at all.
    Enforced,
    /// There is no sandbox on this platform; subprocesses run as before.
    Unavailable,
    /// Tests of the other layers: subprocesses run unsandboxed.
    #[cfg(test)]
    Off,
    /// Tests of the fail-closed path: use this macOS tool path instead of `/usr/bin/sandbox-exec`.
    #[cfg(all(test, target_os = "macos"))]
    EnforcedWithTool(std::path::PathBuf),
    /// Tests of the fail-closed path: the Linux hook that installs the filter fails.
    #[cfg(all(test, target_os = "linux"))]
    FailingForTest,
}

impl NetworkSandbox {
    pub const fn platform_default() -> Self {
        if cfg!(any(target_os = "macos", target_os = "linux")) {
            Self::Enforced
        } else {
            Self::Unavailable
        }
    }

    /// Whether commands run through this executor cannot reach an IP network.
    pub fn isolates_network(&self) -> bool {
        match self {
            Self::Enforced => cfg!(any(target_os = "macos", target_os = "linux")),
            Self::Unavailable => false,
            #[cfg(test)]
            Self::Off => false,
            #[cfg(all(test, target_os = "macos"))]
            Self::EnforcedWithTool(_) => true,
            #[cfg(all(test, target_os = "linux"))]
            Self::FailingForTest => true,
        }
    }
}

impl NetworkSandbox {
    #[cfg(any(target_os = "macos", target_os = "linux"))]
    fn is_enforced(&self) -> bool {
        match self {
            Self::Enforced => true,
            Self::Unavailable => false,
            #[cfg(test)]
            Self::Off => false,
            #[cfg(all(test, target_os = "macos"))]
            Self::EnforcedWithTool(_) => true,
            #[cfg(all(test, target_os = "linux"))]
            Self::FailingForTest => true,
        }
    }
}

/// Creates the command that runs `program` in a new process group, inside the network sandbox
/// when `sandbox` asks for it. Fails when the sandbox is required and cannot be set up.
pub fn command_for(
    sandbox: &NetworkSandbox,
    program: &str,
) -> anyhow::Result<command::r#async::Command> {
    #[cfg(any(target_os = "macos", target_os = "linux"))]
    if sandbox.is_enforced() {
        return sandboxed_command(sandbox, program);
    }
    let _ = sandbox;
    Ok(command::r#async::Command::new_with_process_group(program))
}

/// The macOS sandbox tool.
#[cfg(target_os = "macos")]
pub const SANDBOX_EXEC: &str = "/usr/bin/sandbox-exec";

/// The sandbox profile. Later rules win in the sandbox profile language.
#[cfg(any(target_os = "macos", test))]
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
#[cfg(target_os = "macos")]
pub fn sandboxed_command(sandbox: &NetworkSandbox, shell_program: &str) -> Result<Command> {
    use anyhow::anyhow;

    let tool = match sandbox {
        #[cfg(all(test, target_os = "macos"))]
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

/// Builds the command that runs `shell_program` with the network denied. The caller adds the
/// shell's arguments. Fails when the sandbox cannot be set up, which means the command must not
/// run.
#[cfg(target_os = "linux")]
pub fn sandboxed_command(sandbox: &NetworkSandbox, shell_program: &str) -> Result<Command> {
    #[cfg(test)]
    if matches!(sandbox, NetworkSandbox::FailingForTest) {
        // SAFETY: the closure only returns an error.
        return Ok(unsafe {
            Command::new_with_process_group_and_pre_exec(shell_program, || {
                Err(std::io::Error::from_raw_os_error(libc::ENOSYS))
            })
        });
    }
    let _ = sandbox;
    let program = seccomp::filter_for_this_architecture()?;
    // SAFETY: the closure only calls `prctl` and `seccomp`, both async-signal-safe, on a program
    // that was built before the fork and is not modified.
    let command = unsafe {
        Command::new_with_process_group_and_pre_exec(shell_program, move || {
            seccomp::install(&program)
        })
    };
    Ok(command)
}

/// The classic-BPF program for the Linux filter. Pure data, so its logic is tested on every
/// platform with a small interpreter.
#[cfg(any(target_os = "linux", test))]
pub mod seccomp {
    #[cfg(target_os = "linux")]
    use anyhow::Result;

    /// `struct sock_filter`.
    #[repr(C)]
    #[derive(Clone, Copy, Debug, PartialEq, Eq)]
    pub struct SockFilter {
        pub code: u16,
        pub jt: u8,
        pub jf: u8,
        pub k: u32,
    }

    const BPF_LD_W_ABS: u16 = 0x20;
    const BPF_JMP_JEQ_K: u16 = 0x15;
    const BPF_JMP_JGE_K: u16 = 0x35;
    const BPF_RET_K: u16 = 0x06;

    const SECCOMP_RET_KILL_PROCESS: u32 = 0x8000_0000;
    const SECCOMP_RET_ERRNO: u32 = 0x0005_0000;
    const SECCOMP_RET_ALLOW: u32 = 0x7fff_0000;
    const EPERM: u32 = 1;

    const OFFSET_NR: u32 = 0;
    const OFFSET_ARCH: u32 = 4;
    const OFFSET_ARG0: u32 = 16;

    pub const AF_UNIX: u32 = 1;
    pub const AF_NETLINK: u32 = 16;

    /// What differs between the architectures the filter supports.
    #[derive(Clone, Copy, Debug)]
    pub struct Architecture {
        pub audit_arch: u32,
        pub nr_socket: u32,
        pub nr_io_uring_setup: u32,
        /// Syscall numbers at or above this value are an alternate ABI (x32) the filter does not
        /// model, so they are denied outright.
        pub alternate_abi_floor: Option<u32>,
    }

    #[allow(dead_code)] // only one of the two is used on a given target
    pub const X86_64: Architecture = Architecture {
        audit_arch: 0xC000_003E,
        nr_socket: 41,
        nr_io_uring_setup: 425,
        alternate_abi_floor: Some(0x4000_0000),
    };

    #[allow(dead_code)] // only one of the two is used on a given target
    pub const AARCH64: Architecture = Architecture {
        audit_arch: 0xC000_00B7,
        nr_socket: 198,
        nr_io_uring_setup: 425,
        alternate_abi_floor: None,
    };

    /// Where a jump goes.
    #[derive(Clone, Copy)]
    enum Label {
        Next,
        Check,
        Deny,
        Allow,
        Kill,
    }

    enum Op {
        Load(u32),
        JumpIfEqual(u32, Label, Label),
        JumpIfAtLeast(u32, Label, Label),
        Return(u32),
    }

    /// Returns the program for `arch`.
    ///
    /// * wrong architecture (a 32-bit process on a 64-bit kernel): kill;
    /// * `io_uring_setup`: `EPERM`;
    /// * `socket`: allowed for `AF_UNIX` and `AF_NETLINK`, `EPERM` for every other family;
    /// * everything else: allowed.
    pub fn program(arch: Architecture) -> Vec<SockFilter> {
        let mut ops = vec![
            Op::Load(OFFSET_ARCH),
            Op::JumpIfEqual(arch.audit_arch, Label::Next, Label::Kill),
            Op::Load(OFFSET_NR),
        ];
        if let Some(floor) = arch.alternate_abi_floor {
            ops.push(Op::JumpIfAtLeast(floor, Label::Deny, Label::Next));
        }
        ops.push(Op::JumpIfEqual(
            arch.nr_io_uring_setup,
            Label::Deny,
            Label::Next,
        ));
        ops.push(Op::JumpIfEqual(arch.nr_socket, Label::Check, Label::Allow));
        let check = ops.len();
        ops.push(Op::Load(OFFSET_ARG0));
        ops.push(Op::JumpIfEqual(AF_UNIX, Label::Allow, Label::Next));
        ops.push(Op::JumpIfEqual(AF_NETLINK, Label::Allow, Label::Next));
        let deny = ops.len();
        ops.push(Op::Return(SECCOMP_RET_ERRNO | EPERM));
        let allow = ops.len();
        ops.push(Op::Return(SECCOMP_RET_ALLOW));
        let kill = ops.len();
        ops.push(Op::Return(SECCOMP_RET_KILL_PROCESS));

        let target = |label: Label, from: usize| -> usize {
            match label {
                Label::Next => from + 1,
                Label::Check => check,
                Label::Deny => deny,
                Label::Allow => allow,
                Label::Kill => kill,
            }
        };
        let offset = |label: Label, from: usize| -> u8 {
            u8::try_from(target(label, from) - (from + 1)).expect("jump fits a BPF offset")
        };
        ops.iter()
            .enumerate()
            .map(|(index, op)| match *op {
                Op::Load(k) => SockFilter {
                    code: BPF_LD_W_ABS,
                    jt: 0,
                    jf: 0,
                    k,
                },
                Op::JumpIfEqual(k, then, otherwise) => SockFilter {
                    code: BPF_JMP_JEQ_K,
                    jt: offset(then, index),
                    jf: offset(otherwise, index),
                    k,
                },
                Op::JumpIfAtLeast(k, then, otherwise) => SockFilter {
                    code: BPF_JMP_JGE_K,
                    jt: offset(then, index),
                    jf: offset(otherwise, index),
                    k,
                },
                Op::Return(k) => SockFilter {
                    code: BPF_RET_K,
                    jt: 0,
                    jf: 0,
                    k,
                },
            })
            .collect()
    }

    /// What the kernel does with a system call.
    #[cfg(test)]
    #[derive(Debug, PartialEq, Eq)]
    pub enum Verdict {
        Allow,
        Errno(u32),
        Kill,
    }

    /// Runs `program` the way the kernel's classic-BPF interpreter would, for a system call with
    /// the given architecture, number and first argument.
    #[cfg(test)]
    pub fn run(program: &[SockFilter], audit_arch: u32, nr: u32, arg0: u64) -> Verdict {
        let load = |offset: u32| -> u32 {
            match offset {
                OFFSET_NR => nr,
                OFFSET_ARCH => audit_arch,
                OFFSET_ARG0 => arg0 as u32,
                other => panic!("filter read unexpected offset {other}"),
            }
        };
        let mut accumulator = 0u32;
        let mut pc = 0usize;
        loop {
            let instruction = program[pc];
            pc += 1;
            match instruction.code {
                BPF_LD_W_ABS => accumulator = load(instruction.k),
                BPF_JMP_JEQ_K => {
                    pc += usize::from(if accumulator == instruction.k {
                        instruction.jt
                    } else {
                        instruction.jf
                    });
                }
                BPF_JMP_JGE_K => {
                    pc += usize::from(if accumulator >= instruction.k {
                        instruction.jt
                    } else {
                        instruction.jf
                    });
                }
                BPF_RET_K => {
                    return match instruction.k {
                        SECCOMP_RET_ALLOW => Verdict::Allow,
                        SECCOMP_RET_KILL_PROCESS => Verdict::Kill,
                        k if k & 0xffff_0000 == SECCOMP_RET_ERRNO => Verdict::Errno(k & 0xffff),
                        other => panic!("unexpected return value {other:#x}"),
                    };
                }
                other => panic!("unexpected opcode {other:#x}"),
            }
        }
    }

    /// The program for the architecture this binary was built for. Fails on any other, so a
    /// build for an architecture without a verified filter cannot run unsandboxed.
    #[cfg(target_os = "linux")]
    pub fn filter_for_this_architecture() -> Result<Vec<SockFilter>> {
        #[cfg(target_arch = "x86_64")]
        {
            Ok(program(X86_64))
        }
        #[cfg(target_arch = "aarch64")]
        {
            Ok(program(AARCH64))
        }
        #[cfg(not(any(target_arch = "x86_64", target_arch = "aarch64")))]
        {
            Err(anyhow::anyhow!(
                "no network sandbox for this CPU architecture; refusing to run completion commands"
            ))
        }
    }

    /// Installs `program` on the calling thread, from where every `exec` and child inherits it.
    /// Called between `fork` and `exec`, so it makes only system calls.
    #[cfg(target_os = "linux")]
    pub fn install(program: &[SockFilter]) -> std::io::Result<()> {
        const PR_SET_NO_NEW_PRIVS: libc::c_int = 38;
        const PR_SET_SECCOMP: libc::c_int = 22;
        const SECCOMP_MODE_FILTER: libc::c_ulong = 2;

        // Required for an unprivileged process to install a filter; also makes setuid programs
        // run without their extra privileges, which a completion command never needs.
        // SAFETY: plain `prctl` call with integer arguments.
        if unsafe { libc::prctl(PR_SET_NO_NEW_PRIVS, 1 as libc::c_ulong, 0, 0, 0) } != 0 {
            return Err(std::io::Error::last_os_error());
        }
        let length = u16::try_from(program.len())
            .map_err(|_| std::io::Error::from(std::io::ErrorKind::InvalidInput))?;
        let descriptor = libc::sock_fprog {
            len: length,
            filter: program.as_ptr() as *mut libc::sock_filter,
        };
        // SAFETY: `descriptor` points at `program`, which outlives the call, and `SockFilter`
        // has the layout of `sock_filter` (checked by a test).
        if unsafe {
            libc::prctl(
                PR_SET_SECCOMP,
                SECCOMP_MODE_FILTER,
                &descriptor as *const libc::sock_fprog,
                0,
                0,
            )
        } != 0
        {
            return Err(std::io::Error::last_os_error());
        }
        Ok(())
    }
}

#[cfg(test)]
#[path = "network_sandbox_tests.rs"]
mod tests;
