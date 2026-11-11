import Darwin

/// The git branch of a folder, read from the `HEAD` file of its repository.
///
/// OpenRun stays out of git (decision of 2026-10-15), and the sessions list
/// reads a branch about once a second while output flows. So no `git`
/// program runs: one `stat` for each folder up to the repository, and one
/// small read.
public enum GitBranch {
    /// The most bytes read from a `HEAD` file or a `.git` file. Each holds
    /// one short line, and a larger file is no file of git.
    static let readLimit = 4096

    /// The branch of the repository that holds `folder`, or the first seven
    /// characters of the commit when no branch is checked out. Nil outside
    /// every repository, and when a file of the repository cannot be read.
    ///
    /// The search goes up from the folder to the first `.git`: a folder, or
    /// a file that names the folder with `gitdir:`, as a worktree or a
    /// submodule has.
    public static func name(forFolder folder: String) -> String? {
        guard folder.hasPrefix("/") else { return nil }
        var current = folder
        while current.count > 1, current.hasSuffix("/") { current.removeLast() }
        while true {
            switch repository(at: current == "/" ? "/.git" : current + "/.git", in: current) {
            case .found(let gitFolder): return branch(inRepository: gitFolder)
            case .unreadable: return nil
            case .absent: break
            }
            guard current != "/", let slash = current.lastIndex(of: "/") else { return nil }
            current = slash == current.startIndex ? "/" : String(current[..<slash])
        }
    }

    private enum Search {
        case absent
        case unreadable
        case found(String)
    }

    /// The folder of the repository that a `.git` entry names.
    private static func repository(at path: String, in folder: String) -> Search {
        var status = stat()
        guard stat(path, &status) == 0 else { return errno == ENOENT || errno == ENOTDIR ? .absent : .unreadable }
        switch status.st_mode & S_IFMT {
        case S_IFDIR:
            return .found(path)
        case S_IFREG:
            guard let text = firstLine(ofFile: path), text.hasPrefix("gitdir:") else { return .unreadable }
            let named = text.dropFirst("gitdir:".count).trimmingSpaces()
            guard !named.isEmpty else { return .unreadable }
            // A relative path starts at the folder that holds the file.
            return .found(named.hasPrefix("/") ? named : (folder == "/" ? "" : folder) + "/" + named)
        default:
            return .unreadable
        }
    }

    /// `ref: refs/heads/NAME` names a branch. A detached head holds the
    /// hash of the commit: 40 hexadecimal digits, or 64 with SHA-256.
    private static func branch(inRepository gitFolder: String) -> String? {
        guard let head = firstLine(ofFile: gitFolder + "/HEAD") else { return nil }
        if head.hasPrefix("ref:") {
            let reference = head.dropFirst("ref:".count).trimmingSpaces()
            let branch = reference.hasPrefix("refs/heads/") ? String(reference.dropFirst("refs/heads/".count)) : reference
            return branch.isEmpty ? nil : branch
        }
        guard head.count == 40 || head.count == 64, head.allSatisfy(\.isHexDigit) else { return nil }
        return String(head.prefix(7))
    }

    /// The first line of a regular file, with no spaces around it. Nil when
    /// the file cannot be read, is no regular file, or is larger than
    /// `readLimit`.
    static func firstLine(ofFile path: String) -> String? {
        // Without O_NONBLOCK, a named pipe at the path would block the read.
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG, status.st_size <= readLimit else { return nil }
        var bytes = [UInt8](repeating: 0, count: readLimit + 1)
        let count = read(descriptor, &bytes, bytes.count)
        guard count >= 0, count <= readLimit else { return nil }
        let line = bytes[..<count].split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false).first ?? []
        return String(decoding: line, as: UTF8.self).trimmingSpaces()
    }
}

extension StringProtocol {
    fileprivate func trimmingSpaces() -> String {
        String(drop { $0.isWhitespace }.reversed().drop { $0.isWhitespace }.reversed())
    }
}
