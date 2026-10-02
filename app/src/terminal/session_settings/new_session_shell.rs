use std::path::PathBuf;

use serde::{Deserialize, Deserializer, Serialize};
use serde_json::Value;
use settings_value::SettingsValue;
use warp_util::path::ShellFamily;
use warpui::platform::OperatingSystem;

#[derive(Debug, Default, Clone, PartialEq, Eq, Hash, Serialize, schemars::JsonSchema)]
#[schemars(
    description = "Shell to use when opening new sessions.",
    rename_all = "snake_case"
)]
pub enum NewSessionShell {
    #[default]
    #[schemars(description = "Use the operating system's default shell.")]
    SystemDefault,
    #[schemars(description = "A shell executable path.")]
    Executable(String),
    #[schemars(description = "A custom shell command.")]
    Custom(String),
}

/// The values a stored `NewSessionShell` can hold, including the ones of shells that are no longer
/// supported. A stored unsupported value reads as the system default shell instead of failing the
/// whole setting.
#[derive(Serialize, Deserialize, SettingsValue)]
enum StoredNewSessionShell {
    SystemDefault,
    Executable(String),
    #[serde(rename = "MSYS2")]
    Msys2(#[allow(dead_code)] String),
    #[serde(rename = "WSL")]
    Wsl(#[allow(dead_code)] String),
    Custom(String),
}

impl From<StoredNewSessionShell> for NewSessionShell {
    fn from(stored: StoredNewSessionShell) -> Self {
        match stored {
            StoredNewSessionShell::SystemDefault
            | StoredNewSessionShell::Msys2(_)
            | StoredNewSessionShell::Wsl(_) => NewSessionShell::SystemDefault,
            StoredNewSessionShell::Executable(path) => NewSessionShell::Executable(path),
            StoredNewSessionShell::Custom(command) => NewSessionShell::Custom(command),
        }
    }
}

impl From<&NewSessionShell> for StoredNewSessionShell {
    fn from(shell: &NewSessionShell) -> Self {
        match shell {
            NewSessionShell::SystemDefault => StoredNewSessionShell::SystemDefault,
            NewSessionShell::Executable(path) => StoredNewSessionShell::Executable(path.clone()),
            NewSessionShell::Custom(command) => StoredNewSessionShell::Custom(command.clone()),
        }
    }
}

impl<'de> Deserialize<'de> for NewSessionShell {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        StoredNewSessionShell::deserialize(deserializer).map(Self::from)
    }
}

impl SettingsValue for NewSessionShell {
    fn to_file_value(&self) -> Value {
        StoredNewSessionShell::from(self).to_file_value()
    }

    fn from_file_value(value: &Value) -> Option<Self> {
        StoredNewSessionShell::from_file_value(value).map(Self::from)
    }
}

impl NewSessionShell {
    pub fn shell_family(&self) -> ShellFamily {
        let shell = match self {
            NewSessionShell::SystemDefault => return OperatingSystem::get().default_shell_family(),
            NewSessionShell::Executable(shell) | NewSessionShell::Custom(shell) => shell,
        };

        let path = PathBuf::from(shell);
        if let Some(file_stem) = path
            .file_stem()
            .and_then(|s| s.to_str().map(|s| s.to_lowercase()))
            && (file_stem.contains("powershell") || file_stem.contains("pwsh"))
        {
            return ShellFamily::PowerShell;
        }
        ShellFamily::Posix
    }
}

#[cfg(test)]
#[path = "new_session_shell_tests.rs"]
mod tests;
