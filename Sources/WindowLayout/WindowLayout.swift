import DataStorage
import Foundation

/// What the main window keeps between two runs of the app, in
/// `layout.json` of the data folder (decision of 2026-11-10): the rows of
/// the sessions list in the user's order, the selected entry and row, and
/// the filter and the order of the list.
public struct WindowLayout: DataDocument, Equatable {
    public static let file = DataFile.layout
    public static let format = 1
    public static let knownKeys: Set<String> = ["rows", "selectedEntry", "selectedRow", "filter", "order"]

    /// The rows in the user's own order, the first row at the top.
    public var rows: [LayoutRow]
    public var selectedEntry: LayoutEntry
    public var selectedRow: UUID?
    /// The names of the filter and the order of the sessions list. This
    /// module does not know the list, so a name of a later build stays.
    public var filter: String
    public var order: String

    public init(rows: [LayoutRow] = [], selectedEntry: LayoutEntry = .allSessions, selectedRow: UUID? = nil,
                filter: String = "all", order: String = "manual") {
        (self.rows, self.selectedEntry, self.selectedRow, self.filter, self.order) = (rows, selectedEntry, selectedRow, filter, order)
    }

    /// A key that the file does not hold takes its first value, so a file
    /// with fewer keys still reads.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            rows: try values.decodeIfPresent([LayoutRow].self, forKey: .rows) ?? [],
            selectedEntry: try values.decodeIfPresent(LayoutEntry.self, forKey: .selectedEntry) ?? .allSessions,
            selectedRow: try values.decodeIfPresent(UUID.self, forKey: .selectedRow),
            filter: try values.decodeIfPresent(String.self, forKey: .filter) ?? "all",
            order: try values.decodeIfPresent(String.self, forKey: .order) ?? "manual")
    }
}
