use onboarding::{SelectedSettings, UICustomizationSettings};
use settings::Setting as _;
use warp_errors::report_if_error;
use warpui::{AppContext, SingletonEntity as _};

use crate::settings::{CLIAgentSettings, CodeSettings};
use crate::workspace::tab_settings::TabSettings;

/// Applies the settings the user chose in the onboarding slides.
pub(crate) fn apply_onboarding_settings(
    selected_settings: &SelectedSettings,
    app: &mut AppContext,
) {
    apply_ui_customization_settings(&selected_settings.ui_customization, app);

    CLIAgentSettings::handle(app).update(app, |settings, ctx| {
        report_if_error!(
            settings
                .should_render_cli_agent_footer
                .set_value(selected_settings.cli_agent_toolbar_enabled, ctx)
        );
        report_if_error!(
            settings
                .show_agent_notifications
                .set_value(selected_settings.show_agent_notifications, ctx)
        );
    });
}

/// Applies the explicit UI customization settings chosen during the
/// "Customize your UI" onboarding slide.
fn apply_ui_customization_settings(ui: &UICustomizationSettings, app: &mut AppContext) {
    TabSettings::handle(app).update(app, |settings, ctx| {
        report_if_error!(
            settings
                .use_vertical_tabs
                .set_value(ui.use_vertical_tabs, ctx)
        );
        report_if_error!(
            settings
                .show_code_review_button
                .set_value(ui.show_code_review_button, ctx)
        );
    });

    CodeSettings::handle(app).update(app, |settings, ctx| {
        report_if_error!(
            settings
                .show_project_explorer
                .set_value(ui.show_project_explorer, ctx)
        );
        report_if_error!(
            settings
                .show_global_search
                .set_value(ui.show_global_search, ctx)
        );
    });
}

#[cfg(test)]
#[path = "onboarding_tests.rs"]
mod tests;
