//! Helpers for constructing repo detection calls.
//!
//! The core detection logic lives on
//! [`DetectedRepositories::detect_possible_local_git_repo`]. Repo detection only
//! runs for local sessions; remote sessions never resolve a repository, so a
//! remote working directory is never misclassified as a local repo when the
//! same absolute path happens to exist locally.

use std::future::Future;

use futures::future::{Either, ready};
use repo_metadata::repositories::{DetectedRepositories, RepoDetectionSource};
use warp_util::local_or_remote_path::LocalOrRemotePath;
use warpui::{AppContext, SingletonEntity};

/// Describes whether the active session is local or remote.
pub enum RepoDetectionSessionType {
    /// A local terminal session — repo detection runs on the local filesystem.
    Local,
    /// A remote SSH session — no repo detection is performed.
    Remote,
}

/// Detects the git repository root for the given working directory.
///
/// Callers that only need the `DetectedGitRepo` event side effect may drop the
/// returned future: detection runs on a task spawned inside
/// [`DetectedRepositories`], so it completes regardless.
pub fn detect_possible_git_repo(
    session_type: RepoDetectionSessionType,
    active_directory: &str,
    source: RepoDetectionSource,
    ctx: &mut AppContext,
) -> impl Future<Output = Option<LocalOrRemotePath>> + use<> {
    match session_type {
        RepoDetectionSessionType::Local => {
            let detection = DetectedRepositories::handle(ctx).update(ctx, |repos, ctx| {
                repos.detect_possible_local_git_repo(active_directory, source, ctx)
            });
            Either::Left(async move { detection.await.map(LocalOrRemotePath::Local) })
        }
        RepoDetectionSessionType::Remote => Either::Right(ready(None)),
    }
}
