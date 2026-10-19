import Foundation
import SessionProcess

// The executable only reads its start-up input. SessionProcess does the work.
exit(await SessionProcess.runFromCommandLine(
    arguments: Array(CommandLine.arguments.dropFirst()),
    environment: ProcessInfo.processInfo.environment
))
