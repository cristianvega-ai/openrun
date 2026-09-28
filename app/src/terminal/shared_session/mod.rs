use instant::Duration;
use serde::{Deserialize, Serialize};
use session_sharing_protocol::common::{Role, Scrollback, SessionId};
use session_sharing_protocol::sharer::SessionSourceType;
use warpui::id;
use warpui::keymap::ContextPredicate;

use super::model::block::SerializedBlock;
use super::model::terminal_model::BlockIndex;
use super::{GridType, TerminalModel};
use crate::channel::{Channel, ChannelState};
use crate::editor::{InteractionState, ReplicaId};
use crate::features::FeatureFlag;

pub mod ai_agent;
pub mod manager;
pub mod network;
pub mod presence_manager;
pub mod render_util;
pub mod replay_agent_conversations;
mod selections;
pub(super) mod shared_handlers;
pub mod viewer;

/// The toast copy when copying a shared session link.
pub const COPY_LINK_TEXT: &str = "Sharing link copied";

/// Throttle period for selection updates. We throttle instead of debounce because we want
/// to send selections even when it updates fast, so it appears live.
/// Our throttle implementation throttles on the trailing edge (does not drop messages at the end, so the
/// most up to date will always be sent after some delay)
const SELECTION_THROTTLE_PERIOD: Duration = Duration::from_millis(20);

/// `SessionSourceType` paired with the orchestrator `task_id` that rides
/// on the `source_task_id` sidecar.
#[derive(Debug, Clone)]
pub struct SharedSessionSource {
    pub source_type: SessionSourceType,
    pub source_task_id: Option<String>,
}

impl SharedSessionSource {
    pub fn user(source_task_id: Option<String>) -> Self {
        Self {
            source_type: SessionSourceType::User,
            source_task_id,
        }
    }

    pub fn ambient_agent(task_id: Option<String>) -> Self {
        Self {
            source_type: SessionSourceType::AmbientAgent {
                task_id: task_id.clone(),
            },
            source_task_id: task_id,
        }
    }

    /// Sidecar first, then `AmbientAgent.task_id` for legacy producers.
    pub fn orchestrator_task_id(&self) -> Option<&str> {
        self.source_task_id.as_deref().or(match &self.source_type {
            SessionSourceType::AmbientAgent { task_id } => task_id.as_deref(),
            SessionSourceType::User => None,
        })
    }
}

impl Default for SharedSessionSource {
    fn default() -> Self {
        Self::user(None)
    }
}

/// The type of shared session a particular session is, if applicable.
#[derive(Debug, Clone)]
pub enum SharedSessionStatus {
    /// This session is not a shared session.
    NotShared,

    /// We're in the process of joining the session but have not
    /// established the connection with the server yet, or have not received all the events that occurred before the viewer joined yet.
    ViewPending,

    /// This session is a shared session that we are actively viewing.
    /// We have received all the scrollback and events for the shared session that occurred before the viewer joined, and are caught up and receiving events live.
    ActiveViewer { role: Role },

    /// We were viewing a shared session but it ended.
    FinishedViewer,
}

impl SharedSessionStatus {
    pub fn reader() -> Self {
        Self::ActiveViewer { role: Role::Reader }
    }

    pub fn executor() -> Self {
        Self::ActiveViewer {
            role: Role::Executor,
        }
    }

    pub fn is_view_pending(&self) -> bool {
        matches!(self, SharedSessionStatus::ViewPending)
    }

    pub fn is_active_viewer(&self) -> bool {
        matches!(self, SharedSessionStatus::ActiveViewer { .. })
    }

    pub fn is_finished_viewer(&self) -> bool {
        matches!(self, SharedSessionStatus::FinishedViewer)
    }

    pub fn is_viewer(&self) -> bool {
        self.is_view_pending() || self.is_active_viewer() || self.is_finished_viewer()
    }

    pub fn is_executor(&self) -> bool {
        matches!(self, SharedSessionStatus::ActiveViewer { role } if role.can_execute())
    }

    pub fn is_reader(&self) -> bool {
        matches!(
            self,
            SharedSessionStatus::ActiveViewer { role: Role::Reader }
        )
    }

    pub fn as_keymap_context(&self) -> &'static str {
        match self {
            Self::NotShared => "SharedSessionStatus_NotShared",
            Self::ViewPending => "SharedSessionStatus_ViewPending",
            Self::ActiveViewer { role: Role::Reader } => "SharedSessionStatus_Reader",
            Self::ActiveViewer {
                role: Role::Executor | Role::Full,
            } => "SharedSessionStatus_Executor",
            Self::FinishedViewer => "SharedSessionStatus_FinishedViewer",
        }
    }

    pub fn active_viewer_keymap_context() -> ContextPredicate {
        id!(Self::reader().as_keymap_context()) | id!(Self::executor().as_keymap_context())
    }
}

/// Returns the index of the first block that belongs to a shared session's scrollback.
pub fn first_scrollback_block_index(model: &TerminalModel) -> BlockIndex {
    model
        .block_list()
        .blocks()
        .iter()
        .find(|block| {
            block.is_scrollback_block_for_shared_session(model.block_list().transcript_scope())
        })
        .map_or(model.block_list().active_block_index(), |block| {
            block.index()
        })
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize, Eq, PartialEq)]
pub enum SharedSessionActionSource {
    Tab,
    PaneHeader,
    /// The object-specific sharing dialog.
    SharingDialog,
}

/// Returns the native intent URL to join a shared session.
/// This should be used when opening the session from within Warp.
pub fn join_native_intent(session_id: &SessionId) -> String {
    format!(
        "{}://shared_session/{}",
        ChannelState::url_scheme(),
        session_id
    )
}

/// Returns the link to join a shared session.
pub fn join_link(session_id: &SessionId) -> String {
    // For non-bundled builds against the staging server, use the native app intent
    // because the staging web URL won't resolve to a local build.
    let use_web_url = !ChannelState::uses_staging_server() || cfg!(feature = "release_bundle");

    let mut link = if use_web_url {
        format!("{}/session/{}", ChannelState::server_root_url(), session_id,)
    } else {
        join_native_intent(session_id)
    };

    // If this is a preview build, route the sharing link to the preview server.
    if matches!(ChannelState::channel(), Channel::Preview) {
        link.push_str("?preview=true");
    }

    link
}

/// Returns the full session sharing URL given a path.
pub fn connect_endpoint(path: String) -> Option<String> {
    let base = ChannelState::session_sharing_server_url()?;
    if FeatureFlag::SessionSharingAcls.is_enabled() {
        let version = ChannelState::app_version().unwrap_or("v0.00.000");
        if path.contains("?") {
            return Some(format!("{base}{path}&version={version}"));
        } else {
            return Some(format!("{base}{path}?version={version}"));
        }
    }
    Some(format!("{base}{path}"))
}

/// The event number for events sent to the server. The newtype
/// ensures that events are incremented correctly.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
struct EventNumber(usize);

impl EventNumber {
    fn new() -> Self {
        Self(0)
    }

    /// Returns the current event number and increments
    /// it for the next usage. The event number returned
    /// is the event number that should be used for the next
    /// event to send to the server.
    pub fn advance(&mut self) -> usize {
        let next = self.0;
        self.0 += 1;
        next
    }
}

impl From<EventNumber> for usize {
    fn from(value: EventNumber) -> Self {
        value.0
    }
}

impl From<GridType> for session_sharing_protocol::common::GridType {
    fn from(val: GridType) -> Self {
        match val {
            GridType::Prompt => session_sharing_protocol::common::GridType::Prompt,
            GridType::Rprompt => session_sharing_protocol::common::GridType::Rprompt,
            GridType::Output => session_sharing_protocol::common::GridType::Output,
            GridType::PromptAndCommand => {
                session_sharing_protocol::common::GridType::PromptAndCommand
            }
        }
    }
}

impl From<session_sharing_protocol::common::GridType> for GridType {
    fn from(value: session_sharing_protocol::common::GridType) -> Self {
        match value {
            session_sharing_protocol::common::GridType::Prompt => Self::Prompt,
            session_sharing_protocol::common::GridType::Rprompt => Self::Rprompt,
            session_sharing_protocol::common::GridType::Output => Self::Output,
            session_sharing_protocol::common::GridType::PromptAndCommand => Self::PromptAndCommand,
        }
    }
}

impl From<ReplicaId> for session_sharing_protocol::common::InputReplicaId {
    fn from(value: ReplicaId) -> Self {
        value.to_string().into()
    }
}

impl From<session_sharing_protocol::common::InputReplicaId> for ReplicaId {
    fn from(value: session_sharing_protocol::common::InputReplicaId) -> Self {
        ReplicaId::new(value)
    }
}

impl From<&Role> for InteractionState {
    fn from(value: &Role) -> InteractionState {
        match value {
            Role::Reader => InteractionState::Selectable,
            Role::Executor => InteractionState::Editable,
            Role::Full => InteractionState::Editable,
        }
    }
}

/// Decode scrollback blocks from their JSON wire format into [`SerializedBlock`]s.
///
/// Blocks that fail to deserialize are silently dropped.
pub(crate) fn decode_scrollback(scrollback: &Scrollback) -> Vec<SerializedBlock> {
    scrollback
        .blocks
        .iter()
        .filter_map(|block| serde_json::from_slice(&block.raw).ok())
        .collect()
}

#[cfg(test)]
#[path = "mod_tests.rs"]
mod tests;
