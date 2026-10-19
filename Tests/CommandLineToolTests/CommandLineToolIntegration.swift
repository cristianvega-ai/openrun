import Testing

/// Integration tests start real processes and block threads while they wait,
/// so they run one after another. See `SessionProcessIntegration`.
@Suite(.serialized) enum CommandLineToolIntegration {}
