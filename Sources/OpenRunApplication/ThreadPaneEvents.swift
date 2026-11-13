import AgentConversation
import AppKit
import ChatView
import SessionConnection
import SessionProtocol

/// The events of the thread on their way into the chat.
extension ThreadPaneController {
    /// Attaches to the thread. The events then come in batches.
    func attach() {
        guard !isClosed else { return }
        // An attach that runs or a live connection takes the request when it ends.
        if attachment != nil || isAttaching { shouldReconnectAfterAttach = true; return }
        isAttaching = true
        // The new connection replays the thread, so the transcript and its history start again.
        historyGeneration = UUID()
        (historyCursor, historyToken, historyPageCount, isLoadingHistory) = (nil, nil, 0, false)
        chat.facts.isLoadingEarlierHistory = false
        (transcript, isReplayComplete) = (Transcript(), false)
        let (socket, thread, connect, batches) = (socket, thread, connect, ThreadEventBatches())
        eventBatches = batches
        work.async { [weak self] in
            let result = Result { try connect(socket, thread) }
            // The pane knows its attachment before the first event of it comes.
            DispatchQueue.main.async { MainActor.assumeIsolated {
                guard let self else {
                    if case .success(let attachment) = result { attachment.shutdown() }
                    return batches.close()
                }
                self.attached(result)
            } }
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
        }
    }

    /// The connection ended. The next overview of the thread attaches again.
    func disconnected() {
        attachment?.shutdown()
        attachment = nil
        eventBatches?.close()
    }

    /// Takes a batch of events. The events before the replay mark build
    /// the transcript, and the chat shows it once at the mark. After it,
    /// each batch updates only the rows that it changed.
    func take(_ events: [ThreadAttachment.Event]) {
        var change = TranscriptChange()
        // An event that changes only the state, such as the end of a turn, changes no row.
        var hasEvent = false
        for event in events {
            switch event {
            case .event(let event):
                hasEvent = true
                let one = transcript.apply(event)
                change.inserted += one.inserted
                change.updated += one.updated
                change.removed += one.removed
            case .replayComplete(let hasEarlierEvents):
                isReplayComplete = true
                chat.facts.hasEarlierHistory = hasEarlierEvents
                chat.show(transcript)
                change = TranscriptChange()
                hasEvent = false
                // After a restart of the session process the thread keeps no
                // events, so its chat starts with the newest turns of the history.
                if hasEarlierEvents, transcript.items.isEmpty { loadEarlierHistory() }
            case .requestFailed(let failure): failed?(failure.message)
            case .failed(let error):
                disconnected()
                failed?("The connection to the thread failed. \(error)")
            case .closed: disconnected()
            case .threadEnded:
                // The thread is gone, so a new attach could only fail.
                disconnected()
                shouldReconnectAfterAttach = false
            case .messageSent: break
            }
        }
        if isReplayComplete, hasEvent { chat.update(transcript, change: change) }
        refreshSignInAdvice()
        if attachment == nil, !isAttaching, shouldReconnectAfterAttach {
            shouldReconnectAfterAttach = false
            attach()
        }
    }
}
