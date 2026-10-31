import AppKit
import Foundation
import Testing
@testable import OpenRunApplication

@MainActor @Suite(.serialized) struct ModalAlertTests {
    @Test func theQuestionShowsItsWordsAndReturnsWhetherTheFirstButtonWasChosen() async {
        _ = NSApplication.shared
        let words = LaunchAgentQuestion.approvalNeeded.words
        for (response, expected) in [(NSApplication.ModalResponse.alertFirstButtonReturn, true), (.alertSecondButtonReturn, false)] {
            let agreed = await askFromAThread(.approvalNeeded) { alert in
                #expect(alert.messageText == words.title && alert.informativeText == words.message)
                #expect(alert.buttons.map(\.title) == words.buttons)
                return response
            }
            #expect(agreed == expected)
        }
    }

    /// The setup runs on a thread of its own, and the question waits there.
    private func askFromAThread(_ question: LaunchAgentQuestion, runModal: @escaping ModalAlert.RunModal) async -> Bool {
        await withCheckedContinuation { continuation in
            Thread.detachNewThread { continuation.resume(returning: ModalAlert.ask(question, runModal: runModal)) }
        }
    }
}
