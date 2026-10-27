import Carbon.HIToolbox

/// Tells which keyboard layout, or input source, is current. A key can change
/// the layout while the view handles it, and then its text belongs to a layout
/// that the user has just left.
struct KeyboardLayoutWatch {
    /// Gives the identifier of the current input source, such as `com.apple.keylayout.US`.
    var identifier: () -> String? = KeyboardLayoutWatch.systemIdentifier

    static func systemIdentifier() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
            let property = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return nil }
        return Unmanaged<CFString>.fromOpaque(property).takeUnretainedValue() as String
    }
}
