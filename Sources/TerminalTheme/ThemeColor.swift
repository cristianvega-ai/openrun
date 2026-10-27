import TerminalEmulation

extension TerminalColor {
    /// Makes a color from a value such as `0x1e2022`, the way the table of
    /// `documentation/product.md` writes it.
    init(hexadecimal value: UInt32) {
        self.init(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
    }
}
