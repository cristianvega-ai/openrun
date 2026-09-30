use std::collections::{BTreeSet, HashMap};
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use regex::Regex;
use warp_command_signatures::{GeneratorName, GeneratorProcess, Shell};

use super::allowed::ALLOWED_GENERATORS;
use super::denied::DENIED_GENERATORS;
use super::is_generator_allowed;
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
    /// When set, `curl ...` commands are run through `sh` with a `PATH` that contains only this
    /// directory, so they can only ever reach the stub `curl` placed in it.
    stub_curl_dir: Option<std::path::PathBuf>,
}

impl RecordingContext {
    fn new(registry: Arc<CommandRegistry>) -> Self {
        Self {
            registry,
            commands: Mutex::new(Vec::new()),
            stub_curl_dir: None,
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
}

fn guarded() -> RecordingContext {
    RecordingContext::new(CommandRegistry::global_instance())
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
const LOCAL_INPUTS: &[(&str, &str)] = &[
    ("git checkout ", "branch"),
    ("git add ", "git"),
    ("git stash apply ", "stash"),
    ("npm run ", "package.json"),
    ("cargo run --bin ", "cargo metadata"),
    ("docker start ", "docker ps"),
    ("brew uninstall ", "brew list"),
    ("kill ", "ps "),
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

#[test]
fn the_policy_decides_by_spec_and_generator_name() {
    let registry = CommandRegistry::global_instance();
    let name = |name: &str| GeneratorName::new(name);
    assert!(registry.allows_generator("git", &name("local_branches")));
    assert!(!registry.allows_generator("npm", &name("npm_registry_search")));
    assert!(!registry.allows_generator("cargo", &name("crates_io_search")));
    // The same generator name is local in one spec and a network call in another.
    assert!(registry.allows_generator("bat", &name("completions")));
    assert!(!registry.allows_generator("softwareupdate", &name("completions")));
    // Unknown pairs are denied.
    assert!(!registry.allows_generator("git", &name("no_such_generator")));
    assert!(!registry.allows_generator("no-such-spec", &name("local_branches")));
    assert!(!CommandRegistry::empty().allows_generator("git", &name("no_such_generator")));
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
    assert!(
        DENIED_GENERATORS.iter().all(|(_, _, class)| [
            "network",
            "cluster",
            "maybe-network",
            "lan"
        ]
        .contains(class))
    );
}

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
    let allowed: BTreeSet<_> = ALLOWED_GENERATORS.iter().copied().collect();
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

#[test]
fn alias_generators_only_read_local_files() {
    let network = Regex::new(r"curl|wget|https?://|ssh|\bgh\b|fetch|ls-remote").unwrap();
    let mut checked = 0;
    for (_, data) in warp_command_signatures::dynamic_command_signature_data() {
        for alias in data.aliases().values() {
            checked += 1;
            for tokens in [vec!["git", "co"], vec!["npm", "run", "build"]] {
                let command = alias.command(&tokens);
                assert!(!network.is_match(&command), "alias command {command:?}");
            }
        }
    }
    assert!(checked > 0, "the bundled specs define alias generators");
}

#[test]
fn is_generator_allowed_matches_the_listed_pairs() {
    for (spec, name) in ALLOWED_GENERATORS {
        assert!(is_generator_allowed(spec, name), "{spec}/{name}");
    }
    for (spec, name, _) in DENIED_GENERATORS {
        assert!(!is_generator_allowed(spec, name), "{spec}/{name}");
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
