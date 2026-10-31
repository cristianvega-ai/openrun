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

    /// A window that receives a flood stays attached only when its output
    /// reaches the window while the setup question is open.
    @Test func theQuestionLeavesTheMainQueueFreeWhileItIsOpen() async {
        _ = NSApplication.shared
        #expect(await ModalLoopProbe.mainQueueRunsWhileAQuestionIsOpen { _ = await askFromAThread(.failed(detail: "No answer."), runModal: $0) })
    }

    /// The setup runs on a thread of its own, and the question waits there.
    private func askFromAThread(_ question: LaunchAgentQuestion, runModal: @escaping ModalAlert.RunModal) async -> Bool {
        await withCheckedContinuation { continuation in
            Thread.detachNewThread { continuation.resume(returning: ModalAlert.ask(question, runModal: runModal)) }
        }
    }
}

/// Stands in for the modal loop of an alert, which runs the run loop in the
/// mode of a modal panel. It posts a block to the main queue, as the relay
/// of an attached window does, and tells whether the block ran before the
/// alert closed.
@MainActor private final class ModalLoopProbe {
    private var blockRan = false
    private(set) var blockRanWhileTheAlertWasOpen = false

    func spinTheLoop() {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.blockRan = true } }
        let deadline = Date().addingTimeInterval(0.2)
        while !blockRan, Date() < deadline {
            RunLoop.current.run(mode: .modalPanel, before: Date().addingTimeInterval(0.01))
        }
        blockRanWhileTheAlertWasOpen = blockRan
    }

    /// A test that runs at the same time can wait with a run loop of its
    /// own, and that loop can run this modal loop inside a block of the main
    /// queue. So one pass in several tries is enough. The code under test
    /// never starts a block of the main queue for itself.
    static func mainQueueRunsWhileAQuestionIsOpen(_ present: (@escaping ModalAlert.RunModal) async -> Void) async -> Bool {
        for _ in 0..<10 {
            let probe = ModalLoopProbe()
            await present { _ in probe.spinTheLoop(); return .alertFirstButtonReturn }
            if probe.blockRanWhileTheAlertWasOpen { return true }
        }
        return false
    }
}
