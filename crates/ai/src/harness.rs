use std::fmt;

use serde::{Deserialize, Serialize};

/// The execution harness for an agent run.
#[derive(Debug, Copy, Clone, Eq, PartialEq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Harness {
    /// Use Warp's built-in MAA infrastructure (default).
    #[default]
    Oz,
    /// Delegate to the `claude` CLI.
    Claude,
    /// Delegate to the `opencode` CLI.
    OpenCode,
    /// Delegate to the `gemini` CLI.
    Gemini,
    /// Delegate to the `codex` CLI.
    Codex,
    /// A harness produced by a newer client/server that this client doesn't
    /// recognize. Surfaced via deserialization fallbacks (e.g. unknown GraphQL
    /// enum values, unknown `harness_type` strings); never selectable from the
    /// harness dropdown.
    #[serde(other)]
    Unknown,
}

impl Harness {
    /// Parses a user-facing harness name or alias (`claude-code`, `open-code`), ignoring
    /// ASCII case. Returns `None` for unrecognized names and for `unknown`.
    pub fn from_name(value: &str) -> Option<Self> {
        match value.to_ascii_lowercase().as_str() {
            "oz" => Some(Self::Oz),
            "claude" | "claude-code" => Some(Self::Claude),
            "opencode" | "open-code" => Some(Self::OpenCode),
            "gemini" => Some(Self::Gemini),
            "codex" => Some(Self::Codex),
            _ => None,
        }
    }

    /// Parses a harness config-name string (the lowercase name written into
    /// `HarnessConfig::harness_type` by the spawner, e.g. `"claude"`, `"gemini"`, `"oz"`)
    /// into a [`Harness`] variant. Inverse of [`Harness::config_name`]. Returns `None` for
    /// unrecognized names so callers can distinguish a future-server harness from a
    /// round-tripped [`Harness::Unknown`]; callers that want to fall back to `Unknown`
    /// should `.unwrap_or(Harness::Unknown)`. UI surfaces should treat `Unknown` as a
    /// non-Oz, non-runnable harness.
    pub fn from_config_name(name: &str) -> Option<Self> {
        match name {
            "oz" => Some(Harness::Oz),
            "claude" => Some(Harness::Claude),
            "opencode" => Some(Harness::OpenCode),
            "gemini" => Some(Harness::Gemini),
            "codex" => Some(Harness::Codex),
            "unknown" => Some(Harness::Unknown),
            _ => None,
        }
    }

    /// Canonical config name for this harness (the lowercase string written into
    /// `HarnessConfig::harness_type`). Inverse of [`Harness::from_config_name`].
    /// The exhaustive match here forces every new [`Harness`] variant to declare a
    /// canonical name, which prevents `from_config_name` from silently falling back to
    /// `Unknown` when a new variant is added.
    pub fn config_name(self) -> &'static str {
        match self {
            Harness::Oz => "oz",
            Harness::Claude => "claude",
            Harness::OpenCode => "opencode",
            Harness::Gemini => "gemini",
            Harness::Codex => "codex",
            Harness::Unknown => "unknown",
        }
    }
}

impl fmt::Display for Harness {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.config_name())
    }
}

#[cfg(test)]
#[path = "harness_tests.rs"]
mod tests;
