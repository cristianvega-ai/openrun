use super::*;

#[test]
fn test_has_horizontal_split() {
    let single_leaf = PaneNodeSnapshot::Leaf(LeafSnapshot {
        is_focused: false,
        custom_vertical_tabs_title: None,
        contents: LeafContents::Code(CodePaneSnapShot::Local {
            tabs: vec![CodePaneTabSnapshot {
                path: Some(PathBuf::new()),
            }],
            active_tab_index: 0,
            source: None,
        }),
    });
    assert!(!single_leaf.has_horizontal_split());

    let horizontal_split = PaneNodeSnapshot::Branch(BranchSnapshot {
        direction: SplitDirection::Horizontal,
        children: vec![
            (
                PaneFlex(1.),
                PaneNodeSnapshot::Leaf(LeafSnapshot {
                    is_focused: false,
                    custom_vertical_tabs_title: None,
                    contents: LeafContents::Code(CodePaneSnapShot::Local {
                        tabs: vec![CodePaneTabSnapshot {
                            path: Some(PathBuf::new()),
                        }],
                        active_tab_index: 0,
                        source: None,
                    }),
                }),
            ),
            (
                PaneFlex(1.),
                PaneNodeSnapshot::Leaf(LeafSnapshot {
                    is_focused: false,
                    custom_vertical_tabs_title: None,
                    contents: LeafContents::Code(CodePaneSnapShot::Local {
                        tabs: vec![CodePaneTabSnapshot {
                            path: Some(PathBuf::new()),
                        }],
                        active_tab_index: 0,
                        source: None,
                    }),
                }),
            ),
        ],
    });
    assert!(horizontal_split.has_horizontal_split());
}

#[test]
fn test_code_pane_snapshot_single_tab() {
    let snapshot = CodePaneSnapShot::Local {
        tabs: vec![CodePaneTabSnapshot {
            path: Some(PathBuf::from("/tmp/test.rs")),
        }],
        active_tab_index: 0,
        source: Some(CodeSource::FileTree {
            location: crate::code::buffer_location::LocalOrRemotePath::Local(PathBuf::from(
                "/tmp/test.rs",
            )),
        }),
    };
    let CodePaneSnapShot::Local {
        tabs,
        active_tab_index,
        source,
    } = &snapshot;
    assert_eq!(tabs.len(), 1);
    assert_eq!(*active_tab_index, 0);
    assert_eq!(tabs[0].path, Some(PathBuf::from("/tmp/test.rs")));
    assert!(matches!(source, Some(CodeSource::FileTree { .. })));
}

#[test]
fn test_code_pane_snapshot_with_multiple_tabs() {
    let snapshot = CodePaneSnapShot::Local {
        tabs: vec![
            CodePaneTabSnapshot {
                path: Some(PathBuf::from("/tmp/main.rs")),
            },
            CodePaneTabSnapshot {
                path: Some(PathBuf::from("/tmp/lib.rs")),
            },
            CodePaneTabSnapshot { path: None },
        ],
        active_tab_index: 1,
        source: Some(CodeSource::Link {
            path: PathBuf::from("/tmp/main.rs"),
            range_start: None,
            range_end: None,
        }),
    };
    let CodePaneSnapShot::Local {
        tabs,
        active_tab_index,
        source,
    } = &snapshot;
    assert_eq!(tabs.len(), 3);
    assert_eq!(*active_tab_index, 1);
    assert_eq!(tabs[0].path, Some(PathBuf::from("/tmp/main.rs")));
    assert_eq!(tabs[1].path, Some(PathBuf::from("/tmp/lib.rs")));
    assert_eq!(tabs[2].path, None);
    assert!(matches!(source, Some(CodeSource::Link { .. })));
}

#[test]
fn test_left_panel_snapshot_with_removed_conversation_list_tab_falls_back_to_file_tree() {
    let stored =
        r#"{"left_panel_displayed_tab":"ConversationListView","pane_group_id":"pg","width":320}"#;
    let snapshot: LeftPanelSnapshot =
        serde_json::from_str(stored).expect("a removed tab must not discard the snapshot");
    assert_eq!(
        snapshot.left_panel_displayed_tab,
        LeftPanelDisplayedTab::FileTree
    );
    assert_eq!(snapshot.width, 320);
    assert_eq!(snapshot.pane_group_id, "pg");

    let stored = r#"{"left_panel_displayed_tab":"GlobalSearch","pane_group_id":"pg","width":320}"#;
    let snapshot: LeftPanelSnapshot = serde_json::from_str(stored).unwrap();
    assert_eq!(
        snapshot.left_panel_displayed_tab,
        LeftPanelDisplayedTab::GlobalSearch
    );
}
