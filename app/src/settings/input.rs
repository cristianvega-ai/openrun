use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use settings::Setting as _;
/// TODO: move alias_expansion setting into this group.
use settings::{SupportedPlatforms, define_settings_group};
use warpui::{AppContext, SingletonEntity};

use crate::terminal::input::inline_menu::InlineMenuType;
use crate::terminal::session_settings::SessionSettings;

pub const MAX_TIMES_TO_SHOW_AUTOSUGGESTION_HINT: i8 = 2;

/// Per-menu content heights set by drag-to-resize.
///
/// Reading skips entries whose key is not a known [`InlineMenuType`] (for
/// example a menu that no longer exists) or whose height is not a number, so a
/// stale entry does not discard the rest of the stored heights.
#[derive(Debug, Clone, Default, PartialEq, Serialize, schemars::JsonSchema)]
#[serde(transparent)]
pub struct InlineMenuHeights(pub HashMap<InlineMenuType, f32>);

impl<'de> Deserialize<'de> for InlineMenuHeights {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let raw = HashMap::<String, serde_json::Value>::deserialize(deserializer)?;
        let heights = raw
            .into_iter()
            .filter_map(|(key, height)| {
                let menu_type = serde_json::from_value(serde_json::Value::String(key)).ok()?;
                Some((menu_type, height.as_f64()? as f32))
            })
            .collect();
        Ok(Self(heights))
    }
}

impl settings_value::SettingsValue for InlineMenuHeights {
    fn to_file_value(&self) -> serde_json::Value {
        self.0.to_file_value()
    }

    fn from_file_value(value: &serde_json::Value) -> Option<Self> {
        let heights = value
            .as_object()?
            .iter()
            .filter_map(|(key, height)| {
                let menu_type =
                    InlineMenuType::from_file_value(&serde_json::Value::String(key.clone()))?;
                Some((menu_type, f32::from_file_value(height)?))
            })
            .collect();
        Some(Self(heights))
    }
}

define_settings_group!(InputSettings,
    settings: [
        show_hint_text: ShowHintText {
            type: bool,
            default: true,
            supported_platforms: SupportedPlatforms::ALL,
            surface: settings::SettingSurfaces::GUI,
            private: false,
            toml_path: "terminal.input.show_hint_text",
            description: "Whether hint text is shown in the terminal input.",
        },
        completions_open_while_typing: CompletionsOpenWhileTyping {
            type: bool,
            default: false,
            supported_platforms: SupportedPlatforms::ALL,
            surface: settings::SettingSurfaces::GUI,
            private: false,
            toml_path: "terminal.input.completions_open_while_typing",
            description: "Whether the completions menu opens automatically while typing.",
        },
        warp_completions_enabled: WarpCompletionsEnabled {
            type: bool,
            default: true,
            supported_platforms: SupportedPlatforms::ALL,
            surface: settings::SettingSurfaces::GUI,
            private: false,
            toml_path: "terminal.input.warp_completions_enabled",
            description: "Whether Warp's built-in completions are shown for shell commands.",
        },
        native_shell_completions_enabled: NativeShellCompletionsEnabled {
            type: bool,
            default: true,
            supported_platforms: SupportedPlatforms::ALL,
            surface: settings::SettingSurfaces::GUI,
            private: false,
            toml_path: "terminal.input.native_shell_completions_enabled",
            description: "Whether your shell's own completions are used for shell commands.",
        },
        error_underlining: ErrorUnderliningEnabled {
            type: bool,
            default: true,
            supported_platforms: SupportedPlatforms::DESKTOP,
            surface: settings::SettingSurfaces::GUI,
            private: false,
            toml_path: "terminal.input.error_underlining_enabled",
            description: "Whether command errors are underlined in the input.",
        },
        syntax_highlighting: SyntaxHighlighting {
            type: bool,
            default: true,
            supported_platforms: SupportedPlatforms::DESKTOP,
            surface: settings::SettingSurfaces::GUI,
            private: false,
            toml_path: "terminal.input.syntax_highlighting",
            description: "Whether syntax highlighting is enabled in the terminal input.",
        },
        command_corrections: CommandCorrections {
            type: bool,
            default: true,
            supported_platforms: SupportedPlatforms::ALL,
            surface: settings::SettingSurfaces::GUI,
            private: false,
            toml_path: "terminal.input.command_corrections",
            description: "Whether command corrections are suggested for mistyped commands.",
        },
        workflows_box_expanded: WorkflowsBoxExpanded {
            type: bool,
            default: true,
            supported_platforms: SupportedPlatforms::ALL,
            surface: settings::SettingSurfaces::GUI,
            private: true,
            storage_key: "WorkflowsBoxOpen",
        },
        autosuggestion_accepted_count: AutosuggestionAcceptedCount {
            type: i8,
            default: 0,
            supported_platforms: SupportedPlatforms::ALL,
            surface: settings::SettingSurfaces::GUI,
            private: true,
        },
        at_context_menu_in_terminal_mode: AtContextMenuInTerminalMode {
            type: bool,
            default: true,
            supported_platforms: SupportedPlatforms::ALL,
            surface: settings::SettingSurfaces::GUI,
            private: false,
            toml_path: "terminal.input.at_context_menu_in_terminal_mode",
            description: "Whether the @ context menu is available in terminal mode.",
        },
        enable_slash_commands_in_terminal: EnableSlashCommandsInTerminal {
            type: bool,
            default: true,
            supported_platforms: SupportedPlatforms::ALL,
            surface: settings::SettingSurfaces::GUI,
            private: false,
            toml_path: "terminal.input.enable_slash_commands_in_terminal",
            description: "Whether slash commands are available in the terminal input.",
        },
        outline_codebase_symbols_for_at_context_menu: OutlineCodebaseSymbolsForAtContextMenu {
            type: bool,
            default: true,
            supported_platforms: SupportedPlatforms::ALL,
            surface: settings::SettingSurfaces::GUI,
            private: false,
            toml_path: "terminal.input.outline_codebase_symbols_for_at_context_menu",
            description: "Whether codebase symbols appear in the @ context menu.",
        },
        completions_menu_width: CompletionsMenuWidth {
            type: f32,
            default: 330.,
            supported_platforms: SupportedPlatforms::ALL,
            surface: settings::SettingSurfaces::GUI,
            private: true,
        },
        completions_menu_height: CompletionsMenuHeight {
            type: f32,
            default: 185.,
            supported_platforms: SupportedPlatforms::ALL,
            surface: settings::SettingSurfaces::GUI,
            private: true,
        },
        // Per-menu custom content heights set by drag-to-resize. Not user-visible.
        inline_menu_custom_content_heights: InlineMenuCustomContentHeights {
            type: InlineMenuHeights,
            default: InlineMenuHeights::default(),
            supported_platforms: SupportedPlatforms::ALL,
            surface: settings::SettingSurfaces::GUI,
            private: true,
        },
    ]
);

impl InputSettings {
    /// Whether the Warp prompt is used, as opposed to the shell's own PS1.
    pub fn is_warp_prompt_enabled(&self, app: &AppContext) -> bool {
        !*SessionSettings::as_ref(app).honor_ps1.value()
    }
}

#[cfg(test)]
#[path = "input_tests.rs"]
mod tests;
