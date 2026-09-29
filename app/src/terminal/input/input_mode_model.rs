//! Terminal-surface-scoped model managing the input "type": whether the input is a shell command
//! or a prompt composed for a third-party CLI agent in the rich input.

use serde::Serialize;
use warpui::{Entity, EntityId, ModelContext, SingletonEntity};

use crate::terminal::cli_agent_sessions::{
    CLIAgentInputState, CLIAgentSessionsModel, CLIAgentSessionsModelEvent,
};

/// The type of input the user has provided.
#[derive(Default, Debug, Copy, Clone, PartialEq, Eq, Serialize)]
pub enum InputType {
    /// The user input is a shell command.
    #[default]
    Shell,
    /// The user input is a prompt for a CLI agent, composed in the rich input.
    Prompt,
}

impl InputType {
    pub fn is_prompt(&self) -> bool {
        matches!(self, InputType::Prompt)
    }
}

/// Configuration for the terminal pane's input.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Serialize)]
pub struct InputConfig {
    /// The type of the terminal input.
    pub input_type: InputType,

    /// Whether the input type is pinned (e.g. by the `!` shell prefix or an open CLI agent rich
    /// input session).
    pub is_locked: bool,
}

impl InputConfig {
    /// Parses a persisted config. Persisted configs always restore as shell input: the rich input
    /// is never open in a restored pane, and configs written when the input could also be an AI
    /// input (`"AI"`) predate the rich-input-only prompt type.
    pub fn from_persisted(json: &str) -> Option<Self> {
        let value: serde_json::Value = serde_json::from_str(json).ok()?;
        let is_locked = value
            .get("is_locked")
            .and_then(serde_json::Value::as_bool)
            .unwrap_or(true);
        Some(Self {
            input_type: InputType::Shell,
            is_locked,
        })
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

    pub fn is_prompt(&self) -> bool {
        self.input_type == InputType::Prompt
    }

    pub fn is_shell(&self) -> bool {
        self.input_type == InputType::Shell
    }
}

/// Terminal-surface-scoped model responsible for managing the input type.
///
/// Prompt input is only reachable through the CLI agent rich input, so the model rejects prompt
/// configs while no rich input session is open for its surface.
pub struct InputModeModel {
    input_config: InputConfig,

    /// Whether the input buffer was empty at the time the lock was set.  This will be true
    /// if a persistent lock is in place and a buffer is submitted.
    was_lock_set_with_empty_buffer: bool,

    terminal_surface_id: EntityId,
}

impl InputModeModel {
    /// Creates input state for a terminal surface.
    pub fn new(terminal_surface_id: EntityId, ctx: &mut ModelContext<Self>) -> Self {
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
                // CLI agent sessions are keyed by terminal view id, which is also the id of the
                // surface this model belongs to.
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

        Self {
            input_config: InputConfig {
                input_type: InputType::Shell,
                is_locked: true,
            },
            was_lock_set_with_empty_buffer: false,
            terminal_surface_id,
        }
    }

    /// Returns the InputType enum which specifies how we will handle the terminal input.
    pub fn input_type(&self) -> InputType {
        self.input_config.input_type
    }

    /// Whether the input type is locked.
    pub fn is_input_type_locked(&self) -> bool {
        self.input_config.is_locked
    }

    pub fn is_prompt_input_enabled(&self) -> bool {
        self.input_config.input_type.is_prompt()
    }

    pub fn input_config(&self) -> InputConfig {
        self.input_config
    }

    /// Swaps between prompt and shell input types while preserving lock state.
    pub fn set_input_type(&mut self, input_type: InputType, ctx: &mut ModelContext<Self>) {
        let current_config = self.input_config();
        self.set_input_config_internal(current_config.with_input_type(input_type), ctx);
    }

    fn set_input_config_internal(
        &mut self,
        new_config: InputConfig,
        ctx: &mut ModelContext<Self>,
    ) -> bool {
        if new_config.is_prompt()
            && !CLIAgentSessionsModel::as_ref(ctx).is_input_open(self.terminal_surface_id)
        {
            return false;
        }

        if self.input_config == new_config {
            return false;
        }

        let old_config = self.input_config;

        self.input_config = new_config;

        if old_config.input_type != new_config.input_type {
            ctx.emit(InputModeEvent::InputTypeChanged { config: new_config });
        }

        if old_config.is_locked != new_config.is_locked {
            ctx.emit(InputModeEvent::LockChanged { config: new_config });
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
        // We know the buffer is currently empty, as it was just submitted.
        self.set_input_config(self.input_config.locked(), true, ctx);
    }

    pub fn was_lock_set_with_empty_buffer(&self) -> bool {
        self.was_lock_set_with_empty_buffer
    }
}

#[derive(Debug, Clone)]
pub enum InputModeEvent {
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

impl InputModeEvent {
    pub fn updated_config(&self) -> &InputConfig {
        match self {
            InputModeEvent::InputTypeChanged { config }
            | InputModeEvent::LockChanged { config } => config,
        }
    }
}

impl Entity for InputModeModel {
    type Event = InputModeEvent;
}

#[cfg(test)]
#[path = "input_mode_model_tests.rs"]
mod tests;
