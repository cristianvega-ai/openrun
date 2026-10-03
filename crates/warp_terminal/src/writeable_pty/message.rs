use std::borrow::Cow;

use crate::SizeInfo;
use crate::model::BlockId;

/// Messages that may be sent to the `EventLoop`.
#[derive(Debug)]
pub enum Message {
    /// Data that should be written to the PTY.
    Input(Cow<'static, [u8]>),

    /// Requests the shell input buffer after its line editor disables tty echo.
    InputReportingKey {
        key: [u8; 2],
        block: BlockId,
        done: async_channel::Sender<bool>,
    },

    /// Indicates that the `EventLoop` should be shut down.
    Shutdown,

    /// Instruction to resize the PTY.
    Resize(SizeInfo),
}
