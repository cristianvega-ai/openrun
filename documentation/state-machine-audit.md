# OpenRun state machine audit

Audit date: 2026-11-12.
Source revision at the start: `8eeb2500b48ebd9561031dafb5e26eb7399b23c8`.
Source revision after concurrent conversation and history changes: `3d51826601118af2019a534d114a93ac6199b435`.

OpenRun has many state machines beyond its state enums and its eight TLA+ models.
The most consequential ones join thread startup, shutdown, permissions, caller identity, and ownership of a conversation.
Those machines cross actors and socket connections. Several transitions lose their protection across an `await`.

The audit screens all 706 files in the 42 directories under `Sources/`.
It traces the implementations that retain state, their callers, relevant tests, the product decisions, and the formal models.
The inventory includes application behavior and the command-line tool.
It identifies 168 implicit machines, 16 composite machines, and five delegated boundaries: 189 entries in total.
It includes resource lifetimes, bounded queues, incremental parsers, transactions, timers, callbacks, and caches whose validity affects behavior.
It excludes immutable values, pure formatting, and ordinary local loop counters.
The internals of libghostty-vt, AppKit, WebKit, Metal, and launchd are external boundaries, rather than first-party implementations audited here.

This is an audit, not a behavior change or a new product decision.
The application source and the existing tests are unchanged by this audit.


The repairs came after the audit. The section "Results of the repairs" tells what changed.

## Results of the repairs

The repairs went onto `main` on 2026-11-13, one commit for each part.
An independent review of the first version of the repairs found eight more defects, and the commits repair them too.

| Finding | Repair | Commits |
|---|---|---|
| 1 | A program that an agent started counts as a program in another session, so the user is asked first. | `4f65d7e9`, `84622721`, `98d211b4` |
| 2 | The registry and the runner reserve a thread before the first wait of a handoff. | `ce679fb2`, `57f73a6e`, `c5692a8f` |
| 3 | A Codex open and a turn start have a generation, which Stop and Close change. | `04df2bc5`, `b934f9d9`, `64a37c66`, `0670dccf` |
| 4 | The runner records a permission wait before a client sees the request. | `180335f6` |
| 5 | The gate `ThreadAdmission` seals thread work at the shutdown. | `b8e3160d`, `0b567edc`, `3c4f8c34` |
| 6 | A close of a thread ends its terminal session. | `888ae135` |
| 7 | A chat pane drops a dead connection and attaches again at the next overview. | `de3a3e9b`, `e40f50bc` |
| 8 | The chat events that wait hold at most 4,096 events and 4 MiB. | `1049913a`, `0ab1fe5c` |
| 9 | The shared step of Open in Terminal keeps the terminal out of the restart records. | `ff771891` |
| 10 | The draft of a chat keeps its held message. | `b421301a` |
| 11 | A failed answer opens its request again, and a failed message goes back into the draft. | `dfbad48b`, `0e1565da` |
| 12 | The terminal view confirms a size that the grid already has. | `dd747b61` |
| 13 | Each owner of a change of the projects or the settings checks its version. | `5b831497` |

The review found these defects in the first version of the repairs:

- While a Codex server started, every caller counted as an agent, also OpenRun.app. Only a program that the session process started counts now (`84622721`).
- A Stop during the start of a Codex turn could leave the thread busy for good, and the message went away with no word (`64a37c66`, `04df2bc5`).
- A Stop that came before Codex answered a turn start ended the app-server of the whole account. Now only the late turn ends (`eaed4f96`).
- The stage of the chat events encoded each event a second time under its lock. The reader now gives the size of the frame (`0ab1fe5c`).
- A thread that ended attached again and showed an alert (`e40f50bc`).
- A permission answer could pass a later stop. The answers now go on the queue of the messages (`dfbad48b`).
- A server of an account could start after the shutdown (`4f65d7e9`).

These limits remain:

- A program that an agent started, and that then left its parent, such as a daemon, escapes the check of finding 1. The terminal path accepts the same limit for `setsid`.
- No test makes a Codex terminal of finding 9 come back after a restart. The change moves one call into the step that both agents use.
- No test plays a Stop that comes while Codex refuses the start of a turn. A test plays a Stop and a Close during the open.

After the last commit of the repairs, the complete `swift test` passed with no failure.
Timing tests of the terminal flow, the chat speed and the row layout failed now and then under the load of other builds. They passed when they ran alone.

## Meaning of an implicit state machine

A machine is implicit when the next valid operation depends on prior events, but no single type represents all legal states and transitions.
An optional process, a task handle, a set of owners, or a queue with a completion can encode a phase just as a Boolean can.
An actor prevents concurrent access to its fields. It does not make a method atomic across an `await`.

The inventory distinguishes three forms:

- **Implicit:** flags, optionals, collections, resource ownership, or control flow carry the phases.
- **Composite:** an explicit enum describes part of the state, but other fields determine which transitions are valid.
- **Delegated:** an external system retains the state and OpenRun exposes or coordinates it.

One row describes one machine or a tightly coupled family with the same owner and transition rules.
Small timer machines remain separate because their cancellation and completion rules differ.
The states in the tables are descriptive names for current behavior. They are not proposed Swift type names.

## Findings that need attention

### High priority 1 Headless agents bypass terminal approval

[SessionServer.refusal](../Sources/SessionProcess/SessionServer.swift#L466) uses only `SessionRegistry.place(of:)` for terminal reads, input, attachment, and termination.
[CallerPlace.mayAct](../Sources/SessionProcess/CallerPlace.swift#L19) permits every target for a caller outside the known terminal sessions.
Headless agents run on pipes in a new process group, not a new terminal session.
They therefore normally take this unrestricted path.
The thread request path separately checks `ThreadRegistry.isStartedByAgent`; the terminal request path does not.

**Reproduced:** a stand-in agent started by the real `ThreadRunner` received a refusal for `listThreads`, then read a marker from an unrelated terminal through `readScreen`.
No approval question was involved.
The server knew that this process was an agent for the first request.

The caller classification machine needs one rule that includes both terminal membership and agent ancestry.
Apply that classification to every operation whose authority depends on whether the caller acts for the user.
Review protected settings, approval receivers, and the process restart request against the same rule.

### High priority 2 Terminal handoff has no reservation

[SessionServer.openInTerminal](../Sources/SessionProcess/SessionServerThreadTerminal.swift#L13) checks whether a thread already has a terminal, then suspends repeatedly before it records the new owner.
The Claude Code runner accepts messages until `openedInTerminal` eventually calls `setInTerminal`.
Two callers can both pass the initial check.
A message can also start a headless process during the handoff.

**Reproduced:** two concurrent calls for one new Claude Code thread both returned success and created two live terminal sessions for the same conversation.
The registry can retain only one of those sessions in `terminals[thread]`.

Reserve the conversation before the first suspension.
Keep a distinct handoff phase until the terminal is registered.
A failure must release the reservation.
Closing, sending, and a second handoff must observe that phase.

### High priority 3 Codex startup survives Stop and Close

[CodexThreadRunner.sendNextMessage](../Sources/SessionProcess/CodexThreadRunnerTurns.swift#L25) sets `isTurnRunning` before it awaits `openThread()`.
During that wait, `thread` can still be nil.
`stop()` and `close()` act on `thread` but neither invalidates `opening`.
`startOrResumeThread()` later publishes the new thread without checking `isClosed` or a startup generation.
The suspended send then starts its turn.

**Reproduced twice:** after Stop during opening, the stand-in Codex server returned the agent text `ok` and completed the turn.
After Close during opening, the same happened with `isClosed == true` and `thread != nil`.
The second call to `close()` returns early, so it cannot close that late thread.

Startup needs a cancellable operation identity and a checked transition from opening to open.
Recheck it after every external wait, before publishing a resource and before starting a turn.
A resource returned to an obsolete operation must be closed.

### High priority 4 Permission publication precedes registration

[ThreadRunner.askPermission](../Sources/SessionProcess/ThreadRunnerPermissions.swift#L18) emits the visible request and awaits `changed(self)` before it inserts the continuation into `waitingPermissions`.
An answer, Stop, Close, or process end can occur in that interval.
An answer finds no request. A close drains an empty dictionary.
The suspended method then registers a new wait after the request should have ended.

**Reproduced:** a `changed` callback closed the runner in this interval.
The request still registered and ended only at the shortened timeout.
It reported that the user did not answer in time instead of reporting cancellation.
In normal use the configured timeout is 24 hours.

Register the wait before publishing it and before the first suspension.
Check cancellation and the closed state at registration.
Every published request must already have one final answer path.

### High priority 5 Thread shutdown does not close admission

[ThreadRegistry.terminateAll](../Sources/SessionProcess/ThreadRegistryChanges.swift#L212) closes the current runners, but has no stopping state.
`create`, `runner`, `running`, and `openCodexServers` can still create work.
[SessionServer.shutDown](../Sources/SessionProcess/SessionServer.swift#L111) leaves existing client handlers active while it awaits termination.
Those handlers do not test `isClosed` before serving another request.

**Reproduced at the registry boundary:** after `terminateAll()` returned, `create` and `running` admitted a new thread and runner.
The missing guard also leaves an admission window during shutdown.
The terminal `SessionRegistry` already closes this window with `isStopping`.

Seal thread admission before any shutdown suspension.
Include runners that are starting and Codex account servers in the shutdown barrier.
The `SessionLifecycle` model currently covers terminal sessions, not this extension of the lifecycle.

### High priority 6 Closing a thread leaves its terminal running

[ThreadRegistry.close](../Sources/SessionProcess/ThreadRegistryChanges.swift#L75) removes the record and closes the headless runner.
It does not end the session in `terminals[identifier]` or remove that ownership entry.
The server's `closeThread` route calls only this method.

**Reproduced:** after the duplicate handoff above, closing the thread left both terminal sessions running.
The source path also shows that the ordinary single-terminal case has no terminal termination call.
The thread record disappears while its work can continue.
The close transition needs to acquire and end the current owner, including an owner in handoff.

### Medium priority 7 Cached chats do not recover their connections

[ThreadPaneController.take](../Sources/OpenRunApplication/ThreadPaneEvents.swift#L27) ignores `.closed` and `.threadEnded`.
A transport failure reports a message but does not clear the attachment or evict the pane.
[Workspace.chatPane](../Sources/OpenRunApplication/WorkspaceThreads.swift#L23) attaches only a newly created pane.
The overview reconnects independently and can retain the same thread identifiers after a session process restart.

**Established by source inspection:** a cached chat can stay attached to a dead connection after the lists recover.
Selecting it again reuses the same pane. A failed initial attachment has the same recovery gap.
Represent disconnected chat panes and invalidate or reconnect their attachments when the overview reconnects.

### Medium priority 8 Thread event delivery has an unbounded stage

[ThreadEventBatches](../Sources/OpenRunApplication/ThreadEventBatches.swift#L9) appends every event to an array until the main thread takes the batch.
The socket reader returns immediately after each append.
It therefore drains upstream queues even while the main thread cannot keep up.

**Established by source inspection:** this stage has no byte limit, event limit, coalescing, or producer wait.
The bounds in `ClientConnection`, `ThreadEventBuffer`, and `CodexEventChannel` do not bound this array.
The terminal pane already has an admission and completion design in `AttachmentRelay`.
Give the chat handoff an equivalent bound or coalesce safe event types while preserving event order.

### Medium priority 9 Codex terminal sessions enter restart records

The Claude Code path in [SessionServerThreadTerminal](../Sources/SessionProcess/SessionServerThreadTerminal.swift#L34) calls `records.exclude` for the terminal of a thread.
The Codex path creates the session and calls `openedInTerminal` without excluding it.

**Established by source inspection:** a Codex conversation terminal can remain in `sessions.json` and return as an unrelated shell after a restart.
The decision of 2026-11-12 says that a thread's terminal does not come back.
Put exclusion in the shared successful handoff path so both agents receive it.

### Medium priority 10 A held message can disappear with its pane

[ComposerLogic](../Sources/ChatView/ComposerLogic.swift#L18) retains a message submitted while the agent is busy.
That message has not reached the session process.
[ComposerView.submit](../Sources/ChatView/ComposerSending.swift#L24) clears the field and saves the now empty draft.
`ComposerDrafts` saves the field and images, but not `heldMessage`.
`ThreadPanes` evicts panes after eight threads, and a window close discards all of them.

**Established by source inspection:** either transition can discard a submitted message that still waits locally.
Choose an owner whose lifetime matches the waiting message, or return it to the saved draft before a pane closes.
That rule must also cover terminal handoff and account continuation.

### Medium priority 11 Permission controls have no failure transition

[PermissionRequestRowView.answer](../Sources/ChatView/PermissionRequestRowView.swift#L52) inserts the request into `answeredRequests` and disables its controls before the server acknowledges the answer.
Transport errors and `.requestFailed` only reach the generic failure callback.
Neither removes the identifier from `answeredRequests`.

**Established by source inspection:** a rejected or unsent answer leaves a still pending permission request disabled in the cached chat.
Distinguish an answer in flight from an answer that the server accepted.
On a refusal or failed send, allow a retry if the request still waits.

### Medium priority 12 A size acknowledgement can leave requests pending

[SessionPaneController](../Sources/SessionPane/SessionPaneController.swift#L238) appends each requested size to `ownSizeRequests`.
Activation deliberately sends a confirmed size even when the grid already has that size.
[TerminalView.applySize](../Sources/TerminalView/TerminalView.swift#L690) returns immediately for an unchanged grid, before `didApplyGridSize`.
That callback is the only place that consumes `ownSizeRequests`.

**Established by source inspection:** repeated activation at the same size can retain acknowledged requests indefinitely.
The hidden-grid logic continues to treat them as pending.
Consuming an acknowledgement must not depend on changing geometry.

### Medium priority 13 Some versioned changes become unversioned downstream

[SessionServer.changeProjects](../Sources/SessionProcess/SessionServer.swift#L507) passes a project version to `SessionRegistry`, then awaits it before calling the unversioned `ThreadRegistry.updateProjects`.
A newer request can finish that path before the older one resumes.
The older list can then replace the newer project list of the threads.
`changeSetting` has a similar final unversioned call to `AgentLaunchProvider.setProgram` after versioned actor calls.

**Established by source interleaving:** the version checks at the first consumer do not protect later consumers.
Carry the same version to every owner that stores the change.
Check the version at the mutation point, after any preceding wait.

## Complete machine inventory

The final column gives the transition contract that makes the retained state meaningful.
An obligation in this column is not a claim that the implementation always satisfies it.
The findings above identify observed or source-established violations.

### Process startup and service lifetime

| Number | Machine and source | Form | Encoding and transitions | Required property |
|---|---|---|---|---|
| 1 | [Application setup](../Sources/OpenRunApplication/OpenRunApplication.swift) and `LaunchAgentSetup` | Composite | `setupIsReady`, `setupIsRunning`, registration status, and setup outcome. Unprepared → setup in progress → ready, approval required, failed, or cancelled. Retry and registration replacement enter setup again. | Start one setup operation at a time. Start the workspace only after readiness. |
| 2 | [Wake request](../Sources/SessionLaunch/SessionWake.swift) | Implicit | Optional outcome, semaphore, deadline, and owned XPC session. Created → request sent → answered or timed out → cancelled. | One result releases the caller. A timeout releases the session. |
| 3 | [Wake service](../Sources/SessionLaunch/SessionWakeService.swift) | Delegated | XPC listener exists only after socket readiness. Listening → cancelled before socket shutdown. launchd holds later wake requests. | An answered wake must point at a ready listener. |
| 4 | [Process run](../Sources/SessionProcess/SessionProcess.swift) and `ShutdownSignals` | Implicit | Scope-owned server, signal sources, wake service, and competing tasks. Initialize → restore → serve → first signal, idle exit, or app end request → cancel other waits → shut down. | One trigger starts shutdown. Every owned service and child reaches its end. |
| 5 | [Socket listener and lock](../Sources/SessionProcess/SocketListener.swift) | Implicit | Lock descriptor, bound socket, accept source, and cancellation ownership. Take lock → validate stale path → bind → accept → remove socket → release resources. Initialization failures unwind acquired resources. | One server owns the socket. A reused file descriptor is never closed by an old owner. |
| 6 | [Server restoration and shutdown](../Sources/SessionProcess/SessionServer.swift) | Implicit | `recordsToRestore`, `acceptTask`, `isClosed`. Restore records → accept clients → close listener → freeze records → terminate sessions and threads → drain clients. | Close admission before shutdown awaits. Restore each record at most once. |
| 7 | [Client admission](../Sources/SessionProcess/SessionServer.swift) | Implicit | `clients`, `handlers`, and each connection's final-close wait. Accept → reserve a place → serve → drain → descriptor closed → remove place. | The client limit includes sockets whose handlers finished but whose resources remain. |
| 8 | [Idle exit](../Sources/SessionProcess/IdleExit.swift) and `SessionServer.closeWhenIdle` | Implicit | `lastBusy`, client membership, terminal sessions, and thread process facts. Busy → idle candidate → recheck after awaits → grace expired → close. | A new client or work invalidates an idle decision. |
| 9 | [Terminal session registry](../Sources/SessionProcess/SessionRegistry.swift) | Implicit | Session dictionary, limits, versions, and `isStopping`. Absent → constructed and reserved → running → removed. Running registry → stopping rejects new construction. | Reserve before suspension. No terminal starts after shutdown begins. |
| 10 | [Ended terminal identity retention](../Sources/SessionProcess/SessionRegistry.swift) | Implicit | `endedTerminalSessions` and the live-session census. Live known session → ended but descendants may remain → no descendants → forgotten. | A surviving child of an ended terminal does not become an unrestricted user caller. |

Relevant tests: `LaunchAgentSetupTests`, `SessionWakeTests`, `SocketSecurityTests`, `SessionLifecycleTests`, `IdleExitTests`, `CallerPlaceTests`, and `ShutdownTests`.
The terminal registry and idle-exit abstraction appear in `SessionLifecycle.tla`.

### Socket protocol and connections

| Number | Machine and source | Form | Encoding and transitions | Required property |
|---|---|---|---|---|
| 11 | [Protocol greeting](../Sources/SessionProtocol/MessageConnection.swift) | Implicit | Role, expected first message, protocol version, optional capability fields, and hello deadline. Connected → hello → compatible and usable, refused, or closed. | No request is served before agreement. Capabilities gate optional protocols. |
| 12 | [Frame reception](../Sources/SessionProtocol/MessageConnection.swift) | Implicit | Read position, frame length, kind, admission callback, progress time, and deadline policy. Between frames → length → kind → room → payload → decode. | EOF between frames differs from EOF inside a frame. A slow frame stays bounded. |
| 13 | [Frame transmission](../Sources/SessionProtocol/MessageConnection.swift) | Implicit | Send lock, cached socket timeout, byte offset, and progress clock. Waiting for lock → writing whole frame → complete, stalled, or failed. | Frames never interleave. A partial write cannot be reported as complete. |
| 14 | [Server connection phase](../Sources/SessionProcess/ClientConnection.swift) | Composite | Explicit `Phase`, `hasLeft`, read-ahead closure, and queued work. Open → closing after queued sends → ended; immediate failure skips draining. | Nothing new enters a closing connection. Leave handlers run once. |
| 15 | [Socket destruction barrier](../Sources/SessionProcess/ClientConnection.swift) | Implicit | `readingHasStopped`, `writingHasStopped`, `isClosed`, and close waiters; `MessageConnection` atomically replaces its descriptor with -1. | Close only after both users stop. Release all close waiters once. |
| 16 | [Read admission and control reserve](../Sources/SessionProcess/ReadAhead.swift) | Implicit | Unhandled byte and message counts, reserve ownership, condition, closed flag. Shared room → full → control reserve or wait → released; close wakes waits. | Detach can pass full typed input. Every admitted frame releases exactly its own room. |
| 17 | [Connection role](../Sources/SessionProcess/SessionServer.swift) | Implicit | Local `attachedSession`, `attachedThread`, `isWatching`, and membership in approval answerers. Request connection → session attachment, thread attachment, watcher, or answerer → detach or leave. | Role restrictions and stream ownership stay consistent. Unrelated replies must not enter a feed. |
| 18 | [Output queue admission](../Sources/SessionProcess/ClientConnection.swift) | Implicit | Queued bytes, queue order, phase, and per-send completion. Frame admitted → write queued → complete or failed → subtract charge. Oversized admission ends the connection. | Budget counters and completions settle on every path, including refusal. |
| 19 | [Output room and viewer precedence](../Sources/SessionProcess/ClientConnection.swift) and `Session.waitForOutputRoom` | Implicit | High and low marks, waiter identity, snapshot grace, exit flag, progress observer, and one pause deadline. Full → wait → drain, faster viewer, timeout, detach, or program exit. | One pause has one deadline. Obsolete timeouts cannot close a new wait. |
| 20 | [Client connection transfer](../Sources/SessionConnection/SessionClient.swift) | Implicit | A synchronous request owner hands its `MessageConnection` to an attachment or receiver. Request/reply → streaming ownership. | The former owner must stop reading replies once another receiver owns the stream. The API does not encode that transfer in its type. |
| 21 | [Terminal attachment client](../Sources/SessionConnection/SessionAttachment.swift) | Implicit | Attach reply sequence, retained snapshot, one-shot `isReceiving`, and sticky `confirmationRequested`. Attach → snapshot available → receive output and size changes → exited, closed, or failed. | Restore precedes live output. Only one reader starts. Confirmation failures end the correct attachment. |
| 22 | [Thread and feed receivers](../Sources/SessionConnection/ThreadAttachmentReceiving.swift) | Implicit | Atomic one-shot reader ownership and expected message kinds. `ThreadAttachment` also separates replay from live events. `SessionChangeReceiver` retains the first list; `ApprovalQuestionReceiver` retains its answer channel. | Each receiver has one reader and one final transport event. Unknown events cannot corrupt framing. |
| 23 | [Change feed](../Sources/SessionProcess/SessionChangeFeed.swift) | Implicit | Summaries, optional first project/settings/thread lists, watcher membership, thread subscriptions, and `isStopping`. Register snapshot → ordered changes → removal or shutdown suppression. | Snapshot and subscription have no gap. End follows the last change. Shutdown does not announce permanent session deletion. |
| 24 | [Cross-session approval](../Sources/SessionProcess/ApprovalQuestions.swift) | Implicit | Waiting continuations and timers, answerer ownership sets, one pending question per caller session. Register → publish → allowed, denied, timeout, withdrawn, or no answerer → remove. | Only the first final answer applies. Every visible question already has a registered wait. |

Relevant tests: `MessageConnectionTests`, `MessageFrameTests`, `ConnectionLimitTests`, `HostileClientTests`, `ApprovalQuestionsTests`, `ApprovalQuestionFlowTests`, `SessionChangeFeedTests`, and the tests in `SessionConnectionTests`.
Formal coverage includes parts of `AttachSequence`, `LocalDelivery`, and `ApprovalQuestion`.
It does not cover every legal or illegal combination of connection roles.

### Terminal sessions

| Number | Machine and source | Form | Encoding and transitions | Required property |
|---|---|---|---|---|
| 25 | [Session lifetime](../Sources/SessionProcess/Session.swift) | Implicit | `runTask`, `isEnding`, `isFinished`, optional `programExit`, and client membership. Constructed → reading → termination requested or natural exit → final output → notify and remove. | Final output precedes exit. Termination cannot wait forever on a paused viewer. |
| 26 | [Snapshot attachment transaction](../Sources/SessionProcess/Session.swift) | Implicit | Previous size, waiting resize, snapshot result, client membership, and size-announcement deferral. Resolve wait → resize → capture → register or roll back. | Refused attachments leave no partial subscription and no false size announcement. |
| 27 | [Immediate resize transaction](../Sources/SessionProcess/Session.swift) | Implicit | Terminal model size, kernel size, reply-gate override, and rollback result. Validate → resize model → resize program → commit; failure restores the prior size where possible. | Model, program, and clients agree on the size that actually committed. |
| 28 | [Line editor resize wait](../Sources/SessionProcess/LineEditorWait.swift) | Implicit | `request`, `answer`, `number`, earlier-byte count, `next`, owed-client set, and `answerIsLate`. No wait → wait for fresh erase → timed-out model resize → late-answer wait → finish and apply newest queued resize. | Match an answer to its width and generation. Old output cannot answer a new request. Superseded confirmations still settle. |
| 29 | [Reply ownership gate](../Sources/SessionProcess/Session.swift) | Implicit | Connected pseudo terminal, closed flag, relaying-client membership, and temporary resize override. Local replies → real-terminal replies while a relay exists → local replies again. | Each query has one responsible source, subject to the accepted multiple-relay limitation. |
| 30 | [Terminal event accumulation](../Sources/SessionProcess/TerminalEvents.swift) | Implicit | Bell/title flags and optional notification. Reset → callbacks during one parse → apply facts and alert → reset. | A callback affects the current parse once. Notification text takes precedence over a bare bell. |
| 31 | [Activity and attention](../Sources/SessionProcess/SessionActivity.swift) | Implicit | Foreground facts and last work-output, activity, and typed-key times. Working → quiet grace → idle; recent typing suppresses a bell alert. | Output at a shell prompt and output from working programs have the intended different effects. |
| 32 | [Foreground refresh schedule](../Sources/SessionProcess/Session.swift) | Implicit | Optional `factsRefresh`, activity time, ending and finished flags. Inactive → polling while active → final quiet refresh → inactive; end cancels it. | Silent sessions stop polling. Only one refresh task owns the schedule. |
| 33 | [Summary publication schedule](../Sources/SessionProcess/Session.swift) | Implicit | Last published value/time and optional delayed task. Changed facts → immediate publish or pending newest summary → publish → idle. | The publication rate is bounded. The delayed publish includes the latest facts and never follows final removal. |

Relevant tests: `ReattachTests`, `ResizeTests`, `ResizeConfirmationTests`, `LineEditorResizeTests`, `LineEditorWaitTests`, `SessionActivityTests`, `SessionChangesTests`, and `QueryReplyTests`.
`AttachSequence.tla` and `ResizeWait.tla` describe the main ordering contracts here.

### Program input output and destruction

| Number | Machine and source | Form | Encoding and transitions | Required property |
|---|---|---|---|---|
| 34 | [Terminal program launch](../Sources/PseudoTerminal/ProgramLaunch.swift) | Implicit | Parent/child branches, acquired descriptors, terminal setup steps, and the error-report pipe. Allocate → fork → establish terminal and environment → execute; report or EOF tells the parent the outcome. | A failed launch leaves no unowned child. Only successful execution commits ownership. |
| 35 | [Pseudo terminal output flow](../Sources/PseudoTerminal/PseudoTerminal.swift) | Implicit | Unconsumed byte count and read-source suspension flag. Read → high mark pauses → consumption below low mark resumes → final drain and stream finish. | Suspension is balanced. Output remains ordered and bounded while the consumer stalls. |
| 36 | [Input backlog](../Sources/PseudoTerminal/InputBacklog.swift) | Implicit | Waiting input, admitted pieces, owner identities, answer charges, and `frontHasStarted`. Wait → admit → partial write → complete; withdrawal removes only eligible pieces; close settles all waits. | Keys remain whole once their write starts. Replies preserve order. Withdrawn owners leave no eligible bytes. |
| 37 | [Typed-input cancellation](../Sources/PseudoTerminal/PseudoTerminal.swift) | Implicit | Withdrawal ticket, cancellation callback, and checked continuation. Before registration → waiting → taken, withdrawn, or program ended. | Cancellation before registration is remembered. Each caller resumes once. |
| 38 | [Input write source](../Sources/PseudoTerminal/PseudoTerminal.swift) | Implicit | Backlog emptiness, `writeSourceIsSuspended`, terminal closure, and pump progress. Empty and suspended → pending and resumed → drained; destruction resumes before cancellation. | A suspended dispatch source cannot prevent its cancellation handler from running. |
| 39 | [Terminal exit and reap](../Sources/PseudoTerminal/PseudoTerminal.swift) | Implicit | Exit source, optional exit value, retry flag, and exit waiters. Running → exit notification → waitpid retry if needed → drain output → store result → resume waits. | One reap establishes the status. No status waiter remains after the result is known. |
| 40 | [Master descriptor lifetime](../Sources/PseudoTerminal/PseudoTerminal.swift) | Implicit | `sourcesStillUsingMaster`, source cancellation handlers, and master descriptor sentinel. Two users → one user → no users → close once. | Neither source can observe a closed or reused master descriptor. |
| 41 | [Terminal process termination](../Sources/PseudoTerminal/PseudoTerminal.swift) and `TerminalSessionProcesses` | Implicit | Live session census, process groups, stopped jobs, grace deadline, and killing deadline. Hang up groups → continue stopped jobs → grace → kill surviving session members. | End the intended terminal session without signalling an unrelated reused process. |
| 42 | [Pipe program ownership](../Sources/AgentProgram/AgentProgram.swift) and `PipeSpawn` | Implicit | Acquired pipe ends, dispatch sources, optional reaper/exit, weak callbacks, and deinitialization. Spawn → watch → run → reap or owner release → end streams and cancel sources. | Every acquired resource has one cleanup owner, including partial initialization and abandoned programs. |
| 43 | [Agent standard input](../Sources/AgentProgram/AgentProgramInput.swift) | Implicit | Pending writes, per-write offset and continuation, `inputIsClosing`, descriptor, and source suspension. Queue → partial write → complete; close drains queued writes before EOF; end fails them. | Write order and completion truth are preserved. Nothing enters after input closure. |
| 44 | [Agent output and error](../Sources/AgentProgram/AgentProgramOutput.swift) | Implicit | Unconsumed output, source suspension, bounded standard-error tail, EOF, and process end. Read → pause/resume → final drain → finish. | Output backpressure does not lose the final bytes. Standard error stays bounded. |
| 45 | [Process group reaper](../Sources/AgentProgram/ProcessGroupReaper.swift) | Implicit | Exit source, `hasReaped`, process identity, and delayed checks. Watch → detect exit without early identity release → end descendants → reap → finish. | Signals cannot hit a new program that reused the identifier. A lost owner still leaves a reaper. |

Relevant tests are in `PseudoTerminalTests` and `AgentProgramTests`, plus `InputBacklogTests`, `JobControlTests`, and `ShutdownTests`.
`InputBacklog.tla` covers the backlog contract. `SessionLifecycle.tla` abstracts part of termination.

### Thread records runners and conversation ownership

| Number | Machine and source | Form | Encoding and transitions | Required property |
|---|---|---|---|---|
| 46 | [Durable thread registry](../Sources/SessionProcess/ThreadRegistryChanges.swift) | Implicit | Record list, summaries, and stored file. Create/change/rename → save candidate → commit and publish; failed save restores the prior list; close removes the record. | Visible records and accepted mutations have a defined persistence outcome. |
| 47 | [Runner admission and shutdown](../Sources/SessionProcess/ThreadRegistry.swift) | Implicit | Claude/Codex runner dictionaries, lazy account servers, and outstanding creation calls. Dormant record → runner created on first use → closed and removed. Shutdown closes known runners. | No runner may appear beyond the shutdown barrier. This protection is currently missing. |
| 48 | [Runner fact publication](../Sources/SessionProcess/ThreadRegistryChanges.swift) | Implicit | Runner identity, captured facts, record copy, process-to-thread map, summaries, and slot release. Read facts across actors → validate owner → update persistence and indexes → publish. | Stale facts cannot resurrect a closed runner or overwrite a newer authoritative record. |
| 49 | [Agent process slots](../Sources/SessionProcess/AgentProcessSlots.swift) | Implicit | Holder set, waiting order, limit, and registry idle-runner selection. Free → reserved → process running → release and transfer; waiting threads leave on Stop or Close. | Holders and waiters remain consistent. A granted slot eventually starts work or returns to the pool. |
| 50 | [Claude Code process startup](../Sources/SessionProcess/ThreadRunnerProcess.swift) | Implicit | `program`, `isStartingProcess`, `endWasRequested`, closed flag, and conversation-resume fact. Absent → slot wait → launch-settings wait → spawned → output reader → ended. | A late launch cannot outlive Close. Startup failure must release its reservation. |
| 51 | [Claude Code message queue](../Sources/SessionProcess/ThreadRunnerMessages.swift) | Implicit | Waiting messages, message identifiers, `activeMessage`, start flag, and process-ending flag. Accepted locally → wait → write → active turn → turn or process end → next message. | A message removed by Stop cannot later start. At most one active turn owns the next completion. |
| 52 | [Claude Code Stop and Close](../Sources/SessionProcess/ThreadRunnerMessages.swift) | Implicit | Closed/requested-end flags, active message, queued messages, permissions, process identity, and grace wait. Stop removes queued work and interrupts; Close also ends listeners and the process. | Stop cannot silently restart queued work. Close is final even during startup. |
| 53 | [Quiet process eviction](../Sources/SessionProcess/ThreadRunnerProcess.swift) | Implicit | `lastUse`, computed `idleSince`, `quietTask`, and requested-end state. Busy → idle timer → recheck → end process; new work invalidates the timer. | A timer cannot end a process whose idle interval is obsolete. |
| 54 | [Model and permission-mode restart](../Sources/SessionProcess/ThreadRunnerMessages.swift) | Implicit | Record launch facts and `endsAfterTurn`. Change while idle → end now; change during a turn → end after turn; next message resumes with new facts. | Old settings cannot start a new turn after the replacement takes effect. |
| 55 | [Conversation handoff](../Sources/SessionProcess/SessionServerThreadTerminal.swift) and `ThreadRegistry.terminals` | Implicit | Headless runner, `isInTerminal`, terminal map, history boundary, and terminal session. Chat → stop headless → launch terminal → terminal owner → terminal ends → import history → chat. | One conversation has one owner. Intermediate handoff and close transitions need a reservation. |
| 56 | [Claude Code tool permission](../Sources/SessionProcess/ThreadRunnerPermissions.swift) | Implicit | Permission dictionary, continuation, timer, matching tool call, and caller cancellation. Publish/register → await user → allowed, denied, timeout, Stop, process end, or hook departure. | Register before publication. Every other end denies. First final outcome wins. |
| 57 | [Thread replay buffer](../Sources/SessionProcess/ThreadEventBuffer.swift) and runner attachment | Implicit | Encoded entries, byte count, turn-end markers, earlier-event flag, and listeners. Append → trim oldest whole turns or an oversized current turn → replay → mark complete → live delivery. | Replay and live events have no gap or repeat. The retained boundary accurately signals missing history. |
| 58 | [Agent launch settings cache](../Sources/SessionProcess/AgentLaunchProvider.swift) | Implicit | Optional login-shell environment and current program choice. Unread → asynchronous environment read → cached; program changes affect later starts. | Concurrent first callers should share one read. Late settings must not replace newer choices. |
| 59 | [Codex runner opening](../Sources/SessionProcess/CodexThreadRunnerTurns.swift) | Implicit | Optional `thread`, shared `opening` task, closed flag, and conversation record. Unopened → one start/resume in flight → open → stream ended or closed. | Stop, Close, and handoff must invalidate an opening operation before it can publish or send. |
| 60 | [Codex runner turn queue](../Sources/SessionProcess/CodexThreadRunnerTurns.swift) | Implicit | Waiting `CodexTurn` values, `isTurnRunning`, optional open thread, and events. Queue → remove front and mark running → await start → completed/failed → next. | A completion belongs to the correct active operation. Stop removes both waiting and not-yet-started work. |
| 61 | [Codex terminal return](../Sources/SessionProcess/CodexThreadRunnerTerminal.swift) | Implicit | `isInTerminal`, app-server lease, terminal ownership, known transcript turns, and history request. Leave app-server → terminal owner → resume server → import unknown turns → chat. | History import and ownership return complete before a new headless turn can race them. |

Relevant tests: `ThreadRunnerTests`, `ThreadRunnerPermissionTests`, `ThreadRunnerEndTests`, `ThreadProcessLimitTests`, `AgentProcessSlotsTests`, `ThreadTerminalTests`, `ThreadRegistryTests`, and `CodexThreadTests`.
`ThreadPermission.tla` covers permission outcomes, but not the suspension between publication and registration.
No existing model describes runner startup, process slots, or the full conversation handoff.

### Codex account servers and transport

| Number | Machine and source | Form | Encoding and transitions | Required property |
|---|---|---|---|---|
| 62 | [Account server pool](../Sources/CodexAgent/CodexAccountServers.swift) | Implicit | Per-account start task, generation, user count, thread set, and release callbacks. Missing → starting → leased → last user/thread releases → remove and shut down. | A release from an old generation cannot remove its replacement. Shutdown must prevent new leases. |
| 63 | [App-server lifetime](../Sources/CodexAgent/CodexAppServer.swift) | Implicit | Connection, `isShuttingDown`, `hasEnded`, open threads, and approvals. Spawn → initialize → initialized → serve → requested shutdown or process end → finish channels. | Failure of the handshake ends the process. End settles all threads and approvals. |
| 64 | [Request correlation](../Sources/CodexAgent/CodexConnection.swift) | Implicit | Next identifier, waiting continuations and timers, ended flag. Register and send → response, refusal, cancellation, timeout, or connection end → remove. | Each request settles once. Late answers cannot satisfy another request. |
| 65 | [Outgoing line writer](../Sources/CodexAgent/CodexConnection.swift) | Implicit | Async line stream and writer-task lifetime. Queue lines → serial writes → write failure or stream finish → writer ends. | Preserve line order. Failure and owner release must not strand queued request continuations. |
| 66 | [Thread subscription routing](../Sources/CodexAgent/CodexAppServerThreads.swift) and `CodexAppServerNotifications` | Implicit | Open thread map, bounded early lines, unsubscribe counts, and unsubscribe tasks. Unknown during start → buffer → open and replay; closing → drop late lines until unsubscribe settles. | Old subscription output cannot become new history after resume. One stalled thread does not hold others. |
| 67 | [App-server turn lifecycle](../Sources/CodexAgent/CodexAppServerTurns.swift) and `CodexTurnEvents` | Implicit | Starting-turn count, pending user identifiers, requested turn, active turn, and last ended turn. Start request → accepted/started → active → ended; late output becomes status. | Stop can find a turn before its start reply. Late output cannot reopen a completed turn. |
| 68 | [Codex stop sequence](../Sources/CodexAgent/CodexAppServerStop.swift) | Implicit | Start and completion deadlines, approvals, turn identity, background-terminal results, and warning flag. Decline → await turn identity → interrupt → await end → list/terminate commands. | Bounded waits apply to the right turn. Failure to end commands remains visible. |
| 69 | [Codex approval lifecycle](../Sources/CodexAgent/CodexAppServerApprovals.swift) | Implicit | Approval map, request/item/thread identities, timer, and mapper decline reason. Register → publish/update detail → user answer, withdrawal, timeout, Stop, or server end → remove. | A removed approval never allows later. Closing the server sends no impossible answer. |
| 70 | [Per-thread event channel](../Sources/CodexAgent/CodexEventChannel.swift) | Implicit | Event queue, byte sizes, optional waiting reader, and finished flag. Empty → waiting reader or queued events → coalesce/drain → overflow or finish → final event then EOF. | Bound unread work. Resume a reader once. Finishing preserves earlier queued events. |
| 71 | [Item event reconstruction](../Sources/CodexAgent/CodexEventMapper.swift) and item-event files | Implicit | Started item cache, pending message identifiers, active-turn context, and decline reasons. Start → deltas → complete, refused, or interrupted; some events arrive without their start. | Reconstructed item identities and completion remain stable under reordered or missing optional events. |
| 72 | [Token and account usage accumulation](../Sources/CodexAgent/CodexTurnEvents.swift) | Implicit | `tokensBeforeTurn`, `tokensNow`, and account-wide readings distributed to open threads. Capture baseline → accumulate totals → compute turn difference → next baseline. | Usage belongs to its account and turn. Totals must not be mistaken for a turn's delta. |
| 73 | [Codex history paging](../Sources/CodexAgent/CodexAppServerHistory.swift) and `CodexHistory` | Implicit | Open-thread lease, opaque cursor, page limit, chronological reconstruction, and stopped-turn treatment. Newest page → prior cursor pages → beginning. | Preserve whole-turn order and opaque cursor ownership. A stopped turn must not imply an answer that history does not retain. |

Relevant tests are in `CodexAgentTests`, including transport, routing, approvals, stopped turns, account pools, hostile output, history, and end-to-end fixtures.
There is no Codex-specific TLA+ model.

### Conversation reduction and agent decoding

| Number | Machine and source | Form | Encoding and transitions | Required property |
|---|---|---|---|---|
| 74 | [Transcript state reduction](../Sources/AgentConversation/Transcript.swift) | Composite | `ThreadState`, open items, waiting permissions, thinking, and event kind. Idle/finished/failed → in progress → needs user → in progress → turn outcome or process end. | Summary state agrees with pending items and permissions. A terminal event closes the work it leaves open. |
| 75 | [User message acknowledgement](../Sources/AgentConversation/Transcript.swift) | Implicit | Stable message identity and `isAccepted`. Optimistic local item → agent echo → accepted item; duplicates merge. | One user message remains one item. A later duplicate cannot undo acceptance. |
| 76 | [Agent text assembly](../Sources/AgentConversation/Transcript.swift) | Implicit | Item identity, bounded text, completion flag, and open-item membership. Missing → streamed text → complete replacement → closed; end closes partial text. | The final text replaces deltas. Later deltas cannot append to a completed answer. |
| 77 | [Tool call assembly](../Sources/AgentConversation/TranscriptToolCalls.swift) | Composite | `ToolCallItem.State`, input text/value, output count, refusal, and open-item membership. Preparing → running → succeeded, failed, refused, or interrupted. | Refusal remains final when its error result arrives. Inputs and outputs stay bounded and correlated. |
| 78 | [Transcript permission item](../Sources/AgentConversation/TranscriptRequests.swift) | Implicit | Request, optional end, waiting/open sets, and matching tool identity. Requested or refreshed → final outcome → folded item. | A refreshed request cannot erase a final answer. Waiting membership matches the visible item. |
| 79 | [Sub-agent task correlation](../Sources/AgentConversation/TranscriptRequests.swift) | Implicit | Task-to-call maps, reverse maps, optional start/end, and bounded task messages. Message-before-start → bind start → progress → end → trim and remove mappings. | Out-of-order task events reach one task. Trimming removes every obsolete mapping. |
| 80 | [Transcript retention](../Sources/AgentConversation/TranscriptStorage.swift), `RecentIdentifiers`, and `Transcript` | Implicit | Byte counts, item positions, moving first position, dropped-identifier set/order, and open-item sets. Insert/update → exceed limit → drop oldest → retain tombstone → bounded expiry. | Counts and indexes agree. A late delta does not immediately recreate an evicted item. |
| 81 | [History merge and terminal import](../Sources/AgentConversation/TranscriptHistory.swift) | Implicit | Known turns and user identifiers, history namespace, prior transcript, and item limits; `TranscriptHandover` derives a continuation draft. Read older turns → deduplicate → prepend or append only unknown turns → trim. | No repeated live turn or conflicting item identifier appears after history import. |
| 82 | [Sign-in advice](../Sources/AgentConversation/Transcript.swift) and `ThreadPaneController.refreshSignInAdvice` | Composite | Newest failed turn, later user message, and `ChatThreadCondition`. Normal → failed authentication → advice visible → later message or different condition clears/replaces it. | Live events and loaded history give the same advice. Other thread conditions retain precedence. |
| 83 | [Line splitting and recovery](../Sources/AgentConversation/LineSplitter.swift) | Implicit | Partial byte buffer, skipped-line prefix, and skipped byte count. Accumulate → line end → emit; over limit → discard until newline → recover; EOF emits or reports tail. | Split UTF-8 and oversized lines do not corrupt the next line or grow memory without bound. |
| 84 | [Claude Code stream decoder](../Sources/ClaudeCodeAgent/ClaudeCodeLineDecoder.swift) and `ClaudeCodeStreamLines` | Implicit | Streamed message, tool blocks, pending block kinds/indexes, completed-message count, error kind, and agent-task set. Message start → block deltas → full assistant blocks → turn result/reset. | Streamed and complete forms address the same item. Error context belongs to the turn it ends. |
| 85 | [Permission-to-tool matching](../Sources/ClaudeCodeAgent/ClaudeCodeToolCallMatcher.swift) | Implicit | Candidate calls and claimed state. Observe tool input → match hook request → claim once → retire or bound old candidates. | A permission request does not take a different call merely because it has the same tool name. |
| 86 | [Claude Code backward history](../Sources/ClaudeCodeAgent/BackwardLineReader.swift) and `ClaudeCodeHistoryReader` | Implicit | File position, buffer start, partial line, start-of-file flag, page budget, and user-turn boundary. Read backward → skip cut lines → collect whole turns → return cursor → reach start. | A page boundary never invents half a turn. The next cursor continues the same file traversal. |

Relevant tests are in `AgentConversationTests` and `ClaudeCodeAgentTests`.
They cover stream splits, duplicates, missing starts, trimming, task maps, history pages, and authentication outcomes.
These reducers have no dedicated formal model.

### Incremental Markdown

| Number | Machine and source | Form | Encoding and transitions | Required property |
|---|---|---|---|---|
| 87 | [Streaming document](../Sources/MarkdownText/MarkdownDocument.swift) | Implicit | Previous text, completion, shown-byte boundary, blocks, and restart points. New document → append-compatible partial reparse or full replacement → hide ambiguous tail → finalize. | An append reuses only valid earlier blocks. Finalization reveals the retained partial tail correctly. |
| 88 | [Block grammar](../Sources/MarkdownText/MarkdownBlockParser.swift) and block-specific files | Implicit | Line index, paragraph continuation, open fence, list indentation, quote depth, table header/separator lookahead, and completion context. Text → paragraph, fence, list, quote, or table → close or carry incomplete tail. | Streaming and complete parsing converge to the same block structure. Nesting and fence closure belong to the correct scope. |
| 89 | [Inline grammar](../Sources/MarkdownText/MarkdownInlineParser.swift) and inline-specific files | Implicit | Recursive ranges, current styles/link, delimiter runs, escaped characters, and streaming flag. Plain text → code/emphasis/link/address scope → close, escape, or provisional end. | An unfinished delimiter or link does not consume unrelated later text. Final output has stable text and ranges. |

Relevant tests are in `MarkdownTextTests`, including streaming, fences, tables, lists, inline parsing, and rendering.

### Application coordination

| Number | Machine and source | Form | Encoding and transitions | Required property |
|---|---|---|---|---|
| 90 | [Workspace startup](../Sources/OpenRunApplication/WorkspaceRefresh.swift) | Implicit | `isStarted`, `showsSessionAtStart`, first-list flags, saved selection, and pending selection. Show window → obtain authoritative lists → restore/select or create one first shell → ordinary use. | Unknown initial lists are not an empty workspace. Closing the last session later does not create another shell. |
| 91 | [Overview connection](../Sources/SessionOverview/SessionOverviewConnection.swift) | Composite | `ConnectionStatus`, generation, receiver, started flag, retry delay, capabilities, build, and list-readiness flags. Connect → receive → disconnect retaining facts → delayed retry; stop invalidates generations. | Old results cannot replace a newer connection. Readiness and stale data must be distinguished. |
| 92 | [Overview batch coalescing](../Sources/SessionOverview/PendingChanges.swift) | Implicit | Pending events and replaceable positions by session/thread, projects, and settings. Empty → schedule one drain → replace superseded values → list/end barriers reset replacement positions → drain. | Coalescing cannot move a change across a snapshot or end barrier. |
| 93 | [Approval channel retry](../Sources/OpenRunApplication/ApprovalQuestionConnection.swift) | Implicit | Started flag, optional receiver, alerts owner, and retry delay. First connect → accepted or refused → receive questions → disconnected → delayed retry. | Only the active connection owns answers and alerts. Retry tasks must not multiply or survive their intended owner. |
| 94 | [Approval modal queue](../Sources/OpenRunApplication/ApprovalQuestionAlerts.swift) | Implicit | FIFO questions, optional shown alert, `shownHasEnded`, and deferred run-loop block. Queue → display one modal → user answer or server withdrawal → next. | A withdrawn alert cannot send an answer after its modal loop ends. |
| 95 | [Thread pane attachment and replay](../Sources/OpenRunApplication/ThreadPaneController.swift) and `ThreadPaneEvents` | Implicit | Attachment, closed flag, transcript, and `isReplayComplete`. Attach off main thread → replay → show once at mark → live batches → close or transport loss. | Late attachment results must release their resources. A lost transport needs an explicit recoverable phase. |
| 96 | [Thread main-thread batches](../Sources/OpenRunApplication/ThreadEventBatches.swift) | Implicit | Mutex-protected event array and empty-to-nonempty wake rule. Empty → append and schedule → append more → take all → empty. | The stage needs a bounded admission rule. A single wake is not a memory bound. |
| 97 | [Chat history loading](../Sources/OpenRunApplication/ThreadPaneHistory.swift) | Implicit | Loading flags in pane and chat facts, byte cursor or opaque token, page count, transcript limit, and request callback. Idle → request → merge → stop at start/limit or fetch another duplicate-only page. | At most one page loads per pane. Closed or replaced panes must not apply obsolete results. |
| 98 | [Shown-content reconciliation](../Sources/OpenRunApplication/WorkspaceContent.swift) | Composite | `ShownContent`, stale flag, lost/exited session sets, selected row, and live overview. Empty/notice/session/thread/split → desired new content → deactivate old → install new → restore focus. | Cached content is reused only while valid. A disconnected pane is not mistaken for an ended session. |
| 99 | [Terminal pane cache](../Sources/OpenRunApplication/SessionPanes.swift) | Implicit | Pane dictionary and recent-use order. First use creates → reuse moves to newest → ninth cached pane evicts oldest → window close closes all. | Each eviction detaches once and removes both indexes. Visible split leaves need a valid cache owner. |
| 100 | [Chat pane cache](../Sources/OpenRunApplication/ThreadPanes.swift) | Implicit | Chat dictionary and recent-use order. First use attaches → reuse → eviction or window close calls `close`. | Unsent and held user work must survive the pane lifetime boundary. Dead attachments must not remain reusable. |
| 101 | [Browser pane lifetime](../Sources/OpenRunApplication/WorkspaceBrowser.swift) | Implicit | Browser dictionary, remembered layout leaves, addresses, and address-change callbacks. First display creates → reuse/navigate → last owning row/leaf disappears → forget. | A browser cannot outlive its owning row as an orphaned list entry. |
| 102 | [Split keyboard ownership](../Sources/OpenRunApplication/WorkspaceSplits.swift) | Implicit | `lastFocusedLeaf`, `leafToFocus`, current first responder, split tree, and thread-to-terminal substitution. Split or restore → defer focus → attach/layout → activate leaf → neighbor after close. | Input, close, and handoff target the actual focused leaf. |
| 103 | [Selection after asynchronous creation](../Sources/OpenRunApplication/WorkspaceRefresh.swift) | Implicit | `sessionToSelect`, `projectToSelect`, saved selected row, and refresh guard. User requests creation → wait for reply/feed → find row → select and focus → clear request. | An absent item stays pending rather than selecting a different row. Programmatic refresh is not a new user choice. |
| 104 | [Close confirmation](../Sources/OpenRunApplication/WorkspaceSessions.swift), `WorkspaceThreads`, and questions | Implicit | Captured target, program facts, pending sheet/modal callback, and later request result. Request close → decide whether to ask → confirm/cancel → execute against captured target. | A selection change during the question does not redirect the destructive action. A thread close ends its current owner. |
| 105 | [Build comparison and restart](../Sources/OpenRunApplication/WorkspaceSessionProcess.swift) | Implicit | Running build, `knownBuilds`, asynchronous bundled-build read, and restart confirmation. Unknown build → read → recheck current build → offer once → user decision → end request. | A stale comparison cannot restart a different process. Only the user authorizes restart. |
| 106 | [Terminal alert delivery](../Sources/OpenRunApplication/WorkspaceAlerts.swift) and `SystemAlertNotifier` | Implicit | Prior/current alerts, viewed session, notification setting, authorization callback, delivered notification, and cleared-alert timestamp. New alert → request permission/post or suppress → clear/remove. | A late post must not reintroduce an alert already cleared. One clear request belongs to one alert generation. |
| 107 | [Thread attention and Dock count](../Sources/OpenRunApplication/WorkspaceThreads.swift) and `WorkspaceAlerts` | Implicit | Previous thread state, focused thread, notification identifiers, and last badge count. Enter needs-user while unseen → notify; leave → remove; row attention changes → update count. | A viewed request remains pending even if notification is suppressed. Badge count describes rows, not notification deliveries. |
| 108 | [Live settings round trip](../Sources/OpenRunApplication/WorkspaceSettings.swift) and `LiveSettings` | Implicit | Edited control value, request result, authoritative feed values, and settings-window existence. Edit → send → feed applies accepted value or failure restores known value. | Local optimistic controls cannot become the authority. Out-of-order changes need consistent versions. |
| 109 | [Account continuation and last choice](../Sources/OpenRunApplication/WorkspaceThreadAccounts.swift) | Implicit | Last-chosen account in defaults, available accounts, new thread creation, bounded handover text, and draft storage. Choose account → create thread → select when present → place draft → user sends. | Continuation never spends another account automatically. Removed account choices cannot become new-thread defaults. |

Relevant tests are in `SessionOverviewTests` and `OpenRunApplicationTests`.
The approval modal is related to `ApprovalQuestion.tla`; overview reconnection, caches, replay, and history request lifetime are not modeled.

### Window panes lists and browser

| Number | Machine and source | Form | Encoding and transitions | Required property |
|---|---|---|---|---|
| 110 | [List collapse animations](../Sources/MainWindow/MainWindowHiding.swift) | Implicit | Desired hidden flags, AppKit collapse state, animation generation, completed generation, completion callback, and fallback timer. Stable → animate → overlap/replace → newest completion settles. | An old or duplicate completion cannot release the current resize hold. |
| 111 | [Content width hold](../Sources/MainWindow/ContentPaneController.swift) | Implicit | `resizeDepth`, trailing constraint, optional held-width constraint, and replaceable content. Free width → first resize holds → nested resize → last end releases; replacing content transfers the hold. | Every begin has a matching end. A replaced view cannot retain an obsolete active constraint. |
| 112 | [Window focus](../Sources/MainWindow/MainWindowFocus.swift) | Implicit | First responder, window-key state, content-active flag, visible panes, and host callbacks. List focus ↔ content focus; key/resign and hidden panes change valid targets. | Focus notifications reflect the actual responder. Session activation uses the same focused content. |
| 113 | [Full-screen transition](../Sources/MainWindow/MainWindowFullScreen.swift) | Implicit | `isInFullScreen`, will-enter/will-exit events, and failure callbacks. Windowed → entering/full-screen → exiting/windowed; failed transitions restore the prior interpretation. | Traffic-light clearance and minimum geometry recover after failure. |
| 114 | [Window geometry reconciliation](../Sources/MainWindow/MainWindowMinimumSize.swift) and chosen-width files | Implicit | Scheduled-check flag, desired widths, drag-start widths, minimum constraints, screen limits, and current frame. Resize/screen change → defer one check → reconcile; drag captures and later saves chosen widths. | Reconciliation does not recurse indefinitely through layout callbacks or overwrite a user's chosen width with a temporary fit. |
| 115 | [Project table updates and editing](../Sources/ProjectsList/ProjectsListController.swift) and editing/dragging files | Implicit | Current content/rows, selected entry, `isShowingChanges`, field editor, and drag source/destination. Programmatic diff/update → guarded selection → user edit/drag → delegate request → authoritative update. | A refresh cannot masquerade as user intent. Stable identifiers keep selection across reorder. |
| 116 | [Session table filtering and order](../Sources/SessionsList/SessionsListController.swift) and editing/dragging files | Implicit | Rows, filter, order, selection, update guard, and drag identity. Receive facts → filter/sort/diff → retain/select neighbor → user reorder/rename → host. | Hidden rows keep their order. Updates target row identities rather than obsolete indexes. |
| 117 | [Progress animation lifetime](../Sources/SessionsList/ProgressMarkView.swift) | Implicit | Layer animation presence, window/view lifetime, and reduced-motion preference. Working visible row → animate or steady mark → idle/hidden/removed → stop. | Reused rows cannot keep an old activity animation. Accessibility settings affect the current state. |
| 118 | [Split divider interaction](../Sources/PaneSplits/HalvesView.swift) and `SplitPaneView` | Implicit | Split fraction, leaf-view ownership, divider hit target, and mouse drag/up sequence. Rest → divider drag → clamp fraction and lay out → release and persist. | Shares remain valid. Rebuilding a split must preserve the intended leaf views and their ownership. |
| 119 | [Browser navigation and address editing](../Sources/BrowserPane/BrowserPaneActions.swift), navigation delegate, and controller | Delegated | WebKit history/loading/document state plus OpenRun's stored address, observations, and active field editor. Typed address or link → policy → load/history → URL observation → remember; active editing delays field replacement. | Only allowed web addresses navigate. A page cannot overwrite text while the user edits it or open a separate application through another scheme. |
| 120 | [Settings controls](../Sources/SettingsWindow/SettingsPaneController.swift) and controls | Implicit | Displayed versus edited value, selected entries, table fields, and folder-picker callback. Show authority → local edit → validate/submit → accept/feed or restore; a picker can return later or cancel. | Delayed chooser results and server updates apply to the intended setting and row. An invalid value cannot silently become committed. |

Relevant tests are in `MainWindowTests`, `ProjectsListTests`, `SessionsListTests`, `PaneSplitsTests`, `BrowserPaneTests`, and `SettingsWindowTests`.
`PaneAppearance`, `ListContent`, and `ListUpdates` mostly compute appearances and diffs for these owners.
They do not introduce a separate business lifecycle.

### Session panes and transport handoff

| Number | Machine and source | Form | Encoding and transitions | Required property |
|---|---|---|---|---|
| 121 | [Terminal pane lifecycle](../Sources/SessionPane/SessionPaneController.swift) | Implicit | Attaching/closed/failure flags, attachment/view optionals, deferred failure, and pending key takeover. Empty → attaching → snapshot restored → receiving → failed or closed; a hidden failure waits for a window. | Close wins over a late attach. A connection failure does not declare the server's session dead. |
| 122 | [Attachment relay](../Sources/SessionPane/AttachmentRelay.swift) | Implicit | Condition, pending byte/event counts, cancelled flag, and per-event completion. Admit → main-thread delivery → parser completion → release; cancellation wakes producers and drops pending deliveries. | Bounds include work until the parser applies it. Every admitted event releases one slot even after cancellation. |
| 123 | [Connection work queue](../Sources/SessionPane/ConnectionWork.swift) | Implicit | Serial work, stopped latch, ordered detach, and independent forced-shutdown timer. Running → detach queued → shutdown; stalled work is interrupted from another queue. | A blocked send cannot prevent Close. The stopped latch prevents later queued sends. |
| 124 | [Grid ownership and confirmation](../Sources/SessionPane/SessionPaneController.swift) | Implicit | Own-size request queue, actual grid, visible grid, pending activation, and hidden-grid label. Local request → wait for ordered confirmation → consume own requests, or foreign size clears them → key focus takes ownership again. | An acknowledgement settles a request even if the grid already equals its size. Foreign sizes do not cause resize feedback. |
| 125 | [Pre-attachment keyboard focus](../Sources/SessionPane/SessionPaneView.swift) | Implicit | Optional terminal view and current first responder. Pane accepts focus before restore → terminal installed → focus transferred only if still appropriate. | A late attachment cannot steal focus from another pane. |
| 126 | [Single-session window lifetime](../Sources/SessionWindow/SessionWindowController.swift) | Implicit | Closed latch, hosted pane, and on-close callback. Show and attach → close by user/program/failure → detach once → callback. | A window close leaves the session alive unless its program already ended. |

Relevant tests are in `SessionPaneTests` and `SessionWindowTests`, including relay admission, close during attachment, input backpressure, size following, and hidden-grid behavior.
`LocalDelivery.tla` models part of the relay and ordered size/output path.

### Terminal view interaction and scheduling

| Number | Machine and source | Form | Encoding and transitions | Required property |
|---|---|---|---|---|
| 127 | [Output parsing queue](../Sources/TerminalView/OutputParser.swift) and `TerminalOutputQueue` | Implicit | Byte/size events, per-front offset, parsing guard, deferred-discard flag, and completions. Queued → parse pieces until budget → continue; sizes execute in stream order; discard settles the remainder. | Output and sizes preserve order. Reentrant discard cannot invalidate the current buffer or lose completions. |
| 128 | [Parse-turn scheduling](../Sources/TerminalView/TerminalView.swift) | Implicit | Scheduled flag, parse generation, pending parser, and after-output callbacks. First queued work → schedule one turn → parse budget → reschedule or run final callbacks; discard invalidates old turns. | An obsolete scheduled parse cannot apply a replacement stream. End callbacks run after preceding output. |
| 129 | [Display schedule](../Sources/TerminalView/DisplaySchedule.swift) | Implicit | Optional display link, requested flag, and attached window. Request while detached → retain demand → attach display link → one step → pause; stop invalidates the link. | Idle views consume no display ticks. A missing window does not lose a pending request. |
| 130 | [Synchronized output](../Sources/TerminalView/SynchronizedOutputHold.swift) | Implicit | Held flag, timer handle, and terminal mode. Begin hold → retain prior rendered state → end or one-second timeout → release and draw. | A crashed program cannot hold the display indefinitely. Restarted holds and obsolete timers need consistent cancellation. |
| 131 | [Cursor blinking](../Sources/TerminalView/CursorBlink.swift) | Implicit | Shown flag, timer, program blink request, focus, and steady period after typing. Focused blinking → alternate shown/hidden; key press → steady shown → blinking; unfocused/nonblinking → steady. | Old timers cannot hide a cursor after its policy changes. |
| 132 | [Bell flash](../Sources/TerminalView/BellFlash.swift) | Implicit | Flash flag and replaceable timer. Bell → flash → repeated bell extends/restarts → timer clears. | A replaced timer cannot end the newest flash early. |
| 133 | [Focus reporting](../Sources/TerminalView/FocusInput.swift) and terminal responder methods | Implicit | Observed window, observer tokens, first responder, key status, and terminal focus mode. Rebind window → become/resign input focus → send report if requested → remove observers. | A view reports its own current window and focus. Rebinding cannot leave old observers active. |
| 134 | [Text input composition](../Sources/TerminalView/TextInputState.swift) and text-input client | Implicit | Marked text/selection, optional committed-text array, and recorded commands. Between keys → begin key → mark/commit/command → end key; outside-key insertion takes a separate path. | Marked text is not sent early. One key's committed text is not sent twice. |
| 135 | [Keyboard event routing](../Sources/TerminalView/KeyboardInput.swift) | Implicit | Composition state, input-source identity before/after interpretation, Option policy, terminal key modes, and press/release action. Decide local command versus input method versus encoder → interpret → compare source → encode and finish key. | A layout switch cannot send text from the old layout. Key release and modifiers use the program's current protocol. |
| 136 | [Mouse gesture routing](../Sources/TerminalView/PointerInput.swift) | Implicit | `reportedButtons`, Shift state at press, link-click ownership, and terminal mouse mode. Press selects recipient → drag/release remain with that recipient → forget button. | A release does not go to a program that never received its press. Changing Shift mid-drag does not transfer ownership. |
| 137 | [Mouse encoder configuration](../Sources/TerminalView/MouseReporter.swift) | Composite | Cached modes/geometry, pressed-button set, and Ghostty encoder's retained last location. Read new configuration only when necessary → encode press/motion/release. | Reconfiguration does not manufacture duplicate motion. Button state is consistent with routed events. |
| 138 | [Selection gesture](../Sources/TerminalEmulation/SelectionGesture.swift) and `SelectionInput` | Delegated | Ghostty gesture retains grid references, click count, anchor and autoscroll direction; the view retains the last drag. Press → word/line repeated click or drag → selection → release. | Resize, scrollback movement, and object destruction preserve or release tracked references correctly. |
| 139 | [Selection autoscroll schedule](../Sources/TerminalView/SelectionAutoscrollTimer.swift) | Implicit | Optional repeating timer and gesture direction. No scroll → drag outside viewport starts ticks → direction changes → release or no direction cancels. | A completed drag cannot keep moving the viewport. |
| 140 | [Scroll accumulation](../Sources/TerminalView/ScrollAccumulator.swift) and `ScrollInput` | Implicit | Fractional remainder, gesture/momentum boundary, precision, and terminal modes. Accumulate deltas → whole row/tick → viewport, mouse-wheel report, or alternate-screen arrow keys. | Momentum stays with the gesture that created it. Fractions neither disappear prematurely nor repeat. |
| 141 | [Link click and approval](../Sources/TerminalView/LinkClick.swift) | Implicit | Pressed address, current target at release, opener, and optional asynchronous question. Command-press claims click → drag → matching release → open directly or after approval. | A drag cannot accidentally select or report a link press. Approval still belongs to the intended view and target. |
| 142 | [Link hover](../Sources/TerminalView/LinkHover.swift) | Implicit | Hovered cell, detected link, Command state, and output-change invalidation. Inactive → tracked cell → link and underline/pointer → refresh on changed text → leave. | A cached link cannot survive text replacement at the same cell. |
| 143 | [Unsafe paste or insertion approval](../Sources/TerminalView/TerminalView.swift) | Implicit | Paste generation, delegate identity, pending question, source type, and current paste mode. Receive text → encode immediately or ask → verify generation/delegate → send or discard. | A late approval cannot type into a closed or repurposed terminal view. |
| 144 | [Overlay scrollbar](../Sources/TerminalView/OverlayScrollBar.swift) | Implicit | Revealed flag, fade timer, last geometry, update guard, and clip origin. Scroll reveals → timer hides; model update moves knob under guard; user knob movement sends viewport change. | Layout corrections are not user scrolls. A hidden bar cannot intercept grid events. |
| 145 | [Terminal find](../Sources/TerminalView/TerminalViewFind.swift) and `TerminalSearch` | Composite | Optional find bar/search handle, needle, selected match, live terminal references, and rendered marks. Closed → find query → select newest/older/newer → refresh against changing terminal → close, preserving selection. | Search ranges track the current terminal. Closing releases search marks without losing the user's selected text. |
| 146 | [Appearance and font rebinding](../Sources/TerminalView/AppearanceObserver.swift) and `TerminalView` | Implicit | Observed scheme/window, active theme, standard/current font sizes, scale, renderer, and pending frames. Scheme/font/screen change → rebuild affected resources → refit grid → redraw. | Caches and grid metrics use the same generation of fonts, colors, and backing scale. |

Relevant tests are in `TerminalViewTests`, including ordered output, input methods, keyboard routing, mouse routing, selection, timers, appearance, links, and search.
The view's parser, interaction modes, and timer machines are mostly outside the formal models.

### Terminal emulation boundary and rendering

| Number | Machine and source | Form | Encoding and transitions | Required property |
|---|---|---|---|---|
| 147 | [Terminal and snapshot state](../Sources/TerminalEmulation/Terminal.swift) and `TerminalSnapshot` | Delegated | Ghostty terminal handle retains parser state, primary/alternate screens, modes, cursor, scrollback, selection, and unfinished sequences. Write/resize → snapshot → restore or free. | The wrapper preserves single-context access and same-build snapshot rules. Ghostty's internal automata are not separate first-party implementations. |
| 148 | [Callback installation lifetime](../Sources/TerminalEmulation/TerminalReplyHandler.swift), `TerminalEventHandler`, and callback box | Implicit | Stored callback boxes, installed C callbacks, old box lifetime, and partial installation failure. Retain new box → install → commit; on failure unregister where possible, retaining any still-referenced box. | A C callback never reaches freed Swift storage, including rollback failure and terminal destruction. |
| 149 | [Shell prompt scanner](../Sources/TerminalEmulation/ShellPromptScanner.swift) | Composite | Explicit scanner state plus sequence prefix and `zshProgress`. Text → escape/control/command → prompt or command marker; partial signatures continue across chunks. | Chunk boundaries and unrelated escape sequences do not manufacture prompt transitions. |
| 150 | [Prompt location tracker](../Sources/TerminalEmulation/ShellPromptTracker.swift) | Implicit | Scanner, optional tracked grid reference, and editor kind. Prompt start → retain location → prompt end/editing → command start clears → resize preserves appropriate prompt rows. | A tracked prompt remains attached to the intended row through reflow and scrollback changes. |
| 151 | [Line editor answer recognition](../Sources/TerminalEmulation/LineEditorAnswer.swift) | Implicit | Recent bytes, optional bytes since erase, editor kind, and nested prompt scanner. Await erase/marker → repeated row erases → first following byte establishes end; editing end can terminate directly. | A split erase sequence gives the same boundary as a single chunk. |
| 152 | [Kitty notification scanner](../Sources/TerminalEmulation/KittyNotificationScanner.swift) | Composite | Explicit scanner state, bounded command buffer, other-command flag, and earlier multipart text. Text → command → escape terminator → partial/complete notification → retain or clear earlier text. | A foreign or oversized command cannot leak into the next notification. |
| 153 | [Extra terminal replies and color defaults](../Sources/TerminalEmulation/TerminalReplyHandler.swift) | Implicit | Partial pixel-size query match, reported-size override, and last applied color scheme. Match across writes → answer → reset; scheme change → apply defaults → cache success or retry failure. | Query replies use the program's current size and colors, including during deferred model resize. |
| 154 | [Render-state capture and dirtiness](../Sources/TerminalEmulation/RenderState.swift) | Delegated | Ghostty render handle, terminal dirty rows, copied row references, and clean acknowledgement. Terminal mutates → update snapshot → enumerate dirty state → mark handled. | Row data is used only while valid. A failed or deferred draw does not lose needed dirtiness. |
| 155 | [Row cache validity](../Sources/TerminalRendering/RowCache.swift) | Implicit | Row identity/order, cached geometry, grid size, colors, dirty flags, and whether row positions matter. Valid → partial invalidation or whole invalidation → rebuild/reuse → replace cache. | Reflow, moved rows, color change, and atlas replacement invalidate all affected geometry. |
| 156 | [Glyph atlas and packing](../Sources/TerminalRendering/GlyphAtlas.swift) and `AtlasPacker` | Implicit | Glyph entries, hidden bounds, two texture packers, packer cursor/row height, full flag, and frame reclamation. Missing glyph → rasterize → place/grow → full → reclaim and invalidate rows → retry. | Cached coordinates stay tied to the texture generation. Reclamation cannot invalidate commands already in flight. |
| 157 | [Graphics command admission](../Sources/TerminalRendering/TerminalRenderer.swift) | Implicit | Frames-in-flight semaphore, ring-buffer index, retained buffers, encoding success, and command completion. Acquire → reserve buffer → encode → submit → completion releases; early failure releases immediately. | Every acquired slot returns once. The processor never reads a buffer overwritten before completion. |
| 158 | [Backing frame reuse](../Sources/TerminalRendering/TerminalRenderer.swift) | Implicit | Backing texture, drawn grid/colors/selection, per-band geometry, current cursor/overlays, and atlas state. Prepare → compare bands → redraw changed regions → present → remember committed picture. | Remembered bands describe a submitted frame. Resize or resource replacement cannot reuse obsolete pixels. |
| 159 | [Offscreen readback](../Sources/TerminalRendering/OffscreenTarget.swift) | Implicit | Last command buffer and shared texture. Present registers commands → rendering in flight → read pixel/image waits for completion → readback. | Reading cannot race the processor's writes to the texture. |

Relevant tests are in `TerminalEmulationTests` and `TerminalRenderingTests`.
The local terminal copy of the command-line tool has additional formal coverage in `LocalScreen.tla`.
There is no formal model of graphics resource reuse.

### Chat interaction and layout

| Number | Machine and source | Form | Encoding and transitions | Required property |
|---|---|---|---|---|
| 160 | [Composer delivery](../Sources/ChatView/ComposerLogic.swift) and `ComposerSending` | Implicit | Busy flag, held outgoing message, field text/images, send callback, and server transcript. Ready submission sends → busy submission holds/joins → busy ends sends held message; Stop returns held text to the field. | A submitted message has one durable-enough owner until delivery or explicit deletion. Pane eviction currently breaks this. |
| 161 | [Double Escape](../Sources/ChatView/ComposerLogic.swift) | Implicit | `isEscapeArmed`, busy state, and whether the field is empty. First eligible Escape arms → second stops → submit or ineligible Escape resets. | A single Escape cannot accidentally stop work. State reset follows the actual editing and submission policy. |
| 162 | [Draft retention](../Sources/ChatView/ComposerDrafts.swift) | Implicit | Per-thread draft dictionary and recency order, byte/count limits, and shared application lifetime. Edit saves → switch restores → oldest eviction → thread deletion forgets → process end loses drafts. | Draft identity follows the thread, not its current pane. Eviction accounts for text and images. |
| 163 | [Composer availability](../Sources/ChatView/ComposerRefresh.swift) and thread-state presentation | Composite | `ChatThreadCondition`, local closed reason, editability, send-button state, busy flag, and draft. Ready ↔ rate limit, terminal owner, or other condition. | A condition change cannot clear a draft or enable a send the thread cannot accept. |
| 164 | [Permission answer in flight](../Sources/ChatView/PermissionRequestRowView.swift) | Implicit | `answeredRequests`, pending permission item, enabled controls, outgoing answer, and final server event. Waiting → local answer submitted → controls disabled → final folded row. | A failed answer needs a route back to waiting. Local submission is not final acceptance. |
| 165 | [Disclosure and announcement retention](../Sources/ChatView/TranscriptRowContext.swift) and `DisclosureLineView` | Implicit | Opened-part set, announced-request set, disclosure hover/focus, and retained row context. Closed → open → close; first waiting request announces once; views can disappear and reappear. | Recreating a virtual row does not lose disclosure state or repeat an announcement. Obsolete identities need bounded retention. |
| 166 | [Transcript row construction](../Sources/ChatView/TranscriptRowBuilder.swift) and row context | Implicit | Markdown documents, message segments, rendered-block cache, item identities, and changed-item set. New transcript → build → update named items → reuse unchanged rows → remove obsolete cache entries. | Text, rows, and rendered ranges belong to the same transcript generation. |
| 167 | [Row measurement validity](../Sources/ChatView/RowLayout.swift) and `RowLayoutViewport` | Implicit | Keys/indexes, estimated/measured heights, prefix sums, valid-prefix position, width invalidation, and anchors. Estimate → measure → invalidate changed suffix or all measurements → settle. | Prefix positions cannot use stale heights. Measuring visible rows converges while preserving the chosen anchor. |
| 168 | [Virtual row views](../Sources/ChatView/TranscriptRowViewSet.swift) and `TranscriptView` | Implicit | Views by stable key, dirty-key set, viewport range, and tiling guard. Outside viewport → create on entry → configure when changed → remove on exit. | A reused view represents its current row. Programmatic tiling cannot recurse as a user scroll. |
| 169 | [Transcript following and anchoring](../Sources/ChatView/TranscriptScrollView.swift) and `TranscriptView` | Implicit | Following-bottom flag, pinned/current anchor, last clip size, and tiling state. At bottom follows → user scroll stops following → height/width/disclosure changes preserve anchor → jump to newest resumes. | New output cannot pull the user away from older text. Resize corrections are not user scrolls. |
| 170 | [Chat find](../Sources/ChatView/ChatViewControllerFind.swift) | Implicit | Find-bar visibility, query, match array/index, materialized row views, and selected text ranges. Open → compute all-row matches → select newest/step → reveal virtual row → close. | Search includes rows without views. Rebuilt rows do not leave invalid selection ranges. |

Relevant tests are in `ChatViewTests`, including `ComposerLogicTests`, `ComposerDraftsTests`, `PermissionRequestRowViewTests`, `RowLayoutTests`, `TranscriptRowViewSetTests`, `TranscriptScrollViewTests`, and `ChatFindTests`.
The local held message and the server's waiting-message queue are separate machines with different owners and lifetimes.

### Persistence and recovery

| Number | Machine and source | Form | Encoding and transitions | Required property |
|---|---|---|---|---|
| 171 | [Document read and quarantine](../Sources/DataStorage/DataFolder.swift) and `UnreadableFile` | Composite | `DataReadResult`, file existence/type/size, strict syntax, format header, decode result, and set-aside path. Missing → default; valid → load/preserve unknown keys; invalid → quarantine; unreadable/unmovable → fail. | A failed load cannot be silently overwritten by a later save. |
| 172 | [Strict document scanner](../Sources/DataStorage/DocumentTextScanner.swift) and `ObjectMembers` | Implicit | Byte position, recursion depth, object/array/string/number context, and exact raw value slices. Enter value → validate nested tokens/escapes → finish member → end of document. | Accept only complete strict JSON and preserve unknown member text without unbounded nesting. |
| 173 | [Atomic document replacement](../Sources/DataStorage/AtomicFileWriter.swift) | Implicit | Temporary path/descriptor, write offset, flush result, and renamed flag. Create private temporary → write all → flush → rename → committed; failure removes temporary. Old temporary files have a separate age-based cleanup. | A reader sees one complete version. Cleanup cannot remove the current write. |
| 174 | [Two-file project persistence](../Sources/Projects/ProjectStore.swift) | Implicit | Folder file, ordered-name file, save ordering, recovery merge, and rollback attempt in the keeper. Save folders → save entries → commit; crash/failure can leave one side newer → load merges or keeps folderless entries. | A partial update has defined recovery. Rollback failure must not be mistaken for an atomic two-file commit. |
| 175 | [Project mutation publication](../Sources/SessionProcess/ProjectKeeper.swift) | Implicit | Current list, candidate copy, version, save result, and feed. Edit candidate → save → replace memory/increment version/publish; failure retains memory and attempts disk restoration. | A client hears success only after the chosen persistent state commits. Every consumer rejects obsolete versions. |
| 176 | [Setting mutation publication](../Sources/SessionProcess/SettingKeeper.swift) and `SettingValues` | Implicit | Authoritative typed values, protected-setting requester, candidate copy, save result, and version. Validate authority/value → save candidate → replace and publish; failure leaves previous values. | Protected transitions require the right caller. Downstream application of a saved version cannot regress. |
| 177 | [Session restart records](../Sources/SessionProcess/SessionRecordKeeper.swift) | Implicit | Records, excluded-session set, stopped flag, delayed end-removal tasks, and loaded records awaiting restore. Live update → retained; terminal-of-thread exclusion → removed; natural end → grace → remove; shutdown freezes records. | Thread terminals never restore as shells. Shutdown preserves sessions that ended during its grace window. |
| 178 | [Restart-record save schedule](../Sources/SessionProcess/SessionRecordKeeper.swift) | Implicit | Optional `pendingSave`, latest record dictionary, save delay, and stop latch. First change schedules → later changes coalesce → save; stop cancels delay and flushes latest state. | A pending change is not lost at shutdown. Delayed tasks cannot write after the final frozen save. |
| 179 | [Layout write queue](../Sources/WindowLayout/WindowLayoutStore.swift) | Implicit | Optional waiting layout, serial writer queue, and explicit flush. First save schedules → newer layout replaces pending value → writer takes value → save; final flush drains queued work. | An old write cannot replace a newer one. App exit waits for accepted writes to finish. |
| 180 | [Layout membership and split recovery](../Sources/WindowLayout/WindowLayoutRows.swift) and `LayoutPane` files | Composite | Recursive session/thread/browser/split enum, live identity sets, seen identities, selected row, and optional thread-list authority. Load/follow → retain known live leaves → deduplicate → collapse splits/prune orphan browsers → restore selection. | Each live item has one owning row. Unknown thread lists differ from empty authoritative lists. |
| 181 | [Command-line tool installation](../Sources/ToolInstallation/ToolInstallation.swift) and workspace installation flow | Implicit | Destination path state, expected symlink target, directory rights, user confirmation, and administrator result. Missing/conflicting/current install → confirm → ordinary or privileged creation/replacement → verify/result. | Replacement targets the reviewed destination and application. Cancellation performs no installation. |

Relevant tests are in `DataStorageTests`, `ProjectsTests`, `SettingsTests`, `AgentThreadsTests`, `SessionRecordsTests`, `WindowLayoutTests`, and `ToolInstallationTests`, plus keeper and restore tests in `SessionProcessTests`.
These persistence transitions have no dedicated TLA+ model.

### Command-line terminal attachment

| Number | Machine and source | Form | Encoding and transitions | Required property |
|---|---|---|---|---|
| 182 | [Attach orchestration](../Sources/CommandLineTool/AttachCommand.swift) | Implicit | Raw-mode owner, optional picture, pending output, local suspended flag, attachment, key reader, and writer requests. Attach/restore → draw → relay → suspend/restore/repaint/resume → detach, failure, signal, or program exit → cleanup. | Only one thread writes terminal bytes. Every exit route restores terminal state. |
| 183 | [Terminal writer](../Sources/CommandLineTool/TerminalWriter.swift) | Composite | Request enum plus urgent/deferred endings, suspension/resize flags, queued output, closed/stopped latches, wake pipe, and partial-write result. Wait → choose priority request → write or interrupt → drain/defer end → close. | Urgent end can interrupt a blocked terminal. An orderly end follows already accepted output. |
| 184 | [Key sender](../Sources/CommandLineTool/KeySender.swift) | Implicit | Queued-byte count, stopped/paused/detaching flags, read loop, send queue, and detach recognizer. Read → reserve room → send; pause hands keys back to shell; detach interrupts transport and ends. | A blocked input send cannot prevent detach. Keys read while suspended do not reach the session. |
| 185 | [Detach sequence recognition](../Sources/CommandLineTool/DetachKeyRecognizer.swift) | Composite | Sequence classification, held bytes, hold deadline, and kitty/modifyOtherKeys parameter progress. Plain keys → possible prefix → complete detach, unrelated sequence, or timeout releasing bytes. | Prefixes split across reads behave identically. Escape-like ordinary input is not held indefinitely or dropped. |
| 186 | [Local screen and partial repaint](../Sources/CommandLineTool/AttachCommand.swift) | Implicit | Ghostty local screen, alternate-screen flag, saved-title flag, first/current picture, written offsets, and closing-sequence boundaries. Snapshot → picture partly/fully reaches terminal → follow actual output → suspend cleanup → repaint. | State records bytes that reached the real terminal. A partial retry cannot push/pop the title twice or restore the wrong screen. |
| 187 | [Raw terminal mode](../Sources/CommandLineTool/RawTerminalMode.swift) | Implicit | Mutex-protected original termios, current raw mode, output-drain deadline, and repeated enter/restore calls. Original → raw → bounded drain and restore → raw again after resume → final restore. | Restore is repeatable and cannot wait forever on frozen output. |
| 188 | [Attach signal subscription](../Sources/CommandLineTool/AttachSignals.swift) | Implicit | Owned dispatch signal sources and process signal dispositions. Install before raw mode → translate stop/suspend/resume/resize into writer requests → cancel sources at end. | A signal never writes bytes between another writer's escape sequence. Signal handling exists before terminal mutation. |
| 189 | [Permission hook request](../Sources/CommandLineTool/PermissionRequestCommand.swift) | Implicit | Agent request input, socket resolution, server round trip, and chosen hook output. Read request → connect/ask → explicit answer; any failure → denial output. | Transport, decoding, or process failures never become permission grants. |

Relevant tests are in `CommandLineToolTests`, including detach recognition, suspension, terminal restoration, stopped output, signals, and hook failure.
`LocalScreen.tla` covers window/local-screen size agreement; `InputBacklog` and `AttachSequence` cover other parts of the transport.

## Module coverage

Every source directory is accounted for below.
File counts include all files under each source directory.
Several modules provide values or pure transformations for a machine owned elsewhere; they do not each need a separate lifecycle type.

| Source directory | Files | Inventory entries or result |
|---|---|---|
| `AgentConversation` | 49 | 74 to 83; shared event and transcript state. |
| `AgentProgram` | 9 | 42 to 45; pipe and process ownership. |
| `AgentThreads` | 6 | 46, 50, 59; record and conversation-start facts. |
| `AlertNotifications` | 3 | 106 and 107; permission, posting, removal, and notification opening. |
| `BrowserPane` | 5 | 101 and 119; browser lifetime and navigation. |
| `ChatView` | 78 | 82 and 160 to 170; chat interaction and layout. |
| `ClaudeCodeAgent` | 19 | 56, 83 to 86, 189; agent decoding, history, and hook protocol. |
| `CodexAgent` | 40 | 62 to 73; account servers, transport, turns, approvals, and history. |
| `CommandLineTool` | 31 | 182 to 189; interactive attach and hook request. Other commands are request dispatch and formatting. |
| `DataStorage` | 12 | 171 to 173; parsing, quarantine, and atomic replacement. |
| `GitBranch` | 1 | Reads current repository facts. No retained lifecycle across calls. |
| `ListContent` | 7 | Derives rows and account usage from overview/layout values. Its caller owns selection and update state. |
| `ListUpdates` | 1 | Computes a pure diff between two row values. No retained machine. |
| `MainWindow` | 15 | 110 to 114; geometry, focus, animation, and full-screen coordination. |
| `MarkdownText` | 27 | 87 to 89; incremental document and parser state. |
| `OpenRunApplication` | 42 | 1, 82, 90 to 109, 181; application and workspace coordination. |
| `PaneAppearance` | 6 | Appearance/responder presentation under 112 and 146. No separate business lifecycle. |
| `PaneSplits` | 2 | 118; split-view identity and divider interaction. |
| `Projects` | 9 | 174 and 175; two-file persistence and project mutation. |
| `ProjectsList` | 15 | 115; list editing, selection, and dragging. Account displays derive supplied values. |
| `PseudoTerminal` | 11 | 34 to 41; spawn, flow control, cancellation, and destruction. |
| `SessionConnection` | 10 | 20 to 22 and 189; request ownership and stream receivers. |
| `SessionLaunch` | 8 | 1 to 3; registration, wake, and service lifetime. |
| `SessionOverview` | 7 | 90 to 92 and 108; overview values, batching, reconnection, and request delivery. |
| `SessionPane` | 11 | 121 to 125; attachment, delivery, confirmation, failure, and focus. |
| `SessionProcess` | 52 | 4 to 10, 14 to 19, 23 to 33, 46 to 61, 175 to 178; server and domain owners. |
| `SessionProtocol` | 23 | 10 to 13 and 15; framing, greeting, peer identity, and descriptor lifetime. Message values do not add lifecycles. |
| `SessionRecords` | 2 | 177 and 178; persistent terminal records consumed by their keeper. |
| `SessionWindow` | 3 | 126; hosted single-session window. Picker presentation is delegated to AppKit. |
| `SessionsList` | 19 | 116 and 117; list state and progress animation. |
| `Settings` | 16 | 54, 108, 120, 176; validated values and permission limits consumed by owners. |
| `SettingsWindow` | 11 | 120; control edit, chooser, and authoritative update state. |
| `TerminalEmulation` | 52 | 137, 138, 145, 147 to 154; terminal boundary, prompt parsers, callbacks, search, and snapshots. |
| `TerminalRendering` | 31 | 155 to 159; cache validity and graphics resource ownership. |
| `TerminalTheme` | 4 | Color values and deterministic palette construction. Changes are owned by 146 and 153. |
| `TerminalView` | 52 | 127 to 146; parsing, drawing schedules, input, selection, links, and search. |
| `ToolInstallation` | 1 | 181; installation state in the filesystem. |
| `UntrustedText` | 3 | Pure validation and escaping. No retained state across calls. |
| `WindowLayout` | 10 | 179 and 180; queued persistence and tree reconciliation. |
| `openrun` | 1 | Thin entry point into `CommandLineTool`; no additional machine. |
| `openrun-application` | 1 | Thin entry point into `OpenRunApplication`; no additional machine. |
| `openrun-session` | 1 | Thin entry point into `SessionProcess`; no additional machine. |

## Formal model coverage

The models are useful bounded abstractions of particular contracts.
Their success does not establish that every implementation suspension corresponds to one modeled atomic step.
The permission registration gap is a concrete example of that distinction.

| Model | Main contracts and inventory entries | Important boundary |
|---|---|---|
| [AttachSequence](../specifications/AttachSequence.tla) | Snapshot/output order, attachment size, reply ownership, viewer precedence, output pause and wake; 19, 25 to 29. | Does not model chat runners, every connection role, or all dispatch-source destruction details. |
| [ResizeWait](../specifications/ResizeWait.tla) | Fresh editor response, old-width parsing, newest resize, confirmation, late answer, timeout identity; 27 and 28. | Abstracts terminal/editor behavior. Does not cover same-size acknowledgement bookkeeping in the pane. |
| [LocalDelivery](../specifications/LocalDelivery.tla) | Ordered bounded application delivery and size agreement; 122, 124, 127. | Describes the terminal delivery path, not the unbounded chat batch stage. |
| [SessionLifecycle](../specifications/SessionLifecycle.tla) | Terminal shutdown admission, status completion, descendant termination, idle exit; 4, 8, 9, 25, 39, 41. | ThreadRegistry, Codex startup, and conversation handoff are outside its session set. |
| [InputBacklog](../specifications/InputBacklog.tla) | Input order, reply position, withdrawal, partial-piece rule, bounded admission, liveness; 36 and 37. | Does not prove every resource/callback integration around the backlog. |
| [LocalScreen](../specifications/LocalScreen.tla) | The command-line tool's local screen follows its real window size; 186. | Does not model every escape-mode cleanup or partial title-stack write. |
| [ApprovalQuestion](../specifications/ApprovalQuestion.tla) | Trusted answerer, question identity, caller withdrawal, first final outcome, timeout; 24 and 94. | Terminal-session caller classification does not include the new headless-agent route. |
| [ThreadPermission](../specifications/ThreadPermission.tla) | Agent-derived target, trusted user answer, cancellation/finality, failure denial, timeout; 56 and 189. | Registration/publication is atomic in the abstraction. The implementation suspends between those actions. |

No current model covers the complete runner startup/Stop/Close machine, process-slot transfer, Codex pooling, chat reconnection, or conversation ownership transfer.
The appropriate additions are small models of those owners and their actual suspension boundaries.
They should retain controls that deliberately remove each protection and produce the expected failure.

## Cross machine transition contracts

| Relationship | Contract that the implementation needs |
|---|---|
| Caller classification and request dispatch | A known agent cannot become an unrestricted user caller merely because it has no pseudo terminal. |
| Startup and Stop or Close | A completed external wait must validate that its startup operation still owns the right to publish or send. |
| Permission display and answer | A visible request already has a registered continuation. A local answer in flight can recover from transport failure. |
| Conversation and process ownership | At most one headless owner, reserved handoff, terminal owner, or return operation exists for a conversation. Closed is final. |
| Shutdown and admission | Set the stopping state before the first await. Include resources still starting in the termination barrier. |
| Producer and consumer queues | Every asynchronous handoff has a bound, admission rule, and release event. Upstream bounds do not cover a downstream queue that drains them. |
| Geometry and acknowledgement | Applying an acknowledgement is distinct from changing grid dimensions. Both operations have observable obligations. |
| Persistent settings and consumers | The version remains attached to the value through every asynchronous hop to an owner that stores it. |
| Pane cache and user work | Eviction releases transport and views without discarding a submitted message or a draft that the user did not delete. |

## Verification

The pinned Ghostty library was built with `scripts/build-ghostty-library.sh` before Swift builds.
`swift build` completed successfully.
The complete `swift test` invocation ran 2,104 Swift Testing tests across 40 test targets and reported two failures.
Both failed tests passed in a subsequent focused invocation:

- `aClientThatAttachesInATurnGetsEachEventOnce` assumed that the observer attached before the stand-in agent completed its turn. Its exact replay-count assertion failed under the full run.
- `severalStalledViewersPauseTheProgramForTwoSecondsInTotal` measured a longest write of 3.690 seconds against a limit below 3 seconds. Its focused rerun measured 2.414 seconds and passed.

The focused run used `swift test --skip-build --filter 'aClientThatAttachesInATurnGetsEachEventOnce|severalStalledViewersPauseTheProgramForTwoSecondsInTotal'`.
These results establish sensitivity to execution order or load. They do not justify reporting the original full run as passing.

The quick set of `scripts/check-specifications.sh` completed all 78 configurations with their expected outcomes, including its deliberate failure controls.
The long `--all` configurations were not run.
The owner-only launch-agent registration check was not run.
No real Claude Code or Codex account was used by the probes.

An isolated Swift package exercised the real feature modules through controlled callbacks and startup gates.
The package and its build products are in `/tmp/openrun-state-machine-audit.ClBxEE`.
Its source is `AuditProbe/AuditProbe.swift` and its manifest is `Package.swift` there.
It does not modify the application's package, sources, or tests.

| Probe | Observed result |
|---|---|
| Close inside the permission publication callback | Runner was closed; request returned the timeout denial rather than cancellation. |
| Stop while the Codex server provider was suspended | After release, the thread opened and the turn completed with `ok`. |
| Close while the Codex server provider was suspended | After release, the closed runner retained an open thread and completed the turn with `ok`. |
| Thread admission after registry shutdown | `create` and `running` admitted one record and one runner after `terminateAll` returned. |
| Headless agent calls to thread and terminal routes | Thread listing was refused; reading a marker from another terminal was permitted. The real runner launched the stand-in agent. |
| Two concurrent terminal handoffs | Both returned success and created two terminal sessions for one conversation. |
| Close the thread after those handoffs | Both terminal sessions remained running after the thread record and runner were removed. |

Logs are `/tmp/openrun-audit-ghostty.log`, `/tmp/openrun-audit-build.log`, `/tmp/openrun-audit-tests.log`, `/tmp/openrun-audit-recheck.log`, `/tmp/openrun-audit-specifications.log`, and `/tmp/openrun-audit-probes.log`.
The seven probes reproduce all six high-priority findings. Findings 7 to 13 are based on the referenced source paths and their event interleavings.

## Repair order

First close the caller-classification gap, then make conversation handoff exclusive.
Next make startup and shutdown final across actor suspension, and register permission waits before publication.
These changes protect work ownership and permission finality.

Then repair chat disconnection, bounded delivery, held-message ownership, and permission-answer retry.
Finally make terminal-record exclusion shared, consume unchanged-size acknowledgements, and carry versions to every stored consumer.
Add deterministic tests that pause each operation at its suspension boundary and deliver Stop, Close, a replacement, or a second caller there.
An inventory entry does not by itself call for an enum or a refactor.
Use an explicit state type where several fields jointly describe a phase; keep small independent timer and queue machines narrow.
