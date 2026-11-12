import Foundation
import SessionConnection
import SessionProcessHarness
import SessionProtocol
import Testing
@testable import SessionProcess

@Suite struct BuildIdentifierTests {
    @Test func theProgramHasTheIdentifierOfItsBuild() throws {
        let identifier = try #require(BuildIdentifier.current)
        #expect(UUID(uuidString: identifier) != nil && identifier == identifier.lowercased() && BuildIdentifier.current == identifier)
    }

    @Test func theSessionProcessTellsItsBuildToAClientAndOnItsCommandLine() async throws {
        // The program prints the identifier and ends, so the app can read the build in its own bundle.
        let printed = Process(), output = Pipe()
        (printed.executableURL, printed.arguments, printed.standardOutput) = (RunningSessionProcess.sessionExecutable, ["--build-identifier"], output)
        try printed.run()
        printed.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .newlines)
        #expect(printed.terminationStatus == 0 && UUID(uuidString: text) != nil)
        // A process of the same build tells the same identifier in its hello.
        try await RunningSessionProcess.run { process in
            let client = try SessionClient(location: SocketLocation(path: process.socketPath))
            #expect(client.capabilities.build == text)
        }
        // An older session process tells none.
        let older = try JSONDecoder().decode(ServerCapabilities.self, from: Data(#"{"threads":true}"#.utf8))
        #expect(older.build == nil && older.threads)
    }
}
