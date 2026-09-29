mod config;
mod state;

use std::fmt;

pub use config::*;
pub use state::*;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Channel {
    /// The open-source build of Warp.
    Oss,

    /// The integration test build.
    Integration,
}

impl Channel {
    /// Returns the Warp Control CLI command name corresponding to this channel.
    pub fn warpctrl_command_name(&self) -> &'static str {
        match self {
            Channel::Integration => "warpctrl-integration",
            Channel::Oss => "warpctrl-oss",
        }
    }
}

impl fmt::Display for Channel {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str(match self {
            Channel::Integration => "integration",
            Channel::Oss => "warp-oss",
        })
    }
}
