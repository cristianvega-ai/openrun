import SessionLaunch

/// What the app does with the launch agent at its start.
///
/// It registers the agent when it is not registered, and then connects
/// once, which sends a wake when nothing listens. When the user must act,
/// it asks once and stops, so it never registers again in a loop.
struct LaunchAgentSetup {
    enum Outcome: Equatable {
        case ready, waitingForApproval, declined, failed
    }

    let source: any LaunchAgentStatusSource
    /// Connects to the session process, with a wake when nothing listens.
    let connect: () throws(SessionWakeFailure) -> Void
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
        } catch .timedOut where source.status == .enabled {
            return registerAgainWhenTheUserAgrees()
        } catch {
            return fail(error.description)
        }
    }

    /// A wake without an answer while the agent is enabled means that
    /// launchd refuses the program, as after a build that changed its code
    /// signature. A new registration ends every session of the old build,
    /// so the user decides. The app registers again one time only.
    private func registerAgainWhenTheUserAgrees() -> Outcome {
        guard ask(.registerAgain) else { return .declined }
        do {
            try source.unregister()
            try source.register()
        } catch {
            return fail("\(error)")
        }
        do {
            try connect()
            return .ready
        } catch {
            return fail(error.description)
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
