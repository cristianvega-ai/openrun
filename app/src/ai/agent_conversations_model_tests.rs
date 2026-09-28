use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use ai::harness::Harness;
use chrono::{DateTime, Duration, Utc};
use instant::Instant;
use parking_lot::Mutex;
use persistence::model::{AgentConversationData, ChargedUsageTotals, ConversationUsageMetadata};
use warp_core::features::FeatureFlag;
use warpui::{App, EntityId, ModelHandle, SingletonEntity};

use super::entry::{
    AgentConversationEntryId, AgentConversationNavigationSubject, AgentConversationProvenance,
};
use super::query::{DEFAULT_RESULT_COUNT, MAX_SEARCH_RESULTS};
use super::{
    AgentConversationsModel, AgentConversationsModelEvent, AgentManagementFilters, ArtifactFilter,
    ConversationMetadata, ConversationUpdateKind, EnvironmentFilter, HarnessFilter, OwnerFilter,
    StatusFilter, TaskFetchState, query_conversation_entries,
};
use crate::ai::active_agent_views_model::ActiveAgentViewsModel;
use crate::ai::agent::api::ServerConversationToken;
use crate::ai::agent::conversation::{
    AIAgentHarness, AIConversation, AIConversationId, ConversationStatus,
    ServerAIConversationMetadata,
};
use crate::ai::ambient_agents::task::TaskPrincipalInfo;
use crate::ai::ambient_agents::{AmbientAgentTask, AmbientAgentTaskId, AmbientAgentTaskState};
use crate::ai::artifacts::Artifact;
use crate::ai::blocklist::history_model::{
    BlocklistAIHistoryEvent, BlocklistAIHistoryModel, ConversationStatusUpdate,
};
use crate::ai::conversation_navigation::ConversationNavigationData;
use crate::auth::AuthStateProvider;
use crate::cloud_object::{Owner, Revision, ServerMetadata, ServerPermissions};
use crate::server::ids::ServerId;
use crate::test_util::ai_agent_tasks::{create_api_task, create_message};
use crate::workspace::{WorkspaceAction, WorkspaceRegistry};
use crate::workspaces::user_workspaces::TeamlessScopeForTest;

/// Creates a test task with specified creator UID and updated_at time
fn create_test_task(
    task_id: &str,
    creator_uid: &str,
    updated_at: DateTime<Utc>,
) -> AmbientAgentTask {
    AmbientAgentTask {
        task_id: task_id.parse().unwrap(),
        parent_run_id: None,
        title: format!("Task {task_id}"),
        state: AmbientAgentTaskState::Succeeded,
        prompt: "test".to_string(),
        created_at: updated_at,
        started_at: Some(updated_at),
        updated_at,
        run_time: Some("PT1S".parse().unwrap()),
        status_message: None,
        source: None,
        execution_location: None,
        session_id: None,
        session_link: None,
        creator: Some(TaskPrincipalInfo {
            creator_type: "USER".to_string(),
            uid: creator_uid.to_string(),
            display_name: Some(format!("User {creator_uid}")),
        }),
        executor: None,
        conversation_id: None,
        request_usage: None,
        agent_config_snapshot: None,
        artifacts: vec![],
        is_sandbox_running: false,
        last_event_sequence: None,
        children: vec![],
        debug_agent_available: false,
        scope: None,
    }
}

type CapturedConversationUpdate = Mutex<Option<ConversationUpdateKind>>;

/// Test-only handler that mirrors the production view subscription: extracts the
/// `ConversationUpdated` payload and stashes it on a shared cell that test cases assert
/// against.
fn handle_agent_conversation_model_event(
    captured: &CapturedConversationUpdate,
    event: &AgentConversationsModelEvent,
) {
    if let AgentConversationsModelEvent::ConversationUpdated { kind } = event {
        *captured.lock() = Some(*kind);
    }
}

/// Subscribes a [`handle_agent_conversation_model_event`] capture cell to `model` and
/// returns the cell so individual cases can assert on the most recent emission without
/// re-implementing the subscription bookkeeping.
fn subscribe_to_conversation_updated(
    app: &mut App,
    model: &ModelHandle<AgentConversationsModel>,
) -> Arc<CapturedConversationUpdate> {
    let captured = Arc::new(Mutex::new(None));
    let captured_clone = captured.clone();
    app.update(|ctx| {
        ctx.subscribe_to_model(model, move |_, event, _| {
            handle_agent_conversation_model_event(&captured_clone, event);
        });
    });
    captured
}

#[test]
fn test_restored_conversation_emits_restored_kind() {
    App::test((), |mut app| async move {
        let _interactive_management_guard =
            FeatureFlag::InteractiveConversationManagementView.override_enabled(true);
        let agent_model = app.add_singleton_model(|_| create_test_model());
        let captured = subscribe_to_conversation_updated(&mut app, &agent_model);

        agent_model.update(&mut app, |model, ctx| {
            model.handle_history_event(
                &BlocklistAIHistoryEvent::UpdatedConversationStatus {
                    conversation_id: AIConversationId::new(),
                    terminal_surface_id: EntityId::new(),
                    update: ConversationStatusUpdate::Restored,
                    new_status: ConversationStatus::Success,
                },
                ctx,
            );
        });

        let captured = *captured.lock();
        assert_eq!(captured, Some(ConversationUpdateKind::Restored));
    });
}

#[test]
fn test_status_transition_emits_status_set_with_filter_buckets() {
    App::test((), |mut app| async move {
        let _interactive_management_guard =
            FeatureFlag::InteractiveConversationManagementView.override_enabled(true);
        let agent_model = app.add_singleton_model(|_| create_test_model());
        let captured = subscribe_to_conversation_updated(&mut app, &agent_model);

        agent_model.update(&mut app, |model, ctx| {
            model.handle_history_event(
                &BlocklistAIHistoryEvent::UpdatedConversationStatus {
                    conversation_id: AIConversationId::new(),
                    terminal_surface_id: EntityId::new(),
                    update: ConversationStatusUpdate::Changed {
                        prev_status: ConversationStatus::InProgress,
                    },
                    new_status: ConversationStatus::Success,
                },
                ctx,
            );
        });

        let captured = *captured.lock();
        assert_eq!(
            captured,
            Some(ConversationUpdateKind::StatusSet {
                prev_filter: StatusFilter::Working,
                new_filter: StatusFilter::Done,
            }),
        );
    });
}

#[test]
fn test_same_bucket_re_emission_emits_status_set_with_equal_filters() {
    App::test((), |mut app| async move {
        let _interactive_management_guard =
            FeatureFlag::InteractiveConversationManagementView.override_enabled(true);
        let agent_model = app.add_singleton_model(|_| create_test_model());
        let captured = subscribe_to_conversation_updated(&mut app, &agent_model);

        agent_model.update(&mut app, |model, ctx| {
            model.handle_history_event(
                &BlocklistAIHistoryEvent::UpdatedConversationStatus {
                    conversation_id: AIConversationId::new(),
                    terminal_surface_id: EntityId::new(),
                    update: ConversationStatusUpdate::Changed {
                        prev_status: ConversationStatus::InProgress,
                    },
                    new_status: ConversationStatus::InProgress,
                },
                ctx,
            );
        });

        let captured = *captured.lock();
        assert_eq!(
            captured,
            Some(ConversationUpdateKind::StatusSet {
                prev_filter: StatusFilter::Working,
                new_filter: StatusFilter::Working,
            }),
        );
    });
}

/// Helper to generate a unique UUID for task IDs
fn make_uuid(index: usize) -> String {
    format!("550e8400-e29b-41d4-a716-{:012}", index)
}

fn create_test_model() -> AgentConversationsModel {
    AgentConversationsModel {
        tasks: HashMap::new(),
        conversations: HashMap::new(),
        task_fetch_state: Default::default(),
        is_loading: true,
    }
}

#[test]
fn local_conversation_sync_finishes_initial_load() {
    App::test((), |mut app| async move {
        let _interactive_management_guard =
            FeatureFlag::InteractiveConversationManagementView.override_enabled(true);
        add_entry_projection_test_models(&mut app);
        let model = app.add_singleton_model(|_| create_test_model());

        model.update(&mut app, |model, ctx| model.sync_conversations(ctx));

        model.read(&app, |model, _| {
            assert!(!model.is_loading());
        });
    });
}

#[test]
fn conversation_query_caps_recent_entries_and_places_newest_last() {
    App::test((), |mut app| async move {
        add_entry_projection_test_models(&mut app);
        let mut model = create_test_model();
        for index in 0..55 {
            insert_conversation_updated_seconds_ago(
                &mut model,
                &format!("Conversation {index}"),
                index,
            );
        }

        app.update(|ctx| {
            let entries = model.get_entries(&all_owner_filters(), &TeamlessScopeForTest, ctx);
            let results = query_conversation_entries(entries, "");

            assert_eq!(results.len(), DEFAULT_RESULT_COUNT);
            assert_eq!(
                results
                    .first()
                    .map(|result| result.entry.display.title.as_str()),
                Some("Conversation 49")
            );
            assert_eq!(
                results
                    .last()
                    .map(|result| result.entry.display.title.as_str()),
                Some("Conversation 0")
            );
            assert!(
                !results
                    .iter()
                    .any(|result| result.entry.display.title == "Conversation 50")
            );
        });
    });
}

#[test]
fn conversation_query_filters_titles_and_caps_best_fuzzy_results() {
    App::test((), |mut app| async move {
        add_entry_projection_test_models(&mut app);
        let mut model = create_test_model();
        for index in 0..=MAX_SEARCH_RESULTS + 2 {
            let title = if index == 1 {
                "Fix unit tests".to_owned()
            } else {
                format!("Deploy service {index}")
            };
            insert_conversation_updated_seconds_ago(&mut model, &title, index);
        }

        app.update(|ctx| {
            let entries = model.get_entries(&all_owner_filters(), &TeamlessScopeForTest, ctx);
            let results = query_conversation_entries(entries, "deploy");

            assert_eq!(results.len(), MAX_SEARCH_RESULTS);
            assert!(
                results
                    .iter()
                    .all(|result| result.entry.display.title.contains("Deploy"))
            );
            assert!(results.windows(2).all(|window| {
                window[0].title_match.as_ref().unwrap().score
                    <= window[1].title_match.as_ref().unwrap().score
            }));
        });
    });
}

#[test]
fn conversation_query_orders_equal_fuzzy_scores_by_recency() {
    App::test((), |mut app| async move {
        add_entry_projection_test_models(&mut app);
        let mut model = create_test_model();
        for index in [0, 2, 1] {
            insert_conversation_updated_seconds_ago(&mut model, "Deploy service", index);
        }

        app.update(|ctx| {
            let entries = model.get_entries(&all_owner_filters(), &TeamlessScopeForTest, ctx);
            let results = query_conversation_entries(entries, "deploy");

            assert!(results.windows(2).all(|window| {
                window[0].entry.display.last_updated <= window[1].entry.display.last_updated
            }));
        });
    });
}

fn insert_conversation_updated_seconds_ago(
    model: &mut AgentConversationsModel,
    title: &str,
    seconds_ago: usize,
) {
    let conversation_id = AIConversationId::new();
    let mut metadata = create_test_conversation_metadata(conversation_id, title);
    metadata.nav_data.last_updated = chrono::Local::now() - Duration::seconds(seconds_ago as i64);
    model.conversations.insert(conversation_id, metadata);
}

fn create_test_conversation_metadata(
    conversation_id: AIConversationId,
    title: &str,
) -> ConversationMetadata {
    ConversationMetadata {
        nav_data: ConversationNavigationData {
            id: conversation_id,
            title: title.to_string(),
            initial_query: None,
            last_updated: chrono::Local::now(),
            terminal_view_id: None,
            window_id: None,
            pane_view_locator: None,
            initial_working_directory: None,
            latest_working_directory: None,
            is_selected: false,
            is_in_active_pane: false,
            is_closed: false,
            server_conversation_token: None,
        },
    }
}

fn create_restored_conversation(
    conversation_id: AIConversationId,
    root_task_id: &str,
    conversation_data: AgentConversationData,
) -> AIConversation {
    let task = create_api_task(
        root_task_id,
        vec![create_message(
            &format!("{root_task_id}-message"),
            root_task_id,
        )],
    );

    AIConversation::new_restored(conversation_id, vec![task], Some(conversation_data))
        .expect("restored conversation should build")
}

fn all_owner_filters() -> AgentManagementFilters {
    AgentManagementFilters {
        owners: OwnerFilter::All,
        ..Default::default()
    }
}

fn add_entry_projection_test_models(app: &mut App) {
    app.add_singleton_model(|_| AuthStateProvider::new_for_test());
    app.add_singleton_model(|_| BlocklistAIHistoryModel::new(vec![], &[]));
    app.add_singleton_model(|_| ActiveAgentViewsModel::new());
    app.add_singleton_model(|_| WorkspaceRegistry::new());
}

fn mock_server_metadata() -> ServerMetadata {
    ServerMetadata {
        uid: ServerId::default(),
        revision: Revision::now(),
        metadata_last_updated_ts: Utc::now().into(),
        trashed_ts: None,
        folder_id: None,
        is_welcome_object: false,
        creator_uid: None,
        last_editor_uid: None,
        current_editor_uid: None,
    }
}

fn mock_server_permissions() -> ServerPermissions {
    ServerPermissions {
        space: Owner::mock_current_user(),
        guests: Vec::new(),
        anyone_link_sharing: None,
        permissions_last_updated_ts: Utc::now().into(),
    }
}

fn create_server_conversation_metadata(
    title: &str,
    server_token: &str,
    ambient_agent_task_id: Option<AmbientAgentTaskId>,
) -> ServerAIConversationMetadata {
    ServerAIConversationMetadata {
        title: title.to_string(),
        working_directory: None,
        harness: AIAgentHarness::Oz,
        usage: ConversationUsageMetadata {
            was_summarized: false,
            context_window_usage: 0.0,
            credits_spent: 0.0,
            platform_credits_spent: 0.0,
            total_provider_cost_in_cents: None,
            credits_spent_for_last_block: None,
            charged_usage_for_last_block: None,
            total_charged_usage: None,
            token_usage: vec![],
            tool_usage_metadata: Default::default(),
            context_window_segments: Vec::new(),
        },
        metadata: mock_server_metadata(),
        creator: None,
        permissions: mock_server_permissions(),
        ambient_agent_task_id,
        server_conversation_token: ServerConversationToken::new(server_token.to_string()),
        artifacts: Vec::new(),
    }
}

#[test]
fn test_get_entries_includes_local_only_entry() {
    App::test((), |mut app| async move {
        add_entry_projection_test_models(&mut app);

        let conversation_id = AIConversationId::new();
        let mut model = create_test_model();
        model.conversations.insert(
            conversation_id,
            create_test_conversation_metadata(conversation_id, "Local conversation"),
        );

        app.update(|ctx| {
            let entries = model.get_entries(&all_owner_filters(), &TeamlessScopeForTest, ctx);

            assert_eq!(entries.len(), 1);
            let entry = &entries[0];
            assert_eq!(
                entry.id,
                AgentConversationEntryId::Conversation(conversation_id)
            );
            assert_eq!(entry.identity.local_conversation_id, Some(conversation_id));
            assert_eq!(entry.identity.ambient_agent_task_id, None);
            assert_eq!(
                entry.provenance,
                AgentConversationProvenance::LocalInteractive
            );
            assert_eq!(entry.display.title, "Local conversation");
        });
    });
}

#[test]
fn test_local_conversation_entry_uses_charged_usage_dollar_total() {
    App::test((), |mut app| async move {
        add_entry_projection_test_models(&mut app);

        let mut conversation = AIConversation::new(false, false);
        conversation.set_credits_spent_for_test(20.0);
        conversation.set_charged_usage_for_test(Some(ChargedUsageTotals {
            input_cost_in_cents: 10.0,
            output_cost_in_cents: 12.0,
            platform_cost_in_cents: 8.0,
            web_search_cost_in_cents: 6.0,
            ..Default::default()
        }));
        let conversation_id = conversation.id();
        BlocklistAIHistoryModel::handle(&app).update(&mut app, |model, ctx| {
            model.restore_conversations(EntityId::new(), vec![conversation], ctx);
        });

        let mut model = create_test_model();
        model.conversations.insert(
            conversation_id,
            create_test_conversation_metadata(conversation_id, "Local conversation"),
        );

        app.update(|ctx| {
            let entries = model.get_entries(&all_owner_filters(), &TeamlessScopeForTest, ctx);

            assert_eq!(entries[0].display.request_usage, Some(20.0));
            assert_eq!(entries[0].display.cost_in_cents, Some(36.0));
        });
    });
}

#[test]
fn test_conversation_metadata_child_predicate_matches_conversation() {
    use crate::ai::blocklist::history_model::AIConversationMetadata;

    // Non-child conversation: neither representation reports a child.
    let plain = AIConversation::new(false, false);
    let plain_metadata = AIConversationMetadata::from(&plain);
    assert!(!plain.is_child_agent_conversation());
    assert_eq!(
        plain_metadata.is_child_agent_conversation(),
        plain.is_child_agent_conversation()
    );

    // Child conversation: the metadata predicate matches the conversation's.
    let mut child = AIConversation::new(false, false);
    child.set_parent_conversation_id(AIConversationId::new());
    let child_metadata = AIConversationMetadata::from(&child);
    assert!(child.is_child_agent_conversation());
    assert_eq!(
        child_metadata.is_child_agent_conversation(),
        child.is_child_agent_conversation()
    );
}

#[test]
fn test_get_entries_includes_cloud_metadata_only_entry() {
    App::test((), |mut app| async move {
        let token = "cloud-token-only";
        add_entry_projection_test_models(&mut app);
        BlocklistAIHistoryModel::handle(&app).update(&mut app, |model, _| {
            model.merge_cloud_conversation_metadata(vec![create_server_conversation_metadata(
                "Cloud conversation",
                token,
                None,
            )]);
        });

        let model = create_test_model();

        app.update(|ctx| {
            let entries = model.get_entries(&all_owner_filters(), &TeamlessScopeForTest, ctx);

            assert_eq!(entries.len(), 1);
            let entry = &entries[0];
            assert_eq!(
                entry
                    .identity
                    .server_conversation_token
                    .as_ref()
                    .map(|t| t.as_str()),
                Some(token)
            );
            assert_eq!(
                entry.provenance,
                AgentConversationProvenance::CloudSyncedConversation
            );
            assert!(entry.backing.has_cloud_data);
            assert!(!entry.backing.has_loaded_conversation);
            assert!(!entry.backing.has_local_persisted_data);
        });
    });
}

#[test]
fn test_resolve_open_action_handles_server_token_subject_without_entry() {
    App::test((), |mut app| async move {
        add_entry_projection_test_models(&mut app);
        app.add_singleton_model(|_| create_test_model());

        let server_token = ServerConversationToken::new("server-token-subject".to_string());
        app.update(|ctx| {
            let action = AgentConversationsModel::resolve_open_action(
                AgentConversationNavigationSubject::ServerToken(server_token.clone()),
                None,
                ctx,
            );

            assert!(matches!(
                action,
                Some(WorkspaceAction::OpenConversationTranscriptViewer {
                    conversation_id,
                }) if conversation_id == server_token
            ));
        });
    });
}

#[test]
fn test_resolve_open_action_opens_metadata_only_cloud_conversation_by_server_token() {
    App::test((), |mut app| async move {
        let token = "metadata-only-token";
        add_entry_projection_test_models(&mut app);
        BlocklistAIHistoryModel::handle(&app).update(&mut app, |model, _| {
            model.merge_cloud_conversation_metadata(vec![create_server_conversation_metadata(
                "Cloud conversation",
                token,
                None,
            )]);
        });
        app.add_singleton_model(|_| create_test_model());

        app.update(|ctx| {
            let entries = AgentConversationsModel::as_ref(ctx).get_entries(
                &all_owner_filters(),
                &TeamlessScopeForTest,
                ctx,
            );
            let entry = entries
                .iter()
                .find(|entry| {
                    entry
                        .identity
                        .server_conversation_token
                        .as_ref()
                        .is_some_and(|server_token| server_token.as_str() == token)
                })
                .expect("metadata-only cloud entry should exist");

            assert!(entry.backing.has_cloud_data);
            assert!(!entry.backing.has_loaded_conversation);
            assert!(!entry.backing.has_local_persisted_data);

            let action = AgentConversationsModel::resolve_open_action(
                AgentConversationNavigationSubject::Entry(entry.id),
                None,
                ctx,
            );

            assert!(matches!(
                action,
                Some(WorkspaceAction::OpenConversationTranscriptViewer {
                    conversation_id,
                }) if conversation_id.as_str() == token
            ));
        });
    });
}

#[test]
fn test_resolve_copy_link_returns_none_for_local_only_unsynced_conversation() {
    App::test((), |mut app| async move {
        add_entry_projection_test_models(&mut app);

        let conversation_id = AIConversationId::new();
        app.add_singleton_model(|_| {
            let mut model = create_test_model();
            model.conversations.insert(
                conversation_id,
                create_test_conversation_metadata(conversation_id, "Local only"),
            );
            model
        });

        app.update(|ctx| {
            let link = AgentConversationsModel::resolve_copy_link(
                AgentConversationNavigationSubject::Entry(AgentConversationEntryId::Conversation(
                    conversation_id,
                )),
                ctx,
            );

            assert_eq!(link, None);

            let entry = AgentConversationsModel::as_ref(ctx)
                .get_entry_by_id(
                    &AgentConversationEntryId::Conversation(conversation_id),
                    ctx,
                )
                .expect("conversation entry should exist");
            assert!(!entry.capabilities.can_copy_link);
        });
    });
}

#[test]
fn test_server_token_assignment_updates_copy_link_resolution() {
    App::test((), |mut app| async move {
        let _interactive_management_guard =
            FeatureFlag::InteractiveConversationManagementView.override_enabled(true);
        add_entry_projection_test_models(&mut app);

        let conversation_id = AIConversationId::new();
        let terminal_view_id = EntityId::new();
        let conversation = create_restored_conversation(
            conversation_id,
            "root-task",
            AgentConversationData {
                server_conversation_token: None,
                conversation_usage_metadata: None,
                reverted_action_ids: None,
                forked_from_server_conversation_token: None,
                artifacts_json: None,
                parent_agent_id: None,
                agent_name: None,
                orchestration_harness_type: None,
                parent_conversation_id: None,
                is_remote_child: false,
                root_task_is_optimistic: None,
                run_id: None,
                autoexecute_override: None,
                last_event_sequence: None,
                pinned: false,
            },
        );

        BlocklistAIHistoryModel::handle(&app).update(&mut app, |model, ctx| {
            model.restore_conversations(terminal_view_id, vec![conversation], ctx);
        });

        let agent_model = app.add_singleton_model(|_| {
            let mut model = create_test_model();
            model.conversations.insert(
                conversation_id,
                create_test_conversation_metadata(conversation_id, "Conversation"),
            );
            model
        });
        let saw_conversation_updated = Arc::new(AtomicBool::new(false));

        app.update(|ctx| {
            let saw_conversation_updated = saw_conversation_updated.clone();
            ctx.subscribe_to_model(&agent_model, move |_, event, _| {
                if matches!(
                    event,
                    AgentConversationsModelEvent::ConversationUpdated { .. }
                ) {
                    saw_conversation_updated.store(true, Ordering::SeqCst);
                }
            });

            let link = AgentConversationsModel::resolve_copy_link(
                AgentConversationNavigationSubject::Entry(AgentConversationEntryId::Conversation(
                    conversation_id,
                )),
                ctx,
            );
            assert_eq!(link, None);
        });

        let token = "assigned-token-after-entry-build";
        BlocklistAIHistoryModel::handle(&app).update(&mut app, |model, _| {
            model
                .set_server_conversation_token_for_conversation(conversation_id, token.to_string());
        });
        agent_model.update(&mut app, |model, ctx| {
            model.handle_history_event(
                &BlocklistAIHistoryEvent::ConversationServerTokenAssigned {
                    conversation_id,
                    terminal_surface_id: terminal_view_id,
                },
                ctx,
            );
        });

        app.update(|ctx| {
            assert!(saw_conversation_updated.load(Ordering::SeqCst));

            let link = AgentConversationsModel::resolve_copy_link(
                AgentConversationNavigationSubject::Entry(AgentConversationEntryId::Conversation(
                    conversation_id,
                )),
                ctx,
            );
            assert_eq!(
                link,
                Some(ServerConversationToken::new(token.to_string()).conversation_link())
            );
        });
    });
}

#[test]
fn test_environment_none_filter_includes_conversations() {
    App::test((), |mut app| async move {
        add_entry_projection_test_models(&mut app);

        let mut model = create_test_model();

        let conversation_id = AIConversationId::new();
        model.conversations.insert(
            conversation_id,
            create_test_conversation_metadata(conversation_id, "Test conversation"),
        );

        let filters = AgentManagementFilters {
            owners: OwnerFilter::All,
            environment: EnvironmentFilter::NoEnvironment,
            ..Default::default()
        };

        app.update(|ctx| {
            let entries = model.get_entries(&filters, &TeamlessScopeForTest, ctx);

            assert!(
                entries.iter().any(
                    |entry| entry.id == AgentConversationEntryId::Conversation(conversation_id)
                )
            );
        });
    })
}

#[test]
fn test_file_artifact_filter_matches_only_items_with_file_artifacts() {
    let artifacts_with_file = vec![Artifact::File {
        artifact_uid: "artifact-file-1".to_string(),
        filepath: "outputs/report.txt".to_string(),
        filename: "report.txt".to_string(),
        mime_type: "text/plain".to_string(),
        description: Some("Daily summary".to_string()),
        size_bytes: Some(42),
    }];
    let artifacts_with_pr = vec![Artifact::PullRequest {
        url: "https://github.com/org/repo/pull/1".to_string(),
        branch: "main".to_string(),
        repo: Some("repo".to_string()),
        number: Some(1),
    }];

    assert!(super::artifacts_match_filter(
        &artifacts_with_file,
        &ArtifactFilter::File,
    ));
    assert!(!super::artifacts_match_filter(
        &artifacts_with_pr,
        &ArtifactFilter::File,
    ));
    assert!(super::artifacts_match_filter(
        &artifacts_with_file,
        &ArtifactFilter::All,
    ));
}

#[test]
fn test_harness_filter_matches_only_selected_harness() {
    App::test((), |mut app| async move {
        add_entry_projection_test_models(&mut app);

        let mut model = create_test_model();

        let conv_id = AIConversationId::new();
        model.conversations.insert(
            conv_id,
            create_test_conversation_metadata(conv_id, "Local conv"),
        );

        app.update(|ctx| {
            let items_for = |filter: HarnessFilter| -> Vec<AgentConversationEntryId> {
                model
                    .get_entries(
                        &AgentManagementFilters {
                            owners: OwnerFilter::All,
                            harness: filter,
                            ..Default::default()
                        },
                        &TeamlessScopeForTest,
                        ctx,
                    )
                    .into_iter()
                    .map(|entry| entry.id)
                    .collect()
            };

            assert_eq!(items_for(HarnessFilter::All).len(), 1);
            assert!(items_for(HarnessFilter::Specific(Harness::Claude)).is_empty());
            assert_eq!(
                items_for(HarnessFilter::Specific(Harness::Oz)),
                vec![AgentConversationEntryId::Conversation(conv_id)]
            );
        });
    });
}

#[test]
fn test_harness_filter_is_filtering_and_reset() {
    // Default is All → not filtering, and after toggling reset_all_but_owner returns to default.
    let mut filters = AgentManagementFilters::default();
    assert!(!filters.is_filtering());

    filters.harness = HarnessFilter::Specific(Harness::Claude);
    assert!(
        filters.is_filtering(),
        "harness != All should report filtering"
    );

    filters.reset_all_but_owner();
    assert_eq!(filters.harness, HarnessFilter::default());
    assert!(!filters.is_filtering());
}

#[test]
fn test_get_or_async_fetch_task_data_returns_cached_task_without_fetching() {
    // If the task is already in `tasks`, return it directly and don't touch the fetch-state
    // map — even if a stale `PermanentlyFailedAt` entry exists (which shouldn't normally happen,
    // but proves the success path takes precedence).
    App::test((), |mut app| async move {
        let now = Utc::now();
        let task = create_test_task(&make_uuid(7000), "user-a", now);
        let task_id = task.task_id;

        let model_handle = app.add_singleton_model(|_| {
            let mut model = create_test_model();
            model.tasks.insert(task_id, task.clone());
            // Sentinel: even if a permanent-failure entry is present, the cached task wins.
            model.task_fetch_state.insert(
                task_id,
                TaskFetchState::PermanentlyFailed { at: Instant::now() },
            );
            model
        });

        let result = model_handle.update(&mut app, |model, ctx| {
            model.get_or_async_fetch_task_data(&task_id, ctx)
        });

        assert!(result.is_some(), "cached task should be returned");
        model_handle.update(&mut app, |model, _| {
            // The cached-hit fast path doesn't touch `task_fetch_state`, so the sentinel
            // entry is left as-is and (importantly) no `InFlight` entry was added.
            assert!(matches!(
                model.task_fetch_state.get(&task_id),
                Some(TaskFetchState::PermanentlyFailed { .. })
            ));
        });
    });
}

#[test]
fn test_get_or_async_fetch_task_data_skips_when_permanently_failed() {
    // A task id marked as `PermanentlyFailed` within its cooldown (e.g. very recent 403) must
    // not spawn a new fetch.
    App::test((), |mut app| async move {
        let task_id: AmbientAgentTaskId = make_uuid(7001).parse().unwrap();

        let model_handle = app.add_singleton_model(|_| {
            let mut model = create_test_model();
            model.task_fetch_state.insert(
                task_id,
                TaskFetchState::PermanentlyFailed { at: Instant::now() },
            );
            model
        });

        let result = model_handle.update(&mut app, |model, ctx| {
            model.get_or_async_fetch_task_data(&task_id, ctx)
        });

        assert!(result.is_none());
        model_handle.update(&mut app, |model, _| {
            // The state is unchanged -- still permanently failed, no in-flight upgrade.
            assert!(matches!(
                model.task_fetch_state.get(&task_id),
                Some(TaskFetchState::PermanentlyFailed { .. })
            ));
        });
    });
}

#[test]
fn test_get_or_async_fetch_task_data_skips_when_in_flight() {
    // A task id already marked as `InFlight` must not spawn a duplicate fetch.
    App::test((), |mut app| async move {
        let task_id: AmbientAgentTaskId = make_uuid(7002).parse().unwrap();

        let model_handle = app.add_singleton_model(|_| {
            let mut model = create_test_model();
            model
                .task_fetch_state
                .insert(task_id, TaskFetchState::InFlight);
            model
        });

        let result = model_handle.update(&mut app, |model, ctx| {
            model.get_or_async_fetch_task_data(&task_id, ctx)
        });

        assert!(result.is_none());
        model_handle.update(&mut app, |model, _| {
            // Still exactly the one in-flight entry we pre-seeded.
            assert_eq!(model.task_fetch_state.len(), 1);
            assert!(matches!(
                model.task_fetch_state.get(&task_id),
                Some(TaskFetchState::InFlight)
            ));
        });
    });
}

#[test]
fn test_get_or_async_fetch_task_data_skips_within_transient_cooldown() {
    // A recent transient failure (timestamp younger than the cooldown) must short-circuit.
    App::test((), |mut app| async move {
        let task_id: AmbientAgentTaskId = make_uuid(7003).parse().unwrap();

        let model_handle = app.add_singleton_model(|_| {
            let mut model = create_test_model();
            model.task_fetch_state.insert(
                task_id,
                TaskFetchState::TransientlyFailed { at: Instant::now() },
            );
            model
        });

        let result = model_handle.update(&mut app, |model, ctx| {
            model.get_or_async_fetch_task_data(&task_id, ctx)
        });

        assert!(result.is_none());
        model_handle.update(&mut app, |model, _| {
            // The transient entry is preserved (no upgrade to in-flight).
            assert!(matches!(
                model.task_fetch_state.get(&task_id),
                Some(TaskFetchState::TransientlyFailed { .. })
            ));
        });
    });
}

#[test]
fn test_agent_management_filters_serde_backwards_compat() {
    // Persisted state from older clients has no `harness` key → deserializes to All.
    let legacy = r#"{
        "owners": "PersonalOnly",
        "status": "All",
        "source": "All",
        "created_on": "All",
        "creator": "All",
        "artifact": "All"
    }"#;
    let decoded: AgentManagementFilters =
        serde_json::from_str(legacy).expect("legacy payload without harness must deserialize");
    assert_eq!(decoded.harness, HarnessFilter::All);

    // Round trip a Specific(Claude) value.
    let original = AgentManagementFilters {
        harness: HarnessFilter::Specific(Harness::Claude),
        ..Default::default()
    };
    let encoded = serde_json::to_string(&original).unwrap();
    assert!(
        encoded.contains("\"harness\":\"claude\""),
        "expected serialized form to contain \"harness\":\"claude\", got {encoded}"
    );
    let decoded: AgentManagementFilters = serde_json::from_str(&encoded).unwrap();
    assert_eq!(decoded, original);

    // Unknown harness strings deserialize to All (forward compat).
    let forward = r#"{
        "owners": "PersonalOnly",
        "status": "All",
        "source": "All",
        "created_on": "All",
        "creator": "All",
        "artifact": "All",
        "harness": "some-future-harness"
    }"#;
    let decoded: AgentManagementFilters = serde_json::from_str(forward).unwrap();
    assert_eq!(decoded.harness, HarnessFilter::All);
}
