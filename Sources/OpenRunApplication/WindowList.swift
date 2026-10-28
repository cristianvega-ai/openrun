import AppKit
import SessionProtocol
import SessionWindow

/// Keeps each window controller until the user closes its window.
@MainActor
final class WindowList {
    private(set) var controllers: [SessionWindowController] = []
    private let socket: SocketLocation

    init(socket: SocketLocation) { self.socket = socket }

    func open(_ start: SessionStart) {
        let controller = SessionWindowController(start: start, socket: socket)
        controller.onClose = { [weak self, weak controller] in
            guard let controller else { return }
            self?.controllers.removeAll { $0 === controller }
        }
        controllers.append(controller)
        controller.showWindow()
    }

    func closeAll() {
        for controller in controllers { controller.window.close() }
    }
}
