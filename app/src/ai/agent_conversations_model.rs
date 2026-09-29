#[allow(dead_code)]
pub mod entry;
mod query;

use std::collections::{HashMap, HashSet};

pub use entry::{AgentConversationEntry, AgentConversationEntryId};
use fuzzy_match::FuzzyMatchResult;
use itertools::Itertools;
#[cfg(test)]
use query::query_conversation_entries;
use warp_core::execution_mode::AppExecutionMode;
use warp_core::features::FeatureFlag;
use warp_core::ui::theme::WarpTheme;
use warp_core::ui::theme::color::internal_colors;
use warpui::color::ColorU;
use warpui::{AppContext, Entity, ModelContext, SingletonEntity};

use crate::ai::active_agent_views_model::ActiveAgentViewsModel;
use crate::ai::agent::conversation::{AIConversationId, ConversationStatus};
use crate::ai::blocklist::{BlocklistAIHistoryEvent, BlocklistAIHistoryModel};
use crate::ai::conversation_navigation::ConversationNavigationData;
use crate::ui_components::icons::Icon;
use crate::workspaces::user_workspaces::TeamScope;

/// A normalized conversation entry paired with optional title-match metadata.
pub struct AgentConversationQueryResult {
    pub entry: AgentConversationEntry,
    pub title_match: Option<FuzzyMatchResult>,
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

/// This model serves as a unified interface for reading local agent conversations.
pub struct AgentConversationsModel {
    /// A map of conversation IDs to local conversations.
    conversations: HashMap<AIConversationId, ConversationMetadata>,
}

pub enum AgentConversationsModelEvent {
    /// Conversation status, title or metadata was updated.
    ConversationUpdated,
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
                conversations: HashMap::new(),
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
            conversations: HashMap::new(),
        };

        // Only sync local conversations if we're not in CLI mode.
        if AppExecutionMode::as_ref(ctx).can_fetch_agent_runs_for_management() {
            model.sync_conversations(ctx);
        }
        model
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
    }

    /// Returns normalized, owned entries for navigation surfaces, most recently updated first.
    pub fn get_entries<S: TeamScope + ?Sized>(
        &self,
        _scope: &S,
        app: &AppContext,
    ) -> Vec<AgentConversationEntry> {
        self.entries(app)
            .into_iter()
            .sorted_by(|a, b| b.display.last_updated.cmp(&a.display.last_updated))
            .collect()
    }

    fn entries(&self, app: &AppContext) -> Vec<AgentConversationEntry> {
        let history_model = BlocklistAIHistoryModel::as_ref(app);
        let mut entries = Vec::new();
        let mut emitted_conversation_ids = HashSet::new();

        for metadata in self.conversations.values() {
            let conversation_id = metadata.nav_data.id;
            let entry = entry::entry_for_conversation(metadata, history_model);
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
            .map(|metadata| entry::entry_for_conversation(metadata, history_model))
            .or_else(|| {
                history_model
                    .get_conversation_metadata(conversation_id)
                    .map(|metadata| {
                        let nav_data =
                            ConversationNavigationData::from_historical_conversation_metadata(
                                metadata,
                            );
                        entry::entry_for_historical_metadata(metadata, nav_data, history_model)
                    })
            })
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

            // Status and title changes: the terminal view re-renders since these are looked up at
            // render time.
            BlocklistAIHistoryEvent::UpdatedConversationStatus { .. }
            | BlocklistAIHistoryEvent::UpdatedConversationTitle { .. }
            | BlocklistAIHistoryEvent::ConversationServerTokenAssigned { .. } => {
                ctx.emit(AgentConversationsModelEvent::ConversationUpdated);
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
            | BlocklistAIHistoryEvent::UpdatedConversationArtifacts { .. }
            | BlocklistAIHistoryEvent::UpdatedConversationMetadata { .. } => {}
        }
    }
}

#[cfg(test)]
#[path = "agent_conversations_model_tests.rs"]
mod tests;
