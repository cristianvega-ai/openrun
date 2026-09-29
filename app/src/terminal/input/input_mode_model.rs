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
}

impl InputConfig {
    /// Parses a persisted config. Persisted configs always restore as shell input: the rich input
    /// is never open in a restored pane, and configs written when the input could also be an AI
    /// input (`"AI"`) predate the rich-input-only prompt type.
    pub fn from_persisted(json: &str) -> Option<Self> {
        let _: serde_json::Value = serde_json::from_str(json).ok()?;
        Some(Self {
            input_type: InputType::Shell,
        })
    }

    pub fn with_input_type(self, input_type: InputType) -> Self {
        Self { input_type }
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
                    ..
                } = previous_input_state
                {
                    me.set_input_config(*previous_input_config, ctx);
                }
            },
        );

        Self {
            input_config: InputConfig {
                input_type: InputType::Shell,
            },
            terminal_surface_id,
        }
    }

    /// Returns the InputType enum which specifies how we will handle the terminal input.
    pub fn input_type(&self) -> InputType {
        self.input_config.input_type
    }

    pub fn is_prompt_input_enabled(&self) -> bool {
        self.input_config.input_type.is_prompt()
    }

    pub fn input_config(&self) -> InputConfig {
        self.input_config
    }

    /// Swaps between prompt and shell input types.
    pub fn set_input_type(&mut self, input_type: InputType, ctx: &mut ModelContext<Self>) {
        let current_config = self.input_config();
        self.set_input_config(current_config.with_input_type(input_type), ctx);
    }

    /// Sets the input config. Prompt configs are ignored unless a rich input session is open for
    /// this surface.
    pub fn set_input_config(&mut self, new_config: InputConfig, ctx: &mut ModelContext<Self>) {
        if new_config.is_prompt()
            && !CLIAgentSessionsModel::as_ref(ctx).is_input_open(self.terminal_surface_id)
        {
            return;
        }

        if self.input_config == new_config {
            return;
        }

        self.input_config = new_config;
        ctx.emit(InputModeEvent { config: new_config });
    }
}

/// Emitted when the terminal input type is updated.
#[derive(Debug, Clone)]
pub struct InputModeEvent {
    /// The new input config.
    pub config: InputConfig,
}

impl InputModeEvent {
    pub fn updated_config(&self) -> &InputConfig {
        &self.config
    }
}

impl Entity for InputModeModel {
    type Event = InputModeEvent;
}

#[cfg(test)]
#[path = "input_mode_model_tests.rs"]
mod tests;
