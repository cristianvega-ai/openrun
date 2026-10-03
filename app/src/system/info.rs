use std::ffi::OsStr;

use warpui::{Entity, ModelContext, SingletonEntity};

pub struct SystemInfo {
    /// A structure we can use to efficiently query system information.
    system: sysinfo::System,
}

impl SystemInfo {
    /// Creates a new [`SystemInfo`] model.
    pub fn new(_ctx: &mut ModelContext<Self>) -> Self {
        Self {
            system: sysinfo::System::new(),
        }
    }

    #[allow(dead_code)]
    pub fn refresh_all_processes(&mut self) {
        self.system.refresh_processes_specifics(
            sysinfo::ProcessesToUpdate::All,
            true, /* remove_dead_processes */
            Self::all_processes_refresh_kind(),
        );
    }

    #[allow(dead_code)]
    pub fn processes_by_name<'a>(
        &'a self,
        name: &'a str,
    ) -> impl Iterator<Item = &'a sysinfo::Process> {
        self.system.processes_by_name(OsStr::new(name))
    }

    /// Returns the [`sysinfo::ProcessRefreshKind`] that should be used when enumerating the entire
    /// process table.
    ///
    /// This samples neither CPU nor memory, which keeps enumerating the process table cheap.
    #[allow(dead_code)]
    fn all_processes_refresh_kind() -> sysinfo::ProcessRefreshKind {
        sysinfo::ProcessRefreshKind::nothing()
    }
}

impl Entity for SystemInfo {
    type Event = ();
}

impl SingletonEntity for SystemInfo {}
