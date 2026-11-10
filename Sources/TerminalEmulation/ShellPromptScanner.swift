/// Finds, in the output of a program, where a shell starts to draw its
/// prompt and where it stops editing a command line.
///
/// zsh starts each drawing of its prompt in the same way: it turns the text
/// attributes off (`sgr0`, `rmso` and `rmul`) and erases below the cursor
/// (`CSI J`). It does so for a new prompt, after SIGWINCH and for
/// `reset-prompt`. An erase alone is not enough, because zsh also erases a
/// completion list with a bare `CSI J`. `sgr0` alone is not enough either,
/// because fish writes it before an erase.
///
/// A shell with semantic prompts, such as fish 4, marks the start of its
/// prompt with `OSC 133 ; A`, and the start of a command with `OSC 133 ; C`.
///
/// Give it the output in order. A sequence can continue in the next piece.
/// All output passes through it, so it skips text up to the next escape.
public struct ShellPromptScanner: Sendable {
    public enum Event: Sendable, Equatable {
        /// zsh starts to draw its prompt at the cursor.
        case zshPromptStart
        /// A shell marks the start of its prompt (`OSC 133 ; A`).
        case markedPromptStart
        /// Bracketed paste goes off (`CSI ? 2004 l`). zsh then runs a command.
        case editingEnd
        /// A shell marks the start of a command (`OSC 133 ; C`).
        case commandStart
    }

    /// An event, and the index in the output just after its last byte.
    public struct Hit: Sendable, Equatable {
        public var index: Int
        public var event: Event
    }

    private enum State: Sendable { case text, escape, controlSequence, command, escapeInCommand }

    private static let (standoutOff, underlineOff, bracketedPaste) = (SequencePrefix("27"), SequencePrefix("24"), SequencePrefix("?2004"))
    private static let (eraseBelow, eraseBelowFromCursor) = (SequencePrefix(), SequencePrefix("0"))
    private static let (promptMark, commandMark) = (SequencePrefix("133;A").bytes, SequencePrefix("133;C").bytes)

    private var state = State.text
    private var prefix = SequencePrefix()
    /// zsh writes `rmso` (`CSI 27 m`), `rmul` (`CSI 24 m`) and the erase in a
    /// row. This counts the first two when they came last.
    private var zshProgress = 0

    public init() {}

    public mutating func hits(in bytes: ArraySlice<UInt8>) -> [Hit] {
        var hits: [Hit] = []
        var index = bytes.startIndex
        while index < bytes.endIndex {
            guard state == .text else {
                if let event = step(bytes[index]) { hits.append(Hit(index: index + 1, event: event)) }
                index += 1
                continue
            }
            // Text holds no event, and it breaks the row of zsh's sequences.
            let escape = bytes[index...].firstIndex(of: 0x1b)
            if escape != index { zshProgress = 0 }
            guard let escape else { break }
            state = .escape
            index = escape + 1
        }
        return hits
    }

    private mutating func step(_ byte: UInt8) -> Event? {
        switch (state, byte) {
        case (.escape, UInt8(ascii: "[")): (state, prefix) = (.controlSequence, SequencePrefix())
        case (.escape, UInt8(ascii: "]")): (state, prefix, zshProgress) = (.command, SequencePrefix(), 0)
        case (.command, 0x07), (.escapeInCommand, UInt8(ascii: "\\")):
            state = .text
            return commandEvent()
        case (.command, 0x1b): state = .escapeInCommand
        case (.escapeInCommand, _):
            // Another escape ends the command without effect and starts anew.
            state = .escape
            return step(byte)
        case (_, 0x1b): (state, zshProgress) = (.escape, 0)
        case (.controlSequence, 0x40...0x7e):
            state = .text
            return controlSequenceEvent(final: byte)
        case (.controlSequence, 0x20...0x3f), (.command, 0x20...): prefix.append(byte)
        case (.escape, _), (_, 0x18), (_, 0x1a): (state, zshProgress) = (.text, 0)
        default: break
        }
        return nil
    }

    private mutating func controlSequenceEvent(final: UInt8) -> Event? {
        let progress = zshProgress
        zshProgress = 0
        switch final {
        case UInt8(ascii: "m") where prefix == Self.standoutOff: zshProgress = 1
        case UInt8(ascii: "m") where prefix == Self.underlineOff && progress == 1: zshProgress = 2
        case UInt8(ascii: "J") where progress == 2 && (prefix == Self.eraseBelow || prefix == Self.eraseBelowFromCursor): return .zshPromptStart
        case UInt8(ascii: "l") where prefix == Self.bracketedPaste: return .editingEnd
        default: break
        }
        return nil
    }

    private func commandEvent() -> Event? {
        switch prefix.kind(length: 5) {
        case Self.promptMark: .markedPromptStart
        case Self.commandMark: .commandStart
        default: nil
        }
    }
}
