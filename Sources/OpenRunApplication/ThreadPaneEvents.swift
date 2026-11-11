import AgentConversation
import AppKit
import ChatView
import SessionConnection
import SessionProtocol

/// The events of the thread on their way into the chat.
extension ThreadPaneController {
    /// Attaches to the thread. The events then come in batches.
    func attach() {
        let (socket, thread, connect, batches) = (socket, thread, connect, ThreadEventBatches())
        work.async { [weak self] in
            let result = Result { try connect(socket, thread) }
            if case .success(let attachment) = result {
                attachment.startReceiving { event in
                    guard batches.add(event) else { return }
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.take(batches.takeAll()) } }
                }
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.attached(result) } }
        }
    }

    /// Takes a batch of events. The events before the replay mark build
    /// the transcript, and the chat shows it once at the mark. After it,
    /// each batch updates only the rows that it changed.
    func take(_ events: [ThreadAttachment.Event]) {
        var change = TranscriptChange()
        for event in events {
            switch event {
            case .event(let event):
                let one = transcript.apply(event)
                change.inserted += one.inserted
                change.updated += one.updated
                change.removed += one.removed
            case .replayComplete(let hasEarlierEvents):
                isReplayComplete = true
                chat.facts.hasEarlierHistory = hasEarlierEvents
                chat.show(transcript)
                change = TranscriptChange()
            case .requestFailed(let failure): failed?(failure.message)
            case .failed(let error): failed?("The connection to the thread failed. \(error)")
            case .messageSent, .threadEnded, .closed: break
            }
        }
        if isReplayComplete, !change.isEmpty { chat.update(transcript, change: change) }
    }
}
