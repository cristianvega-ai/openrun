//! Interface for working with processes that ensures that commands are spawned with the correct set
//! of arguments: stdin, stdout and stderr are not inherited from the app unless a caller configures
//! them.
//!
//! [`blocking::Command`] can be used as a drop-in replacement for [`std::process::Command`],
//! and [`r#async::Command`] can be used as a drop-in replacement for [`async_process::Command`].
pub mod r#async;
pub mod blocking;
pub mod unix;

pub use std::process::{ExitStatus, Output, Stdio};
