//! Evidence for the git completion generators that run where no network sandbox exists (Windows;
//! `ALLOWED_ON_WINDOWS_WITH_ENVIRONMENT` in `warp_completer`). On Windows the offline environment
//! table is the only layer between a repository and the network or a program it names, so each
//! command of every generator on that list is run through the production executor
//! (`SessionContext::execute_command_at_pwd` into `LocalCommandExecutor`, sandbox off) against
//!
//! * a repository whose config names a program for `core.fsmonitor`, the `clean` filter, an
//!   external diff, a textconv driver and `gpg.program` (with `log.showSignature` on and a commit
//!   that has a `gpgsig` header), and whose `post-index-change` hook is a program, and
//! * a partial clone (`--filter=tree:0`) whose promisor remote is a loopback listener that counts
//!   connections.
//!
//! Every program writes a marker file. Each command is first run without the table to show the
//! fixture does fire, then with it and must leave no marker and make no connection. The tests run
//! on every host: PowerShell (5.1 and 7) on Windows, bash elsewhere. Git must be installed; with
//! `CI` set a missing git, or a missing PowerShell on Windows, fails the test instead of skipping.

use std::collections::{BTreeSet, HashMap};
use std::io::Write as _;
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::time::Duration;

use command::blocking::Command;
use typed_path::TypedPathBuf;
use warp_command_signatures::{GeneratorProcess, Shell};
use warp_completer::completer::{
    CommandExitStatus, CompleterOptions, CompletionsFallbackStrategy, GeneratorContext as _,
    MatchStrategy, suggestions,
};
use warp_completer::signatures::{CommandRegistry, local_git_generators};

use super::network_sandbox::NetworkSandbox;
use super::{CommandExecutor, LocalCommandExecutor, offline_environment};
use crate::completer::SessionContext;
use crate::terminal::model::session::{Session, SessionInfo};
use crate::terminal::shell::ShellType;

fn in_ci() -> bool {
    std::env::var("CI").is_ok_and(|ci| ci == "true")
}

fn executable_name(name: &str) -> String {
    name.to_owned()
}

fn find_on_path(name: &str) -> Option<PathBuf> {
    let file = executable_name(name);
    std::env::split_paths(&std::env::var_os("PATH")?)
        .map(|dir| dir.join(&file))
        .find(|candidate| candidate.is_file())
}

/// Whether git is installed. A missing git fails the test on CI and skips it elsewhere.
fn git_is_installed() -> bool {
    let found = find_on_path("git").is_some();
    if !found {
        assert!(
            !in_ci(),
            "git is not installed on this CI runner, so the git completion tests would pass \
             without testing anything"
        );
        eprintln!("SKIPPED: git is not installed on this machine");
    }
    found
}

/// The path with forward slashes, which git and `sh` accept on every platform.
fn slash(path: &Path) -> String {
    path.to_string_lossy().replace('\\', "/")
}

fn null_device() -> &'static str {
    "/dev/null"
}

/// A loopback listener that counts the connections made to it and answers none of them.
struct Listener {
    port: u16,
    connections: Arc<AtomicUsize>,
    stop: Arc<AtomicBool>,
}

impl Listener {
    fn start() -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        listener.set_nonblocking(true).unwrap();
        let port = listener.local_addr().unwrap().port();
        let connections = Arc::new(AtomicUsize::new(0));
        let stop = Arc::new(AtomicBool::new(false));
        {
            let connections = connections.clone();
            let stop = stop.clone();
            std::thread::spawn(move || {
                while !stop.load(Ordering::Relaxed) {
                    match listener.accept() {
                        Ok(_) => {
                            connections.fetch_add(1, Ordering::Relaxed);
                        }
                        Err(_) => std::thread::sleep(Duration::from_millis(5)),
                    }
                }
            });
        }
        Self {
            port,
            connections,
            stop,
        }
    }

    fn url(&self) -> String {
        format!("http://127.0.0.1:{}/repo.git", self.port)
    }

    fn connections(&self) -> usize {
        self.connections.load(Ordering::Relaxed)
    }
}

impl Drop for Listener {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
    }
}

/// The environment of git invocations that set the fixture up and of the sessions under test:
/// no user or system config, an identity, and no prompts.
fn base_environment(home: &Path) -> HashMap<String, String> {
    [
        ("HOME", slash(home)),
        ("GIT_CONFIG_GLOBAL", null_device().to_owned()),
        ("GIT_CONFIG_SYSTEM", null_device().to_owned()),
        ("GIT_AUTHOR_NAME", "n".to_owned()),
        ("GIT_AUTHOR_EMAIL", "n@example.com".to_owned()),
        ("GIT_COMMITTER_NAME", "n".to_owned()),
        ("GIT_COMMITTER_EMAIL", "n@example.com".to_owned()),
    ]
    .into_iter()
    .map(|(name, value)| (name.to_owned(), value))
    .collect()
}

fn git_output(dir: &Path, args: &[&str], environment: &HashMap<String, String>) -> String {
    git_with_input(dir, args, environment, "")
}

fn git_with_input(
    dir: &Path,
    args: &[&str],
    environment: &HashMap<String, String>,
    input: &str,
) -> String {
    let mut child = Command::new("git")
        .args(args)
        .current_dir(dir)
        .envs(environment)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(input.as_bytes())
        .unwrap();
    let output = child.wait_with_output().unwrap();
    assert!(
        output.status.success(),
        "git {args:?} failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8_lossy(&output.stdout).replace("\r\n", "\n")
}

struct Fixture {
    _temp: tempfile::TempDir,
    listener: Listener,
    markers: PathBuf,
    /// Runs git programs, a signed-looking commit, a staged file, a stash, a tag, a remote branch
    /// and an alias; its config names a program for each marker.
    hostile: PathBuf,
    /// A `--filter=tree:0` clone whose `HEAD` tree is not local and whose `origin` is the listener.
    partial: PathBuf,
    environment: HashMap<String, String>,
}

impl Fixture {
    /// `None` when git is not installed (and the test is skipped).
    fn new() -> Option<Self> {
        if !git_is_installed() {
            return None;
        }
        let temp = tempfile::tempdir().unwrap();
        let listener = Listener::start();
        let markers = temp.path().join("markers");
        std::fs::create_dir_all(&markers).unwrap();
        let environment = base_environment(&temp.path().join("home"));

        let hostile = temp.path().join("hostile");
        std::fs::create_dir_all(&hostile).unwrap();
        let git = |args: &[&str]| git_output(&hostile, args, &environment);
        git(&["init", "-q", "-b", "main"]);
        std::fs::write(hostile.join(".gitattributes"), "f filter=evil diff=evil\n").unwrap();
        std::fs::write(hostile.join("f"), "one\n").unwrap();
        git(&["add", "-A"]);
        git(&["commit", "-qm", "one"]);
        git(&["branch", "feature/x"]);
        git(&["tag", "v1"]);
        git(&["config", "alias.co", "checkout"]);
        git(&["config", "remote.origin.url", &listener.url()]);
        git(&[
            "config",
            "remote.origin.fetch",
            "+refs/heads/*:refs/remotes/origin/*",
        ]);
        git(&["update-ref", "refs/remotes/origin/main", "HEAD"]);
        std::fs::write(hostile.join("f"), "stash me\n").unwrap();
        git(&["stash", "push", "-q"]);
        std::fs::write(hostile.join("staged.txt"), "new\n").unwrap();
        git(&["add", "staged.txt"]);

        // A commit object with a `gpgsig` header: all `log.showSignature` needs to run the
        // configured program.
        let commit = git(&["cat-file", "commit", "HEAD"]);
        let (headers, message) = commit.split_once("\n\n").unwrap();
        let forged = format!(
            "{headers}\ngpgsig -----BEGIN PGP SIGNATURE-----\n \n abcd\n \
             -----END PGP SIGNATURE-----\n\n{message}"
        );
        let signed = git_with_input(
            &hostile,
            &["hash-object", "-t", "commit", "-w", "--stdin"],
            &environment,
            &forged,
        );
        git(&["update-ref", "refs/heads/main", signed.trim()]);

        let program = |name: &str, body: &str| {
            let path = temp.path().join(format!("{name}.sh"));
            std::fs::write(
                &path,
                format!("#!/bin/sh\necho x >> '{}/{name}'\n{body}", slash(&markers)),
            )
            .unwrap();
            {
                use std::os::unix::fs::PermissionsExt as _;
                std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
            }
            path
        };
        let fsmonitor = program("fsmonitor", "printf '\\0'\n");
        let clean = program("clean", "cat\n");
        let external = program("external", "");
        let textconv = program("textconv", "cat \"$1\"\n");
        let gpg = program("gpg", "exit 1\n");
        let post_index_change = program("post-index-change", "");
        let through_sh = |path: &Path| format!("sh '{}'", slash(path));
        for (key, value) in [
            ("core.fsmonitor", through_sh(&fsmonitor)),
            ("filter.evil.clean", through_sh(&clean)),
            ("diff.external", through_sh(&external)),
            ("diff.evil.textconv", through_sh(&textconv)),
            ("log.showSignature", "true".to_owned()),
            ("gpg.program", slash(&gpg)),
        ] {
            git(&["config", key, &value]);
        }
        std::fs::create_dir_all(hostile.join(".git/hooks")).unwrap();
        std::fs::copy(
            &post_index_change,
            hostile.join(".git/hooks/post-index-change"),
        )
        .unwrap();
        // Same size, same modification time as the index: git can only tell that `f` changed by
        // running the clean filter.
        std::fs::write(hostile.join("f"), "two\n").unwrap();
        let index_modified = std::fs::metadata(hostile.join(".git/index"))
            .and_then(|metadata| metadata.modified())
            .unwrap();
        std::fs::OpenOptions::new()
            .write(true)
            .open(hostile.join("f"))
            .and_then(|file| file.set_modified(index_modified))
            .unwrap();

        let source = temp.path().join("source");
        std::fs::create_dir_all(source.join("d")).unwrap();
        let in_source = |args: &[&str]| git_output(&source, args, &environment);
        in_source(&["init", "-q", "-b", "main"]);
        in_source(&["config", "uploadpack.allowFilter", "true"]);
        in_source(&["config", "uploadpack.allowAnySHA1InWant", "true"]);
        std::fs::write(source.join("d/file"), "contents\n").unwrap();
        in_source(&["add", "-A"]);
        in_source(&["commit", "-qm", "one"]);
        let partial = temp.path().join("partial");
        let source_url = { format!("file://{}", slash(&source)) };
        git_output(
            temp.path(),
            &[
                "clone",
                "-q",
                "--no-local",
                "--no-checkout",
                "--filter=tree:0",
                &source_url,
                &slash(&partial),
            ],
            &environment,
        );
        git_output(
            &partial,
            &["config", "remote.origin.url", &listener.url()],
            &environment,
        );

        let fixture = Self {
            _temp: temp,
            listener,
            markers,
            hostile,
            partial,
            environment,
        };
        fixture.reset();
        Some(fixture)
    }

    /// Forgets what the setup ran.
    fn reset(&self) {
        let _ = std::fs::remove_dir_all(&self.markers);
        std::fs::create_dir_all(&self.markers).unwrap();
        self.listener.connections.store(0, Ordering::Relaxed);
    }

    /// The programs that ran since the last reset, and `connection` if anything connected.
    fn effects(&self) -> BTreeSet<String> {
        std::thread::sleep(Duration::from_millis(100));
        let mut effects: BTreeSet<String> = std::fs::read_dir(&self.markers)
            .map(|entries| {
                entries
                    .flatten()
                    .map(|entry| entry.file_name().to_string_lossy().into_owned())
                    .collect()
            })
            .unwrap_or_default();
        if self.listener.connections() > 0 {
            effects.insert("connection".to_owned());
        }
        effects
    }
}

/// A shell a local session runs generator commands in, as `LocalCommandExecutor` starts it.
struct SessionShell {
    label: &'static str,
    path: PathBuf,
    shell_type: ShellType,
    family: Shell,
}

fn session_shells() -> Vec<SessionShell> {
    {
        vec![SessionShell {
            label: "bash",
            path: PathBuf::from("/bin/bash"),
            shell_type: ShellType::Bash,
            family: Shell::Posix,
        }]
    }
}

fn executor(shell: &SessionShell, offline_environment: bool) -> Arc<dyn CommandExecutor> {
    let executor = LocalCommandExecutor::new(Some(shell.path.clone()), shell.shell_type)
        .with_network_sandbox(NetworkSandbox::Off);
    Arc::new(if offline_environment {
        executor
    } else {
        executor.without_offline_environment()
    })
}

struct Ran {
    success: bool,
    output: String,
}

fn session_context(executor: Arc<dyn CommandExecutor>, cwd: &Path) -> SessionContext {
    let path = std::env::var("PATH").ok();
    let session = Session::new(SessionInfo::new_for_test().with_path(path), executor);
    SessionContext::new(
        session,
        CommandRegistry::global_instance(),
        TypedPathBuf::from(cwd.to_str().unwrap()),
    )
}

/// Runs `command` as a generator command: through a `Session` backed by `executor`, from `cwd`.
fn run_as_generator(
    executor: Arc<dyn CommandExecutor>,
    command: &str,
    cwd: &Path,
    variables: &HashMap<String, String>,
) -> Ran {
    let context = session_context(executor, cwd);
    let output = futures_lite::future::block_on(
        context.execute_command_at_pwd(command, Some(variables.clone())),
    )
    .expect("the generator command could not be started");
    let mut text = String::from_utf8_lossy(&output.stdout).into_owned();
    text.push_str(&String::from_utf8_lossy(&output.stderr));
    Ran {
        success: output.status == CommandExitStatus::Success,
        output: text.replace("\r\n", "\n"),
    }
}

/// The command the bundled spec of `(spec, generator)` runs in a shell of `family`.
fn bundled_command(spec: &str, generator: &str, family: Shell) -> String {
    let data = warp_command_signatures::dynamic_command_signature_data();
    let spec_data = data
        .get(spec)
        .unwrap_or_else(|| panic!("no bundled spec {spec}"));
    let (_, generator) = spec_data
        .generators()
        .iter()
        .find(|(name, _)| name.0 == generator)
        .unwrap_or_else(|| panic!("no generator {spec}/{generator}"));
    match &generator.process {
        GeneratorProcess::ShellCommand(command) => command.build(family).to_string(),
        GeneratorProcess::CommandFromTokens(command_from_tokens) => {
            command_from_tokens(&["git", "checkout", "ab"], false, &[])
                .build(family)
                .to_string()
        }
    }
}

/// What a command of the hostile repository must print (a substring), keyed by a part of the
/// command, so that the commands under test are shown to run and to parse in the shell.
const EXPECTED_OUTPUT: &[(&str, &str)] = &[
    ("branch --no-color --sort=-committerdate", "feature/x"),
    ("branch -a --no-color", "origin/main"),
    ("branch -r --no-color", "origin/main"),
    ("tag --list", "v1"),
    ("stash list", "stash@{0}"),
    ("remote -v", "origin"),
    (" remote", "origin"),
    ("rev-list --all --oneline", "one"),
    ("log --oneline", "one"),
    ("--get-regexp '^alias.'", "alias.co"),
    ("--get-regexp '.*'", "alias.co"),
    ("strip=3", "main"),
    ("strip=2", "origin/main"),
    ("ls-files", "staged.txt"),
    ("diff --cached --name-only", "staged.txt"),
    ("worktree list", "worktree "),
];

fn windows_git_commands(family: Shell) -> BTreeSet<String> {
    local_git_generators()
        .iter()
        .map(|(spec, generator)| bundled_command(spec, generator, family))
        .collect()
}

#[test]
fn the_git_generators_run_nothing_and_connect_nowhere_through_the_production_executor() {
    let Some(fixture) = Fixture::new() else {
        return;
    };
    for shell in session_shells() {
        let commands = windows_git_commands(shell.family);
        assert!(commands.len() > 15, "{commands:?}");
        let mut fired_without_the_table = BTreeSet::new();
        for (repository, root) in [("hostile", &fixture.hostile), ("partial", &fixture.partial)] {
            for command in &commands {
                fixture.reset();
                run_as_generator(executor(&shell, false), command, root, &fixture.environment);
                let control = fixture.effects();
                fired_without_the_table.extend(control.iter().cloned());

                fixture.reset();
                let ran =
                    run_as_generator(executor(&shell, true), command, root, &fixture.environment);
                let effects = fixture.effects();
                assert!(
                    effects.is_empty(),
                    "{}: `{command}` in the {repository} repository ran {effects:?} with the \
                     offline environment (without it: {control:?})\n{}",
                    shell.label,
                    ran.output
                );
                if repository == "hostile" {
                    assert!(
                        ran.success,
                        "{}: `{command}` failed in the hostile repository:\n{}",
                        shell.label, ran.output
                    );
                    for (needle, expected) in EXPECTED_OUTPUT {
                        if command.contains(needle) {
                            assert!(
                                ran.output.contains(expected),
                                "{}: `{command}` printed no {expected:?}:\n{}",
                                shell.label,
                                ran.output
                            );
                        }
                    }
                }
            }
        }
        for effect in ["fsmonitor", "gpg", "connection"] {
            assert!(
                fired_without_the_table.contains(effect),
                "{}: the fixture is insensitive, no command ever caused {effect:?} without the \
                 table (saw {fired_without_the_table:?})",
                shell.label
            );
        }
    }
}

#[test]
fn the_engine_completes_git_words_through_the_production_executor_and_runs_no_repository_code() {
    let Some(fixture) = Fixture::new() else {
        return;
    };
    let options = || CompleterOptions {
        match_strategy: MatchStrategy::CaseInsensitive,
        fallback_strategy: CompletionsFallbackStrategy::None,
        suggest_file_path_completions_only: false,
        parse_quotes_as_literals: false,
    };
    let complete = |shell: &SessionShell, line: &str, root: &Path| -> Vec<String> {
        let context = session_context(executor(shell, true), root);
        futures_lite::future::block_on(suggestions(
            line,
            line.len(),
            Some(&fixture.environment),
            options(),
            &context,
        ))
        .map(|results| {
            results
                .suggestions
                .into_iter()
                .map(|matched| matched.suggestion.display.to_string())
                .collect()
        })
        .unwrap_or_default()
    };
    for shell in session_shells() {
        fixture.reset();
        let branches = complete(&shell, "git checkout ", &fixture.hostile);
        assert!(
            branches.iter().any(|branch| branch == "feature/x"),
            "{}: `git checkout <Tab>` offered {branches:?}",
            shell.label
        );
        let tags = complete(&shell, "git tag -d ", &fixture.hostile);
        assert!(
            tags.iter().any(|tag| tag == "v1"),
            "{}: `git tag -d <Tab>` offered {tags:?}",
            shell.label
        );
        // The status-like generators stay off: nothing the working tree needs a filter for.
        complete(&shell, "git add ", &fixture.hostile);
        complete(&shell, "git diff ", &fixture.hostile);
        complete(&shell, "git restore ", &fixture.hostile);
        complete(&shell, "git checkout ", &fixture.partial);
        complete(&shell, "git show ", &fixture.partial);
        assert_eq!(
            fixture.effects(),
            BTreeSet::new(),
            "{}: completing ran repository code or connected",
            shell.label
        );
    }
}

/// Environment variable names are case-insensitive on Windows, and so is git's reading of
/// `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_<n>` and `GIT_CONFIG_VALUE_<n>` there. A session that
/// defines them in another spelling must still have its pair counted by the table, which appends
/// after it, and must not end up with two spellings of the count. On other hosts only the exact
/// spelling is a git variable, so only that one is run.
#[test]
fn a_session_pair_in_any_spelling_is_counted_and_the_table_still_applies() {
    let Some(fixture) = Fixture::new() else {
        return;
    };
    let spellings: &[[&str; 3]] = &[["GIT_CONFIG_COUNT", "GIT_CONFIG_KEY_0", "GIT_CONFIG_VALUE_0"]];
    let reads_the_index = "git --no-optional-locks ls-files";
    let reads_the_sessions_pair = "git config --get alias.zz";
    for shell in session_shells() {
        for [count, key, value] in spellings {
            let mut environment = fixture.environment.clone();
            environment.insert((*count).to_owned(), "1".to_owned());
            environment.insert((*key).to_owned(), "alias.zz".to_owned());
            environment.insert((*value).to_owned(), "status".to_owned());

            fixture.reset();
            let control = run_as_generator(
                executor(&shell, false),
                reads_the_index,
                &fixture.hostile,
                &environment,
            );
            assert!(
                fixture.effects().contains("fsmonitor"),
                "{}: fixture is insensitive with {count}: without the table the repository's \
                 fsmonitor did not run:\n{}",
                shell.label,
                control.output
            );

            fixture.reset();
            let ran = run_as_generator(
                executor(&shell, true),
                reads_the_index,
                &fixture.hostile,
                &environment,
            );
            assert!(ran.success, "{}: {count}: {}", shell.label, ran.output);
            assert_eq!(
                fixture.effects(),
                BTreeSet::new(),
                "{}: with the session defining {count}, the table did not stop fsmonitor",
                shell.label
            );

            let pair = run_as_generator(
                executor(&shell, true),
                reads_the_sessions_pair,
                &fixture.hostile,
                &environment,
            );
            assert_eq!(
                pair.output.trim(),
                "status",
                "{}: the session's own pair was overwritten with {count}",
                shell.label
            );
        }
    }
}

/// The table, as the executor applies it, laid over the base environment, for running git
/// without a shell.
fn table_environment(base: &HashMap<String, String>) -> HashMap<String, String> {
    let (variables, removals) = offline_environment::harden(Some(base.clone()));
    assert!(removals.is_empty() || removals == ["DOCKER_HOST"]);
    variables.unwrap()
}

fn run_git(dir: &Path, args: &[&str], environment: &HashMap<String, String>) {
    let _ = Command::new("git")
        .args(args)
        .current_dir(dir)
        .envs(environment)
        .stdin(Stdio::null())
        .output()
        .unwrap();
}

#[test]
fn git_log_does_not_run_the_repositorys_gpg_program() {
    let Some(fixture) = Fixture::new() else {
        return;
    };
    let commands: [&[&str]; 3] = [
        &["--no-optional-locks", "log", "--oneline"],
        &["--no-optional-locks", "stash", "list"],
        &["log", "-g", "--first-parent", "--format=%gd"],
    ];
    let mut control_fired = false;
    for args in commands {
        fixture.reset();
        run_git(&fixture.hostile, args, &fixture.environment);
        control_fired |= fixture.effects().contains("gpg");
    }
    assert!(
        control_fired,
        "fixture is insensitive: git log with log.showSignature never ran gpg.program"
    );
    let environment = table_environment(&fixture.environment);
    for args in commands {
        fixture.reset();
        run_git(&fixture.hostile, args, &environment);
        assert_eq!(fixture.effects(), BTreeSet::new(), "git {args:?}");
    }
}

#[test]
fn git_cannot_lazy_fetch_over_a_network_transport() {
    let Some(fixture) = Fixture::new() else {
        return;
    };
    let args: &[&str] = &["--no-optional-locks", "diff", "--cached", "--name-only"];
    fixture.reset();
    run_git(&fixture.partial, args, &fixture.environment);
    assert!(
        fixture.effects().contains("connection"),
        "fixture is insensitive: git did not lazy fetch the HEAD tree from the promisor remote"
    );

    let mut only_local_transports = fixture.environment.clone();
    only_local_transports.insert("GIT_ALLOW_PROTOCOL".to_owned(), "file".to_owned());
    fixture.reset();
    run_git(&fixture.partial, args, &only_local_transports);
    assert_eq!(
        fixture.effects(),
        BTreeSet::new(),
        "GIT_ALLOW_PROTOCOL=file alone must stop the lazy fetch of a git that ignores \
         GIT_NO_LAZY_FETCH"
    );

    fixture.reset();
    run_git(
        &fixture.partial,
        args,
        &table_environment(&fixture.environment),
    );
    assert_eq!(fixture.effects(), BTreeSet::new());
}

#[test]
fn git_no_lazy_fetch_stops_a_lazy_fetch() {
    let Some(fixture) = Fixture::new() else {
        return;
    };
    let version = git_output(&fixture.partial, &["--version"], &fixture.environment);
    let numbers: Vec<u32> = version
        .split_whitespace()
        .find(|word| word.starts_with(|c: char| c.is_ascii_digit()))
        .unwrap_or_default()
        .split('.')
        .map_while(|part| part.parse().ok())
        .collect();
    if numbers < vec![2, 44] {
        assert!(
            !in_ci(),
            "{version:?}: GIT_NO_LAZY_FETCH needs git 2.44, and this CI runner has older git"
        );
        eprintln!("SKIPPED: {version:?} predates GIT_NO_LAZY_FETCH (git 2.44)");
        return;
    }
    let mut environment = fixture.environment.clone();
    environment.insert("GIT_NO_LAZY_FETCH".to_owned(), "1".to_owned());
    fixture.reset();
    run_git(
        &fixture.partial,
        &["--no-optional-locks", "diff", "--cached", "--name-only"],
        &environment,
    );
    assert_eq!(fixture.effects(), BTreeSet::new());
}
