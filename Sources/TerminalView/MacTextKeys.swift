import AppKit
import Carbon.HIToolbox

/// The keys that move and delete in the text of a Mac, as the line editors of
/// shells understand them (decision of 2026-11-10). Command-Left and
/// Command-Right go to the start and the end of the line, Option-Left and
/// Option-Right move by words, and Command-Backspace and Option-Backspace
/// delete the line before the cursor and the word before it. The bytes are the
/// keys of Emacs, which zsh, bash, fish and the prompts of agents read.
enum MacTextKeys {
    /// The bytes of such a key, or `nil` for any other key. Arrows and Backspace
    /// type no character, so any Option key moves by words, whatever key is Alt.
    static func bytes(for event: NSEvent) -> [UInt8]? {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch (Int(event.keyCode), modifiers) {
        case (kVK_LeftArrow, .command): return [0x01]
        case (kVK_RightArrow, .command): return [0x05]
        case (kVK_Delete, .command): return [0x15]
        case (kVK_LeftArrow, .option): return [0x1B, UInt8(ascii: "b")]
        case (kVK_RightArrow, .option): return [0x1B, UInt8(ascii: "f")]
        case (kVK_Delete, .option): return [0x1B, 0x7F]
        default: return nil
        }
    }
}
