pub mod auth_state;
pub mod credentials;
pub mod user_uid;

/// Prefix for API keys used in authentication.
#[cfg_attr(target_family = "wasm", allow(dead_code))]
pub const API_KEY_PREFIX: &str = "wk-";
