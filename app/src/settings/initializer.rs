use warpui::{Entity, ModelContext, SingletonEntity};

use crate::settings::PrivacySettings;

pub struct SettingsInitializer;

impl Default for SettingsInitializer {
    fn default() -> Self {
        Self::new()
    }
}

impl SettingsInitializer {
    pub fn new() -> Self {
        Self
    }

    /// A hook for changing settings values at app launch.
    ///
    /// Specifically useful for adjusting settings for new users (those who have not completed
    /// onboarding) when the default value of a setting as set in define_settings_group! is no
    /// longer the desired default value, but we don't want to change it for existing users (which
    /// is what would happen if we changed the default value in define_settings_group! in code).
    pub fn handle_app_launch(&self, ctx: &mut ModelContext<Self>) {
        PrivacySettings::handle(ctx).update(ctx, |settings, ctx| {
            settings.initialize_default_regexes_once(ctx);
        });
    }
}

impl Entity for SettingsInitializer {
    type Event = ();
}

/// Mark SettingsInitializer as global application state.
impl SingletonEntity for SettingsInitializer {}

#[cfg(test)]
#[path = "initializer_tests.rs"]
mod tests;
