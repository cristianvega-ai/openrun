use super::seccomp::{
    self, AARCH64, AF_NETLINK, AF_UNIX, Architecture, SockFilter, Verdict, X86_64,
};
use super::*;

const EPERM: u32 = 1;

fn socket_verdict(arch: Architecture, family: u64) -> Verdict {
    seccomp::run(
        &seccomp::program(arch),
        arch.audit_arch,
        arch.nr_socket,
        family,
    )
}

#[test]
fn filter_has_the_layout_of_sock_filter() {
    assert_eq!(std::mem::size_of::<SockFilter>(), 8);
    assert_eq!(std::mem::align_of::<SockFilter>(), 4);
}

#[test]
fn socket_is_allowed_only_for_unix_and_netlink() {
    for arch in [X86_64, AARCH64] {
        assert_eq!(socket_verdict(arch, AF_UNIX.into()), Verdict::Allow);
        assert_eq!(socket_verdict(arch, AF_NETLINK.into()), Verdict::Allow);
        for (family, name) in [
            (0u64, "AF_UNSPEC"),
            (2, "AF_INET"),
            (10, "AF_INET6"),
            (17, "AF_PACKET"),
            (29, "AF_CAN"),
            (31, "AF_BLUETOOTH"),
            (38, "AF_ALG"),
            (40, "AF_VSOCK"),
            (44, "AF_XDP"),
            (45, "AF_MCTP"),
            (4096, "unknown"),
        ] {
            assert_eq!(
                socket_verdict(arch, family),
                Verdict::Errno(EPERM),
                "{name} on {:#x}",
                arch.audit_arch
            );
        }
    }
}

#[test]
fn only_the_low_word_of_the_family_argument_counts() {
    let arch = X86_64;
    // The kernel reads `socket`'s first argument as an `int`; junk in the upper half of the
    // register must neither hide an INET socket nor turn a UNIX one into a denial.
    assert_eq!(
        socket_verdict(arch, (1u64 << 32) | 2),
        Verdict::Errno(EPERM)
    );
    assert_eq!(
        socket_verdict(arch, 0xdead_beef_0000_0000 | u64::from(AF_UNIX)),
        Verdict::Allow
    );
}

#[test]
fn other_system_calls_are_allowed_and_io_uring_is_not() {
    for arch in [X86_64, AARCH64] {
        let program = seccomp::program(arch);
        for nr in [0u32, 1, 3, 42, 56, 59, 202, 231, 435] {
            if nr == arch.nr_socket || nr == arch.nr_io_uring_setup {
                continue;
            }
            assert_eq!(
                seccomp::run(&program, arch.audit_arch, nr, 2),
                Verdict::Allow,
                "syscall {nr}"
            );
        }
        assert_eq!(
            seccomp::run(&program, arch.audit_arch, arch.nr_io_uring_setup, 0),
            Verdict::Errno(EPERM)
        );
    }
}

#[test]
fn the_alternate_x32_abi_cannot_be_used_to_reach_socket() {
    let program = seccomp::program(X86_64);
    let x32_socket = 0x4000_0000 | X86_64.nr_socket;
    assert_eq!(
        seccomp::run(&program, X86_64.audit_arch, x32_socket, 2),
        Verdict::Errno(EPERM)
    );
    assert_eq!(
        seccomp::run(&program, X86_64.audit_arch, 0x4000_0000, 0),
        Verdict::Errno(EPERM)
    );
}

#[test]
fn a_foreign_architecture_is_killed() {
    // 32-bit x86 on a 64-bit kernel.
    let program = seccomp::program(X86_64);
    assert_eq!(
        seccomp::run(&program, 0x4000_0003, X86_64.nr_socket, 2),
        Verdict::Kill
    );
    let program = seccomp::program(AARCH64);
    assert_eq!(
        seccomp::run(&program, X86_64.audit_arch, AARCH64.nr_socket, 1),
        Verdict::Kill
    );
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
#[test]
fn x86_64_numbers_match_libc() {
    assert_eq!(X86_64.nr_socket as libc::c_long, libc::SYS_socket);
    assert_eq!(
        X86_64.nr_io_uring_setup as libc::c_long,
        libc::SYS_io_uring_setup
    );
    assert_eq!(AF_UNIX as libc::c_int, libc::AF_UNIX);
    assert_eq!(AF_NETLINK as libc::c_int, libc::AF_NETLINK);
}

#[cfg(all(target_os = "linux", target_arch = "aarch64"))]
#[test]
fn aarch64_numbers_match_libc() {
    assert_eq!(AARCH64.nr_socket as libc::c_long, libc::SYS_socket);
    assert_eq!(
        AARCH64.nr_io_uring_setup as libc::c_long,
        libc::SYS_io_uring_setup
    );
}

#[test]
fn only_unix_platforms_with_a_sandbox_report_isolation() {
    let default = NetworkSandbox::platform_default();
    assert_eq!(
        default.isolates_network(),
        cfg!(any(target_os = "macos", target_os = "linux"))
    );
    assert!(!NetworkSandbox::Unavailable.isolates_network());
    assert!(!NetworkSandbox::Off.isolates_network());
}

#[test]
fn macos_profile_denies_ip_dns_and_background_transfers() {
    for line in [
        "(deny network* (remote ip))",
        "(allow network* (remote unix-socket))",
        "/private/var/run/mDNSResponder",
        "com.apple.dnssd.service",
        "com.apple.nsurlsessiond",
    ] {
        assert!(MACOS_PROFILE.contains(line), "{line}");
    }
    // Later rules win, so the deny of the DNS socket has to come after the unix-socket allow.
    assert!(
        MACOS_PROFILE.find("(allow network* (remote unix-socket))")
            < MACOS_PROFILE.find("/private/var/run/mDNSResponder")
    );
}

/// Tests that need a unix machine to run real processes. They check, for the sandbox alone (the
/// environment table is switched off), that real tools cannot reach the loopback canary and that
/// ordinary local work still functions.
#[cfg(any(target_os = "macos", target_os = "linux"))]
mod sandboxed {
    use std::os::unix::net::UnixListener;

    use super::*;
    use crate::terminal::model::session::LocalCommandExecutor;
    use crate::terminal::model::session::command_executor::test_support::*;

    fn sandbox_only_executor() -> LocalCommandExecutor {
        production_executor().without_offline_environment()
    }

    fn assert_sandbox_keeps_silent(scenario: Scenario, canary: &Canary) {
        scenario.assert_control_reaches(canary);
        scenario.assert_silent_through(canary, sandbox_only_executor);
    }

    #[test]
    fn default_executor_reports_isolation() {
        use crate::terminal::model::session::CommandExecutor as _;
        assert!(production_executor().network_isolated());
    }

    #[test]
    fn rustup_cannot_download_a_toolchain() {
        let canary = Canary::start();
        let Some(scenario) = rustup_scenario(&canary) else {
            return;
        };
        assert_sandbox_keeps_silent(scenario, &canary);
    }

    #[test]
    fn npm_cannot_check_for_updates() {
        let canary = Canary::start();
        let Some(scenario) = npm_scenario(&canary) else {
            return;
        };
        assert_sandbox_keeps_silent(scenario, &canary);
    }

    #[test]
    fn corepack_cannot_download_a_package_manager() {
        let canary = Canary::start();
        let Some(scenario) = corepack_scenario(&canary) else {
            return;
        };
        assert_sandbox_keeps_silent(scenario, &canary);
    }

    #[test]
    fn docker_cannot_reach_a_remote_daemon() {
        let canary = Canary::start();
        for mut scenario in docker_scenarios(&canary) {
            scenario.commands = commands(&["docker ps -a --format '{{ json . }}'"]);
            assert_sandbox_keeps_silent(scenario, &canary);
        }
    }

    #[test]
    fn git_cannot_fetch_from_a_promisor_remote() {
        let canary = Canary::start();
        let Some(scenario) = git_lazy_fetch_scenario(&canary) else {
            return;
        };
        assert_sandbox_keeps_silent(scenario, &canary);
    }

    fn run_plain(command: &str, cwd: &std::path::Path) -> Ran {
        run_as_generator(
            sandbox_only_executor(),
            command,
            cwd,
            &system_path(),
            &base_environment(cwd),
        )
    }

    #[test]
    fn a_tcp_connection_to_loopback_is_refused() {
        let canary = Canary::start();
        let temp = tempfile::tempdir().unwrap();
        let connect = format!(
            "if exec 3<>/dev/tcp/127.0.0.1/{}; then echo connected; else echo refused; fi",
            canary.port()
        );
        let control = run_unprotected(
            &connect,
            temp.path(),
            &system_path(),
            &base_environment(temp.path()),
        );
        assert!(
            control.output.contains("connected"),
            "fixture is insensitive: {}",
            control.output
        );
        let ran = run_plain(&connect, temp.path());
        assert!(ran.output.contains("refused"), "{}", ran.output);
        assert!(!ran.output.contains("connected"), "{}", ran.output);
    }

    #[test]
    fn children_of_the_command_are_sandboxed_too() {
        let canary = Canary::start();
        let temp = tempfile::tempdir().unwrap();
        let connect = format!(
            "bash -c 'if exec 3<>/dev/tcp/127.0.0.1/{}; then echo connected; else echo refused; fi'",
            canary.port()
        );
        let ran = run_plain(&format!("sh -c \"{connect}\" | cat"), temp.path());
        assert!(ran.output.contains("refused"), "{}", ran.output);
    }

    #[test]
    fn unix_sockets_and_local_files_still_work() {
        let Some(python) = require_tool("python3") else {
            return;
        };
        let temp = tempfile::tempdir().unwrap();
        let socket_path = temp.path().join("daemon.sock");
        let listener = UnixListener::bind(&socket_path).unwrap();
        let accepter = std::thread::spawn(move || listener.accept().map(|_| ()));

        let ran = run_plain(
            &format!(
                "{} -c \"import socket; s = socket.socket(socket.AF_UNIX); \
                 s.connect('{}'); print('unix-ok')\"; \
                 echo data > written && cat written && pwd && git --version",
                python.display(),
                socket_path.display()
            ),
            temp.path(),
        );
        accepter.join().unwrap().unwrap();
        assert!(ran.success, "{}", ran.output);
        assert!(ran.output.contains("unix-ok"), "{}", ran.output);
        assert!(ran.output.contains("data"), "{}", ran.output);
        assert!(
            ran.output
                .contains(temp.path().file_name().unwrap().to_str().unwrap()),
            "the working directory is kept: {}",
            ran.output
        );
    }

    #[test]
    fn a_failing_setup_runs_nothing() {
        // The pre-exec hook of the Linux sandbox and the missing tool of the macOS one both end in
        // an error from the executor, never in a command that ran without the sandbox.
        let temp = tempfile::tempdir().unwrap();
        let marker = temp.path().join("ran");
        let command = format!("touch '{}'", marker.display());
        let result =
            futures_lite::future::block_on(sandbox_failing_executor().execute_local_command(
                &command,
                temp.path().to_str(),
                None,
                Default::default(),
            ));
        assert!(result.is_err(), "the command ran or reported success");
        assert!(!marker.exists(), "the command ran without its sandbox");
    }

    #[cfg(target_os = "macos")]
    fn sandbox_failing_executor() -> LocalCommandExecutor {
        production_executor().with_network_sandbox(NetworkSandbox::EnforcedWithTool(
            "/nonexistent/sandbox-exec".into(),
        ))
    }

    #[cfg(target_os = "linux")]
    fn sandbox_failing_executor() -> LocalCommandExecutor {
        // A pre-exec hook that fails stands in for a kernel without seccomp filters.
        production_executor().with_network_sandbox(NetworkSandbox::FailingForTest)
    }
}

#[cfg(unix)]
#[test]
fn a_failing_pre_exec_hook_prevents_the_command_from_running() {
    let temp = tempfile::tempdir().unwrap();
    let marker = temp.path().join("ran");
    // SAFETY: the hook only returns an error.
    let mut command = unsafe {
        command::r#async::Command::new_with_process_group_and_pre_exec("/bin/sh", || {
            Err(std::io::Error::from_raw_os_error(1))
        })
    };
    command
        .arg("-c")
        .arg(format!("touch '{}'", marker.display()));
    let result = futures_lite::future::block_on(command.status());
    assert!(result.is_err(), "spawn succeeded despite the failing hook");
    assert!(!marker.exists());
}

#[cfg(target_os = "macos")]
mod macos_only {
    use crate::terminal::model::session::command_executor::test_support::*;

    fn sandbox_only_executor() -> crate::terminal::model::session::LocalCommandExecutor {
        production_executor().without_offline_environment()
    }

    const CONNECT_TO_MDNS: &str = "import socket,sys\n\
        s = socket.socket(socket.AF_UNIX)\n\
        try:\n    s.connect('/var/run/mDNSResponder'); print('mdns-connected')\n\
        except OSError as e:\n    print('mdns-refused', e)\n";

    #[test]
    fn the_dns_daemon_cannot_be_reached() {
        // A sandboxed process's name lookup is sent to the network by mDNSResponder
        // (verified with `log stream`: the looked-up name left the machine). The profile denies
        // the daemon's socket, so the lookup never gets that far.
        let Some(python) = require_tool("python3") else {
            return;
        };
        let temp = tempfile::tempdir().unwrap();
        let script = temp.path().join("mdns.py");
        std::fs::write(&script, CONNECT_TO_MDNS).unwrap();
        let command = format!("{} {}", python.display(), script.display());
        let variables = base_environment(temp.path());

        let control = run_unprotected(&command, temp.path(), &system_path(), &variables);
        assert!(
            control.output.contains("mdns-connected"),
            "fixture is insensitive: {}",
            control.output
        );
        let ran = run_as_generator(
            sandbox_only_executor(),
            &command,
            temp.path(),
            &system_path(),
            &variables,
        );
        assert!(ran.output.contains("mdns-refused"), "{}", ran.output);
    }

    const BACKGROUND_SESSION: &str = r#"
import Foundation
final class D: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    let sem = DispatchSemaphore(value: 0)
    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo l: URL) {}
    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError e: Error?) { sem.signal() }
}
let d = D()
let cfg = URLSessionConfiguration.background(withIdentifier: "probe\(getpid())")
let s = URLSession(configuration: cfg, delegate: d, delegateQueue: nil)
s.downloadTask(with: URL(string: CommandLine.arguments[1])!).resume()
_ = d.sem.wait(timeout: .now() + 8)
"#;

    #[test]
    fn a_background_url_session_cannot_use_the_system_daemon() {
        // Verified: without the mach-lookup deny, `nsurlsessiond` fetched a loopback URL on
        // behalf of a sandboxed process.
        let Some(swiftc) = require_tool("swiftc") else {
            return;
        };
        let canary = Canary::start();
        let temp = tempfile::tempdir().unwrap();
        let source = temp.path().join("probe.swift");
        let binary = temp.path().join("probe");
        std::fs::write(&source, BACKGROUND_SESSION).unwrap();
        let compiled = command::blocking::Command::new(swiftc)
            .arg(&source)
            .arg("-o")
            .arg(&binary)
            .output()
            .unwrap();
        if !compiled.status.success() {
            eprintln!(
                "SKIPPED: swiftc could not build the probe: {}",
                String::from_utf8_lossy(&compiled.stderr)
            );
            return;
        }
        let command = format!("'{}' '{}/probe-url'", binary.display(), canary.url());
        let variables = base_environment(temp.path());

        run_unprotected(&command, temp.path(), &system_path(), &variables);
        assert!(
            !canary.requests().is_empty(),
            "fixture is insensitive: a background URLSession never reached the canary"
        );
        canary.reset();
        run_as_generator(
            sandbox_only_executor(),
            &command,
            temp.path(),
            &system_path(),
            &variables,
        );
        assert_eq!(canary.requests(), Vec::<String>::new());
    }
}

#[cfg(target_os = "linux")]
mod linux_only {
    use crate::terminal::model::session::command_executor::test_support::*;

    fn sandbox_only_executor() -> crate::terminal::model::session::LocalCommandExecutor {
        production_executor().without_offline_environment()
    }

    #[test]
    fn socket_calls_fail_with_eperm_for_inet_and_inet6_and_work_for_unix() {
        let Some(python) = require_tool("python3") else {
            return;
        };
        let temp = tempfile::tempdir().unwrap();
        let script = temp.path().join("sockets.py");
        std::fs::write(
            &script,
            "import socket, errno\n\
             for name, family in (('inet', socket.AF_INET), ('inet6', socket.AF_INET6), ('unix', socket.AF_UNIX)):\n\
             \x20   try:\n\
             \x20       socket.socket(family); print(name, 'ok')\n\
             \x20   except OSError as e:\n\
             \x20       print(name, errno.errorcode[e.errno])\n",
        )
        .unwrap();
        let command = format!("{} {}", python.display(), script.display());
        let variables = base_environment(temp.path());

        let control = run_unprotected(&command, temp.path(), &system_path(), &variables);
        assert!(
            control.output.contains("inet ok"),
            "fixture is insensitive: {}",
            control.output
        );
        let ran = run_as_generator(
            sandbox_only_executor(),
            &command,
            temp.path(),
            &system_path(),
            &variables,
        );
        assert!(ran.output.contains("inet EPERM"), "{}", ran.output);
        assert!(ran.output.contains("inet6 EPERM"), "{}", ran.output);
        assert!(ran.output.contains("unix ok"), "{}", ran.output);
    }
}
