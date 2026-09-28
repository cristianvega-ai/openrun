use std::ops::Deref;

use serde::{Deserialize, Deserializer, Serialize};
use serde_json::Value;
use settings_value::SettingsValue;
use warpui::SingletonEntity;

use crate::chip_configurator::ConfigurableToolbarItem;
use crate::context_chips::{ContextChipKind, available_chips};
use crate::settings::CodeSettings;
use crate::terminal::shared_session::SharedSessionStatus;
use crate::ui_components::icons::Icon;

/// A configurable item in the CLI agent footer.
///
/// This unifies context-chip data displays with interactive control buttons so
/// they can all be arranged through the same drag-and-drop editor.
#[derive(
    Clone,
    Debug,
    Eq,
    PartialEq,
    Hash,
    Serialize,
    Deserialize,
    schemars::JsonSchema,
    settings_value::SettingsValue,
)]
#[schemars(
    description = "An item that can appear in the CLI agent toolbar.",
    rename_all = "snake_case"
)]
pub enum CLIAgentToolbarItemKind {
    #[schemars(description = "A prompt context chip.")]
    ContextChip(ContextChipKind),
    RichInput,
    FileExplorer,
    VoiceInput,
    // Renamed from ImageAttach; alias preserves existing user toolbar configs.
    #[serde(alias = "ImageAttach")]
    FileAttach,
    // Opens settings to the Coding Agents section.
    Settings,
}

impl CLIAgentToolbarItemKind {
    /// Whether this item should be visible to session viewers.
    /// Items that control host settings or initiate actions on the host's
    /// behalf are hidden from viewers.
    pub fn available_to_session_viewer(&self, status: &SharedSessionStatus) -> bool {
        match self {
            Self::Settings | Self::FileAttach | Self::FileExplorer => !status.is_viewer(),
            Self::ContextChip(_) | Self::RichInput | Self::VoiceInput => true,
        }
    }

    pub fn display_label(&self) -> &'static str {
        match self {
            Self::ContextChip(_) => "Context Chip",
            Self::VoiceInput => "Voice Input",
            Self::FileAttach => "Attach File",
            Self::FileExplorer => "File Explorer",
            Self::RichInput => "Rich Input",
            Self::Settings => "Settings",
        }
    }

    pub fn icon(&self) -> Option<Icon> {
        match self {
            Self::ContextChip(kind) => kind.udi_icon(),
            Self::VoiceInput => Some(Icon::Microphone),
            Self::FileAttach => Some(Icon::Plus),
            Self::FileExplorer => Some(Icon::FileCopy),
            Self::RichInput => Some(Icon::TextInput),
            Self::Settings => Some(Icon::Settings),
        }
    }

    /// Whether this item should be included in the toolbar given the current app state.
    pub fn is_available(&self, app: &warpui::AppContext) -> bool {
        match self {
            // Matches the gating on every other project explorer entry point, so the chip
            // cannot open a tool view the rest of the app hides. See
            // `Workspace::compute_left_panel_views` and the `SHOW_PROJECT_EXPLORER`
            // keybinding predicate.
            Self::FileExplorer => {
                cfg!(feature = "local_fs") && *CodeSettings::as_ref(app).show_project_explorer
            }
            _ => true,
        }
    }

    pub fn context_chip_kind(&self) -> Option<&ContextChipKind> {
        match self {
            Self::ContextChip(kind) => Some(kind),
            _ => None,
        }
    }

    pub fn default_left() -> Vec<Self> {
        vec![
            Self::FileAttach,
            Self::VoiceInput,
            Self::ContextChip(ContextChipKind::GitDiffStats),
            Self::FileExplorer,
            Self::RichInput,
        ]
    }

    pub fn default_right() -> Vec<Self> {
        vec![
            Self::ContextChip(ContextChipKind::WorkingDirectory),
            Self::ContextChip(ContextChipKind::ShellGitBranch),
            Self::Settings,
        ]
    }

    /// All items available for the footer configurator.
    pub fn all_available() -> Vec<Self> {
        let mut items: Vec<Self> = available_chips()
            .into_iter()
            .map(Self::ContextChip)
            .collect();
        items.extend([
            Self::FileExplorer,
            Self::RichInput,
            Self::FileAttach,
            Self::VoiceInput,
            Self::Settings,
        ]);
        items
    }
}

impl From<ContextChipKind> for CLIAgentToolbarItemKind {
    fn from(kind: ContextChipKind) -> Self {
        Self::ContextChip(kind)
    }
}

impl ConfigurableToolbarItem for CLIAgentToolbarItemKind {
    fn from_context_chip(kind: ContextChipKind) -> Self {
        Self::ContextChip(kind)
    }

    fn context_chip_kind(&self) -> Option<&ContextChipKind> {
        CLIAgentToolbarItemKind::context_chip_kind(self)
    }

    fn display_label(&self) -> &'static str {
        CLIAgentToolbarItemKind::display_label(self)
    }

    fn icon(&self) -> Option<Icon> {
        CLIAgentToolbarItemKind::icon(self)
    }
}

/// One zone of a saved CLI agent toolbar layout.
///
/// Entries that are no longer valid items (removed variants, unknown names)
/// are skipped instead of invalidating the whole saved layout.
#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, schemars::JsonSchema)]
#[serde(transparent)]
pub struct CLIAgentToolbarItems(Vec<CLIAgentToolbarItemKind>);

impl From<Vec<CLIAgentToolbarItemKind>> for CLIAgentToolbarItems {
    fn from(items: Vec<CLIAgentToolbarItemKind>) -> Self {
        Self(items)
    }
}

impl Deref for CLIAgentToolbarItems {
    type Target = [CLIAgentToolbarItemKind];

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl<'de> Deserialize<'de> for CLIAgentToolbarItems {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let entries = Vec::<Value>::deserialize(deserializer)?;
        Ok(Self(
            entries
                .into_iter()
                .filter_map(|entry| serde_json::from_value(entry).ok())
                .collect(),
        ))
    }
}

impl SettingsValue for CLIAgentToolbarItems {
    fn to_file_value(&self) -> Value {
        self.0.to_file_value()
    }

    fn from_file_value(value: &Value) -> Option<Self> {
        Some(Self(
            value
                .as_array()?
                .iter()
                .filter_map(CLIAgentToolbarItemKind::from_file_value)
                .collect(),
        ))
    }
}

#[cfg(test)]
#[path = "toolbar_item_tests.rs"]
mod tests;
