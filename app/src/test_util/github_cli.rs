use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};

use futures::FutureExt as _;
use futures::future::BoxFuture;

use crate::code_review::github_repo_model::GitHubCli;
use crate::util::git::{PrInfo, RepositoryInfo};

/// A `gh` stand-in that counts lookups and never starts a process.
#[derive(Default)]
pub struct CountingGitHubCli {
    pr_lookups: AtomicUsize,
    repository_lookups: AtomicUsize,
}

impl CountingGitHubCli {
    pub fn pr_lookups(&self) -> usize {
        self.pr_lookups.load(Ordering::SeqCst)
    }

    pub fn repository_lookups(&self) -> usize {
        self.repository_lookups.load(Ordering::SeqCst)
    }

    pub fn total_lookups(&self) -> usize {
        self.pr_lookups() + self.repository_lookups()
    }
}

impl GitHubCli for CountingGitHubCli {
    fn pr_for_branch(
        &self,
        _repo_path: PathBuf,
        _path_env: Option<String>,
    ) -> BoxFuture<'static, anyhow::Result<Option<PrInfo>>> {
        self.pr_lookups.fetch_add(1, Ordering::SeqCst);
        futures::future::ready(Ok(None)).boxed()
    }

    fn repository_info(
        &self,
        _repo_path: PathBuf,
        _path_env: Option<String>,
    ) -> BoxFuture<'static, anyhow::Result<Option<RepositoryInfo>>> {
        self.repository_lookups.fetch_add(1, Ordering::SeqCst);
        futures::future::ready(Ok(None)).boxed()
    }
}
