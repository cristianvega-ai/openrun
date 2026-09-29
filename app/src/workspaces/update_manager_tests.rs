use settings::{PrivatePreferences, PublicPreferences};
use warpui::{AddSingletonModel, App};
use warpui_extras::user_preferences;

use super::*;
use crate::auth::AuthManager;
use crate::server::server_api::ServerApiProvider;
use crate::server::server_api::team::MockTeamClient;
use crate::server::server_api::workspace::{MockWorkspaceClient, WorkspaceClient};
use crate::settings::{CodeSettings, PrivacySettings};
use crate::system::SystemStats;
use crate::workspaces::team::Team;
use crate::workspaces::workspace::{Workspace, WorkspaceUid};

fn initialize_app(
    team_client: Arc<dyn TeamClient>,
    workspace_client: Arc<dyn WorkspaceClient>,
    workspaces: Vec<Workspace>,
    app: &mut App,
) {
    app.add_singleton_model(|_| NetworkStatus::new());
    app.add_singleton_model(|_| SystemStats::new());
    app.add_singleton_model(TeamTesterStatus::new);
    app.add_singleton_model(|ctx| {
        UserWorkspaces::mock(
            team_client.clone(),
            workspace_client.clone(),
            workspaces,
            ctx,
        )
    });
    app.add_singleton_model(PrivacySettings::mock);
    app.add_singleton_model(|_| ServerApiProvider::new_for_test());
    app.add_singleton_model(|_| AuthStateProvider::new_for_test());
    app.add_singleton_model(AuthManager::new_for_test);
}

fn initialize_workspace_preference_dependencies(app: &mut App) {
    app.add_singleton_model(|_| {
        PublicPreferences::new(Box::<user_preferences::in_memory::InMemoryPreferences>::default())
    });
    app.add_singleton_model(|_| {
        PrivatePreferences::new(Box::<user_preferences::in_memory::InMemoryPreferences>::default())
    });
    app.add_singleton_model(CodeSettings::new_with_defaults);
    app.update(|ctx| {
        warpui_extras::secure_storage::register_noop("test", ctx);
    });
}

#[test]
fn on_workspaces_updated_keeps_teams_distinct_and_prunes_a_team_the_response_omits() {
    App::test((), |mut app| async move {
        let team_client = Arc::new(MockTeamClient::new());
        initialize_app(
            team_client.clone(),
            Arc::new(MockWorkspaceClient::new()),
            vec![],
            &mut app,
        );
        initialize_workspace_preference_dependencies(&mut app);
        let team_update_manager =
            app.add_singleton_model(|ctx| TeamUpdateManager::new(team_client, None, ctx));

        let workspace_uid = WorkspaceUid::from(ServerId::from(999));
        let team_a = ServerId::from(1);
        let team_b = ServerId::from(2);

        let workspace_with_teams = |teams: Vec<Team>| {
            Workspace::from_local_cache(workspace_uid, "Test Workspace".to_owned(), Some(teams))
        };
        let team_named =
            |uid: ServerId| Team::from_local_cache(uid, format!("Team {uid}"), None, None, None);

        team_update_manager.update(&mut app, |manager, ctx| {
            manager.on_workspaces_updated(
                Ok(WorkspacesMetadataResponse {
                    workspaces: vec![workspace_with_teams(vec![
                        team_named(team_a),
                        team_named(team_b),
                    ])],
                    joinable_teams: vec![],
                }),
                ctx,
            );
        });

        app.read(|ctx| {
            let workspaces = UserWorkspaces::as_ref(ctx);
            assert!(workspaces.team_from_uid(team_a).is_some());
            assert!(workspaces.team_from_uid(team_b).is_some());
        });

        team_update_manager.update(&mut app, |manager, ctx| {
            manager.on_workspaces_updated(
                Ok(WorkspacesMetadataResponse {
                    workspaces: vec![workspace_with_teams(vec![team_named(team_b)])],
                    joinable_teams: vec![],
                }),
                ctx,
            );
        });

        app.read(|ctx| {
            let workspaces = UserWorkspaces::as_ref(ctx);
            assert!(
                workspaces.team_from_uid(team_a).is_none(),
                "team A should have been evicted once the response stopped naming it, not left \
                 stale"
            );
            assert!(workspaces.team_from_uid(team_b).is_some());
        });

        team_update_manager.update(&mut app, |manager, ctx| {
            manager.on_workspaces_updated(
                Ok(WorkspacesMetadataResponse {
                    workspaces: vec![workspace_with_teams(vec![])],
                    joinable_teams: vec![],
                }),
                ctx,
            );
        });

        app.read(|ctx| {
            let workspaces = UserWorkspaces::as_ref(ctx);
            assert!(
                workspaces.team_from_uid(team_b).is_none(),
                "an authoritative empty response must prune every remaining team, not be \
                 skipped as a no-op"
            );
        });
    });
}
