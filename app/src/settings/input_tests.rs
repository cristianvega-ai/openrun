use serde_json::json;
use settings_value::SettingsValue as _;

use super::*;

#[test]
fn inline_menu_heights_ignore_unknown_menu_keys() {
    let stored = json!({
        "skill_menu": 120.0,
        "prompts_menu": 90.0,
        "plan_menu": 60.0,
        "model_selector": 175.0,
        "conversation_menu": 80.0,
        "profile_selector": 70.0,
        "user_query_menu": 65.0,
        "rewind_menu": 150.0,
        "slash_commands": 200.0,
        "inline_history_menu": 110.0,
    });

    let heights = InlineMenuHeights::from_file_value(&stored).expect("map should parse");

    let mut expected = HashMap::new();
    expected.insert(InlineMenuType::SlashCommands, 200.0);
    expected.insert(InlineMenuType::InlineHistoryMenu, 110.0);
    assert_eq!(heights, InlineMenuHeights(expected));
}

#[test]
fn inline_menu_heights_ignore_unknown_menu_keys_when_deserialized() {
    let stored = json!({
        "ModelSelector": 175.0,
        "RewindMenu": 150.0,
        "ConversationMenu": 80.0,
        "IndexedReposMenu": 90.0,
    });

    let heights = serde_json::from_value::<InlineMenuHeights>(stored).expect("map should parse");

    let mut expected = HashMap::new();
    expected.insert(InlineMenuType::IndexedReposMenu, 90.0);
    assert_eq!(heights, InlineMenuHeights(expected));
}

#[test]
fn inline_menu_heights_ignore_non_numeric_heights() {
    let stored = json!({ "slash_commands": "tall", "indexed_repos_menu": 150.0 });

    let heights = InlineMenuHeights::from_file_value(&stored).expect("map should parse");

    assert_eq!(heights.0.len(), 1);
    assert_eq!(
        heights.0.get(&InlineMenuType::IndexedReposMenu),
        Some(&150.0)
    );
}

#[test]
fn inline_menu_heights_round_trip() {
    let mut map = HashMap::new();
    map.insert(InlineMenuType::InlineHistoryMenu, 175.0);
    let heights = InlineMenuHeights(map);

    let file_value = heights.to_file_value();

    assert_eq!(file_value, json!({ "inline_history_menu": 175.0 }));
    assert_eq!(
        InlineMenuHeights::from_file_value(&file_value),
        Some(heights.clone())
    );
    let stored = serde_json::to_string(&heights).unwrap();
    assert_eq!(
        serde_json::from_str::<InlineMenuHeights>(&stored).unwrap(),
        heights
    );
}

#[test]
fn inline_menu_heights_reject_non_object() {
    assert_eq!(InlineMenuHeights::from_file_value(&json!([1, 2])), None);
}

#[test]
fn stored_universal_input_box_type_is_ignored() {
    use settings::{PrivatePreferences, PublicPreferences, Setting as _, SettingsManager};
    use warpui::SingletonEntity as _;
    use warpui_extras::user_preferences::UserPreferences as _;
    use warpui_extras::user_preferences::in_memory::InMemoryPreferences;

    use crate::terminal::session_settings::SessionSettings;

    warpui::App::test((), |mut app| async move {
        let stored = InMemoryPreferences::default();
        stored
            .write_value_with_hierarchy(
                "input_box_type_setting",
                "\"universal\"".to_owned(),
                Some("terminal.input"),
                None,
            )
            .unwrap();
        app.update(|ctx| {
            ctx.add_singleton_model(move |_| PublicPreferences::new(Box::new(stored)));
            ctx.add_singleton_model(|_| -> PrivatePreferences {
                PrivatePreferences::new(Box::<InMemoryPreferences>::default())
            });
        });
        app.add_singleton_model(|_| SettingsManager::default());
        InputSettings::register(&mut app);
        SessionSettings::register(&mut app);

        let failed_keys = app.update(|ctx| {
            SettingsManager::handle(ctx)
                .update(ctx, |manager, ctx| manager.reload_all_public_settings(ctx))
        });
        assert!(
            failed_keys.is_empty(),
            "a stale input box type must not fail any setting: {failed_keys:?}"
        );

        // The stored value does not select an input: the prompt follows `honor_ps1`.
        app.read(|ctx| {
            assert!(InputSettings::as_ref(ctx).is_warp_prompt_enabled(ctx));
        });
        SessionSettings::handle(&app).update(&mut app, |settings, ctx| {
            settings
                .honor_ps1
                .set_value(true, ctx)
                .expect("honor_ps1 should be settable");
        });
        app.read(|ctx| {
            assert!(!InputSettings::as_ref(ctx).is_warp_prompt_enabled(ctx));
        });
    });
}
