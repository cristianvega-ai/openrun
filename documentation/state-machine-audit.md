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
