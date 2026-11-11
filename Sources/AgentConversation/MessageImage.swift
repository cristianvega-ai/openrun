import Foundation

/// An image that the user sends with a message.
public struct MessageImage: Sendable, Hashable {
    /// The media type, such as `image/png`.
    public var mediaType: String
    /// The bytes of the image file.
    public var data: Data

    public init(mediaType: String, data: Data) {
        self.mediaType = mediaType
        self.data = data
    }
}
