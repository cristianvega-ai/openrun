import GhosttyVt

/// The focus report of mode 1004: `CSI I` when the view gains focus and
/// `CSI O` when it loses it. The view sends it only while the mode is on.
public enum FocusReport {
    public static func encode(gained: Bool) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: 8)
        var written = 0
        let result = output.withUnsafeMutableBytes {
            ghostty_focus_encode(
                gained ? GHOSTTY_FOCUS_GAINED : GHOSTTY_FOCUS_LOST,
                $0.baseAddress?.assumingMemoryBound(to: CChar.self), $0.count, &written
            )
        }
        try TerminalEmulationError.check(result, from: "ghostty_focus_encode")
        return Array(output.prefix(written))
    }
}
