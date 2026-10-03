pub mod model;
pub mod schema;

pub const MIGRATIONS: diesel_migrations::EmbeddedMigrations =
    diesel_migrations::embed_migrations!("migrations");

#[cfg(test)]
#[path = "migration_tests.rs"]
mod migration_tests;
