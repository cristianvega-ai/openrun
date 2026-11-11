import Foundation
import Projects
import Testing

@Suite struct ProjectListErrorTests {
    /// An agent can send a path with an escape sequence, and the message
    /// goes back to a terminal.
    @Test func aPathInAMessageHasNoControlCharacter() {
        let path = "/work/\u{1B}]0;title\u{7}\u{202E}x"
        let errors: [ProjectListError] = [
            .relativeFolder(path: path), .folderDoesNotExist(path: path), .notAFolder(path: path),
            .duplicateFolder(path: path, project: UUID()),
        ]
        for error in errors {
            #expect(!error.description.unicodeScalars.contains { $0.properties.generalCategory == .control })
            #expect(!error.description.contains("\u{202E}"))
            #expect(error.description.contains(#""/work/\u{1B}]0;title\u{7}\u{202E}x""#))
        }
    }
}
