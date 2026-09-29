-- Recreates the dropped tables and columns empty. The rows, and the pane tree entries of the
-- removed pane kinds, are not restored.

CREATE TABLE server_experiments (
    experiment TEXT PRIMARY KEY NOT NULL
);

CREATE TABLE current_user_information (
    email TEXT PRIMARY KEY NOT NULL
);

CREATE TABLE user_profiles (
    firebase_uid TEXT NOT NULL PRIMARY KEY,
    photo_url TEXT NOT NULL,
    email TEXT NOT NULL,
    display_name TEXT
);

CREATE TABLE users (
   id INTEGER NOT NULL PRIMARY KEY,
   firebase_uid  TEXT NOT NULL UNIQUE
);

CREATE TABLE teams (
  id integer NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  server_uid TEXT NOT NULL UNIQUE,
  billing_metadata_json TEXT,
  feature_model_choice_json TEXT
);

CREATE TABLE workspaces (
    id integer NOT NULL PRIMARY KEY,
    name TEXT NOT NULL,
    server_uid TEXT NOT NULL UNIQUE,
    is_selected BOOLEAN NOT NULL DEFAULT FALSE,
    feature_model_choice_json TEXT
);

CREATE TABLE team_settings (
    id INTEGER PRIMARY KEY NOT NULL,
    team_id INTEGER NOT NULL UNIQUE,
    settings_json TEXT NOT NULL,
    FOREIGN KEY (team_id) REFERENCES teams (id)
);

CREATE TABLE team_members (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    team_id INTEGER NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    user_uid TEXT NOT NULL,
    email TEXT NOT NULL,
    role TEXT NOT NULL,
    is_disabled BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE workspace_teams (
    id integer NOT NULL PRIMARY KEY,
    workspace_server_uid TEXT NOT NULL UNIQUE,
    team_server_uid TEXT NOT NULL UNIQUE,
    FOREIGN KEY (workspace_server_uid) REFERENCES workspaces (server_uid),
    FOREIGN KEY (team_server_uid) REFERENCES teams (server_uid)
);

CREATE TABLE folders (
    id INTEGER NOT NULL PRIMARY KEY,
    name TEXT NOT NULL,
    is_open BOOLEAN NOT NULL,
    is_warp_pack BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE notebooks (
  id INTEGER NOT NULL PRIMARY KEY,
  title TEXT,
  data TEXT,
  ai_document_id TEXT
);

CREATE TABLE workflows (
    id INTEGER NOT NULL PRIMARY KEY,
    data TEXT NOT NULL
);

CREATE TABLE generic_string_objects (
    id INTEGER NOT NULL PRIMARY KEY,
    data TEXT NOT NULL
);

CREATE TABLE cloud_objects_refreshes (
  id INTEGER PRIMARY KEY NOT NULL,
  time_of_next_refresh DATETIME NOT NULL
);

CREATE TABLE object_actions (
  id INTEGER PRIMARY KEY NOT NULL,
  hashed_object_id TEXT NOT NULL,
  timestamp DATETIME,
  action TEXT NOT NULL,
  data TEXT,
  count INTEGER,
  oldest_timestamp DATETIME,
  latest_timestamp DATETIME,
  pending BOOLEAN,
  processed_at_timestamp DATETIME
);

CREATE TABLE object_metadata (
    id INTEGER NOT NULL PRIMARY KEY,
    is_pending BOOLEAN NOT NULL,
    object_type TEXT NOT NULL,
    revision_ts INTEGER,
    server_id TEXT,
    client_id TEXT,
    shareable_object_id INTEGER NOT NULL,
    author_id INTEGER,
    retry_count INTEGER NOT NULL,
    metadata_last_updated_ts BIGINTEGER,
    trashed_ts BIGINTEGER,
    folder_id TEXT,
    is_welcome_object BOOLEAN NOT NULL DEFAULT false,
    creator_uid TEXT,
    last_editor_uid TEXT,
    current_editor TEXT
);

CREATE TABLE object_permissions (
  id INTEGER NOT NULL PRIMARY KEY,
  object_metadata_id INTEGER NOT NULL REFERENCES object_metadata(id) ON DELETE CASCADE,
  subject_type TEXT NOT NULL,
  subject_id TEXT,
  subject_uid TEXT NOT NULL,
  permissions_last_updated_at BIGINTEGER,
  object_guests BLOB,
  anyone_with_link_access_level TEXT,
  anyone_with_link_source BLOB
);

CREATE TABLE project_rules (
    id INTEGER NOT NULL PRIMARY KEY,
    path TEXT NOT NULL,
    project_root TEXT NOT NULL
);
CREATE UNIQUE INDEX idx_project_rules_path_unique ON project_rules(path);

CREATE TABLE mcp_server_installations (
    id TEXT NOT NULL PRIMARY KEY,
    templatable_mcp_server TEXT NOT NULL,
    template_version_ts TIMESTAMP NOT NULL,
    variable_values TEXT NOT NULL,
    restore_running BOOLEAN NOT NULL,
    last_modified_at TIMESTAMP NOT NULL
);

CREATE TABLE mcp_environment_variables (
    mcp_server_uuid BLOB PRIMARY KEY NOT NULL,
    environment_variables TEXT NOT NULL
);

CREATE TABLE active_mcp_servers (
    id INTEGER PRIMARY KEY NOT NULL,
    mcp_server_uuid TEXT NOT NULL,
    UNIQUE(mcp_server_uuid)
);

CREATE TABLE ai_queries (
  id INTEGER PRIMARY KEY NOT NULL,
  exchange_id TEXT NOT NULL,
  conversation_id TEXT NOT NULL,
  start_ts DATETIME NOT NULL,
  input TEXT NOT NULL,
  working_directory TEXT,
  output_status TEXT NOT NULL,
  model_id TEXT NOT NULL DEFAULT '',
  planning_model_id TEXT NOT NULL DEFAULT '',
  coding_model_id TEXT NOT NULL DEFAULT ''
);
CREATE UNIQUE INDEX ux_ai_queries_exchange_id ON ai_queries(exchange_id);

CREATE TABLE agent_conversations (
    id INTEGER PRIMARY KEY NOT NULL,
    conversation_id TEXT NOT NULL,
    conversation_data TEXT NOT NULL,
    last_modified_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    summary TEXT
);
CREATE TRIGGER update_last_modified_at_for_agent_conversations AFTER
UPDATE ON agent_conversations FOR EACH ROW WHEN NEW.last_modified_at IS OLD.last_modified_at BEGIN
UPDATE agent_conversations
SET
    last_modified_at = CURRENT_TIMESTAMP
WHERE
    id = OLD.id;

END;
CREATE UNIQUE INDEX ux_agent_conversations_conversation_id ON agent_conversations (conversation_id);

CREATE TABLE agent_tasks (
    id INTEGER PRIMARY KEY NOT NULL,
    conversation_id TEXT NOT NULL,
    task_id TEXT NOT NULL,
    task BLOB NOT NULL,
    last_modified_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (conversation_id) REFERENCES agent_conversations (conversation_id)
);
CREATE TRIGGER update_last_modified_at_for_agent_tasks AFTER
UPDATE ON agent_tasks FOR EACH ROW WHEN NEW.last_modified_at IS OLD.last_modified_at BEGIN
UPDATE agent_tasks
SET
    last_modified_at = CURRENT_TIMESTAMP
WHERE
    id = OLD.id;

END;
CREATE UNIQUE INDEX ux_agent_tasks_task_id ON agent_tasks (task_id);

ALTER TABLE windows ADD COLUMN warp_ai_width FLOAT CHECK (warp_ai_width >= 0);
ALTER TABLE windows ADD COLUMN warp_drive_index_width FLOAT CHECK (warp_drive_index_width >= 0);
ALTER TABLE windows ADD COLUMN agent_management_filters TEXT;
ALTER TABLE windows ADD COLUMN team_uid TEXT;
ALTER TABLE terminal_panes ADD COLUMN llm_model_override TEXT;
ALTER TABLE terminal_panes ADD COLUMN active_profile_id TEXT;
ALTER TABLE terminal_panes ADD COLUMN conversation_ids TEXT;
ALTER TABLE terminal_panes ADD COLUMN active_conversation_id TEXT;
ALTER TABLE notebook_panes ADD COLUMN notebook_id TEXT;
ALTER TABLE commands ADD COLUMN cloud_workflow_id TEXT;
ALTER TABLE blocks ADD COLUMN ai_metadata TEXT;
ALTER TABLE blocks ADD COLUMN agent_view_visibility TEXT;

CREATE TABLE workflow_panes (
  id INTEGER PRIMARY KEY NOT NULL,
  kind TEXT NOT NULL DEFAULT 'workflow' CHECK (kind = 'workflow'),
  workflow_id TEXT,
  FOREIGN KEY (id, kind) REFERENCES pane_leaves (pane_node_id, kind)
);

CREATE TABLE env_var_collection_panes (
  id INTEGER PRIMARY KEY NOT NULL,
  kind TEXT NOT NULL DEFAULT 'env_var_collection' CHECK (kind = 'env_var_collection'),
  env_var_collection_id TEXT,
  FOREIGN KEY (id, kind) REFERENCES pane_leaves (pane_node_id, kind)
);

CREATE TABLE mcp_server_panes (
  id INTEGER PRIMARY KEY NOT NULL,
  kind TEXT NOT NULL DEFAULT 'mcp_server' CHECK (kind = 'mcp_server'),
  FOREIGN KEY (id, kind) REFERENCES pane_leaves (pane_node_id, kind)
);

CREATE TABLE ai_memory_panes (
  id INTEGER PRIMARY KEY NOT NULL,
  kind TEXT NOT NULL DEFAULT 'ai_memory' CHECK (kind = 'ai_memory'),
  FOREIGN KEY (id, kind) REFERENCES pane_leaves (pane_node_id, kind)
);

CREATE TABLE ai_document_panes (
    id INTEGER PRIMARY KEY NOT NULL,
    kind TEXT NOT NULL DEFAULT 'ai_document' CHECK (kind = 'ai_document'),
    document_id TEXT NOT NULL,
    version INTEGER NOT NULL,
    content TEXT,
    title TEXT,
    FOREIGN KEY (id, kind) REFERENCES pane_leaves (pane_node_id, kind)
);

CREATE TABLE ambient_agent_panes (
    id INTEGER PRIMARY KEY NOT NULL REFERENCES pane_nodes(id),
    kind TEXT NOT NULL DEFAULT 'ambient_agent',
    uuid BLOB NOT NULL,
    task_id TEXT
);
