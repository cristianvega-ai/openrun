import Foundation

/// One row of the second pane, as the host describes it.
public struct SessionRowDisplay: Equatable, Sendable {
    public var identifier: UUID
    /// The name that the user gave, or the title of the program.
    public var title: String
    /// The line under the title, such as `~/Projects/openrun · main`.
    public var detail: String
    public var kind: SessionKind
    /// The program works. A row that is not in progress has finished: an
    /// agent waits after its turn, or a terminal is idle.
    public var isInProgress: Bool
    /// The text of the alert while the row needs the user.
    public var alert: String?
    public var lastActivity: Date
    public var startTime: Date

    public init(identifier: UUID, title: String, detail: String, kind: SessionKind, isInProgress: Bool = false,
                alert: String? = nil, lastActivity: Date, startTime: Date) {
        (self.identifier, self.title, self.detail, self.kind) = (identifier, title, detail, kind)
        (self.isInProgress, self.alert, self.lastActivity, self.startTime) = (isInProgress, alert, lastActivity, startTime)
    }
}
