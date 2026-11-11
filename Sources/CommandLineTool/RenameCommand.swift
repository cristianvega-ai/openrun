import SessionConnection
import SessionProtocol

/// `openrun rename`: gives a session a name, or removes the name when none
/// is given. A program in a session may name only its own session.
struct RenameCommand {
    var identifier: String
    var name: String?

    func run(location: SocketLocation) throws {
        let client = try SessionClient(location: location)
        let session = try client.session(matching: identifier)
        try client.rename(session: session.identifier, to: name)
    }
}
