import Foundation
import SessionConnection
import SessionProcessHarness
import SessionProtocol
import Testing
@testable import SessionOverview

/// The result of a request, which arrives on the main thread.
@MainActor final class RequestResult<Value: Sendable> {
    var result: Result<Value, SessionRequestFailure>?

    /// Sends the request and waits for its result.
    func of(_ requests: SessionRequests, _ request: @escaping @Sendable (SessionClient) throws -> Value) async -> Result<Value, SessionRequestFailure>? {
        result = nil
        requests.perform(request) { self.result = $0 }
        _ = await waitUntil { self.result != nil }
        return result
    }
}

@MainActor @Suite(.serialized) struct SessionRequestsTests {
    @Test func requestsGiveTheirAnswersAndARefusalKeepsTheConnection() async throws {
        let process = try RunningSessionProcess()
        defer { process.stop() }
        let requests = SessionRequests(socket: try SocketLocation(path: process.socketPath))
        let added = await RequestResult<ProjectSummary>().of(requests) { try $0.addProject(folder: process.directory.path, name: "Work", currentFolder: nil) }
        #expect(try added?.get().name == "Work")
        let refused = await RequestResult<Bool>().of(requests) { try $0.rename(session: UUID(), to: "x"); return true }
        guard case .failure(let failure) = refused else { Issue.record("No refusal"); return }
        #expect(failure.wasRefused && failure.message.contains("No session"))
        let listed = await RequestResult<[ProjectSummary]>().of(requests) { try $0.projects() }
        #expect(try listed?.get().map(\.name) == ["Work"])
    }

    @Test func aRequestAfterARestartOfTheSessionProcessGoesToTheNewOne() async throws {
        let folder = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try RunningSessionProcess(directory: folder)
        let requests = SessionRequests(socket: try SocketLocation(path: first.socketPath))
        #expect(try await RequestResult<[SessionSummary]>().of(requests) { try $0.summaries() }?.get().isEmpty == true)
        first.stop()
        let missing = await RequestResult<[SessionSummary]>().of(requests) { try $0.summaries() }
        guard case .failure(let failure) = missing else { Issue.record("No failure"); return }
        #expect(!failure.wasRefused)
        let second = try RunningSessionProcess(directory: folder, logName: "log2")
        defer { second.stop() }
        _ = try second.createSession(program: ["/bin/sh"])
        #expect(try await RequestResult<[SessionSummary]>().of(requests) { try $0.summaries() }?.get().count == 1)
    }
}
