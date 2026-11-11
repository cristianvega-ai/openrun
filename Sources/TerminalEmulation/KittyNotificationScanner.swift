import Foundation

/// Finds the desktop notifications of kitty (OSC 99) in the output of a
/// program. libghostty-vt parses OSC 99 and reports nothing for it, while it
/// reports OSC 9 and OSC 777 (see `TerminalEventHandler`).
///
/// A notification is `ESC ] 99 ; METADATA ; PAYLOAD` and then `ESC \` or
/// BEL. The metadata holds `key=value` pairs, separated by colons. `p` names
/// the payload: `title`, the default, and `body` hold text, while `close`,
/// `alive`, `icon`, `buttons` and the query `?` do not. `e=1` means base64.
/// `d=0` means that more pieces of the same notification follow, and it
/// shows at its last piece.
///
/// Give it the output in order. A sequence can continue in the next piece.
/// The text comes from the program, so each command keeps at most
/// `commandByteLimit` bytes, and the rest of it is dropped.
public struct KittyNotificationScanner: Sendable {
    public static let commandByteLimit = 2048

    private enum State: Sendable { case text, escape, command, escapeInCommand }

    private var state = State.text
    private var command: [UInt8] = []
    /// The command is no OSC 99, so its bytes need no keeping.
    private var isOtherCommand = false
    /// The text of the pieces before the last one, of a notification in pieces.
    private var earlierText: String?

    public init() {}

    /// The text of the last notification that ends in the bytes, or nil
    /// when none ends there. The text holds what the program sent and can be
    /// empty.
    public mutating func notification(in bytes: ArraySlice<UInt8>) -> String? {
        var found: String?
        var index = bytes.startIndex
        while index < bytes.endIndex {
            guard state == .text else {
                if let text = step(bytes[index]) { found = text }
                index += 1
                continue
            }
            guard let escape = bytes[index...].firstIndex(of: 0x1B) else { break }
            state = .escape
            index = escape + 1
        }
        return found
    }

    private mutating func step(_ byte: UInt8) -> String? {
        switch (state, byte) {
        case (.escape, UInt8(ascii: "]")):
            (state, isOtherCommand) = (.command, false)
            command.removeAll(keepingCapacity: true)
        case (.command, 0x07), (.escapeInCommand, UInt8(ascii: "\\")):
            state = .text
            return isOtherCommand ? nil : finishedNotification()
        case (.command, 0x1B): state = .escapeInCommand
        case (.escapeInCommand, _):
            // Another escape ends the command without effect and starts anew.
            state = .escape
            return step(byte)
        case (_, 0x1B): state = .escape
        case (.command, 0x18), (.command, 0x1A), (.escape, _): state = .text
        case (.command, _):
            guard !isOtherCommand, command.count < Self.commandByteLimit else { break }
            command.append(byte)
            if command.count == 3, command != Array("99;".utf8) { isOtherCommand = true }
        default: break
        }
        return nil
    }

    private mutating func finishedNotification() -> String? {
        guard command.count >= 3 else { return nil }
        let content = command.dropFirst(3)
        let separator = content.firstIndex(of: UInt8(ascii: ";")) ?? content.endIndex
        var metadata: [String: String] = [:]
        for pair in content[..<separator].split(separator: UInt8(ascii: ":")) {
            let parts = pair.split(separator: UInt8(ascii: "="), maxSplits: 1)
            metadata[String(decoding: parts[0], as: UTF8.self)] = parts.count > 1 ? String(decoding: parts[1], as: UTF8.self) : ""
        }
        guard ["title", "body"].contains(metadata["p"] ?? "title") else { return nil }
        var payload = Array(content[separator...].dropFirst())
        if metadata["e"] == "1" {
            // A command cut at the limit can end inside a group of four.
            payload = Data(base64Encoded: Data(payload.prefix(payload.count / 4 * 4))).map { Array($0) } ?? []
        }
        let text = String(decoding: payload, as: UTF8.self)
        guard metadata["d"] != "0" else {
            if !text.isEmpty { earlierText = text }
            return nil
        }
        defer { earlierText = nil }
        return text.isEmpty ? earlierText ?? "" : text
    }
}
