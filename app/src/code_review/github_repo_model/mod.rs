use std::time::Duration;

use warpui::{AppContext, Entity, ModelContext, ModelHandle};

mod local;
#[cfg(test)]
pub(crate) use local::GitHubCli;
pub use local::LocalGitHubRepoModel;

#[cfg(test)]
use crate::code_review::git_repo_model::GitRepoStatusModel;
use crate::util::git::{PrInfo, RepositoryInfo};

/// How long a consumer keeps its handle (and so `gh` polling) after the UI that shows the GitHub
/// info leaves the screen, for example after switching tabs. Switching back within this time
/// finds the model still alive, so quick tab flips do not restart `gh` each time.
pub(crate) const HIDDEN_CONSUMER_GRACE_PERIOD: Duration = Duration::from_secs(30);

/// How long a terminal in the selected tab keeps its handle while a running command that is not a
/// full-screen program hides the prompt. A full-screen program (`vim`, `less`) gets the shorter
/// [`HIDDEN_CONSUMER_GRACE_PERIOD`]. This one is longer because building or testing often takes
/// minutes: a command that finishes within it neither stops `gh` nor starts it again, while one
/// that runs longer costs a single `gh repo view` and `gh pr view` when it finishes instead of
/// the two calls a minute that polling would make.
pub(crate) const RUNNING_COMMAND_GRACE_PERIOD: Duration = Duration::from_secs(180);

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
            Self::Local(ref m) => m.as_ref(ctx).pr_info(),
        }
    }

    /// Repository info (name/owner) returned by `gh repo view`.
    pub fn repository_info<'a>(&self, ctx: &'a AppContext) -> Option<&'a RepositoryInfo> {
        match *self {
            Self::Local(ref m) => m.as_ref(ctx).repository_info(),
        }
    }

    /// Whether a `gh pr view` fetch is currently in flight.
    pub fn is_refreshing_pr_info(&self, ctx: &AppContext) -> bool {
        match *self {
            Self::Local(ref m) => m.as_ref(ctx).is_refreshing_pr_info(),
        }
    }

    /// Force a PR info refresh (e.g. after a `gh`/`gt` command completes).
    pub fn refresh_pr_info(&self, ctx: &mut ModelContext<Self>) {
        match *self {
            Self::Local(ref m) => m.update(ctx, |m, ctx| m.refresh_pr_info(ctx)),
        }
    }

    /// Force a repository-info refresh.
    pub fn refresh_repository_info(&self, ctx: &mut ModelContext<Self>) {
        match *self {
            Self::Local(ref m) => m.update(ctx, |m, ctx| m.refresh_repository_info(ctx)),
        }
    }
}

#[cfg(test)]
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
