//! This module should houses all horizontal/cross-cutting AI functionality throughout
//! Warp (including Agent Mode).
pub(crate) mod agent;
pub mod ambient_agents;
pub mod artifacts;
#[cfg(not(target_family = "wasm"))]
pub mod aws_credentials;
pub(crate) mod block_context;
pub(crate) mod blocklist;
pub(crate) mod conversation_utils;
pub(crate) mod custom_endpoints;
pub(crate) mod custom_model_routers;
pub(crate) mod document;
pub(crate) mod execution_context;
pub mod execution_profiles;
pub(crate) mod get_relevant_files;
pub(crate) mod harness_display;
pub(crate) mod llms;
pub(crate) mod restored_conversations;
