-------------------------- MODULE ApprovalQuestion --------------------------
\* A model of the question that the session process asks the user when a
\* program in one session types into, reads, attaches to, or kills another
\* session (decisions of 2026-10-15 and 2026-11-10).
\*
\* Each request comes from a caller that runs in another session.  A caller
\* in the target session, or outside every session, needs no question, so the
\* model leaves those callers out.  The session process reads the terminal
\* session of the caller when it accepts the connection, and finds the session
\* at each request.  A caller that has already ended then has no session that
\* the process can find.  SessionRegistry keeps the terminal session of an
\* ended session while a process of it lives, so the caller of a session that
\* ends counts as unknown and never as a caller outside every session.  The
\* model therefore takes the place of a caller as fixed.  The refusal of a
\* second question of one session comes before the question, so it is one
\* more way to the "refused" phase.
\*
\* An answerer is a connection that asks to receive the questions.  The
\* signed OpenRun.app makes such a connection.  Any other program of the user
\* can make one too, so some answerers are impostors.  The user answers only
\* through a signed answerer.  An impostor always allows.
\*
\* The session process is a Swift actor for the questions, so each step below
\* is one step of that actor.  A restart of the session process closes every
\* connection at once.  The model covers it as the steps of each connection
\* that leaves.
\*
\* Each constant below switches one protection.  TRUE is the code.  FALSE is
\* a control, and TLC must find the violation that its configuration names.
\*   SignatureCheckExists  only a signed answerer receives questions and
\*                         answers them.
\*   AnswerNamesQuestion   an answer names the question that it answers.
\*   ResolutionIsFinal     a question that has ended takes no later answer.
\*   WithdrawOnLeave       a question ends when its caller leaves.
\*   UnknownCallerRefused  a caller whose session cannot be found is refused,
\*                         not taken for a caller outside every session.
\*   DenyWithoutAnswerer   a question ends when no answerer is left for it.
\*   TimeLimitExists       a question ends at a time limit.
EXTENDS Naturals, FiniteSets

CONSTANTS RequestCount, AnswererCount, SignedAnswerers,
          SignatureCheckExists, AnswerNamesQuestion, ResolutionIsFinal,
          WithdrawOnLeave, UnknownCallerRefused, DenyWithoutAnswerer,
          TimeLimitExists

Requests  == 1..RequestCount
Answerers == 1..AnswererCount

ASSUME SignedAnswerers \subseteq Answerers

\* phase         for each request: "idle" (not read yet), "waiting" (the
\*               question is out), "refused" (no question was possible),
\*               "performed", "denied", or "withdrawn"
\* callerAlive   the process of the caller still runs
\* gone          the caller left while its question was out
\* connected     the answerer has a connection
\* accepted      the session process takes questions and answers from it
\* shown         the questions that the session process counts as out on the
\*               connection of the answerer
\* seen          every question that reached the answerer, also one that has
\*               ended since; an alert can still be on the screen
\* intended      the pairs <<answerer, request>> that a user allowed through a
\*               signed answerer
\* applied       the pairs <<answerer, request>> whose allow the session
\*               process applied
\* deniedOnce    the request was denied at some time
\* performedOnce the request was performed at some time
VARIABLES phase, callerAlive, gone, connected, accepted, shown, seen,
          intended, applied, deniedOnce, performedOnce

variables == <<phase, callerAlive, gone, connected, accepted, shown, seen,
               intended, applied, deniedOnce, performedOnce>>

Waiting == {request \in Requests : phase[request] = "waiting"}
Answerable(isConnected, isAccepted) ==
  {answerer \in Answerers : isConnected[answerer] /\ isAccepted[answerer]}
\* The connections lose the question when it ends.
Without(request) == [answerer \in Answerers |-> shown[answerer] \ {request}]

InitialState ==
  /\ phase = [request \in Requests |-> "idle"]
  /\ callerAlive = [request \in Requests |-> TRUE]
  /\ gone = [request \in Requests |-> FALSE]
  /\ connected = [answerer \in Answerers |-> FALSE]
  /\ accepted = [answerer \in Answerers |-> FALSE]
  /\ shown = [answerer \in Answerers |-> {}]
  /\ seen = [answerer \in Answerers |-> {}]
  /\ intended = {}
  /\ applied = {}
  /\ deniedOnce = [request \in Requests |-> FALSE]
  /\ performedOnce = [request \in Requests |-> FALSE]

\* The caller writes its request and ends before the session process accepts
\* the connection.  The bytes stay in the socket.
CallerEndsEarly(request) ==
  /\ phase[request] = "idle" /\ callerAlive[request]
  /\ callerAlive' = [callerAlive EXCEPT ![request] = FALSE]
  /\ UNCHANGED <<phase, gone, connected, accepted, shown, seen, intended,
       applied, deniedOnce, performedOnce>>

\* SessionServer accepts the connection, finds the session of the caller,
\* and reads the request.  With no answerer, the request is refused at once.
Request(request) ==
  /\ phase[request] = "idle"
  /\ LET answerers == Answerable(connected, accepted) IN
     IF ~callerAlive[request] /\ ~UnknownCallerRefused THEN
       \* The control takes the caller for one outside every session.
       /\ phase' = [phase EXCEPT ![request] = "performed"]
       /\ performedOnce' = [performedOnce EXCEPT ![request] = TRUE]
       /\ UNCHANGED <<shown, seen>>
     ELSE IF ~callerAlive[request] \/ answerers = {} THEN
       /\ phase' = [phase EXCEPT ![request] = "refused"]
       /\ UNCHANGED <<shown, seen, performedOnce>>
     ELSE
       /\ phase' = [phase EXCEPT ![request] = "waiting"]
       /\ shown' = [answerer \in Answerers |->
            IF answerer \in answerers THEN shown[answerer] \cup {request}
            ELSE shown[answerer]]
       /\ seen' = [answerer \in Answerers |->
            IF answerer \in answerers THEN seen[answerer] \cup {request}
            ELSE seen[answerer]]
       /\ UNCHANGED performedOnce
  /\ UNCHANGED <<callerAlive, gone, connected, accepted, intended, applied,
       deniedOnce>>

\* The connection of the caller closes while its question is out.
CallerLeaves(request) ==
  /\ phase[request] = "waiting" /\ ~gone[request]
  /\ gone' = [gone EXCEPT ![request] = TRUE]
  /\ IF WithdrawOnLeave
     THEN /\ phase' = [phase EXCEPT ![request] = "withdrawn"]
          /\ shown' = Without(request)
     ELSE UNCHANGED <<phase, shown>>
  /\ UNCHANGED <<callerAlive, connected, accepted, seen, intended, applied,
       deniedOnce, performedOnce>>

\* An answerer connects and asks for the questions.  The session process
\* checks the code signature of its program.  An accepted answerer receives
\* every question that is out.
AnswererConnects(answerer) ==
  /\ ~connected[answerer]
  /\ LET isAccepted == answerer \in SignedAnswerers \/ ~SignatureCheckExists IN
     /\ connected' = [connected EXCEPT ![answerer] = TRUE]
     /\ accepted' = [accepted EXCEPT ![answerer] = isAccepted]
     /\ shown' = [shown EXCEPT ![answerer] = IF isAccepted THEN Waiting ELSE {}]
     /\ seen' = [seen EXCEPT ![answerer] =
          IF isAccepted THEN @ \cup Waiting ELSE @]
  /\ UNCHANGED <<phase, callerAlive, gone, intended, applied, deniedOnce,
       performedOnce>>

\* An answerer leaves, for example when the app quits.  A question that no
\* accepted answerer holds any more is denied.
AnswererLeaves(answerer) ==
  /\ connected[answerer]
  /\ LET isConnected == [connected EXCEPT ![answerer] = FALSE]
         isAccepted == [accepted EXCEPT ![answerer] = FALSE]
         left == [shown EXCEPT ![answerer] = {}]
         orphans == IF DenyWithoutAnswerer
                    THEN {request \in Waiting :
                            \A other \in Answerable(isConnected, isAccepted) :
                              request \notin left[other]}
                    ELSE {}
     IN /\ connected' = isConnected
        /\ accepted' = isAccepted
        /\ shown' = [other \in Answerers |-> left[other] \ orphans]
        /\ phase' = [request \in Requests |->
             IF request \in orphans THEN "denied" ELSE phase[request]]
        /\ deniedOnce' = [request \in Requests |->
             deniedOnce[request] \/ request \in orphans]
  /\ UNCHANGED <<callerAlive, gone, seen, intended, applied, performedOnce>>

\* An answerer answers a question that reached it, also one that ended
\* since.  The user decides through a signed answerer.  An impostor allows.
\* The session process takes the answer only from an accepted connection,
\* and only for a question that is still out on that connection.
Answer(answerer, request, allows) ==
  /\ connected[answerer]
  /\ request \in seen[answerer]
  /\ allows \/ answerer \in SignedAnswerers
  /\ intended' = IF allows /\ answerer \in SignedAnswerers
                 THEN intended \cup {<<answerer, request>>} ELSE intended
  /\ \E target \in Requests :
       /\ IF AnswerNamesQuestion THEN target = request ELSE target \in Waiting
       /\ IF accepted[answerer]
             /\ (IF ResolutionIsFinal
                 THEN phase[target] = "waiting" /\ target \in shown[answerer]
                 ELSE phase[target] \in {"waiting", "denied", "withdrawn"})
          THEN /\ phase' = [phase EXCEPT ![target] =
                    IF allows THEN "performed" ELSE "denied"]
               /\ shown' = Without(target)
               /\ applied' = IF allows THEN applied \cup {<<answerer, target>>}
                             ELSE applied
               /\ performedOnce' = [performedOnce EXCEPT ![target] = @ \/ allows]
               /\ deniedOnce' = [deniedOnce EXCEPT ![target] = @ \/ ~allows]
          ELSE UNCHANGED <<phase, shown, applied, performedOnce, deniedOnce>>
  /\ UNCHANGED <<callerAlive, gone, connected, accepted, seen>>

\* The time limit of a question.
TimeLimit(request) ==
  /\ TimeLimitExists /\ phase[request] = "waiting"
  /\ phase' = [phase EXCEPT ![request] = "denied"]
  /\ deniedOnce' = [deniedOnce EXCEPT ![request] = TRUE]
  /\ shown' = Without(request)
  /\ UNCHANGED <<callerAlive, gone, connected, accepted, seen, intended,
       applied, performedOnce>>

Next ==
  \/ \E request \in Requests :
       CallerEndsEarly(request) \/ Request(request) \/ CallerLeaves(request)
         \/ TimeLimit(request)
  \/ \E answerer \in Answerers :
       AnswererConnects(answerer) \/ AnswererLeaves(answerer)
  \/ \E answerer \in Answerers, request \in Requests, allows \in BOOLEAN :
       Answer(answerer, request, allows)

Specification == InitialState /\ [][Next]_variables

\* ---------------------------------------------------------------------------
\* Safety.
\* ---------------------------------------------------------------------------

\* An allow counts only from a signed answerer.  The control without the
\* signature check makes this false.
AllowsComeFromSignedAnswerers ==
  \A pair \in applied : pair[1] \in SignedAnswerers

\* A question never reaches an impostor.  The question holds the text that a
\* caller wants to type.
QuestionsReachOnlySignedAnswerers ==
  \A answerer \in Answerers \ SignedAnswerers : seen[answerer] = {}

\* An allow applies only to the question that the user allowed.  The control
\* without the identifier in the answer makes this false.
AllowsApplyToTheirQuestion == applied \subseteq intended

\* A request is performed only after an allow.  The control that takes an
\* ended caller for one outside every session makes this false.
PerformedOnlyWithAllow ==
  \A request \in Requests :
    performedOnce[request] => \E answerer \in Answerers :
                                <<answerer, request>> \in applied

\* A denied request is never performed.  The control that takes a late
\* answer makes this false.
NoAllowAfterDenial ==
  \A request \in Requests : ~(deniedOnce[request] /\ performedOnce[request])

\* A caller that left gets nothing performed.  The control without the
\* withdrawal makes this false.
NoAllowForGoneCaller ==
  \A request \in Requests : ~(gone[request] /\ performedOnce[request])

\* A question that is out always has an accepted answerer that holds it.
\* The control that keeps a question with no answerer makes this false.
WaitingQuestionsHaveAnAnswerer ==
  \A request \in Waiting :
    \E answerer \in Answerable(connected, accepted) : request \in shown[answerer]

\* The session process counts a question as out only while it waits.
ShownOnlyWhileWaiting ==
  \A answerer \in Answerers : shown[answerer] \subseteq Waiting

\* ---------------------------------------------------------------------------
\* Liveness under weak fairness of the time limit.
\* ---------------------------------------------------------------------------
LiveSpecification ==
  Specification /\ \A request \in Requests : WF_variables(TimeLimit(request))

\* Every question ends.  The control without the time limit makes this false:
\* a signed answerer can stay and never answer.
EveryQuestionEnds ==
  \A request \in Requests :
    (phase[request] = "waiting") ~> (phase[request] # "waiting")

=============================================================================
