use std::path::PathBuf;

use serde::{Deserialize, Serialize};

/// A file location used as code context.
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum CodeContextLocation {
    /// Represent an entire file (used in outline-based context)
    WholeFile(PathBuf),
}

impl CodeContextLocation {
    pub fn path(&self) -> &PathBuf {
        match self {
            CodeContextLocation::WholeFile(path) => path,
        }
    }
}
