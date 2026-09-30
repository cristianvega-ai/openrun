//! Which completion generators may run a command.
//!
//! A `warp-command-signatures` spec can name a *generator*: a shell command the completion
//! engine runs on every completion request to list things such as git branches or npm scripts.
//! The bundled generators are not all local. Some run `curl` against public registries with the
//! text the user is typing, and some call cloud CLIs, `gh`, `kubectl` or `ssh`. Completion
//! requests fire while the user is still typing (autosuggestions) and on Tab, so an unreviewed
//! generator is a network request the user never asked for.
//!
//! The policy is default-deny and works by identity, never by inspecting the command line: a
//! generator runs only if its `(spec, generator name)` pair is in `allowed.rs`. The check is in
//! `CommandRegistry::allows_generator`, called from the one place that executes generators
//! (`completer::engine::argument::legacy`, before the shell command is even built). Alias
//! generators are not covered because the bundled ones only read local files (a test checks it).
//!
//! # Classifying generators
//!
//! * `allowed.rs` lists the generators whose command reads only the local machine: files, the
//!   repository, local daemons. If in doubt, deny.
//! * `denied.rs` lists generators that can reach a network, with a class. It is not consulted at
//!   runtime; it lets the drift test tell a reviewed generator from an unclassified one.
//! * The drift test (`generator_policy_tests.rs`) enumerates
//!   `warp_command_signatures::dynamic_command_signature_data()` and fails, listing the pairs and
//!   their commands, when a pair is in neither file. Bumping the `command-signatures` pin
//!   therefore forces a review. Put each new pair in exactly one of the files, keeping both sorted.
//! * Stripping the network generators from our future `command-signatures` fork (DEP-05) is the
//!   follow-up; this allow-list stays as the guard in this repository.

mod allowed;
#[cfg(test)]
mod denied;

use allowed::ALLOWED_GENERATORS;

/// Whether the generator named `generator` of the spec registered as `spec` (lowercase) is on
/// the local-only allow-list.
pub(super) fn is_generator_allowed(spec: &str, generator: &str) -> bool {
    ALLOWED_GENERATORS
        .binary_search_by(|(allowed_spec, allowed_generator)| {
            (*allowed_spec, *allowed_generator).cmp(&(spec, generator))
        })
        .is_ok()
}

#[cfg(test)]
#[path = "generator_policy_tests.rs"]
mod tests;
