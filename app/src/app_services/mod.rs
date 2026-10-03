//! Functionality relating to services that the application provides
//! to the host system.
//!
//! For example, on macOS, this module sets up integrations with
//! Finder such that the user can open a new Warp tab or window
//! in a given directory.

mod mac;

use warpui::AppContext;

pub fn init(_ctx: &mut AppContext) {
    log::info!("Initializing app services");

    mac::init();
}

pub fn teardown(_ctx: &mut AppContext) {
    log::info!("Tearing down app services...");
}
