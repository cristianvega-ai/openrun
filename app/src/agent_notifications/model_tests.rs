use settings::Setting as _;
use warp_errors::report_if_error;
use warpui::{App, EntityId, ModelHandle, SingletonEntity};

use super::AgentNotificationsModel;
use crate::agent_notifications::{NotificationCategory, NotificationFilter};
use crate::settings::CLIAgentSettings;
use crate::terminal::CLIAgent;
use crate::terminal::cli_agent_sessions::CLIAgentSessionsModel;
use crate::test_util::settings::initialize_settings_for_tests;
use crate::workspace::WorkspaceRegistry;

fn setup_app(app: &mut App) -> ModelHandle<AgentNotificationsModel> {
    initialize_settings_for_tests(app);
    app.add_singleton_model(|_| CLIAgentSessionsModel::new());
    app.add_singleton_model(|_| WorkspaceRegistry::new());
    app.add_singleton_model(AgentNotificationsModel::new)
}

#[test]
fn add_notification_tracks_unread_activity_when_in_app_notifications_are_hidden() {
    App::test((), |mut app| async move {
        let notifications = setup_app(&mut app);

        CLIAgentSettings::handle(&app).update(&mut app, |settings, ctx| {
            report_if_error!(settings.show_agent_notifications.set_value(false, ctx));
        });

        let terminal_view_id = EntityId::new();
        notifications.update(&mut app, |model, ctx| {
            model.add_notification(
                "Agent task".to_owned(),
                "Task completed.".to_owned(),
                NotificationCategory::Complete,
                CLIAgent::Claude,
                terminal_view_id,
                ctx,
            );
        });

        notifications.read(&app, |model, _| {
            assert_eq!(
                model
                    .notifications()
                    .filtered_count(NotificationFilter::All),
                1
            );
            assert!(
                model
                    .notifications()
                    .has_unread_for_terminal_view(terminal_view_id)
            );
        });
    });
}
