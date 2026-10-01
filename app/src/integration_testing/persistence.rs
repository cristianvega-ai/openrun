#[cfg(feature = "local_fs")]
pub use crate::persistence::{PersistenceScope, database_file_path_for_scope};

/// Helpers for tests that inspect what the app wrote to its SQLite database.
#[cfg(feature = "local_fs")]
pub mod written_data {
    use diesel::prelude::*;
    use warpui::{App, AppContext, SingletonEntity as _};

    use crate::persistence::{
        ModelEvent, PersistenceWriter, database_file_path_for_current_scope,
        establish_ro_connection, schema,
    };
    use crate::suggestions::ignored_suggestions_model::SuggestionType;

    const WRITE_MARKER: &str = "OPENRUN_TEST_WRITE_MARKER";

    /// Queues a marker row behind every event already sent to the writer thread. Once
    /// [`write_marker_is_visible`] returns `true`, everything sent before has been handled.
    pub fn queue_write_marker(app: &mut App) {
        app.update(|ctx: &mut AppContext| {
            let sender = PersistenceWriter::handle(ctx)
                .as_ref(ctx)
                .sender()
                .expect("the persistence writer should be running");
            sender
                .send(ModelEvent::AddIgnoredSuggestion {
                    suggestion: WRITE_MARKER.to_owned(),
                    suggestion_type: SuggestionType::ShellCommand,
                })
                .expect("the marker should be queued");
        });
    }

    pub fn write_marker_is_visible() -> bool {
        let path = database_file_path_for_current_scope();
        let Some(path) = path.to_str() else {
            return false;
        };
        let Ok(mut conn) = establish_ro_connection(path) else {
            return false;
        };
        schema::ignored_suggestions::dsl::ignored_suggestions
            .filter(schema::ignored_suggestions::dsl::suggestion.eq(WRITE_MARKER))
            .count()
            .get_result::<i64>(&mut conn)
            .is_ok_and(|count| count > 0)
    }

    /// The number of saved commands and saved blocks.
    pub fn saved_history_row_counts() -> (i64, i64) {
        let path = database_file_path_for_current_scope();
        let mut conn = establish_ro_connection(path.to_str().expect("database path is UTF-8"))
            .expect("the database should open");
        let commands = schema::commands::dsl::commands
            .count()
            .get_result(&mut conn)
            .expect("commands should count");
        let blocks = schema::blocks::dsl::blocks
            .count()
            .get_result(&mut conn)
            .expect("blocks should count");
        (commands, blocks)
    }

    /// Whether `needle` occurs in the bytes of the database file or its write-ahead log.
    pub fn database_bytes_contain(needle: &str) -> bool {
        let path = database_file_path_for_current_scope();
        ["", "-wal"].iter().any(|suffix| {
            std::fs::read(format!("{}{suffix}", path.display())).is_ok_and(|bytes| {
                bytes
                    .windows(needle.len())
                    .any(|window| window == needle.as_bytes())
            })
        })
    }
}
