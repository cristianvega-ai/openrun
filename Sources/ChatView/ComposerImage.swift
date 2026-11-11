import AgentConversation
import Foundation

/// Reads an image that the user pastes or drops into the composer.
///
/// The type comes from the first bytes, not from a file name, so a file
/// with a wrong name is still read right, and a file that is no image of
/// a known type gets a clear message.
enum ComposerImage {
    /// The largest image that the agents take.
    static let byteLimit = 5 * 1024 * 1024
    static let mediaTypes = ["image/png", "image/jpeg", "image/gif", "image/webp"]

    enum Problem: Error, Equatable {
        case unknownType
        case tooLarge(byteCount: Int)

        var message: String {
            switch self {
            case .unknownType: "Only PNG, JPEG, GIF and WebP images can go with a message."
            case .tooLarge(let byteCount):
                "The image is \(Self.megabytes(byteCount)). An image can be at most \(Self.megabytes(ComposerImage.byteLimit))."
            }
        }

        private static func megabytes(_ byteCount: Int) -> String {
            ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .binary)
        }
    }

    static func image(from data: Data) -> Result<MessageImage, Problem> {
        guard let mediaType = mediaType(of: data) else { return .failure(.unknownType) }
        guard data.count <= byteLimit else { return .failure(.tooLarge(byteCount: data.count)) }
        return .success(MessageImage(mediaType: mediaType, data: data))
    }

    static func mediaType(of data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        func starts(_ prefix: [UInt8], at offset: Int = 0) -> Bool {
            bytes.count >= offset + prefix.count && Array(bytes[offset..<offset + prefix.count]) == prefix
        }
        if starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "image/png" }
        if starts([0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if starts(Array("GIF87a".utf8)) || starts(Array("GIF89a".utf8)) { return "image/gif" }
        if starts(Array("RIFF".utf8)), starts(Array("WEBP".utf8), at: 8) { return "image/webp" }
        return nil
    }
}
