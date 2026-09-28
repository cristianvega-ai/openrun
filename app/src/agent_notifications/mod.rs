//! In-app notifications for agent sessions: the notification model, the toast stack, and the
//! notifications mailbox.

pub(crate) mod item;
pub(crate) mod item_rendering;
mod model;
pub(crate) mod toast_stack;
pub(crate) mod view;

pub(crate) use item::{
    NotificationCategory, NotificationFilter, NotificationId, NotificationItem, NotificationItems,
    NotificationOrigin, NotificationSourceAgent,
};
pub(crate) use model::{AgentManagementEvent, AgentNotificationsModel};

pub fn init(app: &mut warpui::AppContext) {
    view::NotificationMailboxView::init(app);
}
