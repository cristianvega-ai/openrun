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
        eventBatches = batches
        work.async { [weak self] in
            let result = Result { try connect(socket, thread) }
            if case .success(let attachment) = result {
                attachment.startReceiving(measuring: { event, size in
                    guard batches.add(event, size: size) else { return }
                    DispatchQueue.main.async { MainActor.assumeIsolated {
                        // A batch of a closed pane, or of an older attach, shows nothing.
                        let events = batches.takeAll()
                        guard let self, !self.isClosed, self.eventBatches === batches else { return }
                        self.take(events)
                    } }
                })
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
                // After a restart of the session process the thread keeps no
                // events, so its chat starts with the newest turns of the history.
                if hasEarlierEvents, transcript.items.isEmpty { loadEarlierHistory() }
            case .requestFailed(let failure): failed?(failure.message)
            case .failed(let error): failed?("The connection to the thread failed. \(error)")
            case .messageSent, .threadEnded, .closed: break
            }
        }
        if isReplayComplete, !change.isEmpty { chat.update(transcript, change: change) }
        refreshSignInAdvice()
    }
}
