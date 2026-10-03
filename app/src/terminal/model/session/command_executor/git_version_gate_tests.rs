//! A fake `git` first on the session's `PATH` reports a chosen version and logs every
//! invocation (arguments, and the offline table variables it was started with). Completing git
//! words through the production path (`SessionContext` over `Session` over the production
//! `LocalCommandExecutor`, sandbox included where the platform has one) must run no git
//! generator when the version is older than 2.31 or cannot be read, and must run them when it is
//! 2.31 or newer. The probe is one `git --version` per session.

use std::os::unix::fs::PermissionsExt as _;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use typed_path::TypedPathBuf;
use warp_completer::completer::{
    CompleterOptions, CompletionsFallbackStrategy, MatchStrategy, suggestions,
};
use warp_completer::signatures::CommandRegistry;

use super::LocalCommandExecutor;
use crate::completer::SessionContext;
use crate::terminal::model::session::{Session, SessionInfo};
use crate::terminal::shell::ShellType;

struct FakeGit {
    _temp: tempfile::TempDir,
    bin: PathBuf,
    log: PathBuf,
    cwd: PathBuf,
}

impl FakeGit {
    /// A `git` that prints `version_output` for `--version` (exiting with `version_status`) and
    /// a branch and a log line for anything else except `config`, which fails as it does for an
    /// alias that does not exist.
    fn new(version_output: &str, version_status: i32) -> Self {
        let temp = tempfile::tempdir().unwrap();
        let bin = temp.path().join("bin");
        let cwd = temp.path().join("repo");
        std::fs::create_dir_all(&bin).unwrap();
        std::fs::create_dir_all(&cwd).unwrap();
        let log = temp.path().join("git.log");
        let script = bin.join("git");
        std::fs::write(
            &script,
            format!(
                "#!/bin/sh\n\
                 echo \"$* | no_lazy_fetch=$GIT_NO_LAZY_FETCH count=$GIT_CONFIG_COUNT\" >> '{log}'\n\
                 if [ \"$1\" = \"--version\" ]; then\n\
                   printf '%s\\n' '{version_output}'\n\
                   exit {version_status}\n\
                 fi\n\
                 if [ \"$1\" = \"config\" ]; then exit 1; fi\n\
                 echo '* main'\n\
                 echo '  feature'\n\
                 echo 'abc1234 a commit'\n",
                log = log.display(),
            ),
        )
        .unwrap();
        std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).unwrap();
        Self {
            _temp: temp,
            bin,
            log,
            cwd,
        }
    }

    fn path(&self) -> String {
        format!("{}:/usr/bin:/bin", self.bin.display())
    }

    fn session_context(&self) -> SessionContext {
        let executor = LocalCommandExecutor::new(Some(PathBuf::from("/bin/bash")), ShellType::Bash);
        let session = Session::new(
            SessionInfo::new_for_test().with_path(Some(self.path())),
            Arc::new(executor),
        );
        SessionContext::new(
            session,
            CommandRegistry::global_instance(),
            TypedPathBuf::from(self.cwd.to_str().unwrap()),
        )
    }

    /// Every invocation of the fake git so far, in order.
    fn invocations(&self) -> Vec<String> {
        std::fs::read_to_string(&self.log)
            .unwrap_or_default()
            .lines()
            .map(str::to_owned)
            .collect()
    }

    fn version_probes(&self) -> usize {
        self.invocations()
            .iter()
            .filter(|line| line.starts_with("--version"))
            .count()
    }

    fn other_invocations(&self) -> Vec<String> {
        self.invocations()
            .into_iter()
            .filter(|line| !line.starts_with("--version"))
            .collect()
    }
}

fn complete(context: &SessionContext, line: &str) -> Vec<String> {
    let options = CompleterOptions {
        match_strategy: MatchStrategy::CaseInsensitive,
        fallback_strategy: CompletionsFallbackStrategy::None,
        suggest_file_path_completions_only: false,
        parse_quotes_as_literals: false,
    };
    futures_lite::future::block_on(suggestions(line, line.len(), None, options, context))
        .map(|results| {
            results
                .suggestions
                .into_iter()
                .map(|matched| matched.suggestion.display.to_string())
                .collect()
        })
        .unwrap_or_default()
}

/// Inputs that reach git generators: branches, stashes, tags, commits, and the alias generator
/// (`git config --get alias.<word>`, which `git co ` reaches).
const INPUTS: &[&str] = &[
    "git checkout ",
    "git stash apply ",
    "git tag -d ",
    "git co ",
];

fn complete_all(context: &SessionContext) {
    for input in INPUTS {
        complete(context, input);
    }
}

#[test]
fn no_git_generator_runs_when_git_is_older_than_2_31() {
    for version in [
        "git version 2.30.2",
        "git version 2.30.9 (Apple Git-130)",
        "git version 1.8.3.1",
    ] {
        let git = FakeGit::new(version, 0);
        let context = git.session_context();
        complete_all(&context);
        assert_eq!(
            git.other_invocations(),
            Vec::<String>::new(),
            "{version}: git ran after the version probe"
        );
        assert_eq!(
            git.version_probes(),
            1,
            "{version}: the version is probed once"
        );
        // Offered nothing from git either.
        assert!(
            !complete(&context, "git checkout ")
                .iter()
                .any(|branch| branch == "feature"),
            "{version}"
        );
        assert_eq!(git.version_probes(), 1, "{version}: and remembered");
    }
}

#[test]
fn git_generators_run_when_git_is_2_31_or_newer() {
    for version in [
        "git version 2.31.0",
        "git version 2.39.3 (Apple Git-146)",
        "git version 2.45.1.windows.1",
        "git version 2.54.0",
    ] {
        let git = FakeGit::new(version, 0);
        let context = git.session_context();
        let branches = complete(&context, "git checkout ");
        assert!(
            branches.iter().any(|branch| branch == "feature"),
            "{version}: offered {branches:?}; git ran {:?}",
            git.invocations()
        );
        complete_all(&context);
        let other = git.other_invocations();
        assert!(
            other.iter().any(|line| line.contains("branch")),
            "{version}: {other:?}"
        );
        assert!(
            other
                .iter()
                .any(|line| line.contains("config --get alias.")),
            "{version}: the alias generator did not run: {other:?}"
        );
        assert_eq!(
            git.version_probes(),
            1,
            "{version}: the version is probed once"
        );
    }
}

#[test]
fn an_unreadable_version_runs_no_git_generator() {
    for (output, status) in [
        ("git version banana", 0),
        ("", 0),
        ("git version 2", 0),
        ("usage: git", 0),
        ("git version 2.40.0", 1),
    ] {
        let git = FakeGit::new(output, status);
        let context = git.session_context();
        complete_all(&context);
        assert_eq!(
            git.other_invocations(),
            Vec::<String>::new(),
            "{output:?} (exit {status})"
        );
    }
}

#[test]
fn a_missing_git_runs_no_git_generator() {
    let temp = tempfile::tempdir().unwrap();
    let executor = LocalCommandExecutor::new(Some(PathBuf::from("/bin/bash")), ShellType::Bash);
    let empty: &Path = temp.path();
    let session = Session::new(
        SessionInfo::new_for_test().with_path(Some(empty.display().to_string())),
        Arc::new(executor),
    );
    let context = SessionContext::new(
        session,
        CommandRegistry::global_instance(),
        TypedPathBuf::from(empty.to_str().unwrap()),
    );
    let offered = complete(&context, "git checkout ");
    assert!(
        offered.iter().all(|word| word.starts_with('-')),
        "only flags can be offered without git: {offered:?}"
    );
}

#[test]
fn the_probe_runs_through_the_offline_environment_of_the_executor() {
    let git = FakeGit::new("git version 2.54.0", 0);
    let context = git.session_context();
    complete(&context, "git checkout ");
    let probe = git
        .invocations()
        .into_iter()
        .find(|line| line.starts_with("--version"))
        .expect("the version was probed");
    assert!(
        probe.contains("no_lazy_fetch=1") && probe.contains("count=3"),
        "the probe did not get the offline environment table: {probe}"
    );
}

#[test]
fn remote_and_in_band_contexts_run_no_generator_alias_or_correction_probe() {
    use super::network_sandbox::NetworkSandbox;
    use super::{CommandExecutor, InBandCommandExecutor, RemoteCommandExecutor};

    let git = FakeGit::new("git version 2.54.0", 0);
    let (commands_tx, commands_rx) = async_channel::unbounded();
    let (cancelled_tx, _) = async_channel::unbounded();
    let executors: Vec<Arc<dyn CommandExecutor>> = vec![
        Arc::new(
            LocalCommandExecutor::new(Some("/bin/bash".into()), ShellType::Bash)
                .with_network_sandbox(NetworkSandbox::Unavailable),
        ),
        Arc::new(RemoteCommandExecutor::new(
            git.cwd.join("unused-control-socket"),
        )),
        Arc::new(InBandCommandExecutor::new(commands_tx, cancelled_tx)),
    ];
    for executor in executors {
        assert!(!executor.network_isolated());
        for shell_type in [
            ShellType::Bash,
            ShellType::Zsh,
            ShellType::Fish,
            ShellType::PowerShell,
        ] {
            let session = Session::new(
                SessionInfo::new_for_test()
                    .with_path(Some(git.path()))
                    .with_shell_type(shell_type),
                executor.clone(),
            );
            assert!(
                futures_lite::future::block_on(
                    session.git_branches_for_command_corrections(git.cwd.to_str().unwrap())
                )
                .is_empty()
            );
            let context = SessionContext::new(
                session,
                CommandRegistry::global_instance(),
                TypedPathBuf::from(git.cwd.to_str().unwrap()),
            );
            for line in [
                "git checkout ",
                "git stash apply ",
                "git co ",
                "uv tool uninstall ",
            ] {
                futures_lite::future::block_on(suggestions(
                    line,
                    line.len(),
                    None,
                    CompleterOptions {
                        match_strategy: MatchStrategy::CaseInsensitive,
                        fallback_strategy: CompletionsFallbackStrategy::None,
                        suggest_file_path_completions_only: false,
                        parse_quotes_as_literals: false,
                    },
                    &context,
                ));
            }
        }
    }
    assert!(
        git.invocations().is_empty(),
        "neither generators nor version/correction probes may start"
    );
    assert!(
        commands_rx.try_recv().is_err(),
        "in-band execution must not be queued"
    );
}
