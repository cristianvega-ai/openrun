use uuid::Uuid;
use warp_errors::report_error;
use warpui::{SingletonEntity, ViewContext};

use super::materialization::{ChildPaneMaterialization, decide_child_pane_materialization};
use crate::ai::agent::api::ServerConversationToken;
use crate::ai::agent::conversation::{AIConversation, AIConversationId};
use crate::ai::agent_conversations_model::AgentConversationsModel;
use crate::ai::ambient_agents::{AmbientAgentTask, AmbientAgentTaskId};
use crate::ai::blocklist::BlocklistAIHistoryModel;
use crate::ai::blocklist::agent_view::AgentViewEntryOrigin;
use crate::pane_group::{PaneGroup, PaneId, TerminalPane, TerminalViewResources};
use crate::terminal::model::terminal_model::ConversationTranscriptViewerStatus;
use crate::terminal::view::load_ai_conversation::{
    RestoreConversationEntryBehavior, RestoredAIConversation,
};

impl PaneGroup {
    /// Materializes the pane for a placeholder child conversation from its
    /// [`AmbientAgentTask`](crate::ai::ambient_agents::AmbientAgentTask),
    /// leaving a loading pane in place while the task is still being fetched.
    ///
    /// Idempotent: repeat calls for a placeholder that already has a live
    /// tracked pane are skipped rather than creating a duplicate pane and
    /// orphaning the first.
    pub(in crate::pane_group) fn materialize_child_pane(
        &mut self,
        child_conversation: AIConversation,
        ctx: &mut ViewContext<Self>,
    ) {
        let child_id = child_conversation.id();

        if let Some(existing_pane_id) = self.child_agent_panes.get(&child_id).copied()
            && self.has_pane_id(existing_pane_id)
        {
            return;
        }

        let Some(task_id) = child_conversation.task_id() else {
            log::warn!("Cannot restore remote child conversation {child_id:?} without a task ID");
            return;
        };
        let task = AgentConversationsModel::handle(ctx).update(ctx, |model, ctx| {
            model.get_or_async_fetch_task_data(&task_id, ctx)
        });

        let Some(task) = task else {
            // Show the child loading presentation rather than the generic
            // cloud-agent composing zero state, and register for a re-drive
            // once the task fetch lands.
            if self
                .create_child_loading_placeholder(
                    child_conversation,
                    AgentViewEntryOrigin::ChildAgent,
                    ctx,
                )
                .is_none()
            {
                return;
            }
            self.pending_child_hydrations.insert(task_id, child_id);
            self.ensure_child_task_update_subscription(ctx);
            return;
        };

        self.apply_child_pane_materialization(child_conversation, task, ctx);
    }

    /// Applies the materialization decision for a child whose task snapshot is
    /// available: `LoadTranscript` fetches and merges the cloud transcript, and
    /// `Pending` leaves a loading placeholder in place until fresher task data arrives.
    fn apply_child_pane_materialization(
        &mut self,
        child_conversation: AIConversation,
        task: AmbientAgentTask,
        ctx: &mut ViewContext<Self>,
    ) {
        match decide_child_pane_materialization(&task) {
            ChildPaneMaterialization::LoadTranscript { server_token } => {
                let child_id = child_conversation.id();
                let task_id = task.task_id;
                let pane_id = self
                    .child_agent_panes
                    .get(&child_id)
                    .copied()
                    .filter(|pane_id| self.has_pane_id(*pane_id))
                    .or_else(|| {
                        self.create_child_loading_placeholder(
                            child_conversation,
                            AgentViewEntryOrigin::ChildAgent,
                            ctx,
                        )
                    });
                let Some(pane_id) = pane_id else {
                    return;
                };
                self.pending_child_hydrations.remove(&task_id);
                self.hydrate_child_transcript(pane_id, child_id, task_id, server_token, ctx);
            }
            ChildPaneMaterialization::Pending => {
                let child_id = child_conversation.id();
                let task_id = task.task_id;
                if !self
                    .child_agent_panes
                    .get(&child_id)
                    .is_some_and(|pane_id| self.has_pane_id(*pane_id))
                {
                    let _ = self.create_child_loading_placeholder(
                        child_conversation,
                        AgentViewEntryOrigin::ChildAgent,
                        ctx,
                    );
                }
                self.pending_child_hydrations.insert(task_id, child_id);
                self.ensure_child_task_update_subscription(ctx);
            }
        }
    }

    /// Loads a completed child conversation's cloud transcript and restores it as a
    /// passive transcript.
    fn hydrate_child_transcript(
        &mut self,
        pane_id: PaneId,
        child_id: AIConversationId,
        task_id: AmbientAgentTaskId,
        server_token: ServerConversationToken,
        ctx: &mut ViewContext<Self>,
    ) {
        let history_handle = BlocklistAIHistoryModel::handle(ctx);
        let future = history_handle.update(ctx, |history_model, ctx| {
            history_model.load_conversation_by_server_token(&server_token, ctx)
        });
        ctx.spawn(future, move |group, conversation, ctx| {
            let still_canonical = group
                .child_agent_panes
                .get(&child_id)
                .copied()
                .is_some_and(|p| p == pane_id && group.has_pane_id(p));
            if !still_canonical {
                return;
            }
            // The pane may have been swapped to another conversation while
            // the fetch was in flight; don't overwrite what it now shows.
            let active_conversation = group
                .terminal_view_from_pane_id(pane_id, ctx)
                .and_then(|view| view.as_ref(ctx).active_conversation_id(ctx));
            if active_conversation != Some(child_id) {
                return;
            }
            let merged = match conversation {
                Some(cloud_conversation) => {
                    let tasks: Vec<warp_multi_agent_api::Task> = cloud_conversation
                        .all_tasks()
                        .filter_map(|task| task.source().cloned())
                        .collect();
                    match BlocklistAIHistoryModel::handle(ctx).update(ctx, |history, _| {
                        history.hydrate_remote_child_placeholder_with_cloud_transcript(
                            child_id,
                            tasks,
                            cloud_conversation,
                        )
                    }) {
                        Ok(merged) => merged,
                        Err(err) => {
                            log::warn!(
                                "child transcript upgrade merge-error \
                                 child_conversation_id={child_id:?} error={err:#}"
                            );
                            return;
                        }
                    }
                }
                None => {
                    log::warn!(
                        "child transcript upgrade fetch-empty \
                         child_conversation_id={child_id:?}"
                    );
                    // Re-queue without evicting the task so the retry is
                    // driven by the normal TasksUpdated cadence rather than
                    // firing immediately on every round-trip. Evicting would
                    // create an unbounded loop on permanent failures such as
                    // a 403 from an Observer that can see the task row but
                    // not the conversation transcript.
                    group.pending_child_hydrations.insert(task_id, child_id);
                    return;
                }
            };

            group.restore_child_passive_transcript(pane_id, child_id, merged, ctx);
        });
    }

    /// Restores a child transcript in place without enabling continuation.
    fn restore_child_passive_transcript(
        &mut self,
        pane_id: PaneId,
        child_id: AIConversationId,
        merged: AIConversation,
        ctx: &mut ViewContext<Self>,
    ) {
        if let Some(terminal_manager) = self
            .terminal_session_by_id(pane_id)
            .map(|session| session.terminal_manager(ctx))
        {
            terminal_manager.update(ctx, |manager, _ctx| {
                let model_handle = manager.model();
                let mut model = model_handle.lock();
                model.set_conversation_transcript_viewer_status(Some(
                    ConversationTranscriptViewerStatus::ViewingLocalConversation,
                ));
            });
        }
        if let Some(terminal_view) = self.terminal_view_from_pane_id(pane_id, ctx) {
            BlocklistAIHistoryModel::handle(ctx).update(ctx, |history, _ctx| {
                history.mark_terminal_surface_as_conversation_transcript_viewer(terminal_view.id());
            });
            terminal_view.update(ctx, |view, ctx| {
                view.set_orchestration_child_live_unavailable(false, ctx);
                view.restore_conversation_after_view_creation(
                    RestoredAIConversation::new(merged),
                    true,
                    RestoreConversationEntryBehavior::PreserveAgentViewState,
                    ctx,
                );
            });
        }
        self.child_agent_panes.insert(child_id, pane_id);
    }

    /// Renders the shared loading placeholder presentation used while a child
    /// has neither an attachable session nor a loadable transcript.
    pub(in crate::pane_group) fn create_child_loading_placeholder(
        &mut self,
        child_conversation: AIConversation,
        origin: AgentViewEntryOrigin,
        ctx: &mut ViewContext<Self>,
    ) -> Option<PaneId> {
        let child_id = child_conversation.id();
        let resources = TerminalViewResources {
            tips_completed: self.tips_completed.clone(),
            server_api: self.server_api.clone(),
            model_event_sender: self.model_event_sender.clone(),
        };
        let view_size = Self::estimated_view_bounds(ctx).size();
        let (loading_view, loading_manager) = Self::create_loading_terminal_manager_and_view(
            resources,
            view_size,
            ctx.window_id(),
            ctx,
        );
        let pane_data = TerminalPane::new(
            Uuid::new_v4().as_bytes().to_vec(),
            loading_manager,
            loading_view.clone(),
            self.model_event_sender.clone(),
            ctx,
        );
        let new_pane_id = pane_data.terminal_pane_id();
        if self
            .attach_child_pane_off_tree(Box::new(pane_data), ctx)
            .is_none()
        {
            report_error!(
                "create_child_loading_placeholder: failed to attach child loading pane",
                extra: { "child_id" => ?child_id }
            );
            return None;
        }

        // Entering agent view is what makes the pill bar render; the loading
        // view keeps the output area a spinner until hydration completes.
        loading_view.update(ctx, |terminal_view, ctx| {
            terminal_view.restore_conversation_after_view_creation(
                RestoredAIConversation::new(child_conversation),
                true,
                RestoreConversationEntryBehavior::PreserveAgentViewState,
                ctx,
            );
            terminal_view.enter_agent_view(None, Some(child_id), origin, ctx);
        });

        self.child_agent_panes.insert(child_id, new_pane_id.into());
        Some(new_pane_id.into())
    }

    /// Re-drives child panes after task metadata changes. Terminal tasks upgrade
    /// the existing pane to a passive transcript.
    pub(in crate::pane_group) fn process_pending_child_hydrations(
        &mut self,
        ctx: &mut ViewContext<Self>,
    ) {
        if self.pending_child_hydrations.is_empty() {
            return;
        }

        let ready_tasks: Vec<_> = self
            .pending_child_hydrations
            .keys()
            .filter(|task_id| {
                AgentConversationsModel::as_ref(ctx)
                    .get_task_data(task_id)
                    .is_some()
            })
            .copied()
            .collect();

        for task_id in ready_tasks {
            let Some(child_id) = self.pending_child_hydrations.remove(&task_id) else {
                continue;
            };
            let Some(task) = AgentConversationsModel::as_ref(ctx).get_task_data(&task_id) else {
                continue;
            };
            let Some(pane_id) = self
                .child_agent_panes
                .get(&child_id)
                .copied()
                .filter(|pane_id| self.has_pane_id(*pane_id))
            else {
                continue;
            };

            match decide_child_pane_materialization(&task) {
                ChildPaneMaterialization::LoadTranscript { server_token } => {
                    self.hydrate_child_transcript(pane_id, child_id, task_id, server_token, ctx);
                }
                ChildPaneMaterialization::Pending => {
                    self.pending_child_hydrations.insert(task_id, child_id);
                }
            }
        }
    }
}
