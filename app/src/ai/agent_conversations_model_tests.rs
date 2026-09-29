use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use chrono::{Duration, Utc};
use persistence::model::{AgentConversationData, ConversationUsageMetadata};
use warp_core::features::FeatureFlag;
use warpui::{App, EntityId, SingletonEntity};

use super::entry::{AgentConversationEntryId, AgentConversationNavigationSubject};
use super::query::{DEFAULT_RESULT_COUNT, MAX_SEARCH_RESULTS};
use super::{
    AgentConversationsModel, AgentConversationsModelEvent, ConversationMetadata,
    query_conversation_entries,
};
use crate::ai::active_agent_views_model::ActiveAgentViewsModel;
use crate::ai::agent::api::ServerConversationToken;
use crate::ai::agent::conversation::{
    AIAgentHarness, AIConversation, AIConversationId, ConversationStatus,
    ServerAIConversationMetadata,
};
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

/// Subscribes a counter to `model` and returns it so individual cases can assert how many
/// `ConversationUpdated` events were emitted.
fn count_conversation_updated_events(
    app: &mut App,
    model: &warpui::ModelHandle<AgentConversationsModel>,
) -> Arc<AtomicUsize> {
    let count = Arc::new(AtomicUsize::new(0));
    let count_clone = count.clone();
    app.update(|ctx| {
        ctx.subscribe_to_model(model, move |_, event, _| {
            let AgentConversationsModelEvent::ConversationUpdated = event;
            count_clone.fetch_add(1, Ordering::SeqCst);
        });
    });
    count
}

#[test]
fn test_status_updates_emit_conversation_updated() {
    App::test((), |mut app| async move {
        let _interactive_management_guard =
            FeatureFlag::InteractiveConversationManagementView.override_enabled(true);
        let agent_model = app.add_singleton_model(|_| create_test_model());
        let count = count_conversation_updated_events(&mut app, &agent_model);

        for update in [
            ConversationStatusUpdate::Restored,
            ConversationStatusUpdate::Changed {
                prev_status: ConversationStatus::InProgress,
            },
        ] {
            agent_model.update(&mut app, |model, ctx| {
                model.handle_history_event(
                    &BlocklistAIHistoryEvent::UpdatedConversationStatus {
                        conversation_id: AIConversationId::new(),
                        terminal_surface_id: EntityId::new(),
                        update,
                        new_status: ConversationStatus::Success,
                    },
                    ctx,
                );
            });
        }

        assert_eq!(count.load(Ordering::SeqCst), 2);
    });
}

fn create_test_model() -> AgentConversationsModel {
    AgentConversationsModel {
        conversations: HashMap::new(),
    }
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
            let entries = model.get_entries(&TeamlessScopeForTest, ctx);
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
            let entries = model.get_entries(&TeamlessScopeForTest, ctx);
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
            let entries = model.get_entries(&TeamlessScopeForTest, ctx);
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
        ambient_agent_task_id: None,
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
            let entries = model.get_entries(&TeamlessScopeForTest, ctx);

            assert_eq!(entries.len(), 1);
            let entry = &entries[0];
            assert_eq!(
                entry.id,
                AgentConversationEntryId::Conversation(conversation_id)
            );
            assert_eq!(entry.identity.local_conversation_id, Some(conversation_id));
            assert!(!entry.backing.has_cloud_data);
            assert_eq!(entry.display.title, "Local conversation");
        });
    });
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
            )]);
        });

        let model = create_test_model();

        app.update(|ctx| {
            let entries = model.get_entries(&TeamlessScopeForTest, ctx);

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
            )]);
        });
        app.add_singleton_model(|_| create_test_model());

        app.update(|ctx| {
            let entries =
                AgentConversationsModel::as_ref(ctx).get_entries(&TeamlessScopeForTest, ctx);
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
fn test_server_token_assignment_updates_entry_token() {
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
                root_task_is_optimistic: None,
                run_id: None,
                autoexecute_override: None,
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
        let count = count_conversation_updated_events(&mut app, &agent_model);

        let entry_id = AgentConversationEntryId::Conversation(conversation_id);
        app.update(|ctx| {
            let entry = AgentConversationsModel::as_ref(ctx)
                .get_entry_by_id(&entry_id, ctx)
                .expect("conversation entry should exist");
            assert_eq!(entry.identity.server_conversation_token, None);
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
            assert_eq!(count.load(Ordering::SeqCst), 1);

            let entry = AgentConversationsModel::as_ref(ctx)
                .get_entry_by_id(&entry_id, ctx)
                .expect("conversation entry should exist");
            assert_eq!(
                entry.identity.server_conversation_token,
                Some(ServerConversationToken::new(token.to_string()))
            );
        });
    });
}
