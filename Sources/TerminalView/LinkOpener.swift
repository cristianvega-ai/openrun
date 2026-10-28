import AppKit

/// Opens a link. A test gives another one, so it does not open a real link.
@MainActor
protocol LinkOpener: AnyObject {
    func open(_ target: URL)
}

/// Opens a link with the default program of macOS for it.
@MainActor
final class WorkspaceLinkOpener: LinkOpener {
    func open(_ target: URL) {
        NSWorkspace.shared.open(target)
    }
}
