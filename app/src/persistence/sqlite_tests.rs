use std::path::PathBuf;
use std::sync::Arc;

use chrono::Utc;
use diesel::connection::SimpleConnection;
use diesel_migrations::MigrationHarness as _;
use pathfinder_geometry::rect::RectF;
use pathfinder_geometry::vector::Vector2F;

use super::{
    app_database_file_path, database_file_path_for_current_scope, database_file_path_for_scope,
    decode_path, deduplicate_events, encode_path, establish_connection, get_all_workspace_metadata,
    read_sqlite_data, save_app_state, save_workspace_metadata, setup_database, start_writer,
};
use crate::app_state::{
    AppState, BranchSnapshot, CodePaneSnapShot, CodePaneTabSnapshot, LeafContents, LeafSnapshot,
    NotebookPaneSnapshot, PaneFlex, PaneNodeSnapshot, SettingsPaneSnapshot, SplitDirection,
    TabGroupSnapshot, TabSnapshot, TerminalPaneSnapshot, WindowSnapshot,
};
use crate::code::editor_management::CodeSource;
use crate::persistence::{
    BlockCompleted, HistoryPersistence, ModelEvent, PersistedDataScope, PersistenceScope,
};
use crate::settings_view::SettingsSection;
use crate::tab::SelectedTabColor;
use crate::terminal::ShellLaunchData;
use crate::terminal::input::{InputConfig, InputType};
use crate::terminal::model::block::SerializedBlock;
use crate::themes::theme::AnsiColorIdentifier;
use crate::workspace::tab_group::TabGroupId;
use crate::workspace_metadata::WorkspaceMetadata;

#[test]
fn app_scope_database_path_matches_app_database_path() {
    assert_eq!(
        database_file_path_for_scope(&PersistenceScope::App),
        app_database_file_path()
    );
}

#[test]
fn database_path_for_current_scope_defaults_to_app_scope() {
    // Unit tests never call `persistence::initialize`, so the process-wide
    // scope defaults to `App` and ad-hoc read-only connections resolve to
    // the GUI database. (nextest runs each test in its own process, so no
    // other test can have set the scope.)
    assert_eq!(
        database_file_path_for_current_scope(),
        app_database_file_path()
    );
}

fn test_workspace_metadata(path: &str) -> WorkspaceMetadata {
    WorkspaceMetadata {
        path: PathBuf::from(path),
        navigated_ts: Some(Utc::now()),
        modified_ts: None,
        queried_ts: None,
    }
}

#[test]
fn sqlite_read_restores_app_state_and_workspace_metadata() {
    let tempdir = tempfile::tempdir().expect("tempdir should be created");
    let database_path = tempdir.path().join("warp.sqlite");
    let mut conn = setup_database(&database_path).expect("database should initialize");

    let app_state = AppState {
        windows: vec![test_terminal_window_snapshot(false)],
        active_window_index: Some(0),
        block_lists: Default::default(),
    };
    save_app_state(&mut conn, &app_state).expect("app state should save");

    let metadata = test_workspace_metadata("/tmp/repo");
    save_workspace_metadata(&mut conn, metadata.clone()).expect("workspace metadata should save");
    let restored =
        read_sqlite_data(&mut conn, PersistedDataScope::Full).expect("persisted data should load");
    let restored_app_state = restored
        .app_state
        .expect("app state should be present for the full scope");
    assert_eq!(restored_app_state.windows.len(), 1);
    assert_eq!(restored.workspace_metadata.len(), 1);
    assert_eq!(restored.workspace_metadata[0].path, metadata.path);
}

#[test]
fn sqlite_writer_upserts_workspace_metadata_events() {
    let tempdir = tempfile::tempdir().expect("tempdir should be created");
    let database_path = tempdir.path().join("warp.sqlite");
    let conn = setup_database(&database_path).expect("database should initialize");

    let writer = start_writer(conn, database_path.clone(), HistoryPersistence::new(true))
        .expect("writer should start");
    let metadata = test_workspace_metadata("/tmp/writer-repo");
    let updated_metadata = WorkspaceMetadata {
        modified_ts: Some(Utc::now()),
        ..metadata.clone()
    };
    for metadata in [metadata.clone(), updated_metadata.clone()] {
        writer
            .sender
            .send(ModelEvent::UpsertWorkspaceMetadata {
                metadata: Box::new(metadata),
            })
            .expect("upsert event should send");
    }
    writer
        .sender
        .send(ModelEvent::Terminate)
        .expect("terminate event should send");
    writer.handle.join().expect("writer should terminate");

    let mut conn = setup_database(&database_path).expect("database should reopen");
    let restored = get_all_workspace_metadata(&mut conn).expect("metadata should load");
    assert_eq!(restored.len(), 1);
    assert_eq!(restored[0].path, metadata.path);
    assert!(restored[0].modified_ts.is_some());
}

#[test]
fn test_deduplicate_snapshots() {
    let completed_block_1 = BlockCompleted {
        pane_id: vec![1, 2, 3],
        block: Arc::new(SerializedBlock::default()),
        is_local: true,
    };
    let completed_block_2 = BlockCompleted {
        pane_id: vec![4, 5, 6],
        block: Arc::new(SerializedBlock::default()),
        is_local: true,
    };
    let snapshot_1 = AppState {
        active_window_index: Some(1),
        block_lists: Default::default(),
        windows: Default::default(),
    };
    let snapshot_2 = AppState {
        active_window_index: Some(2),
        block_lists: Default::default(),
        windows: Default::default(),
    };
    let snapshot_3 = AppState {
        active_window_index: Some(3),
        block_lists: Default::default(),
        windows: Default::default(),
    };

    let original_events = vec![
        ModelEvent::DeleteBlocks(vec![7]),
        ModelEvent::Snapshot(snapshot_1.clone()),
        ModelEvent::SaveBlock(completed_block_1.clone()),
        ModelEvent::Snapshot(snapshot_2.clone()),
        ModelEvent::SaveBlock(completed_block_2.clone()),
        ModelEvent::Snapshot(snapshot_3.clone()),
        ModelEvent::DeleteBlocks(vec![8]),
    ];

    let filtered_events = deduplicate_events(original_events);
    assert_eq!(filtered_events.len(), 5);

    assert!(matches!(&filtered_events[0], &ModelEvent::DeleteBlocks(_)));
    // The first snapshot should have been filtered out.
    assert!(matches!(&filtered_events[1], &ModelEvent::SaveBlock(_)));
    // The second snapshot should have been filtered out.
    assert!(matches!(&filtered_events[2], &ModelEvent::SaveBlock(_)));
    // The third snapshot should be preserved.
    match &filtered_events[3] {
        ModelEvent::Snapshot(snapshot) => assert_eq!(snapshot, &snapshot_3),
        other => panic!("Expected ModelEvent::Snapshot, got {other:?}"),
    }
    assert!(matches!(&filtered_events[4], &ModelEvent::DeleteBlocks(_)));
}

#[test]
fn test_deduplicate_no_snapshots() {
    let original_events = vec![ModelEvent::SaveBlock(BlockCompleted {
        pane_id: vec![1, 2, 3],
        block: Default::default(),
        is_local: true,
    })];
    let filtered_events = deduplicate_events(original_events);
    assert_eq!(filtered_events.len(), 1);
    assert!(matches!(&filtered_events[0], &ModelEvent::SaveBlock(_)));
}

fn test_terminal_window_snapshot(vertical_tabs_panel_open: bool) -> WindowSnapshot {
    WindowSnapshot {
        tabs: vec![TabSnapshot {
            custom_title: None,
            root: PaneNodeSnapshot::Leaf(LeafSnapshot {
                is_focused: true,
                custom_vertical_tabs_title: None,
                contents: LeafContents::Terminal(TerminalPaneSnapshot {
                    uuid: vec![u8::from(vertical_tabs_panel_open) + 1],
                    cwd: Some("/tmp".to_string()),
                    shell_launch_data: Some(ShellLaunchData::Executable {
                        executable_path: PathBuf::from("/bin/zsh"),
                        shell_type: crate::terminal::shell::ShellType::Zsh,
                    }),
                    is_active: true,
                    is_read_only: false,
                    input_config: None,
                }),
            }),
            default_directory_color: None,
            selected_color: SelectedTabColor::default(),
            left_panel: None,
            right_panel: None,
            group_id: None,
            pinned: false,
        }],
        active_tab_index: 0,
        bounds: None,
        fullscreen_state: Default::default(),
        quake_mode: false,
        universal_search_width: None,
        voltron_width: None,
        left_panel_open: false,
        vertical_tabs_panel_open,
        left_panel_width: None,
        right_panel_width: None,
        tab_groups: vec![],
    }
}

#[test]
fn test_sqlite_round_trips_vertical_tabs_panel_open() {
    let tempdir = tempfile::tempdir().expect("tempdir should be created");
    let database_path = tempdir.path().join("warp.sqlite");
    let mut conn = setup_database(&database_path).expect("database should initialize");

    let app_state = AppState {
        windows: vec![
            test_terminal_window_snapshot(false),
            test_terminal_window_snapshot(true),
        ],
        active_window_index: Some(1),
        block_lists: Default::default(),
    };

    save_app_state(&mut conn, &app_state).expect("app state should save");

    let restored = read_sqlite_data(&mut conn, PersistedDataScope::Full)
        .expect("app state should load")
        .app_state
        .expect("app state should be present for the full scope");

    assert_eq!(restored.active_window_index, Some(1));
    assert_eq!(
        restored
            .windows
            .iter()
            .map(|window| window.vertical_tabs_panel_open)
            .collect::<Vec<_>>(),
        vec![false, true]
    );
}

#[test]
fn test_sqlite_round_trips_custom_vertical_tabs_title() {
    let tempdir = tempfile::tempdir().expect("tempdir should be created");
    let database_path = tempdir.path().join("warp.sqlite");
    let mut conn = setup_database(&database_path).expect("database should initialize");

    let app_state = AppState {
        windows: vec![WindowSnapshot {
            tabs: vec![TabSnapshot {
                custom_title: None,
                root: PaneNodeSnapshot::Leaf(LeafSnapshot {
                    is_focused: true,
                    custom_vertical_tabs_title: Some("Production API".to_string()),
                    contents: LeafContents::Terminal(TerminalPaneSnapshot {
                        uuid: vec![42],
                        cwd: Some("/tmp".to_string()),
                        shell_launch_data: Some(ShellLaunchData::Executable {
                            executable_path: PathBuf::from("/bin/zsh"),
                            shell_type: crate::terminal::shell::ShellType::Zsh,
                        }),
                        is_active: true,
                        is_read_only: false,
                        input_config: None,
                    }),
                }),
                default_directory_color: None,
                selected_color: SelectedTabColor::default(),
                left_panel: None,
                right_panel: None,
                group_id: None,
                pinned: false,
            }],
            active_tab_index: 0,
            bounds: None,
            fullscreen_state: Default::default(),
            quake_mode: false,
            universal_search_width: None,
            voltron_width: None,
            left_panel_open: false,
            vertical_tabs_panel_open: false,
            left_panel_width: None,
            right_panel_width: None,
            tab_groups: vec![],
        }],
        active_window_index: Some(0),
        block_lists: Default::default(),
    };

    save_app_state(&mut conn, &app_state).expect("app state should save");

    let restored = read_sqlite_data(&mut conn, PersistedDataScope::Full)
        .expect("app state should load")
        .app_state
        .expect("app state should be present for the full scope");

    let PaneNodeSnapshot::Leaf(LeafSnapshot {
        custom_vertical_tabs_title,
        ..
    }) = &restored.windows[0].tabs[0].root
    else {
        panic!("Expected terminal pane leaf");
    };
    assert_eq!(
        custom_vertical_tabs_title.as_deref(),
        Some("Production API")
    );
}

#[test]
fn test_sqlite_round_trips_code_pane_with_multiple_tabs() {
    let tempdir = tempfile::tempdir().expect("tempdir should be created");
    let database_path = tempdir.path().join("warp.sqlite");
    let mut conn = setup_database(&database_path).expect("database should initialize");

    let app_state = AppState {
        windows: vec![WindowSnapshot {
            tabs: vec![TabSnapshot {
                custom_title: None,
                root: PaneNodeSnapshot::Leaf(LeafSnapshot {
                    is_focused: true,
                    custom_vertical_tabs_title: None,
                    contents: LeafContents::Code(CodePaneSnapShot::Local {
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
                        source: Some(CodeSource::FileTree {
                            location: crate::code::buffer_location::LocalOrRemotePath::Local(
                                PathBuf::from("/tmp/main.rs"),
                            ),
                        }),
                    }),
                }),
                default_directory_color: None,
                selected_color: SelectedTabColor::default(),
                left_panel: None,
                right_panel: None,
                group_id: None,
                pinned: false,
            }],
            active_tab_index: 0,
            bounds: None,
            fullscreen_state: Default::default(),
            quake_mode: false,
            universal_search_width: None,
            voltron_width: None,
            left_panel_open: false,
            vertical_tabs_panel_open: false,
            left_panel_width: None,
            right_panel_width: None,
            tab_groups: vec![],
        }],
        active_window_index: Some(0),
        block_lists: Default::default(),
    };

    save_app_state(&mut conn, &app_state).expect("app state should save");

    let restored = read_sqlite_data(&mut conn, PersistedDataScope::Full)
        .expect("app state should load")
        .app_state
        .expect("app state should be present for the full scope");

    assert_eq!(restored.windows.len(), 1);
    let restored_tab = &restored.windows[0].tabs[0];
    let PaneNodeSnapshot::Leaf(LeafSnapshot {
        contents:
            LeafContents::Code(CodePaneSnapShot::Local {
                tabs,
                active_tab_index,
                source,
            }),
        ..
    }) = &restored_tab.root
    else {
        panic!("Expected code pane leaf");
    };

    assert_eq!(tabs.len(), 3);
    assert_eq!(*active_tab_index, 1);
    assert_eq!(tabs[0].path, Some(PathBuf::from("/tmp/main.rs")));
    assert_eq!(tabs[1].path, Some(PathBuf::from("/tmp/lib.rs")));
    assert_eq!(tabs[2].path, None);
    assert!(matches!(source, Some(CodeSource::FileTree { .. })));
}

/// Verifies that a tab group and its membership round-trip through save/restore.
#[test]
fn test_sqlite_round_trips_tab_groups() {
    let tempdir = tempfile::tempdir().expect("tempdir should be created");
    let database_path = tempdir.path().join("warp.sqlite");
    let mut conn = setup_database(&database_path).expect("database should initialize");

    let group_id = TabGroupId::new();
    let tab_in_group = TabSnapshot {
        custom_title: None,
        root: PaneNodeSnapshot::Leaf(LeafSnapshot {
            is_focused: true,
            custom_vertical_tabs_title: None,
            contents: LeafContents::Terminal(TerminalPaneSnapshot {
                uuid: vec![1],
                cwd: Some("/tmp/grouped".to_string()),
                shell_launch_data: Some(ShellLaunchData::Executable {
                    executable_path: PathBuf::from("/bin/zsh"),
                    shell_type: crate::terminal::shell::ShellType::Zsh,
                }),
                is_active: true,
                is_read_only: false,
                input_config: None,
            }),
        }),
        default_directory_color: None,
        selected_color: SelectedTabColor::default(),
        left_panel: None,
        right_panel: None,
        group_id: Some(group_id),
        pinned: false,
    };
    let tab_outside_group = TabSnapshot {
        custom_title: None,
        root: PaneNodeSnapshot::Leaf(LeafSnapshot {
            is_focused: false,
            custom_vertical_tabs_title: None,
            contents: LeafContents::Terminal(TerminalPaneSnapshot {
                uuid: vec![2],
                cwd: Some("/tmp/ungrouped".to_string()),
                shell_launch_data: Some(ShellLaunchData::Executable {
                    executable_path: PathBuf::from("/bin/zsh"),
                    shell_type: crate::terminal::shell::ShellType::Zsh,
                }),
                is_active: false,
                is_read_only: false,
                input_config: None,
            }),
        }),
        default_directory_color: None,
        selected_color: SelectedTabColor::default(),
        left_panel: None,
        right_panel: None,
        group_id: None,
        pinned: false,
    };

    let app_state = AppState {
        windows: vec![WindowSnapshot {
            tabs: vec![tab_in_group, tab_outside_group],
            active_tab_index: 0,
            bounds: None,
            fullscreen_state: Default::default(),
            quake_mode: false,
            universal_search_width: None,
            voltron_width: None,
            left_panel_open: false,
            vertical_tabs_panel_open: false,
            left_panel_width: None,
            right_panel_width: None,
            tab_groups: vec![TabGroupSnapshot {
                id: group_id,
                name: Some("Backend".to_string()),
                color: SelectedTabColor::Color(AnsiColorIdentifier::Blue),
                collapsed: true,
                pinned: false,
            }],
        }],
        active_window_index: Some(0),
        block_lists: Default::default(),
    };

    save_app_state(&mut conn, &app_state).expect("app state should save");

    let restored = read_sqlite_data(&mut conn, PersistedDataScope::Full)
        .expect("app state should load")
        .app_state
        .expect("app state should be present for the full scope");

    assert_eq!(restored.windows.len(), 1);
    let restored_window = &restored.windows[0];
    assert_eq!(restored_window.tab_groups.len(), 1);
    let restored_group = &restored_window.tab_groups[0];
    assert_eq!(restored_group.name.as_deref(), Some("Backend"));
    assert_eq!(
        restored_group.color,
        SelectedTabColor::Color(AnsiColorIdentifier::Blue)
    );
    assert!(restored_group.collapsed);

    // The in-memory `TabGroupId` is minted fresh on restore, so we check that
    // the grouped tab points at the restored group, and the ungrouped tab
    // remains ungrouped.
    assert_eq!(restored_window.tabs.len(), 2);
    assert_eq!(restored_window.tabs[0].group_id, Some(restored_group.id));
    assert_eq!(restored_window.tabs[1].group_id, None);
}

/// Verifies that the `pinned` flag on tabs and tab groups round-trips through
/// save/restore so the user's pinned layout survives an app restart.
#[test]
fn test_sqlite_round_trips_pinned_state() {
    let tempdir = tempfile::tempdir().expect("tempdir should be created");
    let database_path = tempdir.path().join("warp.sqlite");
    let mut conn = setup_database(&database_path).expect("database should initialize");

    let pinned_group_id = TabGroupId::new();
    let unpinned_group_id = TabGroupId::new();

    let pinned_tab = TabSnapshot {
        custom_title: None,
        root: PaneNodeSnapshot::Leaf(LeafSnapshot {
            is_focused: true,
            custom_vertical_tabs_title: None,
            contents: LeafContents::Terminal(TerminalPaneSnapshot {
                uuid: vec![10],
                cwd: Some("/tmp/pinned".to_string()),
                shell_launch_data: Some(ShellLaunchData::Executable {
                    executable_path: PathBuf::from("/bin/zsh"),
                    shell_type: crate::terminal::shell::ShellType::Zsh,
                }),
                is_active: true,
                is_read_only: false,
                input_config: None,
            }),
        }),
        default_directory_color: None,
        selected_color: SelectedTabColor::default(),
        left_panel: None,
        right_panel: None,
        group_id: None,
        pinned: true,
    };
    let unpinned_tab = TabSnapshot {
        custom_title: None,
        root: PaneNodeSnapshot::Leaf(LeafSnapshot {
            is_focused: false,
            custom_vertical_tabs_title: None,
            contents: LeafContents::Terminal(TerminalPaneSnapshot {
                uuid: vec![11],
                cwd: Some("/tmp/unpinned".to_string()),
                shell_launch_data: Some(ShellLaunchData::Executable {
                    executable_path: PathBuf::from("/bin/zsh"),
                    shell_type: crate::terminal::shell::ShellType::Zsh,
                }),
                is_active: false,
                is_read_only: false,
                input_config: None,
            }),
        }),
        default_directory_color: None,
        selected_color: SelectedTabColor::default(),
        left_panel: None,
        right_panel: None,
        group_id: Some(unpinned_group_id),
        pinned: false,
    };
    let tab_in_pinned_group = TabSnapshot {
        custom_title: None,
        root: PaneNodeSnapshot::Leaf(LeafSnapshot {
            is_focused: false,
            custom_vertical_tabs_title: None,
            contents: LeafContents::Terminal(TerminalPaneSnapshot {
                uuid: vec![12],
                cwd: Some("/tmp/pinned-group".to_string()),
                shell_launch_data: Some(ShellLaunchData::Executable {
                    executable_path: PathBuf::from("/bin/zsh"),
                    shell_type: crate::terminal::shell::ShellType::Zsh,
                }),
                is_active: false,
                is_read_only: false,
                input_config: None,
            }),
        }),
        default_directory_color: None,
        selected_color: SelectedTabColor::default(),
        left_panel: None,
        right_panel: None,
        group_id: Some(pinned_group_id),
        pinned: false,
    };

    let app_state = AppState {
        windows: vec![WindowSnapshot {
            tabs: vec![pinned_tab, tab_in_pinned_group, unpinned_tab],
            active_tab_index: 0,
            bounds: None,
            fullscreen_state: Default::default(),
            quake_mode: false,
            universal_search_width: None,
            voltron_width: None,
            left_panel_open: false,
            vertical_tabs_panel_open: false,
            left_panel_width: None,
            right_panel_width: None,
            tab_groups: vec![
                TabGroupSnapshot {
                    id: pinned_group_id,
                    name: Some("Pinned".to_string()),
                    color: SelectedTabColor::default(),
                    collapsed: false,
                    pinned: true,
                },
                TabGroupSnapshot {
                    id: unpinned_group_id,
                    name: Some("Loose".to_string()),
                    color: SelectedTabColor::default(),
                    collapsed: false,
                    pinned: false,
                },
            ],
        }],
        active_window_index: Some(0),
        block_lists: Default::default(),
    };

    save_app_state(&mut conn, &app_state).expect("app state should save");

    let restored = read_sqlite_data(&mut conn, PersistedDataScope::Full)
        .expect("app state should load")
        .app_state
        .expect("app state should be present for the full scope");

    assert_eq!(restored.windows.len(), 1);
    let restored_window = &restored.windows[0];

    // Tabs come back in insertion order; pinned flag should match what we saved.
    assert_eq!(restored_window.tabs.len(), 3);
    assert!(restored_window.tabs[0].pinned);
    assert!(!restored_window.tabs[1].pinned);
    assert!(!restored_window.tabs[2].pinned);

    // Both groups round-trip with their pinned state preserved. Group ids are
    // minted fresh on restore, so we look them up by name.
    assert_eq!(restored_window.tab_groups.len(), 2);
    let restored_pinned_group = restored_window
        .tab_groups
        .iter()
        .find(|group| group.name.as_deref() == Some("Pinned"))
        .expect("pinned group should restore");
    let restored_loose_group = restored_window
        .tab_groups
        .iter()
        .find(|group| group.name.as_deref() == Some("Loose"))
        .expect("unpinned group should restore");
    assert!(restored_pinned_group.pinned);
    assert!(!restored_loose_group.pinned);
}

fn assert_encode_then_decode_preserves_original_path(original_path: PathBuf) {
    let bytes = encode_path(original_path.clone());
    let decoded_path = decode_path(bytes);
    assert_eq!(original_path, decoded_path);
}

/// Test that a local path can be encoded and decoded. We use this when persisting a local
/// file path for notebooks in sqlite. We need this test because Windows `OsString`s are
/// often arbitrary sequences of 16-bit values, unlike Unix which uses sequences of 8-bit
/// values (bytes). Since `diesel::sql_types::Binary` deals with sequences of bytes (`u8`)
/// we need to perform special casting on `OsString`s on Windows.
#[test]
fn test_path_encode_decode() {
    // Empty path
    assert_encode_then_decode_preserves_original_path(PathBuf::new());

    // Windows-style paths
    assert_encode_then_decode_preserves_original_path(PathBuf::from(r"C:\windows\system32.dll"));
    assert_encode_then_decode_preserves_original_path(PathBuf::from("c:temp"));
    assert_encode_then_decode_preserves_original_path(PathBuf::from(r"\temp"));
    assert_encode_then_decode_preserves_original_path(PathBuf::from(r"\temp\emoji\🙈.txt"));
    assert_encode_then_decode_preserves_original_path(PathBuf::from(r"\temp\ñoñàscii\temp.txt"));
    assert_encode_then_decode_preserves_original_path(PathBuf::from(r"\temp\hindi\हिन्दी"));
    assert_encode_then_decode_preserves_original_path(PathBuf::from(r"\temp\cjk\狗没有耐心"));

    // Unix-style paths
    assert_encode_then_decode_preserves_original_path(PathBuf::from(
        "/home/persistence/example.sql",
    ));
    assert_encode_then_decode_preserves_original_path(PathBuf::from("./database/log.txt"));
    assert_encode_then_decode_preserves_original_path(PathBuf::from("/temp/emoji/🙈.txt"));
    assert_encode_then_decode_preserves_original_path(PathBuf::from("/temp/ñoñàscii/temp.txt"));
    assert_encode_then_decode_preserves_original_path(PathBuf::from("/temp/hindi/हिन्दी"));
    assert_encode_then_decode_preserves_original_path(PathBuf::from("/temp/cjk/狗没有耐心"));
}

// Regression: GH#10083. The macOS green-tile button could leave a 1px-wide
// window bound in `AppContext::window_bounds`, which previously round-tripped
// through SQLite and restored as an unusable 1px sliver. Bounds below the
// platform minimum window size must be dropped on save.
#[test]
fn test_sqlite_drops_too_small_bounds_on_save() {
    use diesel::prelude::*;

    use crate::persistence::schema::windows;

    let tempdir = tempfile::tempdir().expect("tempdir should be created");
    let database_path = tempdir.path().join("warp.sqlite");
    let mut conn = setup_database(&database_path).expect("database should initialize");

    let mut snapshot = test_terminal_window_snapshot(false);
    snapshot.bounds = Some(RectF::new(
        Vector2F::new(0.0, -1410.0),
        Vector2F::new(1.0, 1410.0),
    ));

    let app_state = AppState {
        windows: vec![snapshot],
        active_window_index: Some(0),
        block_lists: Default::default(),
    };

    save_app_state(&mut conn, &app_state).expect("app state should save");

    // Query the row directly so the assertion isolates the save guard and is
    // not masked by the read-side guard in `read_sqlite_data`.
    let row: (Option<f32>, Option<f32>, Option<f32>, Option<f32>) = windows::dsl::windows
        .select((
            windows::columns::window_width,
            windows::columns::window_height,
            windows::columns::origin_x,
            windows::columns::origin_y,
        ))
        .first(&mut conn)
        .expect("a windows row should have been inserted");

    assert_eq!(
        row,
        (None, None, None, None),
        "save-path guard must persist NULL bound columns for sub-minimum geometry"
    );
}

// Regression: GH#10083. Users whose warp.sqlite already contains a 1px row
// (because they hit the bug on an earlier build) must still recover to default
// geometry on next launch rather than restoring the sliver.
#[test]
fn test_sqlite_drops_too_small_bounds_on_read() {
    let tempdir = tempfile::tempdir().expect("tempdir should be created");
    let database_path = tempdir.path().join("warp.sqlite");
    let mut conn = setup_database(&database_path).expect("database should initialize");

    // Save with no bounds so a row exists, then corrupt it directly to bypass
    // the save-path guard and simulate a pre-existing bad row.
    let app_state = AppState {
        windows: vec![test_terminal_window_snapshot(false)],
        active_window_index: Some(0),
        block_lists: Default::default(),
    };
    save_app_state(&mut conn, &app_state).expect("app state should save");

    conn.batch_execute(
        "UPDATE windows \
         SET window_width = 1.0, window_height = 1410.0, \
             origin_x = 0.0, origin_y = -1410.0",
    )
    .expect("corrupting update should succeed");

    let restored = read_sqlite_data(&mut conn, PersistedDataScope::Full)
        .expect("app state should load")
        .app_state
        .expect("app state should be present for the full scope");

    assert_eq!(restored.windows.len(), 1);
    assert!(
        restored.windows[0].bounds.is_none(),
        "tiny persisted bounds must be discarded on read so users recover from a corrupt DB"
    );
}

fn terminal_leaf(uuid_byte: u8) -> PaneNodeSnapshot {
    let mut window = test_terminal_window_snapshot(false);
    let PaneNodeSnapshot::Leaf(mut leaf) = window.tabs.remove(0).root else {
        unreachable!("the test window has a single leaf");
    };
    let LeafContents::Terminal(terminal) = &mut leaf.contents else {
        unreachable!("the test leaf is a terminal");
    };
    terminal.uuid = vec![uuid_byte];
    terminal.is_active = false;
    leaf.is_focused = false;
    PaneNodeSnapshot::Leaf(leaf)
}

/// A settings pane, which the tests below rewrite into a pane kind that no longer exists.
fn settings_leaf() -> PaneNodeSnapshot {
    PaneNodeSnapshot::Leaf(LeafSnapshot {
        is_focused: false,
        custom_vertical_tabs_title: None,
        contents: LeafContents::Settings(SettingsPaneSnapshot::Local {
            current_page: SettingsSection::default(),
            search_query: None,
        }),
    })
}

fn tab_with_root(root: PaneNodeSnapshot) -> TabSnapshot {
    let mut tab = test_terminal_window_snapshot(false).tabs.remove(0);
    tab.root = root;
    tab
}

fn window_with_tabs(tabs: Vec<TabSnapshot>, active_tab_index: usize) -> WindowSnapshot {
    let mut window = test_terminal_window_snapshot(false);
    window.tabs = tabs;
    window.active_tab_index = active_tab_index;
    window
}

fn terminal_uuid(node: &PaneNodeSnapshot) -> Vec<u8> {
    let PaneNodeSnapshot::Leaf(LeafSnapshot {
        contents: LeafContents::Terminal(terminal),
        ..
    }) = node
    else {
        panic!("expected a terminal leaf, got {node:?}");
    };
    terminal.uuid.clone()
}

/// Rewrites every saved settings pane into a pane of `kind`, as if it had been saved by a
/// version that still had that pane type.
fn rewrite_settings_panes_as_kind(conn: &mut diesel::SqliteConnection, kind: &str) {
    conn.batch_execute(&format!(
        "PRAGMA foreign_keys = OFF;
         DELETE FROM settings_panes;
         UPDATE pane_leaves SET kind = '{kind}' WHERE kind = 'settings';
         PRAGMA foreign_keys = ON;"
    ))
    .expect("panes should be rewritten");
}

#[test]
fn test_sqlite_restore_opens_default_settings_page_for_stored_teams_section() {
    let tempdir = tempfile::tempdir().expect("tempdir should be created");
    let database_path = tempdir.path().join("warp.sqlite");
    let mut conn = setup_database(&database_path).expect("database should initialize");

    let settings_on_privacy = PaneNodeSnapshot::Leaf(LeafSnapshot {
        is_focused: false,
        custom_vertical_tabs_title: None,
        contents: LeafContents::Settings(SettingsPaneSnapshot::Local {
            current_page: SettingsSection::Privacy,
            search_query: None,
        }),
    });
    let app_state = AppState {
        windows: vec![window_with_tabs(
            vec![tab_with_root(settings_on_privacy)],
            0,
        )],
        active_window_index: Some(0),
        block_lists: Default::default(),
    };
    save_app_state(&mut conn, &app_state).expect("app state should save");
    conn.batch_execute("UPDATE settings_panes SET current_page = 'Teams'")
        .expect("stored section should be rewritten");

    let restored = read_sqlite_data(&mut conn, PersistedDataScope::Full)
        .expect("a stored Teams section must not fail the read")
        .app_state
        .expect("app state should be present for the full scope");

    let PaneNodeSnapshot::Leaf(LeafSnapshot {
        contents: LeafContents::Settings(SettingsPaneSnapshot::Local { current_page, .. }),
        ..
    }) = &restored.windows[0].tabs[0].root
    else {
        panic!("expected a settings leaf");
    };
    assert_eq!(*current_page, SettingsSection::default());
}

#[test]
fn test_sqlite_restore_skips_removed_pane_kinds_without_losing_the_tab() {
    let tempdir = tempfile::tempdir().expect("tempdir should be created");
    let database_path = tempdir.path().join("warp.sqlite");
    let mut conn = setup_database(&database_path).expect("database should initialize");

    let split_with_removed_pane = tab_with_root(PaneNodeSnapshot::Branch(BranchSnapshot {
        direction: SplitDirection::Horizontal,
        children: vec![
            (PaneFlex(0.5), terminal_leaf(2)),
            (PaneFlex(0.5), settings_leaf()),
        ],
    }));
    let app_state = AppState {
        windows: vec![
            window_with_tabs(
                vec![
                    tab_with_root(settings_leaf()),
                    tab_with_root(terminal_leaf(1)),
                    split_with_removed_pane.clone(),
                    tab_with_root(settings_leaf()),
                ],
                2,
            ),
            window_with_tabs(vec![tab_with_root(settings_leaf())], 0),
            window_with_tabs(
                vec![
                    tab_with_root(terminal_leaf(3)),
                    tab_with_root(settings_leaf()),
                ],
                1,
            ),
        ],
        active_window_index: Some(0),
        block_lists: Default::default(),
    };
    save_app_state(&mut conn, &app_state).expect("app state should save");
    rewrite_settings_panes_as_kind(&mut conn, "get_started");

    let restored = read_sqlite_data(&mut conn, PersistedDataScope::Full)
        .expect("stale pane kinds must not fail the whole read")
        .app_state
        .expect("app state should be present for the full scope");

    assert_eq!(restored.windows.len(), 3, "no window is lost");

    let first = &restored.windows[0];
    assert_eq!(
        first.tabs.len(),
        2,
        "tabs holding only removed panes are dropped"
    );
    assert_eq!(terminal_uuid(&first.tabs[0].root), vec![1]);
    assert_eq!(
        terminal_uuid(&first.tabs[1].root),
        vec![2],
        "the surviving pane of a split replaces the split"
    );
    assert_eq!(
        first.active_tab_index, 1,
        "the active tab keeps pointing at the same tab after the tab before it was dropped"
    );

    let second = &restored.windows[1];
    assert!(second.tabs.is_empty());
    assert_eq!(second.active_tab_index, 0);

    let third = &restored.windows[2];
    assert_eq!(third.tabs.len(), 1);
    assert_eq!(terminal_uuid(&third.tabs[0].root), vec![3]);
    assert_eq!(
        third.active_tab_index, 0,
        "an active index past the last surviving tab is clamped"
    );
}

#[test]
fn test_sqlite_restore_and_save_survive_stale_workflow_pane_leaf() {
    let tempdir = tempfile::tempdir().expect("tempdir should be created");
    let database_path = tempdir.path().join("warp.sqlite");
    let mut conn = setup_database(&database_path).expect("database should initialize");

    let app_state = AppState {
        windows: vec![window_with_tabs(
            vec![tab_with_root(PaneNodeSnapshot::Branch(BranchSnapshot {
                direction: SplitDirection::Vertical,
                children: vec![
                    (PaneFlex(0.5), terminal_leaf(1)),
                    (PaneFlex(0.5), settings_leaf()),
                ],
            }))],
            0,
        )],
        active_window_index: Some(0),
        block_lists: Default::default(),
    };
    save_app_state(&mut conn, &app_state).expect("app state should save");
    rewrite_settings_panes_as_kind(&mut conn, "workflow");

    let restored = read_sqlite_data(&mut conn, PersistedDataScope::Full)
        .expect("a stale workflow pane leaf must not fail the read")
        .app_state
        .expect("app state should be present for the full scope");
    assert_eq!(
        terminal_uuid(&restored.windows[0].tabs[0].root),
        vec![1],
        "the split collapses to its remaining pane"
    );

    save_app_state(&mut conn, &app_state)
        .expect("saving must not trip over the stale workflow pane leaf");
}

#[test]
fn test_sqlite_restore_skips_stale_profile_editor_pane_and_keeps_the_split() {
    let tempdir = tempfile::tempdir().expect("tempdir should be created");
    let database_path = tempdir.path().join("warp.sqlite");
    let mut conn = setup_database(&database_path).expect("database should initialize");

    let app_state = AppState {
        windows: vec![window_with_tabs(
            vec![tab_with_root(PaneNodeSnapshot::Branch(BranchSnapshot {
                direction: SplitDirection::Horizontal,
                children: vec![
                    (PaneFlex(0.5), terminal_leaf(4)),
                    (PaneFlex(0.5), settings_leaf()),
                ],
            }))],
            0,
        )],
        active_window_index: Some(0),
        block_lists: Default::default(),
    };
    save_app_state(&mut conn, &app_state).expect("app state should save");
    rewrite_settings_panes_as_kind(&mut conn, "execution_profile_editor");

    let restored = read_sqlite_data(&mut conn, PersistedDataScope::Full)
        .expect("a stale profile editor pane must not fail the read")
        .app_state
        .expect("app state should be present for the full scope");
    assert_eq!(restored.windows[0].tabs.len(), 1, "the tab is kept");
    assert_eq!(terminal_uuid(&restored.windows[0].tabs[0].root), vec![4]);
}

#[test]
fn test_sqlite_restore_skips_cloud_notebook_pane_without_losing_the_tab() {
    let tempdir = tempfile::tempdir().expect("tempdir should be created");
    let database_path = tempdir.path().join("warp.sqlite");
    let mut conn = setup_database(&database_path).expect("database should initialize");

    // A notebook row with no local path is what a cloud notebook pane left behind.
    let cloud_notebook_leaf = PaneNodeSnapshot::Leaf(LeafSnapshot {
        is_focused: false,
        custom_vertical_tabs_title: None,
        contents: LeafContents::Notebook(NotebookPaneSnapshot::LocalFileNotebook { path: None }),
    });
    let app_state = AppState {
        windows: vec![window_with_tabs(
            vec![tab_with_root(PaneNodeSnapshot::Branch(BranchSnapshot {
                direction: SplitDirection::Horizontal,
                children: vec![
                    (PaneFlex(0.5), cloud_notebook_leaf),
                    (PaneFlex(0.5), terminal_leaf(7)),
                ],
            }))],
            0,
        )],
        active_window_index: Some(0),
        block_lists: Default::default(),
    };
    save_app_state(&mut conn, &app_state).expect("app state should save");

    let restored = read_sqlite_data(&mut conn, PersistedDataScope::Full)
        .expect("a cloud notebook pane must not fail the read")
        .app_state
        .expect("app state should be present for the full scope");

    assert_eq!(restored.windows[0].tabs.len(), 1);
    assert_eq!(terminal_uuid(&restored.windows[0].tabs[0].root), vec![7]);
}

fn restored_input_config(node: &PaneNodeSnapshot) -> Option<InputConfig> {
    let PaneNodeSnapshot::Leaf(LeafSnapshot {
        contents: LeafContents::Terminal(terminal),
        ..
    }) = node
    else {
        panic!("expected a terminal leaf, got {node:?}");
    };
    terminal.input_config
}

/// `terminal_panes.input_config` values written while the input could be an AI input (`"AI"`)
/// restore as shell input.
#[test]
fn test_sqlite_restores_persisted_ai_input_config_as_shell() {
    let tempdir = tempfile::tempdir().expect("tempdir should be created");
    let database_path = tempdir.path().join("warp.sqlite");
    let mut conn = setup_database(&database_path).expect("database should initialize");

    let app_state = AppState {
        windows: vec![window_with_tabs(
            vec![tab_with_root(PaneNodeSnapshot::Branch(BranchSnapshot {
                direction: SplitDirection::Vertical,
                children: vec![
                    (PaneFlex(0.5), terminal_leaf(1)),
                    (PaneFlex(0.5), terminal_leaf(2)),
                ],
            }))],
            0,
        )],
        active_window_index: Some(0),
        block_lists: Default::default(),
    };
    save_app_state(&mut conn, &app_state).expect("app state should save");
    conn.batch_execute(
        r#"UPDATE terminal_panes
           SET input_config = '{"input_type":"AI","is_locked":true}'
           WHERE uuid = x'01';
           UPDATE terminal_panes
           SET input_config = '{"input_type":"AI","is_locked":false}'
           WHERE uuid = x'02';"#,
    )
    .expect("persisted AI input configs should be written");

    let restored = read_sqlite_data(&mut conn, PersistedDataScope::Full)
        .expect("a persisted AI input config must not fail the read")
        .app_state
        .expect("app state should be present for the full scope");

    let PaneNodeSnapshot::Branch(branch) = &restored.windows[0].tabs[0].root else {
        panic!("expected the split to be restored");
    };
    assert_eq!(
        restored_input_config(&branch.children[0].1),
        Some(InputConfig {
            input_type: InputType::Shell,
        })
    );
    assert_eq!(
        restored_input_config(&branch.children[1].1),
        Some(InputConfig {
            input_type: InputType::Shell,
        })
    );
}

#[test]
fn test_sqlite_round_trips_shell_input_config() {
    let tempdir = tempfile::tempdir().expect("tempdir should be created");
    let database_path = tempdir.path().join("warp.sqlite");
    let mut conn = setup_database(&database_path).expect("database should initialize");

    let mut leaf = terminal_leaf(1);
    let PaneNodeSnapshot::Leaf(LeafSnapshot {
        contents: LeafContents::Terminal(terminal),
        ..
    }) = &mut leaf
    else {
        unreachable!("terminal_leaf returns a terminal");
    };
    let shell_config = InputConfig {
        input_type: InputType::Shell,
    };
    terminal.input_config = Some(shell_config);

    let app_state = AppState {
        windows: vec![window_with_tabs(vec![tab_with_root(leaf)], 0)],
        active_window_index: Some(0),
        block_lists: Default::default(),
    };
    save_app_state(&mut conn, &app_state).expect("app state should save");

    let restored = read_sqlite_data(&mut conn, PersistedDataScope::Full)
        .expect("app state should load")
        .app_state
        .expect("app state should be present for the full scope");
    assert_eq!(
        restored_input_config(&restored.windows[0].tabs[0].root),
        Some(shell_config)
    );
}

#[test]
fn stored_ignored_suggestions_of_removed_types_are_dropped() {
    use diesel::sqlite::SqliteConnection;
    use diesel::{Connection, RunQueryDsl, sql_query};
    use diesel_migrations::MigrationHarness;

    use super::get_all_ignored_suggestions;
    use crate::suggestions::ignored_suggestions_model::SuggestionType;

    let mut conn = SqliteConnection::establish(":memory:").expect("in-memory database");
    conn.run_pending_migrations(::persistence::MIGRATIONS)
        .expect("migrations should run");
    sql_query(
        "INSERT INTO ignored_suggestions (suggestion, suggestion_type) VALUES \
         ('git status', 'shell_command'), ('explain this error', 'ai_query')",
    )
    .execute(&mut conn)
    .expect("rows should insert");

    assert_eq!(
        get_all_ignored_suggestions(&mut conn).expect("suggestions should load"),
        vec![("git status".to_owned(), SuggestionType::ShellCommand)]
    );
}

/// A database at the schema before the migration that dropped the unused
/// tables, with rows in every dropped table and column (see the file for the layout).
const PRE_DROP_DEAD_TABLES_SEED: &str =
    include_str!("../../../crates/persistence/test_data/pre_drop_dead_tables_seed.sql");

/// Creates a database at `database_path` whose migrations stop right before the one that drops
/// the dead tables, and fills it with [`PRE_DROP_DEAD_TABLES_SEED`].
fn seed_database_before_dropping_dead_tables(database_path: &std::path::Path) {
    let mut conn =
        establish_connection(database_path.to_str().expect("path should be utf-8"), false)
            .expect("database should open");
    let pending = conn
        .pending_migrations(::persistence::MIGRATIONS)
        .expect("pending migrations should list");
    for migration in pending
        .iter()
        .take_while(|migration| migration.name().version().to_string().as_str() < "20260929000000")
    {
        conn.run_migration(migration.as_ref())
            .expect("earlier migration should run");
    }
    conn.batch_execute(PRE_DROP_DEAD_TABLES_SEED)
        .expect("seed should insert");
}

#[test]
fn test_sqlite_restores_a_session_saved_before_the_dead_tables_were_dropped() {
    let tempdir = tempfile::tempdir().expect("tempdir should be created");
    let database_path = tempdir.path().join("warp.sqlite");
    seed_database_before_dropping_dead_tables(&database_path);

    // The app runs the remaining migrations when it opens the database.
    let mut conn = setup_database(&database_path).expect("database should migrate");
    let data = read_sqlite_data(&mut conn, PersistedDataScope::Full)
        .expect("the migrated session should load");
    let restored = data.app_state.expect("app state should be present");

    assert_eq!(restored.windows.len(), 2);
    assert_eq!(restored.active_window_index, Some(0));

    let window = &restored.windows[0];
    assert_eq!(
        window
            .tabs
            .iter()
            .map(|tab| tab.custom_title.as_deref())
            .collect::<Vec<_>>(),
        vec![Some("kept split"), Some("mixed")],
        "tabs made only of removed panes are gone"
    );
    assert_eq!(
        window.active_tab_index, 1,
        "the active tab is still the mixed tab"
    );
    assert!(window.tabs[0].group_id.is_some(), "the tab group is kept");
    assert!(window.tabs[1].pinned);
    assert_eq!(window.voltron_width, Some(500.0));
    assert_eq!(window.universal_search_width, Some(300.0));

    let PaneNodeSnapshot::Leaf(LeafSnapshot {
        contents: LeafContents::Terminal(first_terminal),
        custom_vertical_tabs_title,
        is_focused,
    }) = &window.tabs[0].root
    else {
        panic!("the split with one surviving pane restores as that pane");
    };
    assert_eq!(first_terminal.uuid, vec![1, 1]);
    assert_eq!(first_terminal.cwd.as_deref(), Some("/work/one"));
    assert_eq!(
        custom_vertical_tabs_title.as_deref(),
        Some("first terminal")
    );
    assert!(*is_focused);

    let PaneNodeSnapshot::Branch(BranchSnapshot {
        direction,
        children,
    }) = &window.tabs[1].root
    else {
        panic!("the mixed tab keeps its split");
    };
    assert_eq!(*direction, SplitDirection::Horizontal);
    let contents: Vec<_> = children
        .iter()
        .map(|(_, child)| match child {
            PaneNodeSnapshot::Leaf(leaf) => &leaf.contents,
            PaneNodeSnapshot::Branch(_) => panic!("the emptied inner split is gone"),
        })
        .collect();
    assert_eq!(contents.len(), 5);
    assert!(matches!(
        contents[0],
        LeafContents::Code(CodePaneSnapShot::Local { tabs, .. }) if tabs.len() == 1
    ));
    assert!(matches!(
        contents[1],
        LeafContents::Terminal(terminal) if terminal.uuid == vec![2, 2]
    ));
    assert!(matches!(
        contents[2],
        LeafContents::Notebook(NotebookPaneSnapshot::LocalFileNotebook { path })
            if path.as_deref() == Some(std::path::Path::new("/work/notes.md"))
    ));
    assert!(matches!(
        contents[3],
        LeafContents::Settings(SettingsPaneSnapshot::Local {
            current_page: SettingsSection::Privacy,
            ..
        })
    ));
    assert!(matches!(contents[4], LeafContents::CodeReview(_)));

    assert!(
        restored.windows[1].tabs.is_empty(),
        "a window whose only tab held removed panes has no tabs left"
    );

    let block_ids = |uuid: Vec<u8>| -> Vec<String> {
        restored.block_lists[&crate::app_state::PaneUuid(uuid)]
            .iter()
            .map(|block| block.id.as_str().to_owned())
            .collect()
    };
    assert_eq!(
        block_ids(vec![1, 1]),
        vec!["plain", "attached", "null-metadata", "garbled-metadata"],
        "blocks that belonged to an agent conversation are gone"
    );
    assert_eq!(block_ids(vec![2, 2]), vec!["second-terminal"]);

    assert_eq!(data.command_history.len(), 2);
    assert_eq!(data.projects.len(), 1);
    assert_eq!(data.ignored_suggestions.len(), 1);
    assert_eq!(data.workspace_metadata.len(), 1);
    assert_eq!(
        data.workspace_language_servers
            .get(std::path::Path::new("/work/one"))
            .and_then(|servers| servers.get(&lsp::supported_servers::LSPServerType::RustAnalyzer)),
        Some(&crate::workspace_metadata::EnablementState::Yes)
    );

    save_app_state(&mut conn, &restored).expect("the restored session should save again");
    let resaved = read_sqlite_data(&mut conn, PersistedDataScope::Full)
        .expect("the saved session should load")
        .app_state
        .expect("app state should be present");
    assert_eq!(resaved.windows.len(), restored.windows.len());
    // Tab groups get a fresh id each time they are read.
    let without_group_ids = |tabs: &[TabSnapshot]| -> Vec<TabSnapshot> {
        tabs.iter()
            .cloned()
            .map(|mut tab| {
                tab.group_id = None;
                tab
            })
            .collect()
    };
    assert_eq!(
        without_group_ids(&resaved.windows[0].tabs),
        without_group_ids(&restored.windows[0].tabs)
    );
    assert_eq!(resaved.windows[0].active_tab_index, 1);
}

/// Tests for the "Save command history" setting and the "Delete saved history" action.
mod history_tests {
    use diesel::prelude::*;
    use diesel::sql_types::Text;
    use warp_core::command::ExitCode;

    use super::*;
    use crate::persistence::sqlite::handle_model_event;
    use crate::persistence::{
        FinishedCommandMetadata, SavedHistoryDeleted, StartedCommandMetadata,
    };
    use crate::terminal::model::session::SessionId;

    const SECRET_COMMAND: &str = "export OPENRUN_TEST_TOKEN=ghp_synthetic123";
    const SECRET_TOKEN: &[u8] = b"ghp_synthetic123";
    const SECRET_OUTPUT: &[u8] = b"OPENRUN_TEST_OUTPUT_ghp_synthetic456";
    const PANE_UUID: u8 = 1;

    #[derive(QueryableByName)]
    struct IntegrityRow {
        #[diesel(sql_type = Text)]
        integrity_check: String,
    }

    #[derive(QueryableByName)]
    struct ForeignKeyViolation {
        #[diesel(sql_type = Text)]
        #[allow(dead_code)]
        table: String,
    }

    fn started_command(command: &str) -> StartedCommandMetadata {
        StartedCommandMetadata {
            command: command.to_owned(),
            start_ts: Some(chrono::Local::now()),
            pwd: Some("/tmp".to_owned()),
            shell: Some("zsh".to_owned()),
            username: Some("tester".to_owned()),
            hostname: Some("host".to_owned()),
            session_id: Some(SessionId::from(7)),
            workflow_command: None,
            git_branch: None,
        }
    }

    fn finished_command() -> FinishedCommandMetadata {
        FinishedCommandMetadata {
            exit_code: ExitCode::from(0),
            start_ts: chrono::Local::now(),
            completed_ts: chrono::Local::now(),
            session_id: SessionId::from(7),
        }
    }

    fn secret_block(excluded_from_saved_history: bool) -> BlockCompleted {
        let mut block = SerializedBlock::new_for_test(
            SECRET_COMMAND.as_bytes().to_vec(),
            SECRET_OUTPUT.to_vec(),
        );
        block.excluded_from_saved_history = excluded_from_saved_history;
        BlockCompleted {
            pane_id: vec![PANE_UUID],
            block: Arc::new(block),
            is_local: true,
        }
    }

    fn layout_snapshot() -> AppState {
        AppState {
            windows: vec![test_terminal_window_snapshot(false)],
            active_window_index: Some(0),
            block_lists: Default::default(),
        }
    }

    fn count_commands(conn: &mut SqliteConnection) -> i64 {
        persistence::schema::commands::dsl::commands
            .count()
            .get_result(conn)
            .expect("commands should count")
    }

    fn count_blocks(conn: &mut SqliteConnection) -> i64 {
        persistence::schema::blocks::dsl::blocks
            .count()
            .get_result(conn)
            .expect("blocks should count")
    }

    fn assert_database_is_intact(conn: &mut SqliteConnection) {
        let integrity: Vec<IntegrityRow> = diesel::sql_query("PRAGMA integrity_check")
            .load(conn)
            .expect("integrity_check should run");
        assert_eq!(integrity.len(), 1);
        assert_eq!(integrity[0].integrity_check, "ok");
        let violations: Vec<ForeignKeyViolation> = diesel::sql_query("PRAGMA foreign_key_check")
            .load(conn)
            .expect("foreign_key_check should run");
        assert!(violations.is_empty(), "no foreign key may be violated");
    }

    /// The bytes of the database file and of its write-ahead log and shared-memory file.
    fn database_bytes(database_path: &std::path::Path) -> Vec<u8> {
        let mut bytes = Vec::new();
        for suffix in ["", "-wal", "-shm"] {
            let path = format!("{}{suffix}", database_path.display());
            if let Ok(contents) = std::fs::read(path) {
                bytes.extend(contents);
            }
        }
        bytes
    }

    fn contains(haystack: &[u8], needle: &[u8]) -> bool {
        haystack
            .windows(needle.len())
            .any(|window| window == needle)
    }

    fn send_secret_session(writer: &super::super::WriterHandles) {
        for event in [
            ModelEvent::Snapshot(layout_snapshot()),
            ModelEvent::InsertCommand {
                metadata: started_command(SECRET_COMMAND),
            },
            ModelEvent::SaveBlock(secret_block(false)),
            ModelEvent::UpdateFinishedCommand {
                metadata: finished_command(),
            },
        ] {
            writer.sender.send(event).expect("event should send");
        }
        writer
            .sender
            .send(ModelEvent::Terminate)
            .expect("terminate should send");
    }

    #[test]
    fn history_off_writes_no_command_or_block_text_to_the_database() {
        let tempdir = tempfile::tempdir().expect("tempdir should be created");
        let database_path = tempdir.path().join("warp.sqlite");
        let conn = setup_database(&database_path).expect("database should initialize");

        let writer = start_writer(conn, database_path.clone(), HistoryPersistence::new(false))
            .expect("writer should start");
        send_secret_session(&writer);
        writer.handle.join().expect("writer should terminate");

        let mut conn = setup_database(&database_path).expect("database should reopen");
        assert_eq!(count_commands(&mut conn), 0);
        assert_eq!(count_blocks(&mut conn), 0);
        assert_database_is_intact(&mut conn);
        drop(conn);

        let bytes = database_bytes(&database_path);
        assert!(
            !contains(&bytes, SECRET_TOKEN),
            "the command must not be on disk"
        );
        assert!(
            !contains(&bytes, SECRET_OUTPUT),
            "the output must not be on disk"
        );
        assert!(
            !contains(&bytes, b"OPENRUN_TEST_TOKEN"),
            "no part of the command may be on disk"
        );

        // Session layout is still saved and restored.
        let mut conn = setup_database(&database_path).expect("database should reopen");
        let restored = read_sqlite_data(&mut conn, PersistedDataScope::Full)
            .expect("persisted data should load")
            .app_state
            .expect("app state should be present");
        assert_eq!(restored.windows.len(), 1);
    }

    #[test]
    fn history_on_writes_commands_and_blocks_and_the_byte_check_sees_them() {
        let tempdir = tempfile::tempdir().expect("tempdir should be created");
        let database_path = tempdir.path().join("warp.sqlite");
        let conn = setup_database(&database_path).expect("database should initialize");

        let writer = start_writer(conn, database_path.clone(), HistoryPersistence::new(true))
            .expect("writer should start");
        send_secret_session(&writer);
        writer.handle.join().expect("writer should terminate");

        let mut conn = setup_database(&database_path).expect("database should reopen");
        assert_eq!(count_commands(&mut conn), 1);
        assert_eq!(count_blocks(&mut conn), 1);
        assert_database_is_intact(&mut conn);
        drop(conn);

        let bytes = database_bytes(&database_path);
        assert!(
            contains(&bytes, SECRET_TOKEN),
            "control: the byte check finds the command"
        );
        assert!(
            contains(&bytes, SECRET_OUTPUT),
            "control: the byte check finds the output"
        );

        let mut conn = setup_database(&database_path).expect("database should reopen");
        let restored = read_sqlite_data(&mut conn, PersistedDataScope::Full)
            .expect("persisted data should load");
        assert_eq!(restored.command_history.len(), 1);
        let restored_blocks = restored.app_state.expect("app state").block_lists;
        assert_eq!(restored_blocks.values().map(Vec::len).sum::<usize>(), 1);
    }

    #[test]
    fn toggling_history_applies_to_the_next_event() {
        let tempdir = tempfile::tempdir().expect("tempdir should be created");
        let database_path = tempdir.path().join("warp.sqlite");
        let mut conn = setup_database(&database_path).expect("database should initialize");
        save_app_state(&mut conn, &layout_snapshot()).expect("layout should save");
        let history = HistoryPersistence::new(true);

        let save = |conn: &mut SqliteConnection, history: &HistoryPersistence| {
            handle_model_event(
                ModelEvent::InsertCommand {
                    metadata: started_command("echo first"),
                },
                conn,
                history,
            )
            .expect("insert should be handled");
            handle_model_event(ModelEvent::SaveBlock(secret_block(false)), conn, history)
                .expect("block should be handled");
        };

        save(&mut conn, &history);
        assert_eq!((count_commands(&mut conn), count_blocks(&mut conn)), (1, 1));

        history.set_enabled(false);
        save(&mut conn, &history);
        handle_model_event(
            ModelEvent::UpdateFinishedCommand {
                metadata: finished_command(),
            },
            &mut conn,
            &history,
        )
        .expect("update should be handled");
        assert_eq!((count_commands(&mut conn), count_blocks(&mut conn)), (1, 1));

        history.set_enabled(true);
        save(&mut conn, &history);
        assert_eq!((count_commands(&mut conn), count_blocks(&mut conn)), (2, 2));
    }

    #[test]
    fn blocks_for_commands_the_shell_keeps_out_of_history_are_not_saved() {
        let tempdir = tempfile::tempdir().expect("tempdir should be created");
        let database_path = tempdir.path().join("warp.sqlite");
        let mut conn = setup_database(&database_path).expect("database should initialize");
        save_app_state(&mut conn, &layout_snapshot()).expect("layout should save");

        handle_model_event(
            ModelEvent::SaveBlock(secret_block(true)),
            &mut conn,
            &HistoryPersistence::new(true),
        )
        .expect("block should be handled");
        assert_eq!(count_blocks(&mut conn), 0);
        drop(conn);
        assert!(!contains(&database_bytes(&database_path), SECRET_TOKEN));
    }

    #[test]
    fn without_history_scope_restores_layout_but_not_commands_or_blocks() {
        let tempdir = tempfile::tempdir().expect("tempdir should be created");
        let database_path = tempdir.path().join("warp.sqlite");
        let mut conn = setup_database(&database_path).expect("database should initialize");
        save_app_state(&mut conn, &layout_snapshot()).expect("layout should save");
        let history = HistoryPersistence::new(true);
        handle_model_event(
            ModelEvent::InsertCommand {
                metadata: started_command(SECRET_COMMAND),
            },
            &mut conn,
            &history,
        )
        .expect("insert should be handled");
        handle_model_event(
            ModelEvent::SaveBlock(secret_block(false)),
            &mut conn,
            &history,
        )
        .expect("block should be handled");

        let restored = read_sqlite_data(&mut conn, PersistedDataScope::for_gui(false))
            .expect("persisted data should load");
        assert!(restored.command_history.is_empty());
        let app_state = restored.app_state.expect("layout should still restore");
        assert_eq!(app_state.windows.len(), 1);
        assert!(app_state.block_lists.is_empty());

        let restored = read_sqlite_data(&mut conn, PersistedDataScope::for_gui(true))
            .expect("persisted data should load");
        assert_eq!(restored.command_history.len(), 1);
        assert_eq!(restored.app_state.expect("app state").block_lists.len(), 1);
    }

    fn delete_saved_history_through_the_writer(
        conn: &mut SqliteConnection,
        history: &HistoryPersistence,
    ) -> Result<SavedHistoryDeleted, String> {
        let (done, outcome) = futures::channel::oneshot::channel();
        handle_model_event(
            ModelEvent::DeleteSavedHistory { done: Some(done) },
            conn,
            history,
        )
        .expect("delete should be handled");
        futures::executor::block_on(outcome).expect("delete should report an outcome")
    }

    #[test]
    fn deleting_saved_history_removes_rows_and_text_and_keeps_the_database_intact() {
        let tempdir = tempfile::tempdir().expect("tempdir should be created");
        let database_path = tempdir.path().join("warp.sqlite");
        let mut conn = setup_database(&database_path).expect("database should initialize");
        save_app_state(&mut conn, &layout_snapshot()).expect("layout should save");
        save_workspace_metadata(&mut conn, test_workspace_metadata("/tmp/repo"))
            .expect("workspace metadata should save");
        let history = HistoryPersistence::new(true);
        for _ in 0..3 {
            handle_model_event(
                ModelEvent::InsertCommand {
                    metadata: started_command(SECRET_COMMAND),
                },
                &mut conn,
                &history,
            )
            .expect("insert should be handled");
        }
        for _ in 0..2 {
            handle_model_event(
                ModelEvent::SaveBlock(secret_block(false)),
                &mut conn,
                &history,
            )
            .expect("block should be handled");
        }
        assert!(contains(&database_bytes(&database_path), SECRET_TOKEN));

        let deleted = delete_saved_history_through_the_writer(&mut conn, &history)
            .expect("delete should succeed");
        assert_eq!(
            deleted,
            SavedHistoryDeleted {
                commands: 3,
                blocks: 2
            }
        );
        assert_eq!((count_commands(&mut conn), count_blocks(&mut conn)), (0, 0));
        assert_database_is_intact(&mut conn);

        // The connection is still open, so this also covers the write-ahead log.
        let bytes = database_bytes(&database_path);
        assert!(
            !contains(&bytes, SECRET_TOKEN),
            "deleted commands must not stay on disk"
        );
        assert!(
            !contains(&bytes, SECRET_OUTPUT),
            "deleted output must not stay on disk"
        );

        // Layout and unrelated tables are untouched, and saving still works afterwards.
        let restored = read_sqlite_data(&mut conn, PersistedDataScope::Full)
            .expect("persisted data should load");
        assert_eq!(restored.app_state.expect("app state").windows.len(), 1);
        assert_eq!(restored.workspace_metadata.len(), 1);
        handle_model_event(
            ModelEvent::InsertCommand {
                metadata: started_command("echo after"),
            },
            &mut conn,
            &history,
        )
        .expect("insert should be handled");
        assert_eq!(count_commands(&mut conn), 1);
        assert_database_is_intact(&mut conn);
    }

    #[test]
    fn deleting_saved_history_works_while_saving_is_off_and_on_an_empty_database() {
        let tempdir = tempfile::tempdir().expect("tempdir should be created");
        let database_path = tempdir.path().join("warp.sqlite");
        let mut conn = setup_database(&database_path).expect("database should initialize");
        handle_model_event(
            ModelEvent::InsertCommand {
                metadata: started_command(SECRET_COMMAND),
            },
            &mut conn,
            &HistoryPersistence::new(true),
        )
        .expect("insert should be handled");

        let off = HistoryPersistence::new(false);
        let deleted = delete_saved_history_through_the_writer(&mut conn, &off)
            .expect("delete should succeed while saving is off");
        assert_eq!(
            deleted,
            SavedHistoryDeleted {
                commands: 1,
                blocks: 0
            }
        );
        let deleted = delete_saved_history_through_the_writer(&mut conn, &off)
            .expect("deleting nothing should succeed");
        assert_eq!(deleted, SavedHistoryDeleted::default());
        assert_database_is_intact(&mut conn);
        assert!(!contains(&database_bytes(&database_path), SECRET_TOKEN));
    }

    #[test]
    fn deleting_saved_history_through_the_writer_thread_reports_the_outcome() {
        let tempdir = tempfile::tempdir().expect("tempdir should be created");
        let database_path = tempdir.path().join("warp.sqlite");
        let conn = setup_database(&database_path).expect("database should initialize");
        let writer = start_writer(conn, database_path.clone(), HistoryPersistence::new(true))
            .expect("writer should start");
        for event in [
            ModelEvent::Snapshot(layout_snapshot()),
            ModelEvent::InsertCommand {
                metadata: started_command(SECRET_COMMAND),
            },
            ModelEvent::SaveBlock(secret_block(false)),
        ] {
            writer.sender.send(event).expect("event should send");
        }
        let (done, outcome) = futures::channel::oneshot::channel();
        writer
            .sender
            .send(ModelEvent::DeleteSavedHistory { done: Some(done) })
            .expect("delete should send");
        let deleted = futures::executor::block_on(outcome)
            .expect("writer should answer")
            .expect("delete should succeed");
        assert_eq!(
            deleted,
            SavedHistoryDeleted {
                commands: 1,
                blocks: 1
            }
        );
        writer
            .sender
            .send(ModelEvent::Terminate)
            .expect("terminate should send");
        writer.handle.join().expect("writer should terminate");

        let bytes = database_bytes(&database_path);
        assert!(!contains(&bytes, SECRET_TOKEN));
        assert!(!contains(&bytes, SECRET_OUTPUT));
    }
}
