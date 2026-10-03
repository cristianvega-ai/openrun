//! Tests for `2026-09-29-000000_drop_dead_tables`, which drops the unused tables, the pane kinds
//! and columns that went with them, and the pane tree entries of removed pane kinds.

use diesel::connection::SimpleConnection as _;
use diesel::sql_types::{BigInt, Text};
use diesel::sqlite::SqliteConnection;
use diesel::{Connection as _, QueryableByName, RunQueryDsl as _, sql_query};
use diesel_migrations::MigrationHarness as _;

use crate::MIGRATIONS;

/// A database at the schema right before the migration, holding rows in every table and column
/// it drops (see the comments in the file for the pane layout).
const SEED: &str = include_str!("../test_data/pre_drop_dead_tables_seed.sql");

const DROP_DEAD_TABLES_VERSION: &str = "20260929000000";

const DROPPED_TABLES: &[&str] = &[
    "active_mcp_servers",
    "agent_conversations",
    "agent_tasks",
    "ai_document_panes",
    "ai_memory_panes",
    "ai_queries",
    "ambient_agent_panes",
    "cloud_objects_refreshes",
    "current_user_information",
    "env_var_collection_panes",
    "folders",
    "generic_string_objects",
    "mcp_environment_variables",
    "mcp_server_installations",
    "mcp_server_panes",
    "notebooks",
    "object_actions",
    "object_metadata",
    "object_permissions",
    "project_rules",
    "server_experiments",
    "team_members",
    "team_settings",
    "teams",
    "user_profiles",
    "users",
    "workflow_panes",
    "workflows",
    "workspace_teams",
    "workspaces",
];

const KEPT_TABLES: &[&str] = &[
    "app",
    "blocks",
    "code_pane_tabs",
    "code_panes",
    "code_review_panes",
    "commands",
    "ignored_suggestions",
    "notebook_panes",
    "pane_branches",
    "pane_leaves",
    "pane_nodes",
    "panels",
    "projects",
    "settings_panes",
    "tab_groups",
    "tabs",
    "terminal_panes",
    "windows",
    "workspace_language_server",
    "workspace_metadata",
];

const DROPPED_COLUMNS: &[(&str, &str)] = &[
    ("blocks", "ai_metadata"),
    ("blocks", "agent_view_visibility"),
    ("commands", "cloud_workflow_id"),
    ("notebook_panes", "notebook_id"),
    ("terminal_panes", "llm_model_override"),
    ("terminal_panes", "active_profile_id"),
    ("terminal_panes", "conversation_ids"),
    ("terminal_panes", "active_conversation_id"),
    ("windows", "warp_ai_width"),
    ("windows", "warp_drive_index_width"),
    ("windows", "agent_management_filters"),
    ("windows", "team_uid"),
];

#[derive(QueryableByName)]
struct Text1 {
    #[diesel(sql_type = Text)]
    value: String,
}

#[derive(QueryableByName)]
struct Int1 {
    #[diesel(sql_type = BigInt)]
    value: i64,
}

fn strings(conn: &mut SqliteConnection, query: &str) -> Vec<String> {
    sql_query(query)
        .load::<Text1>(conn)
        .expect("query should run")
        .into_iter()
        .map(|row| row.value)
        .collect()
}

fn ints(conn: &mut SqliteConnection, query: &str) -> Vec<i64> {
    sql_query(query)
        .load::<Int1>(conn)
        .expect("query should run")
        .into_iter()
        .map(|row| row.value)
        .collect()
}

fn count(conn: &mut SqliteConnection, query: &str) -> i64 {
    ints(conn, query)[0]
}

fn tables(conn: &mut SqliteConnection) -> Vec<String> {
    strings(
        conn,
        "SELECT name AS value FROM sqlite_master WHERE type = 'table' ORDER BY name",
    )
}

fn columns(conn: &mut SqliteConnection, table: &str) -> Vec<String> {
    strings(
        conn,
        &format!("SELECT name AS value FROM pragma_table_info('{table}')"),
    )
}

/// Runs every migration before the one under test, then seeds every table.
///
/// Foreign keys are enforced, as they are when the app runs its migrations.
fn seeded_connection_before_migration() -> SqliteConnection {
    let mut conn = SqliteConnection::establish(":memory:").expect("database should open");
    conn.batch_execute("PRAGMA foreign_keys = ON;")
        .expect("foreign keys should switch on");

    let pending = conn
        .pending_migrations(MIGRATIONS)
        .expect("pending migrations should list");
    let mut ran_earlier_migrations = 0;
    for migration in &pending {
        if migration.name().version().to_string().as_str() >= DROP_DEAD_TABLES_VERSION {
            break;
        }
        conn.run_migration(migration.as_ref())
            .expect("earlier migration should run");
        ran_earlier_migrations += 1;
    }
    assert!(
        ran_earlier_migrations > 100,
        "earlier migrations should have run"
    );
    assert_eq!(
        count(
            &mut conn,
            &format!(
                "SELECT COUNT(*) AS value FROM __diesel_schema_migrations \
                 WHERE version >= '{DROP_DEAD_TABLES_VERSION}'"
            )
        ),
        0
    );

    for dropped in DROPPED_TABLES {
        assert!(
            tables(&mut conn).iter().any(|table| table == dropped),
            "{dropped} should exist before the migration"
        );
    }
    conn.batch_execute(SEED).expect("seed should insert");
    conn
}

fn migrated_seeded_connection() -> SqliteConnection {
    let mut conn = seeded_connection_before_migration();
    conn.run_pending_migrations(MIGRATIONS)
        .expect("the migration should run with foreign keys enforced");
    conn
}

#[test]
fn migration_drops_the_dead_tables_and_columns() {
    let mut conn = migrated_seeded_connection();

    let remaining = tables(&mut conn);
    for dropped in DROPPED_TABLES {
        assert!(
            !remaining.iter().any(|t| t == dropped),
            "{dropped} is dropped"
        );
    }
    for kept in KEPT_TABLES {
        assert!(remaining.iter().any(|t| t == kept), "{kept} is kept");
    }
    for (table, column) in DROPPED_COLUMNS {
        assert!(
            !columns(&mut conn, table).iter().any(|c| c == column),
            "{table}.{column} is dropped"
        );
    }
    assert_eq!(
        strings(
            &mut conn,
            "SELECT name AS value FROM sqlite_master \
             WHERE type IN ('index', 'trigger') AND tbl_name NOT IN (SELECT name FROM sqlite_master WHERE type = 'table')"
        ),
        Vec::<String>::new(),
        "indexes and triggers of dropped tables go with them"
    );
    assert_eq!(
        count(
            &mut conn,
            "SELECT COUNT(*) AS value FROM pragma_foreign_key_check"
        ),
        0,
        "no foreign key is left dangling"
    );
}

#[test]
fn migration_removes_panes_of_removed_kinds_and_keeps_the_tree_consistent() {
    let mut conn = migrated_seeded_connection();

    assert_eq!(
        strings(
            &mut conn,
            "SELECT pane_node_id || ':' || kind AS value FROM pane_leaves ORDER BY pane_node_id"
        ),
        vec![
            "2:terminal",
            "13:code",
            "14:terminal",
            "15:notebook",
            "16:settings",
            "17:code_review",
        ],
        "only the pane kinds that can still be restored are left, and the cloud notebook is gone"
    );
    assert_eq!(
        ints(&mut conn, "SELECT id AS value FROM pane_nodes ORDER BY id"),
        vec![1, 2, 8, 13, 14, 15, 16, 17],
        "the nodes of removed panes and of splits left without panes are deleted"
    );
    assert_eq!(
        ints(
            &mut conn,
            "SELECT pane_node_id AS value FROM pane_branches ORDER BY pane_node_id"
        ),
        vec![1, 8]
    );
    assert_eq!(
        count(
            &mut conn,
            "SELECT COUNT(*) AS value FROM pane_nodes \
             WHERE is_leaf = 1 AND id NOT IN (SELECT pane_node_id FROM pane_leaves)"
        ),
        0,
        "every leaf node has a pane"
    );
    assert_eq!(
        count(
            &mut conn,
            "SELECT COUNT(*) AS value FROM pane_nodes branch WHERE is_leaf = 0 \
             AND NOT EXISTS (SELECT 1 FROM pane_nodes child WHERE child.parent_pane_node_id = branch.id)"
        ),
        0,
        "every split has at least one child"
    );
    assert_eq!(
        count(
            &mut conn,
            "SELECT COUNT(*) AS value FROM pane_nodes WHERE is_leaf = 0 \
             AND id NOT IN (SELECT pane_node_id FROM pane_branches)"
        ),
        0,
        "every split node has its branch row"
    );

    assert_eq!(
        ints(&mut conn, "SELECT id AS value FROM notebook_panes"),
        vec![15],
        "the local markdown notebook pane is kept and the cloud one is not"
    );
    assert_eq!(
        count(
            &mut conn,
            "SELECT length(local_path) AS value FROM notebook_panes WHERE id = 15"
        ),
        14
    );
    assert_eq!(
        strings(
            &mut conn,
            "SELECT cwd AS value FROM terminal_panes ORDER BY id"
        ),
        vec!["/work/one", "/work/two"]
    );
    assert_eq!(
        count(&mut conn, "SELECT COUNT(*) AS value FROM code_pane_tabs"),
        1
    );
    assert_eq!(
        strings(
            &mut conn,
            "SELECT current_page AS value FROM settings_panes"
        ),
        vec!["Privacy"]
    );
    assert_eq!(
        strings(
            &mut conn,
            "SELECT repo_path AS value FROM code_review_panes"
        ),
        vec!["/work/two"]
    );
}

#[test]
fn migration_deletes_tabs_without_panes_and_keeps_the_active_tab() {
    let mut conn = migrated_seeded_connection();

    assert_eq!(
        ints(&mut conn, "SELECT id AS value FROM tabs ORDER BY id"),
        vec![1, 4],
        "the get started, agent and profile tabs are deleted"
    );
    assert_eq!(
        ints(&mut conn, "SELECT tab_id AS value FROM panels ORDER BY id"),
        vec![4]
    );
    assert_eq!(
        ints(
            &mut conn,
            "SELECT active_tab_index AS value FROM windows ORDER BY id"
        ),
        vec![1, 0],
        "the active tab is still the fourth tab, now the second one"
    );
    assert_eq!(
        ints(&mut conn, "SELECT COUNT(*) AS value FROM windows"),
        vec![2],
        "windows are kept even when they lose all their tabs"
    );
    assert_eq!(
        ints(
            &mut conn,
            "SELECT tab_group_id AS value FROM tabs WHERE id = 1"
        ),
        vec![1]
    );
}

#[test]
fn migration_drops_only_agent_blocks_and_keeps_the_rest_of_the_session() {
    let mut conn = migrated_seeded_connection();

    assert_eq!(
        strings(
            &mut conn,
            "SELECT block_id AS value FROM blocks ORDER BY id"
        ),
        vec![
            "plain",
            "attached",
            "null-metadata",
            "garbled-metadata",
            "second-terminal"
        ],
        "blocks created in or requested by an agent are deleted; blocks that only had a \
         conversation attached, a null value or a value that is not JSON stay"
    );
    assert_eq!(
        strings(
            &mut conn,
            "SELECT command AS value FROM commands ORDER BY id"
        ),
        vec!["echo one", "echo {{word}}"]
    );
    assert_eq!(
        strings(
            &mut conn,
            "SELECT workflow_command AS value FROM commands WHERE workflow_command IS NOT NULL"
        ),
        vec!["echo {{word}}"]
    );
    assert_eq!(
        ints(
            &mut conn,
            "SELECT CAST(voltron_width AS INTEGER) AS value FROM windows WHERE id = 1"
        ),
        vec![500]
    );
    assert_eq!(
        ints(
            &mut conn,
            "SELECT CAST(universal_search_width AS INTEGER) AS value FROM windows WHERE id = 1"
        ),
        vec![300]
    );
    for (table, expected) in [
        ("projects", 1),
        ("ignored_suggestions", 1),
        ("workspace_metadata", 1),
        ("workspace_language_server", 1),
        ("tab_groups", 1),
        ("app", 1),
    ] {
        assert_eq!(
            count(&mut conn, &format!("SELECT COUNT(*) AS value FROM {table}")),
            expected,
            "{table} keeps its rows"
        );
    }
}

#[test]
fn migration_runs_on_an_empty_database_and_can_be_reverted_and_rerun() {
    let mut conn = SqliteConnection::establish(":memory:").expect("database should open");
    conn.batch_execute("PRAGMA foreign_keys = ON;")
        .expect("foreign keys should switch on");
    conn.run_pending_migrations(MIGRATIONS)
        .expect("all migrations should run on a new database");
    for dropped in DROPPED_TABLES {
        assert!(!tables(&mut conn).iter().any(|t| t == dropped));
    }

    while tables(&mut conn)
        .iter()
        .any(|table| table == "history_scrub_pending")
    {
        conn.revert_last_migration(MIGRATIONS)
            .expect("later migration should revert");
    }
    conn.revert_last_migration(MIGRATIONS)
        .expect("the migration should revert");
    for dropped in DROPPED_TABLES {
        assert!(
            tables(&mut conn).iter().any(|t| t == dropped),
            "{dropped} is recreated"
        );
    }
    for (table, column) in DROPPED_COLUMNS {
        assert!(
            columns(&mut conn, table).iter().any(|c| c == column),
            "{table}.{column} is recreated"
        );
    }

    conn.run_pending_migrations(MIGRATIONS)
        .expect("the migration should run again");
    for dropped in DROPPED_TABLES {
        assert!(!tables(&mut conn).iter().any(|t| t == dropped));
    }
}

#[test]
fn reverted_migration_runs_again_over_a_seeded_database() {
    let mut conn = migrated_seeded_connection();
    while tables(&mut conn)
        .iter()
        .any(|table| table == "history_scrub_pending")
    {
        conn.revert_last_migration(MIGRATIONS)
            .expect("later migration should revert");
    }
    conn.revert_last_migration(MIGRATIONS)
        .expect("the migration should revert");
    conn.run_pending_migrations(MIGRATIONS)
        .expect("the migration should run again");
    assert_eq!(
        ints(&mut conn, "SELECT id AS value FROM tabs ORDER BY id"),
        vec![1, 4]
    );
}
