use std::collections::HashMap;

use chrono::{DateTime, Local};
#[cfg(test)]
use uuid::Uuid;
use warp_multi_agent_api::ToolType;

use crate::ai::agent::AIAgentInput;
use crate::ai::agent::conversation::AIConversationId;
use crate::ai::agent::task::TaskId;
use crate::ai::llms::LLMId;
use crate::terminal::ShellLaunchData;
use crate::terminal::model::session::SessionType;
use crate::terminal::model::session::active_session::ActiveSession;
use warpui::AppContext;

#[derive(Debug, Clone)]
pub struct SessionContext {
    session_type: Option<SessionType>,
    shell: Option<ShellLaunchData>,
    current_working_directory: Option<String>,
}

impl SessionContext {
    pub fn from_session(session: &ActiveSession, app: &AppContext) -> Self {
        SessionContext {
            session_type: session.session_type(app),
            shell: session.shell_launch_data(app),
            current_working_directory: session.current_working_directory().cloned(),
        }
    }

    pub fn session_type(&self) -> &Option<SessionType> {
        &self.session_type
    }

    pub fn shell(&self) -> &Option<ShellLaunchData> {
        &self.shell
    }

    pub fn current_working_directory(&self) -> &Option<String> {
        &self.current_working_directory
    }

    /// Returns `true` if this is a remote session.
    pub fn is_remote(&self) -> bool {
        matches!(self.session_type, Some(SessionType::WarpifiedRemote))
    }

    #[cfg(test)]
    pub fn new_for_test() -> Self {
        SessionContext {
            session_type: None,
            shell: None,
            current_working_directory: None,
        }
    }

    #[cfg(test)]
    pub fn new_with_session_type_for_test(session_type: Option<SessionType>) -> Self {
        SessionContext {
            session_type,
            shell: None,
            current_working_directory: None,
        }
    }
}

#[derive(Debug)]
pub struct RequestInput {
    pub conversation_id: AIConversationId,
    pub input_messages: HashMap<TaskId, Vec<AIAgentInput>>,
    pub working_directory: Option<String>,
    pub model_id: LLMId,
    pub coding_model_id: LLMId,
    pub cli_agent_model_id: LLMId,
    pub request_start_ts: DateTime<Local>,
    pub supported_tools_override: Option<Vec<ToolType>>,
}

impl RequestInput {
    pub fn all_inputs(&self) -> impl Iterator<Item = &AIAgentInput> {
        self.input_messages.values().flatten()
    }

    pub fn with_supported_tools(mut self, tools: Vec<ToolType>) -> Self {
        self.supported_tools_override = Some(tools);
        self
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct ResponseStreamId(String);

impl ResponseStreamId {
    #[cfg(test)]
    pub fn new_for_test() -> Self {
        Self(Uuid::new_v4().to_string())
    }
}
