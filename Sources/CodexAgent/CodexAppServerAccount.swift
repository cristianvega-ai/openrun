import AgentConversation

/// The account and its usage, which Codex gives at any time without a
/// turn and without a model request.
extension CodexAppServer {
    public func readAccount() async throws -> CodexAccount {
        CodexAccount(answer: try await request("account/read", .object(["refreshToken": .bool(false)])))
    }

    /// The usage of the account, with each window named by its length.
    public func readUsage() async throws -> UsageReading {
        guard let limits = try await request("account/rateLimits/read", .object([:]))["rateLimits"], limits.object != nil else {
            throw CodexRequestError.unexpectedAnswer(method: "account/rateLimits/read")
        }
        return CodexUsage.reading(from: limits)
    }
}
