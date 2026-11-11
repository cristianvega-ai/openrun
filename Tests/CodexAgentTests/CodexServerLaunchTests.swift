import Testing
@testable import CodexAgent

@Suite struct CodexServerLaunchTests {
    @Test func theAccountFolderBecomesCodexHome() {
        let launch = CodexServerLaunch(accountFolder: "/config/second", environment: ["PATH": "/bin", "CODEX_HOME": "/config/codex"])
        #expect(launch.programLaunch.arguments == ["app-server"])
        #expect(launch.programLaunch.executablePath == "codex")
        #expect(launch.programLaunch.environment == ["PATH": "/bin", "CODEX_HOME": "/config/second"])
    }

    @Test func theDefaultAccountKeepsTheEnvironment() {
        let launch = CodexServerLaunch(environment: ["CODEX_HOME": "/config/codex"])
        #expect(launch.programLaunch.environment == ["CODEX_HOME": "/config/codex"])
    }
}
