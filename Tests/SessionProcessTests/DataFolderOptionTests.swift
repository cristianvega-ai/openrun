import DataStorage
import Foundation
import SessionProtocol
import Testing
@testable import SessionProcess

/// The session process keeps its data in the folder of its socket, unless
/// `--data-folder` names another. So a process on a socket in a test folder
/// never touches the data of the user.
@Suite struct DataFolderOptionTests {
    @Test func theDefaultSocketGivesTheDefaultDataFolder() throws {
        let process = SessionProcess(socketLocation: try SocketLocation(path: SocketLocation.defaultPath))
        #expect(process.dataFolder == DataFolder.default)
    }

    @Test func anotherSocketGivesItsOwnFolder() throws {
        let process = SessionProcess(socketLocation: try SocketLocation(path: "/private/tmp/test-folder/socket"))
        #expect(process.dataFolder.path == "/private/tmp/test-folder")
    }

    @Test func theOptionWinsAndARelativePathStartsAtTheCurrentFolder() throws {
        #expect(SessionProcess.dataFolder(flag: "data/../other", currentFolder: "/work").path == "/work/other")
        #expect(SessionProcess.dataFolder(flag: "/absolute/./data", currentFolder: "/work").path == "/absolute/data")
        let location = try SocketLocation(path: "/private/tmp/test-folder/socket")
        let process = SessionProcess(socketLocation: location, dataFolder: DataFolder(path: "/elsewhere"), machServiceName: nil, idleExit: nil)
        #expect(process.dataFolder.path == "/elsewhere")
    }
}
