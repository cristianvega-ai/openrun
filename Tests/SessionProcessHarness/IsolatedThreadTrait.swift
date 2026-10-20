import Testing

/// Runs each test case of a suite on a thread of its own, after it gets a
/// slot from `IntegrationTestSlots`. The parent suites of the integration
/// tests use it in place of `.serialized`.
///
/// Integration tests block threads while they wait for real processes. Swift
/// Testing runs tests on the threads of Swift concurrency, so blocked tests
/// would stop the tasks that other tests and the harness wait for.
public struct IsolatedThreadTrait: SuiteTrait, TestTrait, TestScoping {
    public var isRecursive: Bool { true }

    public func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        let slots = IntegrationTestSlots.shared
        await slots.enter(for: test)
        do {
            // Unstructured tasks that the test starts do not get this
            // preference, so they keep the threads of Swift concurrency.
            try await withTaskExecutorPreference(SerialQueueExecutor(label: test.name)) {
                try await function()
            }
        } catch {
            await slots.leave(for: test)
            throw error
        }
        await slots.leave(for: test)
    }
}

extension Trait where Self == IsolatedThreadTrait {
    /// Runs each test on a thread of its own, with a limit on how many run
    /// at once.
    public static var isolatedThread: Self { IsolatedThreadTrait() }
}
