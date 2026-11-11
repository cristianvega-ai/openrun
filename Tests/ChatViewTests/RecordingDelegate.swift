@testable import ChatView

/// A host that records what the chat asks of it.
@MainActor final class RecordingDelegate: ChatViewControllerDelegate {
    var requests: [String] = []

    func chatViewController(_ controller: ChatViewController, send message: ChatOutgoingMessage) {
        requests.append("send \(message.text) \(message.images.count)")
    }
    func chatViewControllerStop(_ controller: ChatViewController) { requests.append("stop") }
    func chatViewController(_ controller: ChatViewController, answerPermissionRequest identifier: String, with answer: ChatPermissionAnswer) {
        requests.append("answer \(identifier) \(answer)")
    }
    func chatViewController(_ controller: ChatViewController, selectModel identifier: String) { requests.append("model \(identifier)") }
    func chatViewController(_ controller: ChatViewController, selectPermissionMode identifier: String) { requests.append("mode \(identifier)") }
    func chatViewControllerOpenInTerminal(_ controller: ChatViewController) { requests.append("terminal") }
    func chatViewControllerReturnFromTerminal(_ controller: ChatViewController) { requests.append("return") }
    func chatViewControllerLoadEarlierHistory(_ controller: ChatViewController) { requests.append("earlier") }
    func chatViewController(_ controller: ChatViewController, openLink target: String) { requests.append("link \(target)") }
    func chatViewController(_ controller: ChatViewController, startNewThreadOnAccount identifier: String) {
        requests.append("new thread \(identifier)")
    }
}
