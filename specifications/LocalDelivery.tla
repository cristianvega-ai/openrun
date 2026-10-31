--------------------------- MODULE LocalDelivery ----------------------------
\* One session and its confirming app clients. The server queue counts one
\* unit per control or output message; the snapshot is free. Output and resize
\* production are bounded by the configuration. Each client attaches once.
\* The snapshot represents the prior output as a prefix. Each output frame
\* is one piece. The model assumes successful sizes and a successful attach
\* with an empty initial server queue. It omits byte sizes, queries and input.
\*
\* One receiver can hold one frame while the relay waits for room. Relay
\* admission lasts until the view applies the event. A read that has room
\* admits the frame in the same step; only a blocked read needs a separate
\* state. The snapshot is restored
\* before later events. One oversized output may enter an empty relay. An
\* end event follows the earlier output; closing a window discards it all.
EXTENDS Naturals, Sequences, FiniteSets, TLC

CONSTANTS ClientNames, OutputCountLimit, ResizeCountLimit, OutputLimit,
          LocalEventLimit, LocalByteLimit, AllowOutOfOrderSize

Clients == ClientNames
\* The clients have the same behavior, so their names can be permuted.
ClientSymmetry == Permutations(Clients)
Sizes == 1..2
Message(kind, number, dimensions) ==
  [kind |-> kind, number |-> number, dimensions |-> dimensions]
Prefix(count) == [index \in 1..count |-> index]
Counted(queue) ==
  Cardinality({index \in 1..Len(queue) :
    queue[index].kind \notin {"snapshot", "end"}})
RelayCount(queue) ==
  Cardinality({index \in 1..Len(queue) : queue[index].kind # "snapshot"})
FrameBytes(message) ==
  IF message.kind = "output" THEN 1 + (message.number % 3) ELSE 0
RECURSIVE QueueBytes(_)
QueueBytes(queue) ==
  IF Len(queue) = 0 THEN 0 ELSE FrameBytes(Head(queue)) + QueueBytes(Tail(queue))
RemoveAt(queue, index) ==
  SubSeq(queue, 1, index - 1) \o SubSeq(queue, index + 1, Len(queue))

\* accepted and applied record the abstract event order, without attached.
VARIABLES outputCount, resizeCount, sessionSize, open, attempted, attached,
          restored, serverQueues, receivedFrames, applicationQueues, accepted, applied,
          appliedOutput, drawingSize, wrongSizeOrder

variables == <<outputCount, resizeCount, sessionSize, open, attempted,
               attached, restored, serverQueues, receivedFrames, applicationQueues, accepted,
               applied, appliedOutput, drawingSize, wrongSizeOrder>>

InitialState ==
  /\ outputCount = 0
  /\ resizeCount = 0
  /\ sessionSize = 1
  /\ open = Clients
  /\ attempted = {}
  /\ attached = {}
  /\ restored = {}
  /\ serverQueues = [client \in Clients |-> <<>>]
  /\ receivedFrames = [client \in Clients |-> <<>>]
  /\ applicationQueues = [client \in Clients |-> <<>>]
  /\ accepted = [client \in Clients |-> <<>>]
  /\ applied = [client \in Clients |-> <<>>]
  /\ appliedOutput = [client \in Clients |-> <<>>]
  /\ drawingSize = [client \in Clients |-> 1]
  /\ wrongSizeOrder = FALSE

\* Each counted message costs one unit. A full server queue closes that
\* client; local backlog never contributes to the server capacity check.
Full(recipients) ==
  {client \in recipients : Counted(serverQueues[client]) >= OutputLimit}

Attach(client, dimensions) ==
  /\ client \in open \ attempted
  /\ LET others == IF dimensions # sessionSize THEN attached ELSE {}
         full == Full(others)
         snapshot == Message("snapshot", outputCount, dimensions)
         size == Message("size", 0, dimensions)
     IN /\ sessionSize' = dimensions
        /\ attempted' = attempted \cup {client}
        /\ open' = open \ full
        /\ attached' = (attached \ full) \cup {client}
        /\ serverQueues' = [recipient \in Clients |->
             IF recipient = client
             THEN <<Message("attached", 0, dimensions), snapshot>>
             ELSE IF recipient \in full THEN <<>>
             ELSE IF recipient \in others THEN Append(serverQueues[recipient], size)
             ELSE serverQueues[recipient]]
        /\ applicationQueues' = [recipient \in Clients |->
             IF recipient \in full THEN <<>> ELSE applicationQueues[recipient]]
        /\ receivedFrames' = [recipient \in Clients |->
             IF recipient \in full THEN <<>> ELSE receivedFrames[recipient]]
        /\ accepted' = [recipient \in Clients |->
             IF recipient = client THEN <<snapshot>>
             ELSE IF recipient \in others \ full THEN Append(accepted[recipient], size)
             ELSE accepted[recipient]]
        /\ UNCHANGED <<outputCount, resizeCount, restored, applied,
             appliedOutput, drawingSize, wrongSizeOrder>>

ProduceOutput ==
  /\ outputCount < OutputCountLimit
  /\ LET message == Message("output", outputCount + 1, sessionSize)
         full == Full(attached)
     IN /\ outputCount' = outputCount + 1
        /\ open' = open \ full
        /\ attached' = attached \ full
        /\ serverQueues' = [client \in Clients |->
             IF client \in full THEN <<>>
             ELSE IF client \in attached THEN Append(serverQueues[client], message)
             ELSE serverQueues[client]]
        /\ applicationQueues' = [client \in Clients |->
             IF client \in full THEN <<>> ELSE applicationQueues[client]]
        /\ receivedFrames' = [client \in Clients |->
             IF client \in full THEN <<>> ELSE receivedFrames[client]]
        /\ accepted' = [client \in Clients |->
             IF client \in attached \ full THEN Append(accepted[client], message)
             ELSE accepted[client]]
        /\ UNCHANGED <<resizeCount, sessionSize, attempted, restored, applied,
             appliedOutput, drawingSize, wrongSizeOrder>>

Resize(client, dimensions) ==
  /\ client \in attached \cap restored
  /\ resizeCount < ResizeCountLimit
  /\ LET recipients == IF dimensions # sessionSize THEN attached ELSE {client}
         message == Message("size", 0, dimensions)
         full == Full(recipients)
     IN /\ resizeCount' = resizeCount + 1
        /\ sessionSize' = dimensions
        /\ open' = open \ full
        /\ attached' = attached \ full
        /\ serverQueues' = [recipient \in Clients |->
             IF recipient \in full THEN <<>>
             ELSE IF recipient \in recipients THEN Append(serverQueues[recipient], message)
             ELSE serverQueues[recipient]]
        /\ applicationQueues' = [recipient \in Clients |->
             IF recipient \in full THEN <<>> ELSE applicationQueues[recipient]]
        /\ receivedFrames' = [recipient \in Clients |->
             IF recipient \in full THEN <<>> ELSE receivedFrames[recipient]]
        /\ accepted' = [recipient \in Clients |->
             IF recipient \in recipients \ full THEN Append(accepted[recipient], message)
             ELSE accepted[recipient]]
        /\ UNCHANGED <<outputCount, attempted, restored, applied, appliedOutput,
             drawingSize, wrongSizeOrder>>

CanAdmit(client, message) ==
  LET queue == applicationQueues[client]
  IN message.kind \in {"attached", "snapshot"} \/
       /\ RelayCount(queue) < LocalEventLimit
       /\ (RelayCount(queue) = 0 \/
            QueueBytes(queue) + FrameBytes(message) <= LocalByteLimit)

Receive(client) ==
  /\ client \in open
  /\ Len(serverQueues[client]) > 0
  /\ Len(receivedFrames[client]) = 0
  /\ LET message == Head(serverQueues[client])
     IN /\ message.kind \in {"attached", "snapshot"} \/ client \in restored
        /\ serverQueues' = [serverQueues EXCEPT ![client] = Tail(@)]
        /\ receivedFrames' = IF CanAdmit(client, message) THEN receivedFrames
             ELSE [receivedFrames EXCEPT ![client] = <<message>>]
        /\ applicationQueues' = IF CanAdmit(client, message) /\ message.kind # "attached"
             THEN [applicationQueues EXCEPT ![client] = Append(@, message)]
             ELSE applicationQueues
        /\ UNCHANGED <<outputCount, resizeCount, sessionSize, open, attempted,
             attached, restored, accepted, applied, appliedOutput, drawingSize,
             wrongSizeOrder>>

Admit(client) ==
  /\ client \in open
  /\ Len(receivedFrames[client]) = 1
  /\ LET message == Head(receivedFrames[client])
     IN /\ CanAdmit(client, message)
        /\ receivedFrames' = [receivedFrames EXCEPT ![client] = <<>>]
        /\ applicationQueues' = IF message.kind = "attached" THEN applicationQueues
             ELSE [applicationQueues EXCEPT ![client] = Append(@, message)]
        /\ UNCHANGED <<outputCount, resizeCount, sessionSize, open, attempted,
             attached, restored, serverQueues, accepted, applied, appliedOutput,
             drawingSize, wrongSizeOrder>>

Apply(client, index) ==
  /\ client \in open
  /\ index \in 1..Len(applicationQueues[client])
  /\ index = 1 \/ (AllowOutOfOrderSize /\ client \in restored /\
       applicationQueues[client][index].kind = "size")
  /\ LET message == applicationQueues[client][index]
     IN /\ applicationQueues' = [applicationQueues EXCEPT ![client] = RemoveAt(@, index)]
        /\ open' = IF message.kind = "end" THEN open \ {client} ELSE open
        /\ applied' = [applied EXCEPT ![client] = Append(@, message)]
        /\ restored' = IF message.kind = "snapshot" THEN restored \cup {client}
             ELSE restored
        /\ appliedOutput' = IF message.kind = "snapshot"
             THEN [appliedOutput EXCEPT ![client] = Prefix(message.number)]
             ELSE IF message.kind = "output"
             THEN [appliedOutput EXCEPT ![client] = Append(@, message.number)]
             ELSE appliedOutput
        /\ drawingSize' = IF message.kind \in {"snapshot", "size"}
             THEN [drawingSize EXCEPT ![client] = message.dimensions]
             ELSE drawingSize
        /\ wrongSizeOrder' = wrongSizeOrder \/
             (message.kind = "output" /\ message.dimensions # drawingSize[client])
        /\ UNCHANGED <<outputCount, resizeCount, sessionSize, attempted,
             attached, serverQueues, receivedFrames, accepted>>

\* Exit and connection-end events wait behind the output that arrived first.
EndDelivery(client) ==
  /\ client \in attached
  /\ LET message == Message("end", 0, sessionSize)
     IN /\ attached' = attached \ {client}
        /\ serverQueues' = [serverQueues EXCEPT ![client] = Append(@, message)]
        /\ accepted' = [accepted EXCEPT ![client] = Append(@, message)]
        /\ UNCHANGED <<outputCount, resizeCount, sessionSize, open, attempted,
             restored, receivedFrames, applicationQueues, applied, appliedOutput,
             drawingSize, wrongSizeOrder>>

Leave(client) ==
  /\ client \in open
  /\ open' = open \ {client}
  /\ attached' = attached \ {client}
  /\ serverQueues' = [serverQueues EXCEPT ![client] = <<>>]
  /\ receivedFrames' = [receivedFrames EXCEPT ![client] = <<>>]
  /\ applicationQueues' = [applicationQueues EXCEPT ![client] = <<>>]
  /\ UNCHANGED <<outputCount, resizeCount, sessionSize, attempted, restored,
       accepted, applied, appliedOutput, drawingSize, wrongSizeOrder>>

Next == ProduceOutput
  \/ (\E client \in Clients, dimensions \in Sizes :
        Attach(client, dimensions) \/ Resize(client, dimensions))
  \/ (\E client \in Clients :
        Receive(client) \/ Admit(client) \/ EndDelivery(client) \/ Leave(client))
  \/ (\E client \in Clients :
        \E index \in 1..Len(applicationQueues[client]) : Apply(client, index))

Specification == InitialState /\ [][Next]_variables

ServerCapacity == \A client \in Clients : Counted(serverQueues[client]) <= OutputLimit
ApplicationCapacity == \A client \in Clients :
  /\ RelayCount(applicationQueues[client]) <= LocalEventLimit
  /\ QueueBytes(applicationQueues[client]) <= LocalByteLimit \/
       RelayCount(applicationQueues[client]) = 1
ReceiverCapacity == \A client \in Clients : Len(receivedFrames[client]) <= 1
ClosedQueuesEmpty == \A client \in Clients \ open :
  /\ serverQueues[client] = <<>>
  /\ receivedFrames[client] = <<>>
  /\ applicationQueues[client] = <<>>
NoGapNoRepeat == \A client \in restored :
  /\ appliedOutput[client] = Prefix(Len(appliedOutput[client]))
  /\ Len(appliedOutput[client]) <= outputCount
ApplicationOrder == \A client \in Clients :
  applied[client] = SubSeq(accepted[client], 1, Len(applied[client]))
SizeOrder == ~wrongSizeOrder
ConfirmedSizeAgreement ==
  (\A client \in Clients :
     /\ Len(serverQueues[client]) = 0
     /\ Len(receivedFrames[client]) = 0
     /\ Len(applicationQueues[client]) = 0)
  => (\A client \in attached : drawingSize[client] = sessionSize)

\* Restrict the false claim to a state with pending output. This makes the
\* control show the size marker behind output, not only a frame in transit.
ServerOnlySizeAgreement ==
  /\ (\A client \in Clients : Len(serverQueues[client]) = 0)
  /\ (\A client \in Clients : Len(receivedFrames[client]) = 0)
  /\ (\E client \in attached :
        \E index \in 1..Len(applicationQueues[client]) :
          applicationQueues[client][index].kind = "output")
  => (\A client \in attached \cap restored : drawingSize[client] = sessionSize)
=============================================================================
