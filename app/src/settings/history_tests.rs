use settings::{PrivatePreferences, PublicPreferences, Setting as _, SettingsManager};
use warpui::{App, SingletonEntity as _};
use warpui_extras::user_preferences::in_memory::InMemoryPreferences;
use warpui_extras::user_preferences::toml_backed::TomlBackedUserPreferences;

use super::{HistorySettings, SaveCommandHistory};
use crate::terminal::general_settings::GeneralSettings;

/// Loads `contents` as the settings file and returns the keys that failed to load along with the
/// resulting values of `save_command_history` and `restore_session`.
fn load_settings_file(contents: &str) -> (Vec<String>, bool, bool) {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("settings.toml");
    std::fs::write(&path, contents).unwrap();
    let (preferences, error) = TomlBackedUserPreferences::new(path);
    assert!(error.is_none(), "the settings file itself must still load");

    App::test((), |mut app| async move {
        app.update(|ctx| {
            ctx.add_singleton_model(move |_| PublicPreferences::new(Box::new(preferences)));
            ctx.add_singleton_model(|_| -> PrivatePreferences {
                PrivatePreferences::new(Box::<InMemoryPreferences>::default())
            });
        });
        app.add_singleton_model(|_| SettingsManager::default());
        GeneralSettings::register(&mut app);
        HistorySettings::register(&mut app);

        let failed_keys = app.update(|ctx| {
            SettingsManager::handle(ctx)
                .update(ctx, |manager, ctx| manager.reload_all_public_settings(ctx))
        });
        let (save, restore) = app.read(|ctx| {
            (
                *HistorySettings::as_ref(ctx).save_command_history,
                *GeneralSettings::as_ref(ctx).restore_session,
            )
        });
        (failed_keys, save, restore)
    })
}

#[test]
fn saving_history_is_on_by_default() {
    let (failed_keys, save, _) = load_settings_file("");
    assert!(failed_keys.is_empty());
    assert!(save);
}

#[test]
fn saving_history_can_be_turned_off_in_the_settings_file() {
    let (failed_keys, save, restore) = load_settings_file(
        "[privacy]\nsave_command_history = false\n\n[general]\nrestore_session = false\n",
    );
    assert!(failed_keys.is_empty(), "{failed_keys:?}");
    assert!(!save);
    assert!(!restore, "neighbouring settings still load");
}

#[test]
fn an_invalid_value_falls_back_to_saving_and_does_not_disturb_other_settings() {
    for invalid in ["\"no\"", "0", "[]", "{ enabled = false }"] {
        let (failed_keys, save, restore) = load_settings_file(&format!(
            "[privacy]\nsave_command_history = {invalid}\n\n[general]\nrestore_session = false\n"
        ));
        assert!(save, "{invalid} falls back to the default");
        assert!(!restore, "{invalid} must not discard neighbouring settings");
        assert_eq!(
            failed_keys,
            vec!["save_command_history".to_owned()],
            "{invalid} is reported as the one invalid key"
        );
    }
}

#[test]
fn the_setting_round_trips_through_the_settings_file() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("settings.toml");
    let (preferences, error) = TomlBackedUserPreferences::new(path.clone());
    assert!(error.is_none());

    App::test((), |mut app| async move {
        app.update(|ctx| {
            ctx.add_singleton_model(move |_| PublicPreferences::new(Box::new(preferences)));
            ctx.add_singleton_model(|_| -> PrivatePreferences {
                PrivatePreferences::new(Box::<InMemoryPreferences>::default())
            });
        });
        app.add_singleton_model(|_| SettingsManager::default());
        HistorySettings::register(&mut app);

        app.update(|ctx| {
            HistorySettings::handle(ctx).update(ctx, |settings, ctx| {
                settings
                    .save_command_history
                    .set_value(false, ctx)
                    .expect("the setting should serialize");
            });
        });
    });

    let written = std::fs::read_to_string(&path).expect("the settings file should be written");
    assert!(
        written.contains("[privacy]") && written.contains("save_command_history = false"),
        "unexpected settings file:\n{written}"
    );

    let (preferences, error) = TomlBackedUserPreferences::new(path);
    assert!(error.is_none());
    assert_eq!(
        SaveCommandHistory::read_from_preferences(&preferences),
        Some(false)
    );
}
