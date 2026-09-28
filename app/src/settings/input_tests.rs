use serde_json::json;
use settings_value::SettingsValue as _;

use super::*;

#[test]
fn inline_menu_heights_ignore_unknown_menu_keys() {
    let stored = json!({
        "skill_menu": 120.0,
        "prompts_menu": 90.0,
        "plan_menu": 60.0,
        "slash_commands": 200.0,
        "rewind_menu": 150.0,
    });

    let heights = InlineMenuHeights::from_file_value(&stored).expect("map should parse");

    let mut expected = HashMap::new();
    expected.insert(InlineMenuType::SlashCommands, 200.0);
    expected.insert(InlineMenuType::RewindMenu, 150.0);
    assert_eq!(heights, InlineMenuHeights(expected));
}

#[test]
fn inline_menu_heights_ignore_non_numeric_heights() {
    let stored = json!({ "slash_commands": "tall", "rewind_menu": 150.0 });

    let heights = InlineMenuHeights::from_file_value(&stored).expect("map should parse");

    assert_eq!(heights.0.len(), 1);
    assert_eq!(heights.0.get(&InlineMenuType::RewindMenu), Some(&150.0));
}

#[test]
fn inline_menu_heights_round_trip() {
    let mut map = HashMap::new();
    map.insert(InlineMenuType::ModelSelector, 175.0);
    let heights = InlineMenuHeights(map);

    let file_value = heights.to_file_value();

    assert_eq!(file_value, json!({ "model_selector": 175.0 }));
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
