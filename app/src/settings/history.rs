use settings::macros::define_settings_group;

define_settings_group!(HistorySettings, settings: [
    save_command_history: SaveCommandHistory {
        type: bool,
        default: true,
        private: false,
        toml_path: "privacy.save_command_history",
        description: "Whether OpenRun saves the commands you run, and the command text and output of session-restore blocks, to its local database. When false, nothing new is written there and nothing from it is loaded at startup; up-arrow history works only until the app quits. Commands already saved stay on disk until you use Delete saved history.",
    },
]);

#[cfg(test)]
#[path = "history_tests.rs"]
mod tests;
