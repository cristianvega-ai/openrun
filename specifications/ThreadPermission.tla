-------------------------- MODULE ThreadPermission --------------------------
\* A model of the permission request of an agent thread (proposal 2 of
\* 2026-11-10).  Claude Code runs the hook `openrun permission-request` when
\* it wants a permission.  The hook asks the session process, the user
\* answers in the chat of OpenRun.app, and the hook prints the decision for
\* the agent.
\*
\* A request comes from a program.  A genuine request comes from a hook that
\* the agent of a thread started.  Any other program of the user can reach
\* the socket too, so some requests come from an impostor.  The message of a
\* request can name a thread, and a hook can lie about it.
\*
\* An answerer is a program that sends an answer.  The user answers only
\* through the signed OpenRun.app that runs outside every session and every
\* thread.  Every other answerer is an impostor and always allows: a program
\* without the signature, and a signed app that an agent started.
\*
\* The registry of the threads and the runner of a thread are Swift actors,
\* so each step below is one step.  A restart of the session process closes
\* every connection, which the model covers as the failure of each hook.
\*
\* Each constant below switches one protection.  TRUE is the code.  FALSE is
\* a control, and TLC must find the violation that its configuration names.
\*   SignatureCheckExists   only a signed program answers.
\*   PlaceCheckExists       only a program outside every session and every
\*                          thread answers.
\*   CallerCheckExists      only a program that the agent of a thread
\*                          started asks.
\*   ThreadComesFromCaller  the thread of a request is the thread of the
\*                          agent that started the caller, not a field of
\*                          the message.
\*   ResolutionIsFinal      a request that has ended takes no later answer.
\*   FailureBlocks          a hook that fails blocks the tool
\*                          (`"onFailure": "block"`).
\*   TimeLimitExists        a request ends at a time limit.
EXTENDS Naturals, FiniteSets

CONSTANTS RequestCount, ThreadCount, GenuineRequests, LyingRequests,
          AnswererCount, SignedAnswerers, OutsideAnswerers,
          SignatureCheckExists, PlaceCheckExists, CallerCheckExists,
          ThreadComesFromCaller, ResolutionIsFinal, FailureBlocks,
          TimeLimitExists

Requests  == 1..RequestCount
Threads   == 1..ThreadCount
Answerers == 1..AnswererCount

ASSUME GenuineRequests \subseteq Requests /\ LyingRequests \subseteq Requests
ASSUME SignedAnswerers \subseteq Answerers /\ OutsideAnswerers \subseteq Answerers
ASSUME ThreadCount >= 2

\* The thread whose agent started the caller of a request.
ThreadOf(request) == ((request - 1) % ThreadCount) + 1
\* The thread that the message of the request names.  A lie names another one.
NamedThread(request) ==
  IF request \in LyingRequests THEN (ThreadOf(request) % ThreadCount) + 1
  ELSE ThreadOf(request)
\* The one answerer through which the user answers.
Trusted == SignedAnswerers \cap OutsideAnswerers

\* phase       for each request: "idle" (not asked yet), "waiting" (the
\*             request shows in a chat), "refused" (the session process
\*             took no request), "allowed" or "denied"
\* hook        the program that asks: "notStarted", "asking", "printedAllow",
\*             "printedDeny", or "failed" (a crash, a kill, a lost
\*             connection, or its own time limit)
\* tool        what the agent did with the tool call of a genuine request:
\*             "held", "ran" or "blocked"
\* shownIn     the thread whose chat shows the request, or 0
\* intended    the requests that the user allowed in the trusted app
\* deniedOnce  the request was denied or ended at some time
\* agentRuns   the agent of the thread runs
VARIABLES phase, hook, tool, shownIn, intended, deniedOnce, agentRuns

variables == <<phase, hook, tool, shownIn, intended, deniedOnce, agentRuns>>

InitialState ==
  /\ phase = [request \in Requests |-> "idle"]
  /\ hook = [request \in Requests |-> "notStarted"]
  /\ tool = [request \in Requests |-> "held"]
  /\ shownIn = [request \in Requests |-> 0]
  /\ intended = {}
  /\ deniedOnce = [request \in Requests |-> FALSE]
  /\ agentRuns = [thread \in Threads |-> TRUE]

\* Only the agent of a genuine request acts on what the hook prints.
ToolAfter(request, outcome) ==
  [tool EXCEPT ![request] = IF request \in GenuineRequests THEN outcome ELSE @]

\* A program asks for a permission.  SessionServer finds the thread from
\* the parents of the caller (ProcessAncestry).  It refuses a caller that no
\* agent started, and a caller whose agent has ended.  The hook prints a
\* denial after a refusal.
Ask(request) ==
  /\ hook[request] = "notStarted"
  /\ LET thread == IF ThreadComesFromCaller THEN ThreadOf(request)
                   ELSE NamedThread(request)
         isTaken == (request \in GenuineRequests \/ ~CallerCheckExists)
                    /\ agentRuns[thread] IN
     IF isTaken THEN
       /\ phase' = [phase EXCEPT ![request] = "waiting"]
       /\ hook' = [hook EXCEPT ![request] = "asking"]
       /\ shownIn' = [shownIn EXCEPT ![request] = thread]
       /\ UNCHANGED tool
     ELSE
       /\ phase' = [phase EXCEPT ![request] = "refused"]
       /\ hook' = [hook EXCEPT ![request] = "printedDeny"]
       /\ tool' = ToolAfter(request, "blocked")
       /\ UNCHANGED shownIn
  /\ UNCHANGED <<intended, deniedOnce, agentRuns>>

\* The session process gets an answer.  It takes the answer only from the
\* signed app outside every session and every thread, and only for a request
\* that waits.
ServerTakes(answerer, request, allows) ==
  LET isAccepted == (answerer \in SignedAnswerers \/ ~SignatureCheckExists)
                    /\ (answerer \in OutsideAnswerers \/ ~PlaceCheckExists)
      isOpen == phase[request] = "waiting"
                \/ (~ResolutionIsFinal /\ phase[request] \in {"allowed", "denied"}) IN
  /\ IF isAccepted /\ isOpen THEN
       /\ phase' = [phase EXCEPT ![request] = IF allows THEN "allowed" ELSE "denied"]
       /\ deniedOnce' = [deniedOnce EXCEPT ![request] = @ \/ ~allows]
     ELSE UNCHANGED <<phase, deniedOnce>>
  /\ UNCHANGED <<hook, tool, shownIn, agentRuns>>

\* The user answers a request in the chat of the trusted app.  The box of a
\* request can stay on the screen for a moment after the request has ended,
\* so the answer can come late.
UserAnswers(answerer, request, allows) ==
  /\ answerer \in Trusted
  /\ shownIn[request] # 0
  /\ intended' = IF allows THEN intended \cup {request} ELSE intended
  /\ ServerTakes(answerer, request, allows)

\* An impostor allows a request that waits.  It can be the agent itself.
ImpostorAnswers(answerer, request) ==
  /\ answerer \notin Trusted
  /\ phase[request] = "waiting"
  /\ UNCHANGED intended
  /\ ServerTakes(answerer, request, TRUE)

\* The hook gets the answer and prints it, and the agent acts on it.
HookReceives(request) ==
  /\ hook[request] = "asking" /\ phase[request] \in {"allowed", "denied"}
  /\ hook' = [hook EXCEPT ![request] =
       IF phase[request] = "allowed" THEN "printedAllow" ELSE "printedDeny"]
  /\ tool' = ToolAfter(request, IF phase[request] = "allowed" THEN "ran" ELSE "blocked")
  /\ UNCHANGED <<phase, shownIn, intended, deniedOnce, agentRuns>>

\* The hook fails before it prints an answer: a crash, a kill, its own time
\* limit, or a connection that closes, also by a restart of the session
\* process.  The session process ends the request of a caller that left.
HookFails(request) ==
  /\ hook[request] = "asking"
  /\ hook' = [hook EXCEPT ![request] = "failed"]
  /\ tool' = ToolAfter(request, IF FailureBlocks THEN "blocked" ELSE "ran")
  /\ IF phase[request] = "waiting"
     THEN /\ phase' = [phase EXCEPT ![request] = "denied"]
          /\ deniedOnce' = [deniedOnce EXCEPT ![request] = TRUE]
     ELSE UNCHANGED <<phase, deniedOnce>>
  /\ UNCHANGED <<shownIn, intended, agentRuns>>

\* A stop of the turn, the end of the agent, or the close of the thread
\* ends every request of the thread with a denial.
AgentEnds(thread) ==
  /\ agentRuns[thread]
  /\ agentRuns' = [agentRuns EXCEPT ![thread] = FALSE]
  /\ LET ends == {request \in Requests :
                    phase[request] = "waiting" /\ shownIn[request] = thread} IN
     /\ phase' = [request \in Requests |->
          IF request \in ends THEN "denied" ELSE phase[request]]
     /\ deniedOnce' = [request \in Requests |->
          deniedOnce[request] \/ request \in ends]
  /\ UNCHANGED <<hook, tool, shownIn, intended>>

\* The next message of the user starts the agent again.
AgentStarts(thread) ==
  /\ ~agentRuns[thread]
  /\ agentRuns' = [agentRuns EXCEPT ![thread] = TRUE]
  /\ UNCHANGED <<phase, hook, tool, shownIn, intended, deniedOnce>>

\* The request waited for 24 hours.
TimeLimit(request) ==
  /\ TimeLimitExists /\ phase[request] = "waiting"
  /\ phase' = [phase EXCEPT ![request] = "denied"]
  /\ deniedOnce' = [deniedOnce EXCEPT ![request] = TRUE]
  /\ UNCHANGED <<hook, tool, shownIn, intended, agentRuns>>

NextState ==
  \/ \E request \in Requests :
       \/ Ask(request) \/ HookReceives(request) \/ HookFails(request)
       \/ TimeLimit(request)
       \/ \E answerer \in Answerers :
            \/ UserAnswers(answerer, request, TRUE)
            \/ UserAnswers(answerer, request, FALSE)
            \/ ImpostorAnswers(answerer, request)
  \/ \E thread \in Threads : AgentEnds(thread) \/ AgentStarts(thread)

Specification == InitialState /\ [][NextState]_variables

\* ---------------------------------------------------------------------------
\* Safety.
\* ---------------------------------------------------------------------------

\* The session process allows a request only with the answer of the user.
\* The controls without the signature check and without the place check
\* make this false.
AllowOnlyFromUser ==
  \A request \in Requests : phase[request] = "allowed" => request \in intended

\* A tool runs only with the answer of the user.  A lost connection, a
\* restart and a time limit never grant.  The control in which a hook that
\* fails does not block makes this false.
ToolRunsOnlyWithUserAllow ==
  \A request \in Requests : tool[request] = "ran" => request \in intended

\* A request that was denied or has ended is never allowed later.  The
\* control that takes a late answer makes this false.
NoAllowAfterEnd ==
  \A request \in Requests : ~(deniedOnce[request] /\ phase[request] = "allowed")

\* A chat shows only the requests of its own agent, so the user knows who
\* asks.  The control without the caller check, and the control that takes
\* the thread from the message, make this false.
RequestShowsInThreadOfItsAgent ==
  \A request \in Requests :
    shownIn[request] # 0 =>
      request \in GenuineRequests /\ shownIn[request] = ThreadOf(request)

\* ---------------------------------------------------------------------------
\* Liveness under weak fairness of the time limit and of the answer to the hook.
\* ---------------------------------------------------------------------------
LiveSpecification ==
  Specification /\ \A request \in Requests :
    WF_variables(TimeLimit(request)) /\ WF_variables(HookReceives(request))

\* Every request ends.  The control without the time limit makes this false:
\* the user can leave a request with no answer for ever.
EveryRequestEnds ==
  \A request \in Requests :
    (phase[request] = "waiting") ~> (phase[request] # "waiting")

\* No hook waits for ever.
EveryHookEnds ==
  \A request \in Requests :
    (hook[request] = "asking") ~> (hook[request] # "asking")

=============================================================================
