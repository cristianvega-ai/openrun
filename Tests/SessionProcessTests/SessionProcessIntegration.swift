import Testing

/// Every integration test starts real processes and blocks threads while it
/// waits for them. Running them one after another keeps them from starving each
/// other of threads, and keeps the timing of the tests steady.
@Suite(.serialized) enum SessionProcessIntegration {}
