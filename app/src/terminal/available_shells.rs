use std::borrow::Cow;
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use settings::Setting as _;
use warpui::{AppContext, Entity, ModelContext, SingletonEntity};

use super::ShellLaunchData;
use super::session_settings::{NewSessionShell, StartupShell};
use super::shell::ShellType;
use crate::util::path::file_exists_and_is_executable;

#[derive(Debug, PartialEq, Eq, Hash)]
struct LocalConfig {
    command: String,
    executable_path: PathBuf,
    shell_type: ShellType,
}

impl crate::terminal::local_tty::shell::AvailableShell for AvailableShell {
    fn get_valid_shell_path_and_type(&self) -> Option<ShellLaunchData> {
        AvailableShell::get_valid_shell_path_and_type(self)
    }
}

impl TryFrom<StartupShell> for LocalConfig {
    type Error = ();

    fn try_from(value: StartupShell) -> Result<Self, Self::Error> {
        use crate::terminal::local_tty::shell::supported_shell_path_and_type;

        let command = value.shell_command().ok_or(())?;
        let (path, shell_type) = supported_shell_path_and_type(command).ok_or(())?;
        Ok(Self {
            command: command.to_string(),
            executable_path: path.to_path_buf(),
            shell_type,
        })
    }
}

/// The state for the AvailableShell model. Is kept private to the module, b/c we do not want people
/// manually destructuring or matching on this data.
#[derive(Debug, PartialEq, Eq, Hash)]
enum Config {
    SystemDefault,
    KnownLocal(LocalConfig),
    Custom(LocalConfig),
}

// The concept of specifying an available shell does not exist on non-local filesystems. So we allow
// dead code so that the concept of the struct can exist, but remove any methods that do anything
// with it. That way, method calls can still take `Option<AvailableShell>` as an argument, but
// builds without a local tty can just specify `None` for the value.
/// Contains the config describing a 'shell' that can be launched for a new session. Currently falls
/// into 3 categories:
/// - Known Local: A shell that is known to be installed on the local filesystem, and can be run
///   by invoking an executable.
/// - Custom: A user-specified custom executable that can be run locally.
/// - System Default: Uses the default shell for a given system.
///
/// All state is stored in an Arc so that it can be safely and easily copied. In general, unless you
/// are using a custom shell, you should not be constructing this struct directly. Instead, use the
/// methods available on the `AvailableShells` model.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct AvailableShell {
    id: Option<String>,
    state: Arc<Config>,
}

impl AvailableShell {
    /// Returns an "id" associated with a known shell. If
    /// shell1.is_some_and(|id1| shell2.is_some_and(|id2| id1 == id2)) holds,
    /// then shell1 and shell2 are the same shell.
    pub fn id(&self) -> Option<&str> {
        self.id.as_deref()
    }

    pub fn short_name(&self) -> Cow<'_, str> {
        match self.state.as_ref() {
            Config::SystemDefault => Cow::from("Default"),
            Config::KnownLocal(LocalConfig { command, .. }) => match command.as_str() {
                "bash" => Cow::from("Bash"),
                "zsh" => Cow::from("Zsh"),
                "fish" => Cow::from("Fish"),
                "pwsh" => Cow::from("PowerShell"),
                _ => Cow::from(command),
            },
            Config::Custom(_) => Cow::from("Custom"),
        }
    }

    pub fn details(&self) -> Cow<'_, str> {
        match self.state.as_ref() {
            Config::SystemDefault => Cow::from("System default shell"),
            Config::KnownLocal(LocalConfig {
                executable_path, ..
            }) => Cow::from(format!("{}", executable_path.display())),
            Config::Custom(LocalConfig {
                executable_path, ..
            }) => Cow::from(format!("Custom: {}", executable_path.display())),
        }
    }
}

impl AvailableShell {
    /// The long name of the shell. For local shells, this includes the path to
    /// the executable.
    fn long_name(&self) -> String {
        match &self.state.as_ref() {
            Config::SystemDefault => "Default".to_string(),
            Config::KnownLocal(LocalConfig {
                executable_path, ..
            }) => format!("{} ({})", self.short_name(), executable_path.display()),
            Config::Custom(LocalConfig { command, .. }) => format!("Custom ({command})"),
        }
    }

    /// If the shell is a Custom shell, returns the custom shell path. Otherwise returns None. Can
    /// also be used to assert whether or not the shell is a custom shell using `is_some()`.
    pub fn get_custom_path(&self) -> Option<String> {
        if let Config::Custom(config) = self.state.as_ref() {
            Some(config.executable_path.display().to_string())
        } else {
            None
        }
    }

    fn matches_preference(&self, preference: &NewSessionShell) -> bool {
        match preference {
            NewSessionShell::SystemDefault => matches!(self.state.as_ref(), Config::SystemDefault),
            NewSessionShell::Executable(path) => {
                matches!(self.state.as_ref(), Config::KnownLocal(LocalConfig { executable_path, .. }) if executable_path == Path::new(path))
            }
            NewSessionShell::Custom(path) => {
                matches!(self.state.as_ref(), Config::Custom(LocalConfig { executable_path, .. }) if executable_path == Path::new(path))
            }
        }
    }

    /// Returns the launch data for a shell.
    ///
    /// Our conversion methodology is as follows:
    ///
    /// | [`AvailableShell`]         | Validation | [`Option<ShellLaunchData>`]        |
    /// |:---------------------------|:----------:|-----------------------------------:|
    /// | [`Config::SystemDefault`]  | No         | [`Option::None`]                   |
    /// | [`Config::KnownLocal`]     | Yes        | [`ShellLaunchData::Executable`]    |
    /// | [`Config::Custom`]         | Yes        | [`ShellLaunchData::Executable`]    |
    ///
    /// For `KnownLocal` and `Custom` we validate that the executable path
    /// is still valid.
    pub fn get_valid_shell_path_and_type(&self) -> Option<ShellLaunchData> {
        match self.state.as_ref() {
            Config::SystemDefault => None,
            Config::KnownLocal(LocalConfig {
                executable_path,
                shell_type,
                ..
            })
            | Config::Custom(LocalConfig {
                executable_path,
                shell_type,
                ..
            }) => {
                // We already did the supported_shell_path_and_type when constructing the model, but
                // in case the model is out of date we want to verify that the exe is still there.
                if file_exists_and_is_executable(executable_path) {
                    Some(ShellLaunchData::Executable {
                        executable_path: executable_path.clone(),
                        shell_type: *shell_type,
                    })
                } else {
                    None
                }
            }
        }
    }

    fn new_local_executable(
        command: String,
        executable_path: PathBuf,
        shell_type: ShellType,
    ) -> Self {
        Self {
            id: Some(format!("local:{}", executable_path.display())),
            state: Arc::new(Config::KnownLocal(LocalConfig {
                command,
                executable_path,
                shell_type,
            })),
        }
    }

    pub(crate) fn new_custom_shell(
        command: String,
        executable_path: PathBuf,
        shell_type: ShellType,
    ) -> Self {
        Self {
            id: None,
            state: Arc::new(Config::Custom(LocalConfig {
                command,
                executable_path,
                shell_type,
            })),
        }
    }
}

impl From<AvailableShell> for NewSessionShell {
    fn from(value: AvailableShell) -> Self {
        match value.state.as_ref() {
            Config::SystemDefault => NewSessionShell::SystemDefault,
            Config::KnownLocal(LocalConfig {
                executable_path, ..
            }) => NewSessionShell::Executable(executable_path.display().to_string()),
            Config::Custom(LocalConfig {
                executable_path, ..
            }) => NewSessionShell::Custom(executable_path.display().to_string()),
        }
    }
}

impl From<AvailableShell> for StartupShell {
    fn from(value: AvailableShell) -> Self {
        match value.state.as_ref() {
            Config::SystemDefault => StartupShell::Default,
            Config::KnownLocal(LocalConfig { shell_type, .. }) => {
                StartupShell::from(Some(shell_type.name().to_string()))
            }
            Config::Custom(LocalConfig {
                executable_path, ..
            }) => StartupShell::Custom(executable_path.display().to_string()),
        }
    }
}

impl Default for AvailableShell {
    fn default() -> Self {
        Self {
            id: None,
            state: Arc::new(Config::SystemDefault),
        }
    }
}

impl TryFrom<&str> for AvailableShell {
    type Error = ();

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        use crate::terminal::local_tty::shell::supported_shell_path_and_type;
        let (path, shell_type) = supported_shell_path_and_type(value).ok_or(())?;
        let command = path
            .file_name()
            .and_then(|file_name| file_name.to_str())
            .ok_or(())?
            .to_string();
        Ok(Self::new_custom_shell(command, path, shell_type))
    }
}

impl TryFrom<NewSessionShell> for AvailableShell {
    type Error = ();

    fn try_from(value: NewSessionShell) -> Result<Self, Self::Error> {
        if let NewSessionShell::Custom(path) = &value {
            Ok(AvailableShell::try_from(path.as_str())?)
        } else {
            Err(())
        }
    }
}

pub struct AvailableShells {
    shells: Vec<AvailableShell>,
    /// A map of shell name to the number of times it appears in the list.
    shell_counts: HashMap<String, usize>,
}

impl AvailableShells {
    pub fn new(_ctx: &mut ModelContext<Self>) -> Self {
        let fallback_shells_path = Some(Path::new("/etc/shells"));

        let env_path = std::env::var_os("PATH").unwrap_or_default();
        let mut paths_to_search = std::env::split_paths(&env_path).collect::<Vec<PathBuf>>();

        // The PATH here is limited since it doesn't include the locations added
        // by the user's login shell. We add the Homebrew installer locations to
        // the search paths so we can detect shells installed via Homebrew.
        {
            // Apple Silicon homebrew path
            paths_to_search.push(PathBuf::from("/opt/homebrew/bin"));
            // Intel homebrew path
            paths_to_search.push(PathBuf::from("/usr/local/bin"));
        }

        let shells = Self::load_known_shells(&paths_to_search, fallback_shells_path);

        let shell_counts = shells.iter().fold(HashMap::new(), |mut counts, shell| {
            let count = counts.entry(shell.short_name().to_string()).or_insert(0);
            *count += 1;
            counts
        });
        Self {
            shells,
            shell_counts,
        }
    }

    /// Returns an iterable that iterates over all available shells.
    pub fn get_available_shells(&self) -> impl Iterator<Item = &AvailableShell> {
        self.shells.iter()
    }

    /// Returns the display name for a shell, context aware of the other
    /// available shells. If the shell appears only once, we return the short
    /// name. If the shell appears multiple times, we disambiguate by showing
    /// the full name with the path to the executable.
    pub fn display_name_for_shell<'a>(&self, shell: &'a AvailableShell) -> Cow<'a, str> {
        if self
            .shell_counts
            .get::<str>(shell.short_name().as_ref())
            .is_some_and(|count| *count > 1)
        {
            Cow::from(shell.long_name())
        } else {
            shell.short_name()
        }
    }

    /// Attempts to convert from ShellLaunchData into an AvailableShell
    ///
    /// **Note: This is here b/c we need to be able to get an AvailableShell
    /// from snapshot data. You probably should not be calling this.**
    ///
    /// The methodology is:
    ///
    /// 1. Search for a matching shell in the list of AvailableShells.
    ///    If it exists, then we return it. This covers all `KnownLocal` cases.
    /// 2. If we have `Executable`` data that has not matched the list, we convert it to
    ///    a custom shell. This covers the case of either a Custom shell or a KnownLocal
    ///    that for whatever reason is no longer valid. An invalid Custom or KnownLocal
    ///    will still be validated before launching a shell (and fall back to default),
    ///    so it is fine to return a Custom here.
    ///
    /// See [`AvailableShell::get_valid_shell_path_and_type`] for more information on how
    /// we generate these launch configs in the other direction.
    pub fn get_from_shell_launch_data(&self, config: &ShellLaunchData) -> Option<AvailableShell> {
        let ShellLaunchData::Executable {
            executable_path,
            shell_type,
        } = config;
        self.shells
            .iter()
            .find(|shell| {
                matches!(
                    shell.state.as_ref(),
                    Config::KnownLocal(LocalConfig {
                        executable_path: known_path,
                        shell_type: known_type,
                        ..
                    }) if known_path == executable_path && known_type == shell_type
                )
            })
            .cloned()
            .or_else(|| {
                Some(AvailableShell::new_custom_shell(
                    executable_path.file_name()?.to_str()?.to_string(),
                    executable_path.clone(),
                    *shell_type,
                ))
            })
    }

    /// Checks the user preferences for the shell to use for new sessions, returning an available
    /// shell object.
    pub fn get_user_preferred_shell(&self, ctx: &AppContext) -> AvailableShell {
        let preference = self.get_user_preferred_shell_setting(ctx);

        match preference {
            NewSessionShell::SystemDefault => AvailableShell::default(),
            NewSessionShell::Custom(_) => AvailableShell::try_from(preference).unwrap_or_default(),
            // TODO(DAN): This should be cached in the model. Also handle custom
            preference => self
                .shells
                .iter()
                .find(|shell| shell.matches_preference(&preference))
                .cloned()
                .unwrap_or_default(),
        }
    }

    /// Sets the user-preferred shell for new sessions. Saves the value back to user settings.
    pub fn set_user_preferred_shell(
        &self,
        value: AvailableShell,
        ctx: &mut ModelContext<Self>,
    ) -> anyhow::Result<()> {
        use super::session_settings::SessionSettings;
        SessionSettings::handle(ctx).update(ctx, |settings, ctx| {
            settings
                .new_session_shell_override
                .set_value(Some(NewSessionShell::from(value)), ctx)
        })
    }

    fn load_known_shells(
        paths_to_search: &[PathBuf],
        fallback_path: Option<&Path>,
    ) -> Vec<AvailableShell> {
        let shell_types = Self::get_shell_types();

        let mut known_shells = vec![];
        let mut fallback_shell_map = fallback_path
            .and_then(|path| Self::load_fallback_shells(path, &shell_types).ok())
            .unwrap_or_default();

        for (shell_type, command_name) in shell_types {
            let mut fallback_shells = fallback_shell_map.remove(command_name).unwrap_or_default();
            for path in Self::resolve_all_executables(command_name, paths_to_search.iter()) {
                fallback_shells.remove(&path);
                known_shells.push(AvailableShell::new_local_executable(
                    command_name.to_string(),
                    path,
                    shell_type,
                ));
            }

            // We append shells found in /etc/shells but not the path after the shells found on the path.
            for path in fallback_shells.iter() {
                if file_exists_and_is_executable(path) {
                    known_shells.push(AvailableShell::new_local_executable(
                        command_name.to_string(),
                        path.clone(),
                        shell_type,
                    ));
                }
            }
        }

        known_shells
    }

    fn get_shell_types() -> Vec<(ShellType, &'static str)> {
        vec![
            (ShellType::Zsh, "zsh"),
            (ShellType::Bash, "bash"),
            (ShellType::Fish, "fish"),
            (ShellType::PowerShell, "pwsh"),
        ]
    }

    /// Resolves all full paths to executables of the given command name in PATH.
    ///
    /// `paths_to_search` should contain the locations in PATH along with any
    /// manually added paths that we want to search.
    fn resolve_all_executables<'a>(
        command: &str,
        paths_to_search: impl Iterator<Item = &'a PathBuf>,
    ) -> Vec<PathBuf> {
        use itertools::Itertools as _;

        paths_to_search
            .filter_map(|single_path| {
                let joined = single_path.join(command);
                let canonicalized = std::fs::canonicalize(&joined).unwrap_or(joined);
                file_exists_and_is_executable(&canonicalized).then_some(canonicalized)
            })
            .unique()
            .collect()
    }

    fn load_fallback_shells(
        path: &Path,
        shell_types: &[(ShellType, &str)],
    ) -> anyhow::Result<HashMap<String, HashSet<PathBuf>>> {
        use std::fs::File;
        use std::io::{BufRead, BufReader};

        let mut shells = HashMap::new();

        let file = File::open(path)?;

        for (_, exe) in shell_types.iter() {
            shells.insert(exe.to_string(), HashSet::new());
        }

        let reader = BufReader::new(file);
        for line in reader.lines() {
            let line = line?;
            // For each line in /etc/shells, we check:
            // - does it not start with a #?
            // - is it not empty?
            // - does the "file_name" map to a shell that we support?
            //
            // If all of those are true, then we add it to the set of paths associated with that shell
            if !line.trim_start().starts_with('#') && !line.trim().is_empty() {
                let Ok(path) = std::fs::canonicalize(line) else {
                    continue;
                };
                if let Some(file_name) = path.file_name().and_then(|name| name.to_str())
                    && let Some(set) = shells.get_mut(file_name)
                {
                    set.insert(path);
                }
            }
        }
        Ok(shells)
    }

    fn get_user_preferred_shell_setting(&self, ctx: &AppContext) -> NewSessionShell {
        use super::session_settings::SessionSettings;

        let new_session_shell_override = SessionSettings::as_ref(ctx)
            .new_session_shell_override
            .to_owned();

        new_session_shell_override.unwrap_or_else(|| {
            // Fallback logic in case the new_session_shell has not been set.
            // We attempt to read the legacy setting startup_shell_override, and map it to a
            // NewSessionShell. If that mapping fails at all, we set it to NewSessionShell::SystemDefault.
            // We also write back to the new_session_shell_override setting so that we don't have to do this
            // all the time.
            self.get_user_preferred_shell_setting_fallback(ctx)
        })
    }

    fn get_user_preferred_shell_setting_fallback(&self, ctx: &AppContext) -> NewSessionShell {
        use super::session_settings::SessionSettings;

        let startup_shell = SessionSettings::as_ref(ctx)
            .startup_shell_override
            .to_owned();
        match startup_shell {
            StartupShell::Default => NewSessionShell::SystemDefault,
            StartupShell::Custom(path) => NewSessionShell::Custom(path),
            _ => startup_shell
                .shell_command()
                .and_then(|command| {
                    for shell in self.shells.iter() {
                        if let Config::KnownLocal(LocalConfig {
                            command: shell_command,
                            executable_path,
                            ..
                        }) = shell.state.as_ref()
                            && shell_command == command
                        {
                            return Some(NewSessionShell::Executable(
                                executable_path.display().to_string(),
                            ));
                        }
                    }
                    None
                })
                .unwrap_or(NewSessionShell::SystemDefault),
        }
    }

    /// Finds the first shell that matches the given shell type.
    pub fn find_known_shell_by_type(&self, shell: ShellType) -> Option<AvailableShell> {
        self.shells
            .iter()
            .find(|s| matches!(s.state.as_ref(), Config::KnownLocal(LocalConfig { shell_type, .. }) if shell == *shell_type))
            .cloned()
    }

    /// Finds the first known shell whose command name matches `name`.
    ///
    /// This is used to resolve a bare shell name from a tab config (e.g.
    /// `shell = "pwsh"`) against shells that [`AvailableShells::new`] has
    /// already discovered. Because that discovery supplements the process
    /// `PATH` with well-known install locations (such as `/opt/homebrew/bin`
    /// on macOS), this lookup can find shells that a plain `PATH` search via
    /// [`AvailableShell::try_from`] would miss when Warp is launched outside
    /// an interactive shell.
    ///
    /// Comparison is case-sensitive.
    pub fn find_by_command_name(&self, name: &str) -> Option<AvailableShell> {
        self.shells
            .iter()
            .find(|shell| {
                let command = match shell.state.as_ref() {
                    Config::KnownLocal(LocalConfig { command, .. }) => command.as_str(),
                    Config::Custom(_) | Config::SystemDefault => {
                        return false;
                    }
                };
                command == name
            })
            .cloned()
    }
}

impl Entity for AvailableShells {
    type Event = ();
}
impl SingletonEntity for AvailableShells {}

pub fn register(app: &mut impl warpui::AddSingletonModel) {
    app.add_singleton_model(AvailableShells::new);
}

#[cfg(test)]
#[path = "available_shells_tests.rs"]
mod tests;
