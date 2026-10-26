-------------------------- MODULE SessionLifecycle --------------------------
\* A model of sessions, kill, shutdown, and the clients that wait for an
\* answer, with the stopping state of SessionRegistry.
\*
\* The registry and every session are Swift actors, so each step below is one
\* actor step.  SessionRegistry.terminateAll sets `isStopping` and copies the
\* session list in one step.  A create from another client can happen only
\* before or after that step.
\*
\* The constant StoppingStateExists switches one protection.
\*   TRUE   The code has this protection.  SessionRegistry.create refuses
\*          from the moment `isStopping` is set.  TLC must find no
\*          violation.
\*   FALSE  A control that removes the protection.  A session can start after
\*          shutdown began, and terminateAll does not end it.  TLC must find
\*          that NoSessionStartsDuringShutdown is false.
EXTENDS Naturals, FiniteSets

CONSTANTS SessionCount, ClientCount, StoppingStateExists

Sessions  == 1..SessionCount
Clients   == 1..ClientCount
Programs  == {<<session, 1>> : session \in Sessions}
InSession == {<<session, index>> : session \in Sessions, index \in 1..2}
Daemons   == {<<session, 3>> : session \in Sessions}
AllProcesses == InSession \cup Daemons

\* liveSessions  sessions whose program has not ended
\* aliveProcesses every process that is alive; a daemon has index 3 and is
\*               not in the program's session (it called setsid)
\* used          session identifiers that were handed out
\* stopping      SessionRegistry.isStopping
\* shutdownBegan the session process got SIGTERM, SIGINT or SIGHUP
\* shutdownTargets the sessions that terminateAll copied before it suspended
\* killing       a client asked for `openrun kill`, and the grace period runs
\* startedDuringShutdown  sessions created after shutdown began
\* killWaiters   for each session, the clients that wait for the answer to
\*               its killSession
\* exitWaiters   for each session, the clients that wait for the exit status
\*               of its program
\* killAnswers   the pairs <<client, session>> that got the answer to a kill
\* exitAnswers   the pairs <<client, session>> that got the exit status
VARIABLES liveSessions, aliveProcesses, used, stopping, shutdownBegan,
          shutdownTargets, killing, startedDuringShutdown,
          killWaiters, exitWaiters, killAnswers, exitAnswers

variables == <<liveSessions, aliveProcesses, used, stopping, shutdownBegan,
          shutdownTargets, killing, startedDuringShutdown, killWaiters,
          exitWaiters, killAnswers, exitAnswers>>

ProgramEnded(session) == <<session, 1>> \notin aliveProcesses
InSessionProcesses(session) == {<<session, index>> : index \in 1..2}

InitialState ==
  /\ liveSessions = {}
  /\ aliveProcesses = {}
  /\ used = {}
  /\ stopping = FALSE
  /\ shutdownBegan = FALSE
  /\ shutdownTargets = {}
  /\ killing = [session \in Sessions |-> FALSE]
  /\ startedDuringShutdown = {}
  /\ killWaiters = [session \in Sessions |-> {}]
  /\ exitWaiters = [session \in Sessions |-> {}]
  /\ killAnswers = {}
  /\ exitAnswers = {}

\* SessionServer.create and SessionRegistry.create.  The registry refuses
\* from the moment `isStopping` is set.  Before that, and without the
\* stopping state, a new program starts.  The program starts in Session.init.
Create(client, session) ==
  /\ session \notin used
  /\ (StoppingStateExists => ~stopping)
  /\ used' = used \cup {session}
  /\ liveSessions' = liveSessions \cup {session}
  /\ aliveProcesses' = aliveProcesses \cup InSessionProcesses(session)
  /\ startedDuringShutdown' =
       IF shutdownBegan THEN startedDuringShutdown \cup {session}
       ELSE startedDuringShutdown
  /\ UNCHANGED <<stopping, shutdownBegan, shutdownTargets, killing,
       killWaiters, exitWaiters, killAnswers, exitAnswers>>

\* SessionServer.shutDown and SessionRegistry.terminateAll.  The registry
\* sets `isStopping`, copies the sessions, and then ends them.  A later
\* create can miss the copy.
BeginShutdown ==
  /\ ~shutdownBegan
  /\ shutdownBegan' = TRUE
  /\ stopping' = StoppingStateExists
  /\ shutdownTargets' = liveSessions
  /\ UNCHANGED <<liveSessions, aliveProcesses, used, killing,
       startedDuringShutdown, killWaiters, exitWaiters, killAnswers,
       exitAnswers>>

\* SessionServer.serve (the killSession case) and Session.terminate.  A client
\* asks to kill one session.  SIGHUP goes out at once.  A process may act on
\* it or ignore it.
RequestKill(session) ==
  /\ session \in liveSessions
  /\ ~killing[session]
  /\ killing' = [killing EXCEPT ![session] = TRUE]
  /\ UNCHANGED <<liveSessions, aliveProcesses, used, stopping, shutdownBegan,
       shutdownTargets, startedDuringShutdown, killWaiters, exitWaiters,
       killAnswers, exitAnswers>>

\* PseudoTerminal.terminate.  A process acts on SIGHUP.  This is not
\* determined: a program may ignore it, and the SIGKILL below is then the one
\* that ends it.
ProcessDies(session, index) ==
  /\ <<session, index>> \in aliveProcesses
  /\ ~(InSessionProcesses(session) = {})
  /\ aliveProcesses' = aliveProcesses \ {<<session, index>>}
  /\ liveSessions' = IF index = 1 THEN liveSessions \ {session}
                     ELSE liveSessions
  /\ UNCHANGED <<used, stopping, shutdownBegan, shutdownTargets, killing,
       startedDuringShutdown, killWaiters, exitWaiters, killAnswers,
       exitAnswers>>

\* PseudoTerminal.terminate sends SIGKILL after the grace period.
\* SessionServer.shutDown ends every target session through
\* SessionRegistry.terminateAll.  A daemon, index 3, is not in the session and
\* stays alive.  The owner decided this.
KillRemainingProcesses(session) ==
  /\ killing[session] \/ (shutdownBegan /\ session \in shutdownTargets)
  /\ (\E index \in 1..2 : <<session, index>> \in aliveProcesses)
  /\ aliveProcesses' = aliveProcesses \ InSessionProcesses(session)
  /\ liveSessions' = liveSessions \ {session}
  /\ UNCHANGED <<used, stopping, shutdownBegan, shutdownTargets, killing,
       startedDuringShutdown, killWaiters, exitWaiters, killAnswers,
       exitAnswers>>

\* TerminalSessionProcesses: a process that calls setsid leaves the program's
\* session.  `openrun kill` and shutdown do not reach it.
\* documentation/architecture.md, "Process model", describes this.
StartDaemon(session) ==
  /\ session \in liveSessions
  /\ <<session, 3>> \notin aliveProcesses
  /\ aliveProcesses' = aliveProcesses \cup {<<session, 3>>}
  /\ UNCHANGED <<liveSessions, used, stopping, shutdownBegan,
       shutdownTargets, killing, startedDuringShutdown, killWaiters,
       exitWaiters, killAnswers, exitAnswers>>

\* SessionServer.serve: a client waits for the answer to killSession, or for
\* the exit status of its attached program.
WaitForKill(client, session) ==
  /\ killing[session]
  /\ killWaiters' = [killWaiters EXCEPT ![session] = @ \cup {client}]
  /\ UNCHANGED <<liveSessions, aliveProcesses, used, stopping, shutdownBegan,
       shutdownTargets, killing, startedDuringShutdown, exitWaiters,
       killAnswers, exitAnswers>>

WaitForExit(client, session) ==
  /\ session \in liveSessions
  /\ exitWaiters' = [exitWaiters EXCEPT ![session] = @ \cup {client}]
  /\ UNCHANGED <<liveSessions, aliveProcesses, used, stopping, shutdownBegan,
       shutdownTargets, killing, startedDuringShutdown, killWaiters,
       killAnswers, exitAnswers>>

\* The answer goes out once per waiting client.  The guard on the set is the
\* exactly-once rule.
AnswerKill(client, session) ==
  /\ client \in killWaiters[session]
  /\ session \notin liveSessions
  /\ <<client, session>> \notin killAnswers
  /\ killAnswers' = killAnswers \cup {<<client, session>>}
  /\ UNCHANGED <<liveSessions, aliveProcesses, used, stopping, shutdownBegan,
       shutdownTargets, killing, startedDuringShutdown, killWaiters,
       exitWaiters, exitAnswers>>

AnswerExit(client, session) ==
  /\ client \in exitWaiters[session]
  /\ ProgramEnded(session)
  /\ <<client, session>> \notin exitAnswers
  /\ exitAnswers' = exitAnswers \cup {<<client, session>>}
  /\ UNCHANGED <<liveSessions, aliveProcesses, used, stopping, shutdownBegan,
       shutdownTargets, killing, startedDuringShutdown, killWaiters,
       exitWaiters, killAnswers>>

Next ==
  \/ (\E client \in Clients, session \in Sessions : Create(client, session))
  \/ BeginShutdown
  \/ (\E session \in Sessions : RequestKill(session))
  \/ (\E session \in Sessions, index \in 1..2 : ProcessDies(session, index))
  \/ (\E session \in Sessions : KillRemainingProcesses(session))
  \/ (\E session \in Sessions : StartDaemon(session))
  \/ (\E client \in Clients, session \in Sessions :
        WaitForKill(client, session) \/ WaitForExit(client, session))
  \/ (\E client \in Clients, session \in Sessions :
        AnswerKill(client, session) \/ AnswerExit(client, session))

Specification == InitialState /\ [][Next]_variables

\* ---------------------------------------------------------------------------
\* Safety.
\* ---------------------------------------------------------------------------

\* No session starts after shutdown began.  The control without the stopping
\* state makes this false.
NoSessionStartsDuringShutdown == startedDuringShutdown = {}

\* Every answer was sent at most once: the sets cannot hold a pair twice, and
\* AnswerKill and AnswerExit are guarded by the pair not being in the set.
StatusAnsweredAtMostOnce ==
  Cardinality(killAnswers) <= SessionCount * ClientCount
    /\ Cardinality(exitAnswers) <= SessionCount * ClientCount

\* A session that is alive has a live program.
LiveSessionsHavePrograms ==
  \A session \in liveSessions : <<session, 1>> \in aliveProcesses

\* ---------------------------------------------------------------------------
\* Liveness under weak fairness.
\* ---------------------------------------------------------------------------
Fairness ==
  /\ (\A session \in Sessions :
        WF_variables(KillRemainingProcesses(session)))
  /\ (\A client \in Clients, session \in Sessions :
        WF_variables(AnswerKill(client, session))
        /\ WF_variables(AnswerExit(client, session)))

LiveSpecification == Specification /\ Fairness

\* kill ends every process of its session; the daemon is not in the session.
KillEndsItsSession ==
  \A session \in Sessions :
    (killing[session]) ~>
      (~(\E index \in 1..2 : <<session, index>> \in aliveProcesses))

\* shutdown ends every session.
ShutdownEndsEverySession ==
  shutdownBegan ~> (liveSessions = {})

\* every client that waits gets its answer.
EveryWaiterAnswered ==
  \A client \in Clients, session \in Sessions :
    ((client \in killWaiters[session]) ~>
        (<<client, session>> \in killAnswers))
    /\ (((client \in exitWaiters[session])
         /\ ProgramEnded(session)) ~>
        (<<client, session>> \in exitAnswers))

=============================================================================
