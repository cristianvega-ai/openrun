use uuid::Uuid;
use warpui::App;

use super::*;
use crate::test_util::terminal::{add_window_with_terminal, initialize_app_for_terminal_view};

#[test]
fn unmapped_token_never_bootstraps_a_new_conversation_when_not_bound() {
    // Regression test: an explicit server token that doesn't resolve to any locally known
    // conversation must never be treated the same as an explicit no-token request. Only the
    // latter is allowed to bootstrap a new conversation; the former names a conversation this
    // client just doesn't know about yet (or at all), so it must be dropped instead of silently
    // duplicated into a brand new conversation.
    App::test((), |mut app| async move {
        initialize_app_for_terminal_view(&mut app);
        let terminal = add_window_with_terminal(&mut app, None);
        let unmapped_token_str = "550e8400-e29b-41d4-a716-446655440c00";
        let unmapped_token =
            ServerConversationToken::from_uuid(Uuid::parse_str(unmapped_token_str).unwrap());

        let conversation_count_before = terminal.read(&app, |terminal, ctx| {
            BlocklistAIHistoryModel::as_ref(ctx)
                .all_live_conversations_for_terminal_surface(terminal.id())
                .count()
        });

        terminal.update(&mut app, |terminal, ctx| {
            terminal.ai_controller().update(ctx, |controller, ctx| {
                assert_eq!(controller.native_prompt_conversation_id, None);
                controller.execute_warp_agent_prompt_from_shared_session_injection(
                    "prompt".into(),
                    Some(unmapped_token),
                    vec![],
                    ParticipantId::new(),
                    None,
                    ctx,
                );
            });
        });

        terminal.read(&app, |terminal, ctx| {
            let conversation_count_after = BlocklistAIHistoryModel::as_ref(ctx)
                .all_live_conversations_for_terminal_surface(terminal.id())
                .count();
            assert_eq!(
                conversation_count_after, conversation_count_before,
                "an unmapped token must never bootstrap a new conversation"
            );
        });
    });
}
