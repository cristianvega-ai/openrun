import Testing
@testable import TerminalEmulation

@Suite struct MouseEncoderTests {
    @Test func reportsPressesReleasesWheelTurnsAndMotion() throws {
        let terminal = try makeTerminal(columns: 20, rows: 10)
        let encoder = try MouseEncoder()
        func send(_ events: MouseEvent...) throws -> [String] {
            encoder.update(from: terminal, cellWidth: 16, cellHeight: 32, anyButtonPressed: false)
            return try events.map { String(decoding: try encoder.encode($0), as: UTF8.self) }
        }
        let press = MouseEvent(action: .press, button: .left, x: 86, y: 101)
        #expect(try send(press) == [""])
        terminal.write("\u{1B}[?1003h\u{1B}[?1006h")
        let release = MouseEvent(action: .release, button: .left, x: 86, y: 101)
        let wheel = MouseEvent(action: .press, button: .wheelUp, x: 0, y: 0)
        #expect(try send(press, release, wheel) == ["\u{1B}[<0;6;4M", "\u{1B}[<0;6;4m", "\u{1B}[<64;1;1M"])
        let motion = MouseEvent(action: .motion, button: nil, x: 40, y: 40)
        #expect(try send(motion, MouseEvent(action: .motion, button: nil, x: 41, y: 41)) == ["\u{1B}[<35;3;2M", ""])
    }

    @Test func aButtonStateKeepsTheLastCellButUpdateForgetsIt() throws {
        let terminal = try makeTerminal(columns: 20, rows: 10)
        terminal.write("\u{1B}[?1003h\u{1B}[?1006h")
        let encoder = try MouseEncoder()
        encoder.update(from: terminal, cellWidth: 16, cellHeight: 32, anyButtonPressed: false)
        func motion(_ x: Float) throws -> String { String(decoding: try encoder.encode(MouseEvent(action: .motion, button: nil, x: x, y: 5)), as: UTF8.self) }
        #expect(try motion(40) == "\u{1B}[<35;3;1M")
        encoder.setAnyButtonPressed(true)
        #expect(try motion(41) == "")
        encoder.update(from: terminal, cellWidth: 16, cellHeight: 32, anyButtonPressed: false)
        #expect(try motion(42) == "\u{1B}[<35;3;1M")
    }
}
