//! Which completion generators may run a command.
//!
//! A `warp-command-signatures` spec can name a *generator*: a shell command the completion
//! engine runs on every completion request to list things such as git branches or npm scripts.
//! Completion requests fire while the user is still typing (autosuggestions) and on Tab, so a
//! generator runs before the user submits anything. A generator must therefore never
//!
//! * execute shell syntax derived from the user's tokens,
//! * touch a network, or
//! * execute code the project controls.
//!
//! The bundled generators do not all meet that. Some run `curl` against public registries with
//! the text the user is typing, some call cloud CLIs, `gh`, `kubectl` or `ssh`, some command
//! lines interpolate the typed word unquoted, and some tools reach a network or run project
//! files depending on the environment (a rustup proxy installing a toolchain, a remote
//! `DOCKER_HOST`, `core.fsmonitor` in a repository's config).
//!
//! The policy is default-deny and works by identity, never by inspecting the command line: a
//! generator runs only if its `(spec, generator name)` pair is in `allowed.rs`. The check is in
//! `CommandRegistry::allows_generator`, called before the shell command is built, in
//! `completer::engine::argument::legacy`. Alias generators, which the completion engine runs to
//! expand an alias the user typed, are the second place a command is executed
//! (`CommandRegistry::signature_with_alias_expansion`); they follow the same rule through
//! `CommandRegistry::allows_alias_generator` and `ALLOWED_ALIAS_GENERATORS`.
//!
//! Every retained generator and alias command requires `Containment::NetworkIsolated`, before
//! any version probe. Only the app's local executor supplies that context and applies the
//! audited offline environment. SSH control-socket and in-band executors do not qualify.
//!
//! Git reads and aliases additionally need the session's Git to be at least 2.31, because older
//! Git ignores the `GIT_CONFIG_COUNT` overrides. The offline environment also supplies an empty
//! `GIT_ALLOW_PROTOCOL`: no local, remote or custom transport may run during completion.
//!
//! `AUDIT.md` records every formerly accepted generator's hostile real-tool evidence or deny
//! decision. Missing required tools exit 86 and fail nextest. `generator_policy_tests.rs` checks
//! classification drift, containment, version probing and typed-token injection with real shells.
//! The two accepted lists retain their evidence categories (environment-reviewed and requiring
//! both environment and OS isolation); neither is permission to run in an unproved context.

mod allowed;
#[cfg(test)]
mod denied;
mod token_gate;

use allowed::{
    ALLOWED_ALIAS_GENERATORS, ALLOWED_GENERATORS, ALLOWED_WHEN_ISOLATED, GIT_ALIAS_GENERATORS,
    GIT_PIPELINE_GENERATORS, LOCAL_GIT_GENERATORS,
};
pub(super) use token_gate::{TokenPolicy, sanitize_env_vars, token_policy};

use crate::completer::Containment;

/// Whether the generator named `generator` of the spec registered as `spec` (lowercase) may run
/// a command. `containment` says what the context guarantees about the command (see
/// [`ALLOWED_WHEN_ISOLATED`]).
///
/// Both accepted lists require a network-isolated local context; their evidence categories
/// differ, not their runtime containment requirement.
pub(super) fn is_generator_allowed(spec: &str, generator: &str, containment: Containment) -> bool {
    let listed = |list: &[(&str, &str)]| {
        list.binary_search_by(|(listed_spec, listed_generator)| {
            (*listed_spec, *listed_generator).cmp(&(spec, generator))
        })
        .is_ok()
    };
    containment == Containment::NetworkIsolated
        && (listed(ALLOWED_GENERATORS) || listed(ALLOWED_WHEN_ISOLATED))
}

/// Whether the generator named `generator` of the spec registered as `spec` (lowercase) runs
/// `git`. These run only when the session's git is at least `MINIMUM_GIT_VERSION`: the offline
/// environment table protects against a repository's `core.fsmonitor`, `core.hooksPath` and
/// `log.showSignature` through `GIT_CONFIG_COUNT` overrides, which older git ignores.
pub(super) fn generator_runs_git(spec: &str, generator: &str) -> bool {
    let listed = |list: &[(&str, &str)]| {
        list.binary_search_by(|(listed_spec, listed_generator)| {
            (*listed_spec, *listed_generator).cmp(&(spec, generator))
        })
        .is_ok()
    };
    listed(LOCAL_GIT_GENERATORS) || listed(GIT_PIPELINE_GENERATORS)
}

/// Whether the alias generator named `alias` of the spec registered as `spec` (lowercase) runs
/// `git`; see [`generator_runs_git`].
pub(super) fn alias_generator_runs_git(spec: &str, alias: &str) -> bool {
    GIT_ALIAS_GENERATORS.contains(&(spec, alias))
}

/// The local git generators (one `git` read of the local repository each).
pub(super) fn local_git_generators() -> &'static [(&'static str, &'static str)] {
    LOCAL_GIT_GENERATORS
}

/// The generators that run only in an isolated context.
pub(super) fn generators_allowed_when_isolated() -> &'static [(&'static str, &'static str)] {
    ALLOWED_WHEN_ISOLATED
}

/// Whether the alias generator named `alias` of the spec registered as `spec` (lowercase) may
/// run a command.
pub(super) fn is_alias_generator_allowed(
    spec: &str,
    alias: &str,
    containment: Containment,
) -> bool {
    containment == Containment::NetworkIsolated
        && ALLOWED_ALIAS_GENERATORS
            .binary_search_by(|(allowed_spec, allowed_alias)| {
                (*allowed_spec, *allowed_alias).cmp(&(spec, alias))
            })
            .is_ok()
}

#[cfg(test)]
#[path = "generator_policy_tests.rs"]
mod tests;
