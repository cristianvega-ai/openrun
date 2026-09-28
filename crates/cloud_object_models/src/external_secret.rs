use serde::{Deserialize, Serialize};
use warp_util::path::ShellFamily;

/// Represents a completed external secret reference.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub enum ExternalSecret {
    OnePassword(OnePasswordSecret),
    LastPass(LastPassSecret),
}

impl ExternalSecret {
    pub fn get_secret_extraction_command(&self, shell_family: ShellFamily) -> String {
        let prefix = match shell_family {
            ShellFamily::Posix => "\\",
            ShellFamily::PowerShell => "",
        };
        match self {
            ExternalSecret::OnePassword(secret) => {
                format!(
                    "{}op item get --fields credential --reveal {}",
                    prefix, secret.reference
                )
            }
            ExternalSecret::LastPass(secret) => {
                format!("{}lpass show --password {}", prefix, secret.reference)
            }
        }
    }

    pub fn get_display_name(&self) -> String {
        match self {
            ExternalSecret::OnePassword(secret) => secret.name.clone(),
            ExternalSecret::LastPass(secret) => secret.name.clone(),
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct OnePasswordSecret {
    name: String,
    reference: String,
}

impl OnePasswordSecret {
    pub fn new(name: String, reference: String) -> Self {
        Self { name, reference }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct LastPassSecret {
    name: String,
    reference: String,
}

impl LastPassSecret {
    pub fn new(name: String, reference: String) -> Self {
        Self { name, reference }
    }
}
