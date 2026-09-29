// Onboarding library crate

mod model;
mod onboarding_view;
pub mod slides;

pub use model::{SelectedSettings, UICustomizationSettings};
pub use onboarding_view::{OnboardingView, OnboardingViewAction, OnboardingViewEvent, init};
