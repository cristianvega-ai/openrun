/// The session process that answers comes from an older build, which has
/// no feed of the sessions, the projects and the settings. The window
/// cannot show its lists until that process ends.
struct OlderSessionProcess: Error, CustomStringConvertible {
    var description: String {
        "The session process that runs is from an older version of OpenRun. End its sessions, or restart the Mac, and open OpenRun again."
    }
}
