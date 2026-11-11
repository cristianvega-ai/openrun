import Foundation
import SessionConnection
import SessionProtocol
import UntrustedText

/// The `openrun` command: reads the arguments, runs one command, and returns
/// the exit code. Output goes to standard output, and every error goes to
/// standard error.
public enum CommandLineTool {
    /// - Returns: 0 when the command worked, 1 when it could not be done, and
    ///   2 when the arguments were wrong. After `attach`, the exit code of the
    ///   session's program, when it ended while attached. `notify` never
    ///   exits with 2, because a hook of Claude Code then blocks the action.
    public static func run(arguments: [String], environment: [String: String]) -> Int32 {
        do {
            let parsed = try CommandLineArguments(arguments)
            if parsed.command == .help {
                write(UsageText.full + "\n", to: .standardOutput)
                return 0
            }
            if case .notify(let identifier, let text) = parsed.command {
                try NotifyCommand(identifier: identifier, text: text).run(socketFlag: parsed.socketPath, environment: environment)
                return 0
            }
            let location = try resolveLocation(flag: parsed.socketPath, environment: environment)
            return try execute(parsed.command, location: location, environment: environment)
        } catch let error as CommandLineToolError {
            return exitCode(report(error), arguments: arguments)
        } catch let error as SessionConnectionError {
            return exitCode(report(CommandLineToolError(error)), arguments: arguments)
        } catch {
            writeError(error)
            return 1
        }
    }

    private static func exitCode(_ code: Int32, arguments: [String]) -> Int32 {
        code == 2 && CommandLineArguments.namesNotify(arguments) ? 1 : code
    }

    private static func report(_ error: CommandLineToolError) -> Int32 {
        writeError(error)
        if case .usage = error { write(UsageText.hint + "\n", to: .standardError) }
        return error.exitCode
    }

    private static func execute(_ command: ToolCommand, location: SocketLocation, environment: [String: String]) throws -> Int32 {
        switch command {
        case .new(let folder, let program):
            write(try NewCommand(folder: folder, program: program).run(location: location, environment: environment), to: .standardOutput)
        case .list(let printsJSON):
            write(try ListCommand(printsJSON: printsJSON).run(location: location), to: .standardOutput)
        case .attach(let identifier):
            return try AttachCommand(identifier: identifier).run(location: location)
        case .read(let identifier, let includeScrollback):
            write(try ReadCommand(identifier: identifier, includeScrollback: includeScrollback).run(location: location), to: .standardOutput)
        case .send(let identifier, let text, let pressEnter):
            try SendCommand(identifier: identifier, text: text, pressEnter: pressEnter).run(location: location)
        case .kill(let identifier):
            try KillCommand(identifier: identifier).run(location: location)
        case .rename(let identifier, let name):
            try RenameCommand(identifier: identifier, name: name).run(location: location)
        case .projectList(let printsJSON):
            write(try ProjectListCommand(printsJSON: printsJSON).run(location: location), to: .standardOutput)
        case .notify, .help:
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
        let text = (error as? CommandLineToolError)?.printableDescription ?? PrintableText.escapingControlCharacters(in: "\(error)")
        write("openrun: \(text)\n", to: .standardError)
    }

    private static func write(_ text: String, to handle: FileHandle) {
        handle.write(Data(text.utf8))
    }
}
