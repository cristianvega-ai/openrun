//! Inline history menu for up-arrow history.
//!
//! Shows the command history of the terminal session.
mod data_source;
mod search_item;
mod view;

pub use data_source::{AcceptHistoryItem, InlineHistoryMenuDataSource};
pub use view::{InlineHistoryMenuEvent, InlineHistoryMenuView};
