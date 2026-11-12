import Foundation

/// The session process in the bundle of this app, which the launch agent
/// starts.
enum BundledSessionProcess {
    /// The identifier of the build of that program, which the program
    /// prints. `nil` outside an app bundle, as in a test, or when the
    /// program does not answer.
    static func buildIdentifier() -> String? {
        guard Bundle.main.bundleURL.pathExtension == "app",
              let program = Bundle.main.url(forAuxiliaryExecutable: "openrun-session") else { return nil }
        let (process, output) = (Process(), Pipe())
        (process.executableURL, process.arguments) = (program, ["--build-identifier"])
        (process.standardOutput, process.standardError, process.standardInput) = (output, FileHandle.nullDevice, FileHandle.nullDevice)
        guard (try? process.run()) != nil else { return nil }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        let identifier = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return process.terminationStatus == 0 && !identifier.isEmpty ? identifier : nil
    }
}
