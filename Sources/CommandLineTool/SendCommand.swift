import SessionProtocol

/// `openrun send`: types text into a session without attaching.
struct SendCommand {
    var identifier: String
    var text: String
    var pressEnter: Bool

    func run(location: SocketLocation) throws {
        let client = try SessionClient(location: location)
        let session = try client.session(matching: identifier)
        // A terminal sends a carriage return for the Enter key, not a line feed.
        let typed = pressEnter ? text + "\r" : text
        _ = try client.request(.sendText(identifier: session.identifier, text: typed))
    }
}
