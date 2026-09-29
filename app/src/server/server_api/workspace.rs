use anyhow::{Result, anyhow};
use async_trait::async_trait;
use cynic::MutationBuilder;
#[cfg(test)]
use mockall::{automock, predicate::*};
use warp_graphql::mutations::remove_user_from_workspace::{
    RemoveUserFromWorkspace, RemoveUserFromWorkspaceInput, RemoveUserFromWorkspaceResult,
    RemoveUserFromWorkspaceVariables,
};

use super::ServerApi;
use super::team::TeamClient;
use crate::auth::UserUid;
use crate::server::graphql::{get_request_context, get_user_facing_error_message};
use crate::workspaces::user_workspaces::WorkspacesMetadataResponse;
use crate::workspaces::workspace::WorkspaceUid;
use cloud_objects::cloud_object::CloudObjectEventEntrypoint;

#[cfg_attr(test, automock)]
#[cfg_attr(not(target_family = "wasm"), async_trait)]
#[cfg_attr(target_family = "wasm", async_trait(?Send))]
pub trait WorkspaceClient: 'static + Send + Sync {
    async fn remove_user_from_workspace(
        &self,
        user_uid: UserUid,
        workspace_uid: WorkspaceUid,
        entrypoint: CloudObjectEventEntrypoint,
    ) -> Result<WorkspacesMetadataResponse>;
}

#[cfg_attr(not(target_family = "wasm"), async_trait)]
#[cfg_attr(target_family = "wasm", async_trait(?Send))]
impl WorkspaceClient for ServerApi {
    async fn remove_user_from_workspace(
        &self,
        user_uid: UserUid,
        workspace_uid: WorkspaceUid,
        entrypoint: CloudObjectEventEntrypoint,
    ) -> Result<WorkspacesMetadataResponse> {
        let variables = RemoveUserFromWorkspaceVariables {
            input: RemoveUserFromWorkspaceInput {
                user_uid: user_uid.as_str().into(),
                workspace_uid: String::from(workspace_uid).into(),
                entrypoint: entrypoint.into(),
            },
            request_context: get_request_context(),
        };
        let operation = RemoveUserFromWorkspace::build(variables);
        let result = self
            .send_graphql_request(operation, None)
            .await?
            .remove_user_from_workspace;

        match result {
            RemoveUserFromWorkspaceResult::RemoveUserFromWorkspaceOutput(output) => {
                if output.success {
                    self.workspaces_metadata().await
                } else {
                    Err(anyhow!("failed to remove user from workspace"))
                }
            }
            RemoveUserFromWorkspaceResult::UserFacingError(error) => {
                Err(anyhow!(get_user_facing_error_message(error)))
            }
            RemoveUserFromWorkspaceResult::Unknown => {
                Err(anyhow!("unknown error while removing user from workspace"))
            }
        }
    }
}
