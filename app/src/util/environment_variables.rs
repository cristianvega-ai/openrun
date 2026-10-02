//! Environment variable names and the rule for comparing them.
//!
//! Maps of variables handed to subprocesses are `HashMap<String, String>`, which compares keys
//! exactly. Windows does not: its variable names are case-insensitive. Code that looks a
//! variable up in such a map, or sets one in it, goes through this module so that a session that
//! defines `Path` or `git_config_count` is handled as the one variable it is.

use std::collections::HashMap;

/// How environment variable names compare where the subprocess is started. Windows compares them
/// ignoring case (`Path` is `PATH`, `git_config_count` is `GIT_CONFIG_COUNT`) and so does git
/// there; everywhere else `a` and `A` are two variables.
///
/// The offline table has to follow that rule in two places. Reading the session's
/// `GIT_CONFIG_COUNT` must find it whatever its spelling, or the table's pairs would be numbered
/// from 0 over the session's own. Writing a table entry must replace every spelling of the name,
/// or the map would hold `GIT_CONFIG_COUNT` and `git_config_count` and the subprocess would see
/// whichever one the operating system happens to keep.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NameCase {
    Sensitive,
    Insensitive,
}

impl NameCase {
    /// The rule of the host that starts the subprocess.
    pub const fn of_host() -> Self {
        if cfg!(windows) {
            Self::Insensitive
        } else {
            Self::Sensitive
        }
    }

    /// Whether `a` and `b` name the same variable. Insensitive comparison folds with the full
    /// Unicode uppercase mapping, which includes everything Windows folds for ASCII names.
    pub fn same(self, a: &str, b: &str) -> bool {
        match self {
            Self::Sensitive => a == b,
            Self::Insensitive => {
                a == b
                    || a.chars()
                        .flat_map(char::to_uppercase)
                        .eq(b.chars().flat_map(char::to_uppercase))
            }
        }
    }
}

/// The keys of `variables` that name `name`, exact spelling first, then the others in order.
fn spellings<'a>(
    variables: &'a HashMap<String, String>,
    name: &str,
    case: NameCase,
) -> Vec<&'a String> {
    let mut found: Vec<&String> = variables
        .keys()
        .filter(|key| case.same(key, name))
        .collect();
    found.sort_by(|a, b| (a.as_str() != name, *a).cmp(&(b.as_str() != name, *b)));
    found
}

/// The value of `name` in `variables`. When several spellings are present (which Windows cannot
/// represent in one environment) the exact one wins, then the first in sorted order, so the
/// answer does not depend on hash order.
pub fn get_variable<'a>(
    variables: &'a HashMap<String, String>,
    name: &str,
    case: NameCase,
) -> Option<&'a String> {
    spellings(variables, name, case)
        .first()
        .and_then(|key| variables.get(*key))
}

/// Sets `name` to `value`, first removing every other spelling of it.
pub fn set_variable(
    variables: &mut HashMap<String, String>,
    name: &str,
    value: String,
    case: NameCase,
) {
    remove_variable(variables, name, case);
    variables.insert(name.to_owned(), value);
}

/// Removes every spelling of `name`.
pub fn remove_variable(variables: &mut HashMap<String, String>, name: &str, case: NameCase) {
    let keys: Vec<String> = spellings(variables, name, case)
        .into_iter()
        .cloned()
        .collect();
    for key in keys {
        variables.remove(&key);
    }
}

#[cfg(test)]
#[path = "environment_variables_tests.rs"]
mod tests;
