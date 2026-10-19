import Testing
@testable import CommandLineTool

@Suite struct CommandLineArgumentsTests {

    @Test func usageErrorsExitWithTwoAndOperatingErrorsWithOne() {
        #expect(CommandLineToolError.usage("x").exitCode == 2)
        #expect(CommandLineToolError.failure("x").exitCode == 1)
    }
}
