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

    @Test func everyOtherCharacterOfTheBlockHasAtLeastOneArm() {
        let lines = (0x2500...0x257F).compactMap { Unicode.Scalar($0).flatMap(BoxLineArms.init) }
        #expect(lines.count == 128 - 19)
        #expect(lines.allSatisfy { [$0.up, $0.right, $0.down, $0.left].contains { $0 != .none } })
    }
}
