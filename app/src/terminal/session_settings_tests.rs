use settings::{PrivatePreferences, PublicPreferences, SettingsManager};
use warpui::SingletonEntity as _;
use warpui_extras::user_preferences::UserPreferences as _;
use warpui_extras::user_preferences::in_memory::InMemoryPreferences;

use super::*;

#[test]
fn stored_agent_toolbar_layout_is_ignored() {
    warpui::App::test((), |mut app| async move {
        let stored = InMemoryPreferences::default();
        stored
            .write_value_with_hierarchy(
                "agent_toolbar_chip_selection_setting",
                r#"{"Custom":{"left":[{"ContextChip":"WorkingDirectory"},"ModelSelector","NLDToggle"],"right":["VoiceInput","ShareSession","HandoffToCloud","FastForwardToggle"]}}"#
                    .to_owned(),
                Some("agents.warp_agent.input"),
                None,
            )
            .unwrap();
        stored
            .write_value_with_hierarchy(
                "cli_agent_toolbar_chip_selection_setting",
                r#""Default""#.to_owned(),
                Some("agents.third_party"),
                None,
            )
            .unwrap();
        app.update(|ctx| {
            ctx.add_singleton_model(move |_| PublicPreferences::new(Box::new(stored)));
            ctx.add_singleton_model(|_| -> PrivatePreferences {
                PrivatePreferences::new(Box::<InMemoryPreferences>::default())
            });
        });
        app.add_singleton_model(|_| SettingsManager::default());
        SessionSettings::register(&mut app);

        let failed_keys = app.update(|ctx| {
            SettingsManager::handle(ctx)
                .update(ctx, |manager, ctx| manager.reload_all_public_settings(ctx))
        });
        assert!(
            failed_keys.is_empty(),
            "a stale agent toolbar layout must not fail any setting: {failed_keys:?}"
        );

        app.read(|ctx| {
            let settings = SessionSettings::as_ref(ctx);
            assert_eq!(
                *settings.cli_agent_footer_chip_selection,
                CLIAgentToolbarChipSelection::Default
            );
        });
    });
}
