import Foundation
@testable import SessionProcess
import Testing

@Suite struct HelperSearchPathTests {
    @Test func aProgramInAnAppBundleHasTheHelpersFolderOfTheBundle() {
        #expect(HelperSearchPath.helperFolder(forExecutableAt: "/Applications/OpenRun.app/Contents/MacOS/openrun-session")
            == "/Applications/OpenRun.app/Contents/Helpers")
    }

    @Test(arguments: [
        "/Users/someone/openrun/.build/debug/openrun-session",
        "/Users/someone/Contents/MacOS/openrun-session",
        "/Applications/OpenRun.app/Contents/Helpers/openrun",
        "openrun-session",
    ])
    func aProgramOutsideAnAppBundleHasNoHelpersFolder(path: String) {
        #expect(HelperSearchPath.helperFolder(forExecutableAt: path) == nil)
    }

    @Test func theHelpersFolderComesFirstOnThePathOfASession() {
        let helpers = HelperSearchPath(executablePath: "/Applications/OpenRun.app/Contents/MacOS/openrun-session")
        let folder = "/Applications/OpenRun.app/Contents/Helpers"
        #expect(helpers.adding(to: ["PATH": "/opt/homebrew/bin:/usr/bin", "HOME": "/Users/someone"])
            == ["PATH": "\(folder):/opt/homebrew/bin:/usr/bin", "HOME": "/Users/someone"])
        #expect(helpers.adding(to: [:]) == ["PATH": "\(folder):/usr/bin:/bin:/usr/sbin:/sbin"])
        #expect(helpers.adding(to: ["PATH": ""]) == ["PATH": folder])
        // A session that a session started has the folder already.
        #expect(helpers.adding(to: ["PATH": "/usr/bin:\(folder)"]) == ["PATH": "/usr/bin:\(folder)"])
    }

    @Test func outsideABundleThePathStaysAsItIs() {
        let helpers = HelperSearchPath(executablePath: "/Users/someone/openrun/.build/debug/openrun-session")
        #expect(helpers.adding(to: ["PATH": "/usr/bin"]) == ["PATH": "/usr/bin"])
    }
}
