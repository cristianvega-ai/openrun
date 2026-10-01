#![cfg_attr(not(feature = "local_fs"), allow(dead_code))]

cfg_if::cfg_if! {
    if #[cfg(feature = "local_fs")] {
        mod block_list;
        mod sqlite;
        pub mod commands;
    }
}

pub use persistence::model;
#[cfg_attr(not(feature = "local_fs"), expect(unused_imports))]
pub use persistence::schema;

#[cfg(feature = "integration_tests")]
pub mod testing;

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::SyncSender;
use std::sync::{Arc, OnceLock};
use std::thread::JoinHandle;

use chrono::{DateTime, Local};
use instant::Instant;
use lsp::supported_servers::LSPServerType;
#[cfg(any(feature = "local_fs", feature = "integration_tests"))]
pub use sqlite::database_file_path_for_current_scope;
// Only re-exported for integration tests (via `integration_testing::persistence`);
// in-crate code should resolve paths through `database_file_path_for_current_scope`.
#[cfg(any(feature = "local_fs", feature = "integration_tests"))]
#[cfg_attr(not(feature = "integration_tests"), expect(unused_imports))]
pub use sqlite::database_file_path_for_scope;
#[cfg(any(feature = "local_fs", feature = "integration_tests"))]
pub use sqlite::establish_ro_connection;
#[cfg(all(test, feature = "local_fs"))]
pub(crate) use sqlite::persist_events_for_test;
use warp_core::command::ExitCode;
use warp_errors::report_error;
use warpui::{Entity, SingletonEntity};

use self::model::Project;
use crate::app_state::AppState;
use crate::suggestions::ignored_suggestions_model::SuggestionType;
use crate::terminal::history::PersistedCommand;
use crate::terminal::model::block::SerializedBlock;
use crate::terminal::model::session::SessionId;
use crate::workspace_metadata::{EnablementState, WorkspaceMetadata as CodeWorkspaceMetadata};

#[derive(Clone)]
pub enum PersistenceScope {
    /// The GUI app (and other launch modes that share its database).
    App,
}

/// The [`PersistenceScope`] this process's persistence was initialized with.
///
/// Set once by [`initialize`]. Code that opens ad-hoc read-only connections
/// should resolve the database path through [`current_scope`] (or
/// `database_file_path_for_current_scope`) rather than hardcoding a scope, so
/// it reads the same database as the writer.
static CURRENT_SCOPE: OnceLock<PersistenceScope> = OnceLock::new();

/// Returns the scope [`initialize`] was called with, defaulting to
/// [`PersistenceScope::App`] when persistence has not been initialized (e.g.
/// tests that construct models directly).
pub fn current_scope() -> PersistenceScope {
    CURRENT_SCOPE
        .get()
        .cloned()
        .unwrap_or(PersistenceScope::App)
}

/// Which subsets of [`PersistedData`] a launch mode actually consumes.
///
/// Loading everything unconditionally is expensive (GUI session-restore
/// payloads dominate startup on large databases), so headless launch modes
/// opt out of the data they never read.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PersistedDataScope {
    /// The GUI app: everything, including window/tab/block session
    /// restoration and command history.
    Full,
    /// The GUI app with the "Save command history" setting off: window, tab
    /// and pane layout is restored, but neither the saved command history nor
    /// the saved block command text and output is read.
    WithoutHistory,
}

impl PersistedDataScope {
    /// The scope for the GUI app given the "Save command history" setting.
    pub fn for_gui(save_command_history: bool) -> Self {
        if save_command_history {
            PersistedDataScope::Full
        } else {
            PersistedDataScope::WithoutHistory
        }
    }

    /// Window/tab/pane snapshots.
    fn session_restoration(self) -> bool {
        matches!(
            self,
            PersistedDataScope::Full | PersistedDataScope::WithoutHistory
        )
    }

    /// Blocks (command text and output) saved for session restoration.
    fn restored_blocks(self) -> bool {
        matches!(self, PersistedDataScope::Full)
    }

    /// Shell-command history.
    fn command_history(self) -> bool {
        matches!(self, PersistedDataScope::Full)
    }
}

/// Whether the writer thread may persist command history and block text.
///
/// The writer thread checks this for every event that carries command text or
/// output, so a disabled history is enforced in one place no matter which part
/// of the app sends the event. Clones share the same flag.
#[derive(Clone, Debug)]
pub struct HistoryPersistence(Arc<AtomicBool>);

impl HistoryPersistence {
    pub fn new(enabled: bool) -> Self {
        Self(Arc::new(AtomicBool::new(enabled)))
    }

    pub fn is_enabled(&self) -> bool {
        self.0.load(Ordering::SeqCst)
    }

    pub fn set_enabled(&self, enabled: bool) {
        self.0.store(enabled, Ordering::SeqCst);
    }
}

/// Initializes the persistence "subsystem".
///
/// Returns the previously-persisted data, if any, and handles for
/// writing updated data to persist, if the persistence subsystem is
/// available.
#[cfg_attr(not(feature = "local_fs"), allow(unused_variables))]
pub fn initialize(
    scope: PersistenceScope,
    data_scope: PersistedDataScope,
    history: HistoryPersistence,
) -> (Option<Box<PersistedData>>, Option<WriterHandles>) {
    // Record the scope for ad-hoc read-only connections; keep the first value
    // if this is ever called more than once in a process (e.g. tests).
    let _ = CURRENT_SCOPE.set(scope.clone());
    cfg_if::cfg_if! {
        if #[cfg(feature = "local_fs")] {
            sqlite::initialize(scope, data_scope, history)
        } else {
            (None, None)
        }
    }
}

/// Holds interfaces to the writer thread.
pub struct WriterHandles {
    pub handle: JoinHandle<()>,
    pub sender: SyncSender<ModelEvent>,
}

/// Model for interacting with the writer thread.
pub struct PersistenceWriter {
    thread_handle: Option<JoinHandle<()>>,
    model_event_sender: Option<SyncSender<ModelEvent>>,
}

impl PersistenceWriter {
    pub fn new(handle: Option<WriterHandles>) -> Self {
        let (thread_handle, model_event_sender) = match handle {
            Some(handle) => (Some(handle.handle), Some(handle.sender)),
            None => (None, None),
        };
        Self {
            thread_handle,
            model_event_sender,
        }
    }

    /// Sending half for sending model updates to the persistence writer thread.
    pub fn sender(&self) -> Option<SyncSender<ModelEvent>> {
        self.model_event_sender.clone()
    }

    /// Synchronously terminate the SQLite writer thread.
    pub fn terminate(&mut self) {
        if let Some(handle) = self.thread_handle.take() {
            let start = Instant::now();
            let Some(sender) = self.sender() else {
                report_error!("Model event sender should exist if thread handle is set");
                return;
            };
            if let Err(err) = sender.send(ModelEvent::Terminate) {
                report_error!(
                    anyhow::Error::new(err).context("Could not terminate SQLite writer thread")
                );
            }
            if handle.join().is_err() {
                report_error!("SQLite writer thread panicked");
            }
            log::info!("Shut down SQLite writer in {:?}", start.elapsed());
        }
    }
}

impl Drop for PersistenceWriter {
    fn drop(&mut self) {
        self.terminate();
    }
}

impl Entity for PersistenceWriter {
    type Event = ();
}

impl SingletonEntity for PersistenceWriter {}

/// The data read from the local database at startup.
pub struct PersistedData {
    /// Session restoration data. `None` when the launch mode's
    /// [`PersistedDataScope`] excludes it entirely (the daemon).
    pub app_state: Option<AppState>,

    pub command_history: Vec<PersistedCommand>,
    pub workspace_metadata: Vec<CodeWorkspaceMetadata>,
    pub workspace_language_servers: HashMap<PathBuf, HashMap<LSPServerType, EnablementState>>,
    pub projects: Vec<Project>,
    pub ignored_suggestions: Vec<(String, SuggestionType)>,
}

#[derive(Clone, Debug)]
pub struct BlockCompleted {
    pub pane_id: Vec<u8>,
    /// Indicates if the block was created locally (e.g. not in a remote session)
    pub is_local: bool,
    pub block: Arc<SerializedBlock>,
}

/// How much saved history [`ModelEvent::DeleteSavedHistory`] removed.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SavedHistoryDeleted {
    pub commands: usize,
    pub blocks: usize,
}

#[derive(Debug)]
pub struct StartedCommandMetadata {
    pub command: String,
    pub start_ts: Option<DateTime<Local>>,
    pub pwd: Option<String>,
    pub shell: Option<String>,
    pub username: Option<String>,
    pub hostname: Option<String>,
    pub session_id: Option<SessionId>,
    pub git_branch: Option<String>,
    pub workflow_command: Option<String>,
}

#[derive(Debug)]
pub struct FinishedCommandMetadata {
    pub exit_code: ExitCode,
    pub start_ts: DateTime<Local>,
    pub completed_ts: DateTime<Local>,
    pub session_id: SessionId,
}

#[derive(Debug)]
pub enum ModelEvent {
    SaveBlock(BlockCompleted),
    DeleteBlocks(Vec<u8>),
    /// Deletes every saved command and every saved block's command text and output, whether or not
    /// history saving is enabled. `done` receives the outcome once the database has been compacted.
    DeleteSavedHistory {
        done: Option<futures::channel::oneshot::Sender<Result<SavedHistoryDeleted, String>>>,
    },
    Snapshot(AppState),
    InsertCommand {
        metadata: StartedCommandMetadata,
    },
    UpdateFinishedCommand {
        metadata: FinishedCommandMetadata,
    },
    /// Close the SQLite writer thread when the app is about to quit.
    Terminate,
    UpsertWorkspaceMetadata {
        metadata: Box<CodeWorkspaceMetadata>,
    },
    UpsertProject {
        project: Project,
    },
    DeleteProject {
        path: String,
    },
    AddIgnoredSuggestion {
        suggestion: String,
        suggestion_type: SuggestionType,
    },
    RemoveIgnoredSuggestion {
        suggestion: String,
        suggestion_type: SuggestionType,
    },
    UpsertWorkspaceLanguageServer {
        workspace_path: PathBuf,
        lsp_type: LSPServerType,
        enabled: EnablementState,
    },
}
