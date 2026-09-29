-- Removes everything the offline terminal no longer reads or writes: the AI, MCP and agent
-- tables, the Warp Drive, team, account and experiment tables, the pane kinds that went with them
-- and the columns that only those features used.
--
-- Foreign keys are enforced while migrations run, so every table is dropped after the tables
-- that reference it.

-- Pane kinds that no longer exist. These per-kind tables reference pane_leaves (or pane_nodes),
-- so they go before the rows they point at.
DROP TABLE IF EXISTS ai_document_panes;
DROP TABLE IF EXISTS ai_memory_panes;
DROP TABLE IF EXISTS ambient_agent_panes;
DROP TABLE IF EXISTS env_var_collection_panes;
DROP TABLE IF EXISTS mcp_server_panes;
DROP TABLE IF EXISTS workflow_panes;

-- Notebook panes that were backed by a cloud notebook have no local path.
DELETE FROM notebook_panes WHERE local_path IS NULL;

-- Keep only the pane kinds the app can still restore (terminal, local markdown notebook, code,
-- settings, code review). This also removes the kinds that never had a table of their own
-- (get_started, execution_profile_editor).
DELETE FROM pane_leaves
    WHERE kind NOT IN ('terminal', 'notebook', 'code', 'settings', 'code_review')
    OR (kind = 'notebook' AND pane_node_id NOT IN (SELECT id FROM notebook_panes));

-- Delete the leaf pane_nodes that no longer have a pane_leaves row.
DELETE FROM pane_nodes
    WHERE is_leaf = 1
    AND id NOT IN (SELECT pane_node_id FROM pane_leaves);

-- Delete the splits that have no pane left anywhere below them. A split that keeps at least one
-- pane stays as it is; restoring a split with a single child yields that child.
WITH RECURSIVE live_nodes(id) AS (
    SELECT id FROM pane_nodes WHERE is_leaf = 1
    UNION
    SELECT pane_nodes.parent_pane_node_id
        FROM pane_nodes JOIN live_nodes ON pane_nodes.id = live_nodes.id
        WHERE pane_nodes.parent_pane_node_id IS NOT NULL
)
DELETE FROM pane_branches WHERE pane_node_id NOT IN (SELECT id FROM live_nodes);

WITH RECURSIVE live_nodes(id) AS (
    SELECT id FROM pane_nodes WHERE is_leaf = 1
    UNION
    SELECT pane_nodes.parent_pane_node_id
        FROM pane_nodes JOIN live_nodes ON pane_nodes.id = live_nodes.id
        WHERE pane_nodes.parent_pane_node_id IS NOT NULL
)
DELETE FROM pane_nodes WHERE id NOT IN (SELECT id FROM live_nodes);

-- Delete the tabs whose panes were all removed, and move each window's active tab index back by
-- the number of deleted tabs before it so it keeps pointing at the same tab.
UPDATE windows SET active_tab_index = MAX(0, active_tab_index - (
    SELECT COUNT(*) FROM tabs
        WHERE tabs.window_id = windows.id
        AND tabs.id NOT IN (SELECT tab_id FROM pane_nodes)
        AND (
            SELECT COUNT(*) FROM tabs earlier
                WHERE earlier.window_id = tabs.window_id AND earlier.id < tabs.id
        ) < windows.active_tab_index
));
DELETE FROM panels WHERE tab_id NOT IN (SELECT tab_id FROM pane_nodes);
DELETE FROM tabs WHERE id NOT IN (SELECT tab_id FROM pane_nodes);

-- Blocks that were created in, or attached to, an agent conversation are not restored.
DELETE FROM blocks WHERE
    CASE WHEN ai_metadata IS NOT NULL AND json_valid(ai_metadata)
        THEN json_type(ai_metadata) != 'null'
        ELSE 0
    END
    OR CASE WHEN agent_view_visibility IS NOT NULL AND json_valid(agent_view_visibility)
        THEN json_type(agent_view_visibility, '$.Agent') IS NOT NULL
        ELSE 0
    END;

-- Columns that only the removed features used.
ALTER TABLE blocks DROP COLUMN ai_metadata;
ALTER TABLE blocks DROP COLUMN agent_view_visibility;
ALTER TABLE commands DROP COLUMN cloud_workflow_id;
ALTER TABLE notebook_panes DROP COLUMN notebook_id;
ALTER TABLE terminal_panes DROP COLUMN llm_model_override;
ALTER TABLE terminal_panes DROP COLUMN active_profile_id;
ALTER TABLE terminal_panes DROP COLUMN conversation_ids;
ALTER TABLE terminal_panes DROP COLUMN active_conversation_id;
ALTER TABLE windows DROP COLUMN warp_ai_width;
ALTER TABLE windows DROP COLUMN warp_drive_index_width;
ALTER TABLE windows DROP COLUMN agent_management_filters;
ALTER TABLE windows DROP COLUMN team_uid;

-- AI, MCP and agent tables.
DROP TABLE IF EXISTS agent_tasks;
DROP TABLE IF EXISTS agent_conversations;
DROP TABLE IF EXISTS ai_queries;
DROP TABLE IF EXISTS active_mcp_servers;
DROP TABLE IF EXISTS mcp_environment_variables;
DROP TABLE IF EXISTS mcp_server_installations;
DROP TABLE IF EXISTS project_rules;

-- Warp Drive (cloud objects).
DROP TABLE IF EXISTS object_permissions;
DROP TABLE IF EXISTS object_metadata;
DROP TABLE IF EXISTS object_actions;
DROP TABLE IF EXISTS cloud_objects_refreshes;
DROP TABLE IF EXISTS generic_string_objects;
DROP TABLE IF EXISTS workflows;
DROP TABLE IF EXISTS notebooks;
DROP TABLE IF EXISTS folders;

-- Teams and workspaces.
DROP TABLE IF EXISTS workspace_teams;
DROP TABLE IF EXISTS team_members;
DROP TABLE IF EXISTS team_settings;
DROP TABLE IF EXISTS teams;
DROP TABLE IF EXISTS workspaces;

-- Accounts and server experiments.
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS user_profiles;
DROP TABLE IF EXISTS current_user_information;
DROP TABLE IF EXISTS server_experiments;
