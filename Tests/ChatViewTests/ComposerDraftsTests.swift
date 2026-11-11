import AgentConversation
import Foundation
import Testing

@testable import ChatView

struct ComposerDraftsTests {
    typealias Draft = ComposerDrafts.Draft

    @Test func aDraftKeepsItsTextAndImagesForItsThread() {
        var drafts = ComposerDrafts()
        let image = MessageImage(mediaType: "image/png", data: Data([1, 2, 3]))
        drafts.save(Draft(text: "Half a thought", images: [image]), for: "a")
        #expect(drafts.draft(for: "a") == Draft(text: "Half a thought", images: [image]))
        #expect(drafts.draft(for: "b").isEmpty)
        drafts.save(Draft(), for: "a")
        #expect(drafts.count == 0)
        drafts.save(Draft(text: "a"), for: "a")
        drafts.forget("a")
        #expect(drafts.count == 0)
    }

    @Test func theOldestDraftsGoPastTheLimits() {
        var drafts = ComposerDrafts()
        for index in 0...ComposerDrafts.countLimit { drafts.save(Draft(text: "\(index)"), for: "\(index)") }
        #expect(drafts.count == ComposerDrafts.countLimit)
        #expect(drafts.draft(for: "0").isEmpty)
        let large = MessageImage(mediaType: "image/png", data: Data(count: ComposerDrafts.byteLimit / 2 + 1))
        drafts.save(Draft(images: [large]), for: "x")
        drafts.save(Draft(images: [large]), for: "y")
        #expect(drafts.draft(for: "x").isEmpty)
        #expect(drafts.draft(for: "y").images == [large])
    }
}
