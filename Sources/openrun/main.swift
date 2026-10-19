import CommandLineTool
import Foundation

// The executable only reads its start-up input. CommandLineTool does the work.
exit(CommandLineTool.run(
    arguments: Array(CommandLine.arguments.dropFirst()),
    environment: ProcessInfo.processInfo.environment
))
