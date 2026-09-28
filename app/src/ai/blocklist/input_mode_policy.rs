//! View-supplied policy for input-mode decisions.
//!
//! Several of [`BlocklistAIInputModel`](super::BlocklistAIInputModel)'s
//! decisions depend on view concepts the model cannot know about — e.g.
//! whether the surface distinguishes "fullscreen agent view" from "top-level
//! terminal", or whether locking the input to AI is allowed outside a
//! conversation. The view supplies those answers via [`InputModePolicy`],
//! mirroring how [`ConversationSelection`](super::conversation_selection::ConversationSelection)
//! injects per-view selection semantics.
//!
//! The implementation lives in `super::agent_view::GuiInputModePolicy`.

use std::rc::Rc;

use warpui::AppContext;

use super::conversation_selection::ConversationSelectionEvent;
use super::input_model::InputConfig;

/// Per-view policy consulted by [`BlocklistAIInputModel`](super::BlocklistAIInputModel)
/// for decisions it cannot make view-agnostically: lock gating and reactive
/// config transitions driven by conversation-selection events.
///
/// The reactive hook receives the raw event and decides the config to apply,
/// so view-specific event payloads (fullscreen vs. inline, entry origins)
/// stay a concern of the implementing view.
pub trait InputModePolicy: 'static {
    /// The config the surface starts with.
    fn initial_config(&self, app: &AppContext) -> InputConfig;

    /// Whether the input may currently be locked to AI. When this returns
    /// `false`, `{AI, locked}` config writes are rejected.
    fn allows_locked_ai_input(&self, app: &AppContext) -> bool;

    /// The config to apply in response to a conversation-selection event, or
    /// `None` to leave the config unchanged.
    fn config_on_conversation_selection_changed(
        &self,
        event: &ConversationSelectionEvent,
        current: InputConfig,
        app: &AppContext,
    ) -> Option<InputConfig>;
}

/// Shared handle to a view-supplied [`InputModePolicy`].
pub type InputModePolicyHandle = Rc<dyn InputModePolicy>;
