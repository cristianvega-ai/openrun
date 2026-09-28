// Onboarding library crate

mod model;
mod onboarding_view;
pub mod slides;
pub mod telemetry;

cfg_if::cfg_if! {
    if #[cfg(feature = "bin")] {
        mod telemetry_provider;
        pub use telemetry_provider::MockTelemetryContextProvider;
    }
}

pub use model::{SelectedSettings, UICustomizationSettings};
pub use onboarding_view::{OnboardingView, OnboardingViewAction, OnboardingViewEvent, init};
pub use telemetry::OnboardingEvent;
