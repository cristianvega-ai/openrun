//! This module should houses all horizontal/cross-cutting AI functionality throughout
//! Warp (including Agent Mode).
pub(crate) mod active_agent_views_model;
pub(crate) mod agent;
pub(crate) mod agent_conversations_model;
pub(crate) mod agent_management;
pub mod ambient_agents;
pub(crate) mod artifact_download;
pub mod artifacts;
#[cfg(not(target_family = "wasm"))]
pub mod aws_credentials;
pub(crate) mod block_context;
pub(crate) mod blocklist;
pub mod control_code_parser;
pub(crate) mod conversation_details_panel;
#[cfg(feature = "local_fs")]
pub(crate) mod conversation_export;
pub(crate) mod conversation_navigation;
pub(crate) mod conversation_rename;
pub(crate) mod conversation_status_ui;
pub(crate) mod conversation_utils;
pub(crate) mod custom_endpoints;
pub(crate) mod custom_model_routers;
pub(crate) mod document;
pub(crate) mod execution_context;
pub(crate) mod get_relevant_files;
pub(crate) mod harness_display;
pub(crate) mod llms;
pub(crate) mod restored_conversations;
use warpui::AppContext;
pub mod execution_profiles;
pub(crate) mod loading;

pub(crate) use ai::paths;

pub fn init(app: &mut AppContext) {
    blocklist::keyboard_navigable_buttons::init(app);
    blocklist::block::number_shortcut_buttons::init(app);
    conversation_details_panel::init(app);
    agent_management::init(app);
}
