pub mod terminal_manager;
mod terminal_view_adaptor;

pub use terminal_manager::TerminalManager;
pub(crate) use terminal_view_adaptor::{TerminalViewSurfaceConfig, create_terminal_view_surface};
pub use warp_terminal::local_tty::*;

pub fn run_terminal_server(args: &warp_cli::TerminalServerArgs) {
    warp_terminal::local_tty::server::run_terminal_server(
        args,
        crate::features::init_feature_flags,
        crate::terminal::platform::init,
    );
}

impl event_loop::ActiveTerminal for crate::terminal::TerminalModel {
    fn input_reporting_block(&self) -> Option<warp_terminal::model::BlockId> {
        self.input_reporting_block()
    }

    fn exit(&mut self, reason: crate::terminal::model::terminal_model::ExitReason) {
        crate::terminal::TerminalModel::exit(self, reason);
    }
}
