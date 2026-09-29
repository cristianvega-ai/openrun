use warp_core::channel::{Channel, ChannelState};
use warp_core::features::FeatureFlag;
use warp_core::settings::Setting;
use warp_errors::report_if_error;
use warpui::{Entity, ModelContext, SingletonEntity};

use crate::root_view::has_completed_local_onboarding;
use crate::settings::{
    AISettings, FontSettings, PrivacySettings, ThemeSettings, ThinkingDisplayMode,
};
use crate::themes::theme::ThemeKind;

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
        /// We use a font-size of 16px (12pt) on Windows to more closely match the default font size of
        /// Windows terminal.
        const DEFAULT_WINDOWS_MONOSPACE_FONT_SIZE: f32 = 16.;

        // Integration tests start from a fresh profile that never completes onboarding, and are
        // written against the base defaults.
        let is_new_user =
            !has_completed_local_onboarding(ctx) && ChannelState::channel() != Channel::Integration;

        PrivacySettings::handle(ctx).update(ctx, |settings, ctx| {
            settings.initialize_default_regexes_once(ctx);
        });

        if is_new_user {
            if FeatureFlag::DefaultAdeberryTheme.is_enabled() {
                log::debug!("Setting default theme to Adeberry for new user");
                ThemeSettings::handle(ctx).update(ctx, |settings, ctx| {
                    if *settings.theme_kind.value() == ThemeKind::Phenomenon {
                        report_if_error!(settings.theme_kind.set_value(ThemeKind::Adeberry, ctx));
                    }
                });
            }

            if cfg!(windows) {
                log::debug!("Setting default font size to 16px (12pt) for a new Windows user");
                FontSettings::handle(ctx).update(ctx, |settings, ctx| {
                    if !settings.monospace_font_size.is_value_explicitly_set() {
                        report_if_error!(
                            settings
                                .monospace_font_size
                                .set_value(DEFAULT_WINDOWS_MONOSPACE_FONT_SIZE, ctx)
                        );
                    }
                })
            }
        }

        // Migrate the old `KeepThinkingExpanded` bool setting to the new
        // `ThinkingDisplayMode` enum setting.
        //
        // The old setting was a boolean (default: false) that controlled whether
        // agent thinking blocks stayed expanded after streaming. It has been
        // replaced by a three-option enum: ShowAndCollapse (default),
        // AlwaysShow, and NeverShow.
        //
        // If the user explicitly set `KeepThinkingExpanded` to `true`, migrate
        // them to `ThinkingDisplayMode::AlwaysShow` so they don't lose their
        // preference when updating to the new client.
        //
        // TODO(jefflloyd): Remove this approximately 6 weeks from 3/19/26.
        {
            use warp_core::user_preferences::GetUserPreferences as _;

            AISettings::handle(ctx).update(ctx, |ai_settings, ctx| {
                // If the new setting already has a value in preferences, the
                // migration has already run (or the user set it directly).
                let new_key_exists = ctx
                    .private_user_preferences()
                    .read_value("ThinkingDisplayMode")
                    .unwrap_or_default()
                    .is_some();

                if new_key_exists {
                    return;
                }

                // Read the old boolean setting directly from preferences
                // because `KeepThinkingExpanded` has been removed from the
                // `AISettings` struct — there is no typed field left to query.
                let old_value_was_true = ctx
                    .private_user_preferences()
                    .read_value("KeepThinkingExpanded")
                    .unwrap_or_default()
                    .and_then(|v| serde_json::from_str::<bool>(&v).ok())
                    == Some(true);

                if old_value_was_true {
                    report_if_error!(
                        ai_settings
                            .thinking_display_mode
                            .set_value(ThinkingDisplayMode::AlwaysShow, ctx)
                    );
                }

                // Clean up the old key.
                let _ = ctx
                    .private_user_preferences()
                    .remove_value("KeepThinkingExpanded");
            });
        }
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
