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
        .target(name: "SessionProtocol"),
        .testTarget(
            name: "SessionProtocolTests",
            dependencies: ["SessionProtocol"]
        ),
        .target(name: "PseudoTerminal"),
        .target(
            name: "SessionProcess",
            dependencies: ["TerminalEmulation", "PseudoTerminal", "SessionProtocol"]
        ),
        .executableTarget(
            name: "openrun-session",
            dependencies: ["SessionProcess"]
        ),
        .target(
            name: "CommandLineTool",
            dependencies: ["TerminalEmulation", "SessionProtocol"]
        ),
        .executableTarget(
            name: "openrun",
            dependencies: ["CommandLineTool"]
        ),
        .testTarget(
            name: "PseudoTerminalTests",
            dependencies: ["PseudoTerminal"]
        ),
        // Support code for the integration tests. It starts the real
        // executables.
        .target(
            name: "SessionProcessHarness",
            dependencies: ["PseudoTerminal", "TerminalEmulation", "openrun", "openrun-session"],
            path: "Tests/SessionProcessHarness"
        ),
        .testTarget(
            name: "SessionProcessTests",
            dependencies: ["SessionProcessHarness", "SessionProcess", "SessionProtocol", "TerminalEmulation"]
        ),
        .testTarget(
            name: "CommandLineToolTests",
            dependencies: ["SessionProcessHarness", "CommandLineTool", "PseudoTerminal"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
