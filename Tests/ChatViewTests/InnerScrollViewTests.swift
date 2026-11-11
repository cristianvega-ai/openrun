import Testing

@testable import ChatView

struct InnerScrollViewTests {
    @Test func aScrollGoesOnToTheTranscriptAtTheEdgesOnly() {
        #expect(InnerScrollView.handsOn(deltaX: 0, deltaY: 5, offset: 0, maximumOffset: 100))
        #expect(!InnerScrollView.handsOn(deltaX: 0, deltaY: 5, offset: 40, maximumOffset: 100))
        #expect(!InnerScrollView.handsOn(deltaX: 0, deltaY: -5, offset: 40, maximumOffset: 100))
        #expect(InnerScrollView.handsOn(deltaX: 0, deltaY: -5, offset: 100, maximumOffset: 100))
    }

    @Test func aBoxThatFitsAndASidewaysScrollHandOn() {
        #expect(InnerScrollView.handsOn(deltaX: 0, deltaY: -5, offset: 0, maximumOffset: 0))
        #expect(InnerScrollView.handsOn(deltaX: 8, deltaY: 1, offset: 40, maximumOffset: 100))
    }
}
