//! Settings for Blocklist AI.
//!
//! These settings are currently used to configure the underlying model/API used to power the AI
//! UX, as well as small UX configurations.

use std::path::PathBuf;

use ::ai::api_keys::CustomEndpointDefinitions;
pub use cloud_object_models::{
    AgentModeCommandExecutionPredicate, DEFAULT_COMMAND_EXECUTION_ALLOWLIST,
    DEFAULT_COMMAND_EXECUTION_DENYLIST,
};
use serde::{Deserialize, Serialize};
use settings::{
    RespectUserSyncSetting, Setting, SupportedPlatforms, SyncToCloud, define_settings_group,
};
use strum_macros::EnumIter;
use warp_core::execution_mode::AppExecutionMode;
use warp_core::features::FeatureFlag;
use warpui::{AppContext, Entity, ModelContext, SingletonEntity, UpdateModel, WeakViewHandle};

use crate::ai::execution_profiles::ExecutionProfilesConfig;
use crate::auth::AuthStateProvider;
use crate::terminal::TerminalView;
use crate::workspaces::user_workspaces::UserWorkspaces;

pub enum FocusedTerminalInfoEvent {
    TerminalInfoUpdated,
}

/// Singleton model that is used to track the remote sessions in the terminal.
/// Useful for organizations that have restrictions on using AI in sessions in
/// remote sessions.
#[derive(Default, Clone, Debug)]
pub struct FocusedTerminalInfo {
    terminal: Option<WeakViewHandle<TerminalView>>,
    contains_any_remote_blocks: bool,
    contains_any_restored_remote_blocks: bool,
}

impl FocusedTerminalInfo {
    pub fn new(_: &mut ModelContext<Self>) -> Self {
        Self::default()
    }

    pub fn terminal(&self) -> Option<&WeakViewHandle<TerminalView>> {
        self.terminal.as_ref()
    }

    pub fn contains_any_remote_blocks(&self) -> bool {
        self.contains_any_remote_blocks
    }

    pub fn contains_any_restored_remote_blocks(&self) -> bool {
        self.contains_any_restored_remote_blocks
    }

    /// Records what the focused `terminal` contains, in a single atomic operation.
    /// Only emits a TerminalInfoUpdated event if anything changes.
    /// Returns true if the event was emitted.
    ///
    /// The surface is written together with its flags rather than tracked separately so a
    /// reader cannot resolve one terminal's team for another terminal's content.
    pub fn update(
        &mut self,
        terminal: WeakViewHandle<TerminalView>,
        contains_any_remote_blocks: bool,
        contains_any_restored_remote_blocks: bool,
        ctx: &mut ModelContext<Self>,
    ) -> bool {
        let unchanged = self.terminal.as_ref().map(|held| held.id()) == Some(terminal.id())
            && self.contains_any_remote_blocks == contains_any_remote_blocks
            && self.contains_any_restored_remote_blocks == contains_any_restored_remote_blocks;
        if unchanged {
            return false;
        }

        self.terminal = Some(terminal);
        self.contains_any_remote_blocks = contains_any_remote_blocks;
        self.contains_any_restored_remote_blocks = contains_any_restored_remote_blocks;
        ctx.emit(FocusedTerminalInfoEvent::TerminalInfoUpdated);
        true
    }
}

impl Entity for FocusedTerminalInfo {
    type Event = FocusedTerminalInfoEvent;
}

impl SingletonEntity for FocusedTerminalInfo {}

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
    AISettings,
    SupportedPlatforms::ALL,
    SyncToCloud::Globally(RespectUserSyncSetting::Yes),
    surface: settings::SettingSurfaces::GUI,
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

/// Controls how agent thinking/reasoning traces are displayed after streaming.
#[derive(
    Default,
    Debug,
    serde::Serialize,
    serde::Deserialize,
    PartialEq,
    Copy,
    Clone,
    EnumIter,
    schemars::JsonSchema,
    settings_value::SettingsValue,
)]
#[schemars(
    description = "Controls how agent thinking is displayed after streaming.",
    rename_all = "snake_case"
)]
pub enum ThinkingDisplayMode {
    /// Show reasoning blocks while streaming, then collapse them when complete (default).
    #[default]
    ShowAndCollapse,
    /// Always keep reasoning blocks expanded, even after streaming finishes.
    AlwaysShow,
    /// Never show reasoning blocks.
    NeverShow,
}

settings::macros::implement_setting_for_enum!(
    ThinkingDisplayMode,
    AISettings,
    SupportedPlatforms::ALL,
    SyncToCloud::Globally(RespectUserSyncSetting::Yes),
    surface: settings::SettingSurfaces::GUI,
    private: false,
    toml_path: "agents.warp_agent.other.thinking_display_mode",
    description: "Controls how agent thinking traces are displayed after streaming.",
);

impl ThinkingDisplayMode {
    /// Display name for the settings dropdown.
    pub fn display_name(&self) -> &'static str {
        match self {
            ThinkingDisplayMode::ShowAndCollapse => "Show & collapse",
            ThinkingDisplayMode::AlwaysShow => "Always show",
            ThinkingDisplayMode::NeverShow => "Never show",
        }
    }

    pub fn command_palette_description(&self) -> &'static str {
        match self {
            ThinkingDisplayMode::ShowAndCollapse => "Set agent thinking display: show & collapse",
            ThinkingDisplayMode::AlwaysShow => "Set agent thinking display: always show",
            ThinkingDisplayMode::NeverShow => "Set agent thinking display: never show",
        }
    }

    pub fn should_render(&self) -> bool {
        !matches!(self, ThinkingDisplayMode::NeverShow)
    }

    pub fn should_keep_expanded(&self) -> bool {
        matches!(self, ThinkingDisplayMode::AlwaysShow)
    }
}

/// Unit for GUI usage and spend displays.
#[derive(
    Default,
    Debug,
    serde::Serialize,
    serde::Deserialize,
    PartialEq,
    Copy,
    Clone,
    EnumIter,
    schemars::JsonSchema,
    settings_value::SettingsValue,
)]
#[schemars(
    description = "Which unit the GUI's usage/spend displays show: credits or dollars.",
    rename_all = "snake_case"
)]
pub enum UsageDisplayUnit {
    #[default]
    Credits,
    Dollars,
}

settings::macros::implement_setting_for_enum!(
    UsageDisplayUnit,
    AISettings,
    SupportedPlatforms::ALL,
    SyncToCloud::Globally(RespectUserSyncSetting::Yes),
    surface: settings::SettingSurfaces::GUI,
    private: false,
    toml_path: "agents.warp_agent.other.usage_display_unit",
    description: "Which unit the GUI's usage/spend displays show: credits or dollars.",
    feature_flag: FeatureFlag::PricingTransparency,
);

impl UsageDisplayUnit {
    pub fn display_name(&self) -> &'static str {
        match self {
            UsageDisplayUnit::Credits => "Credits",
            UsageDisplayUnit::Dollars => "Dollars",
        }
    }
}

/// Controls what happens when a user submits a new prompt while the agent is
/// still responding to an earlier prompt.
///
/// This is the *default* used when a conversation has no explicit auto-queue
/// override.
#[derive(
    Default,
    Debug,
    serde::Serialize,
    serde::Deserialize,
    PartialEq,
    Copy,
    Clone,
    EnumIter,
    schemars::JsonSchema,
    settings_value::SettingsValue,
)]
#[schemars(
    description = "Default behavior when submitting a new prompt while the agent is still responding.",
    rename_all = "snake_case"
)]
pub enum PromptSubmissionMode {
    /// Cancel the in-flight response and submit the new prompt immediately
    /// (default).
    #[default]
    Interrupt,
    /// Hold the new prompt until the in-flight response finishes, then submit.
    Queue,
}

settings::macros::implement_setting_for_enum!(
    PromptSubmissionMode,
    AISettings,
    SupportedPlatforms::ALL,
    SyncToCloud::Globally(RespectUserSyncSetting::Yes),
    surface: settings::SettingSurfaces::GUI,
    private: false,
    toml_path: "agents.warp_agent.other.default_prompt_submission_mode",
    description: "Default behavior when submitting a new prompt while the agent is still responding.",
    feature_flag: FeatureFlag::QueueSlashCommand,
);

impl PromptSubmissionMode {
    /// Display name for the settings dropdown.
    pub fn display_name(&self) -> &'static str {
        match self {
            PromptSubmissionMode::Interrupt => "Interrupt response",
            PromptSubmissionMode::Queue => "Queue until response finishes",
        }
    }

    pub fn command_palette_description(&self) -> &'static str {
        match self {
            PromptSubmissionMode::Interrupt => "Set default prompt submission: interrupt response",
            PromptSubmissionMode::Queue => {
                "Set default prompt submission: queue until response finishes"
            }
        }
    }
}

/// What happens when a prompt is submitted while an agent controls an agent-requested
/// long-running command (LRC).
///
/// Only consulted when [`PromptSubmissionMode`] is `Interrupt`: in `Queue` mode
/// prompts always queue until the full response finishes, so this setting is
/// hidden and ignored.
#[derive(
    Default,
    Debug,
    serde::Serialize,
    serde::Deserialize,
    PartialEq,
    Copy,
    Clone,
    EnumIter,
    schemars::JsonSchema,
    settings_value::SettingsValue,
)]
#[schemars(
    description = "What happens when a prompt is submitted while an agent controls an agent-requested long-running command.",
    rename_all = "snake_case"
)]
pub enum LongRunningCommandSubmissionMode {
    /// Send the prompt to the agent immediately, steering it mid-command.
    SendImmediately,
    /// Queue the prompt and send it to the agent when the command finishes
    /// (default).
    #[default]
    QueueUntilCommandCompletes,
}

settings::macros::implement_setting_for_enum!(
    LongRunningCommandSubmissionMode,
    AISettings,
    SupportedPlatforms::ALL,
    SyncToCloud::Globally(RespectUserSyncSetting::Yes),
    surface: settings::SettingSurfaces::GUI,
    private: false,
    toml_path: "agents.warp_agent.other.long_running_command_submission_mode",
    description: "What happens when a prompt is submitted while an agent controls an agent-requested long-running command.",
    feature_flag: FeatureFlag::QueueSlashCommand,
);

impl LongRunningCommandSubmissionMode {
    /// Display name for the settings dropdown.
    pub fn display_name(&self) -> &'static str {
        match self {
            LongRunningCommandSubmissionMode::SendImmediately => "Send immediately",
            LongRunningCommandSubmissionMode::QueueUntilCommandCompletes => {
                "Queue until command finishes"
            }
        }
    }

    pub fn command_palette_description(&self) -> &'static str {
        match self {
            LongRunningCommandSubmissionMode::SendImmediately => {
                "Set long-running command submission: send immediately"
            }
            LongRunningCommandSubmissionMode::QueueUntilCommandCompletes => {
                "Set long-running command submission: queue until command finishes"
            }
        }
    }
}

#[derive(
    Debug,
    Serialize,
    Deserialize,
    Clone,
    Copy,
    Default,
    PartialEq,
    EnumIter,
    schemars::JsonSchema,
    settings_value::SettingsValue,
)]
#[schemars(
    description = "File read permission level for the agent.",
    rename_all = "snake_case"
)]
pub enum AgentModeCodingPermissionsType {
    /// Agent Mode must ask for explicit permission for any type of file read.
    #[default]
    AlwaysAskBeforeReading,
    /// Agent Mode can always read files without explicit consent.
    AlwaysAllowReading,
    /// Agent Mode can only read certain files without explicit consent.
    ///
    /// The specific filepaths are backed by the
    /// [`AISettings::agent_mode_coding_file_read_allowlist`] setting.
    AllowReadingSpecificFiles,
}

define_settings_group!(AISettings, settings: [
    // If `false`, all AI features are disabled.
    is_any_ai_enabled: IsAnyAIEnabled {
        type: bool,
        default: true,
        supported_platforms: SupportedPlatforms::ALL,
        sync_to_cloud: SyncToCloud::Globally(RespectUserSyncSetting::No),
        surface: settings::SettingSurfaces::GUI,
        private: false,
        toml_path: "agents.warp_agent.is_any_ai_enabled",
        description: "Controls whether all AI features are enabled.",
    },
    // This field should not be referenced directly to lookup active AI enablement -- use the
    // `is_active_ai_enabled()` getter.
    is_active_ai_enabled_internal: IsActiveAIEnabled {
        type: bool,
        default: true,
        supported_platforms: SupportedPlatforms::ALL,
        sync_to_cloud: SyncToCloud::Globally(RespectUserSyncSetting::No),
        surface: settings::SettingSurfaces::GUI,
        private: false,
        toml_path: "agents.warp_agent.active_ai.enabled",
        description: "Controls whether proactive AI features like suggestions are enabled.",
    },
    // Predicates that Agent Mode can use to decide if it can execute
    // a command without explicit user consent.
    //
    // Prefer [`BlocklistAIPermissions::can_autoexecute_command`] to
    // interpret this allowlist.
    agent_mode_command_execution_allowlist: AgentModeCommandExecutionAllowlist {
        type: Vec<AgentModeCommandExecutionPredicate>,
        default: DEFAULT_COMMAND_EXECUTION_ALLOWLIST.clone(),
        supported_platforms: SupportedPlatforms::ALL,
        sync_to_cloud: SyncToCloud::Globally(RespectUserSyncSetting::Yes),
        surface: settings::SettingSurfaces::ALL,
        private: false,
        toml_path: "agents.profiles.agent_mode_command_execution_allowlist",
        description: "Commands that the agent can execute without explicit permission.",
    },
    // Predicates that Agent Mode can use to decide if a command must
    // be executed by the user.
    //
    // Prefer [`BlocklistAIPermissions::can_autoexecute_command`] to
    // interpret this denylist.
    agent_mode_command_execution_denylist: AgentModeCommandExecutionDenylist {
        type: Vec<AgentModeCommandExecutionPredicate>,
        default: DEFAULT_COMMAND_EXECUTION_DENYLIST.clone(),
        supported_platforms: SupportedPlatforms::ALL,
        sync_to_cloud: SyncToCloud::Globally(RespectUserSyncSetting::Yes),
        surface: settings::SettingSurfaces::ALL,
        private: false,
        toml_path: "agents.profiles.agent_mode_command_execution_denylist",
        description: "Commands that the agent must always ask before executing.",
    },
    // Enabled iff Agent Mode can execute readonly commands without explicit user consent.
    //
    // Prefer [`BlocklistAIPermissions::can_autoexecute_command`] to
    // interpret this setting.
    agent_mode_execute_read_only_commands: AgentModeExecuteReadonlyCommands {
        type: bool,
        default: false,
        supported_platforms: SupportedPlatforms::ALL,
        sync_to_cloud: SyncToCloud::Globally(RespectUserSyncSetting::Yes),
        surface: settings::SettingSurfaces::ALL,
        private: false,
        toml_path: "agents.profiles.agent_mode_execute_readonly_commands",
        description: "Whether the agent can auto-execute read-only commands without asking.",
    },
    // Determines coding permissions that Agent Mode has.
    // Note that if Agent Mode has permissions to execute readonly commands,
    // that automatically gives Agent Mode the ability to also _read_ files for coding
    // tasks, including codebase search.
    //
    // Prefer [`BlocklistAIPermissions::can_read_file`] to interpret this setting.
    agent_mode_coding_permissions: AgentModeCodingPermissions {
        type: AgentModeCodingPermissionsType,
        default: AgentModeCodingPermissionsType::default(),
        supported_platforms: SupportedPlatforms::ALL,
        sync_to_cloud: SyncToCloud::Globally(RespectUserSyncSetting::Yes),
        surface: settings::SettingSurfaces::ALL,
        private: false,
        toml_path: "agents.profiles.agent_mode_coding_permissions",
        description: "The file read permission level for the agent.",
    }
    // Specific filepaths that Agent Mode can read without asking for additional permissions.
    // These should be persisted as absolute filepaths to avoid ambiguity.
    //
    // This is used in conjunction with [`AgentModeCodingPermissionsType::AllowReadingSpecificFiles`]
    // but modelled as a separate setting because it is not cloud-synced.
    //
    // Prefer [`BlocklistAIPermissions::can_read_file`] to interpret this setting.
    agent_mode_coding_file_read_allowlist: AgentModeCodingFileReadAllowlist {
        type: Vec<PathBuf>,
        default: vec![],
        supported_platforms: SupportedPlatforms::ALL,
        sync_to_cloud: SyncToCloud::Never,
        surface: settings::SettingSurfaces::ALL,
        private: false,
        toml_path: "agents.profiles.agent_mode_coding_file_read_allowlist",
        description: "File paths the agent can read without asking for permission.",
    }
    // The complete execution-profile collection.
    execution_profiles: ExecutionProfiles {
        type: ExecutionProfilesConfig,
        default: ExecutionProfilesConfig::default(),
        supported_platforms: SupportedPlatforms::ALL,
        sync_to_cloud: SyncToCloud::Globally(RespectUserSyncSetting::Yes),
        surface: settings::SettingSurfaces::ALL,
        private: false,
        toml_path: "agents.execution_profiles",
        max_table_depth: 2,
        description: "AI execution profiles and their permissions.",
    }
    // Non-secret custom inference endpoint definitions. Credentials remain in
    // secure storage.
    custom_endpoints: CustomEndpoints {
        type: CustomEndpointDefinitions,
        default: CustomEndpointDefinitions::default(),
        supported_platforms: SupportedPlatforms::ALL,
        sync_to_cloud: SyncToCloud::Globally(RespectUserSyncSetting::Yes),
        surface: settings::SettingSurfaces::ALL,
        private: false,
        toml_path: "agents.custom_endpoints",
        max_table_depth: 2,
        description: "Custom inference endpoint definitions.",
    }
    usage_display_unit: UsageDisplayUnit,
    // Whether or not the profile-level command autoexecution speedbump has been shown.
    //
    // Not a user-visible setting - we model it as a setting so we can track how often
    // it's shown across devices.
    has_shown_agent_mode_profile_command_autoexecution_speedbump: HasShownAgentModeProfileCommandAutoexecutionSpeedbump {
        type: bool,
        default: false,
        supported_platforms: SupportedPlatforms::ALL,
        sync_to_cloud: SyncToCloud::Globally(RespectUserSyncSetting::Yes),
        surface: settings::SettingSurfaces::GUI,
        private: true,
    }
    // Whether or not we should show the speedbump for auto-executing readonly cmds.
    //
    // Not a user-visible settings - we model it as a setting so we can track how often
    // it's shown across devices.
    should_show_agent_mode_autoexecute_readonly_commands_speedbump: ShouldShowAgentModeModelExecuteReadonlyCommandsSpeedbump {
        type: bool,
        default: true,
        supported_platforms: SupportedPlatforms::ALL,
        sync_to_cloud: SyncToCloud::Globally(RespectUserSyncSetting::Yes),
        surface: settings::SettingSurfaces::GUI,
        private: true,
    }
    // Whether or not we should show the speedbump for auto-writing to the PTY.
    //
    // Not a user-visible settings - we model it as a setting so we can track how often
    // it's shown across devices.
    should_show_agent_mode_write_to_pty_speedbump: ShouldShowAgentModeWriteToPtySpeedbump {
        type: bool,
        default: true,
        supported_platforms: SupportedPlatforms::ALL,
        sync_to_cloud: SyncToCloud::Globally(RespectUserSyncSetting::Yes),
        surface: settings::SettingSurfaces::GUI,
        private: true,
    }
    // Whether or not we should show the speedbump for auto-reading files.
    //
    // Not a user-visible settings - we model it as a setting so we can track how often
    // it's shown across devices.
    should_show_agent_mode_autoread_files_speedbump: ShouldShowAgentModeCodingReadPermissionsNudge {
        type: bool,
        default: true,
        supported_platforms: SupportedPlatforms::ALL,
        sync_to_cloud: SyncToCloud::Globally(RespectUserSyncSetting::Yes),
        surface: settings::SettingSurfaces::GUI,
        private: true,
    }
    // Whether or not we should show the one-shot speedbump on Ask-User-Question cards.
    //
    // Not a user-visible setting - we model it as a setting so we can track state.
    // Intentionally NOT cloud-synced: we want users to see the first-time nudge on
    // each fresh device, and we avoid a cloud-sync race that would make the flag
    // silently stay `false` on new devices after being consumed once elsewhere.
    should_show_agent_mode_ask_user_question_speedbump: ShouldShowAgentModeAskUserQuestionSpeedbump {
        type: bool,
        default: true,
        supported_platforms: SupportedPlatforms::ALL,
        sync_to_cloud: SyncToCloud::Never,
        surface: settings::SettingSurfaces::GUI,
        private: true,
    }
    // Whether to use locally loaded AWS credentials for Bedrock-enabled requests.
    aws_bedrock_credentials_enabled: AwsBedrockCredentialsEnabled {
        type: bool,
        default: false,
        supported_platforms: SupportedPlatforms::DESKTOP,
        sync_to_cloud: SyncToCloud::Globally(RespectUserSyncSetting::Yes),
        surface: settings::SettingSurfaces::GUI,
        private: false,
        toml_path: "cloud_platform.third_party_api_keys.aws_bedrock_credentials_enabled",
        description: "Whether Warp should use your local AWS credentials for Bedrock-enabled requests.",
    }
    // Whether to automatically run the AWS login command when Bedrock credentials are expired.
    //
    // When true, the configured login command will be run automatically without asking.
    // When false (default), a prompt will be shown asking for permission.
    aws_bedrock_auto_login: AwsBedrockAutoLogin {
        type: bool,
        default: false,
        supported_platforms: SupportedPlatforms::DESKTOP,
        sync_to_cloud: SyncToCloud::Globally(RespectUserSyncSetting::Yes),
        surface: settings::SettingSurfaces::GUI,
        private: false,
        toml_path: "cloud_platform.third_party_api_keys.aws_bedrock_auto_login",
        description: "Whether to automatically run the AWS login command when Bedrock credentials expire.",
    }
    // Command to run to refresh AWS credentials when using Bedrock auto-login.
    aws_bedrock_auth_refresh_command: AwsBedrockAuthRefreshCommand {
        type: String,
        default: "aws login".to_string(),
        supported_platforms: SupportedPlatforms::DESKTOP,
        sync_to_cloud: SyncToCloud::Globally(RespectUserSyncSetting::Yes),
        surface: settings::SettingSurfaces::GUI,
        private: false,
        toml_path: "cloud_platform.third_party_api_keys.aws_bedrock_auth_refresh_command",
        description: "The command to run to refresh AWS credentials for Bedrock.",
    }
    // AWS profile name to use when loading credentials from the local AWS credential/config chain.
    aws_bedrock_profile: AwsBedrockProfile {
        type: String,
        default: "default".to_string(),
        supported_platforms: SupportedPlatforms::DESKTOP,
        sync_to_cloud: SyncToCloud::Globally(RespectUserSyncSetting::Yes),
        surface: settings::SettingSurfaces::GUI,
        private: false,
        toml_path: "cloud_platform.third_party_api_keys.aws_bedrock_profile",
        description: "The AWS profile name to use for Bedrock credentials.",
    }
    // Whether the AWS Bedrock login banner has been permanently dismissed.
    //
    // Not a user-visible setting - we model it as a setting so we can track state.
    aws_bedrock_login_banner_dismissed: AwsBedrockLoginBannerDismissed {
        type: bool,
        default: false,
        supported_platforms: SupportedPlatforms::DESKTOP,
        sync_to_cloud: SyncToCloud::Globally(RespectUserSyncSetting::Yes),
        surface: settings::SettingSurfaces::GUI,
        private: true,
    }
    // Whether to mint and attach Gemini Enterprise (GEAP) credentials to eligible agent
    // requests, routing them through the workspace's Google Cloud project. Only consulted
    // when the admin sets the GEAP host to RESPECT_USER_SETTING; ENFORCE bypasses it.
    // Prefer [`UserWorkspaces::is_gemini_enterprise_credentials_enabled`] to interpret
    // this setting.
    gemini_enterprise_credentials_enabled: GeminiEnterpriseCredentialsEnabled {
        type: bool,
        default: false,
        supported_platforms: SupportedPlatforms::DESKTOP,
        sync_to_cloud: SyncToCloud::Globally(RespectUserSyncSetting::Yes),
        surface: settings::SettingSurfaces::GUI,
        private: false,
        toml_path: "cloud_platform.third_party_api_keys.gemini_enterprise_credentials_enabled",
        description: "Whether Warp should route eligible requests through your workspace's Gemini Enterprise Google Cloud project.",
    }

    should_render_use_agent_footer_for_user_commands: ShouldRenderUseAgentToolbarForUserCommands {
        type: bool,
        default: true,
        supported_platforms: SupportedPlatforms::ALL,
        sync_to_cloud: SyncToCloud::Globally(RespectUserSyncSetting::Yes),
        surface: settings::SettingSurfaces::GUI,
        private: false,
        toml_path: "agents.warp_agent.other.should_render_use_agent_toolbar_for_user_commands",
        description: "Whether to show the \"Use Agent\" footer for terminal commands.",
    }

    // Whether the ambient agent trial widget has been dismissed by the user.
    //
    // Not a user-visible setting - we model it as a setting so we can track state.
    ambient_agent_trial_widget_dismissed: AmbientAgentTrialWidgetDismissed {
        type: bool,
        default: false,
        supported_platforms: SupportedPlatforms::ALL,
        sync_to_cloud: SyncToCloud::Globally(RespectUserSyncSetting::Yes),
        surface: settings::SettingSurfaces::GUI,
        private: true,
    }

    default_session_mode_internal: DefaultSessionMode,

    // Controls how agent thinking/reasoning traces are displayed.
    thinking_display_mode: ThinkingDisplayMode,

    // Default behavior when the user submits a new prompt while the agent is still
    // responding.
    default_prompt_submission_mode: PromptSubmissionMode,

    // What happens when a prompt is submitted while an agent controls an agent-requested
    // long-running command. Only consulted when `default_prompt_submission_mode` is `Interrupt`.
    long_running_command_submission_mode: LongRunningCommandSubmissionMode,

    // Whether agent-executed shell commands should be included in command history
    // (up-arrow, Ctrl-R search, inline history menu).
    // When false, commands run by the AI agent are excluded from history.
    include_agent_commands_in_history: IncludeAgentCommandsInHistory {
        type: bool,
        default: false,
        supported_platforms: SupportedPlatforms::ALL,
        sync_to_cloud: SyncToCloud::Globally(RespectUserSyncSetting::Yes),
        surface: settings::SettingSurfaces::GUI,
        private: false,
        toml_path: "agents.warp_agent.input.include_agent_commands_in_history",
        description: "Whether agent-executed commands are included in command history.",
    }

    // Whether fast forward / auto-approve can run commands that match the command denylist.
    auto_approve_bypasses_command_denylist: AutoApproveBypassesCommandDenylist {
        type: bool,
        default: true,
        supported_platforms: SupportedPlatforms::ALL,
        sync_to_cloud: SyncToCloud::Globally(RespectUserSyncSetting::Yes),
        surface: settings::SettingSurfaces::ALL,
        private: false,
        toml_path: "agents.warp_agent.other.auto_approve_bypasses_command_denylist",
        description: "Whether auto-approve bypasses the command denylist.",
    }


    // Whether Oz should add attribution (co-author line) to commit messages and PRs.
    // This is the user-level preference; it may be overridden by the window's team's
    // `enable_warp_attribution` AdminEnablementSetting (see
    // `UserWorkspaces::get_agent_attribution_setting`).
    agent_attribution_enabled: AgentAttributionEnabled {
        type: bool,
        default: true,
        supported_platforms: SupportedPlatforms::ALL,
        sync_to_cloud: SyncToCloud::Globally(RespectUserSyncSetting::No),
        surface: settings::SettingSurfaces::GUI,
        private: false,
        toml_path: "agents.warp_agent.other.agent_attribution_enabled",
        description: "Whether the Warp Agent adds an attribution co-author line to commit messages and pull requests it creates.",
    }
]);

impl AISettings {
    pub fn register_and_subscribe_to_events(app: &mut AppContext) {
        Self::register(app);
        app.add_singleton_model(FocusedTerminalInfo::new);

        app.update_model(&Self::handle(app), |_me, ctx| {
            ctx.subscribe_to_model(&FocusedTerminalInfo::handle(ctx), |_me, _, event, ctx| {
                if matches!(event, FocusedTerminalInfoEvent::TerminalInfoUpdated) {
                    // Pipe the event so that any view that listens for settings changes will be notified.
                    ctx.emit(AISettingsChangedEvent::IsAnyAIEnabled {
                        change_event_reason: ChangeEventReason::LocalChange,
                    });
                }
            });
        });
    }

    pub fn is_ai_disabled_due_to_remote_session_org_policy(&self, app: &AppContext) -> bool {
        let focused_terminal = FocusedTerminalInfo::as_ref(app);
        let Some(terminal) = focused_terminal.terminal() else {
            return false;
        };
        if !focused_terminal.contains_any_remote_blocks()
            && !focused_terminal.contains_any_restored_remote_blocks()
        {
            return false;
        }

        let user_workspaces = UserWorkspaces::as_ref(app);
        let scope = user_workspaces.team_context(terminal, app);
        !user_workspaces.is_ai_allowed_in_remote_sessions(&scope)
    }

    pub fn is_any_ai_enabled(&self, app: &AppContext) -> bool {
        // Disable AI for anonymous and logged-out users.
        let is_anonymous_or_logged_out = AuthStateProvider::as_ref(app)
            .get()
            .is_anonymous_or_logged_out();

        *self.is_any_ai_enabled
            && !is_anonymous_or_logged_out
            && !self.is_ai_disabled_due_to_remote_session_org_policy(app)
    }

    pub fn default_session_mode(&self) -> DefaultSessionMode {
        *self.default_session_mode_internal.value()
    }

    pub fn is_active_ai_enabled(&self, app: &warpui::AppContext) -> bool {
        self.is_any_ai_enabled(app)
            && *self.is_active_ai_enabled_internal
            && AppExecutionMode::as_ref(app).allows_active_ai()
    }

    pub fn is_command_denylist_editable(&self, app: &AppContext) -> bool {
        self.is_any_ai_enabled(app)
    }

    pub fn is_ask_user_question_permissions_editable(&self, app: &AppContext) -> bool {
        self.is_any_ai_enabled(app)
    }
}

#[cfg(test)]
#[path = "ai_tests.rs"]
mod tests;
