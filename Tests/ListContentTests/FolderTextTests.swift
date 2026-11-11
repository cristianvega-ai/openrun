import Testing
@testable import ListContent

@Suite struct FolderTextTests {
    @Test func theHomeFolderShowsAsATilde() {
        #expect(FolderText.shown("/Users/ana", home: "/Users/ana") == "~")
        #expect(FolderText.shown("/Users/ana/Projects/openrun", home: "/Users/ana") == "~/Projects/openrun")
        #expect(FolderText.shown("/Users/anabel/work", home: "/Users/ana") == "/Users/anabel/work")
        #expect(FolderText.shown("/tmp", home: "/Users/ana") == "/tmp")
        #expect(FolderText.shown("/tmp", home: "") == "/tmp")
        #expect(FolderText.shown("/tmp", home: "/") == "/tmp")
    }

    @Test func theLastNameOfAFolder() {
        #expect(FolderText.lastName(of: "/Users/ana/Projects/openrun", home: "/Users/ana") == "openrun")
        #expect(FolderText.lastName(of: "/Users/ana", home: "/Users/ana") == "~")
        #expect(FolderText.lastName(of: "/", home: "/Users/ana") == "/")
    }
}
