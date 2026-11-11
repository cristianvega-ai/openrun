import Foundation

/// A small app bundle with an ad hoc signature, as an OpenRun.app that was
/// built with no identity. `codesign --sign -` needs no certificate.
public enum AdHocBundle {
    /// Makes `NAME.app` in `folder`: `mainProgram` as its main program
    /// `Contents/MacOS/OpenRun`, and `openrun-session` beside it. Signs the
    /// session process, then the bundle, from the inside out.
    public static func make(named name: String, in folder: URL, mainProgram: URL) throws -> URL {
        let bundle = folder.appendingPathComponent(name + ".app", isDirectory: true)
        let programs = bundle.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: programs, withIntermediateDirectories: true)
        let information: [String: String] = [
            "CFBundleExecutable": "OpenRun", "CFBundleIdentifier": "ai.cristianvega.openrun.test", "CFBundlePackageType": "APPL",
        ]
        try PropertyListSerialization.data(fromPropertyList: information, format: .xml, options: 0)
            .write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        try FileManager.default.copyItem(at: mainProgram, to: programs.appendingPathComponent("OpenRun"))
        try FileManager.default.copyItem(at: RunningSessionProcess.sessionExecutable, to: programs.appendingPathComponent("openrun-session"))
        _ = try codesign(["--force", "--sign", "-", programs.appendingPathComponent("openrun-session").path])
        _ = try codesign(["--force", "--sign", "-", bundle.path])
        return bundle
    }

    /// The code hash of the main program of the bundle, as `codesign`
    /// reports it, in lower case.
    public static func codeHash(of bundle: URL) throws -> String {
        let report = try codesign(["--display", "--verbose=3", bundle.path])
        guard let line = report.split(separator: "\n").first(where: { $0.hasPrefix("CDHash=") }) else {
            throw HarnessError.commandFailed(description: "codesign reported no code hash: \(report)")
        }
        return line.dropFirst("CDHash=".count).lowercased()
    }

    /// Runs `codesign` and returns what it wrote. It writes its report to
    /// standard error.
    private static func codesign(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw HarnessError.commandFailed(description: "codesign \(arguments.joined(separator: " ")) failed: \(output)")
        }
        return output
    }
}
