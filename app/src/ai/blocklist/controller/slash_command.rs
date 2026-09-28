use std::sync::Arc;

use warp_core::features::FeatureFlag;
use warp_errors::report_error;
use warpui::{AppContext, ModelContext, SingletonEntity};

use super::response_stream::RecoveryBudget;
use super::{
    BlocklistAIController, BlocklistAIControllerEvent, RequestInput, input_context_for_request,
};
use crate::BlocklistAIHistoryModel;
use crate::ai::agent::conversation::AIConversationId;
use crate::ai::agent::{
    AIAgentContext, AIAgentInput, CancellationReason, CloneRepositoryURL, EntrypointType,
    RequestMetadata,
};
use crate::ai::blocklist::agent_view::AgentViewEntryOrigin;
use crate::ai::blocklist::queued_query::QueuedQueryId;
use crate::search::slash_command_menu::static_commands::commands;
use crate::terminal::input::slash_commands::SlashCommandTrigger;
use crate::workspaces::user_workspaces::ResolvedTeamScope;

pub enum SlashCommandRequest {
    CreateNewProject {
        query: String,
    },
    CloneRepository {
        url: String,
    },
    CreateEnvironment {
        repos: Vec<String>,
        use_current_dir: bool,
    },
    Summarize {
        prompt: Option<String>,
    },
}

impl SlashCommandRequest {
    /// Parses user input into a SlashCommandRequest for slash commands that are handled
    /// via the AI query flow (as opposed to action-based slash commands handled in input.rs).
    pub fn from_query(query: &str) -> Option<SlashCommandRequest> {
        // Check if query starts with /compact and route to summarize conversation
        if let Some(prompt) = query.strip_prefix(commands::COMPACT.name) {
            return Some(Self::Summarize {
                prompt: prompt.strip_prefix(' ').map(String::from),
            });
        }

        None
    }

    pub(super) fn send_request(
        self,
        controller: &mut BlocklistAIController,
        queued_query_id: Option<QueuedQueryId>,
        conversation_id_override: Option<AIConversationId>,
        ctx: &mut ModelContext<BlocklistAIController>,
    ) {
        let is_queued_prompt = queued_query_id.is_some();
        // A fired queued prompt carries the conversation it was queued on; use it directly
        // instead of re-deriving from the current UI selection (which may point at a different
        // conversation the user navigated to). Falls back to the selection for direct sends.
        let conversation_id =
            conversation_id_override.or_else(|| self.conversation_id(controller, ctx));
        let context = input_context_for_request(
            false,
            controller.context_model.as_ref(ctx),
            controller.active_session.as_ref(ctx),
            Vec::new(),
            ctx,
        );
        let entrypoint = self.entrypoint();
        let is_summarize = matches!(self, Self::Summarize { .. });
        let inputs = self.input(context);
        if inputs.is_empty() {
            return;
        }
        let active_conversation_id = BlocklistAIHistoryModel::as_ref(ctx)
            .active_conversation_id(controller.terminal_surface_id);

        // If no existing conversation, create a new one.
        // When AgentView is enabled, enter agent view which creates the conversation
        // and ensures AI blocks render correctly in the agent view.
        let Some(conversation_id) = conversation_id.or_else(|| {
            if FeatureFlag::AgentView.is_enabled() {
                controller.context_model.update(ctx, |context_model, ctx| {
                    context_model
                        .try_start_new_conversation(
                            AgentViewEntryOrigin::SlashCommand {
                                trigger: SlashCommandTrigger::input(),
                            },
                            ctx,
                        )
                        .ok()
                })
            } else {
                Some(controller.start_new_conversation_for_request(ctx).id())
            }
        }) else {
            report_error!("Failed to get conversation ID for slash command request");
            return;
        };

        let cancellation_reason = CancellationReason::FollowUpSubmitted {
            is_for_same_conversation: active_conversation_id
                .is_some_and(|id| id == conversation_id),
        };
        if let Some(active_conversation_id) = active_conversation_id {
            controller.cancel_conversation_progress(
                active_conversation_id,
                cancellation_reason,
                ctx,
            );
        }

        let Some(conversation) =
            BlocklistAIHistoryModel::as_ref(ctx).conversation(&conversation_id)
        else {
            return;
        };
        let task_id = conversation.get_root_task_id().clone();

        let scope = ResolvedTeamScope::from_scope(&controller.team_context(ctx));
        let request_input = RequestInput::for_task(
            inputs,
            task_id,
            &controller.active_session,
            controller.get_current_response_initiator(),
            conversation_id,
            controller.terminal_surface_id,
            &scope,
            ctx,
        );
        let model_id = request_input.model_id.clone();

        match controller.send_request_input(
            request_input,
            Some(RequestMetadata {
                is_autodetected_user_query: false,
                entrypoint,
                is_auto_resume_after_error: false,
            }),
            RecoveryBudget::fresh(),
            is_queued_prompt,
            ctx,
        ) {
            Ok((_, stream_id)) => {
                // Emit SentRequest event to trigger buffer clearing
                if is_summarize {
                    ctx.emit(BlocklistAIControllerEvent::SentRequest {
                        contains_user_query: true,
                        is_queued_prompt,
                        model_id,
                        stream_id,
                    });
                }
            }
            Err(e) => report_error!(e.context("Failed to send agent slash command request")),
        }
    }

    pub(super) fn conversation_id(
        &self,
        controller: &BlocklistAIController,
        app: &AppContext,
    ) -> Option<AIConversationId> {
        match self {
            Self::Summarize { .. } | Self::CreateEnvironment { .. } => controller
                .context_model
                .as_ref(app)
                .selected_conversation_id(app),
            _ => None,
        }
    }

    fn input(self, context: Arc<[AIAgentContext]>) -> Vec<AIAgentInput> {
        match self {
            SlashCommandRequest::CreateNewProject { query } => {
                vec![AIAgentInput::CreateNewProject { query, context }]
            }
            SlashCommandRequest::CloneRepository { url } => {
                vec![AIAgentInput::CloneRepository {
                    clone_repo_url: CloneRepositoryURL::new(url),
                    context,
                }]
            }
            SlashCommandRequest::CreateEnvironment {
                mut repos,
                use_current_dir,
            } => {
                let display_query = if repos.is_empty() {
                    "/create-environment".to_string()
                } else {
                    format!("/create-environment {}", repos.join(" "))
                };

                // Add "." to represent the current working directory
                if use_current_dir {
                    repos.push(String::from("."));
                }

                vec![AIAgentInput::CreateEnvironment {
                    context,
                    display_query: Some(display_query),
                    repo_paths: repos,
                }]
            }
            SlashCommandRequest::Summarize { prompt, .. } => {
                vec![AIAgentInput::SummarizeConversation { prompt, context }]
            }
        }
    }

    fn entrypoint(&self) -> EntrypointType {
        match self {
            SlashCommandRequest::CloneRepository { .. } => EntrypointType::CloneRepository,
            SlashCommandRequest::CreateNewProject { .. }
            | SlashCommandRequest::CreateEnvironment { .. }
            | SlashCommandRequest::Summarize { .. } => EntrypointType::UserInitiated,
        }
    }
}
