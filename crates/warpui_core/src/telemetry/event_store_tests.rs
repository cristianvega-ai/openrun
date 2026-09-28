use chrono::{Duration, TimeZone, Utc};

use crate::telemetry::event_store::{
    EventPayload, EventStore, SESSION_CONTINUATION_THRESHOLD_SECONDS,
};
use crate::time::{get_current_time, test_offset_time};

fn record_block_creation(
    event_store: &mut EventStore,
    user_id: &Option<String>,
    anonymous_id: &str,
) {
    event_store.record_event(
        user_id.clone(),
        anonymous_id.to_owned(),
        "Block Creation".into(),
        None,
        false, /* contains_ugc */
        get_current_time(),
    );
}

#[test]
fn test_initialize_session() {
    test_offset_time(5);
    let event_store = EventStore::new();
    assert_eq!(
        event_store.current_session_created_at,
        Utc.timestamp_opt(5, 0).unwrap()
    );
}

#[test]
fn test_event_queue_empty() {
    let user_id = Some("user123".to_string());
    let anonymous_id = "anon-user-xyz";
    let mut event_store = EventStore::new();
    record_block_creation(&mut event_store, &user_id, anonymous_id);
    let session_created_at_0 = event_store.current_session_created_at;

    // Queue is empty and an event comes in while session is fresh
    event_store.events.clear();
    test_offset_time(1);
    record_block_creation(&mut event_store, &user_id, anonymous_id);
    assert_eq!(
        event_store.events.back().unwrap().session_created_at,
        session_created_at_0
    );

    // Queue is empty and an event comes in while session is stale
    event_store.events.clear();
    let inactivity_duration = SESSION_CONTINUATION_THRESHOLD_SECONDS as i64 + 1;
    test_offset_time(inactivity_duration);
    let now = get_current_time();
    record_block_creation(&mut event_store, &user_id, anonymous_id);
    assert_eq!(event_store.events.back().unwrap().session_created_at, now);
}

#[test]
fn test_named_event_after_inactivity() {
    let user_id = Some("user123".to_string());
    let anonymous_id = "anon-user-xyz";
    let mut event_store = EventStore::new();
    let inactivity_duration = SESSION_CONTINUATION_THRESHOLD_SECONDS as i64 + 1;
    record_block_creation(&mut event_store, &user_id, anonymous_id);
    let session_created_at_0 = event_store.events.back().unwrap().session_created_at;

    test_offset_time(inactivity_duration);

    record_block_creation(&mut event_store, &user_id, anonymous_id);
    assert_eq!(
        event_store.events.back().unwrap().payload,
        EventPayload::NamedEvent {
            user_id,
            anonymous_id: anonymous_id.to_owned(),
            name: "Block Creation".into(),
            value: None
        }
    );
    let session_created_at_1 = event_store.events.back().unwrap().session_created_at;
    assert_eq!(
        session_created_at_1 - session_created_at_0,
        Duration::seconds(inactivity_duration)
    );
}

#[test]
fn test_named_event_after_activity() {
    let user_id = Some("user123".to_string());
    let anonymous_id = "anon-user-xyz";
    let mut event_store = EventStore::new();
    record_block_creation(&mut event_store, &user_id, anonymous_id);
    let timestamp_0 = event_store.events.back().unwrap().timestamp;
    let session_created_at_0 = event_store.events.back().unwrap().session_created_at;

    test_offset_time(5);
    record_block_creation(&mut event_store, &user_id, anonymous_id);
    assert_eq!(event_store.events.len(), 2);
    let timestamp_1 = event_store.events.back().unwrap().timestamp;
    let session_created_at_1 = event_store.events.back().unwrap().session_created_at;
    assert_eq!(session_created_at_0, session_created_at_1);
    assert_eq!(timestamp_1 - timestamp_0, Duration::seconds(5));
}
