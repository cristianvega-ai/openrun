use crate::request_context::RequestContext;
use crate::schema;
use crate::user::DiscoverableTeamData;
use crate::workspace::Workspace;

/*
query GetWorkspacesMetadataForUser($requestContext: RequestContext!) {
  user(requestContext: $requestContext) {
    ... on UserOutput {
      user {
        profile {
          uid
        }
        workspaces {
          uid
          name
          members {
            uid
            email
            role
            isDisabled
          }
          teams {
            uid
            name
            inviteLink
            members {
              uid
              email
              role
              isDisabled
            }
            visibility
            featureModelChoice { ... }
          }
          openTeams {
            teamUid
            numMembers
            name
            teamAcceptingInvites
          }
          billingMetadata {
            customerType
            tier {
              name
              description
              warpAiPolicy {
                limit
                isCodeSuggestionsToggleable
                isPromptSuggestionsToggleable
                isNextCommandEnabled
                isGitOperationsAiEnabled
              }
              teamSizePolicy {
                isUnlimited
                limit
              }
              sessionSharingPolicy {
                enabled
                maxSessionBytesSize
              }
              anyoneWithLinkSharingPolicy {
                toggleable
              }
              directLinkSharingPolicy {
                toggleable
              }
              byoApiKeyPolicy {
                enabled
              }
              byoEndpointPolicy {
                enabled
              }
              managedByokByoePolicy {
                enabled
              }
            }
          }
          settings {
            isDiscoverable
            isInviteLinkEnabled
            llmSettings {
              enabled
            }
            teamByo {
              firstPartyEnabled
              endpointsEnabled
              allowUserKeys
              allowUserEndpoints
              firstPartyKeys {
                provider
                credentialUid
              }
              endpoints {
                uid
                name
                enabled
                credentialUid
                models {
                  configKey
                  slug
                  alias
                  displayName
                  enabled
                }
              }
            }
            telemetrySettings {
              forceEnabled
            }
            linkSharingSettings {
              anyoneWithLinkSharingEnabled
              directLinkSharingEnabled
            }
            codebaseContextSettings {
              enabled
            }
          }
          pendingEmailInvites {
            email
            expired
            teamUid
          }
          inviteLinkDomainRestrictions {
            uid
            domain
          }
          isEligibleForDiscovery
        }
        discoverableTeams {
          teamUid
          numMembers
          name
          teamAcceptingInvites
        }
      }
    }
  }
}
*/

#[derive(cynic::QueryVariables, Debug)]
pub struct GetWorkspacesMetadataForUserVariables {
    pub request_context: RequestContext,
}

#[derive(cynic::QueryFragment, Debug)]
pub struct UserOutput {
    pub user: User,
}

#[derive(cynic::InlineFragments, Debug)]
pub enum UserResult {
    UserOutput(UserOutput),
    #[cynic(fallback)]
    Unknown,
}

#[derive(cynic::QueryFragment, Debug)]
pub struct User {
    pub profile: UserProfile,
    pub workspaces: Vec<Workspace>,
    pub discoverable_teams: Vec<DiscoverableTeamData>,
}

#[derive(cynic::QueryFragment, Debug)]
#[cynic(graphql_type = "FirebaseProfile")]
pub struct UserProfile {
    pub uid: String,
}

#[derive(cynic::QueryFragment, Debug)]
#[cynic(
    graphql_type = "RootQuery",
    variables = "GetWorkspacesMetadataForUserVariables"
)]
pub struct GetWorkspacesMetadataForUser {
    #[arguments(requestContext: $request_context)]
    pub user: UserResult,
}
crate::client::define_operation! {
    get_workspaces_metadata_for_user(GetWorkspacesMetadataForUserVariables) -> GetWorkspacesMetadataForUser;
}
