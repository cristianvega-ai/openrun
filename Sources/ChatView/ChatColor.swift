import TerminalEmulation

/// A color of the chat as plain numbers, so an appearance stays a plain
/// value that a host can compare and keep.
public struct ChatColor: Equatable, Hashable, Sendable {
    /// Each component from 0 to 1, in the sRGB color space.
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(_ color: TerminalColor) {
        self.init(red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255)
    }

    /// This color moved toward `other` by `fraction`, from 0 for this color
    /// to 1 for the other one.
    public func mixed(with other: ChatColor, fraction: Double) -> ChatColor {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * fraction }
        return ChatColor(
            red: mix(red, other.red), green: mix(green, other.green), blue: mix(blue, other.blue), alpha: mix(alpha, other.alpha))
    }

    public func withAlpha(_ alpha: Double) -> ChatColor {
        ChatColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
