pub mod bindings;
pub mod commands;

use bitflags::bitflags;
pub use commands::SlashCommandId;

bitflags! {
    /// Specifies the requirements for a slash command to be available.
    ///
    /// Each flag represents a requirement that the session context must satisfy. The command is
    /// available when the session supports *all* of the command's requirement flags.
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub struct Availability: u8 {
        /// No requirements — always available.
        const ALWAYS = 0;
        /// Requires a local session (not available in remote sessions).
        const LOCAL = 1 << 0;
        /// Requires a git repository.
        const REPOSITORY = 1 << 1;
    }
}

/// Stable identity for a static slash command.
///
/// Front-ends dispatch on this value instead of matching command-name strings.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SlashCommandKind {
    Edit,
    RenameTab,
    SetTabColor,
    OpenCodeReview,
    OpenSettingsFile,
    OpenRepo,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Argument {
    pub hint_text: Option<&'static str>,
    pub is_optional: bool,
}

impl Argument {
    pub(super) fn optional() -> Self {
        Self {
            is_optional: true,
            ..Default::default()
        }
    }

    pub(super) fn required() -> Self {
        Self {
            is_optional: false,
            ..Default::default()
        }
    }

    pub(super) fn with_hint_text(mut self, text: &'static str) -> Self {
        self.hint_text = Some(text);
        self
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StaticCommand {
    pub kind: SlashCommandKind,
    pub name: &'static str,
    pub description: &'static str,
    /// The icon rendered for the command in the slash command menu.
    pub icon_path: &'static str,
    /// Specifies the requirements for this command to be available. See [`Availability`].
    pub availability: Availability,
    pub argument: Option<Argument>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SlashCommandArgumentHint {
    pub input_prefix: String,
    pub text: &'static str,
}

impl StaticCommand {
    pub fn matches_filter(&self, filter_text: &str) -> bool {
        if filter_text.is_empty() {
            return true;
        }

        let filter_lower = filter_text.to_lowercase();
        self.name
            .to_lowercase()
            .get(1..)
            .unwrap_or("")
            .starts_with(&filter_lower)
    }

    pub fn is_active(&self, session_context: Availability) -> bool {
        session_context.contains(self.availability)
    }

    pub fn argument_hint(&self) -> Option<SlashCommandArgumentHint> {
        let text = self.argument.as_ref()?.hint_text?;
        Some(SlashCommandArgumentHint {
            input_prefix: format!("{} ", self.name),
            text,
        })
    }
}

#[cfg(test)]
#[path = "mod_tests.rs"]
mod tests;
