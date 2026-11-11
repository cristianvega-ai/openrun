import Foundation
import PseudoTerminal

/// The environment of the user's login shell, which the session process
/// reads once and gives each agent that it starts (decision of
/// 2026-11-10). launchd gives the session process a short environment, and
/// the agents live in folders that the user's shell adds to `PATH`.
public enum LoginShellEnvironment {
    /// Variables of the shell itself, which make no sense in another program.
    static let shellVariables: Set<String> = ["_", "PWD", "OLDPWD", "SHLVL"]

    /// Runs the shell as an interactive login shell, as a terminal window
    /// would, and reads the environment that it ends with. A profile can
    /// print text or wait for input, so the environment comes between two
    /// markers, standard input is closed, and the shell gets `timeLimit`.
    ///
    /// - Returns: The environment, or nil when the shell fails, takes too
    ///   long, prints more than `byteLimit` bytes, or prints no markers. The
    ///   caller then uses its own environment.
    public static func read(
        shell: LoginShell = .current(), base: [String: String], folder: String,
        timeLimit: Duration = .seconds(10), byteLimit: Int = 1024 * 1024
    ) async -> [String: String]? {
        let marker = "OPENRUN-ENVIRONMENT-" + UUID().uuidString
        let command = "printf '%s' \(marker); /usr/bin/env -0; printf '%s' \(marker)"
        guard let program = try? AgentProgram(launching: AgentProgramLaunch(
            executablePath: shell.path, arguments: ["-l", "-i", "-c", command], folder: folder, environment: base))
        else { return nil }
        program.closeInput()
        let watchdog = Task {
            guard (try? await Task.sleep(for: timeLimit)) != nil else { return false }
            await program.terminate(gracePeriod: .milliseconds(200))
            return true
        }
        var output: [UInt8] = []
        for await chunk in program.output {
            output += chunk
            program.markOutputConsumed(chunk.count)
            if output.count > byteLimit {
                await program.terminate(gracePeriod: .milliseconds(200))
                break
            }
        }
        _ = await program.waitForExit()
        watchdog.cancel()
        guard await !watchdog.value, output.count <= byteLimit else { return nil }
        return parse(String(decoding: output, as: UTF8.self), marker: marker)
    }

    /// The variables between the two markers. Each entry ends with NUL and
    /// is `NAME=value`. A value can hold a line end, so NUL splits them.
    static func parse(_ text: String, marker: String) -> [String: String]? {
        guard let start = text.range(of: marker), let end = text.range(of: marker, options: .backwards),
              start.upperBound <= end.lowerBound
        else { return nil }
        var environment: [String: String] = [:]
        for entry in text[start.upperBound..<end.lowerBound].split(separator: "\u{0}") {
            guard let equals = entry.firstIndex(of: "="), equals != entry.startIndex else { continue }
            let name = String(entry[..<equals])
            if shellVariables.contains(name) { continue }
            environment[name] = String(entry[entry.index(after: equals)...])
        }
        return environment.isEmpty ? nil : environment
    }
}
