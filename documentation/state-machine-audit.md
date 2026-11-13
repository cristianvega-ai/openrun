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
