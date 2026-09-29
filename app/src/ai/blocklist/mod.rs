//! This module contains model, controller, and view logic for Blocklist AI.
mod blocklist_filter;
pub mod history_model;
mod permissions;
mod persistence;
pub mod prompt;
mod request_input;

#[cfg(test)]
pub(crate) use history_model::AIQueryHistoryOutputStatus;
pub(crate) use history_model::{
    BlocklistAIHistoryEvent, BlocklistAIHistoryModel, ConversationStatusUpdate,
};
#[cfg(test)]
pub(crate) use permissions::is_agent_mode_autonomy_allowed;
pub use permissions::{BlocklistAIPermissions, CommandExecutionPermissionAllowedReason};
pub(crate) use persistence::PersistedAIInput;
#[cfg(test)]
pub(crate) use persistence::PersistedAIInputType;
pub(crate) use request_input::{RequestInput, ResponseStreamId, SessionContext};
