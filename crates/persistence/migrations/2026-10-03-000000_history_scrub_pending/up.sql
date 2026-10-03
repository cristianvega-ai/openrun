CREATE TABLE history_scrub_pending (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    generation TEXT NOT NULL
);
