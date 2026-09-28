use std::sync::OnceLock;

use warpui_core::{Entity, ModelContext, SingletonEntity};

// Global execution mode, for logic that runs outside the UI framework.
static GLOBAL_EXECUTION_MODE: OnceLock<ExecutionMode> = OnceLock::new();

/// Execution mode that Warp is running under.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ExecutionMode {
    /// Warp is running as a normal desktop app.
    App,
}

impl ExecutionMode {
    /// Returns the client ID to report to the server.
    /// This must stay in sync with the util/client.go constants on the server.
    pub fn client_id(&self) -> &'static str {
        match self {
            ExecutionMode::App => "warp-app",
        }
    }

    /// Whether a CLI-based MCP server can fall back to inheriting this process's PATH when
    /// no explicit `mcp_execution_path` setting is available.
    ///
    /// The desktop app keeps requiring a shell-derived path, so a failed MCP spawn surfaces
    /// as an actionable toast instead of silently launching with the wrong PATH.
    pub fn can_inherit_process_path_for_mcp(&self) -> bool {
        match self {
            ExecutionMode::App => false,
        }
    }
}

/// Model tracking the mode that Warp is running in.
#[derive(Clone, Debug)]
pub struct AppExecutionMode {
    mode: ExecutionMode,
}

impl AppExecutionMode {
    /// Create an `AppExecutionMode` model with the execution mode set.
    pub fn new(mode: ExecutionMode, _ctx: &mut ModelContext<Self>) -> Self {
        let _ = GLOBAL_EXECUTION_MODE.set(mode);
        Self { mode }
    }

    /// True if running as an interactive app client.
    fn is_app(&self) -> bool {
        matches!(self.mode, ExecutionMode::App)
    }

    /// Whether Active AI features are allowed in this execution mode.
    ///
    /// Active AI should only run in interactive clients, where there's a user
    /// to engage with it.
    pub fn allows_active_ai(&self) -> bool {
        self.is_app()
    }

    /// Whether the app can save and restore sessions.
    pub fn can_save_session(&self) -> bool {
        self.is_app()
    }

    /// Whether the app can automatically start MCP servers from the previous session.
    pub fn can_autostart_mcp_servers(&self) -> bool {
        self.is_app()
    }

    /// Whether the app can show interactive onboarding UIs (e.g. the onboarding
    /// callout tutorial). Onboarding requires a user to interact with it.
    pub fn can_show_onboarding(&self) -> bool {
        self.is_app()
    }

    /// Whether the app can sync agent conversations (tasks and cloud conversation metadata).
    pub fn can_fetch_agent_runs_for_management(&self) -> bool {
        self.is_app()
    }

    /// Returns the client ID to report to the server.
    pub fn client_id(&self) -> &'static str {
        self.mode.client_id()
    }

    /// Whether a CLI-based MCP server can fall back to inheriting this process's PATH when
    /// no explicit `mcp_execution_path` setting is available.
    pub fn can_inherit_process_path_for_mcp(&self) -> bool {
        self.mode.can_inherit_process_path_for_mcp()
    }
}

impl Entity for AppExecutionMode {
    type Event = ();
}

impl SingletonEntity for AppExecutionMode {}

/// Returns the current global client ID string.
/// This is set when AppExecutionMode is constructed during application start.
/// Returns None if the execution mode has not been set yet.
pub fn current_client_id() -> Option<&'static str> {
    GLOBAL_EXECUTION_MODE.get().map(|mode| mode.client_id())
}
