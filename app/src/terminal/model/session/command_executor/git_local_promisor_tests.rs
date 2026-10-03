//! Evidence that no git the gate accepts runs a repository's own program while a completion
//! generator reads history (Astra review 3, R3-02).
//!
//! The bug: git older than the May 2024 security releases ignores `GIT_NO_LAZY_FETCH`, so a
//! generator that reads an object a partial clone does not have still lazy-fetches it from the
//! promisor remote. With `GIT_ALLOW_PROTOCOL=file` (what the table set before) that is allowed
//! for a local path or `file://` URL, and the lazy fetch starts the `remote.<name>.uploadpack`
//! program named by the repository's config: project code, before anything is submitted.
//!
//! The fixture is a repository whose objects are all missing (so every generator command that
//! reads an object lazy-fetches) with a promisor remote that is a local path, a `file://` URL,
//! an `ext::` URL or an `ssh://` URL, and whose config names a program for `uploadpack` and for
//! `core.sshCommand`. Every program writes a marker file.
//!
//! For each git under test:
//!
//! * control 1: with a permissive protocol list and no `GIT_NO_LAZY_FETCH`, the lazy fetch must
//!   start every one of the programs (the fixture is sensitive, on every version);
//! * control 2: with the table as it was before this change (`GIT_ALLOW_PROTOCOL=file`,
//!   `GIT_NO_LAZY_FETCH=1`), a git that ignores `GIT_NO_LAZY_FETCH` must still run the
//!   `uploadpack` program (the bug reproduces);
//! * the claim: through the production `LocalCommandExecutor` with the table, even when the
//!   session's own environment allows every protocol, no program runs for any command of the
//!   local git generators, and every command still succeeds in a healthy repository (no false
//!   positive: a repository whose `origin` is a local path still lists its branches and remotes);
//! * the engine: completing `git reset ` and `git checkout ` through the production suggestions
//!   engine and executor runs no program, and the engine did run git generators (the version
//!   gate accepted this git).
//!
//! Which gits: the one on `PATH` always, plus every install prefix listed in `OPENRUN_TEST_GIT`
//! (colon-separated; each holds `bin/git` and `libexec/git-core`). CI builds git 2.31.0 (the
//! oldest the gate accepts), 2.43.0 and 2.44.0 (both ignore `GIT_NO_LAZY_FETCH`) and 2.43.4 (a
//! patched backport) from the official source tarballs and lists them there; see
//! `.github/actions/old-git`. A prefix that is listed but missing fails the test.
//! Missing required matrix versions exit 86; a run without them supplies no policy evidence.

use std::collections::{BTreeSet, HashMap};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use command::blocking::Command;
use typed_path::TypedPathBuf;
use warp_command_signatures::Shell;
use warp_completer::completer::{
    CommandExitStatus, CompleterOptions, CompletionsFallbackStrategy, GeneratorContext as _,
    GitVersion, MINIMUM_GIT_VERSION, MatchStrategy, suggestions,
};
use warp_completer::signatures::CommandRegistry;

use super::git_completion_tests::{base_environment, git_output, local_git_commands, slash};
use super::network_sandbox::NetworkSandbox;
use super::{CommandExecutor, LocalCommandExecutor};
use crate::completer::SessionContext;
use crate::terminal::model::session::{Session, SessionInfo};
use crate::terminal::shell::ShellType;

/// One git under test.
pub(super) struct GitInstall {
    label: String,
    /// `bin` of an install prefix, or `None` for the git on `PATH`.
    bin: Option<PathBuf>,
    /// `libexec/git-core` of an install prefix.
    exec_path: Option<PathBuf>,
    version: GitVersion,
    version_text: String,
}

impl GitInstall {
    pub(super) fn path(&self) -> String {
        let system = std::env::var("PATH").unwrap_or_else(|_| "/usr/bin:/bin".to_owned());
        match &self.bin {
            Some(bin) => format!("{}:{system}", bin.display()),
            None => system,
        }
    }

    /// Variables that make the commands run this git's helpers.
    pub(super) fn variables(&self) -> HashMap<String, String> {
        self.exec_path
            .iter()
            .map(|exec_path| ("GIT_EXEC_PATH".to_owned(), slash(exec_path)))
            .collect()
    }

    /// Whether this git is one of those the May 2024 security releases (2.45.1 and the
    /// backports 2.44.1, 2.43.4, 2.42.2, 2.41.1, 2.40.2, 2.39.4) did not reach: it ignores
    /// `GIT_NO_LAZY_FETCH`. `None` for a vendor build whose backports are not known (Apple Git).
    fn ignores_no_lazy_fetch(&self) -> Option<bool> {
        if self.version_text.contains("Apple") {
            return None;
        }
        let GitVersion {
            major,
            minor,
            patch,
        } = self.version;
        let fixed_patch = match (major, minor) {
            (2, 39) => 4,
            (2, 40) => 2,
            (2, 41) => 1,
            (2, 42) => 2,
            (2, 43) => 4,
            (2, 44) => 1,
            (2, 45) => 1,
            (2, minor) if minor > 45 => 0,
            (major, _) if major > 2 => 0,
            _ => u32::MAX,
        };
        Some(patch < fixed_patch)
    }
}

fn describe(label: String, bin: Option<PathBuf>, exec_path: Option<PathBuf>) -> GitInstall {
    let program = bin
        .as_ref()
        .map_or_else(|| PathBuf::from("git"), |bin| bin.join("git"));
    let output = Command::new(&program).arg("--version").output().unwrap();
    let version_text = String::from_utf8_lossy(&output.stdout).trim().to_owned();
    let version = GitVersion::parse(&version_text)
        .unwrap_or_else(|| panic!("{label}: cannot read the version from {version_text:?}"));
    GitInstall {
        label,
        bin,
        exec_path,
        version,
        version_text,
    }
}

/// The gits to test: the one on `PATH` (if any; on CI its absence fails) and the install
/// prefixes in `OPENRUN_TEST_GIT`.
pub(super) fn installs() -> Vec<GitInstall> {
    let mut installs = Vec::new();
    if super::test_support::find_tool("git").is_some() {
        installs.push(describe("git on PATH".to_owned(), None, None));
    } else {
        eprintln!("TEST SKIPPED: git is not installed");
        std::process::exit(86);
    }
    for prefix in std::env::var("OPENRUN_TEST_GIT")
        .unwrap_or_default()
        .split(':')
        .filter(|prefix| !prefix.is_empty())
    {
        let prefix = PathBuf::from(prefix);
        let bin = prefix.join("bin");
        assert!(
            bin.join("git").is_file(),
            "OPENRUN_TEST_GIT lists {}, which has no bin/git",
            prefix.display()
        );
        let exec_path = prefix.join("libexec/git-core");
        installs.push(describe(
            format!("git at {}", prefix.display()),
            Some(bin),
            Some(exec_path).filter(|path| path.is_dir()),
        ));
    }
    for required in [
        GitVersion::new(2, 31, 0),
        GitVersion::new(2, 43, 0),
        GitVersion::new(2, 43, 4),
    ] {
        if !installs.iter().any(|install| install.version == required) {
            eprintln!("TEST SKIPPED: OPENRUN_TEST_GIT must include Git {required:?}");
            std::process::exit(86);
        }
    }
    installs
}

/// A marker is the name of a program that ran.
const PROGRAMS: [&str; 3] = ["uploadpack", "ssh", "ext"];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Remote {
    LocalPath,
    FileUrl,
    Ext,
    Ssh,
}

const REMOTES: [Remote; 4] = [Remote::LocalPath, Remote::FileUrl, Remote::Ext, Remote::Ssh];

struct Fixture {
    _temp: tempfile::TempDir,
    markers: PathBuf,
    /// A complete repository whose `origin` is a local path.
    healthy: PathBuf,
    /// A repository with every object missing and a promisor remote that names programs.
    partial: PathBuf,
    source: PathBuf,
    uploadpack: PathBuf,
    /// The program an `ext::` URL starts. The URL syntax has no quoting.
    ext: PathBuf,
    environment: HashMap<String, String>,
}

fn executable(path: &Path, body: &str) {
    use std::os::unix::fs::PermissionsExt as _;
    std::fs::write(path, body).unwrap();
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755)).unwrap();
}

impl Fixture {
    fn new(install: &GitInstall) -> Self {
        let temp = tempfile::tempdir().unwrap();
        let markers = temp.path().join("markers");
        std::fs::create_dir_all(&markers).unwrap();
        let mut environment = base_environment(&temp.path().join("home"));
        environment.extend(install.variables());
        // The repository is built with the git under test, so that what it writes is what that
        // git reads.
        let program = |name: &str| {
            let path = temp.path().join(format!("{name}.sh"));
            executable(
                &path,
                &format!(
                    "#!/bin/sh\necho x >> '{}/{name}'\nexit 1\n",
                    slash(&markers)
                ),
            );
            path
        };
        let uploadpack = program("uploadpack");
        let ssh = program("ssh");
        let ext = program("ext");

        let source = temp.path().join("source");
        std::fs::create_dir_all(&source).unwrap();
        let in_source = |args: &[&str]| git_output_with(install, &source, args, &environment);
        in_source(&["init", "-q", "-b", "main"]);
        std::fs::write(source.join("a"), "first\n").unwrap();
        in_source(&["add", "-A"]);
        in_source(&["commit", "-qm", "one"]);
        in_source(&["tag", "-a", "-m", "tag", "v1"]);
        in_source(&["branch", "feature/x"]);
        in_source(&["config", "alias.co", "checkout"]);
        std::fs::write(source.join("a"), "second\n").unwrap();
        in_source(&["commit", "-qam", "two"]);
        in_source(&["update-ref", "refs/remotes/origin/main", "HEAD"]);
        std::fs::write(source.join("a"), "stash me\n").unwrap();
        in_source(&["stash", "push", "-q"]);
        std::fs::write(source.join("staged.txt"), "new\n").unwrap();
        in_source(&["add", "staged.txt"]);

        let healthy = temp.path().join("healthy");
        copy_directory(&source, &healthy);
        git_output_with(
            install,
            &healthy,
            &["config", "remote.origin.url", &slash(&source)],
            &environment,
        );
        git_output_with(
            install,
            &healthy,
            &[
                "config",
                "remote.origin.fetch",
                "+refs/heads/*:refs/remotes/origin/*",
            ],
            &environment,
        );

        let partial = temp.path().join("partial");
        copy_directory(&source, &partial);
        let fixture = Self {
            _temp: temp,
            markers,
            healthy,
            partial,
            source,
            uploadpack,
            ext,
            environment,
        };
        for (key, value) in [
            ("remote.origin.promisor", "true".to_owned()),
            ("remote.origin.partialclonefilter", "blob:none".to_owned()),
            ("extensions.partialClone", "origin".to_owned()),
            (
                "remote.origin.fetch",
                "+refs/heads/*:refs/remotes/origin/*".to_owned(),
            ),
            ("remote.origin.uploadpack", slash(&fixture.uploadpack)),
            ("core.sshCommand", slash(&ssh)),
        ] {
            git_output_with(
                install,
                &fixture.partial,
                &["config", key, &value],
                &fixture.environment,
            );
        }
        fixture
    }

    /// Points `origin` of the partial clone at `remote` and takes every object away again, so
    /// that the next command has to lazy-fetch, and forgets the programs that ran.
    fn arm(&self, install: &GitInstall, remote: Remote) {
        let url = match remote {
            Remote::LocalPath => slash(&self.source),
            Remote::FileUrl => format!("file://{}", slash(&self.source)),
            Remote::Ext => format!("ext::{} %G", slash(&self.ext)),
            Remote::Ssh => "ssh://localhost/repo.git".to_owned(),
        };
        git_output_with(
            install,
            &self.partial,
            &["config", "remote.origin.url", &url],
            &self.environment,
        );
        let objects = self.partial.join(".git/objects");
        let _ = std::fs::remove_dir_all(&objects);
        std::fs::create_dir_all(objects.join("pack")).unwrap();
        std::fs::create_dir_all(objects.join("info")).unwrap();
        let _ = std::fs::remove_dir_all(&self.markers);
        std::fs::create_dir_all(&self.markers).unwrap();
    }

    /// The programs that ran since the last [`Fixture::arm`].
    fn ran(&self) -> BTreeSet<&'static str> {
        std::thread::sleep(std::time::Duration::from_millis(30));
        PROGRAMS
            .into_iter()
            .filter(|name| self.markers.join(name).exists())
            .collect()
    }
}

fn copy_directory(from: &Path, to: &Path) {
    let status = Command::new("cp")
        .arg("-R")
        .arg(from)
        .arg(to)
        .status()
        .unwrap();
    assert!(status.success());
}

fn git_output_with(
    install: &GitInstall,
    dir: &Path,
    args: &[&str],
    environment: &HashMap<String, String>,
) -> String {
    let mut environment = environment.clone();
    environment.insert("PATH".to_owned(), install.path());
    // Fixtures are built by the git under test; the helper it needs is in its own exec path.
    git_output(dir, args, &environment)
}

#[derive(Clone, Copy)]
enum Defense {
    /// No table; the variables below are the whole environment.
    None,
    /// The production executor with the offline environment table.
    Table,
}

fn executor(defense: Defense, sandbox: bool) -> Arc<dyn CommandExecutor> {
    let executor = LocalCommandExecutor::new(Some(PathBuf::from("/bin/bash")), ShellType::Bash);
    let executor = if sandbox {
        executor
    } else {
        executor.with_network_sandbox(NetworkSandbox::Off)
    };
    Arc::new(match defense {
        Defense::None => executor.without_offline_environment(),
        Defense::Table => executor,
    })
}

struct Ran {
    success: bool,
    output: String,
}

fn session_context(
    install: &GitInstall,
    executor: Arc<dyn CommandExecutor>,
    cwd: &Path,
) -> SessionContext {
    let session = Session::new(
        SessionInfo::new_for_test().with_path(Some(install.path())),
        executor,
    );
    SessionContext::new(
        session,
        CommandRegistry::global_instance(),
        TypedPathBuf::from(cwd.to_str().unwrap()),
    )
}

/// Runs `command` as a generator command through `executor`, with `variables` as the session's
/// environment.
fn run(
    install: &GitInstall,
    executor: Arc<dyn CommandExecutor>,
    command: &str,
    cwd: &Path,
    variables: &HashMap<String, String>,
) -> Ran {
    let context = session_context(install, executor, cwd);
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

/// What the session's own environment can do to the table: allow every protocol.
fn permissive(fixture: &Fixture) -> HashMap<String, String> {
    let mut variables = fixture.environment.clone();
    variables.insert("GIT_ALLOW_PROTOCOL".to_owned(), "file:ssh:ext".to_owned());
    variables.insert("GIT_TERMINAL_PROMPT".to_owned(), "0".to_owned());
    variables
}

/// The table as it was before this change: local transports allowed, `GIT_NO_LAZY_FETCH` set.
fn previous_table(fixture: &Fixture) -> HashMap<String, String> {
    let mut variables = fixture.environment.clone();
    for (name, value) in [
        ("GIT_ALLOW_PROTOCOL", "file"),
        ("GIT_NO_LAZY_FETCH", "1"),
        ("GIT_TERMINAL_PROMPT", "0"),
        ("GIT_CONFIG_COUNT", "3"),
        ("GIT_CONFIG_KEY_0", "core.fsmonitor"),
        ("GIT_CONFIG_VALUE_0", "false"),
        ("GIT_CONFIG_KEY_1", "log.showSignature"),
        ("GIT_CONFIG_VALUE_1", "false"),
        ("GIT_CONFIG_KEY_2", "core.hooksPath"),
        ("GIT_CONFIG_VALUE_2", "/dev/null"),
    ] {
        variables.insert(name.to_owned(), value.to_owned());
    }
    variables
}

#[test]
fn a_repositorys_uploadpack_program_never_runs_on_any_git_the_gate_accepts() {
    let installs = installs();
    for install in &installs {
        assert!(
            install.version.honors_environment_overrides(),
            "{}: {} is older than {MINIMUM_GIT_VERSION}, which the gate refuses; the test would \
             prove nothing about an accepted git",
            install.label,
            install.version_text
        );
        let fixture = Fixture::new(install);
        let commands = local_git_commands(Shell::Posix);
        assert!(commands.len() > 12, "{commands:?}");
        // The two commands that read an object the partial clone does not have: the tree of the
        // index (`git reset ` reaches it) and the history. The controls need no more.
        let probes: BTreeSet<String> = commands
            .iter()
            .filter(|command| {
                command.contains("diff --cached --name-only") || command.contains("log --oneline")
            })
            .cloned()
            .collect();
        assert_eq!(probes.len(), 2, "{probes:?}");

        // Control 1: with nothing in the way, the lazy fetch starts every program.
        let mut fired_permissive = BTreeSet::new();
        for remote in REMOTES {
            for command in &probes {
                fixture.arm(install, remote);
                run(
                    install,
                    executor(Defense::None, false),
                    command,
                    &fixture.partial,
                    &permissive(&fixture),
                );
                fired_permissive.extend(fixture.ran());
            }
        }
        assert_eq!(
            fired_permissive,
            PROGRAMS.into_iter().collect::<BTreeSet<_>>(),
            "{} ({}): the fixture is insensitive: with every protocol allowed and no \
             GIT_NO_LAZY_FETCH, a lazy fetch did not start every program",
            install.label,
            install.version_text
        );

        // Control 2: the table as it was. A git that ignores GIT_NO_LAZY_FETCH runs the
        // repository's uploadpack program for a local remote; that is the bug.
        let mut fired_previous = BTreeSet::new();
        for remote in [Remote::LocalPath, Remote::FileUrl] {
            for command in &probes {
                fixture.arm(install, remote);
                run(
                    install,
                    executor(Defense::None, false),
                    command,
                    &fixture.partial,
                    &previous_table(&fixture),
                );
                fired_previous.extend(fixture.ran());
            }
        }
        if let Some(true) = install.ignores_no_lazy_fetch() {
            assert!(
                fired_previous.contains("uploadpack"),
                "{} ({}): this git ignores GIT_NO_LAZY_FETCH, but the previous table did not \
                 reproduce the bug (programs that ran: {fired_previous:?})",
                install.label,
                install.version_text
            );
        }
        eprintln!(
            "{} ({}): previous table ran {fired_previous:?}",
            install.label, install.version_text
        );

        // The claim: through the production executor with the table, whatever the session says.
        for sandbox in [false, true] {
            // Every command for the transports a lazy fetch can complete over; the others (the
            // protocol list refuses `ext::` and `ssh://` before anything starts) and the
            // sandboxed executor with the two commands that read missing objects.
            for remote in REMOTES {
                let local = matches!(remote, Remote::LocalPath | Remote::FileUrl);
                if sandbox && !local {
                    continue;
                }
                let selected: Vec<&String> = if local && !sandbox {
                    commands.iter().collect()
                } else {
                    probes.iter().collect()
                };
                for command in selected {
                    fixture.arm(install, remote);
                    let ran = run(
                        install,
                        executor(Defense::Table, sandbox),
                        command,
                        &fixture.partial,
                        &permissive(&fixture),
                    );
                    let programs = fixture.ran();
                    assert!(
                        programs.is_empty(),
                        "{} ({}): `{command}` with a {remote:?} promisor remote ran {programs:?} \
                         through the production executor (sandbox: {sandbox})\n{}",
                        install.label,
                        install.version_text,
                        ran.output
                    );
                }
            }
        }
    }
}

/// The false-positive control: the protocol list that stops a lazy fetch does not stop the
/// generators from reading a complete repository whose `origin` is a local path.
#[test]
fn a_complete_repository_with_a_local_origin_still_completes_on_every_accepted_git() {
    for install in installs() {
        let fixture = Fixture::new(&install);
        let mut seen = String::new();
        for command in local_git_commands(Shell::Posix) {
            let ran = run(
                &install,
                executor(Defense::Table, true),
                &command,
                &fixture.healthy,
                &fixture.environment,
            );
            // `git config --get alias.x` style commands may fail; the listing ones must not.
            if !command.contains("--get alias") {
                assert!(
                    ran.success,
                    "{} ({}): `{command}` failed in a healthy repository:\n{}",
                    install.label, install.version_text, ran.output
                );
            }
            seen.push_str(&ran.output);
        }
        for expected in ["feature/x", "v1", "origin", "stash@{0}", "staged.txt"] {
            assert!(
                seen.contains(expected),
                "{} ({}): no generator printed {expected:?}:\n{seen}",
                install.label,
                install.version_text
            );
        }
    }
}

/// Astra's reproducer: ask the production suggestions engine for `git reset ` in a partial clone
/// whose promisor remote is local and names an `uploadpack` program.
#[test]
fn completing_in_a_partial_clone_with_a_local_promisor_runs_no_repository_program() {
    let options = || CompleterOptions {
        match_strategy: MatchStrategy::CaseInsensitive,
        fallback_strategy: CompletionsFallbackStrategy::None,
        suggest_file_path_completions_only: false,
        parse_quotes_as_literals: false,
    };
    for install in installs() {
        let fixture = Fixture::new(&install);
        let complete = |line: &str, root: &Path| -> Vec<String> {
            let context = session_context(&install, executor(Defense::Table, true), root);
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
        // The engine runs git generators for this git: the gate accepted it.
        let branches = complete("git checkout ", &fixture.healthy);
        assert!(
            branches.iter().any(|branch| branch == "feature/x"),
            "{} ({}): `git checkout <Tab>` offered {branches:?}, so the version gate refused \
             this git or the generators did not run",
            install.label,
            install.version_text
        );
        for remote in [Remote::LocalPath, Remote::FileUrl] {
            for line in [
                "git reset ",
                "git checkout ",
                "git show ",
                "git diff ",
                "git log ",
                "git tag -d ",
                "git stash apply ",
                "git branch -d ",
            ] {
                fixture.arm(&install, remote);
                complete(line, &fixture.partial);
                let programs = fixture.ran();
                assert!(
                    programs.is_empty(),
                    "{} ({}): completing `{line}` in a partial clone with a {remote:?} promisor \
                     remote ran {programs:?}",
                    install.label,
                    install.version_text
                );
            }
        }
    }
}

#[test]
fn the_release_notes_rule_for_which_gits_ignore_no_lazy_fetch_is_what_the_test_assumes() {
    let version = |text: &str| describe_text(text).ignores_no_lazy_fetch();
    for (text, expected) in [
        ("git version 2.31.0", Some(true)),
        ("git version 2.39.3", Some(true)),
        ("git version 2.39.4", Some(false)),
        ("git version 2.40.1", Some(true)),
        ("git version 2.40.2", Some(false)),
        ("git version 2.43.0", Some(true)),
        ("git version 2.43.4", Some(false)),
        ("git version 2.44.0", Some(true)),
        ("git version 2.44.1", Some(false)),
        ("git version 2.45.0", Some(true)),
        ("git version 2.45.1", Some(false)),
        ("git version 2.46.0", Some(false)),
        ("git version 3.0.0", Some(false)),
        ("git version 2.39.5 (Apple Git-154)", None),
        ("git version 2.54.0 (Apple Git-157)", None),
    ] {
        assert_eq!(version(text), expected, "{text}");
    }
}

fn describe_text(text: &str) -> GitInstall {
    GitInstall {
        label: text.to_owned(),
        bin: None,
        exec_path: None,
        version: GitVersion::parse(text).unwrap(),
        version_text: text.to_owned(),
    }
}

#[test]
fn an_empty_protocol_list_also_refuses_a_custom_helper_named_none() {
    for install in installs() {
        let fixture = Fixture::new(&install);
        let helpers = fixture._temp.path().join("helpers");
        std::fs::create_dir(&helpers).unwrap();
        let marker = helpers.join("ran");
        executable(
            &helpers.join("git-remote-none"),
            &format!("#!/bin/sh\ntouch '{}'\nexit 1\n", marker.display()),
        );
        let mut variables = fixture.environment.clone();
        variables.insert("GIT_EXEC_PATH".into(), slash(&helpers));
        variables.insert("GIT_ALLOW_PROTOCOL".into(), "none".into());
        let command = "git ls-remote none::fixture";
        run(
            &install,
            executor(Defense::None, false),
            command,
            &fixture.healthy,
            &variables,
        );
        assert!(
            marker.exists(),
            "custom-helper positive control did not run"
        );
        std::fs::remove_file(&marker).unwrap();
        run(
            &install,
            executor(Defense::Table, false),
            command,
            &fixture.healthy,
            &variables,
        );
        assert!(
            !marker.exists(),
            "the empty protocol list allowed a custom helper"
        );
    }
}
