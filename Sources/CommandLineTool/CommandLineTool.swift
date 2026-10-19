import Foundation
import SessionProtocol
import TerminalEmulation

/// The `openrun` command: reads the arguments, runs one command, and returns
/// the exit code. Output goes to standard output, and every error goes to
/// standard error.
public enum CommandLineTool {
    /// - Returns: 0 when the command worked, 1 when it could not be done, and
    ///   2 when the arguments were wrong. After `attach`, the exit code of the
    ///   session's program, when it ended while attached.
    public static func run(arguments: [String], environment: [String: String]) -> Int32 {
        do {
            let parsed = try CommandLineArguments(arguments)
            if parsed.command == .help {
                write(UsageText.full + "\n", to: .standardOutput)
                return 0
            }
            let location = try resolveLocation(flag: parsed.socketPath, environment: environment)
            return try execute(parsed.command, location: location, environment: environment)
        } catch let error as CommandLineToolError {
            writeError(error)
            if case .usage = error { write(UsageText.hint + "\n", to: .standardError) }
            return error.exitCode
        } catch {
            writeError(error)
            return 1
        }
    }

    private static func execute(_ command: ToolCommand, location: SocketLocation, environment: [String: String]) throws -> Int32 {
        switch command {
        case .new(let folder, let program):
            write(try NewCommand(folder: folder, program: program).run(location: location, environment: environment), to: .standardOutput)
        case .list:
            write(try ListCommand().run(location: location), to: .standardOutput)
        case .attach(let identifier):
            return try AttachCommand(identifier: identifier).run(location: location)
        case .read(let identifier, let includeScrollback):
            write(try ReadCommand(identifier: identifier, includeScrollback: includeScrollback).run(location: location), to: .standardOutput)
        case .send(let identifier, let text, let pressEnter):
            try SendCommand(identifier: identifier, text: text, pressEnter: pressEnter).run(location: location)
        case .kill(let identifier):
            try KillCommand(identifier: identifier).run(location: location)
        case .help:
            break
        }
        return 0
    }

    private static func resolveLocation(flag: String?, environment: [String: String]) throws -> SocketLocation {
        do {
            return try SocketLocation.resolve(flag: flag, environment: environment)
        } catch {
            throw CommandLineToolError.failure("\(error)")
        }
    }

    /// An error message can hold text from a client, such as a program name
    /// or a failure from the session process. It must not drive the terminal
    /// of the caller, so every control character is escaped. The tool's own
    /// line breaks, between the lines of a list, are kept.
    private static func writeError(_ error: Error) {
        let text = (error as? CommandLineToolError)?.printableDescription ?? PrintableText.escaping("\(error)")
        write("openrun: \(text)\n", to: .standardError)
    }

    private static func write(_ text: String, to handle: FileHandle) {
        handle.write(Data(text.utf8))
    }
}
