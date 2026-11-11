import Testing
@testable import TerminalRendering

@Suite struct BoxLineArmsTests {
    private func arms(_ character: Character) -> BoxLineArms? {
        BoxLineArms(character.unicodeScalars.first!)
    }

    @Test func theCharactersOfAgentFramesHaveTheirArms() {
        #expect(arms("─") == BoxLineArms(up: .none, right: .light, down: .none, left: .light))
        #expect(arms("│") == BoxLineArms(up: .light, right: .none, down: .light, left: .none))
        #expect(arms("┌") == BoxLineArms(up: .none, right: .light, down: .light, left: .none))
        #expect(arms("┼") == BoxLineArms(up: .light, right: .light, down: .light, left: .light))
        #expect(arms("╋") == BoxLineArms(up: .heavy, right: .heavy, down: .heavy, left: .heavy))
    }

    @Test func mixedWeightsFollowTheNamesOfTheCharacters() {
        // BOX DRAWINGS DOWN LIGHT AND RIGHT UP HEAVY.
        #expect(arms("┡") == BoxLineArms(up: .heavy, right: .heavy, down: .light, left: .none))
        // BOX DRAWINGS DOWN SINGLE AND HORIZONTAL DOUBLE.
        #expect(arms("╤") == BoxLineArms(up: .none, right: .double, down: .light, left: .double))
        // BOX DRAWINGS HEAVY UP AND LIGHT DOWN.
        #expect(arms("╿") == BoxLineArms(up: .heavy, right: .none, down: .light, left: .none))
    }

    @Test func dashesCornersAndDiagonalsHaveNoArms() {
        for character in "┄┅┆┇┈┉┊┋╌╍╎╏╭╮╯╰╱╲╳" { #expect(arms(character) == nil, "\(character)") }
        #expect(arms("A") == nil && arms("▀") == nil)
    }

    @Test func neighborsJoinWithNoGapAndNoOverlapAtEveryTextSize() {
        let all = (0x2500...0x257F).compactMap { Unicode.Scalar($0).flatMap(BoxLineArms.init) }
        for size in drawnCellSizes {
            func canvas(_ arms: BoxLineArms) -> CellCanvas {
                var canvas = CellCanvas(width: size.width, height: size.height)
                arms.draw(on: &canvas)
                return canvas
            }
            func column(_ canvas: CellCanvas, _ index: Int) -> [UInt8] { (0..<size.height).map { canvas.coverage(column: index, row: $0) } }
            func row(_ canvas: CellCanvas, _ index: Int) -> [UInt8] { (0..<size.width).map { canvas.coverage(column: $0, row: index) } }
            // At 6 points on a screen of scale 1, a double line fills a cell of 4 pixels
            // to its edges. There the edge holds the whole line and can hold more.
            let isRoomy = size.width >= 6
            func joins(_ drawn: [UInt8], _ reference: [UInt8]) -> Bool {
                isRoomy ? drawn == reference : zip(drawn, reference).allSatisfy { $1 == 0 || $0 == $1 }
            }
            for weight in [BoxLineArms.Weight.light, .heavy, .double] {
                let horizontal = canvas(BoxLineArms(up: .none, right: weight, down: .none, left: weight))
                let vertical = canvas(BoxLineArms(up: weight, right: .none, down: weight, left: .none))
                for arms in all {
                    let drawn = canvas(arms)
                    if arms.right == weight { #expect(joins(column(drawn, size.width - 1), column(horizontal, 0)), "\(arms) \(size)") }
                    if arms.left == weight { #expect(joins(column(drawn, 0), column(horizontal, size.width - 1)), "\(arms) \(size)") }
                    if arms.down == weight { #expect(joins(row(drawn, size.height - 1), row(vertical, 0)), "\(arms) \(size)") }
                    if arms.up == weight { #expect(joins(row(drawn, 0), row(vertical, size.height - 1)), "\(arms) \(size)") }
                    guard isRoomy else { continue }
                    if arms.right == .none { #expect(column(drawn, size.width - 1).allSatisfy { $0 == 0 }, "\(arms) \(size)") }
                    if arms.down == .none { #expect(row(drawn, size.height - 1).allSatisfy { $0 == 0 }, "\(arms) \(size)") }
                }
            }
        }
    }

    @Test func everyOtherCharacterOfTheBlockHasAtLeastOneArm() {
        let lines = (0x2500...0x257F).compactMap { Unicode.Scalar($0).flatMap(BoxLineArms.init) }
        #expect(lines.count == 128 - 19)
        #expect(lines.allSatisfy { [$0.up, $0.right, $0.down, $0.left].contains { $0 != .none } })
    }
}
