import SessionProcessHarness
import Testing

/// Integration tests start real processes and block threads while they wait,
/// so each one runs on a thread of its own. See `IsolatedThreadTrait`.
@Suite(.isolatedThread) enum CommandLineToolIntegration {}
