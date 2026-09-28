/// Discards a telemetry event: nothing is recorded or sent. The event and context are still
/// evaluated so that call sites keep type-checking.
#[macro_export]
macro_rules! send_telemetry_sync_from_ctx {
    ($event:expr_2021, $ctx:expr_2021) => {{
        let _ = $event;
        let _ = &$ctx;
    }};
}

/// Same as [`send_telemetry_sync_from_ctx`], for callers that only have an `AppContext`.
#[macro_export]
macro_rules! send_telemetry_sync_from_app_ctx {
    ($event:expr_2021, $app_ctx:expr_2021) => {{
        let _ = $event;
        let _ = &$app_ctx;
    }};
}

/// Same as [`send_telemetry_sync_from_ctx`], for callers that only have an executor.
#[macro_export]
macro_rules! send_telemetry_on_executor {
    ($auth_state: expr_2021, $event:expr_2021, $executor:expr_2021) => {{
        let _ = &$auth_state;
        let _ = $event;
        let _ = &$executor;
    }};
}
