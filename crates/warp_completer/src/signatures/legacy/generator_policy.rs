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
//! `CommandRegistry::allows_alias_generator` and `ALLOWED_ALIAS_GENERATORS`, which is empty.
//!
//! `ALLOWED_WHEN_ISOLATED` lists the generators whose tool can reach a network or run repository
//! code in the environment alone but was shown not to when the operating system denies the
//! network to the command and the offline environment table is applied. They run only when the
//! `GeneratorContext` reports `network_isolated()` (macOS and Linux local sessions).
//!
//! On Windows two lists run. `ALLOWED_ON_WINDOWS` is the subset of file reads and PowerShell
//! cmdlets that take no tokens. `ALLOWED_ON_WINDOWS_WITH_ENVIRONMENT` is the local git
//! generators (one `git` read of the local repository each, the `ALLOWED_WHEN_ISOLATED` git trio
//! included); they run only when the `GeneratorContext` reports `offline_environment_applied()`,
//! which the local PowerShell/cmd, Git Bash/MSYS2 and WSL executors do and the in-band executor
//! does not. There is no network sandbox on Windows, so the environment table (no lazy fetch
//! from a promisor remote, no `core.fsmonitor`, no `log.showSignature`, local transports only)
//! is the only layer; any other generator that starts a program stays off.
//!
//! An entry in `allowed.rs` records that someone read the command and the tool's behaviour. It
//! is not a proof: only some tools were run against a canary (see `denied.rs` for which), and
//! the rest of the allowed external CLIs are reviewed from their commands and documentation.
//!
//! # Classifying generators
//!
//! * `allowed.rs` lists the generators whose command reads only the local machine: files, the
//!   repository, local daemons. If in doubt, deny.
//! * `denied.rs` lists the generators that must not run, with a class. It is not consulted at
//!   runtime; it lets the drift test tell a reviewed generator from an unclassified one.
//! * The drift test (`generator_policy_tests.rs`) enumerates
//!   `warp_command_signatures::dynamic_command_signature_data()` and fails, listing the pairs and
//!   their commands, when a generator or alias generator is in neither file. Bumping the
//!   `command-signatures` pin therefore forces a review. Put each new pair in exactly one of the
//!   files, keeping both sorted.
//! * The injection corpus in the same test file runs every allowed token-taking generator with
//!   hostile tokens in real bash, zsh, sh, fish and PowerShell 7 (started as a local session
//!   starts them: `fish --no-config -c`, `pwsh -NoProfile -c`) and fails if anything but the
//!   generator's own command ran. fish and `pwsh` must be installed when `CI` is set; elsewhere
//!   a missing one is skipped with a message.
//! * Stripping the network generators from our future `command-signatures` fork (DEP-05) is the
//!   follow-up; this allow-list stays as the guard in this repository.

mod allowed;
#[cfg(test)]
mod denied;
mod token_gate;

use allowed::{
    ALLOWED_ALIAS_GENERATORS, ALLOWED_GENERATORS, ALLOWED_ON_WINDOWS,
    ALLOWED_ON_WINDOWS_WITH_ENVIRONMENT, ALLOWED_WHEN_ISOLATED,
};
pub(super) use token_gate::{TokenPolicy, sanitize_env_vars, token_policy};

use crate::completer::Containment;

/// Whether the generator named `generator` of the spec registered as `spec` (lowercase) may run
/// a command on this platform. `containment` says what the context guarantees about the command
/// (see [`ALLOWED_WHEN_ISOLATED`] and [`ALLOWED_ON_WINDOWS_WITH_ENVIRONMENT`]).
pub(super) fn is_generator_allowed(spec: &str, generator: &str, containment: Containment) -> bool {
    is_generator_allowed_on(cfg!(windows), containment, spec, generator)
}

/// [`is_generator_allowed`] for an explicit platform, so that the Windows tier is testable on
/// every host.
///
/// * macOS and Linux: [`ALLOWED_GENERATORS`] always, [`ALLOWED_WHEN_ISOLATED`] only in a
///   network-isolated context.
/// * Windows: the [`ALLOWED_ON_WINDOWS`] subset always, and the [`ALLOWED_ON_WINDOWS_WITH_ENVIRONMENT`]
///   git generators only when the executor applies the offline environment table. The isolated
///   tier never runs on Windows as such: there is no network sandbox.
pub(super) fn is_generator_allowed_on(
    windows: bool,
    containment: Containment,
    spec: &str,
    generator: &str,
) -> bool {
    let listed = |list: &[(&str, &str)]| {
        list.binary_search_by(|(listed_spec, listed_generator)| {
            (*listed_spec, *listed_generator).cmp(&(spec, generator))
        })
        .is_ok()
    };
    if windows {
        return listed(ALLOWED_ON_WINDOWS)
            || (containment >= Containment::OfflineEnvironment
                && listed(ALLOWED_ON_WINDOWS_WITH_ENVIRONMENT));
    }
    if listed(ALLOWED_GENERATORS) {
        return true;
    }
    containment == Containment::NetworkIsolated && listed(ALLOWED_WHEN_ISOLATED)
}

/// The generators that run on Windows only when the executor applies the offline environment
/// table.
pub(super) fn generators_allowed_on_windows_with_environment()
-> &'static [(&'static str, &'static str)] {
    ALLOWED_ON_WINDOWS_WITH_ENVIRONMENT
}

/// The generators that run only in an isolated context.
pub(super) fn generators_allowed_when_isolated() -> &'static [(&'static str, &'static str)] {
    ALLOWED_WHEN_ISOLATED
}

/// Whether the alias generator named `alias` of the spec registered as `spec` (lowercase) may
/// run a command.
pub(super) fn is_alias_generator_allowed(spec: &str, alias: &str) -> bool {
    ALLOWED_ALIAS_GENERATORS
        .binary_search_by(|(allowed_spec, allowed_alias)| {
            (*allowed_spec, *allowed_alias).cmp(&(spec, alias))
        })
        .is_ok()
}

#[cfg(test)]
#[path = "generator_policy_tests.rs"]
mod tests;
