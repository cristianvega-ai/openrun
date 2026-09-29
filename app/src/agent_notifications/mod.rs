//! In-app notifications for CLI agent sessions: the notification model, the toast stack, and the
//! notifications mailbox.

pub(crate) mod item;
pub(crate) mod item_rendering;
mod model;
pub(crate) mod toast_stack;
pub(crate) mod view;

pub(crate) use item::{
    NotificationCategory, NotificationFilter, NotificationId, NotificationItem, NotificationItems,
};
pub(crate) use model::{AgentNotificationsEvent, AgentNotificationsModel};

pub fn init(app: &mut warpui::AppContext) {
    view::NotificationMailboxView::init(app);
}
