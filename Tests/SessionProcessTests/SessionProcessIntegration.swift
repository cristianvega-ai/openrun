import SessionProcessHarness
import Testing

/// Every integration test starts real processes and blocks threads while it
/// waits for them. Each test runs on a thread of its own, so a blocked test
/// does not stop the others. See `IsolatedThreadTrait`.
@Suite(.isolatedThread) enum SessionProcessIntegration {}
