import DataStorage
import Foundation
import Projects
import SessionProcessHarness
import Testing
@testable import SessionProcess

@Suite struct ProjectKeeperTests {
    /// A data folder of the test with two folders to add as projects.
    private static func makeFolders() throws -> (data: URL, first: String, second: String) {
        let data = try RunningSessionProcess.makeDirectory()
        for name in ["first", "second"] {
            try FileManager.default.createDirectory(at: data.appendingPathComponent(name), withIntermediateDirectories: false)
        }
        let real = try #require(realpath(data.path, nil).map { pointer in defer { free(pointer) }; return String(cString: pointer) })
        return (data, real + "/first", real + "/second")
    }

    @Test func eachChangeIsOnTheDiskWhenItReturns() async throws {
        let (data, first, second) = try Self.makeFolders()
        defer { try? FileManager.default.removeItem(at: data) }
        let store = ProjectStore(dataFolder: DataFolder(path: data.path))
        let keeper = ProjectKeeper(store: store)
        let added = try await keeper.add(folder: first, name: nil, currentFolder: nil)
        #expect(added.version == 1 && added.project.folder == first)
        let other = try await keeper.add(folder: "second", name: "Other", currentFolder: data.path).project
        #expect(other.folder == second)
        _ = try await keeper.move(identifier: other.identifier, to: 0)
        _ = try await keeper.rename(identifier: added.project.identifier, to: "First")
        let kept = await keeper.list
        #expect(try store.load().list == kept)
        let removed = try await keeper.remove(identifier: other.identifier)
        #expect(removed.version == 5)
        #expect(try store.load().list.projects.map(\.name) == ["First"])
        // A new keeper, as after a restart, reads the same list.
        let restarted = await ProjectKeeper(store: store).list
        #expect(restarted == removed.list)
    }

    @Test func aRefusedChangeChangesNothing() async throws {
        let (data, first, _) = try Self.makeFolders()
        defer { try? FileManager.default.removeItem(at: data) }
        let keeper = ProjectKeeper(store: ProjectStore(dataFolder: DataFolder(path: data.path)))
        await #expect(throws: ProjectListError.folderDoesNotExist(path: first + "-missing")) {
            try await keeper.add(folder: first + "-missing", name: nil, currentFolder: nil)
        }
        await #expect(throws: ProjectListError.invalidName) { try await keeper.add(folder: first, name: "a\nb", currentFolder: nil) }
        let (version, list) = (await keeper.version, await keeper.list)
        #expect(version == 0 && list.projects.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: data.appendingPathComponent("projects.json").path))
    }

    /// A save that fails leaves the list in memory as it is on the disk.
    @Test func aFailedSaveKeepsTheListBeforeTheChange() async throws {
        let (data, first, second) = try Self.makeFolders()
        defer { chmod(data.path, 0o700); try? FileManager.default.removeItem(at: data) }
        let store = ProjectStore(dataFolder: DataFolder(path: data.path))
        let keeper = ProjectKeeper(store: store)
        let before = try await keeper.add(folder: first, name: nil, currentFolder: nil).list
        try #require(chmod(data.path, 0o500) == 0)
        await #expect(throws: DataSaveFailure.self) { try await keeper.add(folder: second, name: nil, currentFolder: nil) }
        let (list, version) = (await keeper.list, await keeper.version)
        #expect(list == before && version == 1)
        try #require(chmod(data.path, 0o700) == 0)
        #expect(try store.load().list == before)
    }

    @Test func aFileThatCannotBeReadDoesNotStopTheStart() async throws {
        let (data, _, _) = try Self.makeFolders()
        defer { try? FileManager.default.removeItem(at: data) }
        try Data("not JSON".utf8).write(to: data.appendingPathComponent("projects.json"))
        let keeper = ProjectKeeper(store: ProjectStore(dataFolder: DataFolder(path: data.path)))
        let list = await keeper.list
        #expect(list.projects.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: data.path)
        #expect(names.contains { $0.hasPrefix("projects.unreadable-") }, "\(names)")
    }
}
