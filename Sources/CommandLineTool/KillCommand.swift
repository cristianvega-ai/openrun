import SessionProtocol

/// `openrun kill`: ends a session and its program.
struct KillCommand {
    var identifier: String

    func run(location: SocketLocation) throws {
        let client = try SessionClient(location: location)
        let session = try client.session(matching: identifier)
        _ = try client.request(.killSession(identifier: session.identifier))
    }
}
