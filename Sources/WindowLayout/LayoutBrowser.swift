import Foundation

/// A web page in a split of a row. The browser opens as one of the
/// splits of the third pane (decision of 2026-10-15).
public struct LayoutBrowser: Codable, Equatable, Sendable {
    public var identifier: UUID
    /// The address of the page, which comes back with the row.
    public var address: String

    public init(identifier: UUID = UUID(), address: String) {
        (self.identifier, self.address) = (identifier, address)
    }
}
