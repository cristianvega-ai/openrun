/// Which data can sync later and which stays on its Mac, as the decision of
/// 2026-10-15 asks. The two never share a file, so a later sync takes whole
/// files and never has to pick fields out of a file.
public enum DataFileScope: Hashable, Sendable {
    /// Data that can sync to the other Macs of the user, such as project
    /// names and settings.
    case shared
    /// Data that belongs to this Mac, such as folder paths and sessions.
    case thisMac
}
