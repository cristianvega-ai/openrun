//! Which of the user's typed words may reach a generator's shell command.
//!
//! A generator that takes tokens builds a shell command string from them. The dependency does
//! that in plain Rust closures: some put a word between single quotes with the quote escaped,
//! some check it, some put it in raw. The engine cannot tell which from the closure, so the
//! decision is made here, once, before the closure runs:
//!
//! * [`TokenPolicy::Strict`] is the default for every generator that takes tokens. Every word of
//!   the command line must be [inert](is_inert_word): letters, digits and `. _ / : @ + , = -`
//!   only, so that no shell (bash, zsh, fish, PowerShell, cmd) can read any of it as syntax,
//!   whatever the closure does with it.
//! * [`TokenPolicy::Escaped`] is for generators reviewed to quote the word they use for POSIX
//!   shells (`'` becomes `'\''`) or to check it, and covered by the injection corpus. Any word
//!   without control characters or a backslash is allowed on bash, zsh and fish. A backslash
//!   is refused because fish reads `\'` inside single quotes as an escaped quote, so the
//!   POSIX quoting breaks out in fish. On PowerShell and cmd it is `Strict` too: `'` is not
//!   escaped as `\'` there.
//! * [`TokenPolicy::Inert`] is for generators whose command does not depend on the tokens at
//!   all (the corpus checks that).
//!
//! The words of `KEY=value` assignments typed before the command are filtered the same way,
//! for every generator ([`sanitize_env_vars`]).
//!
//! A generator that is not in the table below is `Strict`. A word that fails the check makes the
//! engine skip the generator: nothing is run and no suggestion is made.

use warp_util::path::ShellFamily;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum TokenPolicy {
    /// The command does not depend on the tokens.
    Inert,
    /// The generator quotes or checks the word it uses, for POSIX shells.
    Escaped,
    /// Every word must be inert. The default.
    Strict,
}

/// Generators that are not `Strict`, sorted by `(spec, generator)`. Entries remain classified when their tools are denied;
/// token safety alone never grants execution. The injection corpus verifies these policies.
const TOKEN_POLICIES: &[(&str, &str, TokenPolicy)] = &[
    ("apt", "list_prefix", TokenPolicy::Escaped),
    ("chown", "users_or_groups", TokenPolicy::Escaped),
    ("docker", "from_as", TokenPolicy::Escaped),
    ("git", "local_or_remote_branch", TokenPolicy::Inert),
    ("git", "push_refspec_branches", TokenPolicy::Inert),
    ("git", "push_refspec_tags", TokenPolicy::Inert),
    ("git-flow", "type_branches", TokenPolicy::Escaped),
    ("kubecolor", "cluster", TokenPolicy::Escaped),
    ("kubecolor", "context", TokenPolicy::Escaped),
    ("kubecolor", "user", TokenPolicy::Escaped),
    ("kubectl", "cluster", TokenPolicy::Escaped),
    ("kubectl", "context", TokenPolicy::Escaped),
    ("kubectl", "user", TokenPolicy::Escaped),
    ("man", "list_man_pages", TokenPolicy::Inert),
    ("mosh", "cat_ssh_known_hosts", TokenPolicy::Escaped),
    ("oc", "cluster", TokenPolicy::Escaped),
    ("oc", "context", TokenPolicy::Escaped),
    ("oc", "user", TokenPolicy::Escaped),
    ("robot", "variables", TokenPolicy::Inert),
    ("sftp", "cat_ssh_known_hosts", TokenPolicy::Escaped),
    ("st2", "users_or_groups", TokenPolicy::Escaped),
];

pub fn token_policy(spec: &str, generator: &str) -> TokenPolicy {
    TOKEN_POLICIES
        .binary_search_by(|(listed_spec, listed_generator, _)| {
            (*listed_spec, *listed_generator).cmp(&(spec, generator))
        })
        .map_or(TokenPolicy::Strict, |index| TOKEN_POLICIES[index].2)
}

#[cfg(test)]
pub(super) fn listed_token_policies() -> &'static [(&'static str, &'static str, TokenPolicy)] {
    TOKEN_POLICIES
}

impl TokenPolicy {
    /// Whether a generator with this policy may be given `tokens` (the whole command line, as
    /// the tokenizer split it) in a shell of `family`.
    pub fn permits(self, family: ShellFamily, tokens: &[&str]) -> bool {
        match (self, family) {
            (TokenPolicy::Inert, _) => true,
            (TokenPolicy::Escaped, ShellFamily::Posix) => {
                tokens.iter().all(|token| is_quotable_word(token))
            }
            (TokenPolicy::Escaped | TokenPolicy::Strict, _) => {
                tokens.iter().all(|token| is_inert_word(token))
            }
        }
    }
}

fn is_inert_character(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '/' | ':' | '@' | '+' | ',' | '=' | '-')
}

/// A word no shell reads as syntax: only letters, digits and `. _ / : @ + , = -`. It does not
/// start with `=` (zsh expands `=cmd` to the path of `cmd`), and when it starts with `-` it has
/// the shape of a flag (`-f`, `--file`, `--file=x`), so it cannot be a lone `-` or a string of
/// dashes that some tool reads as an option terminator.
pub fn is_inert_word(word: &str) -> bool {
    if !word.chars().all(is_inert_character) || word.starts_with('=') {
        return false;
    }
    match word.strip_prefix('-') {
        None => true,
        Some(rest) => {
            let rest = rest.strip_prefix('-').unwrap_or(rest);
            rest.chars()
                .next()
                .is_some_and(|c| c.is_ascii_alphanumeric())
        }
    }
}

/// A word that is safe inside POSIX single quotes in bash, zsh and fish once `'` is escaped as
/// `'\''`: no control character (NUL, newline, escape, ...) and no backslash.
pub fn is_quotable_word(word: &str) -> bool {
    !word.chars().any(|c| c.is_control() || c == '\\')
}

/// The `KEY=value` words typed before the command, without those that are not inert. The key is
/// a shell variable name and the value an inert word.
pub fn sanitize_env_vars(env_vars: &[String]) -> Vec<String> {
    env_vars
        .iter()
        .filter(|assignment| {
            assignment.split_once('=').is_some_and(|(key, value)| {
                let mut chars = key.chars();
                chars
                    .next()
                    .is_some_and(|c| c.is_ascii_alphabetic() || c == '_')
                    && chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
                    && value.chars().all(is_inert_character)
                    && !value.starts_with('=')
            })
        })
        .cloned()
        .collect()
}
