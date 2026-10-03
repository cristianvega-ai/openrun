use std::borrow::Cow;
use std::iter;
use std::path::{Path, PathBuf};

use command::blocking::Command;
use rand::distributions::Alphanumeric;
use rand::{Rng, thread_rng};
use regex::Regex;

use crate::terminal::local_tty::shell::{DirectShellStarter, ShellStarterSource};
use crate::terminal::shell;
use crate::terminal::shell::ShellType;

/// Returns the shell starter along with the version of the shell about to be run.
pub fn current_shell_starter_and_version() -> (DirectShellStarter, String) {
    let shell_starter_source =
        ShellStarterSource::init(crate::terminal::available_shells::AvailableShell::default())
            .expect("Could not create a shell starter source");
    let starter = DirectShellStarter::from(shell_starter_source);
    let version = match starter.shell_type() {
        shell::ShellType::Zsh => {
            let stdout = Command::new(starter.logical_shell_path())
                .args(["-c", "echo $ZSH_VERSION"])
                .output()
                .expect("version command should run")
                .stdout;
            String::from_utf8_lossy(&stdout).into_owned()
        }
        shell::ShellType::Bash => {
            let stdout = Command::new(starter.logical_shell_path())
                .args(["-c", "echo $BASH_VERSION"])
                .output()
                .expect("version command should run")
                .stdout;
            String::from_utf8_lossy(&stdout).into_owned()
        }
        shell::ShellType::Fish => {
            let stdout = Command::new(starter.logical_shell_path())
                .args(["-c", "echo $FISH_VERSION"])
                .output()
                .expect("version command should run")
                .stdout;
            String::from_utf8_lossy(&stdout).into_owned()
        }
        shell::ShellType::PowerShell => {
            let stdout = Command::new(starter.logical_shell_path())
                .args(["-Version"])
                .output()
                .expect("version command should run")
                .stdout;
            String::from_utf8_lossy(&stdout).into_owned()
        }
    };
    assert!(!version.is_empty());
    (starter, version)
}

/// Returns the directory for the default histfile location for the ShellType in this
/// ShellStarter based on the given user `home_dir`.
pub fn default_histfile_directory(shell: &ShellType, home_dir: &Path) -> PathBuf {
    match shell {
        ShellType::Fish => home_dir.join(".local/share/fish"),
        ShellType::PowerShell => home_dir.join(".local/share/powershell/PSReadLine"),
        _ => home_dir.to_owned(),
    }
}

/// Generates a random nonce to distinguish between commands.
pub fn nonce() -> String {
    let mut rng = thread_rng();
    iter::repeat(())
        .map(|()| rng.sample(Alphanumeric))
        .map(char::from)
        .take(7)
        .collect()
}

pub use crate::terminal::model::exit_status_check::ExpectedExitStatus;

/// A representation of the expected output from running a command.
pub trait ExpectedOutput: std::fmt::Debug {
    /// Returns whether the given result matches the expected output.
    fn matches(&self, result: &str) -> bool;
}

#[derive(Debug)]
pub struct ExactLine<'a>(Cow<'a, str>);

impl<'a, T: Into<Cow<'a, str>>> From<T> for ExactLine<'a> {
    fn from(value: T) -> Self {
        ExactLine(value.into())
    }
}

impl ExpectedOutput for str {
    fn matches(&self, result: &str) -> bool {
        self == result
    }
}

impl<T: ExpectedOutput + ?Sized> ExpectedOutput for &T {
    fn matches(&self, result: &str) -> bool {
        (*self).matches(result)
    }
}

impl ExpectedOutput for String {
    fn matches(&self, result: &str) -> bool {
        self == result
    }
}

impl ExpectedOutput for ExactLine<'_> {
    fn matches(&self, result: &str) -> bool {
        result.lines().any(|line| line == self.0)
    }
}

impl ExpectedOutput for Regex {
    fn matches(&self, result: &str) -> bool {
        self.is_match(result)
    }
}

impl ExpectedOutput for Path {
    fn matches(&self, result: &str) -> bool {
        self.to_str() == Some(result)
    }
}

impl ExpectedOutput for PathBuf {
    fn matches(&self, result: &str) -> bool {
        self.as_path().matches(result)
    }
}

impl ExpectedOutput for () {
    fn matches(&self, _result: &str) -> bool {
        true
    }
}

impl<T: ExpectedOutput> ExpectedOutput for Option<T> {
    fn matches(&self, result: &str) -> bool {
        match self {
            Some(expected) => expected.matches(result),
            None => true,
        }
    }
}

#[derive(Debug)]
pub struct JsonEq(pub serde_json::Value);

impl ExpectedOutput for JsonEq {
    fn matches(&self, result: &str) -> bool {
        match serde_json::from_str::<serde_json::Value>(result) {
            Ok(actual) => actual == self.0,
            Err(_) => false,
        }
    }
}
