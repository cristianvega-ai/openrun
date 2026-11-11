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
        .testTarget(name: "TerminalViewTests", dependencies: ["TerminalView", "TerminalRendering", "TerminalTheme", "TerminalEmulation"]),
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
        // How launchd starts the session process when a client needs it:
        // the names of the launch agent, its wake service, and the wake.
        .target(name: "SessionLaunch"),
        .testTarget(name: "SessionLaunchTests", dependencies: ["SessionLaunch"]),
        .target(
            name: "SessionProcess",
            dependencies: ["TerminalEmulation", "TerminalTheme", "PseudoTerminal", "SessionProtocol", "SessionLaunch"]
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
        // One window for one session: the attach, the size rules, the title and the questions.
        .target(name: "SessionWindow", dependencies: ["TerminalView", "TerminalEmulation", "SessionConnection", "SessionProtocol"]),
        .testTarget(name: "SessionWindowTests", dependencies: ["SessionWindow", "TerminalView", "TerminalRendering", "SessionConnection", "SessionProtocol", "TerminalEmulation", "SessionProcessHarness"]),
        // The app. In milestone 2 it registers the launch agent at its start.
        .target(name: "OpenRunApplication", dependencies: ["SessionLaunch", "SessionConnection", "SessionProtocol", "SessionWindow"]),
        .testTarget(name: "OpenRunApplicationTests", dependencies: ["OpenRunApplication", "SessionLaunch", "SessionProtocol", "SessionWindow", "SessionProcessHarness", "TerminalView"]),
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
