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
/// `LocalCommandExecutor`). Each test first runs the tool without the offline environment to show
/// the fixture does reach the canary, then with it and asserts silence.
#[cfg(unix)]
mod real_tools {
    use std::io::{Read, Write};
    use std::net::{TcpListener, TcpStream};
    use std::os::unix::fs::PermissionsExt as _;
    use std::path::Path;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::{Arc, Mutex};
    use std::time::Duration;

    use command::blocking::Command;
    use typed_path::TypedPathBuf;
    use warp_completer::completer::{CommandExitStatus, GeneratorContext as _};
    use warp_completer::signatures::CommandRegistry;

    use super::*;
    use crate::completer::SessionContext;
    use crate::terminal::model::session::{LocalCommandExecutor, Session, SessionInfo};

    /// A loopback HTTP server that answers 404 to everything and remembers each request line.
    struct Canary {
        address: std::net::SocketAddr,
        requests: Arc<Mutex<Vec<String>>>,
        stop: Arc<AtomicBool>,
    }

    impl Canary {
        fn start() -> Self {
            let listener = TcpListener::bind("127.0.0.1:0").unwrap();
            listener.set_nonblocking(true).unwrap();
            let address = listener.local_addr().unwrap();
            let requests = Arc::new(Mutex::new(Vec::new()));
            let stop = Arc::new(AtomicBool::new(false));
            {
                let requests = requests.clone();
                let stop = stop.clone();
                std::thread::spawn(move || {
                    while !stop.load(Ordering::Relaxed) {
                        match listener.accept() {
                            Ok((stream, _)) => {
                                let requests = requests.clone();
                                std::thread::spawn(move || serve(stream, &requests));
                            }
                            Err(_) => std::thread::sleep(Duration::from_millis(5)),
                        }
                    }
                });
            }
            Self {
                address,
                requests,
                stop,
            }
        }

        fn url(&self) -> String {
            format!("http://{}", self.address)
        }

        fn requests(&self) -> Vec<String> {
            self.requests.lock().unwrap().clone()
        }

        fn reset(&self) {
            self.requests.lock().unwrap().clear();
        }
    }

    impl Drop for Canary {
        fn drop(&mut self) {
            self.stop.store(true, Ordering::Relaxed);
        }
    }

    fn serve(mut stream: TcpStream, requests: &Mutex<Vec<String>>) {
        stream.set_nonblocking(false).unwrap();
        stream
            .set_read_timeout(Some(Duration::from_secs(2)))
            .unwrap();
        let mut received = Vec::new();
        let mut buffer = [0u8; 1024];
        while !received.windows(4).any(|window| window == b"\r\n\r\n") {
            match stream.read(&mut buffer) {
                Ok(0) | Err(_) => break,
                Ok(read) => received.extend_from_slice(&buffer[..read]),
            }
        }
        if let Some(line) = String::from_utf8_lossy(&received).lines().next() {
            requests.lock().unwrap().push(line.to_owned());
        }
        let _ = stream
            .write_all(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
    }

    fn find_tool(name: &str) -> Option<PathBuf> {
        std::env::var_os("PATH").and_then(|paths| {
            std::env::split_paths(&paths)
                .map(|dir| dir.join(name))
                .find(|candidate| candidate.is_file())
        })
    }

    fn require_tool(name: &str) -> Option<PathBuf> {
        let tool = find_tool(name);
        if tool.is_none() {
            eprintln!("SKIPPED: {name} is not installed on this machine");
        }
        tool
    }

    /// Variables that make the tools under test hermetic and sensitive; applied identically to the
    /// control and the protected run so the only difference between them is the offline table.
    fn base_environment(home: &Path) -> HashMap<String, String> {
        HashMap::from([
            ("HOME".to_owned(), home.to_string_lossy().into_owned()),
            // CI systems set CI=true, which silences npm's update notifier and the like.
            ("CI".to_owned(), "false".to_owned()),
            ("RUSTUP_TOOLCHAIN".to_owned(), String::new()),
        ])
    }

    fn system_path() -> String {
        std::env::var("PATH").unwrap_or_else(|_| "/usr/bin:/bin".to_owned())
    }

    /// The result of one run.
    struct Ran {
        success: bool,
        output: String,
    }

    /// Runs `command` through the real generator path: a `Session` backed by the production
    /// `LocalCommandExecutor`, reached through `SessionContext::execute_command_at_pwd`.
    fn run_as_generator(
        command: &str,
        cwd: &Path,
        path: &str,
        variables: &HashMap<String, String>,
    ) -> Ran {
        let session = Session::new(
            SessionInfo::new_for_test().with_path(Some(path.to_owned())),
            Arc::new(LocalCommandExecutor::new(
                Some("/bin/bash".into()),
                ShellType::Bash,
            )),
        );
        let context = SessionContext::new(
            session,
            CommandRegistry::default().into(),
            TypedPathBuf::from(cwd.to_str().unwrap()),
        );
        let output = futures_lite::future::block_on(
            context.execute_command_at_pwd(command, Some(variables.clone())),
        )
        .expect("the generator command could not be started");
        let mut text = String::from_utf8_lossy(&output.stdout).into_owned();
        text.push_str(&String::from_utf8_lossy(&output.stderr));
        Ran {
            success: output.status == CommandExitStatus::Success,
            output: text,
        }
    }

    /// Runs `command` the way a generator ran before this layer existed: same shell, same
    /// variables, no offline table.
    fn run_unprotected(
        command: &str,
        cwd: &Path,
        path: &str,
        variables: &HashMap<String, String>,
    ) -> Ran {
        let output = Command::new("/bin/bash")
            .arg("--norc")
            .arg("-c")
            .arg(command)
            .current_dir(cwd)
            .envs(variables)
            .env("PATH", path)
            .output()
            .unwrap();
        let mut text = String::from_utf8_lossy(&output.stdout).into_owned();
        text.push_str(&String::from_utf8_lossy(&output.stderr));
        Ran {
            success: output.status.success(),
            output: text,
        }
    }

    fn wait_for_quiet() {
        // Tools such as npm report their update check after the command's own output.
        std::thread::sleep(Duration::from_millis(1500));
    }

    fn git(dir: &Path, args: &[&str]) {
        let status = Command::new("git")
            .args(args)
            .current_dir(dir)
            .env("GIT_CONFIG_GLOBAL", "/dev/null")
            .env("GIT_CONFIG_SYSTEM", "/dev/null")
            .env("GIT_AUTHOR_NAME", "n")
            .env("GIT_AUTHOR_EMAIL", "n@example.com")
            .env("GIT_COMMITTER_NAME", "n")
            .env("GIT_COMMITTER_EMAIL", "n@example.com")
            .status()
            .unwrap();
        assert!(status.success(), "git {args:?} failed");
    }

    #[test]
    fn rustup_proxies_do_not_install_a_toolchain() {
        let Some(rustup) = require_tool("rustup") else {
            return;
        };
        let canary = Canary::start();
        let temp = tempfile::tempdir().unwrap();
        let project = temp.path().join("project");
        std::fs::create_dir_all(project.join("src")).unwrap();
        std::fs::write(
            project.join("rust-toolchain.toml"),
            "[toolchain]\nchannel = \"1.70.0\"\n",
        )
        .unwrap();
        std::fs::write(
            project.join("Cargo.toml"),
            "[package]\nname = \"fixture\"\nversion = \"0.1.0\"\nedition = \"2021\"\n",
        )
        .unwrap();
        std::fs::write(project.join("src/main.rs"), "fn main() {}\n").unwrap();

        let proxies = temp.path().join("proxies");
        std::fs::create_dir_all(&proxies).unwrap();
        for name in ["cargo", "rustc", "rustup"] {
            std::os::unix::fs::symlink(&rustup, proxies.join(name)).unwrap();
        }
        let path = format!("{}:/usr/bin:/bin", proxies.display());

        let mut variables = base_environment(&temp.path().join("home"));
        for (name, value) in [
            ("RUSTUP_HOME", temp.path().join("rustup-home")),
            ("CARGO_HOME", temp.path().join("cargo-home")),
        ] {
            variables.insert(name.to_owned(), value.to_string_lossy().into_owned());
        }
        variables.insert("RUSTUP_DIST_SERVER".to_owned(), canary.url());
        variables.insert("RUSTUP_UPDATE_ROOT".to_owned(), canary.url());
        // The setting the issue says does not help.
        variables.insert("CARGO_NET_OFFLINE".to_owned(), "true".to_owned());

        for command in [
            "cargo metadata --format-version 1 --no-deps",
            "rustc --print target-list",
            "cargo read-manifest",
            "cargo install --list",
            "rustup docs --path",
        ] {
            canary.reset();
            run_unprotected(command, &project, &path, &variables);
            assert!(
                !canary.requests().is_empty(),
                "fixture is insensitive: `{command}` without the offline table never reached the \
                 canary"
            );

            canary.reset();
            let ran = run_as_generator(command, &project, &path, &variables);
            assert_eq!(
                canary.requests(),
                Vec::<String>::new(),
                "`{command}` reached the network through the generator path:\n{}",
                ran.output
            );
        }
    }

    #[test]
    fn npm_does_not_check_for_updates() {
        let Some(npm) = require_tool("npm") else {
            return;
        };
        let canary = Canary::start();
        let temp = tempfile::tempdir().unwrap();
        let project = temp.path().join("project");
        std::fs::create_dir_all(&project).unwrap();
        std::fs::write(
            project.join("package.json"),
            r#"{"name":"fixture","version":"1.0.0"}"#,
        )
        .unwrap();
        let path = format!("{}:{}", npm.parent().unwrap().display(), system_path());

        let mut variables = base_environment(&temp.path().join("home"));
        variables.insert("npm_config_registry".to_owned(), canary.url());
        variables.insert(
            "npm_config_cache".to_owned(),
            temp.path().join("cache").to_string_lossy().into_owned(),
        );
        // The setting the issue says does not help.
        variables.insert("NO_UPDATE_NOTIFIER".to_owned(), "1".to_owned());

        run_unprotected("npm prefix", &project, &path, &variables);
        wait_for_quiet();
        assert!(
            !canary.requests().is_empty(),
            "fixture is insensitive: `npm prefix` without the offline table never reached the canary"
        );

        // A fresh cache, so the "checked recently" marker from the control run is gone.
        std::fs::remove_dir_all(temp.path().join("cache")).unwrap();
        std::fs::remove_dir_all(temp.path().join("home")).ok();
        canary.reset();
        let ran = run_as_generator("npm prefix", &project, &path, &variables);
        wait_for_quiet();
        assert!(ran.success, "npm prefix failed:\n{}", ran.output);
        assert_eq!(canary.requests(), Vec::<String>::new());
    }

    #[test]
    fn corepack_does_not_download_the_pinned_package_manager() {
        let Some(corepack) = require_tool("corepack") else {
            return;
        };
        let canary = Canary::start();
        let temp = tempfile::tempdir().unwrap();
        let project = temp.path().join("project");
        std::fs::create_dir_all(&project).unwrap();
        std::fs::write(
            project.join("package.json"),
            r#"{"name":"fixture","packageManager":"yarn@4.5.0"}"#,
        )
        .unwrap();
        let path = format!("{}:{}", corepack.parent().unwrap().display(), system_path());

        let mut variables = base_environment(&temp.path().join("home"));
        variables.insert("COREPACK_NPM_REGISTRY".to_owned(), canary.url());
        variables.insert(
            "COREPACK_HOME".to_owned(),
            temp.path().join("corepack").to_string_lossy().into_owned(),
        );

        run_unprotected("corepack yarn --version", &project, &path, &variables);
        assert!(
            !canary.requests().is_empty(),
            "fixture is insensitive: corepack without the offline table never reached the canary"
        );

        canary.reset();
        let ran = run_as_generator("corepack yarn --version", &project, &path, &variables);
        assert!(!ran.success, "corepack should refuse to download");
        assert_eq!(canary.requests(), Vec::<String>::new());
    }

    fn fsmonitor_repository(temp: &Path) -> (PathBuf, PathBuf) {
        let repo = temp.join("repo");
        std::fs::create_dir_all(&repo).unwrap();
        git(&repo, &["init", "-q"]);
        let marker = temp.join("fsmonitor-ran");
        let hook = temp.join("fsmonitor-hook.sh");
        std::fs::write(
            &hook,
            format!(
                "#!/bin/sh\necho \"$@\" >> '{}'\nprintf '\\0'\n",
                marker.display()
            ),
        )
        .unwrap();
        std::fs::set_permissions(&hook, std::fs::Permissions::from_mode(0o755)).unwrap();
        git(&repo, &["config", "core.fsmonitor", hook.to_str().unwrap()]);
        std::fs::write(repo.join("tracked"), "one\n").unwrap();
        git(&repo, &["add", "tracked"]);
        (repo, marker)
    }

    #[test]
    fn git_fsmonitor_hook_does_not_run() {
        if require_tool("git").is_none() {
            return;
        }
        let temp = tempfile::tempdir().unwrap();
        let (repo, marker) = fsmonitor_repository(temp.path());
        let path = system_path();
        let variables = base_environment(&temp.path().join("home"));

        for command in [
            "git status --porcelain",
            "git --no-optional-locks branch --no-color",
            "git diff",
            "git ls-files",
        ] {
            let _ = std::fs::remove_file(&marker);
            run_unprotected(command, &repo, &path, &variables);
            let control_ran = marker.exists();
            let _ = std::fs::remove_file(&marker);
            let ran = run_as_generator(command, &repo, &path, &variables);
            assert!(ran.success, "`{command}` failed:\n{}", ran.output);
            assert!(
                !marker.exists(),
                "`{command}` ran the repository's core.fsmonitor program"
            );
            if command == "git status --porcelain" {
                assert!(
                    control_ran,
                    "fixture is insensitive: `{command}` without the offline table never ran the \
                     fsmonitor program"
                );
            }
        }
    }

    #[test]
    fn git_fsmonitor_override_keeps_the_sessions_own_git_config() {
        if require_tool("git").is_none() {
            return;
        }
        let temp = tempfile::tempdir().unwrap();
        let (repo, marker) = fsmonitor_repository(temp.path());
        let path = system_path();
        let mut variables = base_environment(&temp.path().join("home"));
        variables.extend([
            ("GIT_CONFIG_COUNT".to_owned(), "1".to_owned()),
            ("GIT_CONFIG_KEY_0".to_owned(), "user.name".to_owned()),
            ("GIT_CONFIG_VALUE_0".to_owned(), "session-user".to_owned()),
        ]);

        // Setting the repository up already ran the hook.
        let _ = std::fs::remove_file(&marker);
        let ran = run_as_generator(
            "git config --get user.name; git status --porcelain",
            &repo,
            &path,
            &variables,
        );
        assert!(ran.success, "{}", ran.output);
        assert!(
            ran.output.starts_with("session-user\n"),
            "the session's own GIT_CONFIG pair was lost:\n{}",
            ran.output
        );
        assert!(!marker.exists(), "fsmonitor ran");
    }

    #[test]
    fn git_does_not_lazy_fetch_from_a_promisor_remote() {
        if require_tool("git").is_none() {
            return;
        }
        let canary = Canary::start();
        let temp = tempfile::tempdir().unwrap();
        let source = temp.path().join("source");
        std::fs::create_dir_all(&source).unwrap();
        git(&source, &["init", "-q"]);
        git(&source, &["config", "uploadpack.allowFilter", "true"]);
        git(
            &source,
            &["config", "uploadpack.allowAnySHA1InWant", "true"],
        );
        std::fs::write(source.join("file"), "contents\n").unwrap();
        git(&source, &["add", "file"]);
        git(&source, &["commit", "-qm", "one"]);

        let clone = temp.path().join("clone");
        git(
            temp.path(),
            &[
                "clone",
                "-q",
                "--no-local",
                "--no-checkout",
                "--filter=blob:none",
                &format!("file://{}", source.display()),
                clone.to_str().unwrap(),
            ],
        );
        git(
            &clone,
            &[
                "remote",
                "set-url",
                "origin",
                &format!("{}/repo.git", canary.url()),
            ],
        );
        let path = system_path();
        let variables = base_environment(&temp.path().join("home"));
        let command = "git cat-file -p HEAD:file";

        run_unprotected(command, &clone, &path, &variables);
        assert!(
            !canary.requests().is_empty(),
            "fixture is insensitive: reading a missing blob without GIT_NO_LAZY_FETCH never \
             contacted the promisor remote"
        );

        canary.reset();
        let ran = run_as_generator(command, &clone, &path, &variables);
        assert!(!ran.success, "the blob is not local, the read must fail");
        assert_eq!(canary.requests(), Vec::<String>::new());
    }

    #[test]
    fn the_whole_table_reaches_the_generator_process() {
        let temp = tempfile::tempdir().unwrap();
        let mut variables = base_environment(&temp.path().join("home"));
        variables.insert("DOCKER_HOST".to_owned(), "tcp://127.0.0.1:1".to_owned());
        variables.insert("GOPROXY".to_owned(), "https://proxy.example".to_owned());
        let ran = run_as_generator("env", temp.path(), "/usr/bin:/bin", &variables);
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
