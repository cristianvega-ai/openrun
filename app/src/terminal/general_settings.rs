use settings::Setting as _;
use settings_value::LenientSet;
use strum_macros::EnumIter;
use warp_core::settings::SupportedPlatforms;
use warp_core::settings::macros::define_settings_group;
use warpui::{AppContext, SingletonEntity as _};

use crate::banner::BannerState;
use crate::resource_center::Tip;
use crate::tab_configs::TabConfig;
use crate::user_config::WarpConfig;

/// The default mode for new terminal sessions.
#[derive(
    Default, Debug, serde::Serialize, PartialEq, Copy, Clone, EnumIter, schemars::JsonSchema,
)]
#[schemars(
    description = "Default mode for new sessions.",
    rename_all = "snake_case"
)]
pub enum DefaultSessionMode {
    /// New sessions start in the terminal mode (default).
    #[default]
    Terminal,
    /// New sessions open a user-defined tab config.
    /// The specific config is identified by the companion `default_tab_config_path` setting.
    TabConfig,
}

settings::macros::implement_setting_for_enum!(
    DefaultSessionMode,
    GeneralSettings,
    SupportedPlatforms::ALL,
    private: false,
    toml_path: "general.default_session_mode",
    description: "The default mode for new terminal sessions.",
);

/// Modes that earlier builds offered and that no longer exist. A stored value naming one of
/// these opens new sessions in the default mode instead of invalidating the setting.
const RETIRED_DEFAULT_SESSION_MODES: [&str; 3] = ["agent", "cloud_agent", "docker_sandbox"];

impl DefaultSessionMode {
    /// Reads a stored mode name in either the settings-file (`tab_config`) or the serialized
    /// (`TabConfig`) spelling. Retired modes read as the default; unknown names are rejected.
    fn from_stored_name(name: &str) -> Option<Self> {
        let snake_case = name
            .chars()
            .enumerate()
            .flat_map(|(index, c)| {
                let separator = (c.is_ascii_uppercase() && index > 0).then_some('_');
                separator
                    .into_iter()
                    .chain(std::iter::once(c.to_ascii_lowercase()))
            })
            .collect::<String>();
        match snake_case.as_str() {
            "terminal" => Some(Self::Terminal),
            "tab_config" => Some(Self::TabConfig),
            retired if RETIRED_DEFAULT_SESSION_MODES.contains(&retired) => {
                log::warn!("Ignoring retired default session mode {name:?}");
                Some(Self::default())
            }
            _ => None,
        }
    }

    fn file_name(&self) -> &'static str {
        match self {
            DefaultSessionMode::Terminal => "terminal",
            DefaultSessionMode::TabConfig => "tab_config",
        }
    }
}

impl<'de> serde::Deserialize<'de> for DefaultSessionMode {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let name = String::deserialize(deserializer)?;
        Self::from_stored_name(&name).ok_or_else(|| {
            serde::de::Error::custom(format!("unknown default session mode {name:?}"))
        })
    }
}

impl settings_value::SettingsValue for DefaultSessionMode {
    fn to_file_value(&self) -> serde_json::Value {
        serde_json::Value::String(self.file_name().to_owned())
    }

    fn from_file_value(value: &serde_json::Value) -> Option<Self> {
        Self::from_stored_name(value.as_str()?)
    }
}

impl DefaultSessionMode {
    /// Display name for the settings dropdown.
    pub fn display_name(&self) -> &'static str {
        match self {
            DefaultSessionMode::Terminal => "Terminal",
            DefaultSessionMode::TabConfig => "Tab Config",
        }
    }
}

define_settings_group!(GeneralSettings, settings: [
    show_warning_before_quitting: ShowWarningBeforeQuitting {
        type: bool,
        default: true,
        supported_platforms: SupportedPlatforms::DESKTOP,
        private: false,
        toml_path: "general.show_warning_before_quitting",
        description: "Whether to show a warning dialog before quitting Warp.",
    },
    quit_on_last_window_closed: QuitOnLastWindowClosed {
        type: bool,
        default: false,
        supported_platforms: SupportedPlatforms::MAC,
        private: false,
        toml_path: "general.quit_on_last_window_closed",
        description: "Whether to quit Warp when the last window is closed.",
    },
    restore_session: RestoreSession {
        type: bool,
        default: true,
        supported_platforms: SupportedPlatforms::DESKTOP,
        private: false,
        toml_path: "general.restore_session",
        description: "Whether to restore the previous session when Warp starts up.",
    },
    add_app_as_login_item: LoginItem {
        type: bool,
        default: true,
        supported_platforms: SupportedPlatforms::OR(
            Box::new(SupportedPlatforms::MAC),
            Box::new(SupportedPlatforms::WINDOWS),
        ),
        private: false,
        toml_path: "general.login_item",
        description: "Whether to launch Warp automatically when you log in.",
    },
    // Records whether the app has been added as a login item.
    // If it has, we don't try to add it again unless the user explicitly
    // retoggles the setting. This is to allow a user to remove the login item
    // directly from their OS's startup UI and not have it re-added when they
    // next start Warp.
    app_added_as_login_item: AppAddedAsLoginItem {
        type: bool,
        default: false,
        supported_platforms: SupportedPlatforms::OR(
            Box::new(SupportedPlatforms::MAC),
            Box::new(SupportedPlatforms::WINDOWS),
        ),
        private: true,
    },
    link_tooltip: LinkTooltip {
        type: bool,
        default: true,
        supported_platforms: SupportedPlatforms::ALL,
        private: false,
        toml_path: "general.link_tooltip",
        description: "Whether to show a tooltip when hovering over links.",
    },
    welcome_tips_features_used: WelcomeTipsFeaturesUsed {
        type: LenientSet<Tip>,
        default: LenientSet::default(),
        supported_platforms: SupportedPlatforms::ALL,
        private: true,
    },
    welcome_tips_skipped_or_completed: WelcomeTipsCompleted {
        type: bool,
        default: false,
        supported_platforms: SupportedPlatforms::ALL,
        private: true,
    },
    user_default_shell_unsupported_banner_state: UserDefaultShellUnsupportedBannerState {
        type: BannerState,
        default: BannerState::default(),
        supported_platforms: SupportedPlatforms::ALL,
        private: true,
    },
    open_in_warp_banner_dismissed_for_markdown: OpenInWarpBannerDismissedMarkdown {
        type: bool,
        default: false,
        supported_platforms: SupportedPlatforms::ALL,
        private: true,
    },
    open_in_warp_banner_dismissed_for_code_and_text: OpenInWarpBannerDismissedCode {
        type: bool,
        default: false,
        supported_platforms: SupportedPlatforms::ALL,
        private: true,
    },
    // The file path of the tab config used when the default session mode is TabConfig.
    // Only read when mode is TabConfig; ignored for all other modes.
    default_tab_config_path: DefaultTabConfigPath {
        type: String,
        default: String::new(),
        supported_platforms: SupportedPlatforms::ALL,
        private: false,
        toml_path: "general.default_tab_config_path",
    },
    default_session_mode_internal: DefaultSessionMode,
]);

impl GeneralSettings {
    pub fn default_session_mode(&self) -> DefaultSessionMode {
        *self.default_session_mode_internal.value()
    }

    /// Returns the stored default tab config path (only meaningful when the default session
    /// mode is `TabConfig`).
    pub fn default_tab_config_path(&self) -> &str {
        &self.default_tab_config_path
    }

    /// Looks up the `TabConfig` matching the stored `default_tab_config_path`.
    /// Returns `None` if the path is empty or no loaded config matches.
    pub fn resolved_default_tab_config(&self, app: &AppContext) -> Option<TabConfig> {
        let path_str = self.default_tab_config_path.as_str();
        if path_str.is_empty() {
            return None;
        }
        let path = std::path::Path::new(path_str);
        WarpConfig::as_ref(app)
            .tab_configs()
            .iter()
            .find(|config| config.source_path.as_deref().is_some_and(|p| p == path))
            .cloned()
    }
}

#[cfg(test)]
#[path = "general_settings_tests.rs"]
mod tests;
