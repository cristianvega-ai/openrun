import Foundation

/// Where the program that sent a request runs, for the rule that asks the
/// user first before one session types into or reads another (decisions of
/// 2026-10-15 and 2026-11-10).
enum CallerPlace: Equatable, Sendable {
    /// In no session of this process, such as Terminal, ssh, or the app.
    /// A program that left the terminal session of its session, for example
    /// with `setsid`, is here too.
    case outsideEverySession
    /// In the session with this identifier.
    case session(UUID)
    /// The program ended before the session process could find its terminal
    /// session, or its session has ended. It may have run in any session, so
    /// it counts as another one.
    case unknown

    /// Whether the caller may act on the target session without a question.
    func mayAct(on target: UUID) -> Bool {
        switch self {
        case .outsideEverySession: true
        case .session(let own): own == target
        case .unknown: false
        }
    }
}
