use std::cmp::Ordering;

use serde::{Deserialize, Serialize};

use super::team::{DiscoverableTeam, MembershipRole, Team};
use crate::auth::UserUid;
use crate::server::ids::ServerId;

#[derive(Clone, Copy, Hash, Debug, PartialEq, Eq)]
pub struct WorkspaceUid(ServerId);
impl From<String> for WorkspaceUid {
    fn from(uid: String) -> Self {
        WorkspaceUid(ServerId::from_string_lossy(uid))
    }
}
impl From<WorkspaceUid> for String {
    fn from(workspace_uid: WorkspaceUid) -> String {
        workspace_uid.0.to_string()
    }
}
impl From<ServerId> for WorkspaceUid {
    fn from(uid: ServerId) -> Self {
        WorkspaceUid(uid)
    }
}

#[derive(Clone, Debug)]
pub struct Workspace {
    pub uid: WorkspaceUid,
    pub name: String,
    pub teams: Vec<Team>,
    pub open_teams: Vec<DiscoverableTeam>,
    pub billing_metadata: BillingMetadata,
    pub settings: WorkspaceSettings,
    pub invite_link_domain_restrictions: Vec<InviteLinkDomainRestriction>,
    pub pending_email_invites: Vec<EmailInvite>,
    // If the team is eligible for discovery, then show toggle for setting discoverability to the team's admin
    pub is_eligible_for_discovery: bool,
    pub members: Vec<WorkspaceMember>,
    pub total_requests_used_since_last_refresh: i32,
}

impl Workspace {
    pub fn from_local_cache(uid: WorkspaceUid, name: String, teams: Option<Vec<Team>>) -> Self {
        // Derive the workspace billing metadata from the first team's cached billing
        // metadata, if available. This ensures the workspace-level billing info is
        // consistent with team-level data loaded from the cache.
        let billing_metadata = teams
            .as_ref()
            .and_then(|t| t.first())
            .map(|team| team.billing_metadata.clone())
            .unwrap_or_default();
        Self {
            uid,
            name,
            teams: teams.unwrap_or_default(),
            open_teams: Default::default(),
            billing_metadata,
            settings: Default::default(), // TODO: persistence wrapper instead of default
            invite_link_domain_restrictions: Default::default(),
            pending_email_invites: Default::default(),
            is_eligible_for_discovery: false,
            members: Default::default(),
            total_requests_used_since_last_refresh: 0,
        }
    }

    fn get_member_by_email(&self, email: &str) -> Option<&WorkspaceMember> {
        self.members.iter().find(|member| member.email == email)
    }

    pub fn is_workspace_admin(&self, user_email: &str) -> bool {
        self.get_member_by_email(user_email)
            .is_some_and(|member| member.role.is_admin_or_owner())
    }

    pub fn is_native_workspaces_enabled(&self) -> bool {
        self.billing_metadata
            .tier
            .native_workspaces_policy
            .is_some_and(|policy| policy.enabled)
    }

    pub fn joinable_teams(&self) -> impl Iterator<Item = &DiscoverableTeam> {
        self.open_teams.iter().filter(|open_team| {
            let open_team_uid = ServerId::from_string_lossy(&open_team.team_uid);
            self.teams.iter().all(|team| team.uid != open_team_uid)
        })
    }

    pub fn is_native_workspaces_admin(&self, user_email: &str) -> bool {
        self.is_workspace_admin(user_email) && self.is_native_workspaces_enabled()
    }

    pub fn can_be_deleted(&self, current_user_email: &str) -> bool {
        // Current user needs to be an admin and be the only user remaining
        self.is_workspace_admin(current_user_email)
            && self.members.len() == 1
            && self
                .members
                .first()
                .is_some_and(|m| m.email == current_user_email)
    }
}

#[derive(Clone, Eq, PartialEq, Debug)]
pub struct WorkspaceMember {
    pub uid: UserUid,
    pub email: String,
    pub role: MembershipRole,
    pub is_disabled: bool,
    pub usage_info: WorkspaceMemberUsageInfo,
}

#[derive(Clone, Eq, PartialEq, Debug)]
pub struct WorkspaceMemberUsageInfo {
    pub is_unlimited: bool,
    pub request_limit: i32,
    pub requests_used_since_last_refresh: i32,
    pub is_request_limit_prorated: bool,
}

impl PartialOrd for WorkspaceMember {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for WorkspaceMember {
    fn cmp(&self, other: &Self) -> Ordering {
        self.email.cmp(&other.email)
    }
}

#[derive(Clone, Eq, PartialEq, Debug)]
pub struct EmailInvite {
    pub invitee_email: String,
    pub expired: bool,
    pub team_uid: Option<ServerId>,
}

impl PartialOrd for EmailInvite {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for EmailInvite {
    fn cmp(&self, other: &Self) -> Ordering {
        self.invitee_email.cmp(&other.invitee_email)
    }
}

#[derive(Clone, Eq, PartialEq, Debug)]
pub struct InviteLinkDomainRestriction {
    pub uid: ServerId,
    pub domain: String,
}

impl PartialOrd for InviteLinkDomainRestriction {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for InviteLinkDomainRestriction {
    fn cmp(&self, other: &Self) -> Ordering {
        self.domain.cmp(&other.domain)
    }
}

/// This enum is the rust representation of `CustomerType` from the GraphQL Schema.
#[derive(Clone, Copy, Debug, Default, PartialEq, Serialize, Deserialize)]
pub enum CustomerType {
    #[default]
    Free,
    Turbo,
    SelfServe,
    Prosumer,
    Legacy,
    Enterprise,
    Business,
    Lightspeed,
    Build,
    BuildMax,
    Unknown,
}

/// Rust representation of feature policies from the GraphQL Schema.
#[derive(Clone, Debug, Copy, Serialize, Deserialize)]
pub struct WarpAiPolicy {
    pub limit: i64,
    pub is_code_suggestions_toggleable: bool,
    pub is_prompt_suggestions_toggleable: bool,
    pub is_next_command_enabled: bool,
    pub is_git_operations_ai_enabled: bool,
}
#[derive(Clone, Debug, Copy, Serialize, Deserialize)]
pub struct WorkspaceSizePolicy {
    pub is_unlimited: bool,
    pub limit: i64,
}

#[derive(Clone, Debug, Copy, Serialize, Deserialize)]
pub struct SessionSharingPolicy {
    pub is_enabled: bool,
    pub max_session_size: u64,
}

#[derive(Clone, Debug, Copy, Serialize, Deserialize)]
pub struct AIAutonomyPolicy {
    pub is_enabled: bool,
    pub toggleable: bool,
}

#[derive(Clone, Debug, Copy, Serialize, Deserialize)]
pub struct TelemetryDataCollectionPolicy {
    pub default: bool,
    pub toggleable: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct UgcDataCollectionPolicy {
    pub default_setting: UgcCollectionEnablementSetting,
    pub toggleable: bool,
}

#[derive(Clone, Debug, Copy, Serialize, Deserialize)]
pub struct CodebaseContextPolicy {
    pub toggleable: bool,
    pub index_limit: Option<u32>,
    pub max_files_per_repo: u32,
}

#[derive(Clone, Debug, Copy, Serialize, Deserialize)]
pub struct ByoApiKeyPolicy {
    pub enabled: bool,
}

#[derive(Clone, Debug, Copy, Serialize, Deserialize)]
pub struct ByoEndpointPolicy {
    pub enabled: bool,
}

#[derive(Clone, Debug, Copy, Serialize, Deserialize)]
pub struct ManagedByokByoePolicy {
    pub enabled: bool,
}

#[derive(Clone, Debug, Copy, Serialize, Deserialize)]
pub struct MultiAdminPolicy {
    pub enabled: bool,
}

#[derive(Clone, Debug, Copy, Serialize, Deserialize)]
pub struct NativeWorkspacesPolicy {
    pub enabled: bool,
}

#[derive(Clone, Debug, Copy, Serialize, Deserialize)]
pub struct AmbientAgentsPolicy {
    pub max_concurrent_agents: i32,
    pub instance_shape: Option<InstanceShape>,
}

#[derive(Clone, Debug, Copy, Serialize, Deserialize)]
pub struct InstanceShape {
    pub vcpus: i32,
    pub memory_gb: i32,
}

/// This struct is the rust representation of `Tier` from the GraphQL Schema.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Tier {
    pub name: String,
    pub description: String,
    pub warp_ai_policy: Option<WarpAiPolicy>,
    pub workspace_size_policy: Option<WorkspaceSizePolicy>,
    pub session_sharing_policy: Option<SessionSharingPolicy>,
    pub ai_autonomy_policy: Option<AIAutonomyPolicy>,
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

/// This struct is the rust representation of `BillingMetadata` from the GraphQL Schema.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct BillingMetadata {
    pub tier: Tier,
    pub customer_type: CustomerType,
}

impl BillingMetadata {
    pub fn is_byo_api_key_enabled(&self) -> bool {
        self.tier
            .byo_api_key_policy
            .is_some_and(|policy| policy.enabled)
    }

    pub fn is_byo_endpoint_enabled(&self) -> bool {
        self.tier
            .byo_endpoint_policy
            .is_some_and(|policy| policy.enabled)
    }

    pub fn is_managed_byok_byoe_enabled(&self) -> bool {
        self.tier
            .managed_byok_byoe_policy
            .is_some_and(|policy| policy.enabled)
    }
}

#[cfg(test)]
#[path = "workspace_tests.rs"]
mod tests;

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct TelemetrySettings {
    pub force_enabled: bool,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub enum UgcCollectionEnablementSetting {
    Disable,
    Enable,
    #[default]
    RespectUserSetting,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct UgcCollectionSettings {
    pub setting: UgcCollectionEnablementSetting,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub enum AdminEnablementSetting {
    Disable,
    Enable,
    #[default]
    RespectUserSetting,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct CloudConversationStorageSettings {
    pub setting: AdminEnablementSetting,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct LinkSharingSettings {
    pub anyone_with_link_sharing_enabled: bool,
    pub direct_link_sharing_enabled: bool,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct EnterpriseSecretRegex {
    pub pattern: String,
    #[serde(default)]
    pub name: Option<String>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct SecretRedactionSettings {
    pub enabled: bool,
    pub regexes: Vec<EnterpriseSecretRegex>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct CodebaseContextSettings {
    pub setting: AdminEnablementSetting,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct WorkspaceSettings {
    pub telemetry_settings: TelemetrySettings,
    pub ugc_collection_settings: UgcCollectionSettings,
    pub cloud_conversation_storage_settings: CloudConversationStorageSettings,
    pub link_sharing_settings: LinkSharingSettings,
    pub secret_redaction_settings: SecretRedactionSettings,
    pub is_invite_link_enabled: bool,
    pub is_discoverable: bool,
    pub codebase_context_settings: CodebaseContextSettings,
}

/// A workspace-governable setting carried on [`TeamSettings`]: the effective
/// `value` plus whether the workspace layer enforces it (mirrors the server's
/// `*SettingInfo` wrappers). The enforcement bit is preserved so future admin UI
/// can distinguish workspace-enforced values from team-owned ones.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct EnforceableSetting<T> {
    pub value: T,
    #[serde(default)]
    pub is_enforced_by_workspace: bool,
}

/// A list setting split by the layer that contributed each entry (mirrors the
/// server's `StringListSettingInfo` / `SecretRedactionRegexListInfo`). `values`
/// is the authoritative merged result; `workspace_entries` / `team_entries` are
/// preserved so future admin UI can present the layers separately.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct SplitListSetting<T> {
    pub values: Vec<T>,
    #[serde(default)]
    pub workspace_entries: Vec<T>,
    #[serde(default)]
    pub team_entries: Vec<T>,
}

impl<T> SplitListSetting<T> {
    /// Whether an admin layer configured this list.
    ///
    /// Empty `values` does not answer that: the two allowlists merge by intersection
    /// server-side, so layers configuring `["ls"]` and `["git status"]` yield empty `values`
    /// with both entry lists populated. Reading `values` alone would call that unconfigured
    /// and fall back to the user's own profile allowlist, granting exemptions neither admin
    /// granted. The denylists and regex lists merge by union, where empty `values` already
    /// implies empty entries, so the entry checks are inert for them.
    ///
    /// Clearing a list stores it as unset rather than empty -- that is how an admin reverts
    /// to no constraint -- so "configured but empty" does not arise. If that changes,
    /// `StringListSettingInfo.isConfigured` answers this directly, once the vendored schema
    /// copy is re-pulled to include it.
    pub fn is_configured(&self) -> bool {
        !(self.values.is_empty()
            && self.workspace_entries.is_empty()
            && self.team_entries.is_empty())
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct TeamSecretRedactionSettings {
    pub enabled: EnforceableSetting<bool>,
    pub regexes: SplitListSetting<EnterpriseSecretRegex>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct TeamLinkSharingSettings {
    pub anyone_with_link_sharing_enabled: EnforceableSetting<bool>,
    pub direct_link_sharing_enabled: EnforceableSetting<bool>,
}

/// The effective settings that apply to a team, combining the workspace layer
/// with the team's own configuration.
///
/// This is intentionally a distinct type from [`WorkspaceSettings`] rather than
/// an alias: it is sourced from the server's effective `Team.settings`. Each
/// workspace-governable group keeps both its effective value **and** the
/// `is_enforced_by_workspace` / workspace-vs-team split metadata (via
/// [`EnforceableSetting`] / [`SplitListSetting`]) so future admin UI can recover
/// those details. Unlike `WorkspaceSettings`, it does not carry the
/// workspace-scoped `is_invite_link_enabled` / `is_discoverable` flags (those
/// remain on [`WorkspaceSettings`] and are read from the current workspace).
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct TeamSettings {
    pub ugc_collection: EnforceableSetting<UgcCollectionEnablementSetting>,
    pub cloud_conversation_storage: EnforceableSetting<AdminEnablementSetting>,
    pub codebase_context: EnforceableSetting<AdminEnablementSetting>,
    pub secret_redaction: TeamSecretRedactionSettings,
    pub link_sharing: TeamLinkSharingSettings,
    pub telemetry_settings: TelemetrySettings,
}
