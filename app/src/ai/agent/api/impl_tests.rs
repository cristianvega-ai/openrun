use warp_core::features::FeatureFlag;
use warp_multi_agent_api as api;

use super::{
    api_keys_with_warp_credit_fallback_setting, get_supported_cli_agent_tools, get_supported_tools,
};
use crate::ai::agent::api::RequestParams;
use crate::ai::blocklist::SessionContext;
use crate::ai::llms::LLMId;
use crate::terminal::model::session::SessionType;

fn request_params_with_ask_user_question_enabled(ask_user_question_enabled: bool) -> RequestParams {
    let model = LLMId::from("test-model");

    RequestParams {
        input: vec![],
        conversation_token: None,
        forked_from_conversation_token: None,
        tasks: vec![],
        existing_suggestions: None,
        metadata: None,
        session_context: SessionContext::new_for_test(),
        model: model.clone(),
        coding_model: model.clone(),
        cli_agent_model: model,
        context_window_limit: None,
        planning_enabled: true,
        should_redact_secrets: false,
        member_byo_credentials_allowed: false,
        api_keys: None,
        custom_model_providers: None,
        custom_model_routers: None,
        allow_use_of_warp_credits: false,
        autonomy_level: api::AutonomyLevel::Supervised,
        isolation_level: api::IsolationLevel::None,
        web_search_enabled: false,
        ask_user_question_enabled,
        research_agent_enabled: false,
        supported_tools_override: None,
    }
}

fn request_params_for_remote() -> RequestParams {
    let mut params = request_params_with_ask_user_question_enabled(false);
    params.session_context =
        SessionContext::new_with_session_type_for_test(Some(SessionType::WarpifiedRemote));
    params
}

#[test]
fn api_keys_with_warp_credit_fallback_setting_returns_none_without_keys_or_fallback() {
    let api_keys = api_keys_with_warp_credit_fallback_setting(None, false);

    assert!(api_keys.is_none());
}

#[test]
fn api_keys_with_warp_credit_fallback_setting_creates_fallback_only_api_keys() {
    let api_keys = api_keys_with_warp_credit_fallback_setting(None, true)
        .expect("fallback setting should create ApiKeys");

    assert!(api_keys.allow_use_of_warp_credits);
    assert!(api_keys.anthropic.is_empty());
    assert!(api_keys.openai.is_empty());
    assert!(api_keys.google.is_empty());
    assert!(api_keys.open_router.is_empty());
    assert!(api_keys.aws_credentials.is_none());
}

#[test]
fn api_keys_with_warp_credit_fallback_setting_preserves_existing_keys() {
    let api_keys = api_keys_with_warp_credit_fallback_setting(
        Some(api::request::settings::ApiKeys {
            anthropic: "anthropic-key".to_string(),
            openai: String::new(),
            google: String::new(),
            open_router: String::new(),
            grok_oauth_access_token: String::new(),
            allow_use_of_warp_credits: false,
            aws_credentials: None,
            google_cloud_credentials: None,
            chatgpt_delegated_access_token: String::new(),
            skip_chatgpt_subscription: false,
        }),
        true,
    )
    .expect("existing ApiKeys should be preserved");

    assert_eq!(api_keys.anthropic, "anthropic-key");
    assert!(api_keys.allow_use_of_warp_credits);
}

#[test]
fn supported_tools_omits_ask_user_question_when_disabled() {
    let params = request_params_with_ask_user_question_enabled(false);
    let supported_tools = get_supported_tools(&params);

    assert!(!supported_tools.contains(&api::ToolType::AskUserQuestion));
}

#[test]
fn supported_tools_includes_ask_user_question_when_enabled_and_feature_flag_is_enabled() {
    if !FeatureFlag::AskUserQuestion.is_enabled() {
        return;
    }

    let params = request_params_with_ask_user_question_enabled(true);
    let supported_tools = get_supported_tools(&params);

    assert!(supported_tools.contains(&api::ToolType::AskUserQuestion));
}

#[test]
fn supported_tools_include_upload_artifact_when_feature_flag_is_enabled() {
    let _flag = FeatureFlag::ArtifactCommand.override_enabled(true);
    let params = request_params_with_ask_user_question_enabled(false);
    let supported_tools = get_supported_tools(&params);

    assert!(supported_tools.contains(&api::ToolType::UploadFileArtifact));
}

#[test]
fn supported_tools_omit_upload_artifact_when_feature_flag_is_disabled() {
    let _flag = FeatureFlag::ArtifactCommand.override_enabled(false);
    let params = request_params_with_ask_user_question_enabled(false);
    let supported_tools = get_supported_tools(&params);

    assert!(!supported_tools.contains(&api::ToolType::UploadFileArtifact));
}

#[test]
fn remote_supported_tools_omit_file_and_search_tools() {
    let params = request_params_for_remote();
    let supported_tools = get_supported_tools(&params);
    let supported_cli_agent_tools = get_supported_cli_agent_tools(&params);

    assert!(!supported_tools.contains(&api::ToolType::ReadFiles));
    assert!(!supported_tools.contains(&api::ToolType::SearchCodebase));
    assert!(!supported_cli_agent_tools.contains(&api::ToolType::ReadFiles));
    assert!(!supported_cli_agent_tools.contains(&api::ToolType::SearchCodebase));
}
