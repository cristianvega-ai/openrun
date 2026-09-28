use warpui::integration::TestStep;
use warpui::{SingletonEntity, async_assert, async_assert_eq};

use crate::cloud_object::model::persistence::CloudModel;
use crate::cloud_object::{CloudObjectLocation, Space};
use crate::server::cloud_objects::listener::Listener;
use crate::server::cloud_objects::update_manager::{InitiatedBy, UpdateManager};
use crate::server::ids::ClientId;
use crate::util::bindings::keybinding_name_to_display_string;
use crate::workspaces::team::{Team, TeamVisibility};
use crate::workspaces::user_workspaces::UserWorkspaces;
use crate::workspaces::workspace::Workspace;

pub fn join_a_workspace() -> TestStep {
    TestStep::new("Join a Warp Drive workspace")
        .with_action(move |app, _, _| {
            UserWorkspaces::handle(app).update(app, |user_workspaces, ctx| {
                let workspace_uid = "workspace_uid123456789".to_string().into();
                let teams: Vec<Team> = vec![Team {
                    uid: "team_uid12345678912345".try_into().expect("ID is valid"),
                    name: "My Team".to_string(),
                    color: None,
                    invite_link: Default::default(),
                    members: Default::default(),
                    pending_email_invites: Default::default(),
                    invite_link_domain_restrictions: Default::default(),
                    billing_metadata: Default::default(),
                    settings: Default::default(),
                    feature_model_choice: Default::default(),
                    is_eligible_for_discovery: false,
                    visibility: TeamVisibility::Open,
                }];
                let workspaces: Vec<Workspace> = vec![Workspace {
                    uid: workspace_uid,
                    name: "My Workspace".to_string(),
                    teams: teams.clone(),
                    open_teams: Default::default(),
                    billing_metadata: Default::default(),
                    settings: Default::default(),
                    feature_model_choice: Default::default(),
                    invite_link_domain_restrictions: Default::default(),
                    pending_email_invites: Default::default(),
                    is_eligible_for_discovery: false,
                    members: Default::default(),
                    total_requests_used_since_last_refresh: 0,
                }];

                user_workspaces.update_workspaces(workspaces, ctx);
                user_workspaces.set_current_workspace_uid(workspace_uid, ctx)
            });
        })
        .add_assertion(move |app, _| {
            UserWorkspaces::handle(app).read(app, |user_workspaces, _| {
                async_assert!(user_workspaces.has_teams(), "user is on a team")
            })
        })
        .add_assertion(move |app, _| {
            UserWorkspaces::handle(app).read(app, |user_workspaces, _| {
                async_assert!(user_workspaces.has_workspaces(), "user is on a workspace")
            })
        })
}

pub fn create_a_personal_folder() -> TestStep {
    TestStep::new("Create a personal folder")
        .with_action(move |app, _, _| {
            UpdateManager::handle(app).update(app, |update_manager, ctx| {
                update_manager.create_folder(
                    "My first folder".to_string(),
                    UserWorkspaces::as_ref(ctx)
                        .personal_drive(ctx)
                        .expect("User UID must be set in tests"),
                    ClientId::default(),
                    None,
                    true,
                    InitiatedBy::User,
                    ctx,
                )
            })
        })
        .add_assertion(move |app, _| {
            CloudModel::handle(app).read(app, |cloud_model, ctx| {
                async_assert!(
                    cloud_model
                        .active_cloud_objects_in_location_without_descendents(
                            CloudObjectLocation::Space(Space::Personal),
                            ctx,
                        )
                        .count()
                        > 0,
                    "cloud objects exist"
                )
            })
        })
}

pub fn assert_binding_display_string(
    binding: &'static str,
    display_string: Option<&'static str>,
) -> TestStep {
    TestStep::new("Assert a binding's display string").add_named_assertion(
        format!("Binding {binding} should have display string {display_string:?}"),
        move |app, _| {
            app.update(|ctx| {
                async_assert_eq!(
                    keybinding_name_to_display_string(binding, ctx).as_deref(),
                    display_string
                )
            })
        },
    )
}

pub fn assert_websocket_has_started() -> TestStep {
    TestStep::new("Assert a websocket has started").add_named_assertion(
        "subscription abort handle should exist",
        move |app, _| {
            Listener::handle(app).read(app, |listener, _| {
                async_assert!(
                    listener.has_current_subscription_abort_handle(),
                    "subscription has started"
                )
            })
        },
    )
}

pub fn assert_websocket_has_not_started() -> TestStep {
    TestStep::new("Assert a websocket has not started").add_named_assertion(
        "subscription abort handle should not exist",
        move |app, _| {
            Listener::handle(app).read(app, |listener, _| {
                async_assert!(
                    !listener.has_current_subscription_abort_handle(),
                    "subscription has not started"
                )
            })
        },
    )
}
