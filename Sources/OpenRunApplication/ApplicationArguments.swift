import Foundation
import SessionProtocol

/// The socket that the app uses. A nondefault socket is for development and
/// has no launch agent.
struct ApplicationArguments {
    enum Failure: Error, CustomStringConvertible {
        case invalidArguments
        var description: String { "Use OpenRun [--socket PATH]." }
    }

    let socket: SocketLocation

    init(arguments: [String], environment: [String: String]) throws {
        var path: String?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("-psn_") { index += 1; continue }
            guard argument == "--socket", path == nil, index + 1 < arguments.count,
                  !arguments[index + 1].isEmpty, !arguments[index + 1].hasPrefix("--") else {
                throw Failure.invalidArguments
            }
            path = arguments[index + 1]
            index += 2
        }
        socket = try SocketLocation.resolve(flag: path, environment: environment)
    }
}
