use std::collections::HashSet;

use warp_core::channel::ChannelState;
pub use warp_core::features::*;

/// Mark all features which should be enabled on the current channel as enabled.
/// This sets global feature flag state and should never be called in a unit test.
pub fn init_feature_flags() {
    for flag in enabled_features() {
        flag.set_enabled(true);
    }
    mark_initialized();
}

/// Returns all feature flags which should be enabled in the current channel.
pub fn enabled_features() -> HashSet<FeatureFlag> {
    // Enable features overridden for the given channel.
    let mut flags = ChannelState::additional_features();

    let platform_flags: &[FeatureFlag] = &[FeatureFlag::ITermImages, FeatureFlag::KittyImages];
    flags.extend(platform_flags.iter().copied());

    flags
}
