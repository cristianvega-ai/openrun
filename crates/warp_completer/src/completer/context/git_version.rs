//! The version of git that a session's commands run, and the oldest one the offline environment
//! table protects.
//!
//! The table (`offline_environment.rs` in the app crate) keeps git from running a repository's
//! `core.fsmonitor` program, its `gpg.program` and its hooks by appending `GIT_CONFIG_COUNT` /
//! `GIT_CONFIG_KEY_<n>` / `GIT_CONFIG_VALUE_<n>` overrides. Git older than 2.31 does not read
//! those variables: it ignores them and runs the repository's program anyway. Completion
//! generators that run `git` therefore run only when the session's git is known to be at least
//! [`MINIMUM_GIT_VERSION`].

use std::fmt;

/// A git release, `major.minor.patch`. A missing patch number is 0.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct GitVersion {
    pub major: u32,
    pub minor: u32,
    pub patch: u32,
}

/// The oldest git whose `GIT_CONFIG_COUNT` environment overrides take effect (git 2.31.0, March
/// 2021; `GIT_CONFIG_COUNT` is documented in `git-config(1)` from that release on).
pub const MINIMUM_GIT_VERSION: GitVersion = GitVersion::new(2, 31, 0);

/// The command that prints the version, run once per session through the session's own executor.
pub const GIT_VERSION_COMMAND: &str = "git --version";

impl GitVersion {
    pub const fn new(major: u32, minor: u32, patch: u32) -> Self {
        Self {
            major,
            minor,
            patch,
        }
    }

    /// Whether the offline environment table's git overrides work with this git.
    pub fn honors_environment_overrides(self) -> bool {
        self >= MINIMUM_GIT_VERSION
    }

    /// Parses the output of `git --version`: a line `git version <version>[ <anything>]`, where
    /// `<version>` is two or more dot-separated numbers followed by nothing, or by `-<suffix>`
    /// (`2.31.0-rc0`) or `.<non-numeric suffix>` (`2.45.1.windows.1`, `2.50.1.vfs.0.0`). Vendor
    /// text after a space (`(Apple Git-146)`) is ignored. Anything else, including a missing
    /// minor number, is `None`: a version that cannot be read is not a version that is new
    /// enough.
    pub fn parse(output: &str) -> Option<Self> {
        let rest = output
            .lines()
            .find_map(|line| line.trim().strip_prefix("git version "))?;
        let token = rest.split_whitespace().next()?;
        let numbers = token.split('-').next()?;
        let mut parts = [None::<u32>; 3];
        let mut parsed = 0;
        for (index, part) in numbers.split('.').enumerate() {
            if index >= parts.len() || part.is_empty() || !part.bytes().all(|b| b.is_ascii_digit())
            {
                break;
            }
            parts[index] = Some(part.parse().ok()?);
            parsed += 1;
        }
        if parsed < 2 {
            return None;
        }
        Some(Self::new(
            parts[0]?,
            parts[1]?,
            parts[2].unwrap_or_default(),
        ))
    }
}

impl fmt::Display for GitVersion {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}.{}.{}", self.major, self.minor, self.patch)
    }
}

#[cfg(test)]
#[path = "git_version_tests.rs"]
mod tests;
