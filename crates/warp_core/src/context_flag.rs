//! ContextFlag flags are for behaviors that need to be conditionally enabled or disabled based
//! on where the app is being run and are a permanent part of the app.

use std::sync::atomic::{AtomicBool, Ordering};

use enum_iterator::{Sequence, cardinality};

/// All ContextFlag flags are enabled by default.
#[derive(Copy, Clone, Hash, PartialEq, Eq, Debug, Sequence)]
pub enum ContextFlag {
    CreateNewSession,
    CloseWindow,
    ForceSidePanelOpen,
    NetworkLogConsole,
    RunWorkflow,
    LaunchConfigurations,
    WarpEssentials,
    AllowSettingsModalToClose,
    ShowSlowShellStartupBanner,
}

/// The enablement states for context flags.  As mentioned in the documentation
/// for [`ContextFlag`], these are enabled by default.
static FLAG_STATES: [AtomicBool; cardinality::<ContextFlag>()] =
    [const { AtomicBool::new(true) }; { cardinality::<ContextFlag>() }];

impl ContextFlag {
    pub fn is_enabled(&self) -> bool {
        FLAG_STATES[*self as usize].load(Ordering::Relaxed)
    }
}
