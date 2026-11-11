import AgentConversation

/// One message that the app-server writes: JSON-RPC without the `jsonrpc`
/// member, one object on each line (notes 2.1).
enum CodexMessage: Sendable, Hashable {
    /// The answer to a request of OpenRun.
    case response(CodexRequestIdentifier, result: JSONValue)
    /// The refusal of a request of OpenRun. The identifier is nil when the
    /// server could not read the request.
    case failure(CodexRequestIdentifier?, code: Int, message: String)
    case notification(method: String, parameters: JSONValue)
    /// A request of the server to OpenRun, such as an approval. The server
    /// waits for the answer.
    case request(CodexRequestIdentifier, method: String, parameters: JSONValue)

    /// Nil for a JSON value that is none of the four forms. With its line,
    /// the identifier is the JSON text of the line, exactly.
    init?(_ value: JSONValue, line: [UInt8]? = nil) {
        guard value.object != nil else { return nil }
        let identifierValue = value["id"] ?? .null
        var identifier = CodexRequestIdentifier(identifierValue)
        if let line, identifierValue.number != nil || identifierValue.string != nil {
            identifier = CodexIdentifierToken.find(in: line).flatMap(CodexRequestIdentifier.init(token:))
        }
        guard identifier != nil || identifierValue == .null else { return nil }
        if let method = value["method"]?.string {
            let parameters = value["params"] ?? .null
            if let identifier {
                self = .request(identifier, method: method, parameters: parameters)
            } else {
                self = .notification(method: method, parameters: parameters)
            }
        } else if let error = value["error"], error.object != nil {
            self = .failure(identifier, code: error["code"]?.integer ?? 0, message: error["message"]?.string ?? "")
        } else if let identifier, let result = value["result"] {
            self = .response(identifier, result: result)
        } else {
            return nil
        }
    }
}
