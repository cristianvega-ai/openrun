use std::collections::HashMap;

// User default keys
const IS_ACTIVE_AI_ENABLED: &str = "IsActiveAIEnabled";

pub fn user_defaults_map_with_active_ai(enabled: bool) -> HashMap<String, String> {
    HashMap::from_iter([(IS_ACTIVE_AI_ENABLED.to_owned(), enabled.to_string())])
}

/// User defaults for predictable AI input behavior needed in evals.
///
/// This allows tests to more reliably enter and exit AI input mode.
///
/// * UDI is enabled
pub fn user_defaults_map_for_ai_input() -> HashMap<String, String> {
    HashMap::from_iter([(
        "InputBoxTypeSetting".to_owned(),
        serde_json::to_string("Universal").unwrap(),
    )])
}
