use warp_core::features::FeatureFlag;
use warp_core::settings::Setting;
use warpui::{App, SingletonEntity};

use super::SettingsInitializer;
use crate::root_view::mark_local_onboarding_completed;
use crate::settings::{PrivacySettings, ThemeSettings};
use crate::terminal::model::secrets::regexes::DEFAULT_REGEXES_WITH_NAMES;
use crate::test_util::settings::initialize_settings_for_tests;
use crate::themes::theme::ThemeKind;

fn launch(app: &mut App) {
    app.update(|ctx| {
        SettingsInitializer::handle(ctx).update(ctx, |initializer, ctx| {
            initializer.handle_app_launch(ctx);
        });
    });
}

#[test]
fn app_launch_seeds_recommended_secret_regexes_once() {
    App::test((), |mut app| async move {
        initialize_settings_for_tests(&mut app);
        app.add_singleton_model(PrivacySettings::mock);
        app.add_singleton_model(|_| SettingsInitializer::new());

        launch(&mut app);
        app.read(|ctx| {
            let privacy = PrivacySettings::as_ref(ctx);
            assert!(*privacy.has_initialized_default_secret_regexes);
            assert_eq!(
                privacy.user_secret_regex_list.len(),
                DEFAULT_REGEXES_WITH_NAMES.len()
            );
        });

        // Patterns the user removes are not added back on the next launch.
        app.update(|ctx| {
            PrivacySettings::handle(ctx).update(ctx, |privacy, ctx| {
                while !privacy.user_secret_regex_list.is_empty() {
                    privacy.remove_user_secret_regex(&0, ctx);
                }
            });
        });
        launch(&mut app);
        app.read(|ctx| {
            assert!(
                PrivacySettings::as_ref(ctx)
                    .user_secret_regex_list
                    .is_empty()
            );
        });
    });
}

/// Launches with the theme set to Phenomenon, the value the new-user defaults replace.
fn theme_kind_after_launch(app: &mut App, onboarding_completed: bool) -> ThemeKind {
    initialize_settings_for_tests(app);
    app.add_singleton_model(PrivacySettings::mock);
    app.add_singleton_model(|_| SettingsInitializer::new());
    app.update(|ctx| {
        if onboarding_completed {
            mark_local_onboarding_completed(ctx);
        }
        ThemeSettings::handle(ctx).update(ctx, |settings, ctx| {
            settings
                .theme_kind
                .set_value(ThemeKind::Phenomenon, ctx)
                .unwrap();
        });
    });

    launch(app);

    app.read(|ctx| ThemeSettings::as_ref(ctx).theme_kind.value().clone())
}

#[test]
fn fresh_profile_gets_new_user_defaults() {
    let _adeberry = FeatureFlag::DefaultAdeberryTheme.override_enabled(true);
    App::test((), |mut app| async move {
        assert_eq!(
            theme_kind_after_launch(&mut app, false),
            ThemeKind::Adeberry
        );
    });
}

#[test]
fn profile_that_completed_onboarding_keeps_its_settings() {
    let _adeberry = FeatureFlag::DefaultAdeberryTheme.override_enabled(true);
    App::test((), |mut app| async move {
        assert_eq!(
            theme_kind_after_launch(&mut app, true),
            ThemeKind::Phenomenon
        );
    });
}
