use warp_core::features::FeatureFlag;
use warp_core::user_preferences::GetUserPreferences as _;
use warpui::platform::WindowStyle;
use warpui::{App, SingletonEntity, ViewHandle};

use super::{
    AuthOnboardingState, HAS_COMPLETED_ONBOARDING_KEY, NewWorkspaceSource, RootView,
    has_completed_local_onboarding,
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

#[test]
fn onboarding_slides_skip_content_deep_link_terminal() {
    App::test((), |mut app| async move {
        crate::workspace::view::tests::initialize_app(&mut app);
        let deep_link_workspace =
            crate::workspace::view::tests::mock_workspace_opened_from_content_deep_link(&mut app);
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
                panic!("a content deep-link workspace must not be wrapped in onboarding");
            };
            assert_eq!(
                workspace.id(),
                deep_link_workspace.id(),
                "a content deep-link workspace must not be replaced by onboarding"
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
