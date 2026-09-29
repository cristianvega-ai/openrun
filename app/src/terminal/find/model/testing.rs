//! Exports helper test-only methods for use in unit and integration tests.
use super::TerminalFindModel;

impl TerminalFindModel {
    /// Returns the number of visible matches in the block list. The controller's match count
    /// already excludes matches hidden by block filters.
    pub fn visible_block_list_match_count(&self) -> usize {
        self.async_find_controller.match_count()
    }
}
