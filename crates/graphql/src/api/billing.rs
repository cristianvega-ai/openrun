use crate::schema;
use crate::workspace::UgcCollectionEnablementSetting;

#[derive(cynic::QueryFragment, Debug, Clone)]
pub struct BillingMetadata {
    pub customer_type: CustomerType,
    pub tier: Tier,
}

#[derive(cynic::QueryFragment, Debug, Clone)]
pub struct Tier {
    pub name: String,
    pub description: String,
    pub warp_ai_policy: Option<WarpAiPolicy>,
    pub team_size_policy: Option<TeamSizePolicy>,
    pub session_sharing_policy: Option<SessionSharingPolicy>,
    pub ai_autonomy_policy: Option<AiAutonomyPolicy>,
    pub telemetry_data_collection_policy: Option<TelemetryDataCollectionPolicy>,
    pub ugc_data_collection_policy: Option<UgcDataCollectionPolicy>,
    pub codebase_context_policy: Option<CodebaseContextPolicy>,
    pub byo_api_key_policy: Option<ByoApiKeyPolicy>,
    pub byo_endpoint_policy: Option<ByoEndpointPolicy>,
    pub managed_byok_byoe_policy: Option<ManagedByokByoePolicy>,
    pub multi_admin_policy: Option<MultiAdminPolicy>,
    pub native_workspaces_policy: Option<NativeWorkspacesPolicy>,
    pub ambient_agents_policy: Option<AmbientAgentsPolicy>,
}

#[derive(cynic::QueryFragment, Debug, Clone)]
pub struct SessionSharingPolicy {
    pub enabled: bool,
    pub max_session_bytes_size: i32,
}

#[derive(cynic::QueryFragment, Debug, Clone)]
pub struct AiAutonomyPolicy {
    pub enabled: bool,
    pub toggleable: bool,
}

#[derive(cynic::QueryFragment, Debug, Clone)]
pub struct TeamSizePolicy {
    pub is_unlimited: bool,
    pub limit: i32,
}

#[derive(cynic::QueryFragment, Debug, Clone)]
pub struct WarpAiPolicy {
    pub limit: i32,
    pub is_code_suggestions_toggleable: bool,
    pub is_prompt_suggestions_toggleable: bool,
    pub is_next_command_enabled: bool,
    pub is_git_operations_ai_enabled: bool,
}

#[derive(cynic::QueryFragment, Debug, Clone)]
pub struct TelemetryDataCollectionPolicy {
    pub default: bool,
    pub toggleable: bool,
}

#[derive(cynic::QueryFragment, Debug, Clone)]
pub struct UgcDataCollectionPolicy {
    pub default_setting: UgcCollectionEnablementSetting,
    pub toggleable: bool,
}

#[derive(cynic::QueryFragment, Debug, Clone)]
pub struct CodebaseContextPolicy {
    pub toggleable: bool,
    pub is_unlimited_indices: bool,
    pub max_indices: i32,
    pub max_files_per_repo: i32,
    pub embedding_generation_batch_size: i32,
}

#[derive(cynic::QueryFragment, Debug, Clone)]
pub struct ByoApiKeyPolicy {
    pub enabled: bool,
}

#[derive(cynic::QueryFragment, Debug, Clone)]
pub struct ByoEndpointPolicy {
    pub enabled: bool,
}

#[derive(cynic::QueryFragment, Debug, Clone)]
pub struct ManagedByokByoePolicy {
    pub enabled: bool,
}

#[derive(cynic::QueryFragment, Debug, Clone)]
pub struct MultiAdminPolicy {
    pub enabled: bool,
}

#[derive(cynic::QueryFragment, Debug, Clone)]
pub struct NativeWorkspacesPolicy {
    pub enabled: bool,
}

#[derive(cynic::QueryFragment, Debug, Clone)]
pub struct AmbientAgentsPolicy {
    pub enabled: bool,
    pub toggleable: bool,
    pub max_concurrent_agents: i32,
    pub instance_shape: Option<InstanceShape>,
}

#[derive(cynic::QueryFragment, Debug, Clone)]
pub struct InstanceShape {
    pub vcpus: i32,
    pub memory_gb: i32,
}

#[derive(cynic::Enum, Clone, Debug)]
pub enum CustomerType {
    Enterprise,
    Free,
    Legacy,
    ProTrial,
    Prosumer,
    SelfServe,
    TeamTrial,
    Turbo,
    Business,
    Lightspeed,
    Build,
    BuildMax,
    #[cynic(fallback)]
    Other(String),
}
