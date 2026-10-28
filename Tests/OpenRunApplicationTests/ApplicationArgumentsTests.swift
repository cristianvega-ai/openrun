import SessionProtocol
import Testing
@testable import OpenRunApplication

@Suite struct ApplicationArgumentsTests {
    @Test func theFlagOverridesTheEnvironmentAndTheDefault() throws {
        let arguments = try ApplicationArguments(arguments: ["--socket", "/tmp/openrun-test.socket"],
                                                 environment: ["OPENRUN_SOCKET": "/tmp/other.socket"])
        #expect(arguments.socket.path == "/tmp/openrun-test.socket" && !arguments.socket.isDefault)
        #expect(try ApplicationArguments(arguments: [], environment: [:]).socket.isDefault)
        #expect(try ApplicationArguments(arguments: [], environment: ["OPENRUN_SOCKET": "/tmp/other.socket"]).socket.path == "/tmp/other.socket")
        #expect(try ApplicationArguments(arguments: ["-psn_0_1", "--socket", "/tmp/openrun-test.socket"], environment: [:]).socket == arguments.socket)
    }

    @Test(arguments: [["--socket"], ["--socket", ""], ["--other"], ["--socket", "/a", "--socket", "/b"]])
    func invalidArgumentsAreRejected(arguments: [String]) {
        #expect(throws: ApplicationArguments.Failure.self) { try ApplicationArguments(arguments: arguments, environment: [:]) }
    }
}
