import Darwin
import Darwin.membership

/// The access control list of a folder, which macOS checks besides the mode.
///
/// An entry can let another user or a group add and remove files in a
/// folder whose mode lets only the owner write. Such a user could put a
/// socket of their own in the place of the session process's socket, so the
/// folder check reads the list as well as the mode.
enum FolderAccessControlList {
    /// Whether an entry that allows lets anyone but `owner` change what the
    /// folder holds: add a file or a folder, delete one, or write. An entry
    /// that lets them change the list or the owner counts too, because with
    /// it they can give themselves those rights.
    ///
    /// Entries that deny pass. An entry for a group counts even when `owner`
    /// is its only member. Entries that only pass on to new files count as
    /// well. Both err on the safe side.
    ///
    /// - Throws: `SessionProtocolError.systemCallFailed` when the list
    ///   cannot be read.
    static func letsOthersChange(folder: String, owner: uid_t) throws -> Bool {
        guard let list = acl_get_file(folder, ACL_TYPE_EXTENDED) else {
            // ENOENT means the folder has no list. A file system without
            // lists has nothing to check beyond the mode.
            if errno == ENOENT || errno == ENOTSUP || errno == EOPNOTSUPP { return false }
            throw SessionProtocolError.failure(of: "acl_get_file")
        }
        defer { acl_free(UnsafeMutableRawPointer(list)) }
        return letsOthersChange(list: list, owner: owner)
    }

    /// The check on a list that is already read. `rights` and `readTag` are
    /// parameters only so that a test can make a query fail.
    ///
    /// A query that fails counts as an entry that lets others change the
    /// folder, because the check cannot say that the entry is safe.
    static func letsOthersChange(
        list: acl_t,
        owner: uid_t,
        rights: [acl_perm_t] = changingRights,
        readTag: (acl_entry_t, UnsafeMutablePointer<acl_tag_t>) -> Int32 = { acl_get_tag_type($0, $1) }
    ) -> Bool {
        // An entry names a user or a group by a universally unique
        // identifier, not by a user number.
        var ownerIdentifier = [UInt8](repeating: 0, count: 16)
        let ownerIsKnown = mbr_uid_to_uuid(owner, &ownerIdentifier) == 0

        var entry: acl_entry_t?
        var position = ACL_FIRST_ENTRY.rawValue
        while acl_get_entry(list, position, &entry) == 0, let entry {
            position = ACL_NEXT_ENTRY.rawValue
            var tag = ACL_UNDEFINED_TAG
            guard readTag(entry, &tag) == 0 else { return true }
            guard tag == ACL_EXTENDED_ALLOW else { continue }
            if ownerIsKnown, Self.qualifier(of: entry) == ownerIdentifier { continue }
            var permissions: acl_permset_t?
            guard acl_get_permset(entry, &permissions) == 0, let permissions else { return true }
            for right in rights {
                // 1 means the entry has the right, 0 that it has not, and
                // -1 that the query failed.
                if acl_get_perm_np(permissions, right) != 0 { return true }
            }
        }
        return false
    }

    /// The rights that let a user change what a folder holds. For a folder,
    /// `ACL_ADD_FILE` is the write right and `ACL_ADD_SUBDIRECTORY` the
    /// append right.
    private static let changingRights = [
        ACL_ADD_FILE, ACL_ADD_SUBDIRECTORY, ACL_DELETE_CHILD, ACL_WRITE_SECURITY, ACL_CHANGE_OWNER,
    ]

    /// The 16 bytes of the identifier of the user or group that an entry
    /// names, or nil when the entry names none.
    private static func qualifier(of entry: acl_entry_t) -> [UInt8]? {
        guard let qualifier = acl_get_qualifier(entry) else { return nil }
        defer { acl_free(qualifier) }
        return Array(UnsafeRawBufferPointer(start: qualifier, count: 16))
    }
}
