import AgentProgram
import Foundation
import Testing

/// The three pipes work whatever descriptors the parent has open. The
/// probe closes one of 0, 1 and 2 in a process of its own, and then starts
/// a program on pipes.
@Suite struct AgentProgramDescriptorTests {
    /// The folder of the test bundle also holds the executables that the
    /// tests depend on.
    static let probe: String = {
        let bundle = Bundle.allBundles.first { $0.bundleURL.pathExtension == "xctest" }
        let bundlePath = bundle?.bundleURL.path ?? CommandLine.arguments.lazy.compactMap { argument in
            argument.range(of: ".xctest").map { String(argument[..<$0.upperBound]) }
        }.first
        let folder = bundlePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() } ?? Bundle.main.bundleURL.deletingLastPathComponent()
        return folder.appending(path: "agent-program-probe").path
    }()

    @Test(arguments: [0, 1, 2])
    func thePipesWorkWhenTheParentHasADescriptorClosed(descriptor: Int) async throws {
        let program = try AgentProgram(launching: AgentProgramLaunch(
            executablePath: Self.probe, arguments: ["\(descriptor)"], folder: "/", environment: [:]))
        program.closeInput()
        for await chunk in program.output { program.markOutputConsumed(chunk.count) }
        #expect(await program.waitForExit() == .exited(status: 0))
    }
}
