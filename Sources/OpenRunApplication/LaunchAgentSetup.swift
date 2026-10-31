import SessionLaunch

/// What the app does with the launch agent at its start.
///
/// It registers the agent when it is not registered, and then connects
/// once, which sends a wake when nothing listens. When the user must act,
/// it asks once and stops, so it never registers again in a loop.
struct LaunchAgentSetup {
    enum Outcome: Equatable, Sendable {
        case ready, waitingForApproval, failed
    }

    let source: any LaunchAgentStatusSource
    /// Connects to the session process, with a wake when nothing listens.
    let connect: () throws -> Void
    /// Shows a question to the user, and returns whether the user agreed.
    let ask: (LaunchAgentQuestion) -> Bool

    func run() -> Outcome {
        switch source.status {
        case .requiresApproval:
            return waitForApproval()
        case .notRegistered, .notFound:
            do {
                try source.register()
            } catch {
                return fail("\(error)")
            }
            if source.status == .requiresApproval { return waitForApproval() }
        case .enabled:
            break
        }
        do {
            try connect()
            return .ready
        } catch let failure as SessionWakeFailure {
            if case .timedOut(let limit) = failure {
                return fail("The OpenRun session process did not answer within \(limit.components.seconds) seconds.")
            }
            if case .notRegistered = failure {
                return fail("launchd could not find the OpenRun session process.")
            }
            return fail(failure.description)
        } catch {
            return fail(String(describing: error))
        }
    }

    private func waitForApproval() -> Outcome {
        if ask(.approvalNeeded) { source.openSystemSettings() }
        return .waitingForApproval
    }

    private func fail(_ detail: String) -> Outcome {
        _ = ask(.failed(detail: detail))
        return .failed
    }
}
