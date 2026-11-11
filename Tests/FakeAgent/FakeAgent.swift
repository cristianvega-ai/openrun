import Foundation

/// A stand-in for `claude -p`, so that no test runs the real agent and
/// spends the owner's subscription.
struct FakeAgent {
    let environment: [String: String]

    func run(arguments: [String]) -> Int32 {
        guard FakeAgentArguments(arguments) != nil else {
            return fail("the arguments are not the ones that OpenRun gives", status: 64)
        }
        // Claude Code treats a process with this variable as a run inside
        // another run.
        guard environment["CLAUDECODE"] == nil else { return fail("the environment marks a nested run", status: 64) }
        return 0
    }

    func fail(_ problem: String, status: Int32 = 1) -> Int32 {
        try? FileHandle.standardError.write(contentsOf: Data("\(problem)\n".utf8))
        return status
    }
}
