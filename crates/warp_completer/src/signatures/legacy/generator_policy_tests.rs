use std::collections::{BTreeSet, HashMap};
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use regex::Regex;
use warp_command_signatures::{GeneratorProcess, Shell};
use warp_util::path::{EscapeChar, ShellFamily};

use super::allowed::{
    ALLOWED_ALIAS_GENERATORS, ALLOWED_GENERATORS, ALLOWED_ON_WINDOWS,
    ALLOWED_ON_WINDOWS_WITH_ENVIRONMENT, ALLOWED_WHEN_ISOLATED,
};
use super::denied::{DENIED_ALIAS_GENERATORS, DENIED_GENERATORS};
use super::token_gate::{is_inert_word, is_quotable_word, listed_token_policies};
use super::{
    TokenPolicy, is_alias_generator_allowed, is_generator_allowed_on, sanitize_env_vars,
    token_policy,
};
use crate::completer::{
    CommandExitStatus, CommandOutput, CompleterOptions, CompletionContext,
    CompletionsFallbackStrategy, Containment, GeneratorContext, MatchStrategy,
    PathCompletionContext, suggestions,
};
use crate::signatures::CommandRegistry;
use crate::signatures::registry::GeneratorPolicy;

/// A `GeneratorContext` that runs nothing, records every command the engine asks for and
/// reports each as failed (like `git config --get alias.x` for an alias that does not exist).
struct RecordingContext {
    registry: Arc<CommandRegistry>,
    commands: Mutex<Vec<String>>,
    /// What `network_isolated` reports.
    isolated: bool,
    /// What `offline_environment_applied` reports.
    environment: bool,
    /// When set, `curl ...` commands are run through `sh` with a `PATH` that contains only this
    /// directory, so they can only ever reach the stub `curl` placed in it.
    #[cfg(unix)]
    stub_curl_dir: Option<std::path::PathBuf>,
    /// The shell family the session reports; `None` is a POSIX session.
    family: Option<ShellFamily>,
    /// When set, every command is run in this shell, started as a local session starts it, with
    /// an empty `PATH` (shell builtins only), and its standard output and error are collected in
    /// `stdout`. The session reports this shell's family.
    #[cfg(unix)]
    run_in_shell: Option<real_shells::RealShell>,
    #[cfg(unix)]
    stdout: Mutex<String>,
}

impl RecordingContext {
    fn new(registry: Arc<CommandRegistry>) -> Self {
        Self {
            registry,
            commands: Mutex::new(Vec::new()),
            isolated: false,
            environment: false,
            family: None,
            #[cfg(unix)]
            stub_curl_dir: None,
            #[cfg(unix)]
            run_in_shell: None,
            #[cfg(unix)]
            stdout: Mutex::new(String::new()),
        }
    }

    /// Runs the commands in `shell` and reports its family, as a session of that shell does.
    #[cfg(unix)]
    fn in_shell(mut self, shell: &real_shells::RealShell) -> Self {
        self.family = Some(shell.kind.family());
        self.run_in_shell = Some(shell.clone());
        self
    }

    /// The commands the engine asked to run while completing the end of `line`.
    fn commands_for(&self, line: &str) -> Vec<String> {
        self.commands.lock().unwrap().clear();
        let options = CompleterOptions {
            match_strategy: MatchStrategy::CaseInsensitive,
            fallback_strategy: CompletionsFallbackStrategy::None,
            suggest_file_path_completions_only: false,
            parse_quotes_as_literals: false,
        };
        warpui_core::r#async::block_on(suggestions(line, line.len(), None, options, self));
        self.commands.lock().unwrap().clone()
    }
}

impl CompletionContext for RecordingContext {
    fn path_completion_context(&self) -> Option<&dyn PathCompletionContext> {
        None
    }

    fn generator_context(&self) -> Option<&dyn GeneratorContext> {
        Some(self)
    }

    fn top_level_commands(&self) -> Box<dyn Iterator<Item = &str> + '_> {
        Box::new(std::iter::empty())
    }

    fn command_registry(&self) -> &CommandRegistry {
        &self.registry
    }

    fn shell_family(&self) -> Option<ShellFamily> {
        self.family
    }

    fn escape_char(&self) -> EscapeChar {
        match self.family {
            Some(ShellFamily::PowerShell) => EscapeChar::Backtick,
            _ => EscapeChar::Backslash,
        }
    }
}

#[async_trait]
impl GeneratorContext for RecordingContext {
    async fn execute_command_at_pwd(
        &self,
        shell_command: &str,
        _session_env_vars: Option<HashMap<String, String>>,
    ) -> anyhow::Result<CommandOutput> {
        self.commands.lock().unwrap().push(shell_command.to_owned());
        #[cfg(unix)]
        if let Some(shell) = &self.run_in_shell {
            let empty =
                std::env::temp_dir().join(format!("openrun-empty-path-{}", std::process::id()));
            std::fs::create_dir_all(&empty)?;
            let output = shell.run(shell_command, &empty)?;
            self.stdout
                .lock()
                .unwrap()
                .push_str(&String::from_utf8_lossy(&output.stdout));
            self.stdout
                .lock()
                .unwrap()
                .push_str(&String::from_utf8_lossy(&output.stderr));
            return Ok(CommandOutput {
                stdout: output.stdout,
                stderr: output.stderr,
                status: CommandExitStatus::Failure,
                exit_code: None,
            });
        }
        #[cfg(unix)]
        if let Some(stub_dir) = &self.stub_curl_dir
            && shell_command.starts_with("curl ")
        {
            let output = command::blocking::Command::new("/bin/sh")
                .arg("-c")
                .arg(shell_command)
                .env_clear()
                .env("PATH", stub_dir)
                .output()?;
            return Ok(CommandOutput {
                stdout: output.stdout,
                stderr: output.stderr,
                status: CommandExitStatus::Failure,
                exit_code: None,
            });
        }
        Ok(CommandOutput {
            stdout: Vec::new(),
            stderr: Vec::new(),
            status: CommandExitStatus::Failure,
            exit_code: None,
        })
    }

    fn supports_parallel_execution(&self) -> bool {
        true
    }

    fn network_isolated(&self) -> bool {
        self.isolated
    }

    fn offline_environment_applied(&self) -> bool {
        self.environment
    }
}

/// The bundled registry in a context whose executor applies the offline environment table and has
/// no network sandbox (Windows local, Git Bash/MSYS2 and WSL sessions).
fn guarded_with_environment() -> RecordingContext {
    let mut context = guarded();
    context.environment = true;
    context
}

fn guarded() -> RecordingContext {
    RecordingContext::new(CommandRegistry::global_instance())
}

/// The bundled registry in a context whose commands cannot reach a network (macOS and Linux local
/// sessions).
#[cfg(not(windows))]
fn guarded_isolated() -> RecordingContext {
    let mut context = guarded();
    context.isolated = true;
    context.environment = true;
    context
}

/// The bundled specs with every generator enabled, to prove that a test input really does reach
/// a generator when the policy is not in the way.
fn unrestricted() -> RecordingContext {
    let registry = CommandRegistry::new(
        |command| warp_command_signatures::signature_by_name(command),
        warp_command_signatures::dynamic_command_signature_data(),
        GeneratorPolicy::AllowAll,
    );
    RecordingContext::new(Arc::new(registry))
}

/// Inputs whose completion reaches a generator that can talk to a network.
const NETWORK_INPUTS: &[(&str, &str)] = &[
    ("npm install astra", "registry.npmjs.org"),
    ("yarn add astra", "api.npms.io"),
    ("pnpm add astra", "api.npms.io"),
    ("bun add astra", "api.npms.io"),
    ("cargo add astra", "crates.io"),
    ("gh pr checkout ", "gh pr list"),
    ("gh repo clone ast", "gh repo list"),
    ("aws s3 ls s3://", "aws s3 ls"),
    (
        "aws ec2 describe-instances --instance-ids ",
        "aws ec2 describe-instances",
    ),
    ("kubectl get pods ", "get pods -o custom-columns"),
    ("kubectl logs ", "__complete"),
    ("docker pull ast", "docker search"),
    ("fnm install ", "fnm ls-remote"),
    ("tfenv install ", "tfenv list-remote"),
    ("sdk install java ", "api.sdkman.io"),
    ("degit user/re", "api.github.com"),
    ("scp -r host:/tm", "ssh -o BatchMode"),
    (
        "aws ec2 stop-instances --instance-ids ",
        "describe-instances",
    ),
];

/// Inputs whose completion reaches a generator that only reads the local machine.
#[cfg(not(windows))]
const LOCAL_INPUTS: &[(&str, &str)] = &[
    ("git checkout ", "branch"),
    ("git stash apply ", "stash"),
    ("npm run ", "package.json"),
    ("kill ", "ps "),
];

/// Inputs whose completion reaches a generator that looks local but depends on the
/// environment: a rustup proxy that installs a toolchain, a docker CLI that talks to whatever
/// `DOCKER_HOST` names, an `npm` update check, a corepack shim, a repository config that runs
/// `core.fsmonitor`, or a tool that loads project files.
const ENVIRONMENT_INPUTS: &[(&str, &str)] = &[
    ("cargo run --bin ", "cargo metadata"),
    ("docker start ", "docker ps"),
    ("npm install -w ", "npm prefix"),
    ("git diff ", "diff --diff-filter"),
    ("nx run ", "nx "),
    ("brew uninstall ", "brew list"),
];

#[test]
fn network_generators_never_run_with_the_bundled_registry() {
    let guarded = guarded();
    let unrestricted = unrestricted();
    for (input, marker) in NETWORK_INPUTS {
        let reachable = unrestricted.commands_for(input);
        assert!(
            reachable.iter().any(|command| command.contains(marker)),
            "{input:?} should reach a generator containing {marker:?} without the policy, got {reachable:?}"
        );
        let executed = guarded.commands_for(input);
        assert!(
            !executed.iter().any(|command| command.contains(marker)),
            "{input:?} must not run the {marker:?} generator, but ran {executed:?}"
        );
        assert!(
            !executed
                .iter()
                .any(|command| command.contains("curl") || command.contains("https://")),
            "{input:?} ran {executed:?}"
        );
    }
}

#[test]
fn environment_dependent_generators_never_run_with_the_bundled_registry() {
    let guarded = guarded();
    let unrestricted = unrestricted();
    for (input, marker) in ENVIRONMENT_INPUTS {
        let reachable = unrestricted.commands_for(input);
        assert!(
            reachable.iter().any(|command| command.contains(marker)),
            "{input:?} should reach a generator containing {marker:?} without the policy, got {reachable:?}"
        );
        let executed = guarded.commands_for(input);
        assert!(
            !executed.iter().any(|command| command.contains(marker)),
            "{input:?} must not run the {marker:?} generator, but ran {executed:?}"
        );
    }
}

#[cfg(not(windows))]
#[test]
fn local_generators_still_run_with_the_bundled_registry() {
    let guarded = guarded();
    for (input, marker) in LOCAL_INPUTS {
        let executed = guarded.commands_for(input);
        assert!(
            executed.iter().any(|command| command.contains(marker)),
            "{input:?} should run a local generator containing {marker:?}, got {executed:?}"
        );
    }
}

#[cfg(not(windows))]
#[test]
fn the_policy_decides_by_spec_and_generator_name() {
    use warp_command_signatures::GeneratorName;
    let registry = CommandRegistry::global_instance();
    let name = |name: &str| GeneratorName::new(name);
    assert!(registry.allows_generator("git", &name("local_branches"), Containment::Unrestricted));
    assert!(!registry.allows_generator(
        "npm",
        &name("npm_registry_search"),
        Containment::Unrestricted
    ));
    assert!(!registry.allows_generator(
        "cargo",
        &name("crates_io_search"),
        Containment::Unrestricted
    ));
    // The same generator name is local in one spec and a network call in another.
    assert!(registry.allows_generator("bat", &name("completions"), Containment::Unrestricted));
    assert!(!registry.allows_generator(
        "softwareupdate",
        &name("completions"),
        Containment::Unrestricted
    ));
    // Unknown pairs are denied.
    assert!(!registry.allows_generator(
        "git",
        &name("no_such_generator"),
        Containment::Unrestricted
    ));
    assert!(!registry.allows_generator(
        "no-such-spec",
        &name("local_branches"),
        Containment::Unrestricted
    ));
    assert!(!CommandRegistry::empty().allows_generator(
        "git",
        &name("no_such_generator"),
        Containment::NetworkIsolated
    ));
}

#[test]
fn allow_and_deny_lists_are_sorted_unique_lowercase_and_disjoint() {
    let allowed: Vec<_> = ALLOWED_GENERATORS.to_vec();
    let denied: Vec<_> = DENIED_GENERATORS.iter().map(|(s, g, _)| (*s, *g)).collect();
    for (name, list) in [("allowed", &allowed), ("denied", &denied)] {
        assert!(
            list.windows(2).all(|pair| pair[0] < pair[1]),
            "{name} generators must be sorted by (spec, generator) without duplicates"
        );
        assert!(
            list.iter().all(|(spec, _)| *spec == spec.to_lowercase()),
            "{name} specs must be lowercase"
        );
    }
    let allowed_set: BTreeSet<_> = allowed.iter().collect();
    let overlap: Vec<_> = denied
        .iter()
        .filter(|pair| allowed_set.contains(pair))
        .collect();
    assert!(overlap.is_empty(), "in both lists: {overlap:?}");
    let isolated: Vec<_> = ALLOWED_WHEN_ISOLATED.to_vec();
    assert!(
        isolated.windows(2).all(|pair| pair[0] < pair[1]),
        "isolated generators must be sorted by (spec, generator) without duplicates"
    );
    assert!(
        isolated
            .iter()
            .all(|pair| !allowed_set.contains(pair) && !denied.contains(pair)),
        "an isolated-tier generator is also in allowed.rs or denied.rs"
    );
    assert!(
        DENIED_GENERATORS
            .iter()
            .chain(DENIED_ALIAS_GENERATORS)
            .all(|(_, _, class)| DENIED_CLASSES.contains(class)),
        "denied classes must be one of {DENIED_CLASSES:?}"
    );
    let allowed_aliases: Vec<_> = ALLOWED_ALIAS_GENERATORS.to_vec();
    let denied_aliases: Vec<_> = DENIED_ALIAS_GENERATORS
        .iter()
        .map(|(s, a, _)| (*s, *a))
        .collect();
    for (name, list) in [
        ("allowed alias", &allowed_aliases),
        ("denied alias", &denied_aliases),
    ] {
        assert!(
            list.windows(2).all(|pair| pair[0] < pair[1]),
            "{name} generators must be sorted by (spec, alias) without duplicates"
        );
    }
    assert!(
        denied_aliases
            .iter()
            .all(|pair| !allowed_aliases.contains(pair)),
        "an alias generator is in both lists"
    );
}

const DENIED_CLASSES: &[&str] = &[
    "network",
    "cluster",
    "maybe-network",
    "lan",
    "env-network-verified",
    "env-network-likely",
    "project-code",
    "injectable",
];

fn bundled_generators() -> Vec<(String, String, warp_command_signatures::Generator)> {
    let mut all = Vec::new();
    for (spec, data) in warp_command_signatures::dynamic_command_signature_data() {
        for (name, generator) in data.generators() {
            all.push((spec.clone(), name.0.clone(), generator.clone()));
        }
    }
    all.sort_by(|a, b| (&a.0, &a.1).cmp(&(&b.0, &b.1)));
    all
}

/// Sample commands a generator produces, for the reviewer and for the content check below.
fn sample_commands(spec: &str, generator: &warp_command_signatures::Generator) -> Vec<String> {
    match &generator.process {
        GeneratorProcess::ShellCommand(command) => vec![command.build(Shell::Posix).to_string()],
        GeneratorProcess::CommandFromTokens(command_from_tokens) => {
            let variants: [(Vec<&str>, bool); 5] = [
                (vec![spec, "abcd"], false),
                (vec![spec, "install", "abcd"], false),
                (vec![spec, "sub", "abcd", ""], true),
                (vec![spec, "add", "--flag", "abcd"], false),
                (vec![spec, "owner/repo", ""], true),
            ];
            let mut commands = BTreeSet::new();
            for (tokens, trailing_whitespace) in variants {
                commands.insert(
                    command_from_tokens(&tokens, trailing_whitespace, &[])
                        .build(Shell::Posix)
                        .to_string(),
                );
            }
            commands.into_iter().collect()
        }
    }
}

#[test]
fn every_bundled_generator_is_classified() {
    let allowed: BTreeSet<_> = ALLOWED_GENERATORS
        .iter()
        .chain(ALLOWED_WHEN_ISOLATED)
        .copied()
        .collect();
    let denied: BTreeSet<_> = DENIED_GENERATORS.iter().map(|(s, g, _)| (*s, *g)).collect();
    let bundled = bundled_generators();

    let unclassified: Vec<String> = bundled
        .iter()
        .filter(|(spec, name, _)| {
            !allowed.contains(&(spec.as_str(), name.as_str()))
                && !denied.contains(&(spec.as_str(), name.as_str()))
        })
        .map(|(spec, name, generator)| {
            format!(
                "    (\"{spec}\", \"{name}\"),  // {:?}",
                sample_commands(spec, generator)
            )
        })
        .collect();
    assert!(
        unclassified.is_empty(),
        "these generators are in neither allowed.rs nor denied.rs. Review what each command \
         can reach and add it to exactly one of them (see the module documentation of \
         generator_policy.rs):\n{}",
        unclassified.join("\n")
    );

    let bundled_pairs: BTreeSet<_> = bundled
        .iter()
        .map(|(spec, name, _)| (spec.as_str(), name.as_str()))
        .collect();
    let stale: Vec<_> = allowed
        .iter()
        .chain(denied.iter())
        .filter(|pair| !bundled_pairs.contains(pair))
        .collect();
    assert!(
        stale.is_empty(),
        "listed generators that the bundled specs no longer define: {stale:?}"
    );
}

#[test]
fn allowed_generators_do_not_run_network_tools() {
    // Cloud and cluster CLIs are fine when the subcommand only reads their local configuration.
    let local_cli_subcommand = Regex::new(
        r"^\s*(?:kubectl\b.*\bconfig\s+get-|az\s+(?:account\s+list|extension\s+list\s)|gcloud\s+(?:auth|config)\s|gh\s+alias\s)",
    )
    .unwrap();
    let network_tool = Regex::new(
        r"(?:^|[;&|({]|\$\()\s*(?:command\s+|\\)?(?:curl|wget|ssh|scp|sftp|nc|ncat|telnet|ftp|rsync|gh|aws|az|gcloud|gsutil|firebase|heroku|flyctl|kubectl|oc|npx|docker\s+search)\b",
    )
    .unwrap();
    let url = Regex::new(
        r"https?://|ls-remote|list-remote|git\s+(?:--\S+\s+)*(?:fetch|pull|clone|push)\b",
    )
    .unwrap();

    let allowed: BTreeSet<_> = ALLOWED_GENERATORS.iter().copied().collect();
    let mut offenders = Vec::new();
    for (spec, name, generator) in bundled_generators() {
        if !allowed.contains(&(spec.as_str(), name.as_str())) {
            continue;
        }
        for command in sample_commands(&spec, &generator) {
            if (network_tool.is_match(&command) && !local_cli_subcommand.is_match(&command))
                || url.is_match(&command)
            {
                offenders.push(format!("{spec}/{name}: {command}"));
            }
        }
    }
    assert!(
        offenders.is_empty(),
        "allow-listed generators whose command looks like a network call. Move them to \
         denied.rs (or, if the command changed with a pin bump, re-review it):\n{}",
        offenders.join("\n")
    );
}

/// The generators of the RV-01 report that stay denied for another reason as well.
const STILL_DENIED_INJECTABLE_GENERATORS: &[(&str, &str, &str)] = &[
    ("docker", "image_with_tags", "env-network-verified"),
    ("docker-compose", "compose_services", "env-network-likely"),
];

/// The generators of the RV-01 report that put the user's unsubmitted words into the shell
/// command unquoted (or, for the `kubectl` family, the `KEY=value` words typed before the
/// command). They run again, but only behind the token gate.
const GATED_INJECTABLE_GENERATORS: &[(&str, &str)] = &[
    ("asdf", "installed_versions"),
    ("brew", "gist_logs_actions"),
    ("dd", "conv_remaining"),
    ("esbuild", "loader"),
    ("eslint", "env_remaining"),
    ("file", "param_keys"),
    ("kubecolor", "cluster"),
    ("kubecolor", "context"),
    ("kubecolor", "user"),
    ("kubectl", "cluster"),
    ("kubectl", "context"),
    ("kubectl", "user"),
    ("man", "sections_remaining"),
    ("oc", "cluster"),
    ("oc", "context"),
    ("oc", "user"),
    ("ros2", "executables"),
    ("scc", "format_multi"),
    ("sdk", "installed_versions"),
    ("trivy", "pkg_types_remaining"),
    ("trivy", "scanners_remaining"),
    ("trivy", "severity_remaining"),
];

/// The generators of the RV-02 report, by name: a rustup proxy that installs the toolchain a
/// project names, a docker CLI that talks to whatever `DOCKER_HOST` or context names, the `npm`
/// update check, a corepack shim that downloads the package manager, and tools that run code the
/// project (or the repository config) controls.
const ENVIRONMENT_GENERATORS: &[(&str, &str, &str)] = &[
    ("yarn", "all_dependencies_generator", "env-network-verified"),
    ("yarn", "config_list", "env-network-verified"),
    (
        "yarn",
        "get_global_packages_generator",
        "env-network-verified",
    ),
    ("yarn", "workspace_names_generator", "env-network-verified"),
    (
        "eslint",
        "ls_node_modules_root_global",
        "env-network-verified",
    ),
    ("git", "files_for_staging", "project-code"),
    ("git", "get_changed_or_tracked_files", "project-code"),
    ("hub", "status", "project-code"),
    ("hub", "status_staged_or_unstaged", "project-code"),
    ("nx", "apps", "project-code"),
    ("nx", "workspace_targets", "project-code"),
    ("lerna", "ls", "project-code"),
    ("r", "rscript_libpaths", "project-code"),
    ("uv", "project_dependencies", "project-code"),
    ("go", "tool_generator", "env-network-likely"),
];

#[test]
fn the_injectable_and_environment_dependent_generators_are_denied_with_their_class() {
    for (spec, name, class) in STILL_DENIED_INJECTABLE_GENERATORS
        .iter()
        .chain(ENVIRONMENT_GENERATORS)
    {
        for windows in [false, true] {
            assert!(
                !is_generator_allowed_on(windows, Containment::NetworkIsolated, spec, name),
                "{spec}/{name} must not be allowed (windows: {windows})"
            );
        }
        assert_eq!(
            DENIED_GENERATORS
                .iter()
                .find(|(s, g, _)| s == spec && g == name)
                .map(|(_, _, class)| class),
            Some(class),
            "{spec}/{name} must be denied as {class}"
        );
    }
    assert_eq!(
        STILL_DENIED_INJECTABLE_GENERATORS.len() + GATED_INJECTABLE_GENERATORS.len(),
        24
    );
    for (spec, alias, _) in DENIED_ALIAS_GENERATORS {
        assert!(!is_alias_generator_allowed(spec, alias), "{spec}/{alias}");
    }
    assert_eq!(ALLOWED_ALIAS_GENERATORS, &[("git", "alias")]);
}

/// The restored tier: generators that look local but reached a network, or ran repository code,
/// in the environment alone (see `ALLOWED_WHEN_ISOLATED`).
#[test]
fn isolated_generators_run_only_when_the_context_is_isolated() {
    use super::generators_allowed_when_isolated;
    assert_eq!(generators_allowed_when_isolated(), ALLOWED_WHEN_ISOLATED);
    assert!(!ALLOWED_WHEN_ISOLATED.is_empty());
    for (spec, name) in ALLOWED_WHEN_ISOLATED {
        for containment in [Containment::Unrestricted, Containment::OfflineEnvironment] {
            assert!(
                !is_generator_allowed_on(false, containment, spec, name),
                "{spec}/{name} must not run outside a network-isolated context ({containment:?})"
            );
        }
        assert!(
            is_generator_allowed_on(false, Containment::NetworkIsolated, spec, name),
            "{spec}/{name} must run when the context is isolated"
        );
        // Windows has no sandbox: only the pairs with their own Windows entry run, and then on
        // the environment table alone.
        assert!(
            !is_generator_allowed_on(true, Containment::NetworkIsolated, spec, name)
                || ALLOWED_ON_WINDOWS_WITH_ENVIRONMENT.contains(&(*spec, *name)),
            "{spec}/{name} must not run on Windows"
        );
    }
    // Isolation does not unlock anything else.
    for (spec, name, _) in DENIED_GENERATORS {
        for windows in [false, true] {
            assert!(
                !is_generator_allowed_on(windows, Containment::NetworkIsolated, spec, name),
                "{spec}/{name} is denied even in an isolated context (windows: {windows})"
            );
        }
    }
}

#[cfg(not(windows))]
#[test]
fn an_isolated_context_runs_the_restored_generators_and_a_plain_one_does_not() {
    for (input, marker) in [
        ("cargo run --bin ", "cargo metadata"),
        ("docker start ", "docker ps"),
        ("npm install -w ", "npm prefix"),
    ] {
        let plain = guarded().commands_for(input);
        assert!(
            !plain.iter().any(|command| command.contains(marker)),
            "{input:?} ran {marker:?} without isolation: {plain:?}"
        );
        let isolated = guarded_isolated().commands_for(input);
        assert!(
            isolated.iter().any(|command| command.contains(marker)),
            "{input:?} should run {marker:?} in an isolated context, got {isolated:?}"
        );
    }
    // Isolation does not make a network generator run.
    for (input, marker) in NETWORK_INPUTS {
        let executed = guarded_isolated().commands_for(input);
        assert!(
            !executed.iter().any(|command| command.contains(marker)),
            "{input:?} ran the {marker:?} generator in an isolated context: {executed:?}"
        );
    }
}

/// The real shells the tests run generator commands in, started the way a local session starts
/// them (`LocalCommandExecutor`: `zsh -f -c`, `bash --norc -c`, `fish --no-config -c`,
/// `pwsh -NoProfile -c`). A generator command of a fish or PowerShell session is run by that
/// shell itself, never by `sh`: the executor passes the command string to the session's own shell.
///
/// bash, zsh and sh are on every Unix host the tests run on. fish and `pwsh` (PowerShell 7) are
/// not. When one is missing the tests that need it say so and skip it, unless `CI` is set (GitHub
/// Actions sets it): there a missing fish or pwsh fails the test, because a run that silently
/// skips them proves nothing about them. `OPENRUN_TEST_FISH` and `OPENRUN_TEST_PWSH` name an
/// executable that is not on `PATH`.
#[cfg(unix)]
mod real_shells {
    use std::path::{Path, PathBuf};

    use warp_command_signatures::Shell;
    use warp_util::path::ShellFamily;

    #[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug)]
    pub enum ShellKind {
        /// bash, zsh and sh.
        Posix,
        Fish,
        PowerShell,
    }

    impl ShellKind {
        pub fn family(self) -> ShellFamily {
            match self {
                ShellKind::Posix | ShellKind::Fish => ShellFamily::Posix,
                ShellKind::PowerShell => ShellFamily::PowerShell,
            }
        }

        /// The syntax the completion engine builds generator commands in for this shell.
        pub fn command_syntax(self) -> Shell {
            match self {
                ShellKind::Posix | ShellKind::Fish => Shell::Posix,
                ShellKind::PowerShell => Shell::Powershell,
            }
        }

        /// A command that creates the file `name` in `dir` using only what the shell has built
        /// in (the shells run with an empty `PATH`).
        pub fn create_file(self, dir: &str, name: &str) -> String {
            match self {
                ShellKind::Posix | ShellKind::Fish => format!("true > {dir}/{name}"),
                ShellKind::PowerShell => format!("Set-Content {dir}/{name} 1"),
            }
        }

        /// A typed line written for a POSIX shell, in this shell's syntax: only the command that
        /// prints a marker differs. fish and PowerShell print their parse errors with the source
        /// line, which would contain the marker even if nothing ran, so for them the marker is
        /// printed from two pieces and the source never holds it whole (with no quote and no `$(`, which
        /// a generator quotes again or the tokenizer rewrites).
        pub fn typed_line(self, posix_line: &str) -> String {
            let print = regex::Regex::new(r"printf ASTRA_(\w+)").unwrap();
            match self {
                ShellKind::Posix => posix_line.to_owned(),
                ShellKind::Fish => print
                    .replace_all(posix_line, "printf ASTRA_%s $1")
                    .into_owned(),
                ShellKind::PowerShell => print
                    .replace_all(posix_line, "Write-Host -NoNewline ASTRA_; Write-Host $1")
                    .into_owned(),
            }
        }
    }

    #[derive(Clone, Debug)]
    pub struct RealShell {
        pub label: &'static str,
        pub program: PathBuf,
        pub args: &'static [&'static str],
        pub kind: ShellKind,
    }

    impl RealShell {
        /// Runs `command` as `program args -c command` with an empty `PATH`, `empty` as the
        /// working directory and `HOME`, and nothing else in the environment except what
        /// PowerShell needs to start offline.
        pub fn run(&self, command: &str, empty: &Path) -> std::io::Result<std::process::Output> {
            let mut process = command::blocking::Command::new(&self.program);
            process
                .args(self.args.iter())
                .arg("-c")
                .arg(command)
                .env_clear()
                .env("PATH", empty)
                .env("HOME", empty)
                .current_dir(empty)
                .stdin(std::process::Stdio::null());
            if self.kind == ShellKind::PowerShell {
                process
                    .env("POWERSHELL_UPDATECHECK", "Off")
                    .env("POWERSHELL_TELEMETRY_OPTOUT", "1")
                    .env("DOTNET_CLI_TELEMETRY_OPTOUT", "1")
                    .env("DOTNET_NOLOGO", "1");
            }
            process.output()
        }
    }

    impl RealShell {
        /// Whether the shell accepts `command` as a script without running it. Only fish is
        /// asked (`fish -n`): its syntax differs from the POSIX shells the dependency's
        /// commands are written for (`${VAR:-x}` is a syntax error in fish, so such a command
        /// can never run there), and a command that cannot parse is not worth 2,000 runs.
        pub fn parses(&self, command: &str, empty: &Path) -> bool {
            if self.kind != ShellKind::Fish {
                return true;
            }
            command::blocking::Command::new(&self.program)
                .args(self.args.iter())
                .arg("-n")
                .arg("-c")
                .arg(command)
                .env_clear()
                .env("PATH", empty)
                .env("HOME", empty)
                .current_dir(empty)
                .stdin(std::process::Stdio::null())
                .output()
                .is_ok_and(|output| output.status.success())
        }
    }

    fn running_in_ci() -> bool {
        std::env::var_os("CI").is_some_and(|value| !value.is_empty() && value != "false")
    }

    fn find_executable(name: &str, override_variable: &str) -> Option<PathBuf> {
        if let Some(path) = std::env::var_os(override_variable) {
            let path = PathBuf::from(path);
            return path.is_file().then_some(path);
        }
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

    /// `fish` or `pwsh`: the executable, or `None` outside CI with a message saying that the
    /// shell is skipped. In CI a missing shell fails the test.
    fn required_shell(
        label: &'static str,
        args: &'static [&'static str],
        kind: ShellKind,
        override_variable: &str,
    ) -> Option<RealShell> {
        match find_executable(label, override_variable) {
            Some(program) => Some(RealShell {
                label,
                program,
                args,
                kind,
            }),
            None if running_in_ci() => panic!(
                "{label} is not installed and CI is set: the injection tests must run in {label}, \
                 install it on the runner (or set {override_variable})"
            ),
            None => {
                static NOTIFIED: std::sync::Mutex<Vec<&str>> = std::sync::Mutex::new(Vec::new());
                let mut notified = NOTIFIED.lock().unwrap();
                if !notified.contains(&label) {
                    notified.push(label);
                    eprintln!(
                        "SKIPPED: {label} is not installed, so the injection tests do not run in \
                         {label} here (CI installs it and fails without it; set \
                         {override_variable} to a {label} executable to run them)"
                    );
                }
                None
            }
        }
    }

    /// The shells the injection tests run in: bash, zsh and sh where they exist, then fish and
    /// PowerShell 7.
    pub fn installed_shells() -> Vec<RealShell> {
        let mut shells: Vec<_> = [
            ("bash", "/bin/bash", &["--norc"][..]),
            ("zsh", "/bin/zsh", &["-f"][..]),
            ("zsh", "/usr/bin/zsh", &["-f"][..]),
            ("sh", "/bin/sh", &[][..]),
        ]
        .into_iter()
        .filter(|(_, path, _)| Path::new(path).exists())
        .map(|(label, path, args)| RealShell {
            label,
            program: PathBuf::from(path),
            args,
            kind: ShellKind::Posix,
        })
        .collect();
        assert!(!shells.is_empty(), "no POSIX shell to run the tests in");
        shells.extend(required_shell(
            "fish",
            &["--no-config"],
            ShellKind::Fish,
            "OPENRUN_TEST_FISH",
        ));
        shells.extend(required_shell(
            "pwsh",
            &["-NoProfile"],
            ShellKind::PowerShell,
            "OPENRUN_TEST_PWSH",
        ));
        shells
    }
}

#[cfg(unix)]
use real_shells::installed_shells;

/// The exact input of the RV-01 report, through the production suggestions engine and real
/// shells: the command that used to be generated for `docker run` printed a marker. Without the
/// policy it still does (the reproduction); with it, nothing runs.
#[cfg(unix)]
#[test]
fn typing_a_quoted_command_in_an_image_name_executes_nothing() {
    const MARKER: &str = "ASTRA_GENERATOR_INJECTION";
    let inputs = [
        r#"docker run "astra'; printf ASTRA_GENERATOR_INJECTION; #":tag"#,
        r#"docker image rm "astra'; printf ASTRA_GENERATOR_INJECTION; #":tag"#,
    ];
    for shell in installed_shells() {
        let inputs = inputs.map(|input| shell.kind.typed_line(input));
        let control = unrestricted().in_shell(&shell);
        for input in &inputs {
            control.commands_for(input);
            assert!(
                control.stdout.lock().unwrap().contains(MARKER),
                "without the policy {input:?} should print {MARKER} in {shell:?} (the \
                 reproduction), ran {:?}",
                control.commands.lock().unwrap()
            );
            control.stdout.lock().unwrap().clear();
        }

        for isolated in [false, true] {
            let guarded = if isolated {
                guarded_isolated()
            } else {
                guarded()
            }
            .in_shell(&shell);
            for input in &inputs {
                let commands = guarded.commands_for(input);
                assert!(
                    !guarded.stdout.lock().unwrap().contains(MARKER),
                    "{input:?} executed injected shell code in {shell:?}, commands: {commands:?}"
                );
                assert!(
                    !commands.iter().any(|command| command.contains("image ls")),
                    "{input:?} ran {commands:?}"
                );
            }
        }
    }
}

#[test]
fn windows_runs_only_generators_that_read_files_and_take_no_tokens() {
    for (spec, name) in ALLOWED_ON_WINDOWS {
        assert!(
            ALLOWED_GENERATORS.contains(&(*spec, *name)),
            "{spec}/{name} is on the Windows list but not on the allow-list"
        );
        assert!(
            is_generator_allowed_on(true, Containment::Unrestricted, spec, name),
            "{spec}/{name}"
        );
        assert!(
            is_generator_allowed_on(false, Containment::Unrestricted, spec, name),
            "{spec}/{name}"
        );
    }
    assert!(
        ALLOWED_ON_WINDOWS.windows(2).all(|pair| pair[0] < pair[1]),
        "ALLOWED_ON_WINDOWS must be sorted without duplicates"
    );
    // Everything else that starts another program is allowed elsewhere and denied on Windows,
    // whatever the context guarantees.
    for (spec, name) in [
        ("docker", "from_as"),
        ("kill", "process"),
        ("brew", "services"),
        ("kubectx", "context"),
        ("git-flow", "type_branches"),
    ] {
        let allowed_elsewhere =
            is_generator_allowed_on(false, Containment::Unrestricted, spec, name);
        assert_eq!(
            allowed_elsewhere,
            DENIED_GENERATORS
                .iter()
                .all(|(s, g, _)| !(*s == spec && *g == name)),
            "{spec}/{name}"
        );
        for containment in [
            Containment::Unrestricted,
            Containment::OfflineEnvironment,
            Containment::NetworkIsolated,
        ] {
            assert!(
                !is_generator_allowed_on(true, containment, spec, name),
                "{spec}/{name} ({containment:?})"
            );
        }
    }

    let pure: BTreeSet<&str> = [
        "cat",
        "ls",
        "find",
        "grep",
        "egrep",
        "awk",
        "sed",
        "cut",
        "sort",
        "uniq",
        "tr",
        "head",
        "tail",
        "printf",
        "echo",
        "xargs",
        "dirname",
        "basename",
        "true",
        "test",
        "expr",
        "read",
        "cd",
        "Get-Variable",
        "Get-Process",
        "Get-Command",
        "Where-Object",
        "Select-Object",
        "Sort-Object",
        "Get-Unique",
        "until",
        "while",
        "if",
        "for",
        "elif",
        "done",
        "fi",
        "in",
        "i",
        "r",
        "v",
        "p",
        "d",
    ]
    .into_iter()
    .collect();
    let quoted = Regex::new(r#"'[^']*'|"[^"]*""#).unwrap();
    let separator = Regex::new(r"\||;|&&|\$\(|\)|\{|\}|\n|`|\bdo\b|\bthen\b|\belse\b").unwrap();
    let leading = Regex::new(
        r"^(?:(?:until|while|if|for|elif)\b\s*)?(?:\[\[.*?\]\]\s*)?(?:\w+=\S+\s+)*\\?([A-Za-z][\w.-]*)",
    )
    .unwrap();
    let allowed_on_windows: BTreeSet<_> = ALLOWED_ON_WINDOWS.iter().copied().collect();
    let mut checked = 0;
    for (spec, name, generator) in bundled_generators() {
        if !allowed_on_windows.contains(&(spec.as_str(), name.as_str())) {
            continue;
        }
        checked += 1;
        let GeneratorProcess::ShellCommand(command) = &generator.process else {
            panic!("{spec}/{name} takes the user's tokens, so it cannot run on Windows");
        };
        let command = command.build(Shell::Posix).to_string();
        let stripped = quoted.replace_all(&command, "''").into_owned();
        assert!(
            !stripped.contains("sh -c"),
            "{spec}/{name} starts a nested shell: {command}"
        );
        for segment in separator.split(&stripped) {
            if let Some(captures) = leading.captures(segment.trim()) {
                assert!(
                    pure.contains(&captures[1]),
                    "{spec}/{name} starts {:?}, which is not a file read or cmdlet: {command}",
                    &captures[1]
                );
            }
        }
    }
    assert_eq!(checked, ALLOWED_ON_WINDOWS.len());
}

/// The git generators that run on Windows once the executor applies the offline environment
/// table. Spelled out here so that a change to the list in `allowed.rs` shows up as a diff of
/// this test.
const WINDOWS_GIT_GENERATORS: &[(&str, &str)] = &[
    ("checkov", "git_branch"),
    ("gh", "git_branch"),
    ("git", "aliases"),
    ("git", "commits"),
    ("git", "local_branches"),
    ("git", "local_or_remote_branch"),
    ("git", "push_refspec_branches"),
    ("git", "push_refspec_tags"),
    ("git", "refs_remote_branches"),
    ("git", "remote_branches"),
    ("git", "remotes"),
    ("git", "revs"),
    ("git", "settings_generator"),
    ("git", "stashes"),
    ("git", "tags"),
    ("git", "tracked_files"),
    ("git", "treeish"),
    ("git", "worktrees"),
    ("gt", "commits"),
    ("gt", "local_branches"),
    ("hub", "aliases"),
    ("hub", "branches"),
    ("hub", "branches_no"),
    ("hub", "log"),
    ("hub", "remotes"),
    ("hub", "revs"),
    ("hub", "settings_generator"),
    ("hub", "stashes"),
    ("hub", "tag"),
    ("hub", "treeish"),
    ("lerna", "git_branch"),
    ("lerna", "git_remote"),
    ("pnpm", "search_branches"),
    ("pre-commit", "git_branch"),
    ("pre-commit", "git_branch_no"),
    ("pre-commit", "git_remote"),
    ("pre-commit", "git_rev_list"),
    ("turbo", "git_branch"),
    ("vsce", "git_branch"),
];

/// Generators whose command is a git invocation and that are not on the Windows list, with why.
const GIT_GENERATORS_OFF_ON_WINDOWS: &[(&str, &str, &str)] = &[
    ("git", "files_for_staging", "status-like: clean filter"),
    (
        "git",
        "get_changed_or_tracked_files",
        "status-like: clean filter",
    ),
    ("hub", "status", "status-like: clean filter"),
    (
        "hub",
        "status_staged_or_unstaged",
        "status-like: clean filter",
    ),
    (
        "git-flow",
        "type_branches",
        "POSIX pipeline that takes a word",
    ),
    ("codex", "commits", "denied spec"),
    ("codex", "local_branches", "denied spec"),
];

#[test]
fn the_windows_git_list_is_pinned() {
    assert_eq!(ALLOWED_ON_WINDOWS_WITH_ENVIRONMENT, WINDOWS_GIT_GENERATORS);
    assert_eq!(WINDOWS_GIT_GENERATORS.len(), 39);
    assert!(
        WINDOWS_GIT_GENERATORS
            .windows(2)
            .all(|pair| pair[0] < pair[1]),
        "the Windows git list must be sorted without duplicates"
    );
    for pair in WINDOWS_GIT_GENERATORS {
        assert!(
            ALLOWED_GENERATORS.contains(pair) || ALLOWED_WHEN_ISOLATED.contains(pair),
            "{pair:?} is on the Windows git list but on no allow-list"
        );
        assert!(
            !ALLOWED_ON_WINDOWS.contains(pair),
            "{pair:?} is on both Windows lists"
        );
        assert!(
            !DENIED_GENERATORS
                .iter()
                .any(|(s, g, _)| (s, g) == (&pair.0, &pair.1)),
            "{pair:?} is denied"
        );
    }
    for (spec, name, _) in GIT_GENERATORS_OFF_ON_WINDOWS {
        assert!(
            !WINDOWS_GIT_GENERATORS.contains(&(*spec, *name)),
            "{spec}/{name} must stay off on Windows"
        );
        for containment in [
            Containment::Unrestricted,
            Containment::OfflineEnvironment,
            Containment::NetworkIsolated,
        ] {
            assert!(
                !is_generator_allowed_on(true, containment, spec, name),
                "{spec}/{name} ({containment:?})"
            );
        }
    }
}

#[test]
fn windows_git_generators_run_only_where_the_offline_environment_is_applied() {
    for (spec, name) in WINDOWS_GIT_GENERATORS {
        assert!(
            !is_generator_allowed_on(true, Containment::Unrestricted, spec, name),
            "{spec}/{name} must not run on Windows without the offline environment table"
        );
        for containment in [
            Containment::OfflineEnvironment,
            Containment::NetworkIsolated,
        ] {
            assert!(
                is_generator_allowed_on(true, containment, spec, name),
                "{spec}/{name} ({containment:?})"
            );
        }
        // Other platforms are unchanged: the allow-list pairs always run, the isolated-tier pairs
        // only in an isolated context.
        let isolated_only = ALLOWED_WHEN_ISOLATED.contains(&(*spec, *name));
        assert_eq!(
            is_generator_allowed_on(false, Containment::OfflineEnvironment, spec, name),
            !isolated_only,
            "{spec}/{name}"
        );
        assert!(is_generator_allowed_on(
            false,
            Containment::NetworkIsolated,
            spec,
            name
        ));
    }
}

/// The git subcommands a generator on the Windows list may run, with the option that makes each
/// a read of the local repository. Network subcommands (`fetch`, `pull`, `push`, `clone`,
/// `ls-remote`, `remote show`/`update`, `submodule`) and the status-like ones (`status`, `diff`
/// without `--cached`, `ls-files --modified`) are not among them.
const LOCAL_GIT_READS: &str = r"^git (?:--no-optional-locks )?(?:branch|tag|remote|log|rev-list|for-each-ref|stash list|worktree list|config --get-regexp|ls-files|diff --cached --name-only)\b[^|;&$`<>]*$";

#[test]
fn every_windows_git_generator_runs_exactly_one_local_git_read_in_every_shell_family() {
    let command = Regex::new(LOCAL_GIT_READS).unwrap();
    let forbidden = Regex::new(
        r"\b(?:fetch|pull|push|clone|ls-remote|submodule|status|remote (?:show|update|add|set-url|prune)|--modified|--others)\b",
    )
    .unwrap();
    let hostile_tokens: [&[&str]; 3] = [
        &["git", "checkout", "ab"],
        &["git", "push", "origin", "$(touch x)", "`id`", "'; id; '"],
        &["git", "--help", "-C", "x"],
    ];
    let windows: BTreeSet<_> = WINDOWS_GIT_GENERATORS.iter().copied().collect();
    let mut checked = 0;
    for (spec, name, generator) in bundled_generators() {
        if !windows.contains(&(spec.as_str(), name.as_str())) {
            continue;
        }
        checked += 1;
        for shell in [Shell::Posix, Shell::Powershell, Shell::CmdExe] {
            let commands: BTreeSet<String> = match &generator.process {
                GeneratorProcess::ShellCommand(command) => {
                    BTreeSet::from([command.build(shell).to_string()])
                }
                GeneratorProcess::CommandFromTokens(command_from_tokens) => {
                    assert_eq!(
                        super::token_policy(&spec, &name),
                        TokenPolicy::Inert,
                        "{spec}/{name} takes tokens and is not Inert, so it cannot run on Windows"
                    );
                    hostile_tokens
                        .iter()
                        .flat_map(|tokens| {
                            [false, true].map(|trailing_whitespace| {
                                command_from_tokens(tokens, trailing_whitespace, &[])
                                    .build(shell)
                                    .to_string()
                            })
                        })
                        .collect()
                }
            };
            assert_eq!(
                commands.len(),
                1,
                "{spec}/{name} builds different commands from different words: {commands:?}"
            );
            let only = commands.into_iter().next().unwrap();
            assert!(
                command.is_match(&only) && !forbidden.is_match(&only),
                "{spec}/{name} is not one local git read: {only}"
            );
        }
    }
    assert_eq!(checked, WINDOWS_GIT_GENERATORS.len());
}

#[test]
fn the_status_like_git_generators_never_run_in_any_context() {
    let unrestricted = unrestricted();
    let mut isolated = guarded_with_environment();
    isolated.isolated = true;
    let contexts = [
        ("plain", guarded()),
        ("environment", guarded_with_environment()),
        ("isolated", isolated),
    ];
    for (input, marker) in [
        ("git diff ", "diff --diff-filter"),
        ("git add ", "ls-files -z --exclude-standard"),
    ] {
        let reachable = unrestricted.commands_for(input);
        assert!(
            reachable.iter().any(|command| command.contains(marker)),
            "{input:?} should reach {marker:?} without the policy, got {reachable:?}"
        );
        for (label, context) in &contexts {
            let executed = context.commands_for(input);
            assert!(
                !executed.iter().any(|command| command.contains(marker)),
                "{input:?} ran {marker:?} in a {label} context: {executed:?}"
            );
        }
    }
    for (spec, name, _) in GIT_GENERATORS_OFF_ON_WINDOWS
        .iter()
        .filter(|(_, _, why)| why.starts_with("status-like"))
    {
        for windows in [false, true] {
            assert!(
                !is_generator_allowed_on(windows, Containment::NetworkIsolated, spec, name),
                "{spec}/{name} (windows: {windows})"
            );
        }
    }
}

/// On Windows, the engine itself, with the bundled registry: git completions run when the
/// executor applies the table and not otherwise, and a typed word still has to pass the strict
/// token gate.
#[cfg(windows)]
#[test]
fn git_completions_run_on_windows_only_with_the_offline_environment() {
    for (input, marker) in [
        ("git checkout ", "branch"),
        ("git stash apply ", "stash"),
        ("git tag -d ", "tag --list"),
    ] {
        // The alias generator (`git config --get alias.<word>`) runs in every context, behind the
        // token gate, as it always has.
        let plain = guarded().commands_for(input);
        assert!(
            !plain.iter().any(|command| command.starts_with("git")
                && !command.starts_with("git config --get alias.")),
            "{input:?} ran git without the offline environment: {plain:?}"
        );
        let with_environment = guarded_with_environment().commands_for(input);
        assert!(
            with_environment
                .iter()
                .any(|command| command.starts_with("git") && command.contains(marker)),
            "{input:?} should run git {marker:?} with the offline environment: {with_environment:?}"
        );
    }
}

fn bundled_alias_generators() -> BTreeSet<(String, String)> {
    let mut all = BTreeSet::new();
    for (spec, data) in warp_command_signatures::dynamic_command_signature_data() {
        for name in data.aliases().keys() {
            all.insert((spec.to_lowercase(), name.0.clone()));
        }
    }
    all
}

#[test]
fn every_bundled_alias_generator_is_classified() {
    let bundled = bundled_alias_generators();
    assert!(
        !bundled.is_empty(),
        "the bundled specs define alias generators"
    );
    let listed: BTreeSet<(String, String)> = ALLOWED_ALIAS_GENERATORS
        .iter()
        .map(|(s, a)| (s.to_string(), a.to_string()))
        .chain(
            DENIED_ALIAS_GENERATORS
                .iter()
                .map(|(s, a, _)| (s.to_string(), a.to_string())),
        )
        .collect();
    let unclassified: Vec<_> = bundled.difference(&listed).collect();
    assert!(
        unclassified.is_empty(),
        "alias generators in neither ALLOWED_ALIAS_GENERATORS nor DENIED_ALIAS_GENERATORS: \
         {unclassified:?}"
    );
    let stale: Vec<_> = listed.difference(&bundled).collect();
    assert!(
        stale.is_empty(),
        "listed alias generators that no longer exist: {stale:?}"
    );
}

#[test]
fn only_the_git_alias_generator_runs_and_only_for_inert_words() {
    let guarded = guarded();
    let unrestricted = unrestricted();
    // `npm` and `yarn` run `npm prefix`, which is denied.
    for input in ["npm run build ", "yarn run build "] {
        let reachable = unrestricted.commands_for(input);
        assert!(
            reachable
                .iter()
                .any(|command| command.contains("npm prefix")),
            "{input:?} should reach the npm alias generator without the policy, got {reachable:?}"
        );
        let executed = guarded.commands_for(input);
        assert!(
            !executed
                .iter()
                .any(|command| command.contains("npm prefix")),
            "{input:?} ran {executed:?}"
        );
    }
    // The git alias generator builds `git config --get alias.{word}`.
    assert!(
        guarded
            .commands_for("git co ")
            .contains(&"git config --get alias.co".to_owned())
    );
    for hostile in [
        "co;touch${IFS}x",
        "co$(touch x)",
        "co`touch x`",
        "co'x",
        "co|x",
        "co&x",
        "co>x",
        "co\\x",
        "=co",
        "~co",
    ] {
        for input in [format!("git '{hostile}' "), format!("git \"{hostile}\" ")] {
            let reachable = unrestricted.commands_for(&input);
            let executed = guarded.commands_for(&input);
            assert!(
                !executed
                    .iter()
                    .any(|command| command.contains("--get alias.")),
                "{input:?} ran {executed:?} (without the policy: {reachable:?})"
            );
        }
    }
}

#[test]
fn is_alias_generator_allowed_matches_the_listed_pairs() {
    for (spec, name) in ALLOWED_ALIAS_GENERATORS {
        assert!(is_alias_generator_allowed(spec, name), "{spec}/{name}");
    }
    for (spec, name, _) in DENIED_ALIAS_GENERATORS {
        assert!(!is_alias_generator_allowed(spec, name), "{spec}/{name}");
    }
}

#[cfg(not(windows))]
#[test]
fn is_generator_allowed_matches_the_listed_pairs() {
    use super::is_generator_allowed;
    for (spec, name) in ALLOWED_GENERATORS {
        assert!(
            is_generator_allowed(spec, name, Containment::Unrestricted),
            "{spec}/{name}"
        );
    }
    for (spec, name, _) in DENIED_GENERATORS {
        assert!(
            !is_generator_allowed(spec, name, Containment::Unrestricted),
            "{spec}/{name}"
        );
    }
}
/// Types the package-manager commands that used to fetch from public registries, with a stub
/// `curl` as the only `curl` the generator shell can find. The stub logs its arguments and
/// fails; nothing in this test opens a socket.
#[cfg(unix)]
#[test]
fn a_stub_curl_is_never_invoked_while_completing_package_names() {
    use std::os::unix::fs::PermissionsExt;

    let dir = std::env::temp_dir().join(format!("openrun-stub-curl-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let log = dir.join("curl.log");
    let stub = dir.join("curl");
    std::fs::write(
        &stub,
        format!("#!/bin/sh\necho \"$@\" >> '{}'\nexit 22\n", log.display()),
    )
    .unwrap();
    std::fs::set_permissions(&stub, std::fs::Permissions::from_mode(0o755)).unwrap();

    let inputs = [
        "npm install astra",
        "yarn add astra",
        "cargo add astra",
        "bun add astra",
    ];

    let mut control = unrestricted();
    control.stub_curl_dir = Some(dir.clone());
    for input in inputs {
        control.commands_for(input);
    }
    let control_log = std::fs::read_to_string(&log).unwrap_or_default();
    assert_eq!(
        control_log.lines().count(),
        inputs.len(),
        "without the policy each input reaches the stub curl: {control_log:?}"
    );
    std::fs::remove_file(&log).unwrap();

    let mut guarded = guarded();
    guarded.stub_curl_dir = Some(dir.clone());
    for input in inputs {
        guarded.commands_for(input);
    }
    let guarded_log = std::fs::read_to_string(&log).unwrap_or_default();
    std::fs::remove_dir_all(&dir).unwrap();
    assert_eq!(
        guarded_log, "",
        "the stub curl was invoked with the policy on"
    );
}

/// Hostile tokens run through every token-taking generator, then the resulting command is run
/// in real shells that have no program to run: an empty `PATH`, so only shell builtins work.
/// The payloads are shell syntax that creates a marker file with a builtin. A generator is
/// injectable when a marker appears, because then the user's token was executed as shell code
/// instead of being used as data.
#[cfg(unix)]
mod injection_corpus {
    use std::collections::{BTreeMap, BTreeSet};
    use std::path::{Path, PathBuf};

    use warp_command_signatures::GeneratorProcess;
    use warp_util::path::ShellFamily;

    use super::real_shells::{RealShell, ShellKind, installed_shells};
    use super::{
        ALLOWED_GENERATORS, ALLOWED_WHEN_ISOLATED, GATED_INJECTABLE_GENERATORS,
        STILL_DENIED_INJECTABLE_GENERATORS, TokenPolicy, bundled_generators, listed_token_policies,
        sanitize_env_vars, token_policy,
    };

    /// `{CMD}` is replaced with the shell's command that creates the marker file named by the
    /// payload (`true > dir/name`, or `Set-Content dir/name 1` in PowerShell), so it works with
    /// an empty `PATH`; `{M}` with the marker directory. None contains `,` `:` or `=`, which
    /// some generators split on.
    const COMMON_PAYLOADS: &[(&str, &str)] = &[
        ("sq", "XINJ'; {CMD} #"),
        ("dq", "XINJ\"; {CMD} #"),
        ("cs", "XINJ$({CMD})"),
        ("bt", "XINJ`{CMD}`"),
        ("sc", "XINJ; {CMD} #"),
        ("nl", "XINJ\n{CMD}\n"),
        ("amp", "XINJ & {CMD} & "),
        ("pipe", "XINJ | {CMD} #"),
        ("sqcs", "XINJ'$({CMD})'"),
        ("dqcs", "XINJ\"$({CMD})\""),
        ("glob", "XINJ*; {CMD} #"),
        ("andand", "XINJ && {CMD} #"),
        ("oror", "XINJ || {CMD} #"),
    ];

    /// Payloads that only mean something to some shells. fish: a backslash before the quote
    /// (`\'` is an escaped quote inside fish's single quotes, so the POSIX quoting `'\''` closes
    /// the string early) and `(...)` command substitution. PowerShell: the typographic quotes it
    /// reads as quotes, a backtick before a quote, and `@(...)`.
    fn extra_payloads(kind: ShellKind) -> &'static [(&'static str, &'static str)] {
        match kind {
            ShellKind::Posix => &[("brace", "XINJ{true,true}>{M}/brace")],
            ShellKind::Fish => &[
                ("brace", "XINJ{true,true}>{M}/brace"),
                ("bs", "XINJ\\'; {CMD} #"),
                ("bs2", "XINJ\\\\'; {CMD} #"),
                ("bsdq", "XINJ\\\"; {CMD} #"),
                ("bscs", "XINJ\\'$({CMD})'"),
                ("fcs", "XINJ({CMD})"),
                ("fcsq", "XINJ'({CMD})"),
            ],
            ShellKind::PowerShell => &[
                ("lsq", "XINJ\u{2018}; {CMD} #"),
                ("rsq", "XINJ\u{2019}; {CMD} #"),
                ("lbq", "XINJ\u{201a}; {CMD} #"),
                ("hbq", "XINJ\u{201b}; {CMD} #"),
                ("ldq", "XINJ\u{201c}; {CMD} #"),
                ("rdq", "XINJ\u{201d}; {CMD} #"),
                ("bq", "XINJ`'; {CMD} #"),
                ("bqdq", "XINJ`\"; {CMD} #"),
                ("arr", "XINJ@({CMD})"),
                ("sqplus", "XINJ'+$({CMD})+'"),
            ],
        }
    }

    /// The payloads run in PowerShell where the point is only that it executes a payload at all
    /// (every command that does not inject costs a PowerShell start, a fraction of a second on a
    /// fast machine and several seconds on a CI runner).
    const POWERSHELL_PROBE: &[&str] = &["sc", "sq", "cs"];

    fn payloads(kind: ShellKind) -> Vec<(&'static str, &'static str)> {
        COMMON_PAYLOADS
            .iter()
            .chain(extra_payloads(kind))
            .copied()
            .collect()
    }

    /// How the payload is embedded in a token, covering generators that split on `,` `:` `=`
    /// or on the last `:`.
    const WRAPPERS: &[&str] = &["{p}", "{p}:tag", "a,{p},", "a:{p}:", "k=a,{p},", "k=a:{p}:"];

    /// Flags the bundled generators read the value of, plus a few others for margin.
    const FLAGS: &[&str] = &[
        "-f",
        "--file",
        "-o",
        "--context",
        "--namespace",
        "-n",
        "--kubeconfig",
        "--cluster",
        "--user",
        "--staged",
        "--cached",
    ];

    fn marker_dir(label: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("openrun-inject-{}-{label}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    /// Every command the generator can build from the hostile tokens, as a set.
    fn hostile_commands(
        kind: ShellKind,
        spec: &str,
        command_from_tokens: fn(
            &[&str],
            bool,
            &[String],
        ) -> warp_command_signatures::CommandBuilder,
        marker_dir: &Path,
        gate: Option<&Gate<'_>>,
        only_payloads: Option<&[&str]>,
    ) -> BTreeSet<String> {
        let marker_dir = marker_dir.to_str().unwrap();
        let mut commands = BTreeSet::new();
        // With `gate`, the tokens and environment words go through the engine's token gate
        // first, as they do in production; without it the closure sees every hostile word.
        let mut build = |tokens: &[&str], trailing_whitespace: bool, env: &[String]| {
            let env = match gate {
                Some(permits) => {
                    if !permits(tokens) {
                        return;
                    }
                    sanitize_env_vars(env)
                }
                None => env.to_vec(),
            };
            commands.insert(
                command_from_tokens(tokens, trailing_whitespace, &env)
                    .build(kind.command_syntax())
                    .to_string(),
            );
        };
        for (name, payload) in payloads(kind) {
            if only_payloads.is_some_and(|only| !only.contains(&name)) {
                continue;
            }
            let payload = payload
                .replace("{CMD}", &kind.create_file(marker_dir, name))
                .replace("{M}", marker_dir);
            for wrapper in WRAPPERS {
                let p = wrapper.replace("{p}", &payload);
                let p = p.as_str();
                build(&[spec, p], false, &[]);
                build(&[spec, p], true, &[]);
                build(&[spec, "x", p], false, &[]);
                build(&[spec, p, "x"], true, &[]);
                build(&[spec, "x", "y", p], false, &[]);
                build(&[spec, "x", p, "y"], true, &[]);
                build(&[spec, "x", "y", p, "z"], true, &[]);
                if *wrapper == "{p}" || *wrapper == "{p}:tag" {
                    for flag in FLAGS {
                        build(&[spec, flag, p, "z"], true, &[]);
                        build(&[spec, "x", flag, p], false, &[]);
                        let joined = format!("{flag}={p}");
                        build(&[spec, joined.as_str()], false, &[]);
                    }
                }
                let env = [format!("KUBECONFIG={p}"), format!("FOO={p}")];
                build(&[spec, "get"], true, &env);
                build(&[spec, "get", "x"], false, &env);
            }
        }
        commands
    }

    /// What a run of commands in the real shells found: the commands that created a marker file
    /// (`injected`, with the shell's label), and how many commands each shell was given.
    #[derive(Default)]
    struct Report {
        injected: Vec<(&'static str, String)>,
        ran: BTreeMap<&'static str, usize>,
    }

    impl Report {
        fn injected_in(&self, label: &str) -> usize {
            self.injected.iter().filter(|(l, _)| *l == label).count()
        }

        fn describe(&self) -> Vec<String> {
            self.injected
                .iter()
                .map(|(label, command)| format!("{label}: {command}"))
                .collect()
        }
    }

    /// Runs `commands_by_kind[kind]` in every installed shell of that kind and reports the
    /// commands that created a marker file. The commands write into `marker_dir`, and each shell
    /// gets its own directory so that the report says which shell ran the injected code.
    fn executed_injections(
        commands_by_kind: &BTreeMap<ShellKind, BTreeSet<String>>,
        marker_dir: &Path,
        stop_at_first: bool,
    ) -> Report {
        let empty = marker_dir.join("empty-path");
        std::fs::create_dir_all(&empty).unwrap();
        let jobs: Vec<(PathBuf, RealShell, Vec<&String>)> = installed_shells()
            .into_iter()
            .enumerate()
            .map(|(index, shell)| {
                let dir = marker_dir.join(format!("shell-{index}"));
                std::fs::create_dir_all(&dir).unwrap();
                let commands = commands_by_kind
                    .get(&shell.kind)
                    .into_iter()
                    .flatten()
                    // A command without the sentinel does not contain any of the typed tokens.
                    .filter(|command| command.contains("XINJ"))
                    .collect();
                (dir, shell, commands)
            })
            .collect();
        let mut report = Report::default();
        std::thread::scope(|scope| {
            let handles: Vec<_> = jobs
                .iter()
                .map(|(dir, shell, commands)| {
                    let empty = &empty;
                    scope.spawn(move || {
                        let mut injected = Vec::new();
                        let mut ran = 0;
                        for command in commands {
                            // Rewrite the marker directory to this shell's own.
                            let command = command
                                .replace(marker_dir.to_str().unwrap(), dir.to_str().unwrap());
                            drop(shell.run(&command, empty));
                            ran += 1;
                            let created: Vec<_> = std::fs::read_dir(dir)
                                .unwrap()
                                .filter_map(Result::ok)
                                .collect();
                            if !created.is_empty() {
                                injected.push((shell.label, command));
                                for entry in created {
                                    let _ = std::fs::remove_file(entry.path());
                                }
                                if stop_at_first {
                                    break;
                                }
                            }
                        }
                        (shell.label, ran, injected)
                    })
                })
                .collect();
            for handle in handles {
                let (label, ran, injected) = handle.join().unwrap();
                *report.ran.entry(label).or_default() += ran;
                report.injected.extend(injected);
            }
        });
        report
    }

    /// Whether `shell` can parse a command of the generator at all, judged from commands built
    /// with plain words.
    fn generator_parses_in(shell: &RealShell, spec: &str, f: TokenGenerator, empty: &Path) -> bool {
        let shapes: [(&[&str], bool); 3] = [
            (&[spec, "x"], true),
            (&[spec, "x"], false),
            (&[spec, "x", "y"], true),
        ];
        shapes.iter().any(|(tokens, trailing)| {
            let command = f(tokens, *trailing, &[])
                .build(shell.kind.command_syntax())
                .to_string();
            shell.parses(&command, empty)
        })
    }

    /// The commands every generator builds from the hostile tokens, for each kind of shell that
    /// is installed (none for a kind whose shell cannot parse the generator's command).
    fn commands_for_installed_kinds(
        spec: &str,
        f: TokenGenerator,
        dir: &Path,
        gate: Option<TokenPolicy>,
    ) -> BTreeMap<ShellKind, BTreeSet<String>> {
        let empty = dir.join("empty-path");
        std::fs::create_dir_all(&empty).unwrap();
        let shells = installed_shells();
        let first_of_each_kind: BTreeMap<ShellKind, &RealShell> =
            shells.iter().map(|shell| (shell.kind, shell)).collect();
        first_of_each_kind
            .into_iter()
            .map(|(kind, shell)| {
                if !generator_parses_in(shell, spec, f, &empty) {
                    eprintln!("{spec}: its command is a syntax error in {}", shell.label);
                    return (kind, BTreeSet::new());
                }
                let permits = |tokens: &[&str]| {
                    gate.is_none_or(|policy| policy.permits(kind.family(), tokens))
                };
                let gate = gate.map(|_| &permits as &Gate<'_>);
                let only =
                    (gate.is_none() && kind == ShellKind::PowerShell).then_some(POWERSHELL_PROBE);
                (kind, hostile_commands(kind, spec, f, dir, gate, only))
            })
            .collect()
    }

    /// Takes the PowerShell commands out of a set built behind the gate and describes each one
    /// that holds a hostile word. The gate gives PowerShell inert words only, so every hostile
    /// word is refused before a command is built and the set must be empty. Running a command
    /// that does reach it would take half a second each, so it is reported instead of run.
    fn commands_that_reached_powershell(
        commands: &mut BTreeMap<ShellKind, BTreeSet<String>>,
    ) -> Vec<String> {
        commands
            .remove(&ShellKind::PowerShell)
            .into_iter()
            .flatten()
            .filter(|command| command.contains("XINJ"))
            .take(3)
            .map(|command| format!("reached PowerShell behind the gate: {command}"))
            .collect()
    }

    /// Whether a gate lets a command line through.
    type Gate<'a> = dyn Fn(&[&str]) -> bool + 'a;

    type TokenGenerator = fn(&[&str], bool, &[String]) -> warp_command_signatures::CommandBuilder;

    fn generators_taking_tokens(
        pairs: impl Iterator<Item = (String, String)>,
    ) -> Vec<(String, String, TokenGenerator)> {
        let wanted: BTreeSet<_> = pairs.collect();
        bundled_generators()
            .into_iter()
            .filter(|(spec, name, _)| wanted.contains(&(spec.clone(), name.clone())))
            .filter_map(|(spec, name, generator)| match generator.process {
                GeneratorProcess::CommandFromTokens(f) => Some((spec, name, f)),
                GeneratorProcess::ShellCommand(_) => None,
            })
            .collect()
    }

    /// The generators listed as `Escaped`, which take the typed words quoted.
    fn escaped_generators() -> impl Iterator<Item = (String, String)> {
        listed_token_policies()
            .iter()
            .filter(|(_, _, policy)| *policy == TokenPolicy::Escaped)
            .map(|(spec, name, _)| (spec.to_string(), name.to_string()))
    }

    #[test]
    fn no_allowed_generator_executes_the_users_tokens() {
        let generators = generators_taking_tokens(
            ALLOWED_GENERATORS
                .iter()
                .chain(ALLOWED_WHEN_ISOLATED)
                .map(|(s, g)| (s.to_string(), g.to_string())),
        );
        assert!(
            !generators.is_empty(),
            "the allow-list contains token-taking generators"
        );
        let mut failures = Vec::new();
        let mut ran: BTreeMap<&str, usize> = BTreeMap::new();
        for (spec, name, f) in generators {
            let dir = marker_dir(&format!("{spec}-{name}"));
            let mut commands =
                commands_for_installed_kinds(&spec, f, &dir, Some(token_policy(&spec, &name)));
            for reached in commands_that_reached_powershell(&mut commands) {
                failures.push(format!("{spec}/{name}: {reached}"));
            }
            let report = executed_injections(&commands, &dir, false);
            for injected in report.describe() {
                failures.push(format!("{spec}/{name}: {injected}"));
            }
            for (label, count) in &report.ran {
                *ran.entry(label).or_default() += count;
            }
            let _ = std::fs::remove_dir_all(&dir);
        }
        eprintln!("hostile commands the gate let through, run in each shell: {ran:?}");
        assert!(
            failures.is_empty(),
            "allowed generators that ran shell code taken from the typed tokens:\n{}",
            failures.join("\n")
        );
        // The shells that quote with `'\''` were given commands (the `Escaped` generators); a
        // zero would mean the corpus no longer exercises them. PowerShell is given none: the
        // gate is `Strict` there, so every hostile word is refused before a command is built (a
        // command that got through is a failure above).
        for shell in installed_shells()
            .iter()
            .filter(|shell| shell.kind != ShellKind::PowerShell)
        {
            let count = ran.get(shell.label).copied().unwrap_or(0);
            assert!(
                count > 100,
                "only {count} hostile commands reached {} behind the gate",
                shell.label
            );
        }
    }

    /// The corpus is only worth something if it catches a real injection: the generators that
    /// are known to interpolate the typed word raw must be reported when the closure sees every
    /// hostile word, and must run nothing behind the gate. That holds for each real shell
    /// separately: a shell that never runs a payload proves nothing about it.
    #[test]
    fn the_corpus_catches_known_injectable_generators_and_the_gate_stops_them() {
        let known: Vec<(&str, &str)> = GATED_INJECTABLE_GENERATORS
            .iter()
            .copied()
            .chain(
                STILL_DENIED_INJECTABLE_GENERATORS
                    .iter()
                    .map(|(spec, name, _)| (*spec, *name)),
            )
            .collect();
        let mut not_raw = Vec::new();
        let mut missed = Vec::new();
        let mut caught_by_shell: BTreeMap<&str, usize> = BTreeMap::new();
        for (spec, name) in known {
            let generators =
                generators_taking_tokens(std::iter::once((spec.to_string(), name.to_string())));
            let (spec, name, f) = generators.into_iter().next().unwrap();
            let dir = marker_dir(&format!("control-{spec}-{name}"));
            let raw = commands_for_installed_kinds(&spec, f, &dir, None);
            let raw_report = executed_injections(&raw, &dir, true);
            if raw_report.injected.is_empty() {
                not_raw.push(format!("{spec}/{name}"));
            }
            for (label, _) in &raw_report.injected {
                *caught_by_shell.entry(label).or_default() += 1;
            }
            // Every shell that can parse the generator's command runs the injected code.
            for shell in installed_shells() {
                let has_commands = raw
                    .get(&shell.kind)
                    .is_some_and(|commands| commands.iter().any(|c| c.contains("XINJ")));
                if has_commands && raw_report.injected_in(shell.label) == 0 {
                    missed.push(format!("{spec}/{name} in {}", shell.label));
                }
            }
            // Fail closed: listing one of the raw generators as `Escaped` would be a false claim,
            // and the corpus shows it.
            if token_policy(&spec, &name) == TokenPolicy::Strict {
                let mut mislabelled =
                    commands_for_installed_kinds(&spec, f, &dir, Some(TokenPolicy::Escaped));
                commands_that_reached_powershell(&mut mislabelled);
                assert!(
                    !executed_injections(&mislabelled, &dir, true)
                        .injected
                        .is_empty(),
                    "{spec}/{name} is raw but the corpus does not catch it under Escaped"
                );
            }
            let mut gated =
                commands_for_installed_kinds(&spec, f, &dir, Some(token_policy(&spec, &name)));
            let mut injected = commands_that_reached_powershell(&mut gated);
            injected.extend(executed_injections(&gated, &dir, false).describe());
            let _ = std::fs::remove_dir_all(&dir);
            assert!(
                injected.is_empty(),
                "{spec}/{name} ran injected code behind the gate: {injected:?}"
            );
        }
        // The `kubectl` family validates its flag words itself and takes the injection through
        // the `KEY=value` words; the others interpolate the word raw. Every one of them must be
        // caught by the corpus without the gate.
        assert!(
            not_raw.is_empty(),
            "the corpus did not catch these known-injectable generators without the gate: {not_raw:?}"
        );
        eprintln!(
            "known-injectable generators caught without the gate, by shell: {caught_by_shell:?}"
        );
        for shell in installed_shells() {
            assert!(
                caught_by_shell.get(shell.label).copied().unwrap_or(0) > 0,
                "no payload of the corpus executed in {} without the gate, so the corpus does \
                 not exercise that shell: {caught_by_shell:?}",
                shell.label
            );
        }
    }

    /// The `Escaped` tier refuses a backslash only because of fish. Show it with fish itself:
    /// the generators that quote with `'\''` are injectable in fish by a word with a backslash
    /// before the quote when the gate lets backslashes through, and not otherwise.
    #[test]
    fn fish_executes_a_backslash_word_that_posix_quoting_does_not_contain() {
        let Some(fish) = installed_shells()
            .into_iter()
            .find(|shell| shell.kind == ShellKind::Fish)
        else {
            return;
        };
        let escaped_generators = generators_taking_tokens(escaped_generators());
        assert!(!escaped_generators.is_empty());
        let (mut with_backslash, mut without) = (0, 0);
        for (spec, name, f) in escaped_generators {
            let dir = marker_dir(&format!("fish-backslash-{spec}-{name}"));
            let empty = dir.join("empty-path");
            std::fs::create_dir_all(&empty).unwrap();
            if !generator_parses_in(&fish, &spec, f, &empty) {
                let _ = std::fs::remove_dir_all(&dir);
                continue;
            }
            let mut all = BTreeMap::new();
            all.insert(
                ShellKind::Fish,
                hostile_commands(
                    ShellKind::Fish,
                    &spec,
                    f,
                    &dir,
                    // The words the `Escaped` gate passes, and the ones with a backslash
                    // that it refuses.
                    Some(&|tokens: &[&str]| {
                        tokens
                            .iter()
                            .all(|token| !token.chars().any(char::is_control))
                    }),
                    None,
                ),
            );
            let report = executed_injections(&all, &dir, false);
            for (label, command) in &report.injected {
                assert_eq!(*label, fish.label);
                if command.contains('\\') {
                    with_backslash += 1;
                } else {
                    without += 1;
                }
            }
            let _ = std::fs::remove_dir_all(&dir);
        }
        eprintln!(
            "fish injections without the gate: {with_backslash} with a backslash, {without} without"
        );
        assert!(
            with_backslash > 0,
            "fish did not execute any word with a backslash through POSIX quoting"
        );
        assert_eq!(
            without, 0,
            "fish executed a word without a backslash: the POSIX quoting does not hold in fish"
        );
    }

    /// `Escaped` is `Strict` on PowerShell because `'\''` is not how PowerShell quotes. Show it
    /// with PowerShell itself: the same generators, building PowerShell commands from the words
    /// the POSIX tier would allow, are injectable.
    #[test]
    fn powershell_executes_words_that_posix_quoting_does_not_contain() {
        let Some(pwsh) = installed_shells()
            .into_iter()
            .find(|shell| shell.kind == ShellKind::PowerShell)
        else {
            return;
        };
        let escaped_generators = generators_taking_tokens(escaped_generators());
        let mut executed = 0;
        for (spec, name, f) in escaped_generators {
            let dir = marker_dir(&format!("pwsh-posix-{spec}-{name}"));
            let mut all = BTreeMap::new();
            all.insert(
                ShellKind::PowerShell,
                hostile_commands(
                    ShellKind::PowerShell,
                    &spec,
                    f,
                    &dir,
                    Some(&|tokens: &[&str]| {
                        TokenPolicy::Escaped.permits(ShellFamily::Posix, tokens)
                    }),
                    Some(POWERSHELL_PROBE),
                ),
            );
            let report = executed_injections(&all, &dir, true);
            executed += report.injected_in(pwsh.label);
            let _ = std::fs::remove_dir_all(&dir);
            // One generator is enough, and each command that does not inject costs a PowerShell
            // start.
            if executed > 0 {
                eprintln!("PowerShell ran the injected code of {spec}/{name} under the POSIX tier");
                break;
            }
        }
        assert!(
            executed > 0,
            "PowerShell executed none of the words that POSIX quoting lets through, so the \
             PowerShell tier would not need to be stricter"
        );
    }

    /// A generator that is not listed in the token policy table is `Strict`: it never sees a
    /// word that is not inert, whatever its closure does with it.
    #[test]
    fn a_generator_missing_from_the_policy_table_is_strict() {
        assert_eq!(
            token_policy("no-such-spec", "no_such_generator"),
            TokenPolicy::Strict
        );
        assert_eq!(
            token_policy("docker", "image_with_tags"),
            TokenPolicy::Strict
        );
        assert!(TokenPolicy::Strict.permits(ShellFamily::Posix, &["docker", "run", "alpine:3.20"]));
        assert!(!TokenPolicy::Strict.permits(ShellFamily::Posix, &["docker", "run", "a b"]));
    }
}

/// Words a shell reads as syntax or as something other than a plain word, for bash, zsh, fish,
/// PowerShell and cmd.exe.
const HOSTILE_WORDS: &[&str] = &[
    "a b",
    "a\tb",
    "a\nb",
    "a\rb",
    "a\0b",
    "a'b",
    "a\"b",
    "a`b",
    "a$b",
    "$HOME",
    "${HOME}",
    "$(id)",
    "%PATH%",
    "!x",
    "a;b",
    "a&b",
    "a&&b",
    "a|b",
    "a||b",
    "a<b",
    "a>b",
    "a>>b",
    "a(b)",
    "a{b,c}",
    "a[b]",
    "a*",
    "a?",
    "~",
    "~root",
    "a#b",
    "a^b",
    "a\\b",
    "a\\'b",
    "=ls",
    "-",
    "--",
    "---x",
    "-$(id)",
    "-f x",
    "\u{2018}a",
    "a\u{2019}",
    "\u{201a}a",
    "\u{201b}a",
    "\u{201c}a",
    "\u{201d}a",
    "\u{201e}a",
    "a\u{a0}b",
    "a\u{2028}b",
    "\u{ff1b}",
    "a\u{ff07}b",
    "a\u{1b}[31m",
    "é",
];

/// Words a user really types, which must keep working.
const PLAIN_WORDS: &[&str] = &[
    "alpine",
    "alpine:3.20",
    "my-image",
    "feature/x.y",
    "release_1.2+build",
    "user@host:22",
    "node@20.1.0",
    "1,2,3",
    "conv=ascii,",
    "-f",
    "--file",
    "--file=Dockerfile",
    "-n",
    "/usr/local/bin",
    "../relative/path",
    "",
];

#[test]
fn the_strict_gate_refuses_every_hostile_word_in_every_shell_family() {
    for word in HOSTILE_WORDS {
        assert!(!is_inert_word(word), "{word:?} must not be inert");
        for policy in [TokenPolicy::Strict, TokenPolicy::Escaped] {
            assert!(
                !policy.permits(ShellFamily::PowerShell, &["git", word]),
                "{policy:?} must refuse {word:?} on PowerShell and cmd.exe"
            );
        }
        assert!(
            !TokenPolicy::Strict.permits(ShellFamily::Posix, &["git", "ok", word]),
            "Strict must refuse {word:?} on bash, zsh and fish"
        );
    }
    for word in PLAIN_WORDS {
        assert!(is_inert_word(word), "{word:?} must be inert");
        for policy in [
            TokenPolicy::Strict,
            TokenPolicy::Escaped,
            TokenPolicy::Inert,
        ] {
            for family in [ShellFamily::Posix, ShellFamily::PowerShell] {
                assert!(
                    policy.permits(family, &["docker", word]),
                    "{policy:?} must allow {word:?} in {family:?}"
                );
            }
        }
    }
}

#[test]
fn the_escaped_gate_allows_what_posix_quoting_handles_and_nothing_else() {
    // Quotes, spaces and shell syntax are fine inside `'...'` with `'` escaped as `'\''`.
    for word in [
        "my dir/Dockerfile",
        "a'b",
        "a\"b",
        "$(id)",
        "a;b",
        "é",
        "a\nb",
    ] {
        if word.contains('\n') {
            assert!(
                !TokenPolicy::Escaped.permits(ShellFamily::Posix, &[word]),
                "{word:?}"
            );
        } else {
            assert!(
                TokenPolicy::Escaped.permits(ShellFamily::Posix, &[word]),
                "{word:?}"
            );
        }
    }
    // A backslash is refused: fish reads `\'` inside single quotes as an escaped quote, so the
    // POSIX quoting of `\'; cmd` closes the string early in fish. See `fish_breaks_out_...`.
    for word in ["a\\b", "\\'; true #", "a\\", "\0", "\u{1b}"] {
        assert!(
            !TokenPolicy::Escaped.permits(ShellFamily::Posix, &[word]),
            "{word:?}"
        );
        assert!(!is_quotable_word(word), "{word:?}");
    }
    assert!(TokenPolicy::Inert.permits(ShellFamily::PowerShell, &["a b", "$(id)"]));
}

/// What fish reads outside of any quote and outside of any escape in `command`. Inside single
/// quotes fish knows two escapes, `\\` and `\'`; outside quotes a backslash escapes the next
/// character.
fn fish_unquoted_text(command: &str) -> String {
    let chars: Vec<char> = command.chars().collect();
    let (mut index, mut in_quote, mut unquoted) = (0, false, String::new());
    while index < chars.len() {
        match (in_quote, chars[index]) {
            (false, '\'') => in_quote = true,
            (false, '\\') => index += 1,
            (false, c) => unquoted.push(c),
            (true, '\\') if matches!(chars.get(index + 1), Some('\\' | '\'')) => index += 1,
            (true, '\'') => in_quote = false,
            (true, _) => {}
        }
        index += 1;
    }
    unquoted
}

/// The POSIX quoting the dependency uses (`'` becomes `'\''`), applied to a word with a
/// backslash, is a command injection in fish. The gate must therefore never let a backslash
/// through to a generator that quotes this way.
#[test]
fn fish_breaks_out_of_posix_single_quoting_when_the_word_has_a_backslash() {
    let posix_quote = |word: &str| format!("'{}'", word.replace('\'', r"'\''"));
    let breakout = r"\'; touch pwned #";
    let quoted = posix_quote(breakout);
    assert_eq!(quoted, r#"'\'\''; touch pwned #'"#);
    assert!(
        fish_unquoted_text(&quoted).contains("; touch pwned"),
        "fish ends the quote early: {quoted}"
    );
    assert!(!TokenPolicy::Escaped.permits(ShellFamily::Posix, &[breakout]));
    // Without a backslash the same quoting holds in fish.
    let quoted = posix_quote("a'; touch pwned #");
    assert_eq!(fish_unquoted_text(&quoted), "");
    assert!(TokenPolicy::Escaped.permits(ShellFamily::Posix, &["a'; touch pwned #"]));
}

/// PowerShell quotes a single-quoted string by doubling `'`, and also treats `‘ ’ ‚ ‛` as
/// quotes. The dependency's `'\''` is not that, so no generator that takes tokens may rely on its
/// own quoting there: `Escaped` is `Strict` on PowerShell, which refuses every one of them.
#[test]
fn powershell_never_sees_a_quote_character_of_any_kind() {
    for quote in [
        '\'', '"', '`', '\u{2018}', '\u{2019}', '\u{201a}', '\u{201b}', '\u{201c}',
    ] {
        let word = format!("a{quote}; calc #");
        assert!(!TokenPolicy::Escaped.permits(ShellFamily::PowerShell, &[word.as_str()]));
        assert!(!TokenPolicy::Strict.permits(ShellFamily::PowerShell, &[word.as_str()]));
    }
}

#[test]
fn environment_assignments_are_filtered_for_every_generator() {
    let env = |words: &[&str]| words.iter().map(|w| w.to_string()).collect::<Vec<_>>();
    assert_eq!(
        sanitize_env_vars(&env(&[
            "KUBECONFIG=/home/me/.kube/config",
            "A_1=x,y",
            "KUBECONFIG=a;touch x",
            "KUBECONFIG=$(id)",
            "KUBECONFIG=a b",
            "KUBECONFIG='a'",
            "1BAD=x",
            "NOEQUALS",
            "=x",
            "K=a`id`",
            "K==x",
        ])),
        env(&["KUBECONFIG=/home/me/.kube/config", "A_1=x,y"])
    );
}

#[test]
fn the_token_policy_table_is_sorted_allowed_and_holds_up() {
    let table = listed_token_policies();
    assert!(
        table
            .windows(2)
            .all(|pair| (pair[0].0, pair[0].1) < (pair[1].0, pair[1].1)),
        "the token policy table must be sorted by (spec, generator) without duplicates"
    );
    let bundled: HashMap<(String, String), warp_command_signatures::Generator> =
        bundled_generators()
            .into_iter()
            .map(|(spec, name, generator)| ((spec, name), generator))
            .collect();
    for (spec, name, policy) in table {
        assert!(
            ALLOWED_GENERATORS.contains(&(*spec, *name)),
            "{spec}/{name} is in the token policy table but not on the allow-list"
        );
        let generator = &bundled[&(spec.to_string(), name.to_string())];
        let GeneratorProcess::CommandFromTokens(f) = generator.process else {
            panic!("{spec}/{name} takes no tokens, so it needs no token policy");
        };
        if *policy == TokenPolicy::Inert {
            let neutral = f(&[spec, "x"], true, &[]).build(Shell::Posix).to_string();
            for word in HOSTILE_WORDS.iter().chain(PLAIN_WORDS) {
                for tokens in [
                    vec![*spec, word],
                    vec![*spec, "x", word],
                    vec![*spec, word, "x"],
                ] {
                    for trailing in [false, true] {
                        let command = f(&tokens, trailing, &[]).build(Shell::Posix).to_string();
                        assert!(
                            !command.contains(word) || word.is_empty() || neutral.contains(word),
                            "{spec}/{name} is Inert but put {word:?} into {command:?}"
                        );
                    }
                }
            }
        }
    }
    // Every allowed generator that takes tokens either is in the table or is Strict.
    for (spec, name, generator) in bundled_generators() {
        if matches!(generator.process, GeneratorProcess::CommandFromTokens(_))
            && ALLOWED_GENERATORS.contains(&(spec.as_str(), name.as_str()))
        {
            let policy = token_policy(&spec, &name);
            let listed = table.iter().any(|(s, g, _)| *s == spec && *g == name);
            assert_eq!(listed, policy != TokenPolicy::Strict, "{spec}/{name}");
        }
    }
}

/// Plain input keeps completing: the engine passes inert words and, for a generator that
/// quotes, a path with a space. Windows runs none of these generators except git's, which
/// `git_completions_run_on_windows_only_with_the_offline_environment` covers.
#[cfg(not(windows))]
#[test]
fn valid_inputs_still_reach_their_generators() {
    let guarded = guarded();
    let ran = |input: &str, marker: &str| {
        let commands = guarded.commands_for(input);
        assert!(
            commands.iter().any(|command| command.contains(marker)),
            "{input:?} should run a generator containing {marker:?}, got {commands:?}"
        );
    };
    ran("kubectl --context ", "get-contexts");
    ran(
        "kubectl --context prod.example/x get pods --cluster ",
        "get-clusters",
    );
    ran("oc --context ", "get-contexts");
    ran(
        "KUBECONFIG=/home/me/.kube/config kubectl --context ",
        "--kubeconfig=/home/me/.kube/config",
    );
    ran("asdf uninstall nodejs ", "asdf list nodejs");
    ran("trivy image --severity LOW,", "LOW,UNKNOWN");
    ran("scc --format ", "tabular");
    ran("eslint --env node,", "node,browser");
    ran("man -S 1:", "1:2");
    ran(
        "ros2 run demo_nodes_cpp ",
        "ros2 pkg executables demo_nodes_cpp",
    );
    ran("sdk use java ", "candidates/java/");
    ran("git checkout feature/x.y", "branch");
    ran(
        r#"docker build -f "it's; touch pwned" --target "#,
        r#"'it'\''s; touch pwned'"#,
    );
    ran(
        "docker build -f 'my dir/Dockerfile' --target ",
        "'my dir/Dockerfile'",
    );
}

#[test]
fn hostile_input_reaches_no_generator_through_the_engine() {
    let guarded = guarded();
    let unrestricted = unrestricted();
    let mut reached_without_the_gate = 0;
    for (input, marker) in [
        (r#"asdf uninstall "nodejs; touch pwned" "#, "touch"),
        (r#"asdf global 'nodejs$IFS' "#, "IFS"),
        (r#"trivy image --severity "LOW,x y,""#, "x y"),
        (r#"man -S "1;touch pwned:""#, "touch"),
        (r#"ros2 run "demo;touch pwned" "#, "touch"),
        (r#"sdk use "java;touch pwned" "#, "touch"),
        (r#"KUBECONFIG="a;touch pwned" kubectl --context "#, "touch"),
        (r#"KUBECONFIG=a$IFS kubectl --context "#, "IFS"),
        (r#"docker build -f 'a\;touch pwned' --target "#, "touch"),
    ] {
        let reachable = unrestricted.commands_for(input);
        if reachable.iter().any(|command| command.contains(marker)) {
            reached_without_the_gate += 1;
        }
        let executed = guarded.commands_for(input);
        assert!(
            !executed.iter().any(|command| command.contains(marker)),
            "{input:?} ran {executed:?}"
        );
    }
    assert!(
        reached_without_the_gate >= 6,
        "the inputs should reach their generators when the gate is off ({reached_without_the_gate})"
    );
}

/// Typed lines that reach the generators of the RV-01 report and the alias path, with a word
/// that would print the marker if it were executed. Each must print it without the gate (the
/// reproduction) and must run nothing with it, in bash, zsh, fish and PowerShell (written for
/// POSIX shells here; `ShellKind::typed_line` adapts the print command).
#[cfg(unix)]
const ENGINE_INJECTION_INPUTS: &[&str] = &[
    r#"asdf uninstall "nodejs; printf ASTRA_MARK; #" "#,
    r#"asdf global "nodejs' ; printf ASTRA_MARK; #" "#,
    r#"trivy image --severity "LOW,x;printf ASTRA_MARK;," "#,
    r#"ros2 run "demo;printf ASTRA_MARK;#" "#,
    r#"sdk use "java;printf ASTRA_MARK;#" "#,
    r#"eslint --env "node,x;printf ASTRA_MARK;," "#,
    r#"KUBECONFIG="a;printf ASTRA_MARK;#" kubectl --context "#,
    r#"KUBECONFIG="a;printf ASTRA_MARK;#" oc --cluster "#,
    r#"git "co;printf ASTRA_MARK;#" "#,
    r#"docker build -f "it's; printf ASTRA_MARK; #" --target "#,
    // The word fish reads differently inside single quotes: `\'` is an escaped quote there.
    r#"docker build -f "x\'; printf ASTRA_MARK; #" --target "#,
    r#"docker build -f "x\\'; printf ASTRA_MARK; #" --target "#,
    r#"kubectl --context "x\'; printf ASTRA_MARK; #" get-clusters "#,
    // `$(...)` and backticks are command substitutions in every shell; `(...)` is one in fish.
    r#"docker build -f "x$(printf ASTRA_MARK)" --target "#,
    r#"docker build -f "x(printf ASTRA_MARK)" --target "#,
    r#"asdf uninstall "nodejs$(printf ASTRA_MARK)" "#,
];

#[cfg(unix)]
#[test]
fn typed_words_are_never_executed_by_a_real_shell_through_the_engine() {
    let mut reproduced_in: std::collections::BTreeMap<&str, BTreeSet<&str>> = Default::default();
    for shell in installed_shells() {
        let control = unrestricted().in_shell(&shell);
        let guarded = guarded().in_shell(&shell);
        let guarded_isolated = guarded_isolated().in_shell(&shell);
        for input in ENGINE_INJECTION_INPUTS {
            let typed = shell.kind.typed_line(input);
            control.stdout.lock().unwrap().clear();
            control.commands_for(&typed);
            if control.stdout.lock().unwrap().contains("ASTRA_MARK") {
                reproduced_in.entry(shell.label).or_default().insert(*input);
            }
            guarded.stdout.lock().unwrap().clear();
            let commands = guarded.commands_for(&typed);
            let output = guarded.stdout.lock().unwrap().clone();
            assert!(
                !output.contains("ASTRA_MARK"),
                "{typed:?} executed typed words in {shell:?}: {commands:?}"
            );
            guarded_isolated.stdout.lock().unwrap().clear();
            let commands = guarded_isolated.commands_for(&typed);
            let output = guarded_isolated.stdout.lock().unwrap().clone();
            assert!(
                !output.contains("ASTRA_MARK"),
                "{typed:?} executed typed words in an isolated context in {shell:?}: {commands:?}"
            );
        }
    }
    eprintln!("inputs that print the marker without the gate, by shell: {reproduced_in:#?}");
    // The gate is only shown to matter by the inputs that do execute without it, and only
    // for the shells that really executed them: a shell that never started would pass anyway.
    for (label, kind_minimum) in [("bash", 5), ("zsh", 5), ("fish", 3), ("pwsh", 5)] {
        if installed_shells().iter().any(|shell| shell.label == label) {
            let reproduced = reproduced_in.get(label).map_or(0, BTreeSet::len);
            assert!(
                reproduced >= kind_minimum,
                "too few engine inputs reproduce the injection in {label} without the gate: \
                 {reproduced_in:?}"
            );
        }
    }
    // The fish-only breakout, through the engine: with the gate off, the POSIX quoting of a word
    // with a backslash lets real fish run the rest of the line, and no other shell.
    if let Some(fish_inputs) = reproduced_in.get("fish") {
        let backslash_input = ENGINE_INJECTION_INPUTS[10];
        assert!(backslash_input.contains(r"x\'"), "{backslash_input}");
        assert!(
            fish_inputs.contains(backslash_input),
            "fish should execute {backslash_input:?} without the gate: {fish_inputs:?}"
        );
        for label in ["bash", "zsh", "sh"] {
            assert!(
                !reproduced_in
                    .get(label)
                    .is_some_and(|inputs| inputs.contains(backslash_input)),
                "{label} executed the fish-only input {backslash_input:?}"
            );
        }
    }
}
