import Foundation

/// An image that a user message of a thread carries.
public struct ThreadImage: Codable, Equatable, Sendable {
    /// Such as `image/png`. The agent decides which types it takes.
    public var mediaType: String
    public var data: Data

    public init(mediaType: String, data: Data) {
        (self.mediaType, self.data) = (mediaType, data)
    }
}
