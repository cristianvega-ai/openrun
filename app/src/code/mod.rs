use std::any::Any;
use std::fmt::Debug;

use pathfinder_geometry::rect::RectF;
use warp_errors::{ErrorExt, register_error};
use warp_util::file::FileSaveError;
use warpui::AppContext;
use warpui::elements::DropTargetData;

pub mod find_references_view;
pub mod language_server_extension;
#[path = "local_code_editor.rs"]
pub mod local_code_editor;
pub use local_code_editor::ShowFindReferencesCard;
pub mod buffer_location;
pub mod editor;
pub mod editor_management;
pub mod global_buffer_model;
pub mod language_server_shutdown_manager;
pub mod lsp_logs;

#[derive(Debug, thiserror::Error)]
pub enum ImmediateSaveError {
    #[error("No FileId")]
    NoFileId,
    #[error("failed to save file: {0:#}")]
    FailedToSave(#[from] FileSaveError),
    #[error("There is no file tab currently selected")]
    NoActiveFileTab,
}

impl ErrorExt for ImmediateSaveError {
    fn is_actionable(&self) -> bool {
        match self {
            ImmediateSaveError::NoFileId | ImmediateSaveError::NoActiveFileTab => true,
            ImmediateSaveError::FailedToSave(err) => err.is_actionable(),
        }
    }
}
register_error!(ImmediateSaveError);

/// Trait to determine whether we should show the comment editor based on state held
/// by the parent of the [`CodeEditorView`].
pub trait ShowCommentEditorProvider: Debug + 'static {
    /// Returns whether the comment editor should be shown given the location of the line where
    /// the editor would be shown.
    fn should_show_comment_editor(&self, editor_line_location: RectF, app: &AppContext) -> bool;
}

#[derive(Debug)]
struct NoopCommentEditorProvider;

impl ShowCommentEditorProvider for NoopCommentEditorProvider {
    fn should_show_comment_editor(&self, _editor_line_location: RectF, _app: &AppContext) -> bool {
        false
    }
}

/// Trait to determine whether we should show the find references card based on state held
/// by the parent of the [`CodeEditorView`].
pub trait ShowFindReferencesCardProvider: Debug + 'static {
    /// Returns whether the find references card should be shown given the location of the anchor
    /// point where the card would be positioned.
    fn should_show_find_references_card(
        &self,
        card_anchor_location: RectF,
        app: &AppContext,
    ) -> bool;
}

#[derive(Debug)]
pub struct NoopFindReferencesCardProvider;

impl ShowFindReferencesCardProvider for NoopFindReferencesCardProvider {
    fn should_show_find_references_card(
        &self,
        _card_anchor_location: RectF,
        _app: &AppContext,
    ) -> bool {
        false
    }
}

#[derive(Debug)]
pub enum SaveStatus {
    /// Save completed immediately and successfully.
    SavedImmediately,
    /// Save operation is in progress asynchronously (e.g., save-as dialog).
    AsyncSaveInProgress,
    /// Save failed with an error.
    Failed(#[allow(unused)] ImmediateSaveError),
}

#[derive(Debug, Eq, PartialEq)]
pub enum SaveOutcome {
    Canceled,
    Failed,
    Succeeded,
}

pub mod file_tree;
pub mod footer;
mod icon;

pub mod active_file;
pub mod opened_files;
pub mod outline;
pub use icon::icon_from_file_path;

#[path = "view.rs"]
pub mod view;

pub fn init(app: &mut AppContext) {
    self::view::init(app);
    self::file_tree::init(app);
    self::find_references_view::init(app);
}

#[derive(Debug)]
pub struct EditorTabBarDropTargetData {
    index: usize,
}

impl DropTargetData for EditorTabBarDropTargetData {
    fn as_any(&self) -> &dyn Any {
        self
    }
}
