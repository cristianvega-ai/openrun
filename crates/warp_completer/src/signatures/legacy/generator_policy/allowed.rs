//! Generators reviewed to run only a command that reads the local machine (files, the
//! repository, local daemons) and that takes no user tokens, or takes them only safely.
//!
//! Sorted by `(spec, generator)`; [`super::is_generator_allowed`] binary-searches it. The spec is
//! the name a `warp-command-signatures` spec registers its generators under (lowercase).
//! Everything not listed here is denied, see the module documentation of [`super`] for the
//! policy and for how to classify a new entry.

pub(super) const ALLOWED_GENERATORS: &[(&str, &str)] = &[
    ("checkov", "git_branch"),
    ("codex", "commits"),
    ("codex", "local_branches"),
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
    ("lerna", "git_branch"),
    ("lerna", "git_remote"),
    ("pnpm", "search_branches"),
    ("pre-commit", "git_branch"),
    ("pre-commit", "git_branch_no"),
    ("pre-commit", "git_remote"),
    ("pre-commit", "git_rev_list"),
    ("turbo", "git_branch"),
    ("uv", "installed_tools"),
    ("vsce", "git_branch"),
];

/// Generators that run only when the context reports that the operating system keeps the
/// command from reaching a network (`GeneratorContext::network_isolated`: local
/// sessions) and the offline environment table is applied. Each looks local but was shown to
/// reach a network, or to run repository code, in the environment alone:
///
/// * `rustup/rustup_docs`: the rustup proxies install the toolchain a project's
///   `rust-toolchain.toml` names (two GETs per command against a loopback canary). `rustup docs
///   --path` only prints a path, also for a `path =` toolchain (measured: it starts nothing).
///   The `cargo/*` pairs used to be here; they are denied because a `path =` toolchain makes
///   the proxy start the project's own `cargo`/`rustc` (`denied.rs`, class `project-code`).
/// * `docker/*` (ten listing commands): the docker CLI talks to whatever `DOCKER_HOST` or the
///   current docker context names, which may be a remote daemon over `tcp://` or `ssh://`.
/// * `git/tracked_files`, `git/treeish`, `hub/treeish`: `git ls-files` and `git diff --cached`
///   run the `core.fsmonitor` program of a repository's config, and `git diff --cached` reads the
///   `HEAD` tree, which a partial clone may lazy-fetch from a promisor remote whose
///   `remote.<name>.uploadpack` is a program the repository names. The offline table switches
///   both off for every git it accepts (`GIT_CONFIG_COUNT`, `GIT_ALLOW_PROTOCOL`).
///
/// `npm/workspace_generator` used to be here (`npm prefix` ends with an update check); it is
/// denied because npm 6 `require()`s the `onload-script` of a project's `.npmrc`.
///
/// The real tools were run against a canary with the sandbox and the environment table each on
/// its own and both together (`network_sandbox_tests.rs`, `offline_environment_tests.rs`,
/// `restored_generators_tests.rs` in the app crate), and each pair here is checked by that last
/// test against the command the bundled spec runs. Sorted, and disjoint from [`ALLOWED_GENERATORS`].
pub(super) const ALLOWED_WHEN_ISOLATED: &[(&str, &str)] = &[
    ("docker", "all_docker_containers"),
    ("docker", "all_local_images"),
    ("docker", "docker_images"),
    ("docker", "docker_volumes"),
    ("docker", "list_docker_networks"),
    ("docker", "list_docker_plugins"),
    ("docker", "list_docker_volumes"),
    ("docker", "paused_docker_containers"),
    ("docker", "remove_images"),
    ("docker", "running_docker_containers"),
    ("git", "tracked_files"),
    ("git", "treeish"),
    ("hub", "treeish"),
    ("rustup", "rustup_docs"),
];

/// Allowed generators whose command runs `git` but that are not on [`LOCAL_GIT_GENERATORS`]
/// because they are POSIX pipelines. Together with that list this is every allowed generator
/// that runs git; `generator_policy_tests.rs` checks it against the commands of the bundled
/// specs. Sorted.
pub(super) const GIT_PIPELINE_GENERATORS: &[(&str, &str)] = &[];

/// The alias generators that run `git`: all of [`ALLOWED_ALIAS_GENERATORS`].
pub(super) const GIT_ALIAS_GENERATORS: &[(&str, &str)] = ALLOWED_ALIAS_GENERATORS;

/// Alias generators that may run, always behind the strict token gate: `git config --get
/// alias.{word}` is only built from inert words. `npm` and `yarn` run `npm prefix`, which is
/// denied.
pub(super) const ALLOWED_ALIAS_GENERATORS: &[(&str, &str)] = &[("git", "alias")];

/// The local git generators. Each command was run through the real executor against a repository
/// that tries to run code and a partial clone whose promisor remote is a loopback listener
/// (`git_completion_tests.rs` in the app crate).
///
/// Every command is one `git` invocation that reads the local repository: `branch`, `tag`,
/// `for-each-ref`, `rev-list`, `log`, `stash list`, `worktree list`, `remote -v` and
/// `config --get-regexp` read refs, objects and configuration (`codex/commits` and
/// `codex/local_branches` are the very same `git log --oneline` and `git branch` commands as
/// `gt`'s and `git`'s: the `codex` spec reuses their generator functions); `ls-files` and
/// `diff --cached --name-only` read the index and, for the second, the `HEAD` tree. None of them
/// is a status-like command: the `clean` filter of `git status`, `git diff` and
/// `git ls-files --modified` (the four generators in `denied.rs` with class `project-code`)
/// stays denied. `git/local_or_remote_branch`, `git/push_refspec_branches` and
/// `git/push_refspec_tags` take tokens but their command does not depend on them
/// ([`TokenPolicy::Inert`](super::token_gate::TokenPolicy::Inert)). `git-flow/type_branches`
/// is a POSIX pipeline (`p=$(...)`, `sed`, `awk`) that takes a word, so it is not on this list.
///
/// A subset of [`ALLOWED_GENERATORS`] plus the three isolated-tier git pairs. Sorted.
pub(super) const LOCAL_GIT_GENERATORS: &[(&str, &str)] = &[
    ("checkov", "git_branch"),
    ("codex", "commits"),
    ("codex", "local_branches"),
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
