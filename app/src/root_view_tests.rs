use session_sharing_protocol::common::SessionId;
use warp_core::features::FeatureFlag;
use warp_core::user_preferences::GetUserPreferences as _;
use warpui::platform::WindowStyle;
use warpui::{App, SingletonEntity, ViewHandle};

use super::{
    AuthOnboardingState, AuthOnboardingTarget, HAS_COMPLETED_ONBOARDING_KEY, NewWorkspaceSource,
    RootView, WorkspaceArgs, has_completed_local_onboarding,
};
use crate::GlobalResourceHandles;
use crate::auth::AuthStateProvider;

fn set_local_onboarding_completed(app: &mut App, completed: bool) {
    app.update(|ctx| {
        ctx.private_user_preferences()
            .write_value(
                HAS_COMPLETED_ONBOARDING_KEY,
                serde_json::to_string(&completed).unwrap(),
            )
            .unwrap();
    });
}

fn new_root_view(app: &mut App) -> ViewHandle<RootView> {
    let global_resource_handles = GlobalResourceHandles::mock(app);
    let (_, root_view) = app.add_window(WindowStyle::NotStealFocus, |ctx| {
        RootView::new(
            global_resource_handles,
            NewWorkspaceSource::Empty {
                previous_active_window: None,
                shell: None,
            },
            ctx,
        )
    });
    root_view
}

/// Without an account, a new window starts in onboarding until the user completes it locally,
/// and goes straight to the workspace afterwards.
#[test]
fn root_view_new_uses_local_onboarding_state() {
    let _agent_onboarding = FeatureFlag::AgentOnboarding.override_enabled(true);

    App::test((), |mut app| async move {
        crate::workspace::view::tests::initialize_app(&mut app);
        app.update(|ctx| {
            let auth_state = AuthStateProvider::as_ref(ctx).get();
            auth_state.set_credentials(None);
            auth_state.set_user(None);
        });

        set_local_onboarding_completed(&mut app, false);
        let root_view = new_root_view(&mut app);
        app.read(|ctx| {
            assert!(!has_completed_local_onboarding(ctx));
            assert!(matches!(
                root_view.as_ref(ctx).auth_onboarding_state,
                AuthOnboardingState::Onboarding { .. }
            ));
        });

        set_local_onboarding_completed(&mut app, true);
        let root_view = new_root_view(&mut app);
        app.read(|ctx| {
            assert!(has_completed_local_onboarding(ctx));
            assert!(matches!(
                root_view.as_ref(ctx).auth_onboarding_state,
                AuthOnboardingState::Terminal(_)
            ));
        });
    });
}

/// A logged-out shared-session cold start must bypass product onboarding.
#[test]
fn root_view_new_skips_onboarding_for_shared_session_cold_start() {
    let _agent_onboarding = FeatureFlag::AgentOnboarding.override_enabled(true);

    App::test((), |mut app| async move {
        crate::workspace::view::tests::initialize_app(&mut app);
        app.update(|ctx| {
            let auth_state = AuthStateProvider::as_ref(ctx).get();
            auth_state.set_credentials(None);
            auth_state.set_user(None);
        });

        let global_resource_handles = GlobalResourceHandles::mock(&mut app);
        let session_id = SessionId::new();
        let (_, root_view) = app.add_window(WindowStyle::NotStealFocus, |ctx| {
            RootView::new(
                global_resource_handles,
                NewWorkspaceSource::SharedSessionAsViewer { session_id },
                ctx,
            )
        });

        app.read(|ctx| {
            assert!(
                !matches!(
                    root_view.as_ref(ctx).auth_onboarding_state,
                    AuthOnboardingState::Onboarding { .. }
                ),
                "a cold-started shared-session window must not enter onboarding"
            );
        });
    });
}

fn pending_target(state: &AuthOnboardingState) -> Option<&AuthOnboardingTarget> {
    match state {
        AuthOnboardingState::Onboarding { target, .. } => Some(target),
        AuthOnboardingState::Terminal(_) => None,
    }
}

fn assert_pending_workspace_retargeted(
    target: &AuthOnboardingTarget,
    session_id: SessionId,
    case: &str,
) {
    let AuthOnboardingTarget::Workspace(args) = target else {
        panic!("{case}: expected a pending workspace target, found an existing terminal");
    };
    assert!(
        matches!(
            args.workspace_setting,
            NewWorkspaceSource::SharedSessionAsViewer { session_id: id } if id == session_id
        ),
        "{case}: should retarget to the requested session"
    );
}

fn pending_workspace_args(app: &mut App) -> Box<WorkspaceArgs> {
    Box::new(WorkspaceArgs {
        global_resource_handles: GlobalResourceHandles::mock(app),
        workspace_setting: NewWorkspaceSource::Empty {
            previous_active_window: None,
            shell: None,
        },
    })
}

fn root_view_for_join_test(app: &mut App) -> ViewHandle<RootView> {
    crate::workspace::view::tests::initialize_app(app);
    new_root_view(app)
}

fn assert_join_shared_session_retargets_pending(
    app: &mut App,
    root_view: &ViewHandle<RootView>,
    session_id: SessionId,
    case: &str,
) {
    let handled = root_view.update(app, |root_view, ctx| {
        root_view.join_shared_session_in_existing_window(&session_id, ctx)
    });
    assert!(handled, "{case}: expected the link to be handled");
    app.read(|ctx| {
        let state = &root_view.as_ref(ctx).auth_onboarding_state;
        let target = pending_target(state)
            .unwrap_or_else(|| panic!("{case}: expected to remain pre-terminal"));
        assert_pending_workspace_retargeted(target, session_id, case);
    });
}

#[test]
fn join_shared_session_in_existing_window_retargets_pending_onboarding_workspace() {
    App::test((), |mut app| async move {
        let root_view = root_view_for_join_test(&mut app);
        let session_id = SessionId::new();

        let target = AuthOnboardingTarget::Workspace(pending_workspace_args(&mut app));
        root_view.update(&mut app, |root_view, ctx| {
            let onboarding_view = RootView::create_onboarding_view(ctx);
            root_view.auth_onboarding_state = AuthOnboardingState::Onboarding {
                onboarding_view,
                target,
            };
        });

        assert_join_shared_session_retargets_pending(
            &mut app,
            &root_view,
            session_id,
            "Onboarding",
        );
    });
}

#[test]
fn onboarding_slides_skip_content_deep_link_terminal() {
    App::test((), |mut app| async move {
        crate::workspace::view::tests::initialize_app(&mut app);
        let deep_link_workspace =
            crate::workspace::view::tests::mock_workspace_viewing_shared_session(&mut app);
        let plain_workspace = crate::workspace::view::tests::mock_workspace(&mut app);

        let root_view = new_root_view(&mut app);

        root_view.update(&mut app, |root_view, ctx| {
            root_view.auth_onboarding_state =
                AuthOnboardingState::Terminal(deep_link_workspace.clone());
            root_view
                .auth_onboarding_state
                .try_open_onboarding_slides(ctx);
        });
        app.read(|ctx| {
            let AuthOnboardingState::Terminal(workspace) =
                &root_view.as_ref(ctx).auth_onboarding_state
            else {
                panic!("a shared-session workspace must not be wrapped in onboarding");
            };
            assert_eq!(
                workspace.id(),
                deep_link_workspace.id(),
                "a shared-session workspace must not be replaced by onboarding"
            );
        });

        root_view.update(&mut app, |root_view, ctx| {
            root_view.auth_onboarding_state =
                AuthOnboardingState::Terminal(plain_workspace.clone());
            root_view
                .auth_onboarding_state
                .try_open_onboarding_slides(ctx);
        });
        app.read(|ctx| {
            assert!(
                matches!(
                    root_view.as_ref(ctx).auth_onboarding_state,
                    AuthOnboardingState::Onboarding { .. }
                ),
                "a workspace opened with no content deep link should still get onboarding"
            );
        });
    });
}
