import ClaudeCodeAgent
import Foundation
import SessionConnection
import SessionProtocol

/// `openrun permission-request`: the `PermissionRequest` hook of Claude
/// Code in a thread (decision of 2026-11-10). It only asks: it gives the
/// request to the session process and waits for the end of the request.
/// It has no way to allow a call by itself.
enum PermissionRequestCommand {
    /// What the agent reads when the hook could not ask. It names no path
    /// and no error, because the agent shows it to the model.
    static let failureMessage = "OpenRun could not ask the user, so the call does not run."

    /// - Parameter request: What the agent gave the hook on its standard input.
    /// - Returns: What the hook writes on its standard output. Any failure
    ///   gives a denial, because only the user can allow a call.
    static func answer(to request: Data, environment: [String: String]) -> Data {
        do {
            // The session process gave the agent the socket in `OPENRUN_SOCKET`.
            let location = try SocketLocation.resolve(flag: nil, environment: environment)
            let answer = try SessionClient(location: location).requestToolPermission(request)
            return (answer.allows ? ClaudeCodePermissionHookAnswer.allow : .deny(message: answer.message ?? failureMessage)).output
        } catch {
            return ClaudeCodePermissionHookAnswer.deny(message: failureMessage).output
        }
    }
}
