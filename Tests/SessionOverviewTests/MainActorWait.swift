/// Waits on the main actor until the condition holds or the time passes.
/// The sleep lets go of the main queue, so the blocks that bring the
/// events of a connection can run.
@MainActor
func waitUntil(timeout: Duration = .seconds(15), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
    return condition()
}
