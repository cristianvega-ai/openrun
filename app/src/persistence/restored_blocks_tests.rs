//! Tests that sessions saved while agents existed restore their terminal blocks and drop only the
//! blocks that belong to an agent conversation.

use diesel::connection::SimpleConnection as _;
use diesel::sql_query;
use diesel::sql_types::{Binary, Nullable, Text};
use diesel::sqlite::SqliteConnection;
use diesel::{Connection, RunQueryDsl};
use diesel_migrations::MigrationHarness;

use super::get_all_restored_blocks;
use crate::app_state::PaneUuid;

const PANE_UUID: [u8; 4] = [1, 2, 3, 4];
const CONVERSATION_ID: &str = "0b3c1c1a-5d0a-4f43-9d0e-3c8f8a4f1a11";
const ACTION_ID: &str = "6a1d3f52-2f3c-4a53-8c7e-0d3b7b1b9f22";

fn test_connection() -> SqliteConnection {
    let mut conn =
        SqliteConnection::establish(":memory:").expect("in-memory sqlite connection should open");
    conn.run_pending_migrations(::persistence::MIGRATIONS)
        .expect("migrations should run");
    // The pane tree above `terminal_panes` is irrelevant to which stored blocks are restored.
    conn.batch_execute("PRAGMA foreign_keys = OFF;")
        .expect("foreign keys should switch off");
    sql_query("INSERT INTO terminal_panes (kind, uuid, is_active) VALUES ('terminal', ?, 1)")
        .bind::<Binary, _>(PANE_UUID.to_vec())
        .execute(&mut conn)
        .expect("terminal pane should insert");
    conn
}

/// Inserts a finished block the way earlier releases stored it.
fn insert_block(
    conn: &mut SqliteConnection,
    block_id: &str,
    start_ts: &str,
    ai_metadata: Option<&str>,
    agent_view_visibility: Option<&str>,
) {
    sql_query(
        "INSERT INTO blocks (pane_leaf_uuid, stylized_command, stylized_output, exit_code, \
         did_execute, completed_ts, start_ts, honor_ps1, is_background, block_id, ai_metadata, \
         agent_view_visibility) VALUES (?, ?, ?, 0, 1, ?, ?, 0, 0, ?, ?, ?)",
    )
    .bind::<Binary, _>(PANE_UUID.to_vec())
    .bind::<Binary, _>(format!("cmd {block_id}").into_bytes())
    .bind::<Binary, _>(b"output".to_vec())
    .bind::<Text, _>(start_ts.to_owned())
    .bind::<Text, _>(start_ts.to_owned())
    .bind::<Text, _>(block_id.to_owned())
    .bind::<Nullable<Text>, _>(ai_metadata.map(str::to_owned))
    .bind::<Nullable<Text>, _>(agent_view_visibility.map(str::to_owned))
    .execute(conn)
    .expect("block should insert");
}

fn restored_block_ids(conn: &mut SqliteConnection) -> Vec<String> {
    let blocks = get_all_restored_blocks(conn).expect("blocks should load");
    blocks
        .get(&PaneUuid(PANE_UUID.to_vec()))
        .expect("pane should have restored blocks")
        .iter()
        .map(|block| block.id.as_str().to_owned())
        .collect()
}

#[test]
fn restoring_a_session_with_agent_blocks_keeps_only_terminal_blocks() {
    let mut conn = test_connection();

    let agent_requested_command = format!(
        r#"{{"requested_command_action_id":"{ACTION_ID}","conversation_id":"{CONVERSATION_ID}","subagent_task_id":null,"long_running_control_state":{{"Agent":{{"is_blocked":false,"should_hide_responses":false}}}},"has_agent_written_to_block":true}}"#
    );
    let created_in_agent_view = format!(
        r#"{{"Agent":{{"origin_conversation_id":"{CONVERSATION_ID}","pending_other_conversation_ids":[],"other_conversation_ids":[]}}}}"#
    );
    let attached_as_context = format!(
        r#"{{"Terminal":{{"pending_conversation_ids":[],"conversation_ids":["{CONVERSATION_ID}"]}}}}"#
    );

    insert_block(&mut conn, "plain", "2026-01-01 10:00:00", None, None);
    insert_block(
        &mut conn,
        "agent-requested",
        "2026-01-01 10:01:00",
        Some(&agent_requested_command),
        Some(&attached_as_context),
    );
    insert_block(
        &mut conn,
        "agent-view",
        "2026-01-01 10:02:00",
        None,
        Some(&created_in_agent_view),
    );
    insert_block(
        &mut conn,
        "attached",
        "2026-01-01 10:03:00",
        None,
        Some(&attached_as_context),
    );
    insert_block(
        &mut conn,
        "null-metadata",
        "2026-01-01 10:04:00",
        Some("null"),
        None,
    );
    insert_block(&mut conn, "last", "2026-01-01 10:05:00", None, None);

    assert_eq!(
        restored_block_ids(&mut conn),
        vec!["plain", "attached", "null-metadata", "last"]
    );
}
