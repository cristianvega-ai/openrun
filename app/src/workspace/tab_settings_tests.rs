use settings::Setting;
use settings_value::SettingsValue as _;
use warpui::{App, SingletonEntity};

use super::*;
use crate::test_util::settings::initialize_settings_for_tests;
use crate::workspace::header_toolbar_item::HeaderToolbarItemKind;

#[test]
fn use_latest_user_prompt_as_conversation_title_in_tab_names_defaults_to_false() {
    App::test((), |mut app| async move {
        initialize_settings_for_tests(&mut app);

        TabSettings::handle(&app).read(&app, |settings, _ctx| {
            assert!(!*settings.use_latest_user_prompt_as_conversation_title_in_tab_names);
        });
    });
}

#[test]
fn use_latest_user_prompt_as_conversation_title_in_tab_names_uses_vertical_tabs_path() {
    assert_eq!(
        UseLatestUserPromptAsConversationTitleInTabNames::toml_path(),
        Some("appearance.vertical_tabs.use_latest_prompt_as_title")
    );
    assert_eq!(
        UseLatestUserPromptAsConversationTitleInTabNames::hierarchy(),
        Some("appearance.vertical_tabs")
    );
    assert_eq!(
        UseLatestUserPromptAsConversationTitleInTabNames::toml_key(),
        "use_latest_prompt_as_title"
    );
}

#[test]
fn show_vertical_tab_panel_in_restored_windows_defaults_to_false() {
    App::test((), |mut app| async move {
        initialize_settings_for_tests(&mut app);

        TabSettings::handle(&app).read(&app, |settings, _ctx| {
            assert!(!*settings.show_vertical_tab_panel_in_restored_windows);
        });
    });
}

#[test]
fn show_vertical_tab_panel_in_restored_windows_uses_vertical_tabs_path() {
    assert_eq!(
        ShowVerticalTabPanelInRestoredWindows::toml_path(),
        Some("appearance.vertical_tabs.show_panel_in_restored_windows")
    );
    assert_eq!(
        ShowVerticalTabPanelInRestoredWindows::hierarchy(),
        Some("appearance.vertical_tabs")
    );
    assert_eq!(
        ShowVerticalTabPanelInRestoredWindows::toml_key(),
        "show_panel_in_restored_windows"
    );
}

#[test]
fn hide_title_bar_search_bar_in_vertical_tabs_defaults_to_false() {
    App::test((), |mut app| async move {
        initialize_settings_for_tests(&mut app);

        TabSettings::handle(&app).read(&app, |settings, _ctx| {
            assert!(!*settings.hide_title_bar_search_bar_in_vertical_tabs);
        });
    });
}

#[test]
fn hide_title_bar_search_bar_in_vertical_tabs_uses_vertical_tabs_path() {
    assert_eq!(
        HideTitleBarSearchBarInVerticalTabs::toml_path(),
        Some("appearance.vertical_tabs.hide_title_bar_search_bar")
    );
    assert_eq!(
        HideTitleBarSearchBarInVerticalTabs::hierarchy(),
        Some("appearance.vertical_tabs")
    );
    assert_eq!(
        HideTitleBarSearchBarInVerticalTabs::toml_key(),
        "hide_title_bar_search_bar"
    );
}

#[test]
fn header_toolbar_chip_selection_default_contains_code_review() {
    let config = HeaderToolbarChipSelection::Default;
    assert!(config.contains_item(&HeaderToolbarItemKind::CodeReview));
}

#[test]
fn header_toolbar_chip_selection_custom_without_code_review_reports_absent() {
    let config = HeaderToolbarChipSelection::Custom {
        left: vec![
            HeaderToolbarItemKind::TabsPanel,
            HeaderToolbarItemKind::ToolsPanel,
        ]
        .into(),
        right: vec![HeaderToolbarItemKind::NotificationsMailbox].into(),
    };
    assert!(!config.contains_item(&HeaderToolbarItemKind::CodeReview));
    assert!(config.contains_item(&HeaderToolbarItemKind::TabsPanel));
    assert!(config.contains_item(&HeaderToolbarItemKind::ToolsPanel));
    assert!(config.contains_item(&HeaderToolbarItemKind::NotificationsMailbox));
}

#[test]
fn header_toolbar_chip_selection_skips_removed_items_in_settings_file() {
    let stored = serde_json::json!({
        "custom": {
            "left": ["tabs_panel", "agent_management", "tools_panel"],
            "right": ["agent_management", "code_review"],
        }
    });
    let selection = HeaderToolbarChipSelection::from_file_value(&stored)
        .expect("a removed toolbar item must not discard the whole selection");
    assert_eq!(
        selection.left_items(),
        vec![
            HeaderToolbarItemKind::TabsPanel,
            HeaderToolbarItemKind::ToolsPanel
        ]
    );
    assert_eq!(
        selection.right_items(),
        vec![HeaderToolbarItemKind::CodeReview]
    );

    let selection: HeaderToolbarChipSelection = serde_json::from_value(serde_json::json!({
        "Custom": {
            "left": ["TabsPanel", "AgentManagement", "ToolsPanel"],
            "right": ["AgentManagement", "CodeReview"],
        }
    }))
    .expect("a removed toolbar item must not fail the serde parse");
    assert_eq!(
        selection.left_items(),
        vec![
            HeaderToolbarItemKind::TabsPanel,
            HeaderToolbarItemKind::ToolsPanel
        ]
    );
}

#[test]
fn header_toolbar_chip_selection_custom_with_code_review_on_left_reports_present() {
    let config = HeaderToolbarChipSelection::Custom {
        left: vec![HeaderToolbarItemKind::CodeReview].into(),
        right: vec![].into(),
    };
    assert!(config.contains_item(&HeaderToolbarItemKind::CodeReview));
}

#[test]
fn header_toolbar_chip_selection_custom_empty_reports_all_absent() {
    let config = HeaderToolbarChipSelection::Custom {
        left: vec![].into(),
        right: vec![].into(),
    };
    for item in HeaderToolbarItemKind::all_items() {
        assert!(!config.contains_item(&item));
    }
}
