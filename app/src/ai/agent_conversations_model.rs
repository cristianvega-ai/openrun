#[allow(dead_code)]
pub mod entry;
mod query;

use std::collections::{HashMap, HashSet};
use std::time::Duration;

use ai::harness::Harness;
pub use entry::{
    AgentConversationEntry, AgentConversationEntryId, AgentConversationNavigationSubject,
};
use fuzzy_match::FuzzyMatchResult;
use instant::Instant;
use itertools::Itertools;
pub use query::query_conversation_entries;
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use warp_core::execution_mode::AppExecutionMode;
use warp_core::features::FeatureFlag;
use warp_core::ui::theme::WarpTheme;
use warp_core::ui::theme::color::internal_colors;
use warp_errors::report_error;
use warpui::color::ColorU;
use warpui::{AppContext, Entity, ModelContext, RequestState, SingletonEntity};

use crate::ai::active_agent_views_model::ActiveAgentViewsModel;
use crate::ai::agent::api::ServerConversationToken;
use crate::ai::agent::conversation::{AIConversationId, ConversationStatus};
use crate::ai::ambient_agents::{AgentSource, AmbientAgentTask, AmbientAgentTaskId};
use crate::ai::artifacts::Artifact;
use crate::ai::blocklist::{
    BlocklistAIHistoryEvent, BlocklistAIHistoryModel, ConversationStatusUpdate,
};
use crate::ai::cloud_environments::CloudAmbientAgentEnvironment;
use crate::ai::conversation_navigation::ConversationNavigationData;
use crate::auth::AuthStateProvider;
use crate::cloud_object::CloudObjectLookup as _;
use crate::server::ids::{ServerId, SyncId};
use crate::server::retry_strategies::{
    OUT_OF_BAND_REQUEST_RETRY_STRATEGY, is_transient_http_error,
};
use crate::server::server_api::ServerApiProvider;
use crate::ui_components::icons::Icon;
use crate::workspace::{RestoreConversationLayout, WorkspaceAction};
use crate::workspaces::user_workspaces::TeamScope;

/// How long to skip refetching a task that just failed with a transient error
/// (5xx / 408 / 429 / network). Short cooldown — `spawn_with_retry_on_error_when` already
/// runs fast exponential retries before bubbling up the failure, so this is just enough to
/// absorb streaming-driven re-entries.
const TRANSIENT_FETCH_FAILURE_COOLDOWN: Duration = Duration::from_secs(2);

/// How long to skip refetching a task that just failed with a permanent (non-transient) HTTP
/// error such as 401/403/404. We don't refuse forever — permissions can change mid-session
/// (e.g. an ACL grant) — but we wait long enough that streaming bursts and rapid re-entries
/// can't cause a flood.
const PERMANENT_FETCH_FAILURE_COOLDOWN: Duration = Duration::from_secs(60);

/// Per-task fetch state for `get_or_async_fetch_task_data`. The three variants are mutually
/// exclusive: a task id is either being fetched right now, in a short cooldown after a
/// transient failure, or in a longer cooldown after a permanent (non-transient) failure.
#[derive(Debug)]
enum TaskFetchState {
    /// A retry chain is currently outstanding for this task id. Used to dedupe re-entries
    /// (e.g. from streaming-driven panel refreshes) so we don't spawn overlapping retry
    /// chains for the same task id.
    InFlight,
    /// The fetch returned a permanent (non-transient) HTTP error such as 401/403/404; remember
    /// when it failed so we can back off for [`PERMANENT_FETCH_FAILURE_COOLDOWN`] before
    /// retrying. We don't refuse forever in case permissions change mid-session.
    PermanentlyFailed { at: Instant },
    /// The retry chain just exhausted on a transient error; remember when it failed so we
    /// can back off for [`TRANSIENT_FETCH_FAILURE_COOLDOWN`] before retrying.
    TransientlyFailed { at: Instant },
}

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum SessionStatus {
    Available,
    Expired,
    Unavailable,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Default, Serialize, Deserialize)]
pub enum StatusFilter {
    #[default]
    All,
    Working,
    Done,
    Failed,
}

impl StatusFilter {
    /// Returns `true` if a status transition from `prev_bucket` to `new_bucket` flips
    /// whether an item is included by this filter. `All` matches every bucket so it
    /// is never crossed; the other variants are crossed when exactly one of the buckets
    /// equals this filter.
    pub(crate) fn is_membership_crossed(
        self,
        prev_bucket: StatusFilter,
        new_bucket: StatusFilter,
    ) -> bool {
        match self {
            StatusFilter::All => false,
            StatusFilter::Working | StatusFilter::Done | StatusFilter::Failed => {
                (prev_bucket == self) != (new_bucket == self)
            }
        }
    }
}

#[derive(Clone, PartialEq, Eq, Debug, Default, Serialize, Deserialize)]
pub enum SourceFilter {
    #[default]
    All,
    Specific(AgentSource),
}

#[derive(Clone, PartialEq, Eq, Debug, Default, Serialize, Deserialize)]
pub enum CreatorFilter {
    #[default]
    All,
    Specific {
        name: String,
        uid: String,
    },
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Default, Serialize, Deserialize)]
pub enum ArtifactFilter {
    #[default]
    All,
    PullRequest,
    Plan,
    Screenshot,
    File,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Default, Serialize, Deserialize)]
pub enum CreatedOnFilter {
    #[default]
    All,
    Last24Hours,
    Past3Days,
    LastWeek,
}

#[derive(Clone, PartialEq, Eq, Debug, Default, Serialize, Deserialize)]
pub enum EnvironmentFilter {
    #[default]
    All,
    NoEnvironment,
    Specific(String),
}

#[derive(Default, Debug, Copy, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum OwnerFilter {
    All,
    #[default]
    PersonalOnly,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Default)]
pub enum HarnessFilter {
    #[default]
    All,
    Specific(Harness),
}

impl Serialize for HarnessFilter {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        match self {
            HarnessFilter::All => serializer.serialize_str("all"),
            HarnessFilter::Specific(harness) => serializer.collect_str(harness),
        }
    }
}

impl<'de> Deserialize<'de> for HarnessFilter {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let raw = String::deserialize(deserializer)?;
        Ok(Harness::from_name(&raw)
            .map(HarnessFilter::Specific)
            .unwrap_or(HarnessFilter::All))
    }
}

#[derive(Default, PartialEq, Eq, Clone, Debug, Serialize, Deserialize)]
pub struct AgentManagementFilters {
    pub owners: OwnerFilter,
    pub status: StatusFilter,
    pub source: SourceFilter,
    pub created_on: CreatedOnFilter,
    pub creator: CreatorFilter,
    pub artifact: ArtifactFilter,
    #[serde(default)]
    pub environment: EnvironmentFilter,
    #[serde(default)]
    pub harness: HarnessFilter,
}

/// Frontend-specific classification of a normalized conversation-list entry.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AgentConversationListEntryState {
    Selected,
    OpenElsewhere,
    Available,
    Unavailable,
}

/// Per-frontend policy for classifying normalized conversation-list entries.
pub trait AgentConversationListPolicy: 'static {
    /// Classifies `entry` as selected, open elsewhere, available, or unavailable.
    fn classify_entry(
        &self,
        entry: &AgentConversationEntry,
        app: &AppContext,
    ) -> AgentConversationListEntryState;
}

/// A normalized conversation entry paired with optional title-match metadata.
pub struct AgentConversationQueryResult {
    pub entry: AgentConversationEntry,
    pub title_match: Option<FuzzyMatchResult>,
}

impl AgentManagementFilters {
    pub fn reset_all_but_owner(&mut self) {
        self.status = StatusFilter::default();
        self.source = SourceFilter::default();
        self.created_on = CreatedOnFilter::default();
        self.creator = CreatorFilter::default();
        self.artifact = ArtifactFilter::default();
        self.environment = EnvironmentFilter::default();
        self.harness = HarnessFilter::default();
    }

    pub fn is_filtering(&self) -> bool {
        self.status != StatusFilter::default()
            || self.source != SourceFilter::default()
            || self.created_on != CreatedOnFilter::default()
            || self.creator != CreatorFilter::default() && self.owners != OwnerFilter::PersonalOnly
            || self.artifact != ArtifactFilter::default()
            || self.environment != EnvironmentFilter::default()
            || self.harness != HarnessFilter::default()
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum AgentRunDisplayStatus {
    ConversationInProgress,
    ConversationSucceeded,
    ConversationError,
    ConversationBlocked { blocked_action: String },
    ConversationCancelled,
}

impl AgentRunDisplayStatus {
    pub fn from_conversation_status(status: &ConversationStatus) -> Self {
        match status {
            ConversationStatus::InProgress => Self::ConversationInProgress,
            // A recovery is in flight; the run is still working.
            ConversationStatus::TransientError => Self::ConversationInProgress,
            ConversationStatus::Success => Self::ConversationSucceeded,
            ConversationStatus::Error => Self::ConversationError,
            ConversationStatus::Cancelled => Self::ConversationCancelled,
            ConversationStatus::Blocked { blocked_action } => Self::ConversationBlocked {
                blocked_action: blocked_action.clone(),
            },
        }
    }

    pub fn status_filter(&self) -> StatusFilter {
        match self {
            AgentRunDisplayStatus::ConversationInProgress => StatusFilter::Working,
            AgentRunDisplayStatus::ConversationSucceeded => StatusFilter::Done,
            AgentRunDisplayStatus::ConversationError
            | AgentRunDisplayStatus::ConversationBlocked { .. }
            | AgentRunDisplayStatus::ConversationCancelled => StatusFilter::Failed,
        }
    }

    pub fn to_conversation_status(&self) -> ConversationStatus {
        match self {
            AgentRunDisplayStatus::ConversationInProgress => ConversationStatus::InProgress,
            AgentRunDisplayStatus::ConversationSucceeded => ConversationStatus::Success,
            AgentRunDisplayStatus::ConversationError => ConversationStatus::Error,
            AgentRunDisplayStatus::ConversationBlocked { blocked_action } => {
                ConversationStatus::Blocked {
                    blocked_action: blocked_action.clone(),
                }
            }
            AgentRunDisplayStatus::ConversationCancelled => ConversationStatus::Cancelled,
        }
    }

    pub fn is_cancellable(&self) -> bool {
        self.is_working()
    }

    pub fn is_working(&self) -> bool {
        matches!(self, AgentRunDisplayStatus::ConversationInProgress)
    }

    pub fn status_icon_and_color(&self, theme: &WarpTheme) -> (Icon, ColorU) {
        match self {
            AgentRunDisplayStatus::ConversationInProgress => {
                (Icon::ClockLoader, theme.ansi_fg_magenta())
            }
            AgentRunDisplayStatus::ConversationSucceeded => (Icon::Check, theme.ansi_fg_green()),
            AgentRunDisplayStatus::ConversationError => (Icon::Triangle, theme.ansi_fg_red()),
            AgentRunDisplayStatus::ConversationBlocked { .. } => {
                (Icon::StopFilled, theme.ansi_fg_yellow())
            }
            AgentRunDisplayStatus::ConversationCancelled => {
                (Icon::StopFilled, internal_colors::neutral_5(theme))
            }
        }
    }
}

impl std::fmt::Display for AgentRunDisplayStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AgentRunDisplayStatus::ConversationInProgress => write!(f, "In progress"),
            AgentRunDisplayStatus::ConversationSucceeded => write!(f, "Done"),
            AgentRunDisplayStatus::ConversationError => write!(f, "Error"),
            AgentRunDisplayStatus::ConversationBlocked { .. } => write!(f, "Blocked"),
            AgentRunDisplayStatus::ConversationCancelled => write!(f, "Cancelled"),
        }
    }
}

/// Stores conversation metadata needed for display in conversation views.
pub struct ConversationMetadata {
    pub nav_data: ConversationNavigationData,
}

pub(crate) fn artifacts_match_filter(
    artifacts: &[Artifact],
    artifact_filter: &ArtifactFilter,
) -> bool {
    match artifact_filter {
        ArtifactFilter::All => true,
        ArtifactFilter::PullRequest => artifacts
            .iter()
            .any(|artifact| matches!(artifact, Artifact::PullRequest { .. })),
        ArtifactFilter::Plan => artifacts
            .iter()
            .any(|artifact| matches!(artifact, Artifact::Plan { .. })),
        ArtifactFilter::Screenshot => artifacts
            .iter()
            .any(|artifact| matches!(artifact, Artifact::Screenshot { .. })),
        ArtifactFilter::File => artifacts
            .iter()
            .any(|artifact| matches!(artifact, Artifact::File { .. })),
    }
}

/// This model serves as a unified interface for reading local agent conversations. It backs
/// both the agent management view and the conversation list view.
pub struct AgentConversationsModel {
    /// A map of task IDs to agent tasks.
    tasks: HashMap<AmbientAgentTaskId, AmbientAgentTask>,
    /// A map of conversation IDs to local conversations.
    conversations: HashMap<AIConversationId, ConversationMetadata>,
    /// Per-task fetch state for `get_or_async_fetch_task_data`. See [`TaskFetchState`] for
    /// the meaning of each variant. Tasks that have been successfully fetched live in `tasks`
    /// and are absent from this map.
    task_fetch_state: HashMap<AmbientAgentTaskId, TaskFetchState>,
    is_loading: bool,
}

pub enum AgentConversationsModelEvent {
    /// Conversation data was loaded or refreshed.
    ConversationsLoaded,
    /// Existing task data may have been updated (e.g., state changes).
    TasksUpdated,
    /// Conversation status data was updated
    ConversationUpdated { kind: ConversationUpdateKind },
    /// Conversation artifacts were updated (plans, PRs, etc.)
    ConversationArtifactsUpdated { conversation_id: AIConversationId },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConversationUpdateKind {
    /// The conversation was re-loaded into a terminal view.
    Restored,
    /// The conversation's status was set.
    StatusSet {
        prev_filter: StatusFilter,
        new_filter: StatusFilter,
    },
    /// Conversation metadata or capabilities changed.
    MetadataChanged,
    /// Conversation title changed.
    TitleChanged,
}

impl Entity for AgentConversationsModel {
    type Event = AgentConversationsModelEvent;
}

impl SingletonEntity for AgentConversationsModel {}

impl AgentConversationsModel {
    pub fn new(ctx: &mut ModelContext<Self>) -> Self {
        // If FF not enabled, return an empty model.
        if !FeatureFlag::AgentManagementView.is_enabled() {
            return Self {
                tasks: HashMap::new(),
                conversations: HashMap::new(),
                task_fetch_state: HashMap::new(),
                is_loading: false,
            };
        }

        let history_model = BlocklistAIHistoryModel::handle(ctx);
        ctx.subscribe_to_model(&history_model, move |me, _, event, ctx| {
            me.handle_history_event(event, ctx);
        });

        let active_views_model = ActiveAgentViewsModel::handle(ctx);
        ctx.subscribe_to_model(&active_views_model, |me, _, _event, ctx| {
            me.sync_conversations(ctx);
        });

        let mut model = Self {
            tasks: HashMap::new(),
            conversations: HashMap::new(),
            task_fetch_state: HashMap::new(),
            is_loading: true,
        };

        // Only sync local conversations if we're not in CLI mode.
        if AppExecutionMode::as_ref(ctx).can_fetch_agent_runs_for_management() {
            model.sync_conversations(ctx);
        } else {
            model.is_loading = false;
        }
        model
    }

    pub fn is_loading(&self) -> bool {
        self.is_loading
    }

    /// Sync all conversations to the AgentConversationsModel.
    ///
    /// This function will loop through all active panes, recently closed panes, and historical
    /// conversations to construct a complete snapshot of conversations.
    pub fn sync_conversations(&mut self, ctx: &mut ModelContext<Self>) {
        if !FeatureFlag::InteractiveConversationManagementView.is_enabled() {
            return;
        }

        let nav_data_list = ConversationNavigationData::all_conversations(ctx);

        self.conversations.clear();
        for nav_data in nav_data_list {
            let conversation_id = nav_data.id;
            let metadata = ConversationMetadata { nav_data };
            self.conversations.insert(conversation_id, metadata);
        }
        self.is_loading = false;

        ctx.emit(AgentConversationsModelEvent::ConversationsLoaded);
    }

    /// Seeds the task cache so tests can exercise cache-hit paths without a
    /// server round trip.
    #[cfg(test)]
    pub(crate) fn insert_task_for_test(&mut self, task: AmbientAgentTask) {
        self.tasks.insert(task.task_id, task);
    }

    /// Returns normalized, owned entries for agent management/navigation surfaces.
    pub fn get_entries<S: TeamScope + ?Sized>(
        &self,
        filters: &AgentManagementFilters,
        _scope: &S,
        app: &AppContext,
    ) -> Vec<AgentConversationEntry> {
        self.unfiltered_entries(app)
            .into_iter()
            .filter(|entry| entry.matches_filters(filters))
            .sorted_by(|a, b| b.display.last_updated.cmp(&a.display.last_updated))
            .collect()
    }

    pub fn has_items<S: TeamScope + ?Sized>(&self, _scope: &S, app: &AppContext) -> bool {
        !self.unfiltered_entries(app).is_empty()
    }

    fn task_matches_team(task: &AmbientAgentTask, team_uid: Option<ServerId>) -> bool {
        task.scope
            .as_ref()
            .filter(|scope| scope.is_team())
            .is_none_or(|scope| team_uid.is_some_and(|team_uid| scope.uid == team_uid.to_string()))
    }

    /// Returns normalized entries before user-selected filters are applied.
    fn unfiltered_entries(&self, app: &AppContext) -> Vec<AgentConversationEntry> {
        let history_model = BlocklistAIHistoryModel::as_ref(app);
        let mut entries = Vec::new();
        let mut emitted_conversation_ids = HashSet::new();

        for metadata in self.conversations.values() {
            let conversation_id = metadata.nav_data.id;
            let entry = entry::entry_for_conversation(metadata, history_model, app);
            emitted_conversation_ids.insert(conversation_id);
            entries.push(entry);
        }

        for metadata in history_model.get_local_conversations_metadata() {
            if emitted_conversation_ids.contains(&metadata.id) {
                continue;
            }
            let nav_data =
                ConversationNavigationData::from_historical_conversation_metadata(metadata);
            entries.push(entry::entry_for_historical_metadata(
                metadata,
                nav_data,
                history_model,
                app,
            ));
        }

        entries
    }

    pub fn get_entry_by_id(
        &self,
        id: &AgentConversationEntryId,
        app: &AppContext,
    ) -> Option<AgentConversationEntry> {
        let history_model = BlocklistAIHistoryModel::as_ref(app);
        let AgentConversationEntryId::Conversation(conversation_id) = id;
        self.conversations
            .get(conversation_id)
            .map(|metadata| entry::entry_for_conversation(metadata, history_model, app))
            .or_else(|| {
                history_model
                    .get_conversation_metadata(conversation_id)
                    .map(|metadata| {
                        let nav_data =
                            ConversationNavigationData::from_historical_conversation_metadata(
                                metadata,
                            );
                        entry::entry_for_historical_metadata(metadata, nav_data, history_model, app)
                    })
            })
    }

    pub fn resolve_open_action(
        subject: AgentConversationNavigationSubject,
        restore_layout: Option<RestoreConversationLayout>,
        app: &AppContext,
    ) -> Option<WorkspaceAction> {
        let model = Self::as_ref(app);
        match subject {
            AgentConversationNavigationSubject::Entry(id) => model
                .get_entry_by_id(&id, app)
                .and_then(|entry| model.resolve_entry_open_action(&entry, restore_layout, app)),
            AgentConversationNavigationSubject::ServerToken(server_token) => model
                .entry_for_server_token(&server_token, app)
                .and_then(|entry| model.resolve_entry_open_action(&entry, restore_layout, app))
                .or_else(|| {
                    Some(WorkspaceAction::OpenConversationTranscriptViewer {
                        conversation_id: server_token,
                    })
                }),
        }
    }

    pub fn resolve_copy_link(
        subject: AgentConversationNavigationSubject,
        app: &AppContext,
    ) -> Option<String> {
        let model = Self::as_ref(app);
        match subject {
            AgentConversationNavigationSubject::Entry(id) => model
                .get_entry_by_id(&id, app)
                .and_then(|entry| model.resolve_entry_copy_link(&entry)),
            AgentConversationNavigationSubject::ServerToken(server_token) => model
                .entry_for_server_token(&server_token, app)
                .and_then(|entry| model.resolve_entry_copy_link(&entry))
                .or_else(|| Some(server_token.conversation_link())),
        }
    }

    fn resolve_entry_open_action(
        &self,
        entry: &AgentConversationEntry,
        restore_layout: Option<RestoreConversationLayout>,
        app: &AppContext,
    ) -> Option<WorkspaceAction> {
        let active_views_model = ActiveAgentViewsModel::as_ref(app);

        if let Some(conversation_id) = entry.identity.local_conversation_id
            && active_views_model.is_conversation_open(conversation_id, app)
        {
            if let Some(nav_data) = self
                .conversations
                .get(&conversation_id)
                .map(|metadata| &metadata.nav_data)
            {
                return Some(WorkspaceAction::RestoreOrNavigateToConversation {
                    conversation_id,
                    window_id: nav_data.window_id,
                    pane_view_locator: nav_data.pane_view_locator,
                    terminal_view_id: nav_data.terminal_view_id,
                    restore_layout,
                });
            }

            if let Some(terminal_view_id) =
                active_views_model.get_terminal_view_id_for_conversation(conversation_id, app)
            {
                return Some(WorkspaceAction::FocusTerminalViewInWorkspace { terminal_view_id });
            }
        }

        if let Some(conversation_id) = entry.identity.local_conversation_id {
            let nav_data = self
                .conversations
                .get(&conversation_id)
                .map(|metadata| &metadata.nav_data);
            if !entry.backing.has_cloud_data
                || entry.backing.has_local_persisted_data
                || entry.backing.has_loaded_conversation
                || nav_data.is_some()
            {
                return Some(WorkspaceAction::RestoreOrNavigateToConversation {
                    conversation_id,
                    window_id: nav_data.and_then(|nav_data| nav_data.window_id),
                    pane_view_locator: None,
                    terminal_view_id: nav_data.and_then(|nav_data| nav_data.terminal_view_id),
                    restore_layout,
                });
            }
        }

        entry
            .identity
            .server_conversation_token
            .as_ref()
            .map(|token| WorkspaceAction::OpenConversationTranscriptViewer {
                conversation_id: token.clone(),
            })
    }

    fn resolve_entry_copy_link(&self, entry: &AgentConversationEntry) -> Option<String> {
        entry
            .identity
            .server_conversation_token
            .as_ref()
            .map(ServerConversationToken::conversation_link)
    }

    fn entry_for_server_token(
        &self,
        server_token: &ServerConversationToken,
        app: &AppContext,
    ) -> Option<AgentConversationEntry> {
        let history_model = BlocklistAIHistoryModel::as_ref(app);
        let conversation_id = history_model.find_conversation_id_by_server_token(server_token)?;
        self.get_entry_by_id(
            &AgentConversationEntryId::Conversation(conversation_id),
            app,
        )
    }

    fn handle_history_event(
        &mut self,
        event: &BlocklistAIHistoryEvent,
        ctx: &mut ModelContext<Self>,
    ) {
        if !FeatureFlag::InteractiveConversationManagementView.is_enabled() {
            return;
        }
        match event {
            // Events that affect conversation navigation data - need full sync
            BlocklistAIHistoryEvent::StartedNewConversation { .. }
            | BlocklistAIHistoryEvent::SetActiveConversation { .. }
            | BlocklistAIHistoryEvent::AppendedExchange { .. }
            | BlocklistAIHistoryEvent::SplitConversation { .. }
            | BlocklistAIHistoryEvent::RestoredConversations { .. }
            | BlocklistAIHistoryEvent::RemoveConversation { .. }
            | BlocklistAIHistoryEvent::DeletedConversation { .. }
            | BlocklistAIHistoryEvent::ClearedConversationsForTerminalSurface { .. }
            | BlocklistAIHistoryEvent::ClearedActiveConversation { .. }
            => {
                self.sync_conversations(ctx);
            }

            // Status changes - just trigger re-render since status is looked up at render time
            BlocklistAIHistoryEvent::UpdatedConversationStatus {
                update, new_status, ..
            } => {
                let kind = match update {
                    ConversationStatusUpdate::Restored => ConversationUpdateKind::Restored,
                    ConversationStatusUpdate::Changed { prev_status } => {
                        ConversationUpdateKind::StatusSet {
                            prev_filter: AgentRunDisplayStatus::from_conversation_status(
                                prev_status,
                            )
                            .status_filter(),
                            new_filter: AgentRunDisplayStatus::from_conversation_status(new_status)
                                .status_filter(),
                        }
                    }
                };
                ctx.emit(AgentConversationsModelEvent::ConversationUpdated { kind });
            }

            BlocklistAIHistoryEvent::UpdatedConversationTitle { .. } => {
                ctx.emit(AgentConversationsModelEvent::ConversationUpdated {
                    kind: ConversationUpdateKind::TitleChanged,
                });
            }

            // Task/exchange-level changes that don't affect conversation navigation.
            BlocklistAIHistoryEvent::CreatedSubtask { .. }
            | BlocklistAIHistoryEvent::UpgradedTask { .. }
            | BlocklistAIHistoryEvent::ReassignedExchange { .. }
            | BlocklistAIHistoryEvent::UpdatedTodoList { .. }
            | BlocklistAIHistoryEvent::UpdatedAutoexecuteOverride { .. }
            // UpdatedStreamingExchange covers streaming and other exchange-level updates but
            // doesn't change any ConversationNavigationData fields (title comes from
            // UpdateTaskDescription, last_updated uses exchange.start_time which is set at append time).
            | BlocklistAIHistoryEvent::UpdatedStreamingExchange { .. }
            | BlocklistAIHistoryEvent::ConversationTransferredBetweenTerminalSurfaces { .. }
            | BlocklistAIHistoryEvent::ConversationUsageMetadataUpdated { .. }
            | BlocklistAIHistoryEvent::UpdatedConversationMetadata { .. } => {}

            BlocklistAIHistoryEvent::UpdatedConversationArtifacts {
                conversation_id, ..
            } => {
                ctx.emit(AgentConversationsModelEvent::ConversationArtifactsUpdated {
                    conversation_id: *conversation_id,
                });
            }

            BlocklistAIHistoryEvent::ConversationServerTokenAssigned { .. } => {
                ctx.emit(AgentConversationsModelEvent::ConversationUpdated {
                    kind: ConversationUpdateKind::MetadataChanged,
                });
            }
        }
    }

    /// Get raw task data by task ID
    pub fn get_task_data(&self, task_id: &AmbientAgentTaskId) -> Option<AmbientAgentTask> {
        self.tasks.get(task_id).cloned()
    }

    /// Updates a cached task to reflect that execution has started and its
    /// session is now known (from a `run_session_linked` wire event). If the
    /// task is not yet cached, starts a fetch to retrieve it.
    ///
    /// Mutating the cache entry directly avoids a full round-trip while still
    /// giving `decide_child_pane_materialization` the `InProgress` +
    /// `is_sandbox_running=true` + `session_id` it needs to return `AttachLive`
    /// on the next pill click. `TasksUpdated` is emitted so any pending
    /// re-drives fire immediately.
    pub fn update_task_as_running_with_session(
        &mut self,
        task_id: &AmbientAgentTaskId,
        session_id_str: String,
        ctx: &mut ModelContext<Self>,
    ) {
        use crate::ai::ambient_agents::AmbientAgentTaskState;
        if let Some(task) = self.tasks.get_mut(task_id) {
            task.session_id = Some(session_id_str);
            task.is_sandbox_running = true;
            // Only promote to InProgress if still in a queued/pending state;
            // never downgrade a terminal state that may have arrived concurrently.
            match task.state {
                AmbientAgentTaskState::Queued
                | AmbientAgentTaskState::Pending
                | AmbientAgentTaskState::Claimed => {
                    task.state = AmbientAgentTaskState::InProgress;
                }
                _ => {}
            }
            ctx.emit(AgentConversationsModelEvent::TasksUpdated);
        } else {
            // Task not cached yet; start a fetch.
            self.async_fetch_task(task_id, ctx);
        }
    }

    /// Evicts a task from the cache and immediately starts a fresh
    /// `GET /agent/runs/{id}` fetch. Used by the family drain when a terminal
    /// lifecycle event arrives for a child whose cached state is stale (e.g.
    /// still shows `Queued` from the initial discovery fetch). The refreshed
    /// data — including the server conversation token and terminal state —
    /// enables `decide_child_pane_materialization` to return `LoadTranscript`
    /// so subsequent pill clicks load the cloud transcript.
    pub fn evict_and_refetch_task(
        &mut self,
        task_id: &AmbientAgentTaskId,
        ctx: &mut ModelContext<Self>,
    ) {
        self.tasks.remove(task_id);
        self.task_fetch_state.remove(task_id);
        self.async_fetch_task(task_id, ctx);
    }

    /// Get raw task data by task ID, fetching from server if not in memory.
    /// If the task is already in memory, returns it immediately.
    /// If not, spawns an async task to fetch it from the server, stores it in memory,
    /// and emits a TasksUpdated event when ready.
    ///
    /// Multiple unrelated callers (the WASM transcript details panel, the cloud-mode details
    /// panel, and pane-group restoration) can all hit this method, sometimes many times per
    /// second while an agent is streaming. To avoid spamming `GET /api/v1/agent/runs/{id}` we:
    /// * dedupe in-flight fetches per task id,
    /// * back off for [`TRANSIENT_FETCH_FAILURE_COOLDOWN`] after a transient retry chain
    ///   exhausts (5xx/408/429/network), and
    /// * back off for [`PERMANENT_FETCH_FAILURE_COOLDOWN`] after a non-transient failure
    ///   (e.g. 401/403/404). Permanent failures still get retried periodically so we recover
    ///   if permissions change mid-session.
    pub fn get_or_async_fetch_task_data(
        &mut self,
        task_id: &AmbientAgentTaskId,
        ctx: &mut ModelContext<Self>,
    ) -> Option<AmbientAgentTask> {
        // If we already have it, return it
        if let Some(task) = self.tasks.get(task_id) {
            return Some(task.clone());
        }

        self.async_fetch_task(task_id, ctx);
        None
    }

    /// Consult fetch-state guards and spawn a fetch if allowed.
    fn async_fetch_task(&mut self, task_id: &AmbientAgentTaskId, ctx: &mut ModelContext<Self>) {
        match self.task_fetch_state.get(task_id) {
            Some(TaskFetchState::InFlight) => return,
            Some(TaskFetchState::PermanentlyFailed { at, .. }) => {
                if at.elapsed() < PERMANENT_FETCH_FAILURE_COOLDOWN {
                    return;
                }
                // Cooldown has elapsed; clear the entry and fall through to fetch again.
                self.task_fetch_state.remove(task_id);
            }
            Some(TaskFetchState::TransientlyFailed { at, .. }) => {
                if at.elapsed() < TRANSIENT_FETCH_FAILURE_COOLDOWN {
                    return;
                }
                self.task_fetch_state.remove(task_id);
            }
            None => {}
        }

        // Opportunistically purge other expired entries so the map doesn't grow unbounded.
        self.task_fetch_state.retain(|_, state| match state {
            TaskFetchState::TransientlyFailed { at, .. } => {
                at.elapsed() < TRANSIENT_FETCH_FAILURE_COOLDOWN
            }
            TaskFetchState::PermanentlyFailed { at, .. } => {
                at.elapsed() < PERMANENT_FETCH_FAILURE_COOLDOWN
            }
            TaskFetchState::InFlight => true,
        });

        // Otherwise, spawn a task to fetch it. Use the `_when` variant so non-transient errors
        // (e.g. 401/403/404) bail after the first attempt instead of issuing all 4 requests in
        // the retry chain before being cached.
        let ai_client = ServerApiProvider::as_ref(ctx).get_ai_client();
        let task_id_clone = *task_id;

        self.task_fetch_state
            .insert(task_id_clone, TaskFetchState::InFlight);

        ctx.spawn_with_retry_on_error_when(
            move || {
                let ai_client = ai_client.clone();
                async move { ai_client.get_ambient_agent_task(&task_id_clone).await }
            },
            OUT_OF_BAND_REQUEST_RETRY_STRATEGY,
            is_transient_http_error,
            move |model, result, ctx| match result {
                RequestState::RequestSucceeded(task) => {
                    let fetched_id = task.task_id;
                    model.tasks.insert(fetched_id, task);
                    model.task_fetch_state.remove(&fetched_id);
                    ctx.emit(AgentConversationsModelEvent::TasksUpdated);
                }
                RequestState::RequestFailed(e) => {
                    let now = Instant::now();
                    let new_state = if is_transient_http_error(&e) {
                        TaskFetchState::TransientlyFailed { at: now }
                    } else {
                        TaskFetchState::PermanentlyFailed { at: now }
                    };
                    model.task_fetch_state.insert(task_id_clone, new_state);
                    report_error!(e);

                    // On failure, this still emits an update event so that the details panel can re-render with the error message.
                    ctx.emit(AgentConversationsModelEvent::TasksUpdated);
                }
                RequestState::RequestFailedRetryPending(_) => {
                    // Wait for a terminal outcome before updating dedup/backoff state.
                }
            },
        );
    }

    /// Returns all (name, uid) pairs for creators of conversations.
    ///
    /// We use this function to populate the available creator filter list.
    pub fn get_all_creators<S: TeamScope + ?Sized>(
        &self,
        _scope: &S,
        app: &AppContext,
    ) -> Vec<(String, String)> {
        let mut creators: Vec<(String, String)> = Vec::new();

        // Include the current user since they may have local conversations
        let auth_state = AuthStateProvider::as_ref(app).get();
        if let (Some(name), Some(uid)) = (auth_state.display_name(), auth_state.user_id()) {
            creators.push((name, uid.to_string()));
        }

        creators.sort_by(|a, b| a.0.cmp(&b.0));
        creators.dedup_by(|a, b| a.0 == b.0);

        creators
    }

    /// Returns a mapping of environment IDs to display names.
    ///
    /// When multiple environments share the same name, each is disambiguated
    /// as "<name> (<id>)".
    pub fn get_all_environment_ids_and_names<S: TeamScope + ?Sized>(
        &self,
        scope: &S,
        ctx: &AppContext,
    ) -> HashMap<String, String> {
        let mut envs = HashMap::<String, String>::new();
        for task in self
            .tasks
            .values()
            .filter(|task| Self::task_matches_team(task, scope.team_uid()))
        {
            let Some(environment_id) = task
                .agent_config_snapshot
                .as_ref()
                .and_then(|s| s.environment_id.as_deref())
            else {
                continue;
            };

            let Some(server_id) = ServerId::try_from(environment_id).ok() else {
                continue;
            };
            let sync_id = SyncId::ServerId(server_id);
            let Some(env) = CloudAmbientAgentEnvironment::get_by_id(&sync_id, ctx) else {
                continue;
            };
            let env_model = &env.model().string_model;
            envs.insert(environment_id.to_string(), env_model.name.clone());
        }

        // Disambiguate duplicate names by appending the environment ID.
        let mut name_counts = HashMap::<String, usize>::new();
        for name in envs.values() {
            *name_counts.entry(name.clone()).or_default() += 1;
        }
        for (id, name) in &mut envs {
            if name_counts.get(name.as_str()).copied().unwrap_or(0) > 1 {
                *name = format!("{name} ({id})");
            }
        }

        envs
    }
}

#[cfg(test)]
#[path = "agent_conversations_model_tests.rs"]
mod tests;
