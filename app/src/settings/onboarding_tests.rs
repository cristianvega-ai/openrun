use onboarding::{SelectedSettings, UICustomizationSettings};
use warpui::{App, SingletonEntity};

use crate::settings::{CLIAgentSettings, CodeSettings, apply_onboarding_settings};
use crate::test_util::settings::initialize_settings_for_tests;
use crate::workspace::tab_settings::TabSettings;

#[test]
fn apply_onboarding_settings_writes_ui_and_cli_agent_choices() {
    App::test((), |mut app| async move {
        initialize_settings_for_tests(&mut app);

        let selected_settings = SelectedSettings {
            ui_customization: UICustomizationSettings {
                use_vertical_tabs: true,
                show_project_explorer: true,
                show_global_search: false,
                show_code_review_button: true,
            },
            cli_agent_toolbar_enabled: false,
            show_agent_notifications: false,
        };
        app.update(|ctx| apply_onboarding_settings(&selected_settings, ctx));

        app.read(|ctx| {
            let tab_settings = TabSettings::as_ref(ctx);
            assert!(*tab_settings.use_vertical_tabs);
            assert!(*tab_settings.show_code_review_button);

            let code_settings = CodeSettings::as_ref(ctx);
            assert!(*code_settings.show_project_explorer);
            assert!(!*code_settings.show_global_search);

            let cli_agent_settings = CLIAgentSettings::as_ref(ctx);
            assert!(!*cli_agent_settings.should_render_cli_agent_footer);
            assert!(!*cli_agent_settings.show_agent_notifications);
        });
    })
}
