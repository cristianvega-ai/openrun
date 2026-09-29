//! Model-layer AI input state management logic.
//!
//! The primary export of this module is `BlocklistAIInputModel`, which is a terminal-surface-scoped
//! model managing input "type" state (whether the input is in AI or shell mode).

use std::sync::Arc;

use parking_lot::FairMutex;
use serde::{Deserialize, Serialize};
use warp_core::features::FeatureFlag;
use warpui::{AppContext, Entity, EntityId, ModelContext, SingletonEntity};

/// The type of input the user has provided.
#[derive(Default, Debug, Copy, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum InputType {
    /// The user input is a shell command.
    #[default]
    Shell,
    /// The user input is a natural language query to AI.
    AI,
}

impl InputType {
    pub fn is_ai(&self) -> bool {
        matches!(self, InputType::AI)
    }
}

use super::ConversationSelectionHandle;
use super::input_mode_policy::InputModePolicyHandle;
use crate::settings::InputSettings;
use crate::terminal::TerminalModel;
use crate::terminal::cli_agent_sessions::{
    CLIAgentInputState, CLIAgentSessionsModel, CLIAgentSessionsModelEvent,
};

/// Configuration for the terminal pane's input.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct InputConfig {
    /// The type of the terminal input.
    pub input_type: InputType,

    /// Whether the input type is pinned (e.g. by the `!` shell prefix or an open CLI agent rich
    /// input session).
    pub is_locked: bool,
}

impl InputConfig {
    pub fn with_toggled_type(self) -> Self {
        let input_type = if self.input_type.is_ai() {
            InputType::Shell
        } else {
            InputType::AI
        };
        Self { input_type, ..self }
    }

    pub fn with_shell_type(self) -> Self {
        Self {
            input_type: InputType::Shell,
            ..self
        }
    }

    pub fn with_input_type(self, input_type: InputType) -> Self {
        Self { input_type, ..self }
    }

    pub fn locked(self) -> Self {
        Self {
            is_locked: true,
            ..self
        }
    }

    pub fn is_ai(&self) -> bool {
        self.input_type == InputType::AI
    }

    pub fn is_shell(&self) -> bool {
        self.input_type == InputType::Shell
    }
}

/// Terminal-surface-scoped model responsible for managing AI input state.
#[derive(Clone)]
pub struct BlocklistAIInputModel {
    input_config: InputConfig,

    /// Whether the input buffer was empty at the time the lock was set.  This will be true
    /// if a persistent lock is in place and a buffer is submitted.
    was_lock_set_with_empty_buffer: bool,

    conversation_selection: ConversationSelectionHandle,

    /// View-supplied policy for decisions the model cannot make view-agnostically
    /// (lock gating, reactive config transitions).
    policy: InputModePolicyHandle,

    model: Arc<FairMutex<TerminalModel>>,
}

impl BlocklistAIInputModel {
    /// Creates input state for a terminal surface.
    pub fn new(
        model: Arc<FairMutex<TerminalModel>>,
        conversation_selection: ConversationSelectionHandle,
        policy: InputModePolicyHandle,
        terminal_surface_id: EntityId,
        ctx: &mut ModelContext<Self>,
    ) -> Self {
        // Reactively restore input config when CLI agent rich input closes.
        ctx.subscribe_to_model(
            &CLIAgentSessionsModel::handle(ctx),
            move |me, _, event, ctx| {
                let CLIAgentSessionsModelEvent::InputSessionChanged {
                    terminal_view_id: event_view_id,
                    previous_input_state,
                    ..
                } = event
                else {
                    return;
                };
                // CLI agent sessions are keyed by terminal view id; GUI surfaces use the
                // view id as their surface id, so this filters events to our surface.
                if *event_view_id != terminal_surface_id {
                    return;
                }
                if let CLIAgentInputState::Open {
                    previous_input_config,
                    previous_was_lock_set_with_empty_buffer,
                    ..
                } = previous_input_state
                {
                    me.restore_input_config(
                        *previous_input_config,
                        *previous_was_lock_set_with_empty_buffer,
                        ctx,
                    );
                }
            },
        );

        ctx.subscribe_to_model(&conversation_selection, |me, _, event, ctx| {
            if let Some(config) =
                me.policy
                    .config_on_conversation_selection_changed(event, me.input_config(), ctx)
            {
                me.set_input_config_internal(config, ctx);
            }
        });

        let input_config = policy.initial_config(ctx);
        Self {
            input_config,
            conversation_selection,
            policy,
            was_lock_set_with_empty_buffer: false,
            model,
        }
    }

    /// Builds a self-contained input model for tests, usable from other crates
    /// via the `test-util` feature: a mock terminal model, an inert
    /// conversation selection, and no production subscriptions.
    #[cfg(any(test, feature = "test-util"))]
    pub fn mock(policy: InputModePolicyHandle, ctx: &mut AppContext) -> warpui::ModelHandle<Self> {
        use super::conversation_selection::{ConversationSelection, MockConversationSelection};

        let model = Arc::new(FairMutex::new(TerminalModel::mock(None, None)));
        let conversation_selection = ctx
            .add_model(|_| Box::new(MockConversationSelection) as Box<dyn ConversationSelection>);
        let input_config = policy.initial_config(ctx);
        ctx.add_model(|_| Self {
            input_config,
            conversation_selection,
            policy,
            was_lock_set_with_empty_buffer: false,
            model,
        })
    }

    /// Returns whether the surface presents a selected conversation as active.
    fn is_conversation_active(&self, app: &AppContext) -> bool {
        self.conversation_selection
            .as_ref(app)
            .is_conversation_active(app)
    }

    /// Returns the InputType enum which specifies how we will handle the terminal input.
    pub fn input_type(&self) -> InputType {
        self.input_config.input_type
    }

    /// Whether the input type is locked. Does not take feature flags into account.
    pub fn is_input_type_locked(&self) -> bool {
        self.input_config.is_locked
    }

    pub fn is_ai_input_enabled(&self) -> bool {
        matches!(self.input_config.input_type, InputType::AI)
    }

    pub fn input_config(&self) -> InputConfig {
        self.input_config
    }

    pub fn is_terminal_use_active_or_pending(&self) -> bool {
        let model = self.model.lock();
        let active_block = model.block_list().active_block();
        // Keep AI input locked while an agent-requested command is waiting for its
        // CLI subagent, while the user has tagged the agent in, or while the user
        // can hand control of an active monitored command back to the agent.
        active_block.is_agent_driving_command()
            || active_block.is_agent_tagged_in()
            || active_block.is_eligible_for_agent_handoff()
    }
    /// Sets the input config iff the input is in classic mode (i.e. not UDI).
    pub fn set_input_config_for_classic_mode(
        &mut self,
        new_config: InputConfig,
        ctx: &mut ModelContext<Self>,
    ) {
        // When agent view is active, the input should behave like Universal mode
        // even if Classic mode is selected (e.g. when PS1 is enabled).
        if FeatureFlag::AgentView.is_enabled() && self.is_conversation_active(ctx) {
            return;
        }

        if InputSettings::as_ref(ctx).is_warp_prompt_enabled(ctx) {
            return;
        }
        self.set_input_config_internal(new_config, ctx);
    }

    /// Swaps between Agent/Shell input types while preserving lock state.
    pub fn set_input_type(&mut self, input_type: InputType, ctx: &mut ModelContext<Self>) {
        let current_config = self.input_config();
        self.set_input_config_internal(current_config.with_input_type(input_type), ctx);
    }

    fn set_input_config_internal(
        &mut self,
        new_config: InputConfig,
        ctx: &mut ModelContext<Self>,
    ) -> bool {
        // Locking the input to AI is only allowed when the view's policy permits it (e.g. the
        // GUI only allows it inside an agent view or an open CLI agent rich input session).
        if new_config.input_type.is_ai()
            && new_config.is_locked
            && !self.policy.allows_locked_ai_input(ctx)
        {
            return false;
        }

        if self.input_config == new_config {
            return false;
        }

        let old_config = self.input_config;

        self.input_config = new_config;

        // Emit specific events for what actually changed
        if old_config.input_type != new_config.input_type {
            ctx.emit(BlocklistAIInputEvent::InputTypeChanged { config: new_config });
        }

        if old_config.is_locked != new_config.is_locked {
            ctx.emit(BlocklistAIInputEvent::LockChanged { config: new_config });
        }

        true
    }

    /// Allows you to set the input config and mutate the lock state.
    pub fn set_input_config(
        &mut self,
        new_config: InputConfig,
        is_input_buffer_empty: bool,
        ctx: &mut ModelContext<Self>,
    ) {
        self.set_input_config_internal(new_config, ctx);
        self.was_lock_set_with_empty_buffer = self.is_input_type_locked() && is_input_buffer_empty;
    }

    /// Restores a previous input config without recomputing whether the lock was set while the
    /// buffer was empty.
    fn restore_input_config(
        &mut self,
        new_config: InputConfig,
        was_lock_set_with_empty_buffer: bool,
        ctx: &mut ModelContext<Self>,
    ) {
        self.set_input_config_internal(new_config, ctx);
        self.was_lock_set_with_empty_buffer = was_lock_set_with_empty_buffer;
    }

    /// Handles the input buffer being submitted.
    pub fn handle_input_buffer_submitted(&mut self, ctx: &mut ModelContext<Self>) {
        // If the agent is still in control of a long-running command, keep the input locked to AI mode.
        let is_terminal_use_active_or_pending = self.is_terminal_use_active_or_pending();

        let new_config = if is_terminal_use_active_or_pending {
            InputConfig {
                input_type: InputType::AI,
                is_locked: true,
            }
        } else {
            self.input_config.locked()
        };

        // We know the buffer is currently empty, as it was just submitted.
        self.set_input_config(new_config, true, ctx);
    }

    pub fn was_lock_set_with_empty_buffer(&self) -> bool {
        self.was_lock_set_with_empty_buffer
    }
}

#[derive(Debug, Clone)]
pub enum BlocklistAIInputEvent {
    /// Emitted when the terminal input type is updated.
    InputTypeChanged {
        /// The new input config.
        config: InputConfig,
    },
    /// Emitted when the input lock state is updated.
    LockChanged {
        /// The new input config.
        config: InputConfig,
    },
}

impl BlocklistAIInputEvent {
    pub fn did_update_input_config(&self) -> bool {
        match self {
            BlocklistAIInputEvent::InputTypeChanged { .. }
            | BlocklistAIInputEvent::LockChanged { .. } => true,
        }
    }

    pub fn updated_config(&self) -> &InputConfig {
        match self {
            BlocklistAIInputEvent::InputTypeChanged { config }
            | BlocklistAIInputEvent::LockChanged { config } => config,
        }
    }
}

impl Entity for BlocklistAIInputModel {
    type Event = BlocklistAIInputEvent;
}

#[cfg(test)]
#[path = "input_model_tests.rs"]
mod tests;
