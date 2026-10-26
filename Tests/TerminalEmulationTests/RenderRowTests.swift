import Testing
@testable import TerminalEmulation

@Suite struct RenderRowTests {
    @Test func visitsEveryRowFromTheTop() throws {
        let state = try RenderState()
        try state.update(from: makeTerminal(columns: 10, rows: 4))
        var places: [Int] = []
        try state.forEachRow(onlyChanged: false) { places.append($0.viewportRow) }
        #expect(places == [0, 1, 2, 3])
    }

    @Test func typingMakesOneRowDirtyAndKeepsTheIdentifiers() throws {
        let terminal = try makeTerminal(columns: 10, rows: 4)
        let state = try RenderState()
        try state.update(from: terminal)
        var before: [RowIdentifier] = []
        try state.forEachRow(onlyChanged: false) { before.append($0.identifier) }
        #expect(Set(before).count == 4)
        state.markClean()

        terminal.write("x")
        try state.update(from: terminal)
        var changed: [Int] = []
        var after: [RowIdentifier] = []
        try state.forEachRow(onlyChanged: true) { changed.append($0.viewportRow) }
        try state.forEachRow(onlyChanged: false) { after.append($0.identifier) }
        #expect(changed == [0])
        #expect(after == before)
    }
}
