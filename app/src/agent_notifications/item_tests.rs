use warpui::EntityId;

use super::*;
use crate::terminal::CLIAgent;

fn make_notification(terminal_view_id: EntityId) -> NotificationItem {
    NotificationItem::new(
        "cli test".to_owned(),
        "cli msg".to_owned(),
        NotificationCategory::Complete,
        CLIAgent::Claude,
        false,
        terminal_view_id,
        None,
    )
}

#[test]
fn remove_by_terminal_view_cleans_up_notification() {
    let mut items = NotificationItems::default();
    let terminal_view_id = EntityId::new();

    items.push(make_notification(terminal_view_id));
    assert_eq!(items.filtered_count(NotificationFilter::All), 1);

    let removed = items.remove_by_terminal_view(terminal_view_id);
    assert!(removed);
    assert_eq!(items.filtered_count(NotificationFilter::All), 0);
}

#[test]
fn remove_by_terminal_view_leaves_unrelated_notifications() {
    let mut items = NotificationItems::default();
    let terminal_a = EntityId::new();
    let terminal_b = EntityId::new();

    items.push(make_notification(terminal_a));
    items.push(make_notification(terminal_b));
    assert_eq!(items.filtered_count(NotificationFilter::All), 2);

    let removed = items.remove_by_terminal_view(terminal_a);
    assert!(removed);
    assert_eq!(items.filtered_count(NotificationFilter::All), 1);

    let remaining = items
        .items_filtered(NotificationFilter::All)
        .next()
        .unwrap();
    assert_eq!(remaining.terminal_view_id, terminal_b);
}

#[test]
fn remove_by_terminal_view_returns_false_when_nothing_to_remove() {
    let mut items = NotificationItems::default();

    let removed = items.remove_by_terminal_view(EntityId::new());
    assert!(!removed);
}

#[test]
fn push_replaces_existing_notification_for_the_same_terminal_view() {
    let mut items = NotificationItems::default();
    let terminal_view_id = EntityId::new();

    items.push(make_notification(terminal_view_id));
    items.push(make_notification(terminal_view_id));
    assert_eq!(items.filtered_count(NotificationFilter::All), 1);
}
