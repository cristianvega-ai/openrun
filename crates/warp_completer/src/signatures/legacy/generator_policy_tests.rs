use std::collections::{BTreeSet, HashMap};
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use regex::Regex;
use warp_command_signatures::{GeneratorProcess, Shell};
use warp_util::path::ShellFamily;

use super::allowed::{
    ALLOWED_ALIAS_GENERATORS, ALLOWED_GENERATORS, ALLOWED_ON_WINDOWS, ALLOWED_WHEN_ISOLATED,
};
use super::denied::{DENIED_ALIAS_GENERATORS, DENIED_GENERATORS};
use super::token_gate::{is_inert_word, is_quotable_word, listed_token_policies};
use super::{
    TokenPolicy, is_alias_generator_allowed, is_generator_allowed_on, sanitize_env_vars,
    token_policy,
};
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
    /// When set, every command is run in this shell (program and arguments before `-c`) with an
    /// empty `PATH` (shell builtins only)
    /// and its standard output and error are collected in `stdout`.
    #[cfg(unix)]
    run_in_shell: Option<(&'static str, &'static [&'static str])>,
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
            run_in_shell: None,
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
        if let Some((shell, shell_args)) = self.run_in_shell {
            let empty =
                std::env::temp_dir().join(format!("openrun-empty-path-{}", std::process::id()));
            std::fs::create_dir_all(&empty)?;
            let output = command::blocking::Command::new(shell)
                .args(shell_args.iter())
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

/// The POSIX shells installed here, as `(program, arguments before -c)`.
#[cfg(unix)]
fn installed_shells() -> Vec<(&'static str, &'static [&'static str])> {
    let shells: Vec<_> = [
        ("/bin/bash", &["--norc"][..]),
        ("/bin/zsh", &["-f"][..]),
        ("/usr/bin/zsh", &["-f"][..]),
        ("/bin/sh", &[][..]),
    ]
    .into_iter()
    .filter(|(path, _)| std::path::Path::new(path).exists())
    .collect();
    assert!(!shells.is_empty());
    shells
}

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
        let mut control = unrestricted();
        control.run_in_shell = Some(shell);
        for input in inputs {
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
            let mut guarded = if isolated {
                guarded_isolated()
            } else {
                guarded()
            };
            guarded.run_in_shell = Some(shell);
            for input in inputs {
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
    use warp_util::path::ShellFamily;

    use super::{
        ALLOWED_GENERATORS, ALLOWED_WHEN_ISOLATED, GATED_INJECTABLE_GENERATORS,
        STILL_DENIED_INJECTABLE_GENERATORS, TokenPolicy, bundled_generators, sanitize_env_vars,
        token_policy,
    };

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
        gate: Option<TokenPolicy>,
    ) -> BTreeSet<String> {
        let marker_dir = marker_dir.to_str().unwrap();
        let mut commands = BTreeSet::new();
        // With `gate`, the tokens and environment words go through the engine's token gate
        // first, as they do in production; without it the closure sees every hostile word.
        let mut build = |tokens: &[&str], trailing_whitespace: bool, env: &[String]| {
            let env = match gate {
                Some(policy) => {
                    if !policy.permits(ShellFamily::Posix, tokens) {
                        return;
                    }
                    sanitize_env_vars(env)
                }
                None => env.to_vec(),
            };
            commands.insert(
                command_from_tokens(tokens, trailing_whitespace, &env)
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
                .chain(ALLOWED_WHEN_ISOLATED)
                .map(|(s, g)| (s.to_string(), g.to_string())),
        );
        assert!(
            !generators.is_empty(),
            "the allow-list contains token-taking generators"
        );
        let mut failures = Vec::new();
        for (spec, name, f) in generators {
            let dir = marker_dir(&format!("{spec}-{name}"));
            let commands = hostile_commands(&spec, f, &dir, Some(token_policy(&spec, &name)));
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

    /// The corpus is only worth something if it catches a real injection: the generators that
    /// are known to interpolate the typed word raw must be reported when the closure sees every
    /// hostile word, and must run nothing behind the gate.
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
        for (spec, name) in known {
            let generators =
                generators_taking_tokens(std::iter::once((spec.to_string(), name.to_string())));
            let (spec, name, f) = generators.into_iter().next().unwrap();
            let dir = marker_dir(&format!("control-{spec}-{name}"));
            let raw = hostile_commands(&spec, f, &dir, None);
            if executed_injections(&raw, &dir, true).is_empty() {
                not_raw.push(format!("{spec}/{name}"));
            }
            // Fail closed: listing one of the raw generators as `Escaped` would be a false claim,
            // and the corpus shows it.
            if token_policy(&spec, &name) == TokenPolicy::Strict {
                let mislabelled = hostile_commands(&spec, f, &dir, Some(TokenPolicy::Escaped));
                assert!(
                    !executed_injections(&mislabelled, &dir, true).is_empty(),
                    "{spec}/{name} is raw but the corpus does not catch it under Escaped"
                );
            }
            let gated = hostile_commands(&spec, f, &dir, Some(token_policy(&spec, &name)));
            let injected = executed_injections(&gated, &dir, false);
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
/// quotes, a path with a space.
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
/// reproduction) and must run nothing with it, in bash and zsh.
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
];

#[cfg(unix)]
#[test]
fn typed_words_are_never_executed_by_a_real_shell_through_the_engine() {
    let mut reproduced = BTreeSet::new();
    for shell in installed_shells() {
        let mut control = unrestricted();
        control.run_in_shell = Some(shell);
        let mut guarded = guarded();
        guarded.run_in_shell = Some(shell);
        let mut guarded_isolated = guarded_isolated();
        guarded_isolated.run_in_shell = Some(shell);
        for input in ENGINE_INJECTION_INPUTS {
            control.stdout.lock().unwrap().clear();
            control.commands_for(input);
            if control.stdout.lock().unwrap().contains("ASTRA_MARK") {
                reproduced.insert(*input);
            }
            guarded.stdout.lock().unwrap().clear();
            let commands = guarded.commands_for(input);
            let output = guarded.stdout.lock().unwrap().clone();
            assert!(
                !output.contains("ASTRA_MARK"),
                "{input:?} executed typed words in {shell:?}: {commands:?}"
            );
            guarded_isolated.stdout.lock().unwrap().clear();
            let commands = guarded_isolated.commands_for(input);
            let output = guarded_isolated.stdout.lock().unwrap().clone();
            assert!(
                !output.contains("ASTRA_MARK"),
                "{input:?} executed typed words in an isolated context in {shell:?}: {commands:?}"
            );
        }
    }
    // The gate is only shown to matter by the inputs that do execute without it.
    assert!(
        reproduced.len() >= 5,
        "too few engine inputs reproduce the injection without the gate: {reproduced:?}"
    );
}
