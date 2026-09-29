-- A database at the schema before `2026-09-29-000000_drop_dead_tables`, with rows in every table
-- and column that migration drops, and rows in the tables it keeps.
--
-- Window 1 has four tabs, listed with the panes each holds:
--   tab 1  split: terminal (uuid 0101) + ai_document           -> the split stays with the terminal
--   tab 2  get_started                                          -> tab deleted
--   tab 3  split: ambient_agent + workflow                      -> tab deleted
--   tab 4  split: [split: env_var_collection + mcp_server], cloud notebook, code, terminal (0202),
--          local notebook, settings, code_review              -> everything but the first two stays
-- The active tab is tab 4 (index 3) and must be index 1 after tabs 2 and 3 are deleted.
-- Window 2 has one tab (tab 5) holding a split of ai_memory + execution_profile_editor, so it ends
-- up with no tab.

INSERT INTO windows (id, active_tab_index, window_width, window_height, origin_x, origin_y,
    quake_mode, universal_search_width, warp_ai_width, voltron_width, warp_drive_index_width,
    fullscreen_state, agent_management_filters, left_panel_open, vertical_tabs_panel_open, team_uid)
VALUES
    (1, 3, 1200.0, 800.0, 10.0, 20.0, 0, 300.0, 400.0, 500.0, 600.0, 0, '{"owner":"all"}', 1, 0, 'team-1'),
    (2, 0, 900.0, 700.0, 30.0, 40.0, 0, NULL, 410.0, NULL, 610.0, 0, NULL, NULL, NULL, 'team-2');
INSERT INTO app (id, active_window_id) VALUES (1, 1);
INSERT INTO tab_groups (id, window_id, name, color, collapsed, pinned) VALUES (1, 1, 'group', NULL, 0, 0);
INSERT INTO tabs (id, window_id, custom_title, color, tab_group_id, pinned) VALUES
    (1, 1, 'kept split', NULL, 1, 0),
    (2, 1, 'get started', NULL, NULL, 0),
    (3, 1, 'agents', NULL, NULL, 0),
    (4, 1, 'mixed', NULL, NULL, 1),
    (5, 2, 'only removed', NULL, NULL, 0);
INSERT INTO panels (id, tab_id, left_panel, right_panel) VALUES (1, 2, NULL, NULL), (2, 4, NULL, NULL);

INSERT INTO pane_nodes (id, tab_id, parent_pane_node_id, flex, is_leaf) VALUES (1, 1, NULL, NULL, 0);
INSERT INTO pane_nodes (id, tab_id, parent_pane_node_id, flex, is_leaf) VALUES
    (2, 1, 1, 0.5, 1),
    (3, 1, 1, 0.5, 1);
INSERT INTO pane_nodes (id, tab_id, parent_pane_node_id, flex, is_leaf) VALUES (4, 2, NULL, NULL, 1);
INSERT INTO pane_nodes (id, tab_id, parent_pane_node_id, flex, is_leaf) VALUES (5, 3, NULL, NULL, 0);
INSERT INTO pane_nodes (id, tab_id, parent_pane_node_id, flex, is_leaf) VALUES
    (6, 3, 5, 0.5, 1),
    (7, 3, 5, 0.5, 1);
INSERT INTO pane_nodes (id, tab_id, parent_pane_node_id, flex, is_leaf) VALUES (8, 4, NULL, NULL, 0);
INSERT INTO pane_nodes (id, tab_id, parent_pane_node_id, flex, is_leaf) VALUES (9, 4, 8, 0.2, 0);
INSERT INTO pane_nodes (id, tab_id, parent_pane_node_id, flex, is_leaf) VALUES
    (10, 4, 9, 0.5, 1),
    (11, 4, 9, 0.5, 1),
    (12, 4, 8, 0.1, 1),
    (13, 4, 8, 0.2, 1),
    (14, 4, 8, 0.2, 1),
    (15, 4, 8, 0.1, 1),
    (16, 4, 8, 0.1, 1),
    (17, 4, 8, 0.1, 1);
INSERT INTO pane_nodes (id, tab_id, parent_pane_node_id, flex, is_leaf) VALUES (18, 5, NULL, NULL, 0);
INSERT INTO pane_nodes (id, tab_id, parent_pane_node_id, flex, is_leaf) VALUES
    (19, 5, 18, 0.5, 1),
    (20, 5, 18, 0.5, 1);

INSERT INTO pane_branches (id, pane_node_id, horizontal) VALUES
    (1, 1, 1), (2, 5, 0), (3, 8, 1), (4, 9, 0), (5, 18, 1);

INSERT INTO pane_leaves (pane_node_id, kind, is_focused, custom_vertical_tabs_title) VALUES
    (2, 'terminal', 1, 'first terminal'),
    (3, 'ai_document', 0, NULL),
    (4, 'get_started', 1, NULL),
    (6, 'ambient_agent', 1, NULL),
    (7, 'workflow', 0, NULL),
    (10, 'env_var_collection', 0, NULL),
    (11, 'mcp_server', 0, NULL),
    (12, 'notebook', 0, NULL),
    (13, 'code', 0, NULL),
    (14, 'terminal', 1, NULL),
    (15, 'notebook', 0, NULL),
    (16, 'settings', 0, NULL),
    (17, 'code_review', 0, NULL),
    (19, 'ai_memory', 1, NULL),
    (20, 'execution_profile_editor', 0, NULL);

INSERT INTO terminal_panes (id, uuid, cwd, is_active, shell_launch_data, input_config,
    llm_model_override, active_profile_id, conversation_ids, active_conversation_id)
VALUES
    (2, x'0101', '/work/one', 1, NULL, NULL, 'some-model', 'profile-1', '["conversation-1"]', 'conversation-1'),
    (14, x'0202', '/work/two', 1, NULL, NULL, NULL, NULL, NULL, NULL);
INSERT INTO ai_document_panes (id, document_id, version, content, title) VALUES (3, 'doc-1', 1, 'plan', 'Plan');
INSERT INTO ambient_agent_panes (id, kind, uuid, task_id) VALUES (6, 'ambient_agent', x'0606', 'task-1');
INSERT INTO workflow_panes (id, workflow_id) VALUES (7, 'workflow-1');
INSERT INTO env_var_collection_panes (id, env_var_collection_id) VALUES (10, 'evc-1');
INSERT INTO mcp_server_panes (id) VALUES (11);
INSERT INTO notebook_panes (id, notebook_id, local_path) VALUES
    (12, 'cloud-notebook-1', NULL),
    (15, 'stale-notebook-id', x'2f776f726b2f6e6f7465732e6d64');
INSERT INTO code_panes (id, active_tab_index, source_data) VALUES (13, 0, NULL);
INSERT INTO code_pane_tabs (code_pane_id, tab_index, local_path) VALUES (13, 0, x'2f776f726b2f612e7273');
INSERT INTO settings_panes (id, current_page) VALUES (16, 'Privacy');
INSERT INTO code_review_panes (id, terminal_uuid, repo_path) VALUES (17, x'0202', '/work/two');
INSERT INTO ai_memory_panes (id) VALUES (19);

-- Blocks of terminal 0101: the two agent blocks, told apart by column, are the only ones dropped.
INSERT INTO blocks (pane_leaf_uuid, stylized_command, stylized_output, exit_code, did_execute,
    completed_ts, start_ts, honor_ps1, is_background, block_id, ai_metadata, agent_view_visibility)
VALUES
    (x'0101', x'636d64', x'6f7574', 0, 1, '2026-01-01 10:00:00', '2026-01-01 10:00:00', 0, 0, 'plain', NULL, NULL),
    (x'0101', x'636d64', x'6f7574', 0, 1, '2026-01-01 10:01:00', '2026-01-01 10:01:00', 0, 0, 'agent-requested',
        '{"requested_command_action_id":"6a1d3f52-2f3c-4a53-8c7e-0d3b7b1b9f22","conversation_id":"0b3c1c1a-5d0a-4f43-9d0e-3c8f8a4f1a11","subagent_task_id":null,"long_running_control_state":{"Agent":{"is_blocked":false,"should_hide_responses":false}},"has_agent_written_to_block":true}',
        '{"Terminal":{"pending_conversation_ids":[],"conversation_ids":["0b3c1c1a-5d0a-4f43-9d0e-3c8f8a4f1a11"]}}'),
    (x'0101', x'636d64', x'6f7574', 0, 1, '2026-01-01 10:02:00', '2026-01-01 10:02:00', 0, 0, 'agent-view', NULL,
        '{"Agent":{"origin_conversation_id":"0b3c1c1a-5d0a-4f43-9d0e-3c8f8a4f1a11","pending_other_conversation_ids":[],"other_conversation_ids":[]}}'),
    (x'0101', x'636d64', x'6f7574', 0, 1, '2026-01-01 10:03:00', '2026-01-01 10:03:00', 0, 0, 'attached', NULL,
        '{"Terminal":{"pending_conversation_ids":[],"conversation_ids":["0b3c1c1a-5d0a-4f43-9d0e-3c8f8a4f1a11"]}}'),
    (x'0101', x'636d64', x'6f7574', 0, 1, '2026-01-01 10:04:00', '2026-01-01 10:04:00', 0, 0, 'null-metadata', 'null', NULL),
    (x'0101', x'636d64', x'6f7574', 0, 1, '2026-01-01 10:05:00', '2026-01-01 10:05:00', 0, 0, 'garbled-metadata', 'not json', '"Terminal"'),
    (x'0202', x'636d64', x'6f7574', 0, 1, '2026-01-01 10:06:00', '2026-01-01 10:06:00', 0, 0, 'second-terminal', NULL, NULL);

-- Tables kept as they are.
INSERT INTO commands (command, exit_code, start_ts, completed_ts, pwd, shell, username, hostname,
    session_id, git_branch, cloud_workflow_id, workflow_command, is_agent_executed)
VALUES
    ('echo one', 0, '2026-01-01 10:00:00', '2026-01-01 10:00:01', '/work/one', 'zsh', 'me', 'host', 1, NULL, 'cloud-workflow-1', NULL, 0),
    ('echo {{word}}', 0, '2026-01-01 10:01:00', '2026-01-01 10:01:01', '/work/one', 'zsh', 'me', 'host', 1, NULL, NULL, 'echo {{word}}', 1);
INSERT INTO projects (path, added_ts, last_opened_ts) VALUES ('/work/one', '2026-01-01 00:00:00', NULL);
INSERT INTO ignored_suggestions (suggestion, suggestion_type) VALUES ('rm -rf', 'shell_command');
INSERT INTO workspace_metadata (id, repo_path, navigated_ts, modified_ts, queried_ts) VALUES (1, '/work/one', NULL, NULL, NULL);
INSERT INTO workspace_language_server (id, workspace_id, language_server_name, enabled) VALUES (1, 1, '"RustAnalyzer"', '"Yes"');

-- Tables the migration drops.
INSERT INTO agent_conversations (id, conversation_id, conversation_data, summary) VALUES (1, 'conversation-1', '{}', 'summary');
INSERT INTO agent_tasks (id, conversation_id, task_id, task) VALUES (1, 'conversation-1', 'task-1', x'00');
INSERT INTO ai_queries (id, exchange_id, conversation_id, start_ts, input, working_directory, output_status)
    VALUES (1, 'exchange-1', 'conversation-1', '2026-01-01 00:00:00', '[]', '/work/one', 'Completed');
INSERT INTO active_mcp_servers (id, mcp_server_uuid) VALUES (1, 'mcp-1');
INSERT INTO mcp_environment_variables (mcp_server_uuid, environment_variables) VALUES (x'01', '{}');
INSERT INTO mcp_server_installations (id, templatable_mcp_server, template_version_ts, variable_values,
    restore_running, last_modified_at) VALUES ('mcp-1', '{}', '2026-01-01 00:00:00', '{}', 0, '2026-01-01 00:00:00');
INSERT INTO project_rules (id, path, project_root) VALUES (1, '/work/one/AGENTS.md', '/work/one');

INSERT INTO object_metadata (id, is_pending, object_type, shareable_object_id, retry_count)
    VALUES (1, 0, 'NOTEBOOK', 1, 0);
INSERT INTO object_permissions (id, object_metadata_id, subject_type, subject_uid) VALUES (1, 1, 'USER', 'user-1');
INSERT INTO object_actions (id, hashed_object_id, action) VALUES (1, 'hash', 'Execute');
INSERT INTO cloud_objects_refreshes (id, time_of_next_refresh) VALUES (1, '2026-01-01 00:00:00');
INSERT INTO generic_string_objects (id, data) VALUES (1, '{}');
INSERT INTO workflows (id, data) VALUES (1, '{}');
INSERT INTO notebooks (id, title, data, ai_document_id) VALUES (1, 'title', 'data', 'doc-1');
INSERT INTO folders (id, name, is_open, is_warp_pack) VALUES (1, 'folder', 0, 0);

INSERT INTO teams (id, name, server_uid, billing_metadata_json, feature_model_choice_json) VALUES (1, 'team', 'team-uid', '{}', '{}');
INSERT INTO workspaces (id, name, server_uid, is_selected, feature_model_choice_json) VALUES (1, 'workspace', 'workspace-uid', 1, '{}');
INSERT INTO team_settings (id, team_id, settings_json) VALUES (1, 1, '{}');
INSERT INTO team_members (team_id, user_uid, email, role, is_disabled) VALUES (1, 'user-1', 'me@example.com', 'Admin', 0);
INSERT INTO workspace_teams (id, workspace_server_uid, team_server_uid) VALUES (1, 'workspace-uid', 'team-uid');

INSERT INTO users (id, firebase_uid) VALUES (1, 'firebase-1');
INSERT INTO user_profiles (firebase_uid, photo_url, email, display_name) VALUES ('firebase-1', 'url', 'me@example.com', 'Me');
INSERT INTO current_user_information (email) VALUES ('me@example.com');
INSERT INTO server_experiments (experiment) VALUES ('experiment-1');
