import AgentConversation

/// The account that an app-server uses.
///
/// The e-mail address is private. It is for display only: never log it,
/// and never write it to a file. The description leaves it out.
public struct CodexAccount: Sendable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    /// How the account signs in, such as `chatgpt` or `apiKey`.
    public var kind: String?
    /// The plan, such as `plus`.
    public var plan: String?
    public var emailAddress: String?
    /// Whether the user must sign in with `codex login` first.
    public var needsSignIn: Bool

    public init(kind: String? = nil, plan: String? = nil, emailAddress: String? = nil, needsSignIn: Bool = false) {
        self.kind = kind
        self.plan = plan
        self.emailAddress = emailAddress
        self.needsSignIn = needsSignIn
    }

    /// The answer to `account/read`.
    init(answer: JSONValue) {
        let account = answer["account"]
        self.init(
            kind: account?["type"]?.string, plan: account?["planType"]?.string, emailAddress: account?["email"]?.string,
            needsSignIn: account?.object == nil && answer["requiresOpenaiAuth"]?.bool == true)
    }

    public var description: String {
        "CodexAccount(kind: \(kind ?? "none"), plan: \(plan ?? "none"), needsSignIn: \(needsSignIn))"
    }

    public var debugDescription: String { description }
}
