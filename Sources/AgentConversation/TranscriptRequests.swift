/// The permission requests and the sub-agent tasks of a transcript.
extension Transcript {
    /// The most messages that one task item keeps. The oldest go first.
    static let taskMessageLimit = 50

    mutating func applyRequestEvent(_ kind: ConversationEventKind, _ change: inout TranscriptChange) {
        let limit = limits.detailByteLimit
        switch kind {
        case .permissionRequested(var request):
            request.input = boundedInput(request.input)
            let identifier = "permission:" + request.identifier
            var isWaiting = true
            update(identifier, create: .permissionRequest(PermissionRequestItem(request: request)), isOpen: true, &change) { content in
                content.modifyPermissionRequest { item in
                    item.request = request
                    isWaiting = item.isWaiting
                }
            }
            if isWaiting { waitingPermissions.insert(identifier) }
        case .permissionEnded(var end):
            end.message = end.message.map { BoundedText.prefix(of: $0, byteLimit: limit) }
            let identifier = "permission:" + end.identifier
            update(identifier, &change) { content in
                content.modifyPermissionRequest { if $0.isWaiting { $0.end = end } }
            }
            waitingPermissions.remove(identifier)
            openItems.remove(identifier)
        case .taskStarted(var start):
            start.description = BoundedText.prefix(of: start.description, byteLimit: limit)
            start.prompt = BoundedText.prefix(of: start.prompt, byteLimit: limit)
            // A message of the task can come before its start.
            let identifier = start.toolCallIdentifier.flatMap { taskItems[$0] } ?? "task:" + start.identifier
            if let call = start.toolCallIdentifier { taskItems[call] = identifier }
            update(identifier, create: .task(TaskItem(start: nil)), &change) { content in
                content.modifyTask { $0.start = start }
            }
        case .taskMessage(let message):
            let identifier = taskItems[message.toolCallIdentifier] ?? "task:" + message.toolCallIdentifier
            taskItems[message.toolCallIdentifier] = identifier
            update(identifier, create: .task(TaskItem(start: nil)), &change) { content in
                content.modifyTask { task in
                    task.messages.append(BoundedText.prefix(of: message.text, byteLimit: limit))
                    if task.messages.count > Self.taskMessageLimit {
                        task.messages.removeFirst()
                        task.removedMessageCount += 1
                    }
                }
            }
        case .taskEnded(var end):
            end.summary = end.summary.map { BoundedText.prefix(of: $0, byteLimit: limit) }
            let byTask = "task:" + end.identifier
            let identifier = storage.contains(byTask) ? byTask : end.toolCallIdentifier.flatMap { taskItems[$0] } ?? byTask
            update(identifier, create: .task(TaskItem(start: nil)), &change) { content in
                content.modifyTask { $0.end = end }
            }
        default:
            break
        }
    }
}
