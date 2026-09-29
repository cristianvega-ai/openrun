use std::collections::HashSet;

use settings::Setting as _;
use warpui_extras::user_preferences::UserPreferences as _;
use warpui_extras::user_preferences::in_memory::InMemoryPreferences;

use super::{DefaultSessionMode, RestoreSession, WelcomeTipsFeaturesUsed};
use crate::resource_center::{Tip, TipAction, TipHint};

#[test]
fn welcome_tips_used_survive_a_stored_tip_that_no_longer_exists() {
    let preferences = InMemoryPreferences::default();
    preferences
        .write_value(
            WelcomeTipsFeaturesUsed::storage_key(),
            r#"[{"Action":"WarpAI"},{"Action":"SplitPane"},{"Action":"AiCommandSearch"},{"Hint":"CreateBlock"}]"#
                .to_owned(),
        )
        .expect("preferences should accept the value");

    let used = WelcomeTipsFeaturesUsed::read_from_preferences(&preferences)
        .expect("removed tips must not discard the rest of the stored tips");

    assert_eq!(
        used.0,
        HashSet::from([
            Tip::Action(TipAction::SplitPane),
            Tip::Hint(TipHint::CreateBlock),
        ])
    );
}

#[test]
fn retired_default_session_modes_read_as_the_default_mode() {
    use settings_value::SettingsValue as _;
    use warpui_extras::user_preferences::toml_backed::TomlBackedUserPreferences;

    for retired in ["agent", "cloud_agent", "docker_sandbox"] {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("settings.toml");
        std::fs::write(
            &path,
            format!("[general]\ndefault_session_mode = \"{retired}\"\nrestore_session = false\n"),
        )
        .unwrap();
        let (preferences, error) = TomlBackedUserPreferences::new(path);
        assert!(error.is_none(), "the settings file itself must still load");

        assert_eq!(
            DefaultSessionMode::read_from_preferences(&preferences),
            Some(DefaultSessionMode::Terminal),
            "{retired} reads as the default mode, so the setting stays writable"
        );
        assert_eq!(
            RestoreSession::read_from_preferences(&preferences),
            Some(false),
            "other keys in the same file still load"
        );
    }

    // The serialized (CamelCase) spelling used by the non-file preferences path.
    assert_eq!(
        serde_json::from_str::<DefaultSessionMode>("\"CloudAgent\"").unwrap(),
        DefaultSessionMode::Terminal
    );
    assert_eq!(
        serde_json::from_str::<DefaultSessionMode>("\"Agent\"").unwrap(),
        DefaultSessionMode::Terminal
    );
    assert_eq!(
        serde_json::from_str::<DefaultSessionMode>("\"TabConfig\"").unwrap(),
        DefaultSessionMode::TabConfig
    );

    for mode in [DefaultSessionMode::Terminal, DefaultSessionMode::TabConfig] {
        assert_eq!(
            DefaultSessionMode::from_file_value(&mode.to_file_value()),
            Some(mode)
        );
    }
    assert_eq!(
        DefaultSessionMode::from_file_value(&serde_json::json!("not_a_mode")),
        None
    );
}
