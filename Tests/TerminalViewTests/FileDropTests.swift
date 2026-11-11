import AppKit
import Testing
@testable import TerminalView

@Suite struct DroppedFilesTests {
    @Test func plainPathsStayAndOtherPathsAreQuotedForAShell() {
        #expect(DroppedFiles.quoted("/Users/me/Projects/open-run_1.2/a+b,c:d@e%f=g") == "/Users/me/Projects/open-run_1.2/a+b,c:d@e%f=g")
        #expect(DroppedFiles.quoted("/tmp/My File.txt") == "'/tmp/My File.txt'")
        #expect(DroppedFiles.quoted("/tmp/$(rm -rf ~)`x`;&|*?") == "'/tmp/$(rm -rf ~)`x`;&|*?'")
        #expect(DroppedFiles.quoted("/tmp/it's") == "'/tmp/it'\\''s'")
        #expect(DroppedFiles.quoted("/tmp/日本") == "'/tmp/日本'")
    }

    @Test func eachPathIsFollowedByASpace() {
        #expect(DroppedFiles.text(for: ["/a", "/b c"]) == "/a '/b c' ")
    }
}

@MainActor @Suite struct FileDropOfViewTests {
    private func makeView() throws -> (view: TerminalView, delegate: RecordingDelegate, pasteboard: NSPasteboard) {
        let view = try TerminalView()
        let delegate = RecordingDelegate()
        view.delegate = delegate
        return (view, delegate, NSPasteboard(name: NSPasteboard.Name("OpenRunDropTest-\(UUID().uuidString)")))
    }

    @Test func aDropOfFilesTypesTheirPathsAsAPaste() throws {
        let (view, delegate, pasteboard) = try makeView()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: "/tmp/a b.txt") as NSURL, URL(fileURLWithPath: "/tmp/c") as NSURL])
        #expect(view.drop(from: pasteboard))
        #expect(delegate.takeSent() == "'/tmp/a b.txt' /tmp/c ")
        // With bracketed paste on, the paths come inside the brackets, so nothing runs.
        view.terminal.write("\u{1B}[?2004h")
        #expect(view.drop(from: pasteboard))
        #expect(delegate.takeSent() == "\u{1B}[200~'/tmp/a b.txt' /tmp/c \u{1B}[201~")
    }

    @Test func aDropOfTextIsAPasteWithItsQuestion() async throws {
        let (view, delegate, pasteboard) = try makeView()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("ls\nrm -rf /", forType: .string)
        #expect(view.drop(from: pasteboard))
        await settle { !delegate.questions.isEmpty }
        #expect(delegate.questions == ["ls\nrm -rf /"] && delegate.takeSent() == "")
        pasteboard.clearContents()
        #expect(!view.drop(from: pasteboard) && view.dropText(from: pasteboard) == nil)
    }
}
