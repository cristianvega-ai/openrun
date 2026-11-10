----------------------------- MODULE ResizeWait -----------------------------
\* A bounded model of the proposed line-editor resize protocol. The program,
\* the session screen, and each following client have separate sizes. The
\* model covers the wait for a redraw, coalesced resizes, confirmations,
\* timeout, editing end, attach, failed attach, disconnect, output and a size
\* query. AttachSequence checks the wider attach and backpressure protocol.
\*
\* This describes the intended behavior, not a proof that the Swift code
\* implements it. In particular, correct editor detection, fresh redraw
\* attribution, and correct size answers are requirements. Their negative
\* controls show the behavior without those protections. The model abstracts
\* screen changes as an ordered trace; it does not parse terminal bytes or
\* decide whether a cell is styled.
\* A successful rollback restores that trace. The model does not prove that
\* libghostty-vt reflow is reversible.
EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS ClientCount, InitialAttachedCount, WidthCount, RowCount, RequestLimit,
          OutputLimit, QueryLimit, AttachLimit

\* Each definition is a protection or requirement. A control overrides one
\* definition, so TLC must find a named violation without that protection.
CorrectEditorDetection == TRUE
CorrectQuerySize == TRUE
KeepConfirmations == TRUE
SendCursorRule == TRUE
KeepNewestRequest == TRUE
BreakOnlyAfterErase == TRUE
SendEraseBeforeSize == TRUE
EnableTimeout == TRUE
WaitForRows == FALSE
RejectStaleTimeout == TRUE
RejectBufferedErase == TRUE
EnableOutputResume == TRUE
IgnoreZeroDuringWait == TRUE
KeepOldWidthWhileWaiting == TRUE
RestoreProgramOnResizeFailure == TRUE

Clients == 1..ClientCount
Sizes == [columns : 1..WidthCount, rows : 1..RowCount]
InitialSize == [columns |-> 1, rows |-> 1]
Modes == {"editor", "script", "other"}
Outcomes == {"success", "refused", "rollback", "rollbackFailure"}

NoSize == [columns |-> 0, rows |-> 0]
NoRequest == [number |-> 0, client |-> 0, size |-> NoSize, confirms |-> FALSE,
              origin |-> "other", previousSize |-> NoSize, late |-> FALSE]
Request(number, client, size, confirms, origin, previousSize) ==
  [number |-> number, client |-> client, size |-> size, confirms |-> confirms,
   origin |-> origin, previousSize |-> previousSize, late |-> FALSE]
Obligation(number, client) == [number |-> number, client |-> client]
OutputOperation(number) == [kind |-> "output", number |-> number, size |-> 0, keeps |-> "plain"]
SizeOperation(size, keeps) == [kind |-> "size", number |-> 0, size |-> size, keeps |-> keeps]
Message(kind, number, size, keeps, confirmation, snapshot) ==
  [kind |-> kind, number |-> number, size |-> size, keeps |-> keeps,
   confirmation |-> confirmation, snapshot |-> snapshot]
OutputMessage(number) == Message("output", number, 0, "plain", 0, <<>>)
SizeMessage(size, keeps, confirmation) == Message("size", 0, size, keeps, confirmation, <<>>)
SnapshotMessage(size, snapshot) == Message("snapshot", 0, size, FALSE, 0, snapshot)

\* A trace records only the ordering of screen changes and what each size
\* change keeps of the prompt: "plain", "cursorRow" or "promptRows".
ResizedTrace(trace, previous, size, keeps) ==
  IF previous = size THEN trace ELSE Append(trace, SizeOperation(size, keeps))

VARIABLES open, attached, following, programSize, screenSize, screenTrace,
          clientSize, clientTrace, queues, mode, active, pending, owed,
          unanswered, requestCount, outputCount, queryCount, wrongQuery,
          wrongRedrawSize, wrongCursorRule, latestSize, latestValidRequestNumber, attachCount,
          attaching, attachSize, attachOutcome, attachPhase, previousSize,
          previousTrace, ended, lastWaitNumber, scheduledTimeouts, wrongTimeout,
          bufferedErase, wrongRedrawAttribution, outputPaused, lastPauseOutput, lateAnswer

variables == <<open, attached, following, programSize, screenSize, screenTrace,
               clientSize, clientTrace, queues, mode, active, pending, owed,
               unanswered, requestCount, outputCount, queryCount, wrongQuery,
               wrongRedrawSize, wrongCursorRule, latestSize, latestValidRequestNumber, attachCount,
               attaching, attachSize, attachOutcome, attachPhase, previousSize,
               previousTrace, ended, lastWaitNumber, scheduledTimeouts, wrongTimeout,
               bufferedErase, wrongRedrawAttribution, outputPaused, lastPauseOutput, lateAnswer>>

timingVariables == <<lastWaitNumber, scheduledTimeouts, wrongTimeout>>
\* lateAnswer: the shell still owes the answer to a size that passed its
\* time limit. A newer wait must not take that answer as its own.
bufferVariables == <<bufferedErase, wrongRedrawAttribution, lateAnswer>>
outputFlowVariables == <<outputPaused, lastPauseOutput>>

InitialState ==
  /\ open = Clients
  /\ attached = 1..InitialAttachedCount
  /\ following = 1..InitialAttachedCount
  /\ programSize = InitialSize
  /\ screenSize = InitialSize
  /\ screenTrace = <<>>
  /\ clientSize = [client \in Clients |-> InitialSize]
  /\ clientTrace = [client \in Clients |-> <<>>]
  /\ queues = [client \in Clients |-> <<>>]
  /\ mode \in Modes
  /\ active = NoRequest
  /\ pending = NoRequest
  /\ owed = {}
  /\ unanswered = {}
  /\ requestCount = 0
  /\ outputCount = 0
  /\ queryCount = 0
  /\ wrongQuery = FALSE
  /\ wrongRedrawSize = FALSE
  /\ wrongCursorRule = FALSE
  /\ latestSize = InitialSize
  /\ latestValidRequestNumber = 0
  /\ attachCount = 0
  /\ attaching = 0
  /\ attachSize = InitialSize
  /\ attachOutcome = "refused"
  /\ attachPhase = "none"
  /\ previousSize = InitialSize
  /\ previousTrace = <<>>
  /\ ended = FALSE
  /\ lastWaitNumber = 0
  /\ scheduledTimeouts = {}
  /\ wrongTimeout = FALSE
  /\ bufferedErase = FALSE
  /\ wrongRedrawAttribution = FALSE
  /\ lateAnswer = FALSE
  /\ outputPaused = FALSE
  /\ lastPauseOutput = 0

\* All attached screen followers receive program output in order.
OutputQueues(oldQueues, number) ==
  [client \in Clients |->
    IF client \in attached THEN Append(oldQueues[client], OutputMessage(number))
    ELSE oldQueues[client]]

\* The requester gets its own message only when it requested confirmation.
SizeQueues(oldQueues, request, previous, size, keeps) ==
  [client \in Clients |->
    IF client \in attached /\
       ((client # request.client /\ previous # size) \/
        (client = request.client /\ request.confirms))
    THEN Append(oldQueues[client],
      SizeMessage(size, IF SendCursorRule THEN keeps ELSE "plain",
                  IF client = request.client /\ request.confirms
                  THEN request.number ELSE 0))
    ELSE oldQueues[client]]

\* A client whose confirmed request was replaced hears the final size. A
\* newer confirmed request by that client can answer for the earlier one.
OwedQueues(oldQueues, clients, size, keeps) ==
  [client \in Clients |->
    IF client \in clients \cap attached
    THEN Append(oldQueues[client],
      SizeMessage(size, IF SendCursorRule THEN keeps ELSE "plain", requestCount))
    ELSE oldQueues[client]]

WaitsForEditor(size) ==
  (size.columns # screenSize.columns \/ (WaitForRows /\ size.rows # screenSize.rows)) /\
  (mode = "editor" \/ (~CorrectEditorDetection /\ mode = "script"))

\* The foreground and bracketed-paste state can change before the output
\* that ends editing is parsed. A pending resize uses the later state.
ChangeMode(nextMode) ==
  /\ ~ended /\ attaching = 0 /\ (active # NoRequest \/ pending = NoRequest)
  /\ nextMode \in Modes /\ nextMode # mode
  /\ mode' = nextMode
  /\ UNCHANGED <<open, attached, following, programSize, screenSize, screenTrace,
       clientSize, clientTrace, queues, active, pending, owed, unanswered,
       requestCount, outputCount, queryCount, wrongQuery, wrongRedrawSize,
       wrongCursorRule, latestSize, latestValidRequestNumber, attachCount, attaching, attachSize,
       attachOutcome, attachPhase, previousSize, previousTrace, ended>>
  /\ UNCHANGED timingVariables
  /\ UNCHANGED bufferVariables
  /\ UNCHANGED outputFlowVariables

\* A request during the wait replaces the pending request. An unconfirmed
\* requester is not assumed to follow the session's ordered screen protocol.
RequestResize(client, size, confirms) ==
  /\ ~ended /\ attaching = 0 /\ client \in attached
  /\ requestCount < RequestLimit /\ size \in Sizes \cup {NoSize} /\ confirms \in BOOLEAN
  /\ (size # NoSize \/ ~confirms)
  /\ (active # NoRequest \/ pending = NoRequest)
  /\ LET request == Request(requestCount + 1, client, size, confirms, mode, screenSize)
         valid == size # NoSize
         ignored == ~valid /\ (active = NoRequest \/ IgnoreZeroDuringWait)
         replacedClients == IF pending # NoRequest /\ pending.confirms /\ pending.client # 0
                            THEN {pending.client} ELSE {}
         newOwed == (owed \cup (IF KeepConfirmations THEN replacedClients ELSE {})) \
                    (IF confirms THEN {client} ELSE {})
         beginsWait == valid /\ active = NoRequest /\ WaitsForEditor(size)
         immediate == valid /\ active = NoRequest /\ ~beginsWait
         early == beginsWait /\ ~KeepOldWidthWhileWaiting
         sent == IF immediate \/ early THEN SizeQueues(queues, request, screenSize, size, "plain") ELSE queues
     IN /\ requestCount' = requestCount + 1
        /\ latestSize' = IF valid THEN size ELSE latestSize
        /\ latestValidRequestNumber' = IF valid THEN request.number ELSE latestValidRequestNumber
        /\ following' = IF confirms \/ ~valid THEN following ELSE following \ {client}
        /\ unanswered' = IF confirms THEN unanswered \cup {Obligation(request.number, client)} ELSE unanswered
        /\ active' = IF beginsWait THEN request ELSE active
        /\ pending' = IF active # NoRequest /\ ~ignored
             THEN IF KeepNewestRequest \/ pending = NoRequest THEN request ELSE pending
             ELSE pending
        /\ owed' = IF active # NoRequest /\ ~ignored THEN newOwed ELSE owed
        /\ programSize' = IF beginsWait \/ immediate THEN size ELSE programSize
        /\ screenSize' = IF immediate \/ early THEN size ELSE screenSize
        /\ screenTrace' = IF immediate \/ early THEN ResizedTrace(screenTrace, screenSize, size, "plain") ELSE screenTrace
        /\ queues' = sent
        /\ lastWaitNumber' = IF beginsWait THEN lastWaitNumber + 1 ELSE lastWaitNumber
        /\ scheduledTimeouts' = IF beginsWait THEN scheduledTimeouts \cup {lastWaitNumber + 1} ELSE scheduledTimeouts
        /\ UNCHANGED wrongTimeout
        /\ UNCHANGED bufferVariables
        /\ UNCHANGED outputFlowVariables
        /\ UNCHANGED <<open, attached, clientSize, clientTrace, mode, outputCount,
             queryCount, wrongQuery, wrongRedrawSize, wrongCursorRule, attachCount,
             attaching, attachSize, attachOutcome, attachPhase, previousSize,
             previousTrace, ended>>

\* The shell's erase is output at the old width. The session then sends the
\* size marker. A later output step is at the new width. A timeout or an
\* attach comes before the answer, so it keeps the rows of the prompt. An end
\* of editing uses a plain resize.
ResolveWait(reason, includesErase, timeoutNumber) ==
  /\ ~ended /\ active # NoRequest
  /\ reason \in {"redraw", "bufferedErase", "timeout", "editingEnd", "attach"}
  /\ IF reason = "attach" THEN attaching # 0 ELSE attaching = 0
  /\ (reason \notin {"redraw", "bufferedErase"} \/ active.origin = "editor")
  /\ (reason # "redraw" \/ ~bufferedErase)
  /\ (reason # "bufferedErase" \/ (bufferedErase /\ ~RejectBufferedErase))
  /\ (reason \in {"timeout", "attach"} \/ ~outputPaused)
  /\ (reason # "timeout" \/ EnableTimeout)
  /\ (reason # "timeout" \/ timeoutNumber \in scheduledTimeouts)
  /\ includesErase \in BOOLEAN
  /\ includesErase => (reason \in {"redraw", "bufferedErase"} /\ outputCount < OutputLimit)
  /\ LET keeps == IF reason \in {"redraw", "bufferedErase"} \/ ~BreakOnlyAfterErase THEN "cursorRow"
                  ELSE IF reason \in {"timeout", "attach"} THEN "promptRows" ELSE "plain"
         number == outputCount + 1
         beforeTrace == IF includesErase THEN Append(screenTrace, OutputOperation(number)) ELSE screenTrace
         beforeQueues == IF includesErase /\ SendEraseBeforeSize THEN OutputQueues(queues, number) ELSE queues
         sent == SizeQueues(beforeQueues, active, screenSize, active.size, keeps)
         afterQueues == IF includesErase /\ ~SendEraseBeforeSize THEN OutputQueues(sent, number) ELSE sent
         finalQueues == IF pending = NoRequest THEN OwedQueues(afterQueues, owed, active.size, keeps) ELSE afterQueues
     IN /\ screenTrace' = ResizedTrace(beforeTrace, screenSize, active.size, keeps)
        /\ screenSize' = active.size
        /\ queues' = finalQueues
        /\ outputCount' = IF includesErase THEN number ELSE outputCount
        /\ wrongRedrawSize' = (wrongRedrawSize \/ (reason = "redraw" /\ screenSize # active.previousSize))
        /\ wrongCursorRule' = (wrongCursorRule \/ (reason \notin {"redraw", "bufferedErase"} /\ keeps = "cursorRow"))
        /\ wrongRedrawAttribution' = (wrongRedrawAttribution \/ reason = "bufferedErase")
        /\ bufferedErase' = IF reason = "bufferedErase" THEN FALSE ELSE bufferedErase
        /\ UNCHANGED lateAnswer
        /\ wrongTimeout' = (wrongTimeout \/ (reason = "timeout" /\ timeoutNumber # lastWaitNumber))
        /\ scheduledTimeouts' = IF reason = "timeout" THEN scheduledTimeouts \ {timeoutNumber} ELSE scheduledTimeouts
        /\ UNCHANGED lastWaitNumber
        /\ UNCHANGED outputFlowVariables
        /\ mode' = IF reason = "editingEnd" THEN "other" ELSE mode
        /\ active' = NoRequest
        /\ owed' = IF pending = NoRequest THEN {} ELSE owed
        /\ UNCHANGED <<open, attached, following, programSize, clientSize,
             clientTrace, pending, unanswered, requestCount, queryCount,
             wrongQuery, latestSize, latestValidRequestNumber, attachCount, attaching, attachSize,
             attachOutcome, attachPhase, previousSize, previousTrace, ended>>

\* Starting the pending request is part of the same session actor operation
\* that ended the earlier wait. No other session operation can interleave.
StartPending ==
  /\ ~ended /\ active = NoRequest /\ pending # NoRequest
  /\ LET request == Request(pending.number, pending.client, pending.size,
                           pending.confirms, mode, screenSize)
         valid == request.size # NoSize
         waits == valid /\ WaitsForEditor(request.size)
         early == waits /\ ~KeepOldWidthWhileWaiting
         appliedSize == IF valid THEN request.size ELSE screenSize
         sent == IF (waits /\ ~early) \/ ~valid THEN queues ELSE SizeQueues(queues, request, screenSize, request.size, "plain")
     IN /\ programSize' = IF valid THEN request.size ELSE programSize
        /\ screenSize' = IF waits /\ ~early THEN screenSize ELSE appliedSize
        /\ screenTrace' = IF waits /\ ~early THEN screenTrace ELSE ResizedTrace(screenTrace, screenSize, appliedSize, "plain")
        /\ active' = IF waits THEN request ELSE NoRequest
        /\ pending' = NoRequest
        /\ queues' = IF waits THEN sent ELSE OwedQueues(sent, owed, appliedSize, "plain")
        /\ owed' = IF waits THEN owed ELSE {}
        /\ lastWaitNumber' = IF waits THEN lastWaitNumber + 1 ELSE lastWaitNumber
        /\ scheduledTimeouts' = IF waits THEN scheduledTimeouts \cup {lastWaitNumber + 1} ELSE scheduledTimeouts
        /\ UNCHANGED wrongTimeout
        /\ UNCHANGED bufferVariables
        /\ UNCHANGED outputFlowVariables
        /\ UNCHANGED <<open, attached, following, clientSize, clientTrace, mode,
             unanswered, requestCount, outputCount, queryCount, wrongQuery,
             wrongRedrawSize, wrongCursorRule, latestSize, latestValidRequestNumber, attachCount,
             attaching, attachSize, attachOutcome, attachPhase, previousSize,
             previousTrace, ended>>

\* A checked size can still fail when the session screen takes it. The
\* program must return to the screen's old size. The requester hears the
\* size that remains, and a pending request still takes its turn.
FailWait ==
  /\ ~ended /\ active # NoRequest
  /\ LET sent == SizeQueues(queues, active, screenSize, screenSize, "plain")
     IN /\ programSize' = IF RestoreProgramOnResizeFailure THEN screenSize ELSE programSize
        /\ queues' = IF pending = NoRequest THEN OwedQueues(sent, owed, screenSize, "plain") ELSE sent
        /\ latestSize' = IF latestValidRequestNumber = active.number THEN screenSize ELSE latestSize
        /\ UNCHANGED latestValidRequestNumber
        /\ active' = NoRequest
        /\ owed' = IF pending = NoRequest THEN {} ELSE owed
        /\ UNCHANGED <<open, attached, following, screenSize, screenTrace,
             clientSize, clientTrace, mode, pending, unanswered, requestCount,
             outputCount, queryCount, wrongQuery, wrongRedrawSize,
             wrongCursorRule, attachCount, attaching, attachSize, attachOutcome,
             attachPhase, previousSize, previousTrace, ended>>
        /\ UNCHANGED timingVariables
        /\ UNCHANGED bufferVariables
        /\ UNCHANGED outputFlowVariables

ProgramOutput ==
  /\ ~ended /\ attaching = 0 /\ (active # NoRequest \/ pending = NoRequest)
  /\ ~bufferedErase /\ ~outputPaused /\ outputCount < OutputLimit
  /\ outputCount' = outputCount + 1
  /\ screenTrace' = Append(screenTrace, OutputOperation(outputCount + 1))
  /\ queues' = OutputQueues(queues, outputCount + 1)
  /\ UNCHANGED <<open, attached, following, programSize, screenSize, clientSize,
       clientTrace, mode, active, pending, owed, unanswered, requestCount,
       queryCount, wrongQuery, wrongRedrawSize, wrongCursorRule, latestSize, latestValidRequestNumber,
       attachCount, attaching, attachSize, attachOutcome, attachPhase,
       previousSize, previousTrace, ended>>
  /\ UNCHANGED timingVariables
  /\ UNCHANGED bufferVariables
  /\ UNCHANGED outputFlowVariables

\* Bytes already written to the pseudo terminal can be parsed only after a
\* resize begins. An erase in that older output is not the new size's answer.
BufferOldErase ==
  /\ ~ended /\ attaching = 0 /\ active = NoRequest /\ pending = NoRequest
  /\ mode = "editor" /\ ~bufferedErase /\ outputCount < OutputLimit
  /\ bufferedErase' = TRUE
  /\ UNCHANGED <<open, attached, following, programSize, screenSize, screenTrace,
       clientSize, clientTrace, queues, mode, active, pending, owed, unanswered,
       requestCount, outputCount, queryCount, wrongQuery, wrongRedrawSize,
       wrongCursorRule, latestSize, latestValidRequestNumber, attachCount, attaching, attachSize,
       attachOutcome, attachPhase, previousSize, previousTrace, ended,
       lastWaitNumber, scheduledTimeouts, wrongTimeout, wrongRedrawAttribution, lateAnswer>>
  /\ UNCHANGED outputFlowVariables

ParseBufferedErase ==
  /\ ~ended /\ attaching = 0 /\ bufferedErase /\ ~outputPaused /\ outputCount < OutputLimit
  /\ (active # NoRequest \/ pending = NoRequest)
  /\ IF active # NoRequest /\ active.origin = "editor" /\ ~RejectBufferedErase
     THEN ResolveWait("bufferedErase", TRUE, 0)
     ELSE /\ bufferedErase' = FALSE
          /\ outputCount' = outputCount + 1
          /\ screenTrace' = Append(screenTrace, OutputOperation(outputCount + 1))
          /\ queues' = OutputQueues(queues, outputCount + 1)
          /\ UNCHANGED <<open, attached, following, programSize, screenSize,
               clientSize, clientTrace, mode, active, pending, owed, unanswered,
               requestCount, queryCount, wrongQuery, wrongRedrawSize,
               wrongCursorRule, latestSize, latestValidRequestNumber, attachCount, attaching, attachSize,
               attachOutcome, attachPhase, previousSize, previousTrace, ended,
               lastWaitNumber, scheduledTimeouts, wrongTimeout, wrongRedrawAttribution, lateAnswer>>
          /\ UNCHANGED outputFlowVariables

\* This is an over-approximation of output-room backpressure: after output,
\* a slow client can pause parsing. Resize, timeout, attach and detach can
\* still run. At most one pause starts for each parsed output piece.
PauseOutput ==
  /\ ~ended /\ attaching = 0 /\ ~outputPaused /\ outputCount > lastPauseOutput
  /\ \E client \in attached : Len(queues[client]) > 0
  /\ outputPaused' = TRUE
  /\ lastPauseOutput' = outputCount
  /\ UNCHANGED <<open, attached, following, programSize, screenSize, screenTrace,
       clientSize, clientTrace, queues, mode, active, pending, owed, unanswered,
       requestCount, outputCount, queryCount, wrongQuery, wrongRedrawSize,
       wrongCursorRule, latestSize, latestValidRequestNumber, attachCount, attaching, attachSize,
       attachOutcome, attachPhase, previousSize, previousTrace, ended,
       lastWaitNumber, scheduledTimeouts, wrongTimeout, bufferedErase,
       wrongRedrawAttribution, lateAnswer>>

ResumeOutput ==
  /\ ~ended /\ EnableOutputResume /\ outputPaused
  /\ outputPaused' = FALSE
  /\ UNCHANGED <<open, attached, following, programSize, screenSize, screenTrace,
       clientSize, clientTrace, queues, mode, active, pending, owed, unanswered,
       requestCount, outputCount, queryCount, wrongQuery, wrongRedrawSize,
       wrongCursorRule, latestSize, latestValidRequestNumber, attachCount, attaching, attachSize,
       attachOutcome, attachPhase, previousSize, previousTrace, ended,
       lastWaitNumber, scheduledTimeouts, wrongTimeout, bufferedErase,
       wrongRedrawAttribution, lastPauseOutput, lateAnswer>>

\* This model covers a headless session's size answer, not relay ownership.
\* AttachSequence separately checks which terminal answers a query.
QuerySize ==
  /\ ~ended /\ attaching = 0 /\ (active # NoRequest \/ pending = NoRequest)
  /\ ~bufferedErase /\ ~outputPaused /\ queryCount < QueryLimit
  /\ queryCount' = queryCount + 1
  /\ wrongQuery' = (wrongQuery \/ ((IF CorrectQuerySize THEN programSize ELSE screenSize) # programSize))
  /\ UNCHANGED <<open, attached, following, programSize, screenSize, screenTrace,
       clientSize, clientTrace, queues, mode, active, pending, owed, unanswered,
       requestCount, outputCount, wrongRedrawSize, wrongCursorRule, latestSize, latestValidRequestNumber,
       attachCount, attaching, attachSize, attachOutcome, attachPhase,
       previousSize, previousTrace, ended>>
  /\ UNCHANGED timingVariables
  /\ UNCHANGED bufferVariables
  /\ UNCHANGED outputFlowVariables

Deliver(client) ==
  /\ client \in open /\ Len(queues[client]) > 0
  /\ LET message == Head(queues[client])
     IN /\ queues' = [queues EXCEPT ![client] = Tail(@)]
        /\ clientSize' = IF message.kind \in {"size", "snapshot"}
             THEN [clientSize EXCEPT ![client] = message.size] ELSE clientSize
        /\ clientTrace' = [clientTrace EXCEPT ![client] =
             IF message.kind = "snapshot" THEN message.snapshot
             ELSE IF message.kind = "output" THEN Append(@, OutputOperation(message.number))
             ELSE ResizedTrace(@, clientSize[client], message.size, message.keeps)]
        /\ unanswered' = unanswered \ {request \in unanswered :
             request.client = client /\ request.number <= message.confirmation}
        /\ UNCHANGED <<open, attached, following, programSize, screenSize,
             screenTrace, mode, active, pending, owed, requestCount, outputCount,
             queryCount, wrongQuery, wrongRedrawSize, wrongCursorRule, latestSize, latestValidRequestNumber,
             attachCount, attaching, attachSize, attachOutcome, attachPhase,
             previousSize, previousTrace, ended>>
        /\ UNCHANGED timingVariables
        /\ UNCHANGED bufferVariables
        /\ UNCHANGED outputFlowVariables

\* The client's size requests still apply after it leaves; the session only
\* drops its identity and any confirmation that client was owed.
Leave(client) ==
  /\ ~ended /\ attaching = 0 /\ (active # NoRequest \/ pending = NoRequest)
  /\ client \in open
  /\ open' = open \ {client}
  /\ attached' = attached \ {client}
  /\ following' = following \ {client}
  /\ queues' = [queues EXCEPT ![client] = <<>>]
  /\ active' = IF active # NoRequest /\ active.client = client
       THEN [active EXCEPT !.client = 0] ELSE active
  /\ pending' = IF pending # NoRequest /\ pending.client = client
       THEN [pending EXCEPT !.client = 0] ELSE pending
  /\ owed' = owed \ {client}
  /\ unanswered' = {request \in unanswered : request.client # client}
  /\ UNCHANGED <<programSize, screenSize, screenTrace, clientSize, clientTrace,
       mode, requestCount, outputCount, queryCount, wrongQuery,
       wrongRedrawSize, wrongCursorRule, latestSize, latestValidRequestNumber, attachCount, attaching,
       attachSize, attachOutcome, attachPhase, previousSize, previousTrace, ended>>
  /\ UNCHANGED timingVariables
  /\ UNCHANGED bufferVariables
  /\ UNCHANGED outputFlowVariables

\* An attach interrupts and drains all waits within one session actor method.
\* The intermediate phases block session actions; client delivery can still
\* run. A refused attach does not resize. A failed capture may restore the
\* old size, or a failed restoration can leave the new size in place.
BeginAttach(client, size, outcome) ==
  /\ ~ended /\ attaching = 0 /\ (active # NoRequest \/ pending = NoRequest)
  /\ client \in open \ attached
  /\ attachCount < AttachLimit /\ size \in Sizes /\ outcome \in Outcomes
  /\ attaching' = client
  /\ attachSize' = size
  /\ attachOutcome' = outcome
  /\ attachPhase' = "draining"
  /\ attachCount' = attachCount + 1
  /\ UNCHANGED <<open, attached, following, programSize, screenSize, screenTrace,
       clientSize, clientTrace, queues, mode, active, pending, owed, unanswered,
       requestCount, outputCount, queryCount, wrongQuery, wrongRedrawSize,
       wrongCursorRule, latestSize, latestValidRequestNumber, previousSize, previousTrace, ended>>
  /\ UNCHANGED timingVariables
  /\ UNCHANGED bufferVariables
  /\ UNCHANGED outputFlowVariables

ApplyAttach ==
  /\ ~ended /\ attaching # 0 /\ attachPhase = "draining"
  /\ active = NoRequest /\ pending = NoRequest
  /\ previousSize' = screenSize
  /\ previousTrace' = screenTrace
  /\ programSize' = IF attachOutcome = "refused" THEN programSize ELSE attachSize
  /\ screenSize' = IF attachOutcome = "refused" THEN screenSize ELSE attachSize
  /\ screenTrace' = IF attachOutcome = "refused" THEN screenTrace
       ELSE ResizedTrace(screenTrace, screenSize, attachSize, "plain")
  /\ attachPhase' = "capture"
  /\ UNCHANGED <<open, attached, following, clientSize, clientTrace, queues,
       mode, active, pending, owed, unanswered, requestCount, outputCount,
       queryCount, wrongQuery, wrongRedrawSize, wrongCursorRule, latestSize, latestValidRequestNumber,
       attachCount, attaching, attachSize, attachOutcome, ended>>
  /\ UNCHANGED timingVariables
  /\ UNCHANGED bufferVariables
  /\ UNCHANGED outputFlowVariables

FinishAttach ==
  /\ ~ended /\ attaching # 0 /\ attachPhase = "capture"
  /\ LET success == attachOutcome = "success"
         rollsBack == attachOutcome = "rollback"
         changed == screenSize # previousSize
         retained == success \/ attachOutcome = "rollbackFailure"
         newQueues == [client \in Clients |->
           IF success /\ client = attaching
           THEN Append(queues[client], SnapshotMessage(screenSize, screenTrace))
           ELSE IF client \in attached /\ retained /\ changed
           THEN Append(queues[client], SizeMessage(screenSize, "plain", 0))
           ELSE queues[client]]
     IN /\ programSize' = IF rollsBack THEN previousSize ELSE programSize
        /\ screenSize' = IF rollsBack THEN previousSize ELSE screenSize
        /\ screenTrace' = IF rollsBack THEN previousTrace ELSE screenTrace
        /\ latestSize' = IF retained THEN screenSize ELSE latestSize
        /\ UNCHANGED latestValidRequestNumber
        /\ queues' = newQueues
        /\ attached' = IF success THEN attached \cup {attaching} ELSE attached
        /\ following' = IF success THEN following \cup {attaching} ELSE following
        /\ attaching' = 0
        /\ attachPhase' = "none"
        /\ UNCHANGED <<open, clientSize, clientTrace, mode, active, pending, owed,
             unanswered, requestCount, outputCount, queryCount, wrongQuery,
             wrongRedrawSize, wrongCursorRule, attachCount, attachSize,
             attachOutcome, previousSize, previousTrace, ended>>
        /\ UNCHANGED timingVariables
        /\ UNCHANGED bufferVariables
        /\ UNCHANGED outputFlowVariables

\* End of the program closes its clients, so it also ends their obligations.
EndProgram ==
  /\ ~ended /\ attaching = 0 /\ (active # NoRequest \/ pending = NoRequest)
  /\ ended' = TRUE
  /\ open' = {}
  /\ attached' = {}
  /\ following' = {}
  /\ queues' = [client \in Clients |-> <<>>]
  /\ active' = NoRequest
  /\ pending' = NoRequest
  /\ owed' = {}
  /\ unanswered' = {}
  /\ scheduledTimeouts' = {}
  /\ bufferedErase' = FALSE
  /\ outputPaused' = FALSE
  /\ UNCHANGED lastPauseOutput
  /\ UNCHANGED <<lastWaitNumber, wrongTimeout>>
  /\ UNCHANGED wrongRedrawAttribution
  /\ lateAnswer' = FALSE
  /\ UNCHANGED <<programSize, screenSize, screenTrace, clientSize, clientTrace,
       mode, requestCount, outputCount, queryCount, wrongQuery,
       wrongRedrawSize, wrongCursorRule, latestSize, latestValidRequestNumber, attachCount, attaching,
       attachSize, attachOutcome, attachPhase, previousSize, previousTrace>>

\* A timer can arrive after its own wait ended and a newer wait started.
\* It is consumed but must not end that newer wait.
Timeout(number) ==
  /\ ~ended /\ EnableTimeout /\ attaching = 0 /\ number \in scheduledTimeouts
  /\ IF active = NoRequest \/ (RejectStaleTimeout /\ number # lastWaitNumber)
     THEN /\ scheduledTimeouts' = scheduledTimeouts \ {number}
          /\ UNCHANGED <<open, attached, following, programSize, screenSize, screenTrace,
               clientSize, clientTrace, queues, mode, active, pending, owed,
               unanswered, requestCount, outputCount, queryCount, wrongQuery,
               wrongRedrawSize, wrongCursorRule, latestSize, latestValidRequestNumber, attachCount,
               attaching, attachSize, attachOutcome, attachPhase, previousSize,
               previousTrace, ended, lastWaitNumber, wrongTimeout, bufferedErase,
               wrongRedrawAttribution, outputPaused, lastPauseOutput, lateAnswer>>
     ELSE ResolveWait("timeout", FALSE, number)

AnyTimeout == \E number \in 1..RequestLimit : Timeout(number)
AttachWait == ResolveWait("attach", FALSE, 0)
AttachProgress == AttachWait \/ ApplyAttach \/ FinishAttach

Next == ProgramOutput \/ BufferOldErase \/ ParseBufferedErase \/ PauseOutput \/
  ResumeOutput \/ QuerySize \/
  StartPending \/ FailWait \/ EndProgram \/ AnyTimeout
  \/ ResolveWait("editingEnd", FALSE, 0)
  \/ (\E includesErase \in BOOLEAN : ResolveWait("redraw", includesErase, 0))
  \/ AttachProgress
  \/ (\E nextMode \in Modes : ChangeMode(nextMode))
  \/ (\E client \in Clients, size \in Sizes \cup {NoSize}, confirms \in BOOLEAN :
        RequestResize(client, size, confirms))
  \/ (\E client \in Clients, size \in Sizes, outcome \in Outcomes :
        BeginAttach(client, size, outcome))
  \/ (\E client \in Clients : Deliver(client) \/ Leave(client))

Specification == InitialState /\ [][Next]_variables

\* Safety properties. A quiet follower has applied all prior output and size
\* operations. The program can differ from the screen only during a wait.
StateTypes ==
  /\ open \subseteq Clients
  /\ attached \subseteq open
  /\ following \subseteq attached
  /\ programSize \in Sizes /\ screenSize \in Sizes
  /\ clientSize \in [Clients -> Sizes]
  /\ mode \in Modes
  /\ requestCount \in 0..RequestLimit
  /\ latestValidRequestNumber \in 0..requestCount
  /\ outputCount \in 0..OutputLimit
  /\ queryCount \in 0..QueryLimit
  /\ attachCount \in 0..AttachLimit
  /\ attaching \in 0..ClientCount
  /\ attachPhase \in {"none", "draining", "capture"}
  /\ attachOutcome \in Outcomes
  /\ (attaching = 0) = (attachPhase = "none")
  /\ active.client \in 0..ClientCount /\ pending.client \in 0..ClientCount
  /\ active.number \in 0..requestCount /\ pending.number \in 0..requestCount
  /\ (active = NoRequest \/ active.size \in Sizes)
  /\ (pending = NoRequest \/ pending.size \in Sizes \cup {NoSize})
  /\ owed \subseteq attached
  /\ \A request \in unanswered :
       request.client \in attached /\ request.number \in 1..requestCount
  /\ lastWaitNumber \in 0..requestCount
  /\ scheduledTimeouts \subseteq 1..lastWaitNumber
  /\ lastPauseOutput \in 0..outputCount
  /\ lateAnswer \in BOOLEAN

ScreenCopiesAgree ==
  \A client \in following \cap attached :
    (attaching = 0 /\ Len(queues[client]) = 0) =>
      (clientSize[client] = screenSize /\ clientTrace[client] = screenTrace)

SettledSizeAgreement ==
  (~ended /\ attaching = 0 /\ active = NoRequest /\ pending = NoRequest) =>
    (programSize = screenSize /\ screenSize = latestSize)

WaitOnlyForEditor == active = NoRequest \/ active.origin = "editor"
WaitChangesWidth == active = NoRequest \/ active.size.columns # active.previousSize.columns
CorrectSizeAnswers == ~wrongQuery
RedrawUsesOldWidth == ~wrongRedrawSize
CursorRuleFollowsErase == ~wrongCursorRule
TimeoutMatchesWait == ~wrongTimeout
RedrawIsFresh == ~wrongRedrawAttribution

\* Every confirmed request is represented by a pending request, an active
\* request, an owed client, or a confirmation that is already in its queue.
ConfirmationsTracked ==
  \A request \in unanswered :
    \/ (active # NoRequest /\ active.client = request.client /\ active.confirms /\ active.number >= request.number)
    \/ (pending # NoRequest /\ pending.client = request.client /\ pending.confirms /\ pending.number >= request.number)
    \/ request.client \in owed
    \/ (\E index \in 1..Len(queues[request.client]) :
          queues[request.client][index].confirmation >= request.number)

\* Reachability controls deliberately fail. They demonstrate that the bounded
\* runs actually visit the races covered by the properties above.
AttachDuringCoalescingIsUnreachable ==
  ~(attaching # 0 /\ active # NoRequest /\ pending # NoRequest)
StaleTimeoutDuringWaitIsUnreachable ==
  ~(active # NoRequest /\ \E number \in scheduledTimeouts : number # lastWaitNumber)
BufferedEraseDuringWaitIsUnreachable == ~(bufferedErase /\ active # NoRequest)
UnconfirmedReplacementIsUnreachable ==
  ~(active # NoRequest /\ pending # NoRequest /\ ~pending.confirms /\ owed # {})
OtherClientReplacementIsUnreachable ==
  ~(active # NoRequest /\ pending # NoRequest /\ \E client \in owed : client # pending.client)
OutputPauseDuringWaitIsUnreachable == ~(outputPaused /\ active # NoRequest)
ForegroundChangeDuringWaitIsUnreachable ==
  ~(active # NoRequest /\ mode # active.origin)

\* Liveness needs fairness: a timeout, internal attach step, and client
\* delivery must eventually run when each stays enabled. This does not model
\* real elapsed time or prove that 500 milliseconds is respected.
Fairness ==
  /\ WF_variables(AnyTimeout)
  /\ WF_variables(StartPending)
  /\ WF_variables(AttachProgress)
  /\ WF_variables(ParseBufferedErase)
  /\ WF_variables(ResumeOutput)
  /\ (\A client \in Clients : WF_variables(Deliver(client)))

LiveSpecification == Specification /\ Fairness
WaitEventuallyEnds == (active # NoRequest) ~> (active = NoRequest \/ ended)
ConfirmationsEventuallyEnd == (unanswered # {}) ~> (unanswered = {})
BufferedOutputEventuallyEnds == bufferedErase ~> (~bufferedErase \/ ended)

=============================================================================
