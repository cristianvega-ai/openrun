use std::collections::HashSet;

use settings::Setting as _;
use warpui_extras::user_preferences::UserPreferences as _;
use warpui_extras::user_preferences::in_memory::InMemoryPreferences;

use super::{DefaultSessionMode, GeneralSettings, RestoreSession, WelcomeTipsFeaturesUsed};
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

#[test]
fn removed_ai_settings_in_the_settings_file_are_ignored() {
    use settings::{PrivatePreferences, PublicPreferences, SettingsManager};
    use warpui::SingletonEntity as _;

    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("settings.toml");
    std::fs::write(
        &path,
        r#"
[general]
restore_session = false
default_session_mode = "tab_config"

[agents.warp_agent]
is_any_ai_enabled = false

[agents.warp_agent.active_ai]
enabled = false

[agents.warp_agent.input]
include_agent_commands_in_history = true

[agents.warp_agent.other]
thinking_display_mode = "always_show"
usage_display_unit = "dollars"
default_prompt_submission_mode = "queue"
long_running_command_submission_mode = "send_immediately"
auto_approve_bypasses_command_denylist = false
agent_attribution_enabled = false

[agents.profiles]
agent_mode_command_execution_allowlist = ["ls .*"]
agent_mode_command_execution_denylist = ["rm .*"]
agent_mode_execute_readonly_commands = true
agent_mode_coding_permissions = "always_allow_reading"
agent_mode_coding_file_read_allowlist = ["/tmp"]

[agents.execution_profiles.default]
name = "Default"
read_files = "always_allow"

[cloud_platform.third_party_api_keys]
aws_bedrock_credentials_enabled = true
aws_bedrock_auto_login = true
aws_bedrock_auth_refresh_command = "aws sso login"
aws_bedrock_profile = "default"
gemini_enterprise_credentials_enabled = true
"#,
    )
    .unwrap();
    let (preferences, error) =
        warpui_extras::user_preferences::toml_backed::TomlBackedUserPreferences::new(path);
    assert!(error.is_none(), "the settings file itself must still load");

    warpui::App::test((), |mut app| async move {
        app.update(|ctx| {
            ctx.add_singleton_model(move |_| PublicPreferences::new(Box::new(preferences)));
            ctx.add_singleton_model(|_| -> PrivatePreferences {
                PrivatePreferences::new(Box::<InMemoryPreferences>::default())
            });
        });
        app.add_singleton_model(|_| SettingsManager::default());
        GeneralSettings::register(&mut app);

        let failed_keys = app.update(|ctx| {
            SettingsManager::handle(ctx)
                .update(ctx, |manager, ctx| manager.reload_all_public_settings(ctx))
        });
        assert!(
            failed_keys.is_empty(),
            "removed AI settings must not fail any setting: {failed_keys:?}"
        );

        app.read(|ctx| {
            let settings = GeneralSettings::as_ref(ctx);
            assert!(!*settings.restore_session);
            assert_eq!(
                settings.default_session_mode(),
                DefaultSessionMode::TabConfig
            );
        });
    });
}

#[test]
fn removed_team_workspace_and_cloud_settings_in_the_settings_file_are_ignored() {
    use settings::{PrivatePreferences, PublicPreferences, SettingsManager};
    use warpui::SingletonEntity as _;

    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("settings.toml");
    std::fs::write(
        &path,
        r#"
[general]
restore_session = false

[workspace]
team_uid = "stale-team"

[workspace.settings]
is_session_sharing_enabled = true
is_shared_workflows_enabled = true

[teams.settings]
enterprise_secret_redaction_enabled = true

[agents]
cloud_conversation_storage_enabled = false
"#,
    )
    .unwrap();
    let (preferences, error) =
        warpui_extras::user_preferences::toml_backed::TomlBackedUserPreferences::new(path);
    assert!(error.is_none(), "the settings file itself must still load");

    warpui::App::test((), |mut app| async move {
        app.update(|ctx| {
            ctx.add_singleton_model(move |_| PublicPreferences::new(Box::new(preferences)));
            ctx.add_singleton_model(|_| -> PrivatePreferences {
                PrivatePreferences::new(Box::<InMemoryPreferences>::default())
            });
        });
        app.add_singleton_model(|_| SettingsManager::default());
        GeneralSettings::register(&mut app);

        let failed_keys = app.update(|ctx| {
            SettingsManager::handle(ctx)
                .update(ctx, |manager, ctx| manager.reload_all_public_settings(ctx))
        });
        assert!(
            failed_keys.is_empty(),
            "removed team, workspace and cloud settings must not fail any setting: {failed_keys:?}"
        );

        app.read(|ctx| {
            assert!(!*GeneralSettings::as_ref(ctx).restore_session);
        });
    });
}
