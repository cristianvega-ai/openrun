import Testing
@testable import AgentProgram

@Suite struct LoginShellEnvironmentTests {
    @Test func parseKeepsOnlyNamedEntriesBetweenTheMarkers() {
        #expect(LoginShellEnvironment.parse("noise MA=1\u{0}=x\u{0}junk\u{0}B=a=b\u{0}M tail", marker: "M") == ["A": "1", "B": "a=b"])
        #expect(LoginShellEnvironment.parse("M only one", marker: "M") == nil)
        #expect(LoginShellEnvironment.parse("nothing", marker: "M") == nil)
    }
}
