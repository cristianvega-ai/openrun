//! GUI implementation of [`InputModePolicy`].

use warp_core::features::FeatureFlag;
use warpui::{AppContext, EntityId, SingletonEntity};

use super::super::ConversationSelectionHandle;
use super::super::conversation_selection::ConversationSelectionEvent;
use super::super::input_mode_policy::InputModePolicy;
use super::super::input_model::{InputConfig, InputType};
use super::AgentViewEntryOrigin;
use crate::terminal::cli_agent_sessions::CLIAgentSessionsModel;

/// GUI input-mode policy. The surface is either a fullscreen agent view or a
/// top-level terminal (when `FeatureFlag::AgentView` is enabled), and AI input
/// may only be locked inside an agent view or an open CLI-agent rich input
/// session.
pub(crate) struct GuiInputModePolicy {
    conversation_selection: ConversationSelectionHandle,
    terminal_surface_id: EntityId,
}

impl GuiInputModePolicy {
    /// Creates the GUI policy for a terminal surface.
    pub(crate) fn new(
        conversation_selection: ConversationSelectionHandle,
        terminal_surface_id: EntityId,
    ) -> Self {
        Self {
            conversation_selection,
            terminal_surface_id,
        }
    }
}

impl InputModePolicy for GuiInputModePolicy {
    fn initial_config(&self, _app: &AppContext) -> InputConfig {
        InputConfig {
            input_type: InputType::Shell,
            is_locked: true,
        }
    }

    fn allows_locked_ai_input(&self, app: &AppContext) -> bool {
        // When `AgentView` is enabled, the input cannot be locked to AI input mode unless there is
        // an active agent view or a CLI agent rich input session is open. In the CLI agent rich
        // input case, the input must be in AI mode to suppress shell decorations (syntax
        // highlighting, error underlining).
        !FeatureFlag::AgentView.is_enabled()
            || self
                .conversation_selection
                .as_ref(app)
                .is_conversation_active(app)
            || CLIAgentSessionsModel::as_ref(app).is_input_open(self.terminal_surface_id)
    }

    fn config_on_conversation_selection_changed(
        &self,
        event: &ConversationSelectionEvent,
        current: InputConfig,
        _app: &AppContext,
    ) -> Option<InputConfig> {
        match event {
            ConversationSelectionEvent::Changed => None,
            ConversationSelectionEvent::Activated {
                is_fullscreen,
                origin,
            } => {
                if *is_fullscreen && matches!(origin, AgentViewEntryOrigin::ClearBuffer) {
                    Some(current.locked())
                } else {
                    Some(InputConfig {
                        input_type: InputType::AI,
                        is_locked: true,
                    })
                }
            }
            ConversationSelectionEvent::Deactivated {
                is_exit_before_new_entrance,
                ..
            } => {
                if *is_exit_before_new_entrance {
                    return None;
                }
                Some(InputConfig {
                    input_type: InputType::Shell,
                    is_locked: true,
                })
            }
        }
    }
}
