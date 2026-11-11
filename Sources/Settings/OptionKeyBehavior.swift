/// Which Option keys type as Alt, as Meta does in a shell. An Option key
/// that is not Alt types the special characters of the keyboard layout,
/// such as "@" on many European layouts.
public enum OptionKeyBehavior: String, CaseIterable, Hashable, Sendable {
    /// The left key is Alt, and the right key types special characters.
    case left = "left"
    case both = "both"
    case neither = "neither"
}
