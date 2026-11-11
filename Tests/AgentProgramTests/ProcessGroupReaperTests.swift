import Darwin
import Dispatch
import Foundation
import PseudoTerminal
import Testing
@testable import AgentProgram

@Suite struct ProcessGroupReaperTests {
    /// Starts `script` with `sh` on pipes, and reaps it with a reaper.
    func run(_ script: String) async throws -> (exit: ProgramExit, output: String) {
        let launch = AgentProgramLaunch(executablePath: "/bin/sh", arguments: ["-c", script], folder: "/", environment: ["PATH": "/usr/bin:/bin"])
        let started = try PipeSpawn.start(launch)
        close(started.inputDescriptor)
        defer { close(started.outputDescriptor); close(started.errorDescriptor) }
        let queue = DispatchQueue(label: "ProcessGroupReaperTests")
        let exit = await withCheckedContinuation { (continuation: CheckedContinuation<ProgramExit, Never>) in
            queue.async {
                let reaper = ProcessGroupReaper(processIdentifier: started.processIdentifier, queue: queue) { continuation.resume(returning: $0) }
                reaper.start()
            }
        }
        // The program was reaped: no zombie is left.
        #expect(waitpid(started.processIdentifier, nil, WNOHANG) == -1)
        var buffer = [UInt8](repeating: 0, count: 1_024)
        let count = read(started.outputDescriptor, &buffer, buffer.count)
        return (exit, String(decoding: buffer.prefix(max(0, count)), as: UTF8.self))
    }

    @Test func theStatusAndTheSignalOfTheEndCome() async throws {
        #expect(try await run("exit 3").exit == .exited(status: 3))
        #expect(try await run("kill -USR1 $$").exit == .signaled(signal: SIGUSR1))
    }

    @Test func theRestOfTheGroupEndsBeforeTheReap() async throws {
        let (exit, output) = try await run("sleep 300 & echo $!")
        #expect(exit == .exited(status: 0))
        let child = try #require(pid_t(output.trimmingCharacters(in: .newlines)))
        #expect(!ProcessGroupReaper.groupHasLiveMembers(child))
        #expect(kill(child, 0) == -1 || ProcessGroupReaperTests.isZombie(child))
    }

    @Test func aMemberThatIgnoresSIGTERMGetsSIGKILL() async throws {
        let start = ContinuousClock.now
        // The pause lets the inner shell set its trap before the end.
        let (_, output) = try await run("sh -c 'trap \"\" TERM; while :; do sleep 1; done' & sleep 0.3; echo $!")
        let child = try #require(pid_t(output.trimmingCharacters(in: .newlines)))
        #expect(kill(child, 0) == -1 || ProcessGroupReaperTests.isZombie(child))
        #expect(ContinuousClock.now - start > .seconds(1))
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    static func isZombie(_ processIdentifier: pid_t) -> Bool {
        var information = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(processIdentifier, PROC_PIDTBSDINFO, 0, &information, size) != size || information.pbi_status == UInt32(SZOMB)
    }
}
