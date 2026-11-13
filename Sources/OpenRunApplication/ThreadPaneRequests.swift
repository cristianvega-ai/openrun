import AppKit
import ChatView
import SessionConnection
import SessionProtocol

/// The requests of the chat on their way to the session process. The chat
/// changes nothing itself: a new event of the thread shows each result.
extension ThreadPaneController: ChatViewControllerDelegate {
    /// Runs a call that waits for the socket, in order, off the main thread.
    private func send(_ call: @escaping @Sendable (ThreadAttachment) throws -> Void) {
        guard let attachment else { return failed?("The thread is not connected yet. Try again in a moment.") ?? () }
        messageWork.async { [weak self] in
            do { try call(attachment) } catch {
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.failed?("The request did not reach the thread. \(error)") } }
            }
        }
    }

    func chatViewController(_ controller: ChatViewController, send message: ChatOutgoingMessage) {
        let images = message.images.map { ThreadImage(mediaType: $0.mediaType, data: $0.data) }
        send { try $0.send(message: message.text, images: images) }
    }

    func chatViewControllerStop(_ controller: ChatViewController) {
        send { try $0.stop() }
    }

    func chatViewController(_ controller: ChatViewController, answerPermissionRequest identifier: String, with answer: ChatPermissionAnswer) {
        let (socket, thread) = (socket, thread)
        // An answer keeps its place among the messages and the stops.
        messageWork.async { [weak self] in
            do {
                let client = try SessionClient(location: socket)
                switch answer {
                case .allow: try client.answerToolPermission(thread: thread, request: identifier, allows: true)
                case .deny(let message): try client.answerToolPermission(thread: thread, request: identifier, allows: false, message: message)
                }
            } catch {
                DispatchQueue.main.async { MainActor.assumeIsolated {
                    self?.chat.retryPermissionAnswer(identifier)
                    self?.failed?("The answer did not reach the thread. \(error)")
                } }
            }
        }
    }

    /// A link in the text of an agent opens only as a web address: in a
    /// web page of the row when the host takes it, or else with the
    /// default program.
    func chatViewController(_ controller: ChatViewController, openLink target: String) {
        guard let url = URL(string: target), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        if webLinkAction?(url) != true { NSWorkspace.shared.open(url) }
    }

    func chatViewController(_ controller: ChatViewController, selectModel identifier: String) {
        change { try $0.changeThread($1, model: identifier) }
    }

    /// The session process refuses a mode that is wider than the setting allows.
    func chatViewController(_ controller: ChatViewController, selectPermissionMode identifier: String) {
        change { try $0.changeThread($1, permissionMode: identifier) }
    }

    /// Sends a change of the thread on a connection of its own, in order
    /// and off the main thread. The feed brings the new facts.
    private func change(_ call: @escaping @Sendable (SessionClient, UUID) throws -> Void) {
        let (socket, thread) = (socket, thread)
        work.async { [weak self] in
            do { try call(try SessionClient(location: socket), thread) } catch {
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.failed?("\(error)") } }
            }
        }
    }

    func chatViewControllerLoadEarlierHistory(_ controller: ChatViewController) {
        loadEarlierHistory()
    }

    // These parts of the chat arrive with later work on the threads.
    func chatViewControllerOpenInTerminal(_ controller: ChatViewController) {
        openInTerminal?()
    }

    func chatViewControllerReturnFromTerminal(_ controller: ChatViewController) {
        returnFromTerminal?()
    }

    func chatViewController(_ controller: ChatViewController, startNewThreadOnAccount identifier: String) {
        continueOnAccount?(identifier)
    }
}
