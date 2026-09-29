use serde::{Deserialize, Serialize};
use warpui::AppContext;

pub mod arguments;
pub mod categories;
pub mod command_parser;
pub mod info_box;
pub mod local_workflows;
pub mod workflow;

pub use categories::{CategoriesView, CategoriesViewEvent, WorkflowsViewAction};
use workflow::Workflow;

pub fn init(app: &mut AppContext) {
    categories::init(app);
}

#[derive(Copy, Clone, Debug, Deserialize, Serialize, Eq, PartialEq, Hash)]
pub enum WorkflowSource {
    Global,
    Local,
    Project,

    /// A hardcoded workflow type that allows Warp to surface features as Workflows (e.g.
    /// a command to tail the diagnostic log)
    App,
}

/// Wrapper type for a workflow that is run from the terminal input.
#[derive(Clone, Debug, PartialEq)]
pub enum WorkflowType {
    /// Workflows sourced from the local, global, project and app collections.
    Local(Workflow),
}

impl WorkflowType {
    pub fn as_workflow(&self) -> &Workflow {
        let WorkflowType::Local(workflow) = self;
        workflow
    }

    /// Returns the contained [`Workflow`], consuming `self`.
    pub fn take_workflow(self) -> Workflow {
        let WorkflowType::Local(workflow) = self;
        workflow
    }
}
