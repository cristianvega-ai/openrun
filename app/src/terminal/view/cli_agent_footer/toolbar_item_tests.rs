use serde_json::json;
use settings_value::SettingsValue;

use super::*;

#[test]
fn saved_layout_skips_items_the_cli_footer_no_longer_offers() {
    let layout = json!([
        "FileAttach",
        "VoiceInput",
        "ModelSelector",
        { "ContextChip": "GitDiffStats" },
        "NLDToggle",
        "ShareSession",
        "RichInput",
    ]);

    let items: CLIAgentToolbarItems = serde_json::from_value(layout).unwrap();

    assert_eq!(
        items.to_vec(),
        vec![
            CLIAgentToolbarItemKind::FileAttach,
            CLIAgentToolbarItemKind::ContextChip(ContextChipKind::GitDiffStats),
            CLIAgentToolbarItemKind::RichInput,
        ]
    );
}

#[test]
fn image_attach_alias_loads_as_file_attach() {
    let items: CLIAgentToolbarItems = serde_json::from_value(json!(["ImageAttach"])).unwrap();

    assert_eq!(items.to_vec(), vec![CLIAgentToolbarItemKind::FileAttach]);
}

#[test]
fn settings_file_layout_skips_unknown_items() {
    let layout = json!(["file_attach", "model_selector", "settings", "share_session"]);

    let items = CLIAgentToolbarItems::from_file_value(&layout).unwrap();

    assert_eq!(
        items.to_vec(),
        vec![
            CLIAgentToolbarItemKind::FileAttach,
            CLIAgentToolbarItemKind::Settings,
        ]
    );
}

#[test]
fn layout_round_trips_through_the_settings_file() {
    let items = CLIAgentToolbarItems::from(CLIAgentToolbarItemKind::default_left());

    let restored = CLIAgentToolbarItems::from_file_value(&items.to_file_value()).unwrap();

    assert_eq!(restored, items);
}

#[test]
fn custom_selection_with_stale_items_still_loads() {
    let stored =
        json!({ "Custom": { "left": ["ModelSelector", "FileAttach"], "right": ["Settings"] } });

    let selection: crate::terminal::session_settings::CLIAgentToolbarChipSelection =
        serde_json::from_value(stored).unwrap();

    assert_eq!(
        selection,
        crate::terminal::session_settings::CLIAgentToolbarChipSelection::Custom {
            left: vec![CLIAgentToolbarItemKind::FileAttach].into(),
            right: vec![CLIAgentToolbarItemKind::Settings].into(),
        }
    );
}

#[test]
fn layout_skips_context_chips_of_a_removed_kind() {
    let stored = json!([
        { "ContextChip": "AgentPlanAndTodoList" },
        { "ContextChip": "GitDiffStats" },
    ]);
    let items: CLIAgentToolbarItems = serde_json::from_value(stored).unwrap();
    assert_eq!(
        items.to_vec(),
        vec![CLIAgentToolbarItemKind::ContextChip(
            ContextChipKind::GitDiffStats
        )]
    );

    let file_layout = json!([
        { "context_chip": "agent_plan_and_todo_list" },
        { "context_chip": "git_diff_stats" },
    ]);
    let items = CLIAgentToolbarItems::from_file_value(&file_layout).unwrap();
    assert_eq!(
        items.to_vec(),
        vec![CLIAgentToolbarItemKind::ContextChip(
            ContextChipKind::GitDiffStats
        )]
    );
}
