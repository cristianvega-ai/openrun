import Darwin
import Foundation

/// The folder `Contents/Helpers` of the app bundle that holds the session
/// process. It goes first on the `PATH` of each new session, so agents find
/// `openrun` with no setup.
///
/// The folder holds only `openrun`, so it hides no other program. Until
/// milestone 5, the session process and `openrun` come from one build, and
/// this `openrun` is the one that matches.
struct HelperSearchPath: Sendable {
    /// Nil when the process does not run from an app bundle, such as a
    /// program of `swift build`.
    let folder: String?

    /// The search path of `ProgramLaunch` for an environment without one.
    static let systemSearchPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    /// The process reads its own path at its start, because a new build
    /// can replace the bundle while the process runs.
    static func ofThisProcess() -> HelperSearchPath {
        HelperSearchPath(executablePath: ApplicationBundle.executablePathOfThisProcess())
    }

    init(executablePath: String?) {
        folder = executablePath.flatMap(Self.helperFolder(forExecutableAt:))
    }

    /// `NAME.app/Contents/MacOS/PROGRAM` gives `NAME.app/Contents/Helpers`.
    static func helperFolder(forExecutableAt path: String) -> String? {
        ApplicationBundle.path(holdingExecutableAt: path).map { $0 + "/Contents/Helpers" }
    }

    /// The environment of a new session, with the folder first on its
    /// `PATH`. A `PATH` that holds the folder already, as in a session that
    /// a session started, stays as it is.
    func adding(to environment: [String: String]) -> [String: String] {
        guard let folder else { return environment }
        let searchPath = environment["PATH"] ?? Self.systemSearchPath
        guard !searchPath.split(separator: ":").contains(Substring(folder)) else { return environment }
        var changed = environment
        changed["PATH"] = searchPath.isEmpty ? folder : folder + ":" + searchPath
        return changed
    }
}
