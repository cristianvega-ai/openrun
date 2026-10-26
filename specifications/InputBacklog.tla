--------------------------- MODULE InputBacklog -----------------------------
\* A model of PseudoTerminal.InputBacklog: typed input from attached clients,
\* blocking `sendText`, answers to queries, the program's reads, withdrawal
\* when a client leaves, and the end of the program.
\*
\* InputBacklog is not an actor.  PseudoTerminal keeps it on one serial queue
\* and calls it from that queue, so each method below is one atomic step.
\*
\* The model keeps the order of the pieces and their owners.  It leaves out
\* the byte counts inside one piece, the half of the storage that the queues
\* drop, and the started-front-piece rule: a piece here is one byte, so a
\* withdrawn piece is either delivered or not.  documentation/architecture.md
\* describes both refinements.  Neither changes the order or the owner
\* rules.
\*
\* The constant WithdrawalEnabled switches one protection.
\*   TRUE   The code has this protection.  InputBacklog.withdraw removes the
\*          waiting input and the unstarted backlog pieces of a client that
\*          left.  TLC must find no violation.
\*   FALSE  A control that removes the protection.  TLC must find that
\*          NoByteAfterWithdraw is false: a typed byte of a client that left
\*          arrives at the program after that client left.
EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS OwnerCount, ByteLimit, MaximumTypedPerOwner, AnswerCount,
          WithdrawalEnabled

Owners == 1..OwnerCount

\* owner 0 is a terminal answer, which has no owner
Piece(owner, sequenceNumber, isAnswer, isSend, stays) ==
  [owner |-> owner, sequenceNumber |-> sequenceNumber, isAnswer |-> isAnswer,
   isSend |-> isSend, stays |-> stays]

VARIABLES nextByte, nextAnswer, waiting, backlog, admitted, delivered,
          pendingBytes, pendingTyped, left, withdrawMark, programEnded,
          sendState

variables == <<nextByte, nextAnswer, waiting, backlog, admitted, delivered,
               pendingBytes, pendingTyped, left, withdrawMark, programEnded,
               sendState>>

IsTyped(piece) == ~piece.isAnswer

InitialState ==
  /\ nextByte = [owner \in Owners |-> 1]
  /\ nextAnswer = 1
  /\ waiting = <<>>
  /\ backlog = <<>>
  /\ admitted = <<>>
  /\ delivered = <<>>
  /\ pendingBytes = 0
  /\ pendingTyped = 0
  /\ left = [owner \in Owners |-> FALSE]
  /\ withdrawMark = [owner \in Owners |-> 0]
  /\ programEnded = FALSE
  /\ sendState = [owner \in Owners |-> "idle"]

\* PseudoTerminal.type(_:from:whenSettled:), which calls InputBacklog.addTyped.
\* An attached client's key bytes.  They do not stay without their owner.
Type(owner) ==
  /\ ~left[owner]
  /\ ~programEnded
  /\ nextByte[owner] <= MaximumTypedPerOwner
  /\ waiting' = Append(waiting,
       Piece(owner, nextByte[owner], FALSE, FALSE, FALSE))
  /\ nextByte' = [nextByte EXCEPT ![owner] = @ + 1]
  /\ UNCHANGED <<nextAnswer, backlog, admitted, delivered, pendingBytes,
       pendingTyped, left, withdrawMark, programEnded, sendState>>

\* PseudoTerminal.type(_:), which SessionServer.serve calls for sendText.
\* The call waits for room.  The session answers once the bytes are in the
\* backlog.  Bytes that were once in the backlog stay after the client leaves.
Send(owner) ==
  /\ ~left[owner]
  /\ ~programEnded
  /\ sendState[owner] = "idle"
  /\ nextByte[owner] <= MaximumTypedPerOwner
  /\ waiting' = Append(waiting,
       Piece(owner, nextByte[owner], FALSE, TRUE, TRUE))
  /\ nextByte' = [nextByte EXCEPT ![owner] = @ + 1]
  /\ sendState' = [sendState EXCEPT ![owner] = "waiting"]
  /\ UNCHANGED <<nextAnswer, backlog, admitted, delivered, pendingBytes,
       pendingTyped, left, withdrawMark, programEnded>>

\* PseudoTerminal.write and InputBacklog.addAnswer.  An answer goes into the
\* backlog at once when no typed input waits.  Otherwise it waits behind that
\* input and goes in right after it.
AddAnswerDirect ==
  /\ ~programEnded
  /\ nextAnswer <= AnswerCount
  /\ waiting = <<>>
  /\ backlog' = Append(backlog, Piece(0, nextAnswer, TRUE, FALSE, TRUE))
  /\ admitted' = Append(admitted, Piece(0, nextAnswer, TRUE, FALSE, TRUE))
  /\ nextAnswer' = nextAnswer + 1
  /\ pendingBytes' = pendingBytes + 1
  /\ UNCHANGED <<nextByte, waiting, delivered, pendingTyped, left,
       withdrawMark, programEnded, sendState>>

AddAnswerQueued ==
  /\ ~programEnded
  /\ nextAnswer <= AnswerCount
  /\ waiting # <<>>
  /\ waiting' = Append(waiting, Piece(0, nextAnswer, TRUE, FALSE, TRUE))
  /\ nextAnswer' = nextAnswer + 1
  /\ UNCHANGED <<nextByte, backlog, admitted, delivered, pendingBytes,
       pendingTyped, left, withdrawMark, programEnded, sendState>>

\* InputBacklog.admitWaiting, which PseudoTerminal.pumpInput calls.  Typed
\* input moves into the backlog while it fits.  An answer moves in as soon as
\* the input in front of it is in.
Admit ==
  /\ ~programEnded
  /\ waiting # <<>>
  /\ LET piece == Head(waiting)
         fits == piece.isAnswer
                 \/ pendingBytes = 0
                 \/ pendingBytes + 1 <= ByteLimit
     IN /\ fits
        /\ waiting' = Tail(waiting)
        /\ backlog' = Append(backlog, piece)
        /\ admitted' = Append(admitted, piece)
        /\ pendingBytes' = pendingBytes + 1
        /\ pendingTyped' = pendingTyped + (IF piece.isAnswer THEN 0 ELSE 1)
        /\ sendState' = IF piece.isSend
             THEN [sendState EXCEPT ![piece.owner] = "taken"]
             ELSE sendState
        /\ UNCHANGED <<nextByte, nextAnswer, delivered, left,
             withdrawMark, programEnded>>

\* PseudoTerminal.writePendingInput and InputBacklog.removeFromFront.  The
\* terminal takes bytes from the front.
ProgramReads ==
  /\ ~programEnded
  /\ backlog # <<>>
  /\ LET piece == Head(backlog)
     IN /\ backlog' = Tail(backlog)
        /\ delivered' = Append(delivered, piece)
        /\ pendingBytes' = pendingBytes - 1
        /\ pendingTyped' = pendingTyped - (IF piece.isAnswer THEN 0 ELSE 1)
        /\ UNCHANGED <<nextByte, nextAnswer, waiting, admitted, left,
             withdrawMark, programEnded, sendState>>

\* InputBacklog.withdraw, which PseudoTerminal.withdrawTypedInput calls when
\* SessionServer.serve sees that a client left.  Its waiting input goes, and
\* so do its backlog pieces that do not stay without an owner.  A piece that
\* already went to the program cannot be taken back.
Withdraw(owner) ==
  /\ ~left[owner]
  /\ ~programEnded
  /\ left' = [left EXCEPT ![owner] = TRUE]
  /\ withdrawMark' = [withdrawMark EXCEPT ![owner] = Len(delivered)]
  /\ IF WithdrawalEnabled
     THEN LET removedCount ==
                Cardinality({index \in 1..Len(backlog) :
                  backlog[index].owner = owner /\ ~backlog[index].stays})
              removedTyped == removedCount
              keptWaiting ==
                SelectSeq(waiting, LAMBDA piece: piece.owner # owner)
              keptBacklog ==
                SelectSeq(backlog, LAMBDA piece:
                  piece.owner # owner \/ piece.stays)
          IN /\ waiting' = keptWaiting
             /\ backlog' = keptBacklog
             /\ pendingBytes' = pendingBytes - removedCount
             /\ pendingTyped' = pendingTyped - removedTyped
             /\ sendState' = IF sendState[owner] = "waiting"
                  THEN [sendState EXCEPT ![owner] = "failed"]
                  ELSE sendState
     ELSE /\ UNCHANGED <<waiting, backlog, pendingBytes, pendingTyped,
              sendState>>
  /\ UNCHANGED <<nextByte, nextAnswer, admitted, delivered, programEnded>>

\* PseudoTerminal.reapIfExited calls PseudoTerminal.closeInput, which calls
\* InputBacklog.close.  The program ends.  Every typed piece that did not
\* reach it fails, and the backlog goes.
ProgramEnds ==
  /\ ~programEnded
  /\ programEnded' = TRUE
  /\ waiting' = <<>>
  /\ backlog' = <<>>
  /\ pendingBytes' = 0
  /\ pendingTyped' = 0
  /\ sendState' = [owner \in Owners |->
       IF sendState[owner] = "waiting" THEN "failed" ELSE sendState[owner]]
  /\ UNCHANGED <<nextByte, nextAnswer, admitted, delivered, left,
       withdrawMark>>

Next ==
  \/ (\E owner \in Owners : Type(owner) \/ Send(owner) \/ Withdraw(owner))
  \/ AddAnswerDirect \/ AddAnswerQueued
  \/ Admit
  \/ ProgramReads
  \/ ProgramEnds

Specification == InitialState /\ [][Next]_variables

\* ---------------------------------------------------------------------------
\* Safety.
\* ---------------------------------------------------------------------------

\* Each owner's bytes keep the order in which that owner made them.
OwnerOrder ==
  \A owner \in Owners :
    LET bytes == SelectSeq(delivered, LAMBDA piece: piece.owner = owner)
    IN \A index \in 2..Len(bytes) :
         bytes[index].sequenceNumber > bytes[index - 1].sequenceNumber

\* No byte of an owner goes in after its withdrawal, except bytes that were
\* already in the backlog when the client was told that they arrived
\* (`stays`), which documentation/architecture.md keeps.  The control
\* without withdrawal makes this false.
NoByteAfterWithdraw ==
  \A owner \in Owners :
    left[owner] =>
      (\A index \in 1..Len(delivered) :
         (delivered[index].owner = owner /\ ~delivered[index].stays) =>
           index <= withdrawMark[owner])

\* Replies keep their place among the typed input.  The program takes the
\* admitted pieces in order.  A withdrawal can remove an admitted piece
\* before the program takes it, so what the program received is a
\* subsequence of what was admitted, not a prefix.
IsSubsequence(smaller, larger) ==
  LET RECURSIVE Scan(_, _)
      Scan(index, from) ==
        IF index > Len(smaller) THEN TRUE
        ELSE IF from > Len(larger) THEN FALSE
        ELSE IF smaller[index] = larger[from] THEN Scan(index + 1, from + 1)
        ELSE Scan(index, from + 1)
  IN Scan(1, 1)

RepliesKeepPlace == IsSubsequence(delivered, admitted)

\* Typed input in the backlog stays within the limit.  Answers may pass it,
\* by design.
BacklogWithinLimit == pendingTyped <= ByteLimit

\* A client that left keeps no typed piece that it owns and that does not
\* stay.  (Withdraw leaves the bytes of other owners.)
LeftOwnersHoldNothing ==
  \A owner \in Owners :
    left[owner] =>
      ~(\E index \in 1..Len(waiting) :
          waiting[index].owner = owner)
      /\ ~(\E index \in 1..Len(backlog) :
             backlog[index].owner = owner /\ ~backlog[index].stays)

\* ---------------------------------------------------------------------------
\* Liveness under weak fairness.  A send settles once: taken or failed.
\* ---------------------------------------------------------------------------
Fairness ==
  WF_variables(Admit) /\ WF_variables(ProgramReads)
  /\ WF_variables(ProgramEnds)
  /\ (\A owner \in Owners : WF_variables(Withdraw(owner)))

LiveSpecification == Specification /\ Fairness

EverySendSettles ==
  \A owner \in Owners :
    (sendState[owner] = "waiting") ~>
      (sendState[owner] \in {"taken", "failed"})

=============================================================================
