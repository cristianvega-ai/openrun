import Testing
@testable import TerminalRendering

@Suite struct AtlasPackerTests {
    @Test func fillsARowFromLeftToRight() {
        var packer = AtlasPacker(side: 100)
        let first = packer.place(width: 10, height: 20)
        let second = packer.place(width: 10, height: 5)
        #expect([first?.horizontalPosition, first?.verticalPosition] == [0, 0])
        #expect([second?.horizontalPosition, second?.verticalPosition] == [11, 0])
    }

    @Test func startsANewRowBelowTheTallestBitmap() {
        var packer = AtlasPacker(side: 30)
        _ = packer.place(width: 20, height: 8)
        _ = packer.place(width: 8, height: 12)
        let next = packer.place(width: 15, height: 4)
        #expect([next?.horizontalPosition, next?.verticalPosition] == [0, 13])
    }

    @Test func answersNilWhenFullAndWorksAgainAfterAReset() {
        var packer = AtlasPacker(side: 10)
        #expect(packer.place(width: 10, height: 10) != nil)
        #expect(packer.place(width: 1, height: 1) == nil)
        #expect(packer.place(width: 11, height: 1) == nil)
        packer.reset()
        #expect(packer.place(width: 10, height: 10) != nil)
    }
}
