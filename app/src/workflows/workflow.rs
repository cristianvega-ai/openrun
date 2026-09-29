use serde::Deserialize;

/// A saved or ad-hoc command with a name, optional description and text arguments.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Hash)]
#[serde(untagged)]
pub enum Workflow {
    Command {
        name: String,
        command: String,
        #[serde(default)]
        tags: Vec<String>,
        description: Option<String>,
        #[serde(default)]
        arguments: Vec<Argument>,
        source_url: Option<String>,
        author: Option<String>,
        author_url: Option<String>,
        #[serde(default)]
        shells: Vec<warp_workflows::Shell>,
    },
}

impl Workflow {
    pub fn name(&self) -> &str {
        let Self::Command { name, .. } = self;
        name.as_str()
    }

    /// The core "content" of the workflow: the shell command.
    pub fn content(&self) -> &str {
        let Self::Command { command, .. } = self;
        command
    }

    pub fn command(&self) -> Option<&str> {
        let Self::Command { command, .. } = self;
        Some(command.as_str())
    }

    pub fn description(&self) -> Option<&String> {
        let Self::Command { description, .. } = self;
        description.as_ref()
    }

    pub fn arguments(&self) -> &Vec<Argument> {
        let Self::Command { arguments, .. } = self;
        arguments
    }

    pub fn tags(&self) -> Option<&Vec<String>> {
        let Self::Command { tags, .. } = self;
        Some(tags)
    }

    pub fn source_url(&self) -> Option<&String> {
        let Self::Command { source_url, .. } = self;
        source_url.as_ref()
    }

    pub fn author_name(&self) -> Option<&String> {
        let Self::Command { author, .. } = self;
        author.as_ref()
    }

    pub fn shells(&self) -> Option<&Vec<warp_workflows::Shell>> {
        let Self::Command { shells, .. } = self;
        Some(shells)
    }

    pub fn is_command_workflow(&self) -> bool {
        matches!(self, Self::Command { .. })
    }

    pub fn new(name: impl Into<String>, command: impl Into<String>) -> Self {
        Workflow::Command {
            name: name.into(),
            command: command.into(),
            tags: Vec::new(),
            arguments: Vec::new(),
            description: None,
            source_url: None,
            author: None,
            author_url: None,
            shells: Vec::new(),
        }
    }

    pub fn with_arguments(mut self, new_arguments: Vec<Argument>) -> Self {
        let Workflow::Command {
            ref mut arguments, ..
        } = self;
        *arguments = new_arguments;
        self
    }

    pub fn with_description(mut self, new_description: String) -> Self {
        let Workflow::Command {
            ref mut description,
            ..
        } = self;
        *description = Some(new_description);
        self
    }

    pub fn set_name(&mut self, new_name: &str) {
        let Workflow::Command { name, .. } = self;
        new_name.clone_into(name)
    }
}

impl From<warp_workflows::Workflow> for Workflow {
    fn from(workflow: warp_workflows::Workflow) -> Self {
        Workflow::Command {
            name: workflow.name,
            command: workflow.command,
            description: workflow.description,
            arguments: workflow.arguments.into_iter().map(Argument::from).collect(),
            tags: workflow.tags,
            source_url: workflow.source_url,
            author: workflow.author,
            author_url: workflow.author_url,
            shells: workflow.shells,
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Hash, Default)]
pub struct Argument {
    pub name: String,
    pub description: Option<String>,
    pub default_value: Option<String>,
}

impl From<warp_workflows::Argument> for Argument {
    fn from(arg: warp_workflows::Argument) -> Self {
        Argument {
            name: arg.name,
            description: arg.description,
            default_value: arg.default_value,
        }
    }
}

impl Argument {
    pub fn new(name: impl Into<String>) -> Self {
        Argument {
            name: name.into(),
            description: None,
            default_value: None,
        }
    }

    pub fn with_description(mut self, description: impl Into<String>) -> Self {
        self.description = Some(description.into());
        self
    }

    pub fn with_default(mut self, default: impl Into<String>) -> Self {
        self.default_value = Some(default.into());
        self
    }

    pub fn name(&self) -> &str {
        &self.name
    }

    pub fn description(&self) -> &Option<String> {
        &self.description
    }

    pub fn default_value(&self) -> &Option<String> {
        &self.default_value
    }
}
