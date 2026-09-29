use settings::schema::SettingSchemaEntry;
use settings::{Setting, SettingSurfaces, SettingsMode};
use warp_errors::report_if_error;
use warpui::{App, SingletonEntity};

use super::*;
use crate::test_util::settings::initialize_settings_for_tests;

#[test]
fn auto_approve_denylist_bypass_defaults_on_and_is_available_in_gui_settings() {
    let setting = AutoApproveBypassesCommandDenylist::new(None);
    assert!(*setting.value());
    assert_eq!(
        AutoApproveBypassesCommandDenylist::toml_path(),
        Some("agents.warp_agent.other.auto_approve_bypasses_command_denylist")
    );

    let entry = inventory::iter::<SettingSchemaEntry>
        .into_iter()
        .find(|entry| {
            entry.hierarchy == Some("agents.warp_agent.other")
                && entry.storage_key == "auto_approve_bypasses_command_denylist"
        })
        .expect("expected auto-approve denylist bypass schema entry");
    let surfaces: SettingSurfaces = (entry.surfaces_fn)();
    assert!(surfaces.includes(SettingsMode::Gui));
}

/// A real terminal surface for the [`FocusedTerminalInfo`] cases below, which record the
/// handle of the terminal their flags came from. The change-detection cases reuse one stable
/// surface so only the flags vary.
fn focused_terminal_for_test(app: &mut App) -> WeakViewHandle<TerminalView> {
    crate::test_util::terminal::initialize_app_for_terminal_view(app);
    crate::test_util::add_window_with_terminal(app, None).downgrade()
}

// FocusedTerminalInfo Tests

#[test]
fn test_update_both_values_changed() {
    App::test((), |mut app| async move {
        let terminal = focused_terminal_for_test(&mut app);
        let model_handle = app.add_model(|_| FocusedTerminalInfo::default());

        // Setup event tracking
        let (sender, receiver) = async_channel::unbounded();
        app.update(|ctx| {
            let sender = sender.clone();
            ctx.subscribe_to_model(
                &model_handle,
                move |_, event: &FocusedTerminalInfoEvent, _| match event {
                    FocusedTerminalInfoEvent::TerminalInfoUpdated => {
                        let _ = sender.try_send(());
                    }
                },
            );
        });

        // Update both values to (true, false)
        model_handle.update(&mut app, |model, ctx| {
            model.update(terminal.clone(), true, false, ctx);
        });

        // Verify model state
        model_handle.read(&app, |model, _| {
            assert!(model.contains_any_remote_blocks());
            assert!(!model.contains_any_restored_remote_blocks());
        });

        // Verify event was emitted exactly once
        let mut count = 0;
        while receiver.try_recv().is_ok() {
            count += 1;
        }
        assert_eq!(count, 1);
    });
}

#[test]
fn test_update_additional_value_changed() {
    App::test((), |mut app| async move {
        let terminal = focused_terminal_for_test(&mut app);
        let model_handle = app.add_model(|_| FocusedTerminalInfo::default());

        // Setup event tracking
        let (sender, receiver) = async_channel::unbounded();
        app.update(|ctx| {
            let sender = sender.clone();
            ctx.subscribe_to_model(
                &model_handle,
                move |_, event: &FocusedTerminalInfoEvent, _| match event {
                    FocusedTerminalInfoEvent::TerminalInfoUpdated => {
                        let _ = sender.try_send(());
                    }
                },
            );
        });

        // First update to (true, false)
        model_handle.update(&mut app, |model, ctx| {
            model.update(terminal.clone(), true, false, ctx);
        });

        // Clear events by draining the channel
        while receiver.try_recv().is_ok() {}

        // Now update to (true, true) - only changing restored blocks
        model_handle.update(&mut app, |model, ctx| {
            model.update(terminal.clone(), true, true, ctx);
        });

        // Verify model state
        model_handle.read(&app, |model, _| {
            assert!(model.contains_any_remote_blocks());
            assert!(model.contains_any_restored_remote_blocks());
        });

        // Verify event was emitted exactly once
        let mut count = 0;
        while receiver.try_recv().is_ok() {
            count += 1;
        }
        assert_eq!(count, 1);
    });
}

#[test]
fn test_update_no_change() {
    App::test((), |mut app| async move {
        let terminal = focused_terminal_for_test(&mut app);
        let model_handle = app.add_model(|_| FocusedTerminalInfo::default());

        // Setup event tracking
        let (sender, receiver) = async_channel::unbounded();
        app.update(|ctx| {
            let sender = sender.clone();
            ctx.subscribe_to_model(
                &model_handle,
                move |_, event: &FocusedTerminalInfoEvent, _| match event {
                    FocusedTerminalInfoEvent::TerminalInfoUpdated => {
                        let _ = sender.try_send(());
                    }
                },
            );
        });

        // First update to (true, true)
        model_handle.update(&mut app, |model, ctx| {
            model.update(terminal.clone(), true, true, ctx);
        });

        // Clear events by draining the channel
        while receiver.try_recv().is_ok() {}

        // Update with same values (true, true)
        model_handle.update(&mut app, |model, ctx| {
            model.update(terminal.clone(), true, true, ctx);
        });

        // Verify model state remains the same
        model_handle.read(&app, |model, _| {
            assert!(model.contains_any_remote_blocks());
            assert!(model.contains_any_restored_remote_blocks());
        });

        // Verify no event was emitted
        let mut count = 0;
        while receiver.try_recv().is_ok() {
            count += 1;
        }
        assert_eq!(count, 0);
    });
}

#[test]
fn test_update_only_remote_toggles() {
    App::test((), |mut app| async move {
        let terminal = focused_terminal_for_test(&mut app);
        let model_handle = app.add_model(|_| FocusedTerminalInfo::default());

        // Setup event tracking
        let (sender, receiver) = async_channel::unbounded();
        app.update(|ctx| {
            let sender = sender.clone();
            ctx.subscribe_to_model(
                &model_handle,
                move |_, event: &FocusedTerminalInfoEvent, _| match event {
                    FocusedTerminalInfoEvent::TerminalInfoUpdated => {
                        let _ = sender.try_send(());
                    }
                },
            );
        });

        // First update to (true, true)
        model_handle.update(&mut app, |model, ctx| {
            model.update(terminal.clone(), true, true, ctx);
        });

        // Clear events by draining the channel
        while receiver.try_recv().is_ok() {}

        // Update with (false, true) - only remote blocks changes
        model_handle.update(&mut app, |model, ctx| {
            model.update(terminal.clone(), false, true, ctx);
        });

        // Verify model state
        model_handle.read(&app, |model, _| {
            assert!(!model.contains_any_remote_blocks());
            assert!(model.contains_any_restored_remote_blocks());
        });

        // Verify event was emitted exactly once
        let mut count = 0;
        while receiver.try_recv().is_ok() {
            count += 1;
        }
        assert_eq!(count, 1);
    });
}

#[test]
fn test_update_only_restored_toggles() {
    App::test((), |mut app| async move {
        let terminal = focused_terminal_for_test(&mut app);
        let model_handle = app.add_model(|_| FocusedTerminalInfo::default());

        // Setup event tracking
        let (sender, receiver) = async_channel::unbounded();
        app.update(|ctx| {
            let sender = sender.clone();
            ctx.subscribe_to_model(
                &model_handle,
                move |_, event: &FocusedTerminalInfoEvent, _| match event {
                    FocusedTerminalInfoEvent::TerminalInfoUpdated => {
                        let _ = sender.try_send(());
                    }
                },
            );
        });

        // First update to (true, true)
        model_handle.update(&mut app, |model, ctx| {
            model.update(terminal.clone(), true, true, ctx);
        });

        // Clear events by draining the channel
        while receiver.try_recv().is_ok() {}

        // Update with (true, false) - only restored blocks changes
        model_handle.update(&mut app, |model, ctx| {
            model.update(terminal.clone(), true, false, ctx);
        });

        // Verify model state
        model_handle.read(&app, |model, _| {
            assert!(model.contains_any_remote_blocks());
            assert!(!model.contains_any_restored_remote_blocks());
        });

        // Verify event was emitted exactly once
        let mut count = 0;
        while receiver.try_recv().is_ok() {
            count += 1;
        }
        assert_eq!(count, 1);
    });
}

#[test]
fn usage_display_unit_defaults_to_credits_and_round_trips() {
    App::test((), |mut app| async move {
        initialize_settings_for_tests(&mut app);

        AISettings::handle(&app).read(&app, |settings, _ctx| {
            assert_eq!(settings.usage_display_unit, UsageDisplayUnit::Credits);
        });

        AISettings::handle(&app).update(&mut app, |settings, ctx| {
            report_if_error!(
                settings
                    .usage_display_unit
                    .set_value(UsageDisplayUnit::Dollars, ctx)
            );
        });

        AISettings::handle(&app).read(&app, |settings, _ctx| {
            assert_eq!(settings.usage_display_unit, UsageDisplayUnit::Dollars);
        });
    });
}

#[test]
fn usage_display_unit_toml_path() {
    assert_eq!(
        UsageDisplayUnit::toml_path(),
        Some("agents.warp_agent.other.usage_display_unit")
    );
}

#[test]
fn retired_default_session_modes_read_as_the_default_mode() {
    use crate::terminal::general_settings::RestoreSession;
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
