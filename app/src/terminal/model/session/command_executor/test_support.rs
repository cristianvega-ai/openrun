//! Shared fixtures for the tests that run real tools against a loopback canary through the real
//! generator execution path (`SessionContext::execute_command_at_pwd` into
//! `LocalCommandExecutor`). Used by the offline-environment and network-sandbox tests so both
//! prove their layer on the same scenarios.

use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::os::unix::fs::PermissionsExt as _;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use command::blocking::Command;
use typed_path::TypedPathBuf;
use warp_completer::completer::{CommandExitStatus, GeneratorContext as _};
use warp_completer::signatures::CommandRegistry;

use crate::completer::SessionContext;
use crate::terminal::model::session::{LocalCommandExecutor, Session, SessionInfo};
use crate::terminal::shell::ShellType;

/// A loopback HTTP server that answers 404 to everything and remembers each request line.
pub struct Canary {
    address: SocketAddr,
    requests: Arc<Mutex<Vec<String>>>,
    stop: Arc<AtomicBool>,
}

const NOT_FOUND: &str = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";

impl Canary {
    pub fn start() -> Self {
        Self::start_with_response(NOT_FOUND)
    }

    /// A canary that asks every client for basic-auth credentials.
    pub fn start_requiring_login() -> Self {
        Self::start_with_response(
            "HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=\"canary\"\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
        )
    }

    fn start_with_response(response: &'static str) -> Self {
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
                            std::thread::spawn(move || serve(stream, &requests, response));
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

    pub fn url(&self) -> String {
        format!("http://{}", self.address)
    }

    pub fn port(&self) -> u16 {
        self.address.port()
    }

    pub fn requests(&self) -> Vec<String> {
        self.requests.lock().unwrap().clone()
    }

    pub fn reset(&self) {
        self.requests.lock().unwrap().clear();
    }
}

impl Drop for Canary {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
    }
}

fn serve(mut stream: TcpStream, requests: &Mutex<Vec<String>>, response: &str) {
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
    let _ = stream.write_all(response.as_bytes());
}

pub fn find_tool(name: &str) -> Option<PathBuf> {
    std::env::var_os("PATH").and_then(|paths| {
        std::env::split_paths(&paths)
            .map(|dir| dir.join(name))
            .find(|candidate| candidate.is_file())
    })
}

/// The executable of a shell that a local session of that type is launched with, or `None`
/// outside CI with a message saying the test is skipped. With `CI` set a missing shell fails
/// the test: a run that skips fish and PowerShell proves nothing about them.
/// `OPENRUN_TEST_FISH` and `OPENRUN_TEST_PWSH` name an executable that is not on `PATH`.
pub fn session_shell(name: &str, override_variable: &str) -> Option<PathBuf> {
    let found = match std::env::var_os(override_variable) {
        Some(path) => Some(PathBuf::from(path)).filter(|path| path.is_file()),
        None => {
            let path_dirs = std::env::var_os("PATH").unwrap_or_default();
            std::env::split_paths(&path_dirs)
                .chain(
                    ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
                        .into_iter()
                        .map(PathBuf::from),
                )
                .map(|dir| dir.join(name))
                .find(|candidate| candidate.is_file())
        }
    };
    let in_ci = std::env::var_os("CI").is_some_and(|value| !value.is_empty() && value != "false");
    if found.is_none() {
        assert!(
            !in_ci,
            "{name} is not installed and CI is set: the session shell tests must run in {name} \
             (install it on the runner or set {override_variable})"
        );
        eprintln!(
            "SKIPPED: {name} is not installed, so its session shell test does not run here (CI \
             installs it and fails without it; set {override_variable} to run it)"
        );
    }
    found
}

/// Tools whose absence on a CI runner is a failure, not a skip: the tests that use them are the
/// evidence for the generator policy, and a skipped test is no evidence.
const REQUIRED_ON_CI: &[&str] = &["git", "npm", "corepack", "rustup", "docker", "python3"];

/// Tools the Linux runners ship and the macOS runners do not.
const REQUIRED_ON_LINUX_CI: &[&str] = &["go", "gcloud"];

/// The tool's path, or `None` after saying why the test is skipped. On CI (`CI=true`), a tool in
/// [`REQUIRED_ON_CI`] (or, on Linux, [`REQUIRED_ON_LINUX_CI`]) that is missing fails the test
/// instead.
pub fn require_tool(name: &str) -> Option<PathBuf> {
    let tool = find_tool(name);
    if tool.is_none() {
        assert!(
            !(std::env::var("CI").is_ok_and(|ci| ci == "true")
                && (REQUIRED_ON_CI.contains(&name)
                    || (cfg!(target_os = "linux") && REQUIRED_ON_LINUX_CI.contains(&name)))),
            "{name} is not installed on this CI runner, so the real-tool tests that need it \
             would pass without testing anything"
        );
        eprintln!("SKIPPED: {name} is not installed on this machine");
    }
    tool
}

pub fn system_path() -> String {
    std::env::var("PATH").unwrap_or_else(|_| "/usr/bin:/bin".to_owned())
}

/// Variables that make the tools under test hermetic and sensitive; applied identically to the
/// control and the protected run so the only difference between them is the layer under test.
pub fn base_environment(home: &Path) -> HashMap<String, String> {
    HashMap::from([
        ("HOME".to_owned(), home.to_string_lossy().into_owned()),
        // CI systems set CI=true, which silences npm's update notifier and the like.
        ("CI".to_owned(), "false".to_owned()),
        ("RUSTUP_TOOLCHAIN".to_owned(), String::new()),
    ])
}

/// The result of one run.
pub struct Ran {
    pub success: bool,
    pub output: String,
}

/// Runs `command` through the real generator path: a `Session` backed by `executor`, reached
/// through `SessionContext::execute_command_at_pwd`.
pub fn run_as_generator(
    executor: LocalCommandExecutor,
    command: &str,
    cwd: &Path,
    path: &str,
    variables: &HashMap<String, String>,
) -> Ran {
    let session = Session::new(
        SessionInfo::new_for_test().with_path(Some(path.to_owned())),
        Arc::new(executor),
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

/// The same shell the executor uses, with the same variables, and no offline table or sandbox.
pub fn run_unprotected(
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

pub fn git(dir: &Path, args: &[&str]) {
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

/// How a scenario's control run must behave.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Control {
    /// Every command must reach the canary (or run the marker program) without the layer.
    EveryCommand,
    /// At least one command must.
    SomeCommand,
}

/// A real tool in a fixture set up so that, left alone, it reaches the canary (or runs the
/// marker program).
pub struct Scenario {
    pub name: &'static str,
    pub cwd: PathBuf,
    pub path: String,
    pub variables: HashMap<String, String>,
    pub commands: Vec<String>,
    pub control: Control,
    /// Directories the tool writes state into; emptied before every run so the control run
    /// cannot make the protected run look quiet.
    pub state_dirs: Vec<PathBuf>,
    /// A file, or a directory, that the tool's hooks create entries in when they run.
    pub marker: Option<PathBuf>,
    /// How long to wait for a tool that reports in the background.
    pub settle: Duration,
    _temp: tempfile::TempDir,
}

impl Scenario {
    pub fn reset(&self, canary: &Canary) {
        canary.reset();
        if let Some(marker) = &self.marker {
            if marker.is_dir() {
                let _ = std::fs::remove_dir_all(marker);
                std::fs::create_dir_all(marker).unwrap();
            } else {
                let _ = std::fs::remove_file(marker);
            }
        }
        for dir in &self.state_dirs {
            let _ = std::fs::remove_dir_all(dir);
            std::fs::create_dir_all(dir).unwrap();
        }
    }

    pub fn reached(&self, canary: &Canary) -> bool {
        std::thread::sleep(self.settle);
        !canary.requests().is_empty() || self.ran_a_hook()
    }

    /// Which hooks ran (the names of the files in the marker directory, or the marker file).
    pub fn ran_hooks(&self) -> Vec<String> {
        match &self.marker {
            Some(marker) if marker.is_dir() => std::fs::read_dir(marker)
                .map(|entries| {
                    entries
                        .flatten()
                        .map(|entry| entry.file_name().to_string_lossy().into_owned())
                        .collect()
                })
                .unwrap_or_default(),
            Some(marker) if marker.exists() => vec![marker.display().to_string()],
            _ => Vec::new(),
        }
    }

    pub fn ran_a_hook(&self) -> bool {
        !self.ran_hooks().is_empty()
    }

    /// Runs every command without the layer under test and checks the fixture is sensitive.
    pub fn assert_control_reaches(&self, canary: &Canary) {
        let mut any = false;
        for command in &self.commands {
            self.reset(canary);
            run_unprotected(command, &self.cwd, &self.path, &self.variables);
            let reached = self.reached(canary);
            any |= reached;
            assert!(
                reached || self.control == Control::SomeCommand,
                "fixture is insensitive: `{command}` ({}) without the layer never reached the \
                 canary or ran the marker program",
                self.name
            );
        }
        assert!(any, "fixture is insensitive: {}", self.name);
    }

    /// Runs every command without the offline table or the sandbox but with the one variable
    /// `name=value` set, and asserts nothing reached the canary or ran the marker program: the
    /// variable on its own is enough.
    pub fn assert_silent_with_variable(&self, canary: &Canary, name: &str, value: &str) {
        let mut variables = self.variables.clone();
        variables.insert(name.to_owned(), value.to_owned());
        self.assert_silent_with_variables(canary, &variables, name);
    }

    /// Like [`Self::assert_silent_with_variable`], for git's `GIT_CONFIG_*` pair form of a
    /// config override.
    pub fn assert_silent_with_git_config(&self, canary: &Canary, key: &str, value: &str) {
        let mut variables = self.variables.clone();
        variables.insert("GIT_CONFIG_COUNT".to_owned(), "1".to_owned());
        variables.insert("GIT_CONFIG_KEY_0".to_owned(), key.to_owned());
        variables.insert("GIT_CONFIG_VALUE_0".to_owned(), value.to_owned());
        self.assert_silent_with_variables(canary, &variables, key);
    }

    fn assert_silent_with_variables(
        &self,
        canary: &Canary,
        variables: &HashMap<String, String>,
        what: &str,
    ) {
        for command in &self.commands {
            self.reset(canary);
            run_unprotected(command, &self.cwd, &self.path, variables);
            assert!(
                !self.reached(canary),
                "`{command}` ({}) still reached the canary or ran a repository program with only \
                 {what} set; requests: {:?}, hooks: {:?}",
                self.name,
                canary.requests(),
                self.ran_hooks()
            );
        }
    }

    /// Runs every command through `executor()` and asserts nothing reached the canary or ran the
    /// marker program. Returns the outputs.
    pub fn assert_silent_through(
        &self,
        canary: &Canary,
        executor: impl Fn() -> LocalCommandExecutor,
    ) -> Vec<Ran> {
        self.commands
            .iter()
            .map(|command| {
                self.reset(canary);
                let ran =
                    run_as_generator(executor(), command, &self.cwd, &self.path, &self.variables);
                assert!(
                    !self.reached(canary),
                    "`{command}` ({}) reached the network or ran the marker program through the \
                     generator path; requests: {:?}\n{}",
                    self.name,
                    canary.requests(),
                    ran.output
                );
                ran
            })
            .collect()
    }
}

pub fn commands(commands: &[&str]) -> Vec<String> {
    commands
        .iter()
        .map(|command| (*command).to_owned())
        .collect()
}

pub fn production_executor() -> LocalCommandExecutor {
    LocalCommandExecutor::new(Some("/bin/bash".into()), ShellType::Bash)
}

pub fn rustup_scenario(canary: &Canary) -> Option<Scenario> {
    let rustup = require_tool("rustup")?;
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

    let rustup_home = temp.path().join("rustup-home");
    let cargo_home = temp.path().join("cargo-home");
    let mut variables = base_environment(&temp.path().join("home"));
    variables.insert(
        "RUSTUP_HOME".to_owned(),
        rustup_home.to_string_lossy().into_owned(),
    );
    variables.insert(
        "CARGO_HOME".to_owned(),
        cargo_home.to_string_lossy().into_owned(),
    );
    variables.insert("RUSTUP_DIST_SERVER".to_owned(), canary.url());
    variables.insert("RUSTUP_UPDATE_ROOT".to_owned(), canary.url());
    // The setting the issue says does not help.
    variables.insert("CARGO_NET_OFFLINE".to_owned(), "true".to_owned());

    Some(Scenario {
        name: "rustup proxies with a pinned, uninstalled toolchain",
        cwd: project,
        path,
        variables,
        commands: commands(&[
            "cargo metadata --format-version 1 --no-deps",
            "rustc --print target-list",
            "cargo read-manifest",
            "cargo install --list",
            "rustup docs --path",
        ]),
        control: Control::EveryCommand,
        state_dirs: vec![rustup_home, cargo_home],
        marker: None,
        settle: Duration::ZERO,
        _temp: temp,
    })
}

pub fn npm_scenario(canary: &Canary) -> Option<Scenario> {
    let npm = require_tool("npm")?;
    let temp = tempfile::tempdir().unwrap();
    let project = temp.path().join("project");
    std::fs::create_dir_all(&project).unwrap();
    std::fs::write(
        project.join("package.json"),
        r#"{"name":"fixture","version":"1.0.0"}"#,
    )
    .unwrap();
    let path = format!("{}:{}", npm.parent().unwrap().display(), system_path());

    let home = temp.path().join("home");
    let cache = temp.path().join("cache");
    let mut variables = base_environment(&home);
    variables.insert("npm_config_registry".to_owned(), canary.url());
    variables.insert(
        "npm_config_cache".to_owned(),
        cache.to_string_lossy().into_owned(),
    );
    // The setting the issue says does not help.
    variables.insert("NO_UPDATE_NOTIFIER".to_owned(), "1".to_owned());

    Some(Scenario {
        name: "npm update notifier",
        cwd: project,
        path,
        variables,
        commands: commands(&["npm prefix"]),
        control: Control::EveryCommand,
        state_dirs: vec![home, cache],
        marker: None,
        // npm reports its update check after the command's own output.
        settle: Duration::from_millis(1500),
        _temp: temp,
    })
}

pub fn corepack_scenario(canary: &Canary) -> Option<Scenario> {
    let corepack = require_tool("corepack")?;
    let temp = tempfile::tempdir().unwrap();
    let project = temp.path().join("project");
    std::fs::create_dir_all(&project).unwrap();
    std::fs::write(
        project.join("package.json"),
        r#"{"name":"fixture","packageManager":"yarn@4.5.0"}"#,
    )
    .unwrap();
    let path = format!("{}:{}", corepack.parent().unwrap().display(), system_path());

    let corepack_home = temp.path().join("corepack");
    let mut variables = base_environment(&temp.path().join("home"));
    variables.insert("COREPACK_NPM_REGISTRY".to_owned(), canary.url());
    variables.insert(
        "COREPACK_HOME".to_owned(),
        corepack_home.to_string_lossy().into_owned(),
    );

    Some(Scenario {
        name: "corepack pinned package manager",
        cwd: project,
        path,
        variables,
        commands: commands(&["corepack yarn --version"]),
        control: Control::EveryCommand,
        state_dirs: vec![corepack_home],
        marker: None,
        settle: Duration::ZERO,
        _temp: temp,
    })
}

/// A partial clone whose promisor remote is the canary and whose blob is not local.
pub fn git_lazy_fetch_scenario(canary: &Canary) -> Option<Scenario> {
    require_tool("git")?;
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

    Some(Scenario {
        name: "git lazy fetch from a promisor remote",
        cwd: clone,
        path: system_path(),
        variables: base_environment(&temp.path().join("home")),
        commands: commands(&["git cat-file -p HEAD:file"]),
        control: Control::EveryCommand,
        state_dirs: vec![],
        marker: None,
        settle: Duration::ZERO,
        _temp: temp,
    })
}

/// A repository whose config makes git run a program on index-reading commands.
pub fn git_fsmonitor_scenario() -> Option<Scenario> {
    require_tool("git")?;
    let temp = tempfile::tempdir().unwrap();
    let repo = temp.path().join("repo");
    std::fs::create_dir_all(&repo).unwrap();
    git(&repo, &["init", "-q"]);
    let marker = temp.path().join("fsmonitor-ran");
    let hook = temp.path().join("fsmonitor-hook.sh");
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

    Some(Scenario {
        name: "git core.fsmonitor program",
        cwd: repo,
        path: system_path(),
        variables: base_environment(&temp.path().join("home")),
        commands: commands(&[
            "git status --porcelain",
            "git --no-optional-locks branch --no-color",
            "git diff",
            "git ls-files",
        ]),
        control: Control::SomeCommand,
        state_dirs: vec![],
        marker: Some(marker),
        settle: Duration::ZERO,
        _temp: temp,
    })
}

/// A repository whose config and hooks make git run five different programs on read commands:
/// `core.fsmonitor`, a `clean` filter, `diff.external`, a textconv driver and the
/// `post-index-change` hook. Each appends its name to a file in the marker directory. The file
/// `f` is modified right after the index was written, with the index's own modification time,
/// so that git has to run the clean filter to learn whether it changed.
pub fn git_hostile_repository_scenario() -> Option<Scenario> {
    require_tool("git")?;
    let temp = tempfile::tempdir().unwrap();
    let markers = temp.path().join("markers");
    std::fs::create_dir_all(&markers).unwrap();
    let repo = temp.path().join("repo");
    std::fs::create_dir_all(&repo).unwrap();
    git(&repo, &["init", "-q"]);

    let hook = |name: &str, body: &str| {
        let path = temp.path().join(format!("{name}.sh"));
        std::fs::write(
            &path,
            format!(
                "#!/bin/sh\necho x >> '{}/{name}'\n{body}",
                markers.display()
            ),
        )
        .unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        path
    };
    let fsmonitor = hook("fsmonitor", "printf '\\0'\n");
    let clean = hook("clean", "cat\n");
    let external = hook("external", "");
    let textconv = hook("textconv", "cat \"$1\"\n");
    let post_index_change = hook("post-index-change", "");

    std::fs::write(repo.join(".gitattributes"), "f filter=evil diff=evil\n").unwrap();
    std::fs::write(repo.join("f"), "one\n").unwrap();
    git(&repo, &["add", "-A"]);
    git(&repo, &["commit", "-qm", "one"]);
    for (key, value) in [
        ("core.fsmonitor", &fsmonitor),
        ("filter.evil.clean", &clean),
        ("diff.external", &external),
        ("diff.evil.textconv", &textconv),
    ] {
        git(&repo, &["config", key, value.to_str().unwrap()]);
    }
    std::fs::create_dir_all(repo.join(".git/hooks")).unwrap();
    std::fs::copy(
        &post_index_change,
        repo.join(".git/hooks/post-index-change"),
    )
    .unwrap();
    // Same size, same modification time as the index: git can only tell by running the filter.
    std::fs::write(repo.join("f"), "two\n").unwrap();
    let status = Command::new("touch")
        .args(["-r", ".git/index", "f"])
        .current_dir(&repo)
        .status()
        .unwrap();
    assert!(status.success());
    // Setting up ran some of the hooks already.
    let _ = std::fs::remove_dir_all(&markers);
    std::fs::create_dir_all(&markers).unwrap();

    Some(Scenario {
        name: "git repository with fsmonitor, filter, external diff, textconv and hook",
        cwd: repo,
        path: system_path(),
        variables: base_environment(&temp.path().join("home")),
        commands: Vec::new(),
        control: Control::SomeCommand,
        state_dirs: vec![],
        marker: Some(markers),
        settle: Duration::ZERO,
        _temp: temp,
    })
}

/// Docker pointed at the canary twice: through `DOCKER_HOST`, and through a docker context whose
/// endpoint is the canary and that is the current one. Left alone the CLI pings the canary
/// before anything else. Empty when docker is not installed.
pub fn docker_scenarios(canary: &Canary) -> Vec<Scenario> {
    let Some(docker) = require_tool("docker") else {
        return Vec::new();
    };
    let mut scenarios = Vec::new();
    for (name, via_context) in [
        ("docker with a remote DOCKER_HOST", false),
        ("docker with a remote current context", true),
    ] {
        let temp = tempfile::tempdir().unwrap();
        let home = temp.path().join("home");
        let config = temp.path().join("docker-config");
        std::fs::create_dir_all(&home).unwrap();
        std::fs::create_dir_all(&config).unwrap();
        let mut variables = base_environment(&home);
        variables.insert(
            "DOCKER_CONFIG".to_owned(),
            config.to_string_lossy().into_owned(),
        );
        let endpoint = format!("tcp://127.0.0.1:{}", canary.port());
        if via_context {
            let status = Command::new(&docker)
                .args(["context", "create", "remote", "--docker"])
                .arg(format!("host={endpoint}"))
                .envs(&variables)
                .output()
                .unwrap();
            assert!(
                status.status.success(),
                "docker context create failed: {}",
                String::from_utf8_lossy(&status.stderr)
            );
            variables.insert("DOCKER_CONTEXT".to_owned(), "remote".to_owned());
        } else {
            variables.insert("DOCKER_HOST".to_owned(), endpoint);
        }
        scenarios.push(Scenario {
            name,
            cwd: temp.path().to_path_buf(),
            path: format!("{}:{}", docker.parent().unwrap().display(), system_path()),
            variables,
            commands: Vec::new(),
            control: Control::EveryCommand,
            state_dirs: vec![],
            marker: None,
            settle: Duration::ZERO,
            _temp: temp,
        });
    }
    scenarios
}

/// The shell commands of the bundled spec `spec`'s generators that are plain scripts (no typed
/// tokens), as `(generator, command)`.
pub fn bundled_script_commands(spec: &str) -> Vec<(String, String)> {
    let data = warp_command_signatures::dynamic_command_signature_data();
    let Some(spec_data) = data.get(spec) else {
        return Vec::new();
    };
    spec_data
        .generators()
        .iter()
        .filter_map(|(name, generator)| match &generator.process {
            warp_command_signatures::GeneratorProcess::ShellCommand(command) => Some((
                name.0.clone(),
                command
                    .build(warp_command_signatures::Shell::Posix)
                    .to_string(),
            )),
            _ => None,
        })
        .collect()
}

fn go_project(
    temp: &tempfile::TempDir,
    go_mod: &str,
) -> (PathBuf, PathBuf, PathBuf, HashMap<String, String>) {
    let project = temp.path().join("project");
    std::fs::create_dir_all(&project).unwrap();
    std::fs::write(project.join("go.mod"), go_mod).unwrap();
    std::fs::write(project.join("main.go"), "package main\n\nfunc main() {}\n").unwrap();
    let gopath = temp.path().join("gopath");
    let gocache = temp.path().join("gocache");
    let mut variables = base_environment(&temp.path().join("home"));
    variables.insert("GOPATH".to_owned(), gopath.to_string_lossy().into_owned());
    variables.insert(
        "GOMODCACHE".to_owned(),
        gopath.join("mod").to_string_lossy().into_owned(),
    );
    variables.insert("GOCACHE".to_owned(), gocache.to_string_lossy().into_owned());
    variables.insert("GOFLAGS".to_owned(), "-mod=mod".to_owned());
    variables.insert("GOSUMDB".to_owned(), "off".to_owned());
    (project, gopath, gocache, variables)
}

/// A module that requires a dependency nobody has cached, with the canary as GOPROXY.
pub fn go_modules_scenario(canary: &Canary) -> Option<Scenario> {
    let go = require_tool("go")?;
    let temp = tempfile::tempdir().unwrap();
    let (project, gopath, gocache, mut variables) = go_project(
        &temp,
        "module fixture\n\ngo 1.21\n\nrequire example.com/dependency v1.0.0\n",
    );
    variables.insert("GOPROXY".to_owned(), canary.url());
    variables.insert("GOTOOLCHAIN".to_owned(), "local".to_owned());
    Some(Scenario {
        name: "go fetching an uncached module through GOPROXY",
        cwd: project,
        path: format!("{}:{}", go.parent().unwrap().display(), system_path()),
        variables,
        commands: commands(&["go list -m all"]),
        control: Control::EveryCommand,
        state_dirs: vec![gopath, gocache],
        marker: None,
        settle: Duration::ZERO,
        _temp: temp,
    })
}

/// A module whose `go` line asks for a Go far newer than any installed, with `GOTOOLCHAIN=auto`
/// and the canary as GOPROXY: `go` downloads the toolchain through the proxy.
pub fn go_toolchain_scenario(canary: &Canary) -> Option<Scenario> {
    let go = require_tool("go")?;
    let temp = tempfile::tempdir().unwrap();
    let (project, gopath, gocache, mut variables) =
        go_project(&temp, "module fixture\n\ngo 1.99.0\n");
    variables.insert("GOPROXY".to_owned(), canary.url());
    variables.insert("GOTOOLCHAIN".to_owned(), "auto".to_owned());
    Some(Scenario {
        name: "go downloading the toolchain a go.mod asks for",
        cwd: project,
        path: format!("{}:{}", go.parent().unwrap().display(), system_path()),
        variables,
        commands: commands(&["go list -m"]),
        control: Control::EveryCommand,
        state_dirs: vec![gopath, gocache],
        marker: None,
        settle: Duration::ZERO,
        _temp: temp,
    })
}

/// A repository whose `.git/hooks` write a marker, and the commands that make git run them.
pub fn git_hooks_scenario() -> Option<Scenario> {
    require_tool("git")?;
    let temp = tempfile::tempdir().unwrap();
    let markers = temp.path().join("markers");
    std::fs::create_dir_all(&markers).unwrap();
    let repo = temp.path().join("repo");
    std::fs::create_dir_all(&repo).unwrap();
    git(&repo, &["init", "-q"]);
    std::fs::write(repo.join("tracked"), "one\n").unwrap();
    git(&repo, &["add", "tracked"]);
    git(&repo, &["commit", "-qm", "one"]);
    let hooks = repo.join(".git/hooks");
    std::fs::create_dir_all(&hooks).unwrap();
    for name in [
        "post-index-change",
        "reference-transaction",
        "pre-commit",
        "post-checkout",
        "post-merge",
        "pre-auto-gc",
    ] {
        let path = hooks.join(name);
        std::fs::write(
            &path,
            format!("#!/bin/sh\necho x >> '{}/{name}'\n", markers.display()),
        )
        .unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
    }
    let _ = std::fs::remove_dir_all(&markers);
    std::fs::create_dir_all(&markers).unwrap();
    Some(Scenario {
        name: "git repository with hooks",
        cwd: repo,
        path: system_path(),
        variables: base_environment(&temp.path().join("home")),
        // A ref update runs `reference-transaction`; adding a file writes the index and runs
        // `post-index-change`. Neither is a generator command: they show the hooks are live.
        commands: commands(&[
            "git branch hook-check-$$",
            "touch hook-file-$$ && git add hook-file-$$",
        ]),
        control: Control::EveryCommand,
        state_dirs: vec![],
        marker: Some(markers),
        settle: Duration::ZERO,
        _temp: temp,
    })
}

/// Points every proxy variable at the canary, so that a tool which reports home from a fixed
/// host (telemetry, an update check) sends that request to the canary instead.
pub fn route_traffic_to_canary(variables: &mut HashMap<String, String>, canary: &Canary) {
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
}
