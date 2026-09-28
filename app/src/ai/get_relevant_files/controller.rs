use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use ai::index::locations::CodeContextLocation;
use anyhow::anyhow;
use futures_util::stream::AbortHandle;
use warp_errors::report_error;
use warpui::{AppContext, Entity, ModelContext, SingletonEntity};

use crate::ai::agent::{AIAgentActionId, SearchCodebaseResult};
use crate::ai::get_relevant_files::api::{FileContext as FileContextRequest, GetRelevantFiles};
use crate::code::outline::{OutlineStatus, RepoOutlines};
use crate::server::server_api::{AIApiError, ServerApiProvider};
use crate::server::team_scope::RequestTeamScope;

#[derive(Debug)]
pub enum GetRelevantFilesControllerEvent {
    Success {
        action_id: AIAgentActionId,
        result: GetRelevantFilesControllerResult,
    },
    Error {
        action_id: AIAgentActionId,
    },
}

impl GetRelevantFilesControllerEvent {
    pub fn action_id(&self) -> &AIAgentActionId {
        match self {
            GetRelevantFilesControllerEvent::Success { action_id, .. } => action_id,
            GetRelevantFilesControllerEvent::Error { action_id } => action_id,
        }
    }
}

#[derive(Debug)]
pub enum GetRelevantFilesControllerResult {
    Locations(Arc<HashSet<CodeContextLocation>>),
    SearchResult(SearchCodebaseResult),
}

pub enum GetRelevantFilesRequestTarget {
    Local { directory: PathBuf },
}
#[derive(Debug, thiserror::Error)]
pub enum GetRelevantFilesError {
    #[error("Repo outline is still being computed.")]
    Pending,
    #[error("Failed to create outline.")]
    CreateFailed,
    #[error("Failed to create outline.")]
    Missing,
}

/// Controller for GetRelevantFiles action. This is scoped per terminal session.
#[derive(Default)]
pub struct GetRelevantFilesController {
    /// Search requests currently in flight, keyed by the originating action ID.
    /// This allows several SearchCodebase actions to be active at once without newer requests
    /// cancelling unrelated older ones.
    pending_requests: std::collections::HashMap<AIAgentActionId, AbortHandle>,
}

impl GetRelevantFilesController {
    /// Start a new search query based on the repo outline.
    pub fn send_request(
        &mut self,
        target: GetRelevantFilesRequestTarget,
        query: String,
        partial_path_segments: Option<&Vec<String>>,
        action_id: AIAgentActionId,
        team_scope: RequestTeamScope,
        ctx: &mut ModelContext<Self>,
    ) -> Result<(), GetRelevantFilesError> {
        // Cancel any previous request for this action before dispatching.
        self.cancel_request_for_action(&action_id);
        match target {
            GetRelevantFilesRequestTarget::Local { directory } => self.send_local_request(
                &directory,
                query,
                partial_path_segments,
                action_id,
                team_scope,
                ctx,
            ),
        }
    }

    fn send_local_request(
        &mut self,
        directory: &Path,
        query: String,
        partial_path_segments: Option<&Vec<String>>,
        action_id: AIAgentActionId,
        team_scope: RequestTeamScope,
        ctx: &mut ModelContext<Self>,
    ) -> Result<(), GetRelevantFilesError> {
        const MINIMUM_FILE_COUNT_FOR_API_CALL: usize = 2;

        match RepoOutlines::as_ref(ctx).get_outline(directory) {
            Some((OutlineStatus::Complete(outline), base_path)) => {
                let server_api = ServerApiProvider::as_ref(ctx).get();

                let file_outlines = outline.to_file_symbols(partial_path_segments);
                if file_outlines.len() < MINIMUM_FILE_COUNT_FOR_API_CALL {
                    ctx.emit(GetRelevantFilesControllerEvent::Success {
                        action_id,
                        result: GetRelevantFilesControllerResult::Locations(Arc::new(
                            file_outlines
                                .into_iter()
                                .map(|file| {
                                    CodeContextLocation::WholeFile(PathBuf::from(file.path))
                                })
                                .collect(),
                        )),
                    });
                } else {
                    let outline_request = GetRelevantFiles {
                        query,
                        files: file_outlines
                            .into_iter()
                            .map(|outline| FileContextRequest {
                                path: outline.path,
                                symbols: outline.symbols,
                            })
                            .collect(),
                    };
                    let action_id_clone = action_id.clone();
                    let request_abort_handle = ctx
                        .spawn(
                            async move {
                                let response = server_api
                                    .get_relevant_files(&outline_request, team_scope)
                                    .await?;
                                Ok(Arc::new(
                                    response
                                        .relevant_file_paths
                                        .into_iter()
                                        .filter_map(|path| {
                                            let file_path = base_path.join(path);
                                            // Validate the returned file paths.
                                            if file_path.exists() {
                                                Some(CodeContextLocation::WholeFile(file_path))
                                            } else {
                                                None
                                            }
                                        })
                                        .collect(),
                                ))
                            },
                            move |me,
                                  relevant_file_paths: Result<
                                Arc<HashSet<CodeContextLocation>>,
                                AIApiError,
                            >,
                                  ctx| {
                                me.handle_relevant_file_paths_result(
                                    relevant_file_paths.map_err(|e| anyhow!(e)),
                                    action_id_clone,
                                    ctx,
                                )
                            },
                        )
                        .abort_handle();
                    self.pending_requests
                        .insert(action_id, request_abort_handle);
                }
                Ok(())
            }
            Some((OutlineStatus::Pending, _)) => Err(GetRelevantFilesError::Pending),
            Some((OutlineStatus::Failed, _)) => Err(GetRelevantFilesError::CreateFailed),
            None => Err(GetRelevantFilesError::Missing),
        }
    }

    fn handle_relevant_file_paths_result(
        &mut self,
        relevant_file_locations: anyhow::Result<Arc<HashSet<CodeContextLocation>>>,
        action_id: AIAgentActionId,
        ctx: &mut ModelContext<Self>,
    ) {
        if self.pending_requests.remove(&action_id).is_none() {
            return;
        }
        match relevant_file_locations {
            Ok(relevant_file_locations) => {
                ctx.emit(GetRelevantFilesControllerEvent::Success {
                    action_id,
                    result: GetRelevantFilesControllerResult::Locations(relevant_file_locations),
                });
            }
            Err(e) => {
                report_error!(anyhow!(e).context("get_relevant_files failed"));
                ctx.emit(GetRelevantFilesControllerEvent::Error { action_id });
            }
        };
    }

    /// Returns the path to the root directory for a codebase search where pwd is `directory`.
    pub fn root_directory_for_search(&self, directory: &Path, app: &AppContext) -> Option<PathBuf> {
        RepoOutlines::as_ref(app)
            .get_outline(directory)
            .map(|(_, root)| root)
    }

    pub fn cancel_request_for_action(&mut self, action_id: &AIAgentActionId) {
        if let Some(abort_handle) = self.pending_requests.remove(action_id) {
            abort_handle.abort();
        }
    }
}

impl Entity for GetRelevantFilesController {
    type Event = GetRelevantFilesControllerEvent;
}
