use warpui::{AppContext, Entity, ModelContext, ModelHandle};

#[cfg(feature = "local_fs")]
mod local;
#[cfg(all(test, feature = "local_fs"))]
pub(crate) use local::GitHubCli;
#[cfg(feature = "local_fs")]
pub use local::LocalGitHubRepoModel;

#[cfg(all(test, feature = "local_fs"))]
use crate::code_review::git_repo_model::GitRepoStatusModel;
use crate::util::git::{PrInfo, RepositoryInfo};

#[cfg_attr(not(feature = "local_fs"), allow(dead_code))]
#[derive(Debug)]
pub enum GitHubRepoEvent {
    /// Emitted when `pr_info` changes value (fetch result differs from
    /// cached, branch change cleared the cache, etc.).
    PrInfoChanged,
    /// Emitted when `repository_info` changes value.
    RepositoryInfoChanged,
}

// ── GitHubRepoModel ─────────────────────────────────────────────────────────

/// Per-repo GitHub-info model, mirroring
/// [`crate::code_review::git_repo_model::GitRepoStatusModel`].
///
/// Consumers (the GitHub PR prompt chip and the code-review panel) hold a
/// `ModelHandle<GitHubRepoModel>` and subscribe to its [`GitHubRepoEvent`]s.
/// The model is only constructible where a local filesystem is available.
pub enum GitHubRepoModel {
    #[cfg(feature = "local_fs")]
    Local(ModelHandle<LocalGitHubRepoModel>),
}
impl Entity for GitHubRepoModel {
    type Event = GitHubRepoEvent;
}
impl GitHubRepoModel {
    /// Re-emit a sub-model event so subscribers of this model observe the
    /// backend's `GitHubRepoEvent`s.
    pub(crate) fn forward_event(&mut self, event: &GitHubRepoEvent, ctx: &mut ModelContext<Self>) {
        match event {
            GitHubRepoEvent::PrInfoChanged => ctx.emit(GitHubRepoEvent::PrInfoChanged),
            GitHubRepoEvent::RepositoryInfoChanged => {
                ctx.emit(GitHubRepoEvent::RepositoryInfoChanged)
            }
        }
    }

    /// PR info for the current branch.
    pub fn pr_info<'a>(&self, ctx: &'a AppContext) -> Option<&'a PrInfo> {
        match *self {
            #[cfg(feature = "local_fs")]
            Self::Local(ref m) => m.as_ref(ctx).pr_info(),
        }
    }

    /// Repository info (name/owner) returned by `gh repo view`.
    pub fn repository_info<'a>(&self, ctx: &'a AppContext) -> Option<&'a RepositoryInfo> {
        match *self {
            #[cfg(feature = "local_fs")]
            Self::Local(ref m) => m.as_ref(ctx).repository_info(),
        }
    }

    /// Whether a `gh pr view` fetch is currently in flight.
    pub fn is_refreshing_pr_info(&self, ctx: &AppContext) -> bool {
        match *self {
            #[cfg(feature = "local_fs")]
            Self::Local(ref m) => m.as_ref(ctx).is_refreshing_pr_info(),
        }
    }

    /// Force a PR info refresh (e.g. after a `gh`/`gt` command completes).
    pub fn refresh_pr_info(&self, ctx: &mut ModelContext<Self>) {
        match *self {
            #[cfg(feature = "local_fs")]
            Self::Local(ref m) => m.update(ctx, |m, ctx| m.refresh_pr_info(ctx)),
        }
    }

    /// Force a repository-info refresh.
    pub fn refresh_repository_info(&self, ctx: &mut ModelContext<Self>) {
        match *self {
            #[cfg(feature = "local_fs")]
            Self::Local(ref m) => m.update(ctx, |m, ctx| m.refresh_repository_info(ctx)),
        }
    }
}

#[cfg(all(test, feature = "local_fs"))]
impl GitHubRepoModel {
    /// Wraps an inert local-backend test model in the unified enum.
    pub(crate) fn new_local_for_test(
        git_status: ModelHandle<GitRepoStatusModel>,
        ctx: &mut ModelContext<Self>,
    ) -> Self {
        let inner = ctx.add_model(move |_| LocalGitHubRepoModel::new_for_test(git_status));
        ctx.subscribe_to_model(&inner, |me, _, event, ctx| me.forward_event(event, ctx));
        Self::Local(inner)
    }

    pub(crate) fn set_pr_info_for_test(
        &mut self,
        pr_info: Option<PrInfo>,
        ctx: &mut ModelContext<Self>,
    ) {
        let Self::Local(m) = self;
        m.update(ctx, |m, ctx| m.set_pr_info_for_test(pr_info, ctx));
    }
}
