use warpui::{App, SingletonEntity};

use super::SettingsInitializer;
use crate::settings::PrivacySettings;
use crate::terminal::model::secrets::regexes::DEFAULT_REGEXES_WITH_NAMES;
use crate::test_util::settings::initialize_settings_for_tests;

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
