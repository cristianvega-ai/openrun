// swift-tools-version: 6.2
import PackageDescription

// To add a feature: add a target and a test target below, then list the
// target in `products` when another executable needs it. A feature depends
// only on the features it uses through their public types.
let package = Package(
    name: "OpenRun",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "TerminalEmulation", targets: ["TerminalEmulation"]),
        .executable(name: "openrun", targets: ["openrun"]),
        .executable(name: "openrun-session", targets: ["openrun-session"]),
        // The bundle script installs it as Contents/MacOS/OpenRun.
        .executable(name: "openrun-application", targets: ["openrun-application"]),
    ],
    targets: [
        // Built by scripts/build-ghostty-library.sh. Only TerminalEmulation
        // may depend on it.
        .binaryTarget(
            name: "LibraryGhosttyVirtualTerminal",
            path: "Libraries/ghostty-vt.xcframework"
        ),
        .target(
            name: "TerminalEmulation",
            dependencies: ["LibraryGhosttyVirtualTerminal"]
        ),
        .testTarget(
            name: "TerminalEmulationTests",
            dependencies: ["TerminalEmulation"]
        ),
        .target(name: "TerminalTheme", dependencies: ["TerminalEmulation"]),
        .testTarget(name: "TerminalThemeTests", dependencies: ["TerminalTheme", "TerminalEmulation"]),
        .target(name: "TerminalRendering", dependencies: ["TerminalEmulation"]),
        .testTarget(name: "TerminalRenderingTests", dependencies: ["TerminalRendering", "TerminalTheme", "TerminalEmulation"]),
        .target(name: "TerminalView", dependencies: ["TerminalRendering", "TerminalTheme", "TerminalEmulation"]),
        // Support code for the tests that need a drawn frame on a real screen.
        .target(name: "LiveDisplay", path: "Tests/LiveDisplay"),
        .testTarget(name: "TerminalViewTests", dependencies: ["TerminalView", "TerminalRendering", "TerminalTheme", "TerminalEmulation", "LiveDisplay"]),
        // Text from a client or a file that OpenRun shows: the check of a
        // name and the escape of text in a message.
        .target(name: "UntrustedText"),
        .testTarget(name: "UntrustedTextTests", dependencies: ["UntrustedText"]),
        // Where OpenRun keeps its data as readable JSON, and the safe write
        // and read of each file.
        .target(name: "DataStorage", dependencies: ["UntrustedText"]),
        .testTarget(name: "DataStorageTests", dependencies: ["DataStorage", "SessionProtocol"]),
        // The folders that the user adds as projects, and the project of a session.
        .target(name: "Projects", dependencies: ["DataStorage", "UntrustedText"]),
        .testTarget(name: "ProjectsTests", dependencies: ["Projects", "DataStorage"]),
        // The typed settings, their text forms for the tool, and the rule
        // for protected settings.
        .target(name: "Settings", dependencies: ["DataStorage", "UntrustedText"]),
        .testTarget(name: "SettingsTests", dependencies: ["Settings", "DataStorage"]),
        // The model of an agent thread: its events, the transcript that a
        // chat shows, and the state of the thread. It uses no AppKit, so the
        // Linux app can use it too (proposal 13 of 2026-11-10).
        .target(name: "AgentConversation"),
        .testTarget(name: "AgentConversationTests", dependencies: ["AgentConversation"]),
        // Claude Code in a thread: its command line, the user message line,
        // the decoder of its output, its permission hook, and its history.
        .target(name: "ClaudeCodeAgent", dependencies: ["AgentConversation"]),
        .testTarget(name: "ClaudeCodeAgentTests", dependencies: ["ClaudeCodeAgent", "AgentConversation"], exclude: ["Fixtures"]),
        // An agent program on pipes, such as `claude -p`, with its process
        // group, and the environment of the user's login shell.
        .target(name: "AgentProgram", dependencies: ["PseudoTerminal"]),
        // Starts a program on pipes after it closed a standard descriptor.
        .executableTarget(name: "agent-program-probe", dependencies: ["AgentProgram"], path: "Tests/AgentProgramProbe"),
        .testTarget(name: "AgentProgramTests", dependencies: ["AgentProgram", "PseudoTerminal", "agent-program-probe"]),
        // A stand-in for `claude -p` that plays recorded turns, so that no
        // test runs the real agent.
        .executableTarget(name: "fake-agent", path: "Tests/FakeAgent"),
        .testTarget(name: "FakeAgentTests", dependencies: ["fake-agent", "AgentProgram", "ClaudeCodeAgent", "AgentConversation"]),
        .target(name: "SessionProtocol"),
        .testTarget(
            name: "SessionProtocolTests",
            dependencies: ["SessionProtocol"]
        ),
        .target(name: "SessionConnection", dependencies: ["SessionProtocol", "SessionLaunch"]),
        .testTarget(name: "SessionConnectionTests", dependencies: ["SessionConnection", "SessionProtocol", "SessionLaunch"]),
        .target(name: "PseudoTerminal"),
        // The git branch of a folder, read from the files of its repository.
        .target(name: "GitBranch"),
        .testTarget(name: "GitBranchTests", dependencies: ["GitBranch"]),
        // How launchd starts the session process when a client needs it:
        // the names of the launch agent, its wake service, and the wake.
        .target(name: "SessionLaunch"),
        .testTarget(name: "SessionLaunchTests", dependencies: ["SessionLaunch"]),
        .target(
            name: "SessionProcess",
            dependencies: ["TerminalEmulation", "TerminalTheme", "PseudoTerminal", "SessionProtocol", "SessionLaunch", "GitBranch"]
        ),
        .executableTarget(
            name: "openrun-session",
            dependencies: ["SessionProcess"]
        ),
        .target(
            name: "CommandLineTool",
            dependencies: ["SessionConnection", "TerminalEmulation", "SessionProtocol"]
        ),
        .executableTarget(
            name: "openrun",
            dependencies: ["CommandLineTool"]
        ),
        // One session in a view that any window can hold: the attach, the size rules, the title and the questions.
        .target(name: "SessionPane", dependencies: ["TerminalView", "TerminalEmulation", "SessionConnection", "SessionProtocol"]),
        .testTarget(name: "SessionPaneTests", dependencies: ["SessionPane", "TerminalView", "SessionConnection", "SessionProtocol", "TerminalEmulation", "SessionProcessHarness"]),
        // The in-place changes between two versions of a list, for the tables of the panes.
        .target(name: "ListUpdates"),
        .testTarget(name: "ListUpdatesTests", dependencies: ["ListUpdates"]),
        // How the panes of the main window look: the theme colors in AppKit, the top row, the selected row.
        .target(name: "PaneAppearance", dependencies: ["TerminalTheme", "TerminalEmulation"]),
        .testTarget(name: "PaneAppearanceTests", dependencies: ["PaneAppearance", "TerminalTheme", "TerminalEmulation"]),
        // One window for one session pane, and the picker of running sessions.
        .target(name: "SessionWindow", dependencies: ["SessionPane", "TerminalView", "TerminalEmulation", "SessionConnection", "SessionProtocol"]),
        .testTarget(name: "SessionWindowTests", dependencies: ["SessionWindow", "SessionPane", "TerminalView", "TerminalRendering", "SessionConnection", "SessionProtocol", "TerminalEmulation", "SessionProcessHarness", "LiveDisplay"]),
        // The app. In milestone 2 it registers the launch agent at its start.
        .target(name: "OpenRunApplication", dependencies: ["SessionLaunch", "SessionConnection", "SessionProtocol", "SessionPane", "SessionWindow"]),
        .testTarget(name: "OpenRunApplicationTests", dependencies: ["OpenRunApplication", "SessionLaunch", "SessionProtocol", "SessionPane", "SessionWindow", "SessionProcessHarness", "TerminalView"]),
        .executableTarget(name: "openrun-application", dependencies: ["OpenRunApplication"]),
        .testTarget(
            name: "PseudoTerminalTests",
            dependencies: ["PseudoTerminal"]
        ),
        // Support code for the integration tests. It starts the real
        // executables and plays the part of a terminal window.
        .target(
            name: "SessionProcessHarness",
            dependencies: ["PseudoTerminal", "TerminalEmulation", "openrun", "openrun-session"],
            path: "Tests/SessionProcessHarness"
        ),
        .testTarget(
            name: "SessionProcessTests",
            dependencies: ["SessionProcessHarness", "SessionProcess", "SessionProtocol", "SessionLaunch", "TerminalEmulation"]
        ),
        .testTarget(
            name: "CommandLineToolTests",
            dependencies: ["SessionProcessHarness", "CommandLineTool", "SessionConnection", "PseudoTerminal"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
