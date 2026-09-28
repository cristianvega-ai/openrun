//! Prepares orchestrated remote-child launches and classifies their startup errors.
//!
//! This module owns frontend-neutral request construction and startup issue semantics;
//! frontend-specific callers remain responsible for lifecycle state and presentation.
use ai::harness::Harness;
use warpui::{AppContext, SingletonEntity as _};

use crate::ai::agent::UserQueryMode;
use crate::ai::ambient_agents::task::{
    HarnessAuthSecretsConfig, HarnessConfig, normalize_orchestrator_agent_name,
};
use crate::ai::ambient_agents::{
    OUT_OF_CREDITS_TASK_FAILURE_MESSAGE, SERVER_OVERLOADED_TASK_FAILURE_MESSAGE, github_auth_url,
};
use crate::ai::blocklist::StartAgentRequest;
use crate::server::server_api::ai::{AgentConfigSnapshot, SpawnAgentRequest};
use crate::server::server_api::{AIApiError, ClientError, CloudAgentCapacityError};
use crate::server::team_scope::RequestTeamScope;
use crate::settings::PrivacySettings;
use crate::workspaces::user_workspaces::UserWorkspaces;
use crate::workspaces::workspace::AdminEnablementSetting;

/// Remote execution fields carried by [`crate::ai::agent::StartAgentExecutionMode`].
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RemoteChildLaunchConfig {
    pub environment_id: String,
    pub model_id: String,
    pub worker_host: String,
    pub harness_type: String,
    pub title: String,
    pub auth_secret_name: Option<String>,
    pub runner_id: String,
    pub agent_identity_uid: Option<String>,
}

impl RemoteChildLaunchConfig {
    pub fn orchestration_harness(&self) -> Harness {
        if self.harness_type.trim().is_empty() {
            Harness::Oz
        } else {
            Harness::parse_orchestration_harness(&self.harness_type).unwrap_or(Harness::Unknown)
        }
    }
}

/// Frontend-neutral output used to launch one remote child.
#[derive(Clone, Debug)]
pub struct PreparedRemoteChildLaunch {
    pub spawn_request: SpawnAgentRequest,
}

/// Failure while constructing the remote child request, before calling the server.
#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
pub enum PrepareRemoteChildLaunchError {
    #[error("Remote child agents require the parent run_id to be available.")]
    MissingParentRunId,
}

impl PrepareRemoteChildLaunchError {
    pub fn user_message(&self) -> String {
        self.to_string()
    }
}

/// A recoverable startup condition that requires user action.
///
/// The GUI represents this as `ambient_agent::Status::NeedsGithubAuth`.
/// Orchestrated children retain their surface so the user can follow the
/// remediation link, but the original child launch still resolves as failed.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CloudAgentStartupBlocker {
    GitHubAuthRequired { message: String, auth_url: String },
}

/// A terminal cloud-agent startup failure.
///
/// The GUI represents these as `ambient_agent::Status::Failed`. Unlike a
/// blocker, a failure has no remediation action that requires retaining an
/// optimistic orchestrated-child surface.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CloudAgentStartupFailure {
    Capacity { message: String },
    OutOfCredits { message: String },
    ServerOverloaded { message: String },
    Other { message: String },
}

/// Whether authentication can resume a retained launch or requires the user to rerun it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CloudAgentStartupAuthFlow {
    RetryRetainedRequest,
}

/// Renderer-neutral content for a cloud-agent startup card.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CloudAgentStartupPresentation {
    pub title: &'static str,
    pub detail: String,
    pub action_label: Option<&'static str>,
    pub primary_url: Option<String>,
}

impl CloudAgentStartupPresentation {
    pub fn failure(message: impl Into<String>) -> Self {
        Self {
            title: "Failed to start environment",
            detail: message.into(),
            action_label: None,
            primary_url: None,
        }
    }

    pub fn github_auth(auth_url: impl Into<String>, flow: CloudAgentStartupAuthFlow) -> Self {
        let detail = match flow {
            CloudAgentStartupAuthFlow::RetryRetainedRequest => {
                "Please authenticate with GitHub to continue"
            }
        };
        Self {
            title: "GitHub Authentication Required",
            detail: detail.to_string(),
            action_label: Some("Authenticate with GitHub"),
            primary_url: Some(auth_url.into()),
        }
    }
}
/// Shared interpretation of an error returned while starting a cloud agent.
///
/// This distinction preserves the existing orchestrated-child contract:
/// blockers remain visible for user action, while terminal failures are
/// eligible for failed-launch cleanup.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CloudAgentStartupIssue {
    Blocked(CloudAgentStartupBlocker),
    Failed(CloudAgentStartupFailure),
}

/// Builds the public API request for one remote child without owning frontend lifecycle state.
pub fn prepare_remote_child_launch(
    request: &StartAgentRequest,
    config: RemoteChildLaunchConfig,
    team_scope: RequestTeamScope,
    ctx: &AppContext,
) -> Result<PreparedRemoteChildLaunch, PrepareRemoteChildLaunchError> {
    let orchestration_harness = config.orchestration_harness();
    let RemoteChildLaunchConfig {
        environment_id,
        model_id,
        worker_host,
        harness_type,
        title,
        auth_secret_name,
        runner_id,
        agent_identity_uid,
    } = config;
    let Some(parent_run_id) = request.parent_run_id.clone() else {
        return Err(PrepareRemoteChildLaunchError::MissingParentRunId);
    };
    let agent_name = normalize_orchestrator_agent_name(&request.name);
    let environment_id = Some(environment_id).filter(|id| !id.trim().is_empty());
    let harness_override = if harness_type.is_empty() {
        None
    } else {
        match Harness::from_name(&harness_type) {
            Some(harness) => Some(HarnessConfig::from_harness_type(harness)),
            None => {
                log::warn!(
                    "Unknown child-agent harness type: {harness_type:?}; omitting harness override so the server picks its default"
                );
                None
            }
        }
    };
    let harness_auth_secrets = auth_secret_name
        .filter(|name| !name.trim().is_empty())
        .and_then(|name| match orchestration_harness {
            Harness::Claude => Some(HarnessAuthSecretsConfig {
                claude_auth_secret_name: Some(name),
                codex_auth_secret_name: None,
            }),
            Harness::Codex => Some(HarnessAuthSecretsConfig {
                claude_auth_secret_name: None,
                codex_auth_secret_name: Some(name),
            }),
            Harness::Oz | Harness::OpenCode | Harness::Gemini | Harness::Unknown => None,
        });
    let spawn_request = SpawnAgentRequest {
        prompt: Some(request.prompt.clone()),
        mode: UserQueryMode::Normal,
        config: Some(AgentConfigSnapshot {
            name: agent_name,
            environment_id,
            runner_id: (!runner_id.is_empty()).then_some(runner_id),
            model_id: (!model_id.is_empty()).then_some(model_id),
            worker_host: (!worker_host.is_empty()).then_some(worker_host),
            harness: harness_override,
            harness_auth_secrets,
            ..Default::default()
        }),
        title: (!title.is_empty()).then_some(title),
        team: Some(team_scope.team_uid().is_some()),
        skill: None,
        attachments: Vec::new(),
        interactive: Some(true),
        parent_run_id: Some(parent_run_id),
        runtime_skills: Vec::new(),
        referenced_attachments: Vec::new(),
        conversation_id: None,
        initial_snapshot_token: None,
        agent_identity_uid: agent_identity_uid.filter(|uid| !uid.trim().is_empty()),
        snapshot_disabled: should_disable_snapshot(ctx).then_some(true),
        orchestration_handoff: None,
    };
    Ok(PreparedRemoteChildLaunch { spawn_request })
}

/// Maps server/client launch failures into shared startup presentation.
pub fn classify_cloud_agent_startup_error(error: &anyhow::Error) -> CloudAgentStartupIssue {
    if let Some(client_error) = error.downcast_ref::<ClientError>()
        && let Some(auth_url) = &client_error.auth_url
    {
        return CloudAgentStartupIssue::Blocked(CloudAgentStartupBlocker::GitHubAuthRequired {
            message: client_error.error.clone(),
            auth_url: github_auth_url::cloud_setup_auth_url_with_next(auth_url),
        });
    }
    if let Some(capacity_error) = error.downcast_ref::<CloudAgentCapacityError>() {
        return CloudAgentStartupIssue::Failed(CloudAgentStartupFailure::Capacity {
            message: capacity_error.error.clone(),
        });
    }
    if let Some(ai_api_error) = error.downcast_ref::<AIApiError>() {
        match ai_api_error {
            AIApiError::QuotaLimit {
                user_display_message,
            } => {
                return CloudAgentStartupIssue::Failed(CloudAgentStartupFailure::OutOfCredits {
                    message: user_display_message
                        .clone()
                        .unwrap_or_else(|| OUT_OF_CREDITS_TASK_FAILURE_MESSAGE.to_string()),
                });
            }
            AIApiError::ServerOverloaded => {
                return CloudAgentStartupIssue::Failed(
                    CloudAgentStartupFailure::ServerOverloaded {
                        message: SERVER_OVERLOADED_TASK_FAILURE_MESSAGE.to_string(),
                    },
                );
            }
            AIApiError::Transport(_)
            | AIApiError::Deserialization(_)
            | AIApiError::NoContextFound
            | AIApiError::ErrorStatus(_, _)
            | AIApiError::Other(_)
            | AIApiError::Stream { .. }
            | AIApiError::UnexpectedEof
            | AIApiError::GrokSubscriptionTokenRefreshFailed => {}
        }
    }
    CloudAgentStartupIssue::Failed(CloudAgentStartupFailure::Other {
        message: error.to_string(),
    })
}

pub(crate) fn should_disable_snapshot(ctx: &AppContext) -> bool {
    let privacy = PrivacySettings::as_ref(ctx);
    if !privacy.is_cloud_conversation_storage_enabled {
        return true;
    }
    matches!(
        UserWorkspaces::as_ref(ctx).get_cloud_conversation_storage_enablement_setting(),
        AdminEnablementSetting::Disable
    )
}

#[cfg(test)]
#[path = "remote_child_tests.rs"]
mod tests;
