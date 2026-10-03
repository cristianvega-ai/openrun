use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::mpsc::{Receiver, sync_channel};

use chrono::{TimeZone, Utc};
use lsp::supported_servers::LSPServerType;
use warpui::{App, SingletonEntity};

use super::{EnablementState, LSPEnablementResultForFile, PersistedWorkspace, WorkspaceMetadata};
use crate::persistence::ModelEvent;
use crate::settings::CodeSettings;
use crate::test_util::settings::initialize_settings_for_tests;

fn metadata(path: &str, navigated_secs: Option<i64>) -> WorkspaceMetadata {
    WorkspaceMetadata {
        path: PathBuf::from(path),
        navigated_ts: navigated_secs.map(|secs| Utc.timestamp_opt(secs, 0).unwrap()),
        modified_ts: None,
        queried_ts: None,
    }
}

fn persisted_events(rx: &Receiver<ModelEvent>) -> Vec<ModelEvent> {
    rx.try_iter().collect()
}

#[test]
fn enabling_a_server_creates_and_persists_the_workspace() {
    App::test((), |mut app| async move {
        let (tx, rx) = sync_channel(16);
        let handle =
            app.add_model(|ctx| PersistedWorkspace::new(vec![], HashMap::new(), Some(tx), ctx));

        handle.update(&mut app, |workspace, _| {
            workspace.enable_lsp_server_for_path(Path::new("/repo"), LSPServerType::RustAnalyzer);
        });

        handle.read(&app, |workspace, _| {
            let paths: Vec<PathBuf> = workspace.workspaces().map(|ws| ws.path).collect();
            assert_eq!(paths, vec![PathBuf::from("/repo")]);
            let enabled: Vec<LSPServerType> = workspace
                .enabled_lsp_servers(Path::new("/repo/src/main.rs"))
                .expect("workspace should exist")
                .collect();
            assert_eq!(enabled, vec![LSPServerType::RustAnalyzer]);
        });

        let events = persisted_events(&rx);
        assert!(matches!(
            events.as_slice(),
            [
                ModelEvent::UpsertWorkspaceMetadata { metadata },
                ModelEvent::UpsertWorkspaceLanguageServer {
                    workspace_path,
                    lsp_type: LSPServerType::RustAnalyzer,
                    enabled: EnablementState::Yes,
                },
            ] if metadata.path == Path::new("/repo") && workspace_path == Path::new("/repo")
        ));
    })
}

#[test]
fn disabling_a_server_keeps_the_workspace_and_persists_the_choice() {
    App::test((), |mut app| async move {
        let (tx, rx) = sync_channel(16);
        let handle =
            app.add_model(|ctx| PersistedWorkspace::new(vec![], HashMap::new(), Some(tx), ctx));

        handle.update(&mut app, |workspace, _| {
            workspace.enable_lsp_server_for_path(Path::new("/repo"), LSPServerType::Pyright);
            workspace.disable_lsp_server_for_path(Path::new("/repo"), LSPServerType::Pyright);
        });

        handle.read(&app, |workspace, _| {
            assert!(
                workspace
                    .enabled_lsp_servers(Path::new("/repo"))
                    .expect("workspace should exist")
                    .next()
                    .is_none()
            );
            let all: Vec<(LSPServerType, EnablementState)> = workspace
                .all_lsp_servers(Path::new("/repo"), false)
                .expect("workspace should exist")
                .collect();
            assert_eq!(all, vec![(LSPServerType::Pyright, EnablementState::No)]);
        });

        assert!(matches!(
            persisted_events(&rx).last(),
            Some(ModelEvent::UpsertWorkspaceLanguageServer {
                lsp_type: LSPServerType::Pyright,
                enabled: EnablementState::No,
                ..
            })
        ));
    })
}

#[test]
fn file_lookup_uses_the_nearest_workspace_root() {
    App::test((), |mut app| async move {
        let handle =
            app.add_model(|ctx| PersistedWorkspace::new(vec![], HashMap::new(), None, ctx));

        handle.update(&mut app, |workspace, _| {
            workspace.enable_lsp_server_for_path(Path::new("/repo"), LSPServerType::RustAnalyzer);
        });

        handle.read(&app, |workspace, _| {
            assert_eq!(
                workspace.root_for_workspace(Path::new("/repo/src/lib.rs")),
                Some(Path::new("/repo"))
            );
            assert!(matches!(
                workspace.has_enabled_lsp_server_for_file_path(Path::new("/repo/src/lib.rs")),
                LSPEnablementResultForFile::Enabled
            ));
            assert!(matches!(
                workspace.has_enabled_lsp_server_for_file_path(Path::new("/repo/main.py")),
                LSPEnablementResultForFile::LSPNotEnabled { root_name: Some(name) } if name == "repo"
            ));
            assert!(matches!(
                workspace.has_enabled_lsp_server_for_file_path(Path::new("/other/main.rs")),
                LSPEnablementResultForFile::LSPNotEnabled { root_name: None }
            ));
            assert!(matches!(
                workspace.has_enabled_lsp_server_for_file_path(Path::new("/repo/notes.unknown")),
                LSPEnablementResultForFile::UnsupportedLanguage
            ));
        });
    })
}

#[test]
fn restored_language_servers_attach_to_their_workspace() {
    App::test((), |mut app| async move {
        let servers = HashMap::from([(
            PathBuf::from("/repo"),
            HashMap::from([(LSPServerType::GoPls, EnablementState::Yes)]),
        )]);
        let handle = app.add_model(|ctx| {
            PersistedWorkspace::new(vec![metadata("/repo", Some(10))], servers, None, ctx)
        });

        handle.read(&app, |workspace, _| {
            assert_eq!(workspace.total_lsp_server_count(false), 1);
            let enabled: Vec<LSPServerType> = workspace
                .enabled_lsp_servers(Path::new("/repo/cmd/main.go"))
                .expect("workspace should exist")
                .collect();
            assert_eq!(enabled, vec![LSPServerType::GoPls]);
        });
    })
}

#[test]
fn workspaces_are_listed_most_recently_touched_first() {
    App::test((), |mut app| async move {
        let handle = app.add_model(|ctx| {
            PersistedWorkspace::new(
                vec![
                    metadata("/old", Some(10)),
                    metadata("/new", Some(30)),
                    metadata("/middle", Some(20)),
                ],
                HashMap::new(),
                None,
                ctx,
            )
        });

        handle.read(&app, |workspace, _| {
            let paths: Vec<PathBuf> = workspace.workspaces().map(|ws| ws.path).collect();
            assert_eq!(
                paths,
                vec![
                    PathBuf::from("/new"),
                    PathBuf::from("/middle"),
                    PathBuf::from("/old"),
                ]
            );
        });
    })
}

#[test]
fn last_touched_is_the_latest_timestamp() {
    let workspace = WorkspaceMetadata {
        path: PathBuf::from("/repo"),
        navigated_ts: Some(Utc.timestamp_opt(10, 0).unwrap()),
        modified_ts: Some(Utc.timestamp_opt(30, 0).unwrap()),
        queried_ts: Some(Utc.timestamp_opt(20, 0).unwrap()),
    };
    assert_eq!(
        workspace.last_touched(),
        Some(Utc.timestamp_opt(30, 0).unwrap())
    );
    assert_eq!(metadata("/repo", None).last_touched(), None);
}

#[test]
fn language_server_downloads_are_disabled_by_default() {
    App::test((), |mut app| async move {
        initialize_settings_for_tests(&mut app);

        CodeSettings::handle(&app).read(&app, |settings, _| {
            assert!(!*settings.allow_language_server_downloads);
        });
    })
}

#[test]
fn install_is_refused_while_language_server_downloads_are_disabled() {
    use std::cell::RefCell;
    use std::rc::Rc;

    use super::{LSPInstallationStatus, PersistedWorkspaceEvent};
    use crate::workspace::ToastStack;

    App::test((), |mut app| async move {
        initialize_settings_for_tests(&mut app);
        app.add_singleton_model(|_| ToastStack);
        let handle =
            app.add_model(|ctx| PersistedWorkspace::new(vec![], HashMap::new(), None, ctx));

        let statuses = Rc::new(RefCell::new(Vec::new()));
        app.update(|ctx| {
            let statuses = statuses.clone();
            ctx.subscribe_to_model(&handle, move |_, event, _| {
                if let PersistedWorkspaceEvent::InstallStatusUpdate { status, .. } = event {
                    statuses.borrow_mut().push(*status);
                }
            });
        });

        handle.update(&mut app, |workspace, ctx| {
            workspace.handle_install_lsp(
                PathBuf::from("/repo/src/main.rs"),
                PathBuf::from("/repo"),
                LSPServerType::RustAnalyzer,
                None,
                ctx,
            );
        });

        assert_eq!(
            *statuses.borrow(),
            vec![LSPInstallationStatus::NotInstalled]
        );
        handle.read(&app, |workspace, _| {
            assert_eq!(
                workspace
                    .lsp_installation_status
                    .get(&LSPServerType::RustAnalyzer),
                Some(&LSPInstallationStatus::NotInstalled)
            );
            assert!(
                workspace
                    .enabled_lsp_servers(Path::new("/repo"))
                    .is_none_or(|mut servers| servers.next().is_none())
            );
        });
    })
}
