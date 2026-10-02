use super::*;

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
        // The missing sandbox tool ends in
        // an error from the executor, never in a command that ran without the sandbox.
        let temp = tempfile::tempdir().unwrap();
        let marker = temp.path().join("ran");
        let command = format!("touch '{}'", marker.display());
        let result = futures_lite::future::block_on(
            sandbox_failing_executor().execute_local_command(&command, temp.path().to_str(), None),
        );
        assert!(result.is_err(), "the command ran or reported success");
        assert!(!marker.exists(), "the command ran without its sandbox");
    }

    fn sandbox_failing_executor() -> LocalCommandExecutor {
        production_executor().with_network_sandbox(NetworkSandbox::EnforcedWithTool(
            "/nonexistent/sandbox-exec".into(),
        ))
    }
}

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

/// The switch that makes the executor trust an outer sandbox (`WARP_NETWORK_SANDBOX_BY_PARENT`)
/// must exist only in test and integration-test builds. This checks the source: every mention of
/// the switch outside the test module sits under a `cfg` that requires `test` or the
/// `integration_tests` feature, and that feature is not part of any release feature.
#[test]
fn the_outer_sandbox_switch_is_compiled_only_into_test_builds() {
    let source = include_str!("network_sandbox.rs");
    let production = source
        .split("#[cfg(test)]\n#[path = \"network_sandbox_tests.rs\"]")
        .next()
        .unwrap();
    let lines: Vec<&str> = production.lines().collect();
    let mut mentions = 0;
    for (index, line) in lines.iter().enumerate() {
        let is_doc_or_comment = line.trim_start().starts_with("//");
        if is_doc_or_comment
            || !(line.contains("OUTER_SANDBOX_VARIABLE")
                || line.contains("WARP_NETWORK_SANDBOX_BY_PARENT"))
        {
            continue;
        }
        mentions += 1;
        // The item (`const`) carries its own attribute; a use inside `sandboxed_command` sits in an
        // `if` whose statement carries the attribute a few lines above.
        let attribute = lines[..index]
            .iter()
            .rev()
            .take(4)
            .find(|candidate| candidate.trim_start().starts_with("#[cfg("))
            .unwrap_or_else(|| panic!("no cfg attribute above line {}: {line}", index + 1));
        assert!(
            (attribute.contains("test") || attribute.contains("integration_tests"))
                && !attribute.contains("not("),
            "line {} is not compiled only into test builds: {attribute}",
            index + 1
        );
    }
    assert!(
        mentions >= 2,
        "expected the definition and the use of the switch"
    );

    let manifest = include_str!("../../../../../Cargo.toml");
    let release_features = manifest
        .lines()
        .filter(|line| line.starts_with("release_bundle") || line.starts_with("default"))
        .collect::<Vec<_>>()
        .join("\n");
    assert!(
        !release_features.contains("integration_tests"),
        "a release feature enables integration_tests: {release_features}"
    );
}
