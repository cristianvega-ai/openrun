import Foundation
import Testing

@testable import ChatView

struct ComposerImageTests {
    @Test func theTypeComesFromTheFirstBytes() {
        #expect(ComposerImage.mediaType(of: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0])) == "image/png")
        #expect(ComposerImage.mediaType(of: Data([0xFF, 0xD8, 0xFF, 0xE0])) == "image/jpeg")
        #expect(ComposerImage.mediaType(of: Data("GIF89a...".utf8)) == "image/gif")
        #expect(ComposerImage.mediaType(of: Data("RIFF\0\0\0\0WEBPVP8 ".utf8)) == "image/webp")
        #expect(ComposerImage.mediaType(of: Data("%PDF-1.7".utf8)) == nil)
    }

    @Test func aLargeOrUnknownImageGetsAClearMessage() {
        let large = Data([0xFF, 0xD8, 0xFF]) + Data(count: 6 * 1024 * 1024)
        guard case .failure(let problem) = ComposerImage.image(from: large) else { Issue.record("A large image passed"); return }
        #expect(problem.message == "The image is 6 MB. An image can be at most 5 MB.")
        #expect(ComposerImage.image(from: Data("text".utf8)) == .failure(.unknownType))
    }
}
