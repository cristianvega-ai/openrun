import Foundation
@testable import Projects
import Testing

/// The load joins two files that a crash, a hand edit or a later sync can
/// leave out of step.
@Suite struct ProjectMergeTests {
    static let identifiers = (1...5).map { UUID(uuidString: "00000000-0000-0000-0000-00000000000\($0)")! }

    static func entry(_ number: Int, _ name: String? = nil) -> ProjectsDocument.Entry {
        ProjectsDocument.Entry(identifier: identifiers[number - 1], name: name)
    }

    static func folders(_ pairs: [Int: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: pairs.map { (identifiers[$0.key - 1].uuidString, $0.value) })
    }

    @Test func theEntriesKeepTheirOrderAndTheFoldersWithNoEntryFollow() {
        let list = ProjectStore.merge(
            entries: [Self.entry(3, "Three"), Self.entry(1)],
            folders: Self.folders([1: "/one", 2: "/b/two", 3: "/three/", 4: "/a/four"])
        )
        #expect(list.projects.map(\.folder) == ["/three", "/one", "/a/four", "/b/two"])
        #expect(list.projects.map(\.name) == ["Three", nil, nil, nil])
    }

    @Test func badEntriesAreLeftOut() {
        let list = ProjectStore.merge(
            entries: [Self.entry(1), Self.entry(1, "Again"), Self.entry(2), Self.entry(3), Self.entry(4, "bad\u{7}"), Self.entry(5)],
            folders: Self.folders([1: "/one", 2: "/one/", 3: "relative", 4: "/four"])
                .merging(["not an identifier": "/other"]) { first, _ in first }
        )
        #expect(list.projects.map(\.folder) == ["/one", "/four"])
        #expect(list.projects.map(\.name) == [nil, nil])
    }

    @Test func theLoadKeepsAtMostTheLimit() {
        let identifiers = (0...ProjectList.countLimit).map { _ in UUID() }
        let list = ProjectStore.merge(
            entries: identifiers.map { ProjectsDocument.Entry(identifier: $0, name: nil) },
            folders: Dictionary(uniqueKeysWithValues: identifiers.enumerated().map { ($1.uuidString, "/folder/\($0)") })
        )
        #expect(list.projects.count == ProjectList.countLimit)
        #expect(list.projects.first?.identifier == identifiers.first)
    }
}
