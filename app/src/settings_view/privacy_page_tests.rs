use std::sync::mpsc::sync_channel;
use std::time::Duration;

use pathfinder_geometry::vector::vec2f;
use settings::Setting as _;
use warpui::platform::WindowStyle;
use warpui::{
    App, Presenter, SingletonEntity as _, TypedActionView as _, WindowId, WindowInvalidation,
};

use super::{PrivacyPageAction, PrivacyPageView};
use crate::appearance::Appearance;
use crate::persistence::{ModelEvent, SavedHistoryDeleted};
use crate::resource_center::TipsCompleted;
use crate::settings::{HistorySettings, PrivacySettings};
use crate::settings_view::keybindings::KeybindingChangedNotifier;
use crate::settings_view::privacy::{DeleteHistoryModal, DeleteHistoryModalEvent};
use crate::settings_view::settings_page::SettingsPageMeta as _;
use crate::terminal::History;
use crate::terminal::general_settings::UserDefaultShellUnsupportedBannerState;
use crate::test_util::assert_eventually;
use crate::test_util::settings::initialize_settings_for_tests;
use crate::workspace::ToastStack;
use crate::{GlobalResourceHandles, GlobalResourceHandlesProvider};

/// Renders the root view of `window_id`, which panics if any element is built incorrectly.
fn render_window(app: &mut App, window_id: WindowId) {
    let root_view_id = app
        .root_view_id(window_id)
        .expect("window should have a root view");
    let mut presenter = Presenter::new(window_id);
    let invalidation = WindowInvalidation {
        updated: [root_view_id].into_iter().collect(),
        ..Default::default()
    };
    app.update(move |ctx| {
        presenter.invalidate(invalidation, ctx);
        presenter.build_scene(vec2f(900., 700.), 1., None, ctx);
    });
}

fn history_saving_is_on(app: &App) -> bool {
    app.read(|ctx| *HistorySettings::as_ref(ctx).save_command_history.value())
}

#[test]
fn turning_history_off_offers_to_delete_and_confirming_sends_the_delete_event() {
    App::test((), |mut app| async move {
        initialize_settings_for_tests(&mut app);
        app.add_singleton_model(|_| Appearance::mock());
        app.add_singleton_model(|_| KeybindingChangedNotifier::new());
        app.add_singleton_model(PrivacySettings::mock);
        app.add_singleton_model(|_| History::default());
        app.add_singleton_model(|_| ToastStack);
        let tips_handle = app.add_model(|_| TipsCompleted::default());
        let banner_handle =
            app.add_model(|_| UserDefaultShellUnsupportedBannerState::default_value());
        let (sender, receiver) = sync_channel(8);
        app.add_singleton_model(move |_ctx| {
            GlobalResourceHandlesProvider::new(GlobalResourceHandles {
                model_event_sender: Some(sender),
                tips_completed: tips_handle,
                user_default_shell_unsupported_banner_model_handle: banner_handle,
                settings_file_error: None,
            })
        });
        let (window_id, page) = app.add_window(WindowStyle::NotStealFocus, PrivacyPageView::new);
        render_window(&mut app, window_id);

        assert!(history_saving_is_on(&app));
        page.read(&app, |page, _| {
            assert!(!page.delete_history_modal.is_open());
        });

        // Turning saving off writes the setting and offers to delete what is already saved.
        page.update(&mut app, |page, ctx| {
            page.handle_action(&PrivacyPageAction::ToggleSaveCommandHistory, ctx);
        });
        assert!(!history_saving_is_on(&app));
        page.read(&app, |page, _| {
            assert!(page.delete_history_modal.is_open());
        });
        render_window(&mut app, window_id);
        assert!(receiver.try_recv().is_err(), "nothing is deleted yet");

        // Keeping the saved history closes the dialog and deletes nothing.
        page.update(&mut app, |page, ctx| {
            page.handle_delete_history_modal_event(&DeleteHistoryModalEvent::Close, ctx);
        });
        page.read(&app, |page, _| {
            assert!(!page.delete_history_modal.is_open());
        });
        assert!(
            receiver.try_recv().is_err(),
            "closing the dialog deletes nothing"
        );

        // The button in the settings page opens the same dialog; confirming sends the event.
        page.update(&mut app, |page, ctx| {
            page.handle_action(&PrivacyPageAction::ShowDeleteHistoryModal, ctx);
        });
        page.read(&app, |page, _| {
            assert!(page.delete_history_modal.is_open());
        });
        page.update(&mut app, |page, ctx| {
            page.handle_delete_history_modal_event(&DeleteHistoryModalEvent::Confirm, ctx);
        });
        page.read(&app, |page, _| {
            assert!(!page.delete_history_modal.is_open());
        });

        let event = receiver
            .recv_timeout(Duration::from_secs(5))
            .expect("the delete event should be sent");
        let ModelEvent::DeleteSavedHistory { done: Some(done) } = event else {
            panic!("expected DeleteSavedHistory, got {event:?}");
        };
        assert!(
            page.read(&app, |page, _| page.delete_history_in_progress),
            "the button is disabled while the delete runs"
        );
        done.send(Ok(SavedHistoryDeleted {
            commands: 2,
            blocks: 1,
        }))
        .expect("the page should be waiting for the result");
        assert_eventually!(
            !page.read(&app, |page, _| page.delete_history_in_progress),
            "the page should finish the delete"
        );

        // Turning saving back on does not offer a delete.
        page.update(&mut app, |page, ctx| {
            page.handle_action(&PrivacyPageAction::ToggleSaveCommandHistory, ctx);
        });
        assert!(history_saving_is_on(&app));
        page.read(&app, |page, _| {
            assert!(!page.delete_history_modal.is_open());
        });
    });
}

#[test]
fn the_delete_history_dialog_renders_in_both_forms() {
    App::test((), |mut app| async move {
        initialize_settings_for_tests(&mut app);
        app.add_singleton_model(|_| Appearance::mock());
        let (window_id, dialog) =
            app.add_window(WindowStyle::NotStealFocus, DeleteHistoryModal::new);
        render_window(&mut app, window_id);
        dialog.update(&mut app, |dialog, ctx| {
            dialog.set_offered_after_turning_off(true, ctx);
        });
        render_window(&mut app, window_id);
    });
}

#[test]
fn settings_search_finds_the_history_settings_on_the_privacy_page() {
    App::test((), |mut app| async move {
        initialize_settings_for_tests(&mut app);
        app.add_singleton_model(|_| Appearance::mock());
        app.add_singleton_model(|_| KeybindingChangedNotifier::new());
        app.add_singleton_model(PrivacySettings::mock);
        let (_, page) = app.add_window(WindowStyle::NotStealFocus, PrivacyPageView::new);

        for query in [
            "history",
            "save command history",
            "block output",
            "delete saved history",
            "clear",
            "up arrow",
        ] {
            let matched = page.update(&mut app, |page, ctx| page.update_filter(query, ctx));
            assert!(
                matched.is_truthy(),
                "{query:?} should match the history setting"
            );
        }
        let matched = page.update(&mut app, |page, ctx| page.update_filter("zzzzzz", ctx));
        assert!(!matched.is_truthy());
    });
}
