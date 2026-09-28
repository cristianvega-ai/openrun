use serde_json::json;
use warp_core::telemetry::TelemetryEvent;

use super::OnboardingEvent;

#[test]
fn slide_and_setting_payloads() {
    assert_eq!(OnboardingEvent::OnboardingStarted.payload(), None);
    assert_eq!(
        OnboardingEvent::SlideViewed {
            slide_name: "customize".to_string(),
        }
        .payload(),
        Some(json!({ "slide_name": "customize" }))
    );
    assert_eq!(
        OnboardingEvent::SettingChanged {
            setting: "theme".to_string(),
            value: "Dark".to_string(),
        }
        .payload(),
        Some(json!({ "setting": "theme", "value": "Dark" }))
    );
}
