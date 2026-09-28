use futures::FutureExt;
use futures::future::BoxFuture;
use warpui::{Entity, ModelContext};

use super::{ActionExecution, AnyActionExecution, ExecuteActionInput, PreprocessActionInput};
use crate::workspaces::user_workspaces::TeamContext;

/// Handles `UploadArtifact` actions. There is no artifact storage to upload to, so every
/// request is rejected as invalid.
pub struct UploadArtifactExecutor;

impl UploadArtifactExecutor {
    pub(super) fn should_autoexecute(
        &self,
        _input: ExecuteActionInput,
        _scope: &TeamContext<'_>,
        _ctx: &ModelContext<Self>,
    ) -> bool {
        false
    }

    pub(super) fn execute(
        &mut self,
        _input: ExecuteActionInput,
        _ctx: &mut ModelContext<Self>,
    ) -> AnyActionExecution {
        ActionExecution::<()>::InvalidAction.into()
    }

    pub(super) fn preprocess_action(
        &mut self,
        _input: PreprocessActionInput,
        _ctx: &mut ModelContext<Self>,
    ) -> BoxFuture<'static, ()> {
        futures::future::ready(()).boxed()
    }
}

impl Entity for UploadArtifactExecutor {
    type Event = ();
}
