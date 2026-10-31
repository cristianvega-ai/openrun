--------------------------- MODULE AttachSequence ---------------------------
\* A model of one OpenRun Session actor while clients attach, resize, receive
\* output and leave, and of the query reply gate.
\*
\* A Swift actor runs one piece of its code at a time.  This model therefore
\* makes every method of Session one atomic action.  Session.attach has no
\* await inside it, so the whole of it is one step: apply the size, capture
\* the snapshot, send attached and the snapshot, register the client, and
\* announce the size.  The steps that remain are the ones between the
\* methods of Session: output parsing, attach, resize, detach, and the
\* delivery of queued messages to each client.
\*
\* The constant RestoreFailedSize switches one protection of Session.attach.
\*   TRUE   The code has this protection.  A failed attach puts the old
\*          size back, and a size is announced only after a successful
\*          attach.  TLC must find no violation.  The model leaves out the
\*          rare path where the old size cannot be put back: there the new
\*          size stays and is announced (see the comment of Session.attach).
\*   FALSE  A control that removes the protection.  A capture that throws
\*          leaves the new size in place and announces it.  TLC must find
\*          that NoRefusedSize is false.
EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS ClientCount, ChunkCount, OutputLimit, ResizeLimit,
          RestoreFailedSize, RelayingClients, SizeSubscribers, QueryChunks,
          ConfirmingClients, ConfirmResizes, ApplySizeBeforeConfirmation

Clients == 1..ClientCount
Chunks  == 1..ChunkCount
Sizes   == 1..2

\* written   chunks that the program wrote to the pseudo terminal
\* parsed    chunks that the Session actor has parsed and fanned out
\* sessionSize  the one size that the session's terminal and program have
\* attached  clients registered in Session.clients
\* open      clients whose connection is still open
\* attempted clients that sent an attach request
\* queues[client]  messages queued for the client, in order
\* restored  clients that have received their snapshot
\* received[client]  the output chunk numbers that the client has written
\* drawingSize[client]  the size the client lays output out for
\* knownSizes[client]  the sizes that the client has set or learned
\* resizeCount  the number of resizes so far, at most ResizeLimit
\* refusedChangedSize  a failed or refused attach changed the size
\* refusedAnnounced  a failed or refused attach announced a size
\* wrongSizeOrder  an output chunk reached a subscriber before its sizeChanged
\* queryOwners[chunk]  the answerers chosen for the query chunk at parse time
\* replies[chunk]  the answerers that have answered the query chunk
\*                 (0 = session)
\* pendingReplies[client]  the query chunks that the relaying client must
\*                         still answer
VARIABLES written, parsed, sessionSize, attached, open, attempted,
          queues, restored, received, drawingSize, knownSizes, resizeCount,
          refusedChangedSize, refusedAnnounced, wrongSizeOrder,
          queryOwners, replies, pendingReplies, isEnding

variables == <<written, parsed, sessionSize, attached, open, attempted,
               queues, restored, received, drawingSize, knownSizes,
               resizeCount, refusedChangedSize, refusedAnnounced,
               wrongSizeOrder, queryOwners, replies, pendingReplies, isEnding>>

Message(kind, number, dimensions) ==
  [kind |-> kind, number |-> number, dimensions |-> dimensions]

Prefix(count) == [index \in 1..count |-> index]

\* Output messages are the ones that count toward the 8 MiB limit on the
\* process side.  A snapshot does not count (documentation/architecture.md,
\* "Slow clients").
Counted(queue) ==
  Cardinality({index \in 1..Len(queue) : queue[index].kind # "snapshot"})

\* Only these clients use the stored sizes in a guard or a property.
TracksDrawingSize(client) == client \in SizeSubscribers \cup ConfirmingClients
TracksKnownSizes(client) == client \in SizeSubscribers \ ConfirmingClients

InitialState ==
  /\ written = 0
  /\ parsed = 0
  /\ sessionSize = 1
  /\ attached = {}
  /\ open = Clients
  /\ attempted = {}
  /\ queues = [client \in Clients |-> <<>>]
  /\ restored = {}
  /\ received = [client \in Clients |-> <<>>]
  /\ drawingSize = [client \in Clients |-> 1]
  /\ knownSizes = [client \in Clients |-> {1}]
  /\ resizeCount = 0
  /\ refusedChangedSize = FALSE
  /\ refusedAnnounced = FALSE
  /\ wrongSizeOrder = FALSE
  /\ queryOwners = [chunk \in Chunks |-> {}]
  /\ replies = [chunk \in Chunks |-> {}]
  /\ pendingReplies = [client \in Clients |-> {}]
  /\ isEnding = FALSE

\* PseudoTerminal.readAvailableOutput.  The program writes a chunk to the
\* pseudo terminal.  Session.run parses it later, on the actor.
ProgramWrites ==
  /\ written < ChunkCount
  /\ written' = written + 1
  /\ UNCHANGED <<parsed, sessionSize, attached, open, attempted, queues,
       restored, received, drawingSize, knownSizes, resizeCount,
       refusedChangedSize, refusedAnnounced, wrongSizeOrder, queryOwners,
       replies, pendingReplies, isEnding>>

\* Session.run.  The write to the terminal, the reply handler, and the
\* fan-out to every attached client are one actor step.  The loop waits only
\* after the fan-out, in waitForAnswerRoom and Task.yield.
ParseOutput ==
  /\ parsed < written
  /\ ~isEnding
  /\ LET number == parsed + 1
         relays == attached \cap RelayingClients
         isQuery == number \in QueryChunks
         full == {client \in attached : Counted(queues[client]) >= OutputLimit}
         nextQueues == [client \in Clients |->
             IF client \in full THEN <<>>
             ELSE IF client \in attached
             THEN Append(queues[client], Message("output", number, sessionSize))
             ELSE queues[client]]
     IN /\ parsed' = number
        /\ queues' = nextQueues
        /\ attached' = attached \ full
        /\ open' = open \ full
        \* documentation/architecture.md, "Query replies": the decision is
        \* made at the moment the bytes are parsed.  With no relaying client
        \* attached the session answers at once (the handler writes
        \* synchronously).
        /\ queryOwners' = IF isQuery
             THEN [queryOwners EXCEPT ![number] =
                     IF relays = {} THEN {0} ELSE relays]
             ELSE queryOwners
        /\ replies' = IF isQuery /\ relays = {}
             THEN [replies EXCEPT ![number] = {0}]
             ELSE replies
        /\ pendingReplies' = [client \in Clients |->
             IF client \in full THEN {}
             ELSE IF isQuery /\ client \in relays
             THEN pendingReplies[client] \cup {number}
             ELSE pendingReplies[client]]
        /\ UNCHANGED <<written, sessionSize, attempted,
             restored, received, drawingSize, knownSizes, resizeCount,
             refusedChangedSize, refusedAnnounced, wrongSizeOrder, isEnding>>

\* Session.attach, which uses Session.apply and the TerminalSnapshot
\* initializer that captures a terminal.  The whole attach is atomic.
\* The outcome is the result of the apply and the capture:
\*   "success"     the capture returned a snapshot
\*   "nil"         the screen alone does not fit in one frame
\*   "throw"       the capture threw
\*   "applyFailed" the resize of the terminal or of the pseudo terminal threw
\*
\* The name previous is the session size before the attach.  A failed
\* attach must leave it as it was and must not announce a size.
\* documentation/architecture.md, "Attach sequence", says that the other
\* clients get no sizeChanged, because the size did not change in the end.
Attach(client, dimensions, outcome) ==
  /\ client \in open \ attempted
  /\ attempted' = attempted \cup {client}
  /\ LET previous == sessionSize
         success == outcome = "success"
         failedSize ==
           IF outcome \in {"nil", "applyFailed"} THEN previous
           ELSE IF outcome = "throw" /\ RestoreFailedSize THEN previous
           ELSE dimensions
         announces ==
           (success \/ ~RestoreFailedSize) /\ failedSize # previous
         payload ==
           IF success
           THEN <<Message("attached", 0, dimensions),
                  Message("snapshot", parsed, dimensions)>>
           ELSE <<>>
         otherAttached == (attached \cap SizeSubscribers) \ {client}
         didAnnounce == announces /\ otherAttached # {}
         full == IF announces THEN
           {recipient \in otherAttached : Counted(queues[recipient]) >= OutputLimit}
           ELSE {}
     IN /\ sessionSize' = failedSize
        /\ attached' = IF success THEN (attached \ full) \cup {client}
             ELSE attached \ full
        /\ open' = open \ full
        /\ queues' = [recipient \in Clients |->
             IF recipient = client THEN payload
             ELSE IF recipient \in full THEN <<>>
             ELSE IF recipient \in otherAttached /\ announces
                  THEN Append(queues[recipient],
                              Message("size", 0, failedSize))
                  ELSE queues[recipient]]
        /\ refusedChangedSize' =
             (refusedChangedSize \/ (~success /\ failedSize # previous))
        /\ refusedAnnounced' =
             (refusedAnnounced \/ (~success /\ didAnnounce))
        /\ pendingReplies' = [recipient \in Clients |->
             IF recipient \in full THEN {} ELSE pendingReplies[recipient]]
        /\ UNCHANGED <<written, parsed, restored, received,
             drawingSize, knownSizes, resizeCount, wrongSizeOrder, queryOwners,
             replies, isEnding>>

\* A confirming client waits for its ordered size message before it changes
\* its local grid.  Each control removes one of these protections.
\* Session queues the confirmation with the resize, even for the same size.
Resize(client, dimensions) ==
  /\ client \in attached
  /\ (client \notin ConfirmingClients \/ client \in restored)
  /\ resizeCount < ResizeLimit
  /\ LET otherAttached == IF dimensions # sessionSize
                            THEN (attached \cap SizeSubscribers) \ {client}
                            ELSE {}
         confirmation == IF ConfirmResizes /\ client \in ConfirmingClients
                           THEN {client} ELSE {}
         recipients == otherAttached \cup confirmation
         full == {recipient \in recipients :
                    Counted(queues[recipient]) >= OutputLimit}
     IN /\ sessionSize' = dimensions
        /\ resizeCount' = resizeCount + 1
        /\ queues' = [recipient \in Clients |->
             IF recipient \in full THEN <<>>
             ELSE IF recipient \in recipients
                  THEN Append(queues[recipient],
                              Message("size", 0, dimensions))
                  ELSE queues[recipient]]
        /\ attached' = attached \ full
        /\ open' = open \ full
        /\ pendingReplies' = [recipient \in Clients |->
             IF recipient \in full THEN {} ELSE pendingReplies[recipient]]
        /\ drawingSize' = IF TracksDrawingSize(client) /\
             (client \notin ConfirmingClients \/ ApplySizeBeforeConfirmation)
             THEN [drawingSize EXCEPT ![client] = dimensions] ELSE drawingSize
        /\ knownSizes' = IF TracksKnownSizes(client)
             THEN [knownSizes EXCEPT ![client] = @ \cup {dimensions}] ELSE knownSizes
        /\ UNCHANGED <<written, parsed, attempted, restored, received,
             refusedChangedSize, refusedAnnounced, wrongSizeOrder,
             queryOwners, replies, isEnding>>

\* ClientConnection.write.  The serial writer of one client takes the next
\* message.  This is where the client learns a size or receives output.
Deliver(client) ==
  /\ client \in open
  /\ Len(queues[client]) > 0
  /\ LET message == Head(queues[client])
     IN /\ queues' = [queues EXCEPT ![client] = Tail(@)]
        /\ restored' = IF message.kind = "snapshot"
             THEN restored \cup {client} ELSE restored
        /\ received' = IF message.kind = "snapshot"
             THEN [received EXCEPT ![client] = Prefix(message.number)]
             ELSE IF message.kind = "output"
             THEN [received EXCEPT ![client] = Append(@, message.number)]
             ELSE received
        /\ drawingSize' = IF message.kind \in {"snapshot", "size"} /\ TracksDrawingSize(client)
             THEN [drawingSize EXCEPT ![client] = message.dimensions]
             ELSE drawingSize
        /\ knownSizes' = IF message.kind \in {"snapshot", "size"} /\ TracksKnownSizes(client)
             THEN [knownSizes EXCEPT ![client] = @ \cup {message.dimensions}]
             ELSE knownSizes
        /\ wrongSizeOrder' =
             (wrongSizeOrder \/
              (message.kind = "output"
               /\ client \in SizeSubscribers
               /\ IF client \in ConfirmingClients
                     THEN message.dimensions # drawingSize[client]
                     ELSE message.dimensions \notin knownSizes[client]))
        /\ UNCHANGED <<written, parsed, sessionSize, attached, open, attempted,
             resizeCount, refusedChangedSize, refusedAnnounced, queryOwners,
             replies, pendingReplies, isEnding>>

\* SessionServer.serve.  A client leaves, by detach or by disconnect.
\* Session.detach drops it from the client list and updates the reply gate:
\* the gate opens when the client was the last relaying client.
Leave(client) ==
  /\ client \in open
  /\ open' = open \ {client}
  /\ attached' = attached \ {client}
  /\ queues' = [queues EXCEPT ![client] = <<>>]
  /\ pendingReplies' = [pendingReplies EXCEPT ![client] = {}]
  /\ UNCHANGED <<written, parsed, sessionSize, attempted, restored, received,
       drawingSize, knownSizes, resizeCount, refusedChangedSize,
       refusedAnnounced, wrongSizeOrder, queryOwners, replies, isEnding>>

BeginShutdown ==
  /\ ~isEnding
  /\ isEnding' = TRUE
  /\ UNCHANGED <<written, parsed, sessionSize, attached, open, attempted,
       queues, restored, received, drawingSize, knownSizes, resizeCount,
       refusedChangedSize, refusedAnnounced, wrongSizeOrder, queryOwners,
       replies, pendingReplies>>

\* The real terminal of a relaying client answers a query that the session
\* routed to it.  The answer comes back as an input message, which
\* SessionServer.serve passes on.  If the client leaves first, nobody
\* answers.  documentation/architecture.md, "Attaching and detaching while a
\* query is pending", accepts that.
RelayReply(client, chunk) ==
  /\ client \in open
  /\ chunk \in pendingReplies[client]
  /\ replies' = [replies EXCEPT ![chunk] = @ \cup {client}]
  /\ pendingReplies' = [pendingReplies EXCEPT ![client] = @ \ {chunk}]
  /\ UNCHANGED <<written, parsed, sessionSize, attached, open, attempted,
       queues, restored, received, drawingSize, knownSizes, resizeCount,
       refusedChangedSize, refusedAnnounced, wrongSizeOrder, queryOwners, isEnding>>

Next == ProgramWrites \/ ParseOutput \/ BeginShutdown
  \/ (\E client \in Clients, dimensions \in Sizes,
          outcome \in {"success", "nil", "throw", "applyFailed"} :
        Attach(client, dimensions, outcome))
  \/ (\E client \in Clients, dimensions \in Sizes : Resize(client, dimensions))
  \/ (\E client \in Clients : Deliver(client) \/ Leave(client))
  \/ (\E client \in Clients, chunk \in Chunks : RelayReply(client, chunk))

Specification == InitialState /\ [][Next]_variables

\* The agreement control restricts its scenario to a resize while an older
\* foreign size waits in the client's queue.  The protection alone is removed.
StaleForeignControlNext ==
  \/ (\E client \in Clients, dimensions \in Sizes,
          outcome \in {"success", "nil", "throw", "applyFailed"} :
        Attach(client, dimensions, outcome))
  \/ (\E client \in Clients, dimensions \in Sizes :
        /\ Resize(client, dimensions)
        /\ \E index \in 1..Len(queues[client]) :
             /\ queues[client][index].kind = "size"
             /\ queues[client][index].dimensions # dimensions)
  \/ (\E client \in Clients : Deliver(client))

StaleForeignControlSpecification ==
  InitialState /\ [][StaleForeignControlNext]_variables

\* ---------------------------------------------------------------------------
\* The safety properties.
\* ---------------------------------------------------------------------------

\* For every client that has a snapshot, the snapshot prefix plus the output
\* it received is a prefix of the program output.  No gap, no repeat.
ServerCapacity == \A client \in Clients : Counted(queues[client]) <= OutputLimit

NoGapNoRepeat ==
  \A client \in restored :
    /\ received[client] = Prefix(Len(received[client]))
    /\ Len(received[client]) <= parsed

\* A refused or failed attach leaves the session size unchanged and sends no
\* sizeChanged.  The control without RestoreFailedSize makes this false.
NoRefusedSize == ~refusedChangedSize

NoRefusedAnnouncement == ~refusedAnnounced

\* A confirming client uses the size in effect when each output was parsed.
\* A legacy subscriber has learned the size before the output reaches it.
SizeOrder == ~wrongSizeOrder

\* While a relaying client is attached the session process sends no reply.
\* queryOwners[chunk] = {0} records a session reply chosen at parse time, so
\* the invariant says that a session reply is only chosen when no relay is
\* there.
ReplyGate ==
  \A chunk \in Chunks : 0 \in replies[chunk] => queryOwners[chunk] = {0}

\* Each query gets at most one reply in all.  With two relaying clients the
\* design accepts two replies, so that configuration is not checked with
\* this invariant.
SingleReply ==
  \A chunk \in Chunks : Cardinality(replies[chunk]) <= 1

\* A reply comes from an answerer that was chosen for that query.
ReplyOwnership ==
  \A chunk \in Chunks : replies[chunk] \subseteq queryOwners[chunk]

\* When nothing is queued, every attached client that asked for size changes
\* agrees with the session on the size.  This is what two clients of
\* different sizes settle on.
\*
\* The legacy protocol does not promise this.  A client that sends a resize
\* after the attach was applied, but before it receives its snapshot, gets no
\* sizeChanged for it.  So AttachSequenceEarlyResize.cfg expects this
\* property to fail.  Legacy clients send their window size after the restore,
\* but an older foreign size can still arrive after that request.
QuiescentSizeAgreement ==
  (\A client \in Clients : Len(queues[client]) = 0) =>
    (\A client \in attached \cap SizeSubscribers :
       drawingSize[client] = sessionSize)

ConfirmedSizeAgreement ==
  (\A client \in Clients : Len(queues[client]) = 0) =>
    (\A client \in attached \cap ConfirmingClients :
       drawingSize[client] = sessionSize)

\* ---------------------------------------------------------------------------
\* Liveness: a parsed query is answered when nobody can withdraw the answer.
\* Run only with RelayingClients = {}.
\* ---------------------------------------------------------------------------
Fairness ==
  /\ WF_variables(ProgramWrites)
  /\ WF_variables(ParseOutput)
  /\ (\A client \in Clients : WF_variables(Deliver(client)))

LiveSpecification == Specification /\ Fairness

QueryEventuallyAnswered ==
  (parsed >= 2) ~> (replies[2] # {})

=============================================================================
