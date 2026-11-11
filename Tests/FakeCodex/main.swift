import Foundation

exit(FakeCodex(environment: ProcessInfo.processInfo.environment).run(arguments: Array(CommandLine.arguments.dropFirst())))
