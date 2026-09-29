//! This module contains model, controller, and view logic for Blocklist AI.
mod action_model;
pub mod agent_view;
pub mod block;
pub mod code_block;
mod context_model;
mod controller;
pub(crate) mod conversation_selection;
pub(crate) mod diff_storage;
pub(crate) mod diff_types;

pub(crate) mod local_agent_task_sync_model;
pub(super) use controller::RequestInput;
pub mod history_model;
pub mod inline_action;
mod permissions;
mod persistence;
pub mod prompt;
pub mod summarization_cancel_dialog;

pub(crate) mod telemetry_banner;
pub(crate) mod view_util;

pub use action_model::{
    BlocklistAIActionEvent, BlocklistAIActionModel, ShellCommandExecutor, ShellCommandExecutorEvent,
};
pub use block::keyboard_navigable_buttons;
#[cfg(any(test, feature = "integration_tests"))]
pub(crate) use block::model::testing::FakeAIBlockModel;
pub(crate) use block::{AIBlock, AIBlockEvent, RequestedEditResolution, init, model};
pub(crate) use context_model::block_context_from_terminal_model;
pub use context_model::{
    AttachmentType, BlocklistAIContextEvent, BlocklistAIContextModel, PendingAttachment,
    PendingFile,
};
pub use controller::BlocklistAIController;
#[cfg(test)]
pub(crate) use controller::response_stream::ResponseStream;
pub(crate) use controller::response_stream::ResponseStreamId;
pub(crate) use controller::{
    BlocklistAIControllerEvent, ClientIdentifiers, SessionContext, SlashCommandRequest,
};
pub(crate) use conversation_selection::{
    ConversationSelection, ConversationSelectionEvent, ConversationSelectionHandle,
    PendingQueryState,
};
pub(crate) use history_model::{
    AIQueryHistory, AIQueryHistoryOutputStatus, BeginConversationRenameError,
    BlocklistAIHistoryEvent, BlocklistAIHistoryModel, ConversationStatusUpdate, FORK_PREFIX,
    PRE_REWIND_PREFIX,
};
#[cfg(test)]
pub(crate) use permissions::is_agent_mode_autonomy_allowed;
pub use permissions::{BlocklistAIPermissions, CommandExecutionPermissionAllowedReason};
#[cfg(test)]
pub(crate) use persistence::PersistedAIInputType;
#[cfg_attr(target_family = "wasm", allow(unused))]
pub use persistence::maybe_build_ai_query_upsert_event;
pub(crate) use persistence::{PersistedAIInput, SerializedBlockListItem};
pub(crate) use view_util::{
    ai_brand_color, ai_indicator_height, get_ai_block_overflow_menu_element_position_id,
    get_attached_blocks_chip_element_position_id, render_ai_agent_mode_icon,
};

pub use crate::ai::blocklist::block::{AIBlockResponseRating, TextLocation, secret_redaction};
