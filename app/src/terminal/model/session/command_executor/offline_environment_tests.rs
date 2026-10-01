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
        ("GOTOOLCHAIN", "local"),
        ("GOPROXY", "off"),
        ("HOMEBREW_NO_AUTO_UPDATE", "1"),
        ("UV_OFFLINE", "1"),
        ("DENO_NO_UPDATE_CHECK", "1"),
        ("NG_CLI_ANALYTICS", "false"),
        ("NX_DAEMON", "false"),
        ("NX_NO_CLOUD", "true"),
        ("NXF_OFFLINE", "true"),
        ("DOTNET_CLI_TELEMETRY_OPTOUT", "1"),
        ("AZURE_CORE_COLLECT_TELEMETRY", "false"),
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
fn git_override_is_appended_to_existing_pairs() {
    let none = OfflineEnvironment::compute(|_| None);
    assert_eq!(value_of(&none, "GIT_CONFIG_COUNT"), Some("1"));
    assert_eq!(value_of(&none, "GIT_CONFIG_KEY_0"), Some("core.fsmonitor"));
    assert_eq!(value_of(&none, "GIT_CONFIG_VALUE_0"), Some("false"));

    let existing = HashMap::from([("GIT_CONFIG_COUNT", "2")]);
    let appended = OfflineEnvironment::compute(lookup_in(&existing));
    assert_eq!(value_of(&appended, "GIT_CONFIG_COUNT"), Some("3"));
    assert_eq!(
        value_of(&appended, "GIT_CONFIG_KEY_2"),
        Some("core.fsmonitor")
    );
    assert_eq!(value_of(&appended, "GIT_CONFIG_VALUE_2"), Some("false"));
    assert_eq!(
        value_of(&appended, "GIT_CONFIG_KEY_0"),
        None,
        "pairs the session already defines are not rewritten"
    );
    assert_eq!(value_of(&appended, "GIT_CONFIG_KEY_1"), None);

    let bogus = HashMap::from([("GIT_CONFIG_COUNT", "many")]);
    let reset = OfflineEnvironment::compute(lookup_in(&bogus));
    assert_eq!(value_of(&reset, "GIT_CONFIG_COUNT"), Some("1"));
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
                    || line.starts_with("GIT_CONFIG_KEY_2=")),
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
            "GIT_CONFIG_COUNT=1",
            "GIT_CONFIG_KEY_0=core.fsmonitor",
            "GIT_CONFIG_VALUE_0=false",
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
        assert_environment_keeps_silent(scenario, &canary);
    }

    #[test]
    fn npm_does_not_check_for_updates() {
        let canary = Canary::start();
        let Some(scenario) = npm_scenario(&canary) else {
            return;
        };
        assert_environment_keeps_silent(scenario, &canary);
    }

    #[test]
    fn corepack_does_not_download_the_pinned_package_manager() {
        let canary = Canary::start();
        let Some(scenario) = corepack_scenario(&canary) else {
            return;
        };
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
        assert_environment_keeps_silent(scenario, &canary);
    }

    #[test]
    fn git_does_not_lazy_fetch_from_a_promisor_remote() {
        let canary = Canary::start();
        let Some(scenario) = git_lazy_fetch_scenario(&canary) else {
            return;
        };
        assert_environment_keeps_silent(scenario, &canary);
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
