import Darwin
import Foundation
import Testing
@testable import SessionProtocol

/// The folder check must read the access control list of
/// the socket's folder, because an entry can let others change a folder
/// whose mode lets only the owner write.
@Suite struct FolderAccessControlListTests {
    private func makeFolder() throws -> String {
        let path = NSTemporaryDirectory() + "listed-folder-\(UInt32.random(in: 0...UInt32.max))"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        #expect(chmod(path, 0o700) == 0)
        return path
    }

    @Test func aFolderWithoutAListLetsNoOneElseChangeIt() throws {
        let path = try makeFolder()
        defer { removeFolderAndItsAccessControlList(path) }
        #expect(try !FolderAccessControlList.letsOthersChange(folder: path, owner: geteuid()))
    }

    /// Each right that lets another user put a file in the place of the
    /// socket, or give themselves that right, counts.
    @Test(arguments: [
        "everyone allow add_file",
        "everyone allow add_subdirectory",
        "everyone allow delete_child",
        "everyone allow writesecurity",
        "everyone allow chown",
        "group:staff allow add_file",
        "user:nobody allow delete_child",
        "everyone allow add_file,file_inherit,directory_inherit",
    ])
    func anEntryThatAllowsAnotherUserOrAGroupToChangeTheFolderCounts(entry: String) throws {
        let path = try makeFolder()
        defer { removeFolderAndItsAccessControlList(path) }
        try addAccessControlEntry(entry, to: path)
        #expect(try FolderAccessControlList.letsOthersChange(folder: path, owner: geteuid()))
    }

    @Test(arguments: [
        "everyone deny add_file,add_subdirectory,delete_child,writesecurity,chown",
        "everyone allow list,search,readattr,readextattr,readsecurity",
    ])
    func anEntryThatDeniesOrAllowsOnlyReadingPasses(entry: String) throws {
        let path = try makeFolder()
        defer { removeFolderAndItsAccessControlList(path) }
        try addAccessControlEntry(entry, to: path)
        #expect(try !FolderAccessControlList.letsOthersChange(folder: path, owner: geteuid()))
    }

    /// A query that fails must refuse the folder.
    @Test func anEntryWhoseTagCannotBeReadRefusesTheFolder() throws {
        let path = try makeFolder()
        defer { removeFolderAndItsAccessControlList(path) }
        try addAccessControlEntry("everyone allow list", to: path)
        let list = try #require(acl_get_file(path, ACL_TYPE_EXTENDED))
        defer { acl_free(UnsafeMutableRawPointer(list)) }
        #expect(!FolderAccessControlList.letsOthersChange(list: list, owner: geteuid()))
        #expect(FolderAccessControlList.letsOthersChange(list: list, owner: geteuid(), readTag: { _, _ in -1 }))
    }

    @Test func aPermissionQueryThatFailsRefusesTheFolder() throws {
        let path = try makeFolder()
        defer { removeFolderAndItsAccessControlList(path) }
        try addAccessControlEntry("everyone allow list", to: path)
        let list = try #require(acl_get_file(path, ACL_TYPE_EXTENDED))
        defer { acl_free(UnsafeMutableRawPointer(list)) }
        // No right has this number, so the query fails with EINVAL.
        let unknownRight = acl_perm_t(rawValue: 0xfffff)
        #expect(FolderAccessControlList.letsOthersChange(list: list, owner: geteuid(), rights: [unknownRight]))
    }

    @Test func anEntryForTheOwnerPassesAndTheSameEntryForAnotherUserCounts() throws {
        let path = try makeFolder()
        defer { removeFolderAndItsAccessControlList(path) }
        try addAccessControlEntry("user:\(NSUserName()) allow add_file,add_subdirectory,delete_child,writesecurity", to: path)
        #expect(try !FolderAccessControlList.letsOthersChange(folder: path, owner: geteuid()))
        // To a folder of another owner, the same entry lets someone else in.
        let anotherUser = try #require(getpwnam("nobody")).pointee.pw_uid
        #expect(try FolderAccessControlList.letsOthersChange(folder: path, owner: anotherUser))
    }

    /// The entry that lets others in may sit behind entries that pass.
    @Test func anEntryThatCountsIsFoundBehindEntriesThatPass() throws {
        let path = try makeFolder()
        defer { removeFolderAndItsAccessControlList(path) }
        try addAccessControlEntry("everyone deny delete", to: path)
        try addAccessControlEntry("user:\(NSUserName()) allow add_file", to: path)
        try addAccessControlEntry("everyone allow list", to: path)
        #expect(try !FolderAccessControlList.letsOthersChange(folder: path, owner: geteuid()))
        try addAccessControlEntry("group:everyone allow delete_child", to: path)
        #expect(try FolderAccessControlList.letsOthersChange(folder: path, owner: geteuid()))
    }

    /// The exact failure of the folder check, which the tests in
    /// `SocketLocationTests` match by its text.
    @Test func theFolderCheckThrowsTheAccessControlListCase() throws {
        let path = try makeFolder()
        defer { removeFolderAndItsAccessControlList(path) }
        try addAccessControlEntry("everyone allow add_file,delete_child", to: path)
        #expect(throws: SessionProtocolError.socketFolderWritableThroughAccessControlList(folder: path)) {
            try SocketLocation(path: path + "/session.socket").checkFolder()
        }
    }

    @Test func theFolderCheckThrowsTheCaseOfAFileInThePlaceOfTheFolder() throws {
        let file = NSTemporaryDirectory() + "plain-file-\(UInt32.random(in: 0...UInt32.max))"
        #expect(FileManager.default.createFile(atPath: file, contents: Data()))
        defer { try? FileManager.default.removeItem(atPath: file) }
        #expect(throws: SessionProtocolError.socketFolderIsNotADirectory(folder: file)) {
            try SocketLocation(path: file + "/session.socket").checkFolder()
        }
    }
}
