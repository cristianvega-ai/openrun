/// What the chat asks of its host. The chat changes nothing itself: the
/// host sends each request to the session process, and a new transcript or
/// new facts come back.
@MainActor public protocol ChatViewControllerDelegate: AnyObject {
    func chatViewController(_ controller: ChatViewController, send message: ChatOutgoingMessage)
    /// Stops the turn that runs.
    func chatViewControllerStop(_ controller: ChatViewController)
    /// - Parameter identifier: The identifier of the `PermissionRequest`.
    func chatViewController(_ controller: ChatViewController, answerPermissionRequest identifier: String, with answer: ChatPermissionAnswer)
    func chatViewController(_ controller: ChatViewController, selectModel identifier: String)
    /// The identifier is one of the facts' permission modes, so it is never
    /// wider than the present mode.
    func chatViewController(_ controller: ChatViewController, selectPermissionMode identifier: String)
    func chatViewControllerOpenInTerminal(_ controller: ChatViewController)
    func chatViewControllerReturnFromTerminal(_ controller: ChatViewController)
    /// The user reached the top while the agent's history holds more.
    func chatViewControllerLoadEarlierHistory(_ controller: ChatViewController)
    /// The user clicked a link. The target is the text of the link, which
    /// an agent wrote, so the host asks first for a scheme other than
    /// `http` and `https`, as the terminal does.
    func chatViewController(_ controller: ChatViewController, openLink target: String)
    /// The user chose a new thread on another account after a limit.
    func chatViewController(_ controller: ChatViewController, startNewThreadOnAccount identifier: String)
}
