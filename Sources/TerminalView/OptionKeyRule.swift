import TerminalEmulation

/// Which Option keys act as Alt, the meta key of shells and agents. An Option
/// key that is not Alt types the characters of macOS, such as © or é. The
/// default is the left key (decision of 2026-10-26).
public enum OptionKeyRule: Sendable, Equatable, CaseIterable {
    /// The left Option key is Alt, and the right one types characters.
    case left
    /// Both Option keys are Alt.
    case both
    /// No Option key is Alt. Both type characters.
    case neither

    /// The rule as the key encoder of libghostty-vt takes it.
    var encoderRule: KeyEncoder.OptionAsAlternate {
        switch self {
        case .left: .leftOnly
        case .both: .always
        case .neither: .never
        }
    }
}
