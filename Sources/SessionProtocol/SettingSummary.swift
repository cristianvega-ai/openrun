/// One setting as the session process tells its clients (decision of
/// 2026-11-10): its name and the text of its value, as `openrun settings`
/// prints and takes them.
///
/// The protocol keeps its own plain type, so a client needs no other module
/// of OpenRun to read it. The text form of each kind of value belongs to
/// the session process.
public struct SettingSummary: Codable, Equatable, Sendable {
    /// Such as `font-size`.
    public var name: String
    /// Such as `13`. A flag is `on` or `off`, and the commands of the
    /// new-session button are one line of JSON.
    public var text: String
    /// Only OpenRun.app may change a protected setting (decision of
    /// 2026-10-27). Every client may read it.
    public var isProtected: Bool

    public init(name: String, text: String, isProtected: Bool) {
        self.name = name
        self.text = text
        self.isProtected = isProtected
    }
}
