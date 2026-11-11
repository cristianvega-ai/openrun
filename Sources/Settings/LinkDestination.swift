/// Where a link that the user opens from a terminal goes.
public enum LinkDestination: String, CaseIterable, Hashable, Sendable {
    /// The browser that macOS opens for links.
    case defaultBrowser = "default-browser"
    /// A browser split beside the session, in the window of OpenRun.
    case browserSplit = "browser-split"
}
