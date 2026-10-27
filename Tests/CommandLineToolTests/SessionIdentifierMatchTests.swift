import Foundation
import SessionProtocol
import Testing
@testable import CommandLineTool

@Suite struct SessionIdentifierMatchTests {
    private func summary(_ identifier: String) -> SessionSummary {
        SessionSummary(
            identifier: UUID(uuidString: identifier)!,
            folder: "/work/\(identifier.prefix(4))",
            command: ["sh"],
            size: SessionSize(columns: 80, rows: 24),
            createdAt: .now
        )
    }

    private var summaries: [SessionSummary] {
        [
            summary("1A2B3C4D-0000-4000-8000-000000000001"),
            summary("1A2B9999-0000-4000-8000-000000000002"),
            summary("FFEE0000-0000-4000-8000-000000000003"),
        ]
    }

    @Test func aUniquePrefixFindsTheSession() throws {
        #expect(try SessionIdentifierMatch.find("ff", in: summaries).identifierText.hasPrefix("ffee"))
        #expect(try SessionIdentifierMatch.find("1a2b3", in: summaries).identifierText.hasPrefix("1a2b3c4d"))
    }

    @Test func caseDoesNotMatter() throws {
        #expect(try SessionIdentifierMatch.find("FFEE", in: summaries).identifierText.hasPrefix("ffee"))
    }

    @Test func aSharedPrefixIsAmbiguousAndListsTheCandidates() {
        do {
            _ = try SessionIdentifierMatch.find("1a2b", in: summaries)
            Issue.record("The prefix should be ambiguous.")
        } catch let error as CommandLineToolError {
            #expect(error.exitCode == 1)
            #expect(error.description.contains("1a2b3c4d"))
            #expect(error.description.contains("1a2b9999"))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func aFullIdentifierWinsOverLongerMatches() throws {
        let found = try SessionIdentifierMatch.find("1a2b3c4d-0000-4000-8000-000000000001", in: summaries)
        #expect(found.identifierText == "1a2b3c4d-0000-4000-8000-000000000001")
    }

    @Test func noMatchAndAnEmptyIdentifierFail() {
        #expect(throws: CommandLineToolError.self) { try SessionIdentifierMatch.find("zzzz", in: summaries) }
        #expect(throws: CommandLineToolError.self) { try SessionIdentifierMatch.find("", in: summaries) }
        #expect(throws: CommandLineToolError.self) { try SessionIdentifierMatch.find("1a", in: []) }
    }
}
