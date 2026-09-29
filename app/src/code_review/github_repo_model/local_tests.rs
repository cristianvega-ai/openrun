use std::sync::Arc;

use repo_metadata::DirectoryWatcher;
use warp_util::standardized_path::StandardizedPath;
use warpui::{App, ModelHandle};

use super::*;
use crate::code_review::diff_state::DiffStats;
use crate::code_review::git_repo_model::{GitRepoStatusModel, GitStatusMetadata};
use crate::context_chips::display_chip::GitBranchTrackingStatus;
use crate::terminal::local_shell::LocalShellState;
use crate::test_util::assert_eventually;
use crate::test_util::github_cli::CountingGitHubCli;
use crate::test_util::settings::initialize_settings_for_tests;
use crate::util::git::RepositoryInfo;

fn pr(number: u64) -> PrInfo {
    PrInfo {
        number,
        url: format!("https://github.com/warp/warp/pull/{number}"),
        state: "OPEN".to_string(),
        draft: false,
        base_branch: "main".to_string(),
    }
}

fn repository_info() -> RepositoryInfo {
    RepositoryInfo {
        name: "warp".to_string(),
        owner: Some("example".to_string()),
        host: Some("github.com".to_string()),
    }
}

fn test_repository_handle(
    app: &mut App,
    temp_dir: &tempfile::TempDir,
) -> ModelHandle<repo_metadata::Repository> {
    let watcher_handle = app.add_singleton_model(DirectoryWatcher::new_for_testing);
    watcher_handle.update(app, |watcher, ctx| {
        watcher
            .add_directory(
                StandardizedPath::from_local_canonicalized(temp_dir.path()).unwrap(),
                ctx,
            )
            .unwrap()
    })
}

/// Builds an inert `GitHubRepoModel` over a throwaway sibling git-status
/// model. The model never subscribes or fetches; tests drive state directly.
fn new_github_repo_model_for_test(
    app: &mut App,
) -> (tempfile::TempDir, ModelHandle<LocalGitHubRepoModel>) {
    let temp_dir = tempfile::TempDir::new().unwrap();
    let repository = test_repository_handle(app, &temp_dir);
    let git_status =
        app.add_model(move |ctx| GitRepoStatusModel::new_local_for_test(repository, None, ctx));
    let model = app.add_model(move |_| LocalGitHubRepoModel::new_for_test(git_status));
    (temp_dir, model)
}

#[test]
fn pr_info_cleared_on_branch_change() {
    App::test((), |mut app| async move {
        let (_temp_dir, model) = new_github_repo_model_for_test(&mut app);

        // On feature-a with a cached PR.
        model.update(&mut app, |model, ctx| {
            model.branch = Some("feature-a".to_string());
            model.set_pr_info_for_test(Some(pr(123)), ctx);
        });
        model.read(&app, |model, _| {
            assert_eq!(model.pr_info(), Some(&pr(123)));
        });

        // Switching branches clears the now-stale PR.
        model.update(&mut app, |model, ctx| {
            model.branch = Some("feature-b".to_string());
            if model.pr_info.take().is_some() {
                ctx.emit(GitHubRepoEvent::PrInfoChanged);
            }
        });
        model.read(&app, |model, _| {
            assert_eq!(model.pr_info(), None);
        });
    });
}

#[test]
fn repository_info_preserved_on_fetch_error() {
    App::test((), |mut app| async move {
        let (_temp_dir, model) = new_github_repo_model_for_test(&mut app);

        model.update(&mut app, |model, ctx| {
            model.set_repository_info_for_test(Some(repository_info()), ctx);
        });
        model.read(&app, |model, _| {
            assert_eq!(model.repository_info(), Some(&repository_info()));
        });

        model.update(&mut app, |model, ctx| {
            model.handle_repository_info_result(Err(anyhow::anyhow!("gh failed")), ctx);
        });
        model.read(&app, |model, _| {
            assert_eq!(model.repository_info(), Some(&repository_info()));
        });
    });
}

#[test]
fn repository_info_cleared_on_authoritative_empty_result() {
    App::test((), |mut app| async move {
        let (_temp_dir, model) = new_github_repo_model_for_test(&mut app);

        model.update(&mut app, |model, ctx| {
            model.set_repository_info_for_test(Some(repository_info()), ctx);
        });
        model.read(&app, |model, _| {
            assert_eq!(model.repository_info(), Some(&repository_info()));
        });

        model.update(&mut app, |model, ctx| {
            model.handle_repository_info_result(Ok(None), ctx);
        });
        model.read(&app, |model, _| {
            assert_eq!(model.repository_info(), None);
        });
    });
}

#[test]
fn pr_info_cleared_when_branch_goes_away() {
    App::test((), |mut app| async move {
        let (_temp_dir, model) = new_github_repo_model_for_test(&mut app);

        model.update(&mut app, |model, ctx| {
            model.branch = Some("feature-a".to_string());
            model.set_pr_info_for_test(Some(pr(123)), ctx);
        });

        // Branch goes to `None` (e.g. metadata load failure / detached HEAD).
        model.update(&mut app, |model, ctx| {
            model.branch = None;
            if model.pr_info.take().is_some() {
                ctx.emit(GitHubRepoEvent::PrInfoChanged);
            }
        });
        model.read(&app, |model, _| {
            assert_eq!(model.pr_info(), None);
        });
    });
}

#[test]
fn repository_info_survives_branch_change() {
    App::test((), |mut app| async move {
        let (_temp_dir, model) = new_github_repo_model_for_test(&mut app);

        model.update(&mut app, |model, ctx| {
            model.branch = Some("feature-a".to_string());
            model.set_repository_info_for_test(Some(repository_info()), ctx);
        });
        model.read(&app, |model, _| {
            assert_eq!(model.repository_info(), Some(&repository_info()));
        });

        // Repository info is branch-independent — a branch change leaves it.
        model.update(&mut app, |model, _| {
            model.branch = Some("feature-b".to_string());
        });
        model.read(&app, |model, _| {
            assert_eq!(model.repository_info(), Some(&repository_info()));
        });
    });
}

const TEST_REFRESH_INTERVAL: Duration = Duration::from_millis(20);

fn git_status_metadata(branch: &str) -> GitStatusMetadata {
    GitStatusMetadata {
        current_branch_name: branch.to_string(),
        main_branch_name: "main".to_string(),
        stats_against_head: DiffStats::default(),
        branch_tracking_status: GitBranchTrackingStatus::new(branch.to_string(), None, 0, 0),
    }
}

fn initialize_polling_app(app: &mut App) {
    initialize_settings_for_tests(app);
    app.add_singleton_model(|_| LocalShellState::NotLoaded);
}

fn new_polling_model(
    app: &mut App,
    temp_dir: &tempfile::TempDir,
    gh: Arc<CountingGitHubCli>,
) -> ModelHandle<LocalGitHubRepoModel> {
    let repository = test_repository_handle(app, temp_dir);
    let git_status = app.add_model(move |ctx| {
        GitRepoStatusModel::new_local_for_test(repository, Some(git_status_metadata("main")), ctx)
    });
    app.add_model(move |ctx| {
        LocalGitHubRepoModel::new_with_cli(
            PathBuf::from("/test"),
            git_status,
            gh,
            TEST_REFRESH_INTERVAL,
            ctx,
        )
    })
}

#[test]
fn a_live_model_looks_up_the_pr_and_repository_and_keeps_polling() {
    App::test((), |mut app| async move {
        initialize_polling_app(&mut app);
        let gh = Arc::new(CountingGitHubCli::default());
        let temp_dir = tempfile::TempDir::new().unwrap();
        let _model = new_polling_model(&mut app, &temp_dir, gh.clone());

        assert_eventually!(
            200 => gh.pr_lookups() >= 3 && gh.repository_lookups() >= 3,
            "a live model must look up the PR and the repository on creation and on every tick"
        );
    });
}

#[test]
fn dropping_the_model_stops_all_gh_lookups() {
    App::test((), |mut app| async move {
        initialize_polling_app(&mut app);
        let gh = Arc::new(CountingGitHubCli::default());
        let temp_dir = tempfile::TempDir::new().unwrap();
        let model = new_polling_model(&mut app, &temp_dir, gh.clone());

        assert_eventually!(
            200 => gh.total_lookups() >= 2,
            "the model never started polling"
        );

        drop(model);
        // Let an in-flight tick land, then check that nothing else fires.
        warpui::r#async::Timer::after(TEST_REFRESH_INTERVAL * 3).await;
        let settled = gh.total_lookups();
        warpui::r#async::Timer::after(TEST_REFRESH_INTERVAL * 10).await;
        assert_eq!(
            gh.total_lookups(),
            settled,
            "gh must not be run after the last handle is dropped"
        );
    });
}

#[test]
fn a_model_without_a_branch_only_looks_up_the_repository() {
    App::test((), |mut app| async move {
        initialize_polling_app(&mut app);
        let gh = Arc::new(CountingGitHubCli::default());
        let temp_dir = tempfile::TempDir::new().unwrap();
        let repository = test_repository_handle(&mut app, &temp_dir);
        let git_status =
            app.add_model(move |ctx| GitRepoStatusModel::new_local_for_test(repository, None, ctx));
        let cli = gh.clone();
        let _model = app.add_model(move |ctx| {
            LocalGitHubRepoModel::new_with_cli(
                PathBuf::from("/test"),
                git_status,
                cli,
                Duration::from_secs(3600),
                ctx,
            )
        });

        assert_eventually!(
            200 => gh.repository_lookups() == 1,
            "the repository lookup did not run"
        );
        assert_eq!(gh.pr_lookups(), 0, "no branch means no `gh pr view`");
    });
}
