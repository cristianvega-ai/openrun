use session_sharing_protocol::common::WindowSize;
use warpui::elements::MouseStateHandle;

use super::adapter::Participant;

#[derive(Default)]
pub struct Viewer {
    pub sharer: Option<Participant>,
    pub is_reconnecting: bool,

    /// The handle for the "Request edit access" button for viewers.
    pub input_request_edit_access_button_handle: MouseStateHandle,
    /// The viewer has a pending role request.
    pub pending_role_request: bool,

    pub sharer_size: Option<WindowSize>,

    /// The last natural size (rows, cols) that was reported to the sharer.
    /// Used to deduplicate ReportViewerTerminalSize events.
    pub last_reported_natural_size: Option<(usize, usize)>,
}

impl Viewer {
    pub fn set_is_reconnecting(&mut self, is_reconnectiong: bool) {
        self.is_reconnecting = is_reconnectiong;
    }
}
