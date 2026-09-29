//! Conversions between [`Harness`] and the CLI agents it corresponds to.

use ai::harness::Harness;

use crate::ai::agent::conversation::AIAgentHarness;
use crate::terminal::CLIAgent;

/// Returns the [`CLIAgent`] corresponding to a cloud-agent [`Harness`] when it represents a
/// third-party agent. Returns `None` for [`Harness::Oz`] (Warp's built-in harness has no
/// distinct CLI agent identity).
pub fn cli_agent(harness: Harness) -> Option<CLIAgent> {
    match harness {
        Harness::Oz => None,
        Harness::Claude => Some(CLIAgent::Claude),
        Harness::Gemini => Some(CLIAgent::Gemini),
        Harness::OpenCode => Some(CLIAgent::OpenCode),
        Harness::Codex => Some(CLIAgent::Codex),
        Harness::Unknown => Some(CLIAgent::Unknown),
    }
}

/// Map [`AIAgentHarness`] (from `ServerAIConversationMetadata`) to the
/// canonical [`Harness`].
impl From<AIAgentHarness> for Harness {
    fn from(harness: AIAgentHarness) -> Self {
        match harness {
            AIAgentHarness::Oz => Harness::Oz,
            AIAgentHarness::ClaudeCode => Harness::Claude,
            AIAgentHarness::Gemini => Harness::Gemini,
            AIAgentHarness::Codex => Harness::Codex,
            AIAgentHarness::Unknown => Harness::Unknown,
        }
    }
}

impl PartialEq<Harness> for AIAgentHarness {
    fn eq(&self, other: &Harness) -> bool {
        Harness::from(*self) == *other
    }
}
