use std::collections::HashMap;

use super::*;

fn lookup_in<'a>(
    variables: &'a HashMap<&'static str, &'static str>,
) -> impl Fn(&str) -> Option<String> + 'a {
    |name| variables.get(name).map(|value| (*value).to_owned())
}

fn value_of<'a>(environment: &'a OfflineEnvironment, name: &str) -> Option<&'a str> {
    environment
        .set
        .iter()
        .find(|(candidate, _)| candidate == name)
        .map(|(_, value)| value.as_str())
}

#[test]
fn table_sets_every_documented_variable() {
    let environment = OfflineEnvironment::compute(|_| None);
    for (name, value) in [
        ("RUSTUP_AUTO_INSTALL", "0"),
        ("COREPACK_ENABLE_NETWORK", "0"),
        ("npm_config_update_notifier", "false"),
        ("GIT_TERMINAL_PROMPT", "0"),
        ("GIT_NO_LAZY_FETCH", "1"),
        ("GIT_ALLOW_PROTOCOL", "file"),
        ("GOTOOLCHAIN", "local"),
        ("GOPROXY", "off"),
        ("POWERSHELL_TELEMETRY_OPTOUT", "1"),
        ("POWERSHELL_UPDATECHECK", "Off"),
        ("CLOUDSDK_COMPONENT_MANAGER_DISABLE_UPDATE_CHECK", "1"),
    ] {
        assert_eq!(value_of(&environment, name), Some(value), "{name}");
    }
}

#[test]
fn table_overrides_session_values() {
    let session = HashMap::from([
        ("RUSTUP_AUTO_INSTALL".to_owned(), "1".to_owned()),
        ("PATH".to_owned(), "/usr/bin".to_owned()),
        ("npm_config_update_notifier".to_owned(), "true".to_owned()),
    ]);
    let (hardened, removals) = harden(Some(session));
    let hardened = hardened.expect("always Some");
    assert!(removals.is_empty() || removals == ["DOCKER_HOST"]);
    assert_eq!(hardened["RUSTUP_AUTO_INSTALL"], "0");
    assert_eq!(hardened["npm_config_update_notifier"], "false");
    assert_eq!(hardened["PATH"], "/usr/bin", "unrelated values are kept");
}

#[test]
fn git_overrides_are_appended_to_existing_pairs() {
    const PAIRS: [(&str, &str); 3] = [
        ("core.fsmonitor", "false"),
        ("log.showSignature", "false"),
        ("core.hooksPath", "/dev/null"),
    ];
    let none = OfflineEnvironment::compute(|_| None);
    assert_eq!(value_of(&none, "GIT_CONFIG_COUNT"), Some("3"));
    for (index, (key, value)) in PAIRS.iter().enumerate() {
        assert_eq!(
            value_of(&none, &format!("GIT_CONFIG_KEY_{index}")),
            Some(*key)
        );
        assert_eq!(
            value_of(&none, &format!("GIT_CONFIG_VALUE_{index}")),
            Some(*value)
        );
    }

    let existing = HashMap::from([("GIT_CONFIG_COUNT", "2")]);
    let appended = OfflineEnvironment::compute(lookup_in(&existing));
    assert_eq!(value_of(&appended, "GIT_CONFIG_COUNT"), Some("5"));
    for (offset, (key, value)) in PAIRS.iter().enumerate() {
        let index = 2 + offset;
        assert_eq!(
            value_of(&appended, &format!("GIT_CONFIG_KEY_{index}")),
            Some(*key)
        );
        assert_eq!(
            value_of(&appended, &format!("GIT_CONFIG_VALUE_{index}")),
            Some(*value)
        );
    }
    assert_eq!(
        value_of(&appended, "GIT_CONFIG_KEY_0"),
        None,
        "pairs the session already defines are not rewritten"
    );
    assert_eq!(value_of(&appended, "GIT_CONFIG_KEY_1"), None);

    let bogus = HashMap::from([("GIT_CONFIG_COUNT", "many")]);
    let reset = OfflineEnvironment::compute(lookup_in(&bogus));
    assert_eq!(value_of(&reset, "GIT_CONFIG_COUNT"), Some("3"));
    assert_eq!(value_of(&reset, "GIT_CONFIG_KEY_0"), Some("core.fsmonitor"));
}

#[test]
fn remote_docker_host_is_dropped_and_local_ones_are_kept() {
    for remote in [
        "tcp://10.0.0.5:2375",
        "ssh://user@host",
        "TCP://x",
        "host:2375",
    ] {
        let variables = HashMap::from([("DOCKER_HOST", remote)]);
        let environment = OfflineEnvironment::compute(lookup_in(&variables));
        assert_eq!(environment.remove, ["DOCKER_HOST"], "{remote}");
    }
    for local in [
        "unix:///var/run/docker.sock",
        "npipe:////./pipe/docker_engine",
        "fd://3",
        "",
    ] {
        let variables = HashMap::from([("DOCKER_HOST", local)]);
        let environment = OfflineEnvironment::compute(lookup_in(&variables));
        assert!(environment.remove.is_empty(), "{local}");
    }
    assert!(OfflineEnvironment::compute(|_| None).remove.is_empty());
}

mod docker_context {
    use super::*;

    fn write_context(config_dir: &std::path::Path, hash: &str, name: &str, host: &str) {
        let meta_dir = config_dir.join("contexts").join("meta").join(hash);
        std::fs::create_dir_all(&meta_dir).unwrap();
        std::fs::write(
            meta_dir.join("meta.json"),
            format!(r#"{{"Name":"{name}","Metadata":{{}},"Endpoints":{{"docker":{{"Host":"{host}","SkipTLSVerify":false}}}}}}"#),
        )
        .unwrap();
    }

    fn environment_for(
        config_dir: &std::path::Path,
        docker_context: Option<&str>,
    ) -> OfflineEnvironment {
        let config_dir = config_dir.to_string_lossy().into_owned();
        let docker_context = docker_context.map(str::to_owned);
        OfflineEnvironment::compute(move |name| match name {
            "DOCKER_CONFIG" => Some(config_dir.clone()),
            "DOCKER_CONTEXT" => docker_context.clone(),
            _ => None,
        })
    }

    #[test]
    fn current_context_with_a_remote_endpoint_is_replaced_by_the_default() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(
            dir.path().join("config.json"),
            r#"{"currentContext":"prod"}"#,
        )
        .unwrap();
        write_context(dir.path(), "aaa", "prod", "ssh://deploy@prod.example");
        write_context(
            dir.path(),
            "bbb",
            "colima",
            "unix:///Users/me/.colima/docker.sock",
        );

        let environment = environment_for(dir.path(), None);
        assert_eq!(value_of(&environment, "DOCKER_CONTEXT"), Some("default"));
    }

    #[test]
    fn local_and_default_contexts_are_left_alone() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(
            dir.path().join("config.json"),
            r#"{"currentContext":"colima"}"#,
        )
        .unwrap();
        write_context(dir.path(), "aaa", "prod", "tcp://prod.example:2376");
        write_context(
            dir.path(),
            "bbb",
            "colima",
            "unix:///Users/me/.colima/docker.sock",
        );

        assert_eq!(
            value_of(&environment_for(dir.path(), None), "DOCKER_CONTEXT"),
            None,
            "a local context keeps working (colima, orbstack, rancher desktop)"
        );
        assert_eq!(
            value_of(
                &environment_for(dir.path(), Some("default")),
                "DOCKER_CONTEXT"
            ),
            None
        );
    }

    #[test]
    fn docker_context_variable_beats_the_config_file() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(
            dir.path().join("config.json"),
            r#"{"currentContext":"colima"}"#,
        )
        .unwrap();
        write_context(dir.path(), "aaa", "prod", "tcp://prod.example:2376");
        write_context(
            dir.path(),
            "bbb",
            "colima",
            "unix:///Users/me/.colima/docker.sock",
        );

        let environment = environment_for(dir.path(), Some("prod"));
        assert_eq!(value_of(&environment, "DOCKER_CONTEXT"), Some("default"));
    }

    #[test]
    fn missing_or_malformed_files_mean_not_remote() {
        let dir = tempfile::tempdir().unwrap();
        assert_eq!(
            value_of(&environment_for(dir.path(), Some("prod")), "DOCKER_CONTEXT"),
            None
        );
        std::fs::write(dir.path().join("config.json"), "{not json").unwrap();
        assert_eq!(
            value_of(&environment_for(dir.path(), None), "DOCKER_CONTEXT"),
            None
        );
    }
}

#[test]
fn prologue_exists_for_bash_and_zsh_only() {
    assert!(posix_prologue(ShellType::Bash).is_some());
    assert!(posix_prologue(ShellType::Zsh).is_some());
    assert!(posix_prologue(ShellType::Fish).is_none());
    assert!(posix_prologue(ShellType::PowerShell).is_none());
}

/// Every row of the table names the test that exercised it with the real tool, and that test
/// exists in this file. A row that is added without one, or whose test is renamed, fails here.
#[test]
fn every_table_row_names_a_verification_test_that_exists() {
    const VERIFIED_BY: &[(&str, &str)] = &[
        (
            "RUSTUP_AUTO_INSTALL",
            "rustup_proxies_do_not_install_a_toolchain",
        ),
        (
            "COREPACK_ENABLE_NETWORK",
            "corepack_does_not_download_the_pinned_package_manager",
        ),
        (
            "npm_config_update_notifier",
            "npm_does_not_check_for_updates",
        ),
        (
            "GIT_NO_LAZY_FETCH",
            "git_does_not_lazy_fetch_from_a_promisor_remote",
        ),
        ("GIT_TERMINAL_PROMPT", "git_terminal_prompt_is_off"),
        (
            "GIT_ALLOW_PROTOCOL",
            "git_cannot_lazy_fetch_over_a_network_transport",
        ),
        (
            "log.showSignature",
            "git_log_does_not_run_the_repositorys_gpg_program",
        ),
        ("GOTOOLCHAIN", "go_does_not_download_a_toolchain"),
        ("GOPROXY", "go_does_not_fetch_modules"),
        (
            "POWERSHELL_TELEMETRY_OPTOUT",
            "powershell_update_check_and_telemetry_are_switched_off",
        ),
        (
            "POWERSHELL_UPDATECHECK",
            "powershell_update_check_and_telemetry_are_switched_off",
        ),
        (
            "CLOUDSDK_COMPONENT_MANAGER_DISABLE_UPDATE_CHECK",
            "gcloud_reads_the_update_check_switch_from_the_environment",
        ),
        ("core.fsmonitor", "git_fsmonitor_hook_does_not_run"),
        ("core.hooksPath", "git_repository_hooks_do_not_run"),
    ];
    let source = [
        include_str!("offline_environment_tests.rs"),
        include_str!("git_completion_tests.rs"),
    ]
    .concat();
    let mut rows: Vec<&str> = FIXED_VARIABLES.iter().map(|(name, _)| *name).collect();
    rows.extend(GIT_CONFIG_OVERRIDES.iter().map(|(key, _)| *key));
    rows.sort_unstable();
    let mut verified: Vec<&str> = VERIFIED_BY.iter().map(|(name, _)| *name).collect();
    verified.sort_unstable();
    assert_eq!(rows, verified, "the table and its verification list differ");
    for (name, test) in VERIFIED_BY {
        assert!(
            source.contains(&format!("fn {test}()")),
            "{name} is verified by `{test}`, which does not exist"
        );
    }
}

#[cfg(unix)]
mod real_shells {
    use command::blocking::Command;

    use super::*;

    fn shell_path(name: &str) -> Option<PathBuf> {
        ["/bin", "/usr/bin", "/usr/local/bin", "/opt/homebrew/bin"]
            .iter()
            .map(|dir| PathBuf::from(dir).join(name))
            .find(|path| path.exists())
    }

    /// Runs `command` the way the in-band shell function does: `raw=$(eval "$command" 2>&1)` in
    /// the user's shell, with `extra_env` in the shell's own environment. Prints what the
    /// command printed, then what the surrounding shell sees afterwards.
    fn run_in_band(
        shell: &str,
        shell_type: ShellType,
        command: &str,
        extra_env: &[(&str, &str)],
    ) -> Option<(String, String)> {
        let shell_path = shell_path(shell).or_else(|| {
            eprintln!("SKIPPED: {shell} is not installed");
            None
        })?;
        let command = format!("{} {command}", posix_prologue(shell_type).unwrap());
        let output = Command::new(shell_path)
            .arg("-c")
            .arg(r#"raw=$(eval "$1" 2>&1); echo "$raw"; echo "---after"; env | sort"#)
            .arg("shell")
            .arg(&command)
            .envs(extra_env.iter().copied())
            .output()
            .unwrap();
        let output = String::from_utf8(output.stdout).unwrap();
        let (inside, after) = output.split_once("---after\n").unwrap();
        Some((inside.to_owned(), after.to_owned()))
    }

    fn assert_prologue_matches_table(shell: &str, shell_type: ShellType) {
        let Some((inside, after)) = run_in_band(
            shell,
            shell_type,
            "env",
            &[
                ("GIT_CONFIG_COUNT", "2"),
                ("GIT_CONFIG_KEY_0", "user.name"),
                ("GIT_CONFIG_VALUE_0", "zed"),
                ("GIT_CONFIG_KEY_1", "user.email"),
                ("GIT_CONFIG_VALUE_1", "z@example.com"),
                ("DOCKER_HOST", "tcp://127.0.0.1:1"),
            ],
        ) else {
            return;
        };

        let expected = OfflineEnvironment::compute(|name| match name {
            "GIT_CONFIG_COUNT" => Some("2".to_owned()),
            _ => None,
        });
        for (name, value) in &expected.set {
            assert!(
                inside.lines().any(|line| line == format!("{name}={value}")),
                "{shell}: {name}={value} missing from the command's environment:\n{inside}"
            );
        }
        assert!(
            !inside.lines().any(|line| line.starts_with("DOCKER_HOST=")),
            "{shell}: remote DOCKER_HOST survived"
        );
        assert!(
            !inside.contains("__openrun_n"),
            "{shell}: helper variable leaked into the command"
        );
        assert!(
            inside
                .lines()
                .any(|line| line == "GIT_CONFIG_KEY_0=user.name"),
            "{shell}: session git pair 0 was overwritten"
        );
        assert!(
            !after
                .lines()
                .any(|line| line.starts_with("RUSTUP_AUTO_INSTALL=")
                    || line.starts_with("GIT_CONFIG_KEY_2=")
                    || line.starts_with("GIT_CONFIG_KEY_3=")),
            "{shell}: the table leaked into the surrounding shell:\n{after}"
        );
        assert!(
            after.lines().any(|line| line == "GIT_CONFIG_COUNT=2"),
            "{shell}: the surrounding shell's GIT_CONFIG_COUNT changed"
        );
    }

    #[test]
    fn bash_prologue_applies_the_table_inside_the_command_only() {
        assert_prologue_matches_table("bash", ShellType::Bash);
    }

    #[test]
    fn zsh_prologue_applies_the_table_inside_the_command_only() {
        assert_prologue_matches_table("zsh", ShellType::Zsh);
    }

    #[test]
    fn prologue_with_unset_git_count_starts_at_zero() {
        let Some((inside, _)) = run_in_band("bash", ShellType::Bash, "env", &[]) else {
            return;
        };
        for expected in [
            "GIT_CONFIG_COUNT=3",
            "GIT_CONFIG_KEY_0=core.fsmonitor",
            "GIT_CONFIG_VALUE_0=false",
            "GIT_CONFIG_KEY_1=log.showSignature",
            "GIT_CONFIG_VALUE_1=false",
            "GIT_CONFIG_KEY_2=core.hooksPath",
            "GIT_CONFIG_VALUE_2=/dev/null",
        ] {
            assert!(
                inside.lines().any(|line| line == expected),
                "{expected}\n{inside}"
            );
        }
    }
}

/// The tests that matter most: real tools, a loopback canary standing in for the internet, and
/// the real generator execution path (`SessionContext::execute_command_at_pwd` into
/// `LocalCommandExecutor`). Each test first runs the tool without the offline environment to
/// show the fixture does reach the canary, then with it and asserts silence. The network sandbox
/// is switched off here so that only the environment table is under test.
#[cfg(unix)]
mod real_tools {
    use super::*;
    use crate::terminal::model::session::LocalCommandExecutor;
    use crate::terminal::model::session::command_executor::network_sandbox::NetworkSandbox;
    use crate::terminal::model::session::command_executor::test_support::*;

    fn environment_only_executor() -> LocalCommandExecutor {
        production_executor().with_network_sandbox(NetworkSandbox::Off)
    }

    fn assert_environment_keeps_silent(scenario: Scenario, canary: &Canary) {
        scenario.assert_control_reaches(canary);
        scenario.assert_silent_through(canary, environment_only_executor);
    }

    #[test]
    fn rustup_proxies_do_not_install_a_toolchain() {
        let canary = Canary::start();
        let Some(scenario) = rustup_scenario(&canary) else {
            return;
        };
        scenario.assert_silent_with_variable(&canary, "RUSTUP_AUTO_INSTALL", "0");
        assert_environment_keeps_silent(scenario, &canary);
    }

    #[test]
    fn npm_does_not_check_for_updates() {
        let canary = Canary::start();
        let Some(scenario) = npm_scenario(&canary) else {
            return;
        };
        scenario.assert_silent_with_variable(&canary, "npm_config_update_notifier", "false");
        assert_environment_keeps_silent(scenario, &canary);
    }

    #[test]
    fn corepack_does_not_download_the_pinned_package_manager() {
        let canary = Canary::start();
        let Some(scenario) = corepack_scenario(&canary) else {
            return;
        };
        scenario.assert_silent_with_variable(&canary, "COREPACK_ENABLE_NETWORK", "0");
        assert_environment_keeps_silent(scenario, &canary);
    }

    #[test]
    fn docker_does_not_use_a_remote_host_or_context() {
        let canary = Canary::start();
        for mut scenario in docker_scenarios(&canary) {
            scenario.commands = commands(&["docker ps -a --format '{{ json . }}'"]);
            assert_environment_keeps_silent(scenario, &canary);
        }
    }

    #[test]
    fn git_fsmonitor_hook_does_not_run() {
        let canary = Canary::start();
        let Some(scenario) = git_fsmonitor_scenario() else {
            return;
        };
        scenario.assert_silent_with_git_config(&canary, "core.fsmonitor", "false");
        assert_environment_keeps_silent(scenario, &canary);
    }

    #[test]
    fn git_does_not_lazy_fetch_from_a_promisor_remote() {
        let canary = Canary::start();
        let Some(scenario) = git_lazy_fetch_scenario(&canary) else {
            return;
        };
        scenario.assert_silent_with_variable(&canary, "GIT_NO_LAZY_FETCH", "1");
        assert_environment_keeps_silent(scenario, &canary);
    }

    #[test]
    fn git_repository_hooks_do_not_run() {
        let canary = Canary::start();
        let Some(scenario) = git_hooks_scenario() else {
            return;
        };
        scenario.assert_silent_with_git_config(&canary, "core.hooksPath", "/dev/null");
        assert_environment_keeps_silent(scenario, &canary);
    }

    /// Every bundled `git` and `hub` generator that is a plain script, allowed or not, run
    /// through the production executor against a repository full of hooks: none runs a hook.
    #[test]
    fn no_bundled_git_generator_runs_a_repository_hook() {
        let canary = Canary::start();
        let Some(mut scenario) = git_hooks_scenario() else {
            return;
        };
        let mut generator_commands = Vec::new();
        for spec in ["git", "hub"] {
            for (_, command) in bundled_script_commands(spec) {
                if command.trim_start().starts_with("git") {
                    generator_commands.push(command);
                }
            }
        }
        assert!(
            generator_commands.len() >= 10,
            "expected the bundled git generators, found {generator_commands:?}"
        );
        scenario.commands = generator_commands;
        scenario.assert_silent_through(&canary, production_executor);
    }

    #[test]
    fn go_does_not_fetch_modules() {
        let canary = Canary::start();
        let Some(scenario) = go_modules_scenario(&canary) else {
            return;
        };
        scenario.assert_silent_with_variable(&canary, "GOPROXY", "off");
        assert_environment_keeps_silent(scenario, &canary);
    }

    #[test]
    fn go_does_not_download_a_toolchain() {
        let canary = Canary::start();
        let Some(scenario) = go_toolchain_scenario(&canary) else {
            return;
        };
        scenario.assert_silent_with_variable(&canary, "GOTOOLCHAIN", "local");
        assert_environment_keeps_silent(scenario, &canary);
    }

    /// Runs `git ls-remote` against a server that asks for a login, with a controlling terminal
    /// (a pty), and reports whether git printed its `Username for` prompt.
    fn git_prompts_on_the_terminal(
        python: &std::path::Path,
        url: &str,
        prompt_variable: Option<&str>,
    ) -> bool {
        const SCRIPT: &str = r#"
import os, pty, re, select, sys, time
pid, fd = pty.fork()
if pid == 0:
    os.execvp("git", ["git", "ls-remote", sys.argv[1]])
out = b""
deadline = time.time() + 10
while time.time() < deadline:
    ready, _, _ = select.select([fd], [], [], 0.5)
    if ready:
        try:
            data = os.read(fd, 4096)
        except OSError:
            break
        if not data:
            break
        out += data
        if re.search(rb"(^|\n)Username for", out):
            break
try:
    os.kill(pid, 9)
except OSError:
    pass
print("PROMPTED" if re.search(rb"(^|\n)Username for", out) else "NO-PROMPT")
"#;
        let temp = tempfile::tempdir().unwrap();
        let mut command = command::blocking::Command::new(python);
        command
            .args(["-c", SCRIPT, url])
            .current_dir(temp.path())
            .env("HOME", temp.path())
            .env("GIT_CONFIG_GLOBAL", "/dev/null")
            .env("GIT_CONFIG_SYSTEM", "/dev/null")
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .env_remove("GIT_ASKPASS")
            .env_remove("SSH_ASKPASS")
            .env_remove("GIT_TERMINAL_PROMPT");
        if let Some(value) = prompt_variable {
            command.env("GIT_TERMINAL_PROMPT", value);
        }
        let output = command.output().unwrap();
        let text = String::from_utf8_lossy(&output.stdout).into_owned();
        assert!(
            text.contains("PROMPTED") || text.contains("NO-PROMPT"),
            "the pty probe did not run: {text} {}",
            String::from_utf8_lossy(&output.stderr)
        );
        text.contains("PROMPTED")
    }

    #[test]
    fn git_terminal_prompt_is_off() {
        let (Some(python), Some(_)) = (require_tool("python3"), require_tool("git")) else {
            return;
        };
        let canary = Canary::start_requiring_login();
        let url = format!("{}/repo.git", canary.url());
        assert!(
            git_prompts_on_the_terminal(&python, &url, None),
            "fixture is insensitive: git did not prompt for a username"
        );
        assert!(
            !git_prompts_on_the_terminal(&python, &url, Some("0")),
            "git prompted despite GIT_TERMINAL_PROMPT=0"
        );
    }

    #[test]
    fn gcloud_reads_the_update_check_switch_from_the_environment() {
        let Some(gcloud) = require_tool("gcloud") else {
            return;
        };
        let temp = tempfile::tempdir().unwrap();
        let canary = Canary::start();
        let mut variables = base_environment(&temp.path().join("home"));
        // Nothing may reach Google: the update check, if it runs, asks the canary.
        route_traffic_to_canary(&mut variables, &canary);
        variables.insert(
            "CLOUDSDK_COMPONENT_MANAGER_SNAPSHOT_URL".to_owned(),
            canary.url(),
        );
        variables.insert(
            "CLOUDSDK_CORE_DISABLE_USAGE_REPORTING".to_owned(),
            "true".to_owned(),
        );
        variables.insert("CLOUDSDK_CORE_DISABLE_PROMPTS".to_owned(), "1".to_owned());
        variables.insert(
            "CLOUDSDK_CONFIG".to_owned(),
            temp.path().join("gcloud").to_string_lossy().into_owned(),
        );
        let path = format!("{}:{}", gcloud.parent().unwrap().display(), system_path());
        let command = "gcloud config get component_manager/disable_update_check";
        // The property is printed on a line of its own: `True`, `true` or `1` when set.
        let switch_is_on = |output: &str| {
            output.lines().any(|line| {
                let line = line.trim().to_lowercase();
                line == "true" || line == "1"
            })
        };
        let control = run_unprotected(command, temp.path(), &path, &variables);
        assert!(
            !switch_is_on(&control.output),
            "fixture is insensitive: the switch is already on without the variable: {}",
            control.output
        );
        let through_executor = run_as_generator(
            environment_only_executor(),
            command,
            temp.path(),
            &path,
            &variables,
        );
        assert!(
            switch_is_on(&through_executor.output),
            "gcloud did not resolve disable_update_check from the table: {}",
            through_executor.output
        );
    }

    #[test]
    fn git_fsmonitor_override_keeps_the_sessions_own_git_config() {
        let canary = Canary::start();
        let Some(mut scenario) = git_fsmonitor_scenario() else {
            return;
        };
        scenario.variables.extend([
            ("GIT_CONFIG_COUNT".to_owned(), "1".to_owned()),
            ("GIT_CONFIG_KEY_0".to_owned(), "user.name".to_owned()),
            ("GIT_CONFIG_VALUE_0".to_owned(), "session-user".to_owned()),
        ]);
        scenario.commands = commands(&["git config --get user.name; git status --porcelain"]);
        let ran = scenario.assert_silent_through(&canary, environment_only_executor);
        assert!(ran[0].success, "{}", ran[0].output);
        assert!(
            ran[0].output.starts_with("session-user\n"),
            "the session's own GIT_CONFIG pair was lost:\n{}",
            ran[0].output
        );
    }

    #[test]
    fn the_whole_table_reaches_the_generator_process() {
        let temp = tempfile::tempdir().unwrap();
        let mut variables = base_environment(&temp.path().join("home"));
        variables.insert("DOCKER_HOST".to_owned(), "tcp://127.0.0.1:1".to_owned());
        variables.insert("GOPROXY".to_owned(), "https://proxy.example".to_owned());
        let ran = run_as_generator(
            environment_only_executor(),
            "env",
            temp.path(),
            "/usr/bin:/bin",
            &variables,
        );
        assert!(ran.success);
        let expected = OfflineEnvironment::compute(|name| variables.get(name).cloned());
        for (name, value) in &expected.set {
            assert!(
                ran.output
                    .lines()
                    .any(|line| line == format!("{name}={value}")),
                "{name}={value} missing:\n{}",
                ran.output
            );
        }
        assert!(
            !ran.output
                .lines()
                .any(|line| line.starts_with("DOCKER_HOST=")),
            "a remote DOCKER_HOST reached the generator"
        );
    }
}

/// PowerShell 7 against loopback proxies that record every request they receive. The real `pwsh`
/// is needed: the claim is about what it does, not about what a stub would do.
///
/// Two things are checked, with different strength:
///
/// * `powershell_commands_run_with_the_telemetry_and_update_check_switched_off`: the command a
///   PowerShell session's generators use (`pwsh -NoProfile -c`, through the production executor)
///   has both variables set and makes no request. A control shows that the proxy sees `pwsh`'s
///   own .NET HTTP traffic. But that command sends nothing without the variables either (the
///   telemetry and the update check are not part of a `-c` run), so this does not show what the
///   variables change.
/// * `powershell_update_check_and_telemetry_are_switched_off`: four interactive `pwsh` sessions in
///   pseudo-terminals, with no variable, each variable alone and the table. The plain session
///   contacts `aka.ms` (the update check, 3.1 s after start on macOS, pwsh 7.6.6) and, on the
///   Linux runner, `dc.services.visualstudio.com` (telemetry); the session with a variable does
///   not contact that variable's host, and the session with both contacts nothing. Each variable
///   is verified for the hosts the plain session reached on the platform the test ran on.
#[cfg(unix)]
mod real_pwsh {
    use std::path::{Path, PathBuf};
    use std::time::Duration;

    use command::blocking::Command;
    use instant::Instant;

    use super::*;
    use crate::terminal::model::session::LocalCommandExecutor;
    use crate::terminal::model::session::command_executor::network_sandbox::NetworkSandbox;
    use crate::terminal::model::session::command_executor::test_support::*;

    /// Runs an interactive `pwsh` in a pseudo-terminal. It creates the file named by the second
    /// argument when the prompt has appeared and ends `pwsh` when the file named by the third
    /// argument exists. The update check and the telemetry run only when the session is
    /// interactive, which needs a terminal.
    const PTY_SCRIPT: &str = r#"
import os, pty, select, sys, time
pwsh, ready_file, stop_file = sys.argv[1], sys.argv[2], sys.argv[3]
pid, fd = pty.fork()
if pid == 0:
    os.execv(pwsh, [pwsh, "-NoProfile"])
seen = b""
deadline = time.time() + 240
while time.time() < deadline and not os.path.exists(stop_file):
    ready, _, _ = select.select([fd], [], [], 0.1)
    if ready:
        try:
            data = os.read(fd, 4096)
        except OSError:
            break
        if not data:
            break
        seen = (seen + data)[-4096:]
        if b"PS " in seen and b"> " in seen and not os.path.exists(ready_file):
            open(ready_file, "w").write("ready")
try:
    os.write(fd, b"exit\r")
except OSError:
    pass
time.sleep(0.5)
try:
    os.kill(pid, 9)
except OSError:
    pass
os.waitpid(pid, 0)
"#;

    fn proxy_environment(canary: &Canary, home: &Path) -> HashMap<String, String> {
        let mut variables = base_environment(home);
        for name in [
            "HTTP_PROXY",
            "HTTPS_PROXY",
            "ALL_PROXY",
            "http_proxy",
            "https_proxy",
            "all_proxy",
        ] {
            variables.insert(name.to_owned(), canary.url());
        }
        variables.insert("NO_PROXY".to_owned(), String::new());
        variables.insert("no_proxy".to_owned(), String::new());
        variables
    }

    fn pwsh_executor(pwsh: PathBuf) -> LocalCommandExecutor {
        LocalCommandExecutor::new(Some(pwsh), ShellType::PowerShell)
            .with_network_sandbox(NetworkSandbox::Off)
    }

    #[test]
    fn powershell_commands_run_with_the_telemetry_and_update_check_switched_off() {
        let Some(pwsh) = session_shell("pwsh", "OPENRUN_TEST_PWSH") else {
            return;
        };
        let canary = Canary::start();
        let temp = tempfile::tempdir().unwrap();
        let home = temp.path().join("home");
        std::fs::create_dir_all(&home).unwrap();
        let variables = proxy_environment(&canary, &home);
        let run = |command: &str| {
            run_as_generator(
                pwsh_executor(pwsh.clone()),
                command,
                temp.path(),
                &system_path(),
                &variables,
            )
        };

        // Control: with this proxy configuration `pwsh`'s own HTTP client reaches the canary. The
        // host does not resolve, so nothing leaves the machine even if the proxy were ignored.
        let ran = run(
            "try { [System.Net.Http.HttpClient]::new().GetAsync('http://canary-control.invalid/').Result.StatusCode } catch { $_.Exception.Message }",
        );
        assert!(ran.output.contains("NotFound"), "{}", ran.output);
        assert!(
            canary
                .requests()
                .iter()
                .any(|line| line.contains("canary-control.invalid")),
            "the proxy canary did not see pwsh's HTTP request: {:?}",
            canary.requests()
        );
        canary.reset();

        // The command a generator of a PowerShell session runs, through the production executor.
        let ran =
            run("Write-Output \"$env:POWERSHELL_TELEMETRY_OPTOUT/$env:POWERSHELL_UPDATECHECK\"");
        assert!(ran.success, "{}", ran.output);
        assert_eq!(ran.output.trim(), "1/Off");
        std::thread::sleep(Duration::from_secs(5));
        assert_eq!(
            canary.requests(),
            Vec::<String>::new(),
            "pwsh -NoProfile -c made a request"
        );
    }

    /// The host of a request line the canary recorded (`CONNECT host:443 HTTP/1.1`, or
    /// `GET http://host/path HTTP/1.1`).
    fn host_of(request_line: &str) -> String {
        let target = request_line.split_whitespace().nth(1).unwrap_or_default();
        let target = target.split("://").last().unwrap_or_default();
        target
            .split(['/', ':'])
            .next()
            .unwrap_or_default()
            .to_owned()
    }

    struct Interactive {
        name: &'static str,
        canary: Canary,
        child: std::process::Child,
        ready_file: PathBuf,
        stop_file: PathBuf,
    }

    impl Interactive {
        fn hosts(&self) -> Vec<String> {
            let mut hosts: Vec<String> = self
                .canary
                .requests()
                .iter()
                .map(|line| host_of(line))
                .collect();
            hosts.sort();
            hosts.dedup();
            hosts
        }
    }

    #[test]
    fn powershell_update_check_and_telemetry_are_switched_off() {
        let Some(pwsh) = session_shell("pwsh", "OPENRUN_TEST_PWSH") else {
            return;
        };
        if require_tool("python3").is_none() {
            return;
        }
        let temp = tempfile::tempdir().unwrap();
        let script = temp.path().join("interactive_pwsh.py");
        std::fs::write(&script, PTY_SCRIPT).unwrap();
        let table = OfflineEnvironment::compute(|_| None);
        let table_value = |name: &str| -> (String, String) {
            table
                .set
                .iter()
                .find(|(candidate, _)| candidate == name)
                .cloned()
                .unwrap_or_else(|| panic!("{name} is not in the offline table"))
        };
        let powershell_variables: Vec<(String, String)> = table
            .set
            .iter()
            .filter(|(name, _)| name.starts_with("POWERSHELL_"))
            .cloned()
            .collect();
        assert_eq!(
            powershell_variables.len(),
            2,
            "the table is expected to hold POWERSHELL_UPDATECHECK and POWERSHELL_TELEMETRY_OPTOUT"
        );

        // Four interactive sessions at once, each with its own canary: no variable, each of the two
        // alone, and both (the table). Several at once so a runner that traces every process (the
        // network sandbox) does not take four times as long.
        let variants: Vec<(&'static str, Vec<(String, String)>)> = vec![
            ("control", Vec::new()),
            (
                "update check off only",
                vec![table_value("POWERSHELL_UPDATECHECK")],
            ),
            (
                "telemetry opt-out only",
                vec![table_value("POWERSHELL_TELEMETRY_OPTOUT")],
            ),
            ("both (the table)", powershell_variables),
        ];
        let mut sessions: Vec<Interactive> = variants
            .into_iter()
            .enumerate()
            .map(|(index, (name, variables_to_set))| {
                let canary = Canary::start();
                let home = temp.path().join(format!("home-{index}"));
                std::fs::create_dir_all(&home).unwrap();
                let ready_file = temp.path().join(format!("ready-{index}"));
                let stop_file = temp.path().join(format!("stop-{index}"));
                let mut variables = proxy_environment(&canary, &home);
                variables.insert("TERM".to_owned(), "xterm".to_owned());
                for (variable, value) in variables_to_set {
                    variables.insert(variable, value);
                }
                let child = Command::new("python3")
                    .arg(&script)
                    .arg(&pwsh)
                    .arg(&ready_file)
                    .arg(&stop_file)
                    .env_clear()
                    .envs(&variables)
                    .env("PATH", system_path())
                    .spawn()
                    .unwrap();
                Interactive {
                    name,
                    canary,
                    child,
                    ready_file,
                    stop_file,
                }
            })
            .collect();

        // The prompt of every session, then a hold after the last one: the update check starts
        // three seconds after pwsh does (3.1 s measured), and telemetry at start-up, so by then a
        // control that is going to send either has sent it.
        let started = Instant::now();
        while sessions.iter().any(|session| !session.ready_file.exists()) {
            assert!(
                started.elapsed() < Duration::from_secs(180),
                "pwsh did not show a prompt in 180 s in: {:?}",
                sessions
                    .iter()
                    .filter(|session| !session.ready_file.exists())
                    .map(|session| session.name)
                    .collect::<Vec<_>>()
            );
            std::thread::sleep(Duration::from_millis(100));
        }
        let ready_after = started.elapsed();
        std::thread::sleep(Duration::from_secs(12));
        // A slow runner: give the control more time before calling the fixture insensitive.
        while sessions[0].canary.requests().is_empty()
            && started.elapsed() < ready_after + Duration::from_secs(60)
        {
            std::thread::sleep(Duration::from_millis(250));
        }
        std::thread::sleep(Duration::from_secs(3));
        let hosts: Vec<(&'static str, Vec<String>)> = sessions
            .iter()
            .map(|session| (session.name, session.hosts()))
            .collect();

        for session in &mut sessions {
            std::fs::write(&session.stop_file, "stop").unwrap();
            assert!(session.child.wait().unwrap().success());
        }

        // Which hosts a plain interactive pwsh talks to differs by version and platform: 7.6.6 on
        // macOS asked aka.ms (the update check), the Linux runner's pwsh also or only contacts
        // dc.services.visualstudio.com (telemetry). Each variable is verified for the hosts the
        // control reached; the message names what was seen.
        const UPDATE_CHECK_HOST: &str = "aka.ms";
        const TELEMETRY_HOST: &str = "dc.services.visualstudio.com";
        let summary = format!("hosts contacted by each session: {hosts:?}");
        let [control, update_only, telemetry_only, both] = &hosts[..] else {
            unreachable!()
        };
        assert!(
            !control.1.is_empty(),
            "fixture is insensitive: an interactive pwsh without the table contacted nothing \
             ({summary})"
        );
        assert!(
            control
                .1
                .iter()
                .all(|host| host == UPDATE_CHECK_HOST || host == TELEMETRY_HOST),
            "the control contacted a host the table has no variable for ({summary})"
        );
        assert_eq!(both.1, Vec::<String>::new(), "{summary}");
        if control.1.iter().any(|host| host == UPDATE_CHECK_HOST) {
            assert!(
                !update_only.1.iter().any(|host| host == UPDATE_CHECK_HOST),
                "POWERSHELL_UPDATECHECK did not stop the update check ({summary})"
            );
        }
        if control.1.iter().any(|host| host == TELEMETRY_HOST) {
            assert!(
                !telemetry_only.1.iter().any(|host| host == TELEMETRY_HOST),
                "POWERSHELL_TELEMETRY_OPTOUT did not stop the telemetry ({summary})"
            );
        }
        eprintln!("{summary}");
    }
}
