import Foundation

exit(FakeAgent(environment: ProcessInfo.processInfo.environment).run(arguments: Array(CommandLine.arguments.dropFirst())))
