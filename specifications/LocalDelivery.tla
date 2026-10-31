--------------------------- MODULE LocalDelivery ----------------------------
\* One session and its confirming app clients. The server queue counts one
\* unit per control or output message; the snapshot is free. Output and resize
\* production are bounded by the configuration. Each client attaches once.
\* The snapshot represents the prior output as a prefix. Each output frame
\* is one piece. The model assumes successful sizes and a successful attach
\* with an empty initial server queue. It omits byte sizes, queries and input.
\*
\* The local queue includes frames in transit, relay work, and view work.
\* The snapshot is restored before later events. A size follows earlier
\* output. The local queue has no capacity limit.
EXTENDS Naturals, Sequences, FiniteSets, TLC

CONSTANTS ClientNames, OutputCountLimit, ResizeCountLimit, OutputLimit,
          AllowOutOfOrderSize

Clients == ClientNames
\* The clients have the same behavior, so their names can be permuted.
ClientSymmetry == Permutations(Clients)
Sizes == 1..2
Message(kind, number, dimensions) ==
  [kind |-> kind, number |-> number, dimensions |-> dimensions]
Prefix(count) == [index \in 1..count |-> index]
Counted(queue) ==
  Cardinality({index \in 1..Len(queue) : queue[index].kind # "snapshot"})
RemoveAt(queue, index) ==
  SubSeq(queue, 1, index - 1) \o SubSeq(queue, index + 1, Len(queue))

\* accepted and applied record the abstract event order, without attached.
VARIABLES outputCount, resizeCount, sessionSize, open, attempted, attached,
          restored, serverQueues, applicationQueues, accepted, applied,
          appliedOutput, drawingSize, wrongSizeOrder

variables == <<outputCount, resizeCount, sessionSize, open, attempted,
               attached, restored, serverQueues, applicationQueues, accepted,
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
        /\ accepted' = [recipient \in Clients |->
             IF recipient \in recipients \ full THEN Append(accepted[recipient], message)
             ELSE accepted[recipient]]
        /\ UNCHANGED <<outputCount, attempted, restored, applied, appliedOutput,
             drawingSize, wrongSizeOrder>>

Receive(client) ==
  /\ client \in open
  /\ Len(serverQueues[client]) > 0
  /\ LET message == Head(serverQueues[client])
     IN /\ serverQueues' = [serverQueues EXCEPT ![client] = Tail(@)]
        /\ applicationQueues' = IF message.kind = "attached" THEN applicationQueues
             ELSE [applicationQueues EXCEPT ![client] = Append(@, message)]
        /\ UNCHANGED <<outputCount, resizeCount, sessionSize, open, attempted,
             attached, restored, accepted, applied, appliedOutput, drawingSize,
             wrongSizeOrder>>

Apply(client, index) ==
  /\ client \in open
  /\ index \in 1..Len(applicationQueues[client])
  /\ index = 1 \/ (AllowOutOfOrderSize /\ client \in restored /\
       applicationQueues[client][index].kind = "size")
  /\ LET message == applicationQueues[client][index]
     IN /\ applicationQueues' = [applicationQueues EXCEPT ![client] = RemoveAt(@, index)]
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
        /\ UNCHANGED <<outputCount, resizeCount, sessionSize, open, attempted,
             attached, serverQueues, accepted>>

Leave(client) ==
  /\ client \in open
  /\ open' = open \ {client}
  /\ attached' = attached \ {client}
  /\ serverQueues' = [serverQueues EXCEPT ![client] = <<>>]
  /\ applicationQueues' = [applicationQueues EXCEPT ![client] = <<>>]
  /\ UNCHANGED <<outputCount, resizeCount, sessionSize, attempted, restored,
       accepted, applied, appliedOutput, drawingSize, wrongSizeOrder>>

Next == ProduceOutput
  \/ (\E client \in Clients, dimensions \in Sizes :
        Attach(client, dimensions) \/ Resize(client, dimensions))
  \/ (\E client \in Clients : Receive(client) \/ Leave(client))
  \/ (\E client \in Clients :
        \E index \in 1..Len(applicationQueues[client]) : Apply(client, index))

Specification == InitialState /\ [][Next]_variables

ServerCapacity == \A client \in Clients : Counted(serverQueues[client]) <= OutputLimit
NoGapNoRepeat == \A client \in restored :
  /\ appliedOutput[client] = Prefix(Len(appliedOutput[client]))
  /\ Len(appliedOutput[client]) <= outputCount
ApplicationOrder == \A client \in Clients :
  applied[client] = SubSeq(accepted[client], 1, Len(applied[client]))
SizeOrder == ~wrongSizeOrder
ConfirmedSizeAgreement ==
  (\A client \in Clients :
     /\ Len(serverQueues[client]) = 0
     /\ Len(applicationQueues[client]) = 0)
  => (\A client \in attached : drawingSize[client] = sessionSize)

\* Restrict the false claim to a state with pending output. This makes the
\* control show the size marker behind output, not only a frame in transit.
ServerOnlySizeAgreement ==
  /\ (\A client \in Clients : Len(serverQueues[client]) = 0)
  /\ (\E client \in attached :
        \E index \in 1..Len(applicationQueues[client]) :
          applicationQueues[client][index].kind = "output")
  => (\A client \in attached \cap restored : drawingSize[client] = sessionSize)
=============================================================================
