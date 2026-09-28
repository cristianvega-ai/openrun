//! Helpers for constructing repo detection calls.
//!
//! The core detection logic lives on
//! [`DetectedRepositories::detect_possible_local_git_repo`]. Repo detection only
//! runs for local sessions; remote sessions never resolve a repository, so a
//! remote working directory is never misclassified as a local repo when the
//! same absolute path happens to exist locally.

use std::future::Future;

#[cfg(not(target_family = "wasm"))]
use futures::future::Either;
use futures::future::ready;
#[cfg(not(target_family = "wasm"))]
use repo_metadata::repositories::DetectedRepositories;
use repo_metadata::repositories::RepoDetectionSource;
use warp_util::local_or_remote_path::LocalOrRemotePath;
use warpui::AppContext;
#[cfg(not(target_family = "wasm"))]
use warpui::SingletonEntity;

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
#[cfg(not(target_family = "wasm"))]
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

/// Repository detection is not available in WASM builds because
/// `DetectedRepositories` is not registered there.
#[cfg(target_family = "wasm")]
pub fn detect_possible_git_repo(
    _session_type: RepoDetectionSessionType,
    _active_directory: &str,
    _source: RepoDetectionSource,
    _ctx: &mut AppContext,
) -> impl Future<Output = Option<LocalOrRemotePath>> + use<> {
    ready(None)
}
