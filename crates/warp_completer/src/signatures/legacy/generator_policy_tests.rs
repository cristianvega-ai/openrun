use std::collections::{BTreeSet, HashMap};
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use regex::Regex;
use warp_command_signatures::{GeneratorProcess, Shell};

use super::allowed::{
    ALLOWED_ALIAS_GENERATORS, ALLOWED_GENERATORS, ALLOWED_ON_WINDOWS, ALLOWED_WHEN_ISOLATED,
};
use super::denied::{DENIED_ALIAS_GENERATORS, DENIED_GENERATORS};
use super::{is_alias_generator_allowed, is_generator_allowed_on};
use crate::completer::{
    CommandExitStatus, CommandOutput, CompleterOptions, CompletionContext,
    CompletionsFallbackStrategy, GeneratorContext, MatchStrategy, PathCompletionContext,
    suggestions,
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
    /// When set, `curl ...` commands are run through `sh` with a `PATH` that contains only this
    /// directory, so they can only ever reach the stub `curl` placed in it.
    #[cfg(unix)]
    stub_curl_dir: Option<std::path::PathBuf>,
    /// When set, every command is run in `/bin/sh` with an empty `PATH` (shell builtins only)
    /// and its standard output and error are collected in `stdout`.
    #[cfg(unix)]
    run_in_shell: bool,
    #[cfg(unix)]
    stdout: Mutex<String>,
}

impl RecordingContext {
    fn new(registry: Arc<CommandRegistry>) -> Self {
        Self {
            registry,
            commands: Mutex::new(Vec::new()),
            isolated: false,
            #[cfg(unix)]
            stub_curl_dir: None,
            #[cfg(unix)]
            run_in_shell: false,
            #[cfg(unix)]
            stdout: Mutex::new(String::new()),
        }
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
        if self.run_in_shell {
            let empty =
                std::env::temp_dir().join(format!("openrun-empty-path-{}", std::process::id()));
            std::fs::create_dir_all(&empty)?;
            let output = command::blocking::Command::new("/bin/sh")
                .arg("-c")
                .arg(shell_command)
                .env_clear()
                .env("PATH", &empty)
                .current_dir(&empty)
                .stdin(std::process::Stdio::null())
                .output()?;
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
    assert!(registry.allows_generator("git", &name("local_branches"), false));
    assert!(!registry.allows_generator("npm", &name("npm_registry_search"), false));
    assert!(!registry.allows_generator("cargo", &name("crates_io_search"), false));
    // The same generator name is local in one spec and a network call in another.
    assert!(registry.allows_generator("bat", &name("completions"), false));
    assert!(!registry.allows_generator("softwareupdate", &name("completions"), false));
    // Unknown pairs are denied.
    assert!(!registry.allows_generator("git", &name("no_such_generator"), false));
    assert!(!registry.allows_generator("no-such-spec", &name("local_branches"), false));
    assert!(!CommandRegistry::empty().allows_generator("git", &name("no_such_generator"), true));
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

/// The generators of the RV-01 report: they put the user's unsubmitted words into the shell
/// command unquoted (or, for the `kubectl` family, the `KEY=value` words typed before the
/// command). Each is denied; the class says what else is wrong with it.
const INJECTABLE_GENERATORS: &[(&str, &str, &str)] = &[
    ("asdf", "installed_versions", "injectable"),
    ("brew", "gist_logs_actions", "injectable"),
    ("dd", "conv_remaining", "injectable"),
    ("docker", "image_with_tags", "env-network-verified"),
    ("docker-compose", "compose_services", "env-network-likely"),
    ("esbuild", "loader", "injectable"),
    ("eslint", "env_remaining", "injectable"),
    ("file", "param_keys", "injectable"),
    ("kubecolor", "cluster", "injectable"),
    ("kubecolor", "context", "injectable"),
    ("kubecolor", "user", "injectable"),
    ("kubectl", "cluster", "injectable"),
    ("kubectl", "context", "injectable"),
    ("kubectl", "user", "injectable"),
    ("man", "sections_remaining", "injectable"),
    ("oc", "cluster", "injectable"),
    ("oc", "context", "injectable"),
    ("oc", "user", "injectable"),
    ("ros2", "executables", "injectable"),
    ("scc", "format_multi", "injectable"),
    ("sdk", "installed_versions", "injectable"),
    ("trivy", "pkg_types_remaining", "injectable"),
    ("trivy", "scanners_remaining", "injectable"),
    ("trivy", "severity_remaining", "injectable"),
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
    for (spec, name, class) in INJECTABLE_GENERATORS.iter().chain(ENVIRONMENT_GENERATORS) {
        assert!(
            !is_generator_allowed_on(false, false, spec, name),
            "{spec}/{name} must not be allowed"
        );
        assert_eq!(
            DENIED_GENERATORS
                .iter()
                .find(|(s, g, _)| s == spec && g == name)
                .map(|(_, _, class)| class),
            Some(class),
            "{spec}/{name} must be denied as {class}"
        );
    }
    assert_eq!(INJECTABLE_GENERATORS.len(), 24);
    for (spec, alias, _) in DENIED_ALIAS_GENERATORS {
        assert!(!is_alias_generator_allowed(spec, alias), "{spec}/{alias}");
    }
    assert!(ALLOWED_ALIAS_GENERATORS.is_empty());
}

/// The restored tier: generators that look local but reached a network, or ran repository code,
/// in the environment alone (see `ALLOWED_WHEN_ISOLATED`).
#[test]
fn isolated_generators_run_only_when_the_context_is_isolated() {
    use super::generators_allowed_when_isolated;
    assert_eq!(generators_allowed_when_isolated(), ALLOWED_WHEN_ISOLATED);
    assert!(!ALLOWED_WHEN_ISOLATED.is_empty());
    for (spec, name) in ALLOWED_WHEN_ISOLATED {
        assert!(
            !is_generator_allowed_on(false, false, spec, name),
            "{spec}/{name} must not run when the context is not isolated"
        );
        assert!(
            is_generator_allowed_on(false, true, spec, name),
            "{spec}/{name} must run when the context is isolated"
        );
        assert!(
            !is_generator_allowed_on(true, true, spec, name),
            "{spec}/{name} must never run on Windows"
        );
    }
    // Isolation does not unlock anything else.
    for (spec, name, _) in DENIED_GENERATORS {
        assert!(
            !is_generator_allowed_on(false, true, spec, name),
            "{spec}/{name} is denied even in an isolated context"
        );
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

/// The exact input of the RV-01 report, through the production suggestions engine and a real
/// shell: the command that used to be generated for `docker run` printed a marker.
#[cfg(unix)]
#[test]
fn typing_a_quoted_command_in_an_image_name_executes_nothing() {
    const MARKER: &str = "ASTRA_GENERATOR_INJECTION";
    let inputs = [
        r#"docker run "astra'; printf ASTRA_GENERATOR_INJECTION; #":tag"#,
        r#"docker image rm "astra'; printf ASTRA_GENERATOR_INJECTION; #":tag"#,
    ];

    let mut control = unrestricted();
    control.run_in_shell = true;
    for input in inputs {
        control.commands_for(input);
        assert!(
            control.stdout.lock().unwrap().contains(MARKER),
            "without the policy {input:?} should print {MARKER} (the reproduction), ran {:?}",
            control.commands.lock().unwrap()
        );
        control.stdout.lock().unwrap().clear();
    }

    let mut guarded = guarded();
    guarded.run_in_shell = true;
    for input in inputs {
        let commands = guarded.commands_for(input);
        assert!(
            !guarded.stdout.lock().unwrap().contains(MARKER),
            "{input:?} executed injected shell code, commands: {commands:?}"
        );
        assert!(
            !commands.iter().any(|command| command.contains("image ls")),
            "{input:?} ran {commands:?}"
        );
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
            is_generator_allowed_on(true, false, spec, name),
            "{spec}/{name}"
        );
        assert!(
            is_generator_allowed_on(false, false, spec, name),
            "{spec}/{name}"
        );
    }
    assert!(
        ALLOWED_ON_WINDOWS.windows(2).all(|pair| pair[0] < pair[1]),
        "ALLOWED_ON_WINDOWS must be sorted without duplicates"
    );
    // Everything that starts another program is allowed elsewhere and denied on Windows.
    for (spec, name) in [
        ("git", "local_branches"),
        ("git", "tags"),
        ("docker", "from_as"),
        ("kill", "process"),
        ("brew", "services"),
        ("kubectx", "context"),
    ] {
        let allowed_elsewhere = is_generator_allowed_on(false, false, spec, name);
        assert_eq!(
            allowed_elsewhere,
            DENIED_GENERATORS
                .iter()
                .all(|(s, g, _)| !(*s == spec && *g == name)),
            "{spec}/{name}"
        );
        assert!(
            !is_generator_allowed_on(true, false, spec, name),
            "{spec}/{name}"
        );
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
fn alias_generators_never_run_with_the_bundled_registry() {
    let guarded = guarded();
    let unrestricted = unrestricted();
    for (input, marker) in [
        ("git co ", "alias.co"),
        ("npm run build ", "npm prefix"),
        ("yarn run build ", "npm prefix"),
    ] {
        let reachable = unrestricted.commands_for(input);
        assert!(
            reachable.iter().any(|command| command.contains(marker)),
            "{input:?} should reach an alias generator containing {marker:?} without the \
             policy, got {reachable:?}"
        );
        let executed = guarded.commands_for(input);
        assert!(
            !executed.iter().any(|command| command.contains(marker)),
            "{input:?} must not run the {marker:?} alias generator, but ran {executed:?}"
        );
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
        assert!(is_generator_allowed(spec, name, false), "{spec}/{name}");
    }
    for (spec, name, _) in DENIED_GENERATORS {
        assert!(!is_generator_allowed(spec, name, false), "{spec}/{name}");
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
    use std::collections::BTreeSet;
    use std::path::{Path, PathBuf};

    use warp_command_signatures::{GeneratorProcess, Shell};

    use super::{ALLOWED_GENERATORS, DENIED_GENERATORS, bundled_generators};

    /// `{M}` is replaced with the marker directory. The commands use the `true` builtin and a
    /// redirection, so they work with an empty `PATH`. None contains `,` `:` or `=`, which some
    /// generators split on.
    const PAYLOADS: &[(&str, &str)] = &[
        ("sq", "XINJ'; true > {M}/sq #"),
        ("dq", "XINJ\"; true > {M}/dq #"),
        ("cs", "XINJ$(true > {M}/cs)"),
        ("bt", "XINJ`true > {M}/bt`"),
        ("sc", "XINJ; true > {M}/sc #"),
        ("nl", "XINJ\ntrue > {M}/nl\n"),
        ("amp", "XINJ & true > {M}/amp & "),
        ("pipe", "XINJ | true > {M}/pipe #"),
        ("sqcs", "XINJ'$(true > {M}/sqcs)'"),
        ("dqcs", "XINJ\"$(true > {M}/dqcs)\""),
        ("brace", "XINJ{true,true}>{M}/brace"),
        ("glob", "XINJ*; true > {M}/glob #"),
    ];

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
        spec: &str,
        command_from_tokens: fn(
            &[&str],
            bool,
            &[String],
        ) -> warp_command_signatures::CommandBuilder,
        marker_dir: &Path,
    ) -> BTreeSet<String> {
        let marker_dir = marker_dir.to_str().unwrap();
        let mut commands = BTreeSet::new();
        let mut build = |tokens: &[&str], trailing_whitespace: bool, env: &[String]| {
            commands.insert(
                command_from_tokens(tokens, trailing_whitespace, env)
                    .build(Shell::Posix)
                    .to_string(),
            );
        };
        for (_, payload) in PAYLOADS {
            let payload = payload.replace("{M}", marker_dir);
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

    /// The shells available here: `(program, extra args before -c)`.
    fn shells() -> Vec<(&'static str, Vec<&'static str>)> {
        let mut shells = Vec::new();
        for (path, args) in [
            ("/bin/sh", vec![]),
            ("/bin/bash", vec!["--norc"]),
            ("/bin/zsh", vec!["-f"]),
            ("/usr/bin/zsh", vec!["-f"]),
        ] {
            if Path::new(path).exists() {
                shells.push((path, args));
            }
        }
        assert!(!shells.is_empty(), "no POSIX shell to run the corpus in");
        shells
    }

    /// Runs each command in each shell and returns the commands that created a marker file.
    fn executed_injections(
        commands: &BTreeSet<String>,
        marker_dir: &Path,
        stop_at_first: bool,
    ) -> Vec<String> {
        let empty = marker_dir.join("empty-path");
        std::fs::create_dir_all(&empty).unwrap();
        let commands: Vec<&String> = commands
            .iter()
            // A command without the sentinel does not contain any of the typed tokens.
            .filter(|command| command.contains("XINJ"))
            .collect();
        let per_shell_dirs: Vec<(PathBuf, &'static str, Vec<&'static str>)> = shells()
            .into_iter()
            .enumerate()
            .map(|(index, (shell, args))| {
                let dir = marker_dir.join(format!("shell-{index}"));
                std::fs::create_dir_all(&dir).unwrap();
                (dir, shell, args)
            })
            .collect();
        std::thread::scope(|scope| {
            let handles: Vec<_> = per_shell_dirs
                .iter()
                .map(|(dir, shell, args)| {
                    let commands = &commands;
                    let empty = &empty;
                    scope.spawn(move || {
                        let mut injected = Vec::new();
                        for command in commands {
                            // The command writes into `marker_dir`, so rewrite it to this
                            // shell's own directory to know which shell ran it.
                            let command = command
                                .replace(marker_dir.to_str().unwrap(), dir.to_str().unwrap());
                            let output = command::blocking::Command::new(shell)
                                .args(args.iter())
                                .arg("-c")
                                .arg(&command)
                                .env_clear()
                                .env("PATH", empty)
                                .env("HOME", empty)
                                .current_dir(empty)
                                .stdin(std::process::Stdio::null())
                                .output();
                            drop(output);
                            let created: Vec<_> = std::fs::read_dir(dir)
                                .unwrap()
                                .filter_map(Result::ok)
                                .collect();
                            if !created.is_empty() {
                                injected.push(format!("{shell}: {command}"));
                                for entry in created {
                                    let _ = std::fs::remove_file(entry.path());
                                }
                                if stop_at_first {
                                    break;
                                }
                            }
                        }
                        injected
                    })
                })
                .collect();
            handles
                .into_iter()
                .flat_map(|handle| handle.join().unwrap())
                .collect()
        })
    }

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

    #[test]
    fn no_allowed_generator_executes_the_users_tokens() {
        let generators = generators_taking_tokens(
            ALLOWED_GENERATORS
                .iter()
                .map(|(s, g)| (s.to_string(), g.to_string())),
        );
        assert!(
            !generators.is_empty(),
            "the allow-list contains token-taking generators"
        );
        let mut failures = Vec::new();
        for (spec, name, f) in generators {
            let dir = marker_dir(&format!("{spec}-{name}"));
            let commands = hostile_commands(&spec, f, &dir);
            for injected in executed_injections(&commands, &dir, false) {
                failures.push(format!("{spec}/{name}: {injected}"));
            }
            let _ = std::fs::remove_dir_all(&dir);
        }
        assert!(
            failures.is_empty(),
            "allowed generators that ran shell code taken from the typed tokens:\n{}",
            failures.join("\n")
        );
    }

    /// The corpus is only worth something if it catches a real injection: generators known to
    /// interpolate the typed word raw must be reported by the same code.
    #[test]
    fn the_corpus_catches_known_injectable_generators() {
        let known = [
            ("docker", "image_with_tags"),
            ("asdf", "installed_versions"),
            ("man", "sections_remaining"),
            ("kubectl", "context"),
            ("docker-compose", "compose_services"),
            ("sdk", "installed_versions"),
        ];
        for (spec, name) in known {
            assert!(
                DENIED_GENERATORS
                    .iter()
                    .any(|(s, g, _)| *s == spec && *g == name),
                "{spec}/{name} must stay denied while it is injectable"
            );
            let generators =
                generators_taking_tokens(std::iter::once((spec.to_string(), name.to_string())));
            let (spec, name, f) = generators.into_iter().next().unwrap();
            let dir = marker_dir(&format!("control-{spec}-{name}"));
            let commands = hostile_commands(&spec, f, &dir);
            let injected = executed_injections(&commands, &dir, true);
            let _ = std::fs::remove_dir_all(&dir);
            assert!(
                !injected.is_empty(),
                "{spec}/{name} is known to interpolate tokens raw but the corpus did not catch it"
            );
        }
    }
}
