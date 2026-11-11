import Testing

@testable import ChatView

struct ComposerLogicTests {
    @Test func aMessageGoesAtOnceWhileTheAgentRests() {
        var logic = ComposerLogic()
        #expect(logic.submit(ChatOutgoingMessage(text: "  Hello \n")) == .send(ChatOutgoingMessage(text: "Hello")))
        #expect(logic.submit(ChatOutgoingMessage(text: " \n ")) == .none)
    }

    @Test func aMessageWaitsForTheEndOfTheTurn() {
        var logic = ComposerLogic()
        _ = logic.setBusy(true)
        #expect(logic.submit(ChatOutgoingMessage(text: "Then run the tests.")) == .none)
        #expect(logic.submit(ChatOutgoingMessage(text: "And commit.")) == .none)
        #expect(logic.heldMessage?.text == "Then run the tests.\n\nAnd commit.")
        #expect(logic.setBusy(true) == .none)
        #expect(logic.setBusy(false) == .send(ChatOutgoingMessage(text: "Then run the tests.\n\nAnd commit.")))
        #expect(logic.heldMessage == nil)
    }

    @Test func onlyASecondEscapeOnAnEmptyFieldStops() {
        var logic = ComposerLogic()
        #expect(logic.escape(isFieldEmpty: true) == .none)
        _ = logic.setBusy(true)
        #expect(logic.escape(isFieldEmpty: true) == .none)
        #expect(logic.escape(isFieldEmpty: false) == .none)
        #expect(logic.escape(isFieldEmpty: true) == .none)
        #expect(logic.escape(isFieldEmpty: true) == .stop)
    }
}
