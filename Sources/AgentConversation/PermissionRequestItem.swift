/// A permission request in a transcript, and how it ended.
public struct PermissionRequestItem: Codable, Sendable, Hashable {
    public var request: PermissionRequest
    /// Nil while the request waits for the user.
    public var end: PermissionEnd?

    public init(request: PermissionRequest, end: PermissionEnd? = nil) {
        self.request = request
        self.end = end
    }

    public var isWaiting: Bool {
        end == nil
    }
}
