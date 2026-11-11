import AgentConversation

/// The file changes of a `fileChange` item of Codex.
///
/// For a changed file Codex gives a unified diff. For a new or a deleted
/// file it gives the content alone (`"diff":"hi\n"` for a new file with
/// one line), so the content becomes a diff of added or removed lines.
enum CodexFileChanges {
    static func changes(of item: JSONValue) -> [FileChange] {
        let identifier = item["id"]?.string ?? ""
        return (item["changes"]?.array ?? []).enumerated().map { place, change in
            let text = change["diff"]?.string ?? ""
            let kind: FileChange.Kind = switch change["kind"]?["type"]?.string {
            case "add": .added
            case "delete": .deleted
            default: .modified
            }
            var path = change["path"]?.string ?? ""
            if let destination = change["kind"]?["move_path"]?.string { path += " → " + destination }
            let diff = switch kind {
            case .added: wholeFile(text, prefix: "+")
            case .deleted: wholeFile(text, prefix: "-")
            case .modified: text
            }
            return FileChange(identifier: "\(identifier):\(place)", toolCallIdentifier: identifier, path: path, kind: kind, diff: diff)
        }
    }

    /// The content of a file as one hunk of added or removed lines.
    static func wholeFile(_ content: String, prefix: String) -> String {
        guard !content.hasPrefix("@@"), !content.hasPrefix("diff --git") else { return content }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        let kept = content.hasSuffix("\n") ? lines.dropLast() : lines[...]
        let header = prefix == "+" ? "@@ -0,0 +1,\(kept.count) @@" : "@@ -1,\(kept.count) +0,0 @@"
        return ([header] + kept.map { prefix + $0 }).joined(separator: "\n")
    }
}
