---
title: OpenRun architecture
date: 2026-10-15
---

# OpenRun architecture

This document explains the code of the headless core, which is milestone 1 of version 1.
It is for the owner. Read it with `documentation/product.md`, which holds the decisions, and `AGENTS.md`, which holds the rules of the code.
Update it when you add a module or change the protocol.

## What exists

A background program, the session process, owns every shell and agent that the user starts.
Clients connect to it over a Unix socket. The command-line tool `openrun` is the first client.
The app will be another. A client can leave, and the programs keep running.

```
  openrun (client)        the app (later)
        \                  /
         \   Unix socket  /
          v               v
        +-------------------+
        |  openrun-session  |   the session process
        |                   |
        |  session A -------+--> pseudo terminal --> /bin/zsh
        |  session B -------+--> pseudo terminal --> claude
        +-------------------+
```

Each session holds three things: a program on a pseudo terminal, a virtual terminal (libghostty-vt) that parses the program's output, and the list of attached clients.

## Modules

Each feature is its own Swift module, as `AGENTS.md` requires.
A module uses another module only through its public types.

| Module | What it does | Public types |
|---|---|---|
| `TerminalEmulation` | Wraps libghostty-vt: the screen, the scrollback, snapshots, replies to the queries that programs send, and the default colors that a client sets | `Terminal`, `TerminalSnapshot`, `UnfinishedSequence`, `TerminalSize`, `TerminalCursorPosition`, `ScreenFormat`, `ScreenExtent`, `TerminalReplyHandler`, `TerminalColorScheme`, `TerminalColor`, `TerminalEmulationError`, `PrintableText` |
| `PseudoTerminal` | Runs one program on a new pseudo terminal | `PseudoTerminal`, `PseudoTerminalSize`, `ProgramLaunch`, `ProgramExit`, `LoginShell`, `PseudoTerminalError` |
| `SessionProtocol` | The socket protocol that the session process and all clients share | `ClientMessage`, `ServerMessage`, `SessionExit`, `SessionFailure`, `MessageFrame`, `FramedMessage`, `MessageConnection`, `SocketLocation`, `PeerIdentity`, `SessionSummary`, `SessionSize`, `SessionEnvironment`, `SessionProtocolError` |
| `SessionProcess` | The server: sessions, clients, the listening socket, shutdown | `SessionProcess`, `SessionProcessError` |
| `CommandLineTool` | The `openrun` commands | `CommandLineTool` |

The programs in `Sources/openrun` and `Sources/openrun-session` read their start-up input and call `CommandLineTool` and `SessionProcess`. They hold no other logic.

### Dependency direction

Dependencies point one way, from the programs down to the features.

```
openrun           -> CommandLineTool -> SessionProtocol
                                     -> TerminalEmulation -> libghostty-vt
openrun-session   -> SessionProcess  -> SessionProtocol
                                     -> PseudoTerminal
                                     -> TerminalEmulation -> libghostty-vt
```

`TerminalEmulation` is the only module that imports libghostty-vt.
`PseudoTerminal` and `SessionProtocol` depend on no other OpenRun module.
So each of the three size types (`TerminalSize`, `PseudoTerminalSize`, `SessionSize`) belongs to one module. `SessionProcess` converts between them at its edge.

The tests follow the same rule. `Tests/SessionProcessHarness` is support code for the integration tests: it starts the real executables and plays the part of a terminal window.
The integration tests run side by side, each on a thread of its own.
At most 8 run at a time (`IntegrationTestSlots`), apart from long tests that mostly wait and start at once.
The time that a test shows includes its wait for a slot.
`ThroughputTests` run with no other integration test beside them.

### TerminalEmulation

`Terminal` parses output bytes and keeps the state of the screen.
`TerminalSnapshot` encodes the whole state as bytes, including an escape sequence that is not finished yet, and restores it in another `Terminal`.
`TerminalSnapshot(capturing:byteLimit:)` captures within a byte limit. When the whole state is larger, it restores a copy of the terminal and lowers the scrollback line limit of the copy until a new capture fits. Each try keeps fewer lines than the try before. libghostty-vt drops the oldest whole pages over a line limit, so the snapshot keeps as many lines as fit, to within one page. The screens, the cursor, the modes and an unfinished sequence stay whole. The terminal itself keeps all of its scrollback. When a capture without scrollback is still too large, the result is `nil`.
`Terminal.formatted` writes the screen as plain text, or as text with the sequences that reproduce it.
`UnfinishedSequence(of:)` returns the start of an escape sequence or a UTF-8 character that the terminal has parsed and the program has not finished. It wraps `ghostty_terminal_continuation_alloc`, the documented libghostty-vt call for these bytes. libghostty-vt knows them only when it tracked them from the first byte: a new `Terminal` tracks from its start, and a restored terminal from its snapshot on.

`Terminal` refuses values that no window has. A grid needs 1 to 10,000 columns and rows (`Terminal.maximumGridDimension`), at creation and in `resize`. The scrollback limit must be 0 to 1,000,000 lines (`Terminal.maximumScrollbackLines`); a negative number would reach libghostty-vt as an enormous unsigned one. A snapshot restore checks the limit too. Each refusal throws `TerminalEmulationError` before libghostty-vt is called.
`TerminalColor` is a color of three channels, `red`, `green` and `blue`, each from 0 to 255. `Terminal` has calls for the default foreground, background and cursor color and for the default 256-color palette (file `TerminalDefaultColors.swift`). `setDefaultForegroundColor`, `setDefaultBackgroundColor` and `setDefaultCursorColor` set a default, or clear it when the color is `nil`. `setDefaultPalette` takes exactly 256 colors, or `nil` for the built-in palette; any other count throws `TerminalEmulationError`. `defaultForegroundColor`, `defaultBackgroundColor`, `defaultCursorColor` and `defaultPalette` read the defaults back. A snapshot carries the colors that are in force, so a restored terminal keeps the black and white defaults of the session process. The client calls these after it restores a snapshot, to give the terminal its own colors. libghostty-vt keeps a default apart from a color that a program sets with `OSC 4`, `OSC 10`, `OSC 11` or `OSC 12`. A new default does not replace a program color, and a reset by the program brings back the default. `TerminalColorTests.colorsThatAProgramSetsSurviveANewDefault` shows this.
The cap for an unfinished sequence is 32 MiB. A snapshot travels in one frame of at most 64 MiB, and it also holds the screens and the scrollback (more than 15 MiB for a full, densely styled scrollback, and about 80 MB for 1000 columns of wide characters in 256 colors). A cap above the frame size could never fit. A snapshot that is too large loses its oldest scrollback (see "A snapshot that fits in one frame").

`PrintableText.escaping(_:)` makes text from an untrusted source safe to print in a terminal or a log. The command-line tool and the log of the session process use it.

The reply handler is described in "Query replies".

### PseudoTerminal

`PseudoTerminal(launching:)` starts a program as a session leader with the pseudo terminal as its controlling terminal.
It uses `forkpty`, which makes the pseudo terminal, forks, and in the child makes a new session (`setsid`) and opens the terminal as the controlling terminal.

`posix_spawn` with `POSIX_SPAWN_SETSID` does not work for this. It opens files before it makes the new session, so the program starts with the terminal as standard input but without a controlling terminal.
Only a program that opens the terminal itself later, such as `/bin/sh`, then gets one. `ps -o tty=` showed `??` for `sleep`, `zsh`, `perl`, `dash` and `ksh`. Without a controlling terminal, Control-C does nothing and zsh turns job control off.

The child shares the memory of a process that has other threads, so it must not allocate or take a lock.
The parent prepares every C string before the fork. The child calls only system functions with plain numbers and pointers until `execve` replaces it:

- The terminal is descriptors 0, 1 and 2. The child closes every other descriptor up to 10,240, so nothing leaks into the program.
- All signals go back to their default action, and the signal mask is empty. The session process ignores some signals, and an ignored signal would otherwise survive `exec`.
- The child sets the folder with `chdir`, and `IUTF8` on the terminal.
- A failure in the child (a missing folder, an `execve` error) goes back through a pipe that closes on `execve`. The parent reads it before it returns, so `PseudoTerminal(launching:)` still throws for a program that cannot start. The parent checks the folder first (`stat`, then `access`), so a missing folder, a file, or a folder without search permission always shows as a `chdir` failure. Without that check, a relative `PATH` entry made it show as "program not found".
- A file with the execute permission and no `#!` line makes `execve` fail with ENOEXEC. Like a shell, the child then runs `/bin/sh -- PROGRAM ARGUMENTS...`. The parent prepared that argument list before the fork. When the program still cannot start, the error is the first one, from the program itself.
- After a failed launch the parent waits for the child with `waitpid` and repeats the call when a signal interrupts it (EINTR).
- The first size comes from the `winsize` that `forkpty` applies before the program starts.

Before anything else, the launch refuses a value that would reach the program changed, and nothing starts. A C string ends at its first NUL, so a NUL in the program name, the name the program sees for itself, an argument, the folder, or an environment value would give the program a shorter value or another folder. The system splits an environment entry at its first `=`, so a name with `=` would set a variable of another name, such as `OPENRUN_SOCKET`. An empty name sets no variable. Each case throws `PseudoTerminalError.invalidLaunchValue`, whose message names the problem, such as "The program was not started: argument 2 holds a NUL character." The message never repeats the value, because a value can be a secret. Nothing is cut short.

A program name without a slash is searched in the `PATH` of the launch environment (or in `/usr/bin:/bin:/usr/sbin:/sbin` when it has none). `execve` runs after `chdir`, so a relative entry such as `bin`, a `.`, and an empty entry (`::` or a leading or trailing colon) all mean a place inside the launch folder. The lookup checks the file there and returns the relative path, which names the same file after `chdir`. Only a regular file with the execute permission matches. A folder with the name of the program is skipped.

The kernel reports the exit of a session leader with a controlling terminal before `waitpid` can reap it, because it hangs up the terminal first. The exit event comes once, so the reaper tries again every 5 milliseconds until it succeeds. Without this, an unreaped program stays a zombie and its session never ends.
`waitpid` is tried again after EINTR. Any other error, such as ECHILD after another waiter reaped the program, loses the status for good. The program is then reported as exited with status 127, as a shell's `wait` reports a process whose status it does not know. It is never reported as a success.

The object offers:

- `output`, an `AsyncStream` of the bytes that the program writes. `markOutputConsumed` gives the program flow control: when more than 4 MiB wait, the pseudo terminal stops reading, and the program blocks in its own write.
- `type(_:)`, for typed input. Input that the program has not read yet waits in memory, up to 8 MiB. Past that, `type` waits, without blocking a thread, until the program reads enough. Calls that wait go in whole and in order. A single call with more than 8 MiB waits for an empty backlog. When the program ends, or closes its terminal, before the bytes are in the backlog, `type` throws `PseudoTerminalError.programEnded`. Cancelling the task that waits withdraws the bytes and throws `CancellationError`. Bytes that are in the backlog reach the program.
- `type(_:from:whenSettled:)`, for the keys of an attached client. It returns at once, and the bytes go in behind every earlier input. `whenSettled` runs when they are in the backlog, or will never get there. The bytes belong to their owner until they go to the terminal: `withdrawTypedInput(from:)` removes those that wait for room and those in the backlog that have not started to go out. A piece that started goes out whole, so the program never gets half of a key sequence.
- `write`, for a terminal's answers to queries. It never waits, because the terminal answers while it parses output. The answer joins the backlog even when the backlog is full. When typed input waits for room, the answer goes in right behind that input, because a real terminal sends its bytes in the order it made them. It waits only for the input in front of it, never for room. An answer that waits counts toward the 1 MiB of answers at once (see `waitForAnswerRoom`).
- `waitForAnswerRoom`, which waits while more than 1 MiB of answers wait for the program. The session calls it after each chunk of output. A program that asks without end and never reads the answers then stops in its own output, as typed input stops at 8 MiB.
- `resize`, which sets the size with `TIOCSWINSZ`. The kernel sends SIGWINCH to the program.
- `waitForExit`, which returns a `ProgramExit`.
- `terminate`, which ends the program and every other process of its terminal session. The program is a session leader (see `forkpty` above), so this means every process whose session identifier is the program's, also one that moved to another process group. SIGHUP goes to the program's process group first, then to each other process group of the session. A group with a stopped process also gets SIGCONT, because a stopped process acts on the hang-up only when it runs. After the grace period (one second), SIGKILL goes to every process of the session that is still alive, also when the program itself has already ended. A program that has already ended by itself when `terminate` is called leaves its background processes running. A process that started a session of its own (`setsid`), such as a daemon, is not in the session and keeps running. When the system cannot list the processes, the session counts as unknown, not as empty. `terminate` then sends SIGHUP to the program's process group, the process group of the session leader, and repeats it while it waits. It keeps waiting and signalling until the grace period (one second) has passed, and then sends SIGKILL to that group, repeatedly, for up to one more second (the killing limit). It never takes a failed list for a session with no process left.

`InputBacklog` (internal) keeps the books of the input: the backlog, the input that waits, the owners, and the limits. `PseudoTerminal` keeps one on its queue, writes the bytes, and calls the completions that it returns. Unit tests check it without a program. The two queues of `InputBacklog` (the pieces in the backlog and the input that waits) keep a start index that moves up when the front goes. They drop the unused head when it is half of the storage and holds at least 64 entries. Taking the front costs a constant time on average, so 100,000 one-byte pieces drain in well under one second. The limits and the order of the bytes did not change.
The internal `init(launching:typedInputLimit:)` gives a terminal another limit of typed input, so a test can fill the backlog with 64 KiB. `init(launching:)` always uses 8 MiB.

`TerminalSessionProcesses` (internal) finds the processes of the program's session and sends them signals. It uses Darwin calls only. macOS lists no processes by session (`sysctl` with `KERN_PROC_SESSION` fails with ENOENT), so it lists every process with `proc_listallpids` and asks each one for its session with `getsid`. A zombie has ended and is left out. Right before each signal it checks the session of the process again, so a process that ended, and whose identifier went to another program, never gets the signal. A process group gets a signal only when one of its members is still in the session and in that group right before the signal. `members()` throws `TerminalSessionProcesses.ListingFailed` when `proc_listallpids` fails, so a caller can tell a failed list from a session with no process. An empty result means that the session has none.

Why a session identifier is safe to trust: a session identifier is the process identifier of the process that made the session. XNU gives a new process an identifier only when no process, also a zombie, uses that number as its process, process group or session identifier (`forkproc` in `bsd/kern/kern_fork.c`, which keeps the rule of the 4.4BSD `fork`). So while one process of the session lives, no other session can have its number. `terminate` starts only while the program is not yet reaped, looks again at least every 20 milliseconds, and stops for good once the session has no process left. Another session could take the number only after every other process identifier, about 100,000 of them, was handed out in between.

The controlling descriptor is closed once, when the program has ended and the last dispatch source that watched it is gone.

`LoginShell.current()` reads the shell from the user database. `LoginShell.launch` starts it with a leading dash in its name, which makes it a login shell.

### SessionProtocol

This module holds the messages, the frame format, the connection, and the socket location with the check of its folder. `FolderAccessControlList`, an internal type, reads the access control list of the folder for that check. The next sections describe them.

### SessionProcess

`SessionProcess.run()` listens until SIGTERM, SIGINT or SIGHUP arrives. Internally:

| Type | Job |
|---|---|
| `SocketListener` | Checks the folder, takes the lock of the socket, checks for a live process, replaces a stale socket only while the path still holds the socket it checked, creates the socket with mode 0600, and accepts connections of the same user. At most 64 accepted connections, the length of its listen queue, wait for the server to take them, and it closes each one past that at once. After a failed accept it waits before it tries again. At shutdown it removes the socket file only when the file is still its own |
| `SocketListener.SocketLock` | The lock file next to the socket, held for the life of the process, so that two processes that start together cannot both pass the checks. It uses only a regular file of the user, opened without following a symbolic link, and sets its mode to 0600 |
| `SessionServer` | An actor. Refuses clients past the limit, reads each client's messages and answers them. A client keeps its place until its socket is closed |
| `ClientConnection` | One client. A thread reads from it, and a serial queue writes to it. It ends the connection when a deadline or a limit is missed, answers a request that it cannot decode, tells the server when the client has left, and closes the socket once neither the thread nor the queue uses it |
| `ReadAhead` | Holds the reading thread of a client while the frames that were read and not handled are too many. Keeps room for one small control frame, so a client can detach while its input waits |
| `ConnectionLimits` | Every limit and deadline of a client, in one place. See "Limits and deadlines of a client" |
| `SessionRegistry` | An actor. The sessions, found by identifier |
| `Session` | An actor. One program, one `Terminal`, and the attached clients |
| `ShutdownSignals` | Turns the stop signals into a value to wait for |

The log of the session process (`SessionServer.log`) escapes every line with `PrintableText.escaping`. A log line can include text that a client chose, such as a folder, a command or an error message, and a terminal that shows the log must not obey it.

### CommandLineTool

`CommandLineTool.run` parses the arguments (`CommandLineArguments`), connects (`SessionClient`), finds the session from a typed identifier (`SessionIdentifierMatch`), and runs one command.
`NewCommand`, `ListCommand`, `AttachCommand`, `ReadCommand`, `SendCommand` and `KillCommand` hold the commands. `RawTerminalMode` switches the terminal to raw mode and back.
`openrun attach` has three more types. `TerminalWriter` is the one writer of the terminal. `KeySender` reads keys and sends them to the session. `AttachSignals` turns signals into requests for the writer.

## Process model

- **One session process per user.** It is started by hand in the foreground in this milestone. launchd starts it in a later milestone. It logs to standard error.
- **One socket.** The default is `~/Library/Application Support/OpenRun/session.socket`. `OPENRUN_SOCKET` or `--socket PATH` overrides it. The flag wins over the variable. A relative path, such as a bare file name, starts at the current folder of the program that reads it. `SocketLocation` makes it absolute at once, so the path that programs get in `OPENRUN_SOCKET` leads to the socket from any folder. It also removes the empty, `.` and `..` parts of every path, relative or absolute. So a long spelling of a short path works, and programs get the short spelling. Symbolic links keep their names. Only a link right before a `..` is resolved first, because the system reads that `..` as the parent of the folder that the link leads to. A `..` after a name that does not exist removes that name. A path longer than 103 bytes after these steps is refused with a clear message, because that is all a Unix socket address holds.
- **The folder of the socket.** Whoever can write to the folder can put a socket of their own at the path. They could then pose as the session process, or keep the real one from starting. So the folder must be a folder, it must belong to the user, and neither its group nor others may write to it. Its access control list may not give that right to anyone else either: an entry that allows a user other than the owner, or any group, to add a file or a folder, delete one, change the list, or take ownership fails the check. Entries that deny pass, and so do entries that allow only reading. To err on the safe side, an entry for a group fails even when the user is its only member, and an entry that only passes on to new files fails too. The check fails closed: an entry whose tag cannot be read, or a permission query that returns an error, refuses the folder in the same way as an entry that lets others change it. Both sides check all of this: the session process before it starts, and every client before it connects (`SocketLocation.checkFolder`). A folder that fails gets a message that names it, and nothing is sent. So `/tmp` and other shared folders do not work. A file in the place of the folder fails with "is not a folder" on both sides. A missing folder passes on the client side, where connecting then fails as usual. The session process creates a missing folder with mode 0700. It sets mode 0700 on the default OpenRun folder when that is a folder, and it recognizes that folder in any spelling of the path (`/./`, `..`, a symbolic link), because it compares resolved paths. A folder chosen with `--socket` keeps its mode and its access control list, and a folder that fails the check stops the start.
- **The user at the other end.** Each side asks the system for the user of the other end of a connection (`getpeereid`, wrapped in `PeerIdentity`). A client refuses a session process of another user before it sends `hello`, and the session process closes a connection of another user before it sends anything. The socket mode 0600 and the folder check keep other users out already. This check holds also when a mode is wrong.
- **Start.** The process takes the lock of the socket first: the file `PATH.lock` next to the socket, held with `flock` for the life of the process. A second process that finds the lock taken refuses to start with "A session process already runs". This makes the check for a live process and the creation of the socket one step, so two processes that start together cannot both survive, and the one that loses never removes the socket of the other. The lock file stays after the process ends, because a lock on a file that someone removed protects nothing. A process that took the lock checks that the file it locked is still the one at the path. The lock file is opened without following a symbolic link. A symbolic link, a named pipe, a folder or another file that is not a regular file at the lock path stops the start with "is not a regular file", and so does a lock file of another user. The process leaves such a file as it is. A lock file that was there before gets mode 0600, so that no other user can open it and hold the lock.
  With the lock taken, a socket file at the path is either stale or belongs to a program that is not a session process of this version. The process connects and says `hello`, and waits 2 seconds for the answer. A `hello`, or a `failure` such as a version refusal, means a live session process, perhaps an older one, and the process refuses to start. A file that nobody listens on is stale, and the process replaces it. A listener that does not answer `hello` in time is no session process: the process logs that it did not answer and replaces its socket file. Before it removes a stale socket file, the process checks that the path still holds the socket it checked (the same device and inode), because the check can take 2 seconds. When the file was replaced meanwhile, the process leaves it, refuses to start, and says that the file was replaced. A file that is not a socket is never deleted.
  The socket is created with mode 0600: the umask is set before `bind`, so the file never has wider permissions. `openrun-session --help` with any other argument is a usage error with exit code 2.
- **Sessions.** A session has a UUID identifier. The command-line tool accepts any unique start of it. A session ends when its program ends, and it then leaves the list. A program that ends by itself leaves its background processes running. `openrun kill` and shutdown end every process of the program's terminal session, also those in other process groups (see `terminate`). A process that starts a session of its own escapes. Both rules are owner decisions of 2026-10-17.
  An attach during the grace period of `openrun kill` gets `attached`, the last screen, and then the exit status, also for a program that ignores SIGHUP. `SessionLifecycleTests.anAttachDuringTheGracePeriodOfKillGetsTheScreenAndThenTheExitStatus` checks this.
  The session creates its `Terminal` and installs the reply handler before it starts the program. The program starts last, so a failure while the session is created never leaves a program running without a session.
- **Threads.** Each client has one reading thread and one serial writing queue. At most 64 clients are connected at once, so the threads are bounded. The sessions and the registry are actors. A `Session` is the only code that touches its `Terminal`.
  A client keeps its place among the 64 until the connection has ended, its reading thread has returned, its writing queue has run its last work, and its socket is closed (`MessageConnection.close`). This includes the up to 2 seconds in which a client that detached still gets what waits for it. So the limit bounds the descriptors and threads of clients too, also when clients attach and detach fast and read nothing.
- **Shutdown.** On SIGTERM, SIGINT or SIGHUP the process removes the socket file first, so no client can connect to a process that is about to leave. It removes the file only when the file at the path is still the one it created (the same device and inode). It keeps the lock of the socket until it exits. It then ends every program and every other process of its terminal session (SIGHUP, with SIGCONT for a stopped group, then SIGKILL after a second; see `terminate`), closes every client, and exits with status 0.
  Each client gets up to 2 seconds to take what still waits for it, such as the output and the exit status of its program. Then its socket closes. So an attached client whose terminal is paused for a moment still gets the exit status. One that takes nothing for 2 seconds loses the rest.
  A client that was already connected can still send `createSession` while the programs end. `SessionRegistry` marks itself as stopping before `terminateAll` first suspends, and `create` refuses from then on, before it starts a program. The client gets a `failure` with reason `launchFailed` and the message "The session process is stopping." The protocol does not change.
- **Slow clients.** A session never waits for a client. It puts each message on the client's queue. When more than 8 MiB of output waits for a client, the process closes that connection. The client can attach again and gets a fresh snapshot.
  Output counts the bytes of the program's output. A control message counts the bytes of its whole frame, because it is encoded when it is queued. So a client that asks for many large lists of sessions and reads nothing is closed at 8 MiB as well.
  The snapshot, an answer to `readScreen`, and the exit status do not count toward the 8 MiB. A snapshot of a full scrollback in many colors can be larger than 8 MiB alone (a test measured 15 MiB), so counting it would end every attach while the program prints. The output queued after it counts. A connection handles its next request only after its screen answer is written, so screens cannot pile up. A snapshot is at most 64 MiB, the payload limit of one frame (see "A snapshot that fits in one frame").
  The cut applies only when output already waits for the client. A first control frame that is larger than 8 MiB, such as a very large list of sessions, is queued whole. The cut applies from the next frame on. An output frame is at most one read of the pseudo terminal, so only a control frame can be this large.
  A write that takes no byte for 10 seconds also ends the client. So a client that does not read such a first frame ends after 10 seconds.
- **Output flow.** The session parses output at its own pace. When it is slower than the program, the pseudo terminal stops reading (see `markOutputConsumed`), so memory stays bounded.
- **Input flow.** Input of a client that is there is never dropped. The backlog of input that a program has not read holds 8 MiB (see `type`). Past that, typed input waits for the program:
  - `sendText` is answered with `acknowledged` once the whole text is in the backlog. When the program ends while the text waits, the answer is a `failure`. Text that was acknowledged reaches the program, also after its client has left.
  - Input frames of an attached client go to the program in order, one after another. The server does not wait for them before it reads the client's next message, so the client can still detach while its program reads nothing.
  - `sendText` on a connection goes in behind the input frames that the same connection sent before it.
  - When a client detaches or leaves, its typed input that has not gone to the program is dropped: the frames that wait for room, and the pieces in the backlog that have not started to go out. Its requests that were read and not handled yet are dropped too. A client that leaves therefore holds no memory, however often it comes and goes.
  - The reading thread of a client reads at most 1 MiB ahead of the messages that are handled, and at most 1024 messages. Each message counts the size of its frame. The thread reads the length field and the kind byte, waits for room, and only then reads the payload. Past the limit, the socket fills up and the client's own sends wait. A client that sends faster than its program reads, or sends large requests faster than they are handled, cannot make the session process grow.
  - Input that the program does not read stays in the read-ahead until it is in the backlog, so it can fill the read-ahead for as long as the program reads nothing. One control frame of at most 1 KiB may then still be read, into a reserve, so a `detach` (or a `resize`) right behind the full read-ahead is handled at once. Input never takes the reserve, and the reserve holds one frame at a time, so the read-ahead stays within 1 MiB and 1024 messages plus that one frame. A `detach` that comes behind more input than the read-ahead holds still waits behind that input, and so does a `detach` behind a `sendText` that waits for room. Such a client can close its connection instead.
  - A reading thread that waits for room checks every 100 milliseconds whether its client has left. A client that vanishes while its input waits is then detached at once, so it no longer keeps the session silent for queries (see "Query replies").
  - A client that shuts down only its sending side (`shutdown` with `SHUT_WR`) has left too, as the protocol reads the end of a client's frames. macOS reports such a socket as closed by the peer even while unread bytes wait, so a waiting reading thread notices it within 100 milliseconds as well. The client is detached, its waiting input is dropped, and it still reads the clean end of the connection.
  - A wait holds no actor and no thread of Swift concurrency. Only the reading thread of that one client waits. Other sessions, other clients, `killSession`, `detach` and shutdown go on. When the program ends, every wait ends with it.

### Limits and deadlines of a client

`ConnectionLimits` holds them, apart from the limit of connections that wait for the server, which is `SocketListener.waitingConnectionLimit`. Each one ends or refuses a client that would otherwise hold memory, a thread or a descriptor without end.

| Limit | Value | What happens |
|---|---|---|
| Clients at once | 64 | A client past the limit gets a `failure` (reason `invalidRequest`) in place of `hello`, and the connection closes. A client counts until its socket is closed |
| Hello | 5 seconds | A connection that has not delivered its whole `hello` by then is closed |
| A frame that stalls | 30 seconds | Between frames a client may wait as long as it likes. Once a frame has started, each part must follow within 30 seconds, or the client is closed |
| A write that stalls | 10 seconds | A write that takes no byte for 10 seconds ends the client |
| Closing | 2 seconds | A closing client gets this long to take what waits for it. Then the socket closes, also when a write is stuck |
| Output that waits | 8 MiB | See "Slow clients" |
| Read-ahead | 1 MiB and 1024 messages | See "Input flow" |
| Reserve of the read-ahead | One control frame of at most 1 KiB | Read past a full read-ahead, so a client can detach. See "Input flow" |
| Accept after an error | 250 milliseconds | When the process has no descriptor left (EMFILE), the listener waits before it accepts again |
| Connections that wait for the server | 64 | The listener accepts each connection and hands it to the server, which takes it at once. A connection that waits is outside the client limit and has no hello deadline yet. So while the server is busy, at most 64 wait, and the listener closes each connection past that at once, before it reads or sends a byte. 64 is also the length of the listen queue, so the process holds no more waiting connections than the system queues for it |

A frame body is read as its bytes arrive. A frame that announces 64 MiB and sends little holds only what came.
On macOS a failed accept drops the connection that waited. Without the pause, the listener dropped every waiting client at once when the process ran out of descriptors. With it, at most one is dropped in each pause, and the others are served when descriptors free up.
A write uses the socket's send timeout (`SO_SNDTIMEO`) for its deadline, because `MSG_DONTWAIT` does not keep a send on a Unix socket of macOS from blocking. Every send passes `MSG_NOSIGNAL`, because the system refuses `SO_NOSIGPIPE` on a socket whose peer has already closed.

## The socket protocol

### Frames

Everything on the socket is a sequence of frames.

```
+-----------------------+----------+-------------------------+
| length: 4 bytes       | kind:    | payload:                |
| big endian, counts    | 1 byte   | length - 1 bytes        |
| the kind and payload  |          |                         |
+-----------------------+----------+-------------------------+
```

| Kind | Value | Direction | Payload |
|---|---|---|---|
| control | 1 | both | A JSON message |
| output | 2 | server to client | Bytes that the program wrote |
| input | 3 | client to server | Bytes for the program to read |
| snapshot | 4 | server to client | A `TerminalSnapshot` |

Control messages are JSON because they are small, rare and easy to read. Terminal bytes are raw because they are frequent and large.

The largest payload is 64 MiB. The receiver checks the length field before it reads or allocates anything, and refuses a larger frame. It reads the kind byte next and refuses an unknown kind. Only then does it read the payload, as the bytes arrive, so the memory grows only with what came. A zero length, an unknown kind, and a connection that closes in the middle of a frame are errors.

### Version

Both sides send their protocol version in their first message, `hello`. The current version is 1.
A session process that gets another version answers with a `failure` whose reason is `incompatibleProtocol` and closes the connection. Its message is "This session process speaks protocol version N, not M." Every version must keep the words "protocol version" and its own number after them, because a client reads the number from there.
A client that gets another version in the answer, or reads one from the failure, stops with an error that names both versions.
A client that the session process refuses for another reason, such as the limit of 64 clients, gets a `failure` with another reason in place of `hello`, and stops with its message. The session process may close the connection before the client's `hello` goes out, so a client reads the answer even when its `hello` could not be sent.
Raise `MessageFrame.protocolVersion` when a change would confuse an older program.
The `hello` message itself must stay readable by every version.

### Control messages

A control message is a JSON object with one key, the name of the message. The value holds its fields.
A field without a name in the Swift code is called `_0`.

Client to server:

| Message | Fields | Answer |
|---|---|---|
| `hello` | `protocolVersion` | `hello` |
| `createSession` | `folder`, `command` (absent for the login shell), `size`, `environment` | `sessionCreated`. An empty `command` list names no program and gets a `failure` with reason `invalidRequest`. A value that would reach the program changed gets a `failure` with reason `launchFailed` whose message names the problem: an environment name that is empty or holds `=` or NUL, or a NUL in an environment value, an argument, the program or the folder |
| `listSessions` | none | `sessionList` |
| `readScreen` | `identifier`, `includeScrollback` | `screen` |
| `sendText` | `identifier`, `text` | `acknowledged` once the text is in the program's input backlog, behind the input frames that this connection sent before. `failure` with reason `unknownSession` when the program ends before that |
| `killSession` | `identifier` | `acknowledged`, after the session is gone and every process of its terminal session has ended (see `terminate`). On a connection that is attached to that session: `acknowledged`, then `exited`, and the connection closes |
| `attach` | `identifier`, `size`, `relaysRawOutput` (optional), `receivesSizeChanges` (optional) | `attached`, then a snapshot frame, then output frames, and `sizeChanged` when the client asked for it. A size with 0 columns or 0 rows, or one that the terminal refuses, gets a `failure` with reason `invalidRequest`, and the session keeps its size. So does a size at which the screens alone do not fit in one frame (see "A snapshot that fits in one frame"). The `failure` comes in place of `attached`, and the connection stays open and not attached |
| `input` | the bytes, as an input frame | none |
| `resize` | `_0` is the size | none. A size that the terminal refuses (more than 10,000 columns or rows) changes nothing. A new size goes to the other attached clients that asked for it, as `sizeChanged` |
| `detach` | none | the connection closes |

Server to client:

| Message | Fields |
|---|---|
| `hello` | `protocolVersion` |
| `sessionCreated` | `_0` is a session summary |
| `sessionList` | `_0` is a list of session summaries |
| `attached` | `_0` is a session summary |
| `snapshot` | the bytes, as a snapshot frame |
| `output` | the bytes, as an output frame |
| `sizeChanged` | `_0` is the new size. Only a client that set `receivesSizeChanges` in its `attach` receives it, when another client changes the size with `resize` or with `attach`. It comes before the output that is laid out for the new size |
| `screen` | `text` |
| `exited` | `_0` is `{"exited":{"status":N}}` or `{"signaled":{"signal":N}}` |
| `acknowledged` | none |
| `failure` | `_0` holds `reason` (`incompatibleProtocol`, `unknownSession`, `launchFailed` or `invalidRequest`) and `message` |

A session summary holds `identifier`, `folder`, `command` (a list), `size` and `createdAt` (seconds since 1970).
A size holds `columns` and `rows`, each 0 to 65,535.

A control frame from a client that the session process cannot decode gets a `failure` with reason `invalidRequest`, and then the connection closes. Examples are text that is not JSON, a name that is no message of the protocol, a missing field, a field of the wrong type, keys in a control frame, and a value out of range, such as a size of 999999 or -1. The message names the problem in the words of the protocol, such as `A frame is malformed: the field resize._0.rows holds a value that is out of range or in the wrong form.` It never quotes the request, which can hold escape sequences. The first frame gets the same answer in place of `hello`. A frame that breaks the framing (a zero length, a length above the limit, or an unknown kind) closes the connection without an answer, because the bytes after it cannot be read as frames. A frame of a kind that only the server sends also closes the connection without an answer, as before. Other clients notice nothing.
JSON that nests more than 512 levels counts as JSON that cannot be read. The decoder stops at that depth at once, so a frame of 64 MiB of nested arrays costs the memory of the frame and no stack.
An error about a message that does not fit the conversation, such as a `screen` in place of `hello`, names the message and not its fields. A field can be a whole screen, or text that a user typed.

Examples of control payloads:

```json
{"hello":{"protocolVersion":1}}
{"createSession":{"environment":{"PATH":"/usr/bin"},"folder":"/work","size":{"columns":80,"rows":24}}}
{"attach":{"identifier":"3F2A9C1E-0000-4000-8000-000000000001","relaysRawOutput":true,"size":{"columns":80,"rows":24}}}
{"attach":{"identifier":"3F2A9C1E-0000-4000-8000-000000000001","receivesSizeChanges":true,"size":{"columns":80,"rows":24}}}
{"resize":{"_0":{"columns":100,"rows":30}}}
{"sizeChanged":{"_0":{"columns":100,"rows":30}}}
{"exited":{"_0":{"exited":{"status":3}}}}
{"failure":{"_0":{"message":"No session has the identifier 3f2a9c1e-…","reason":"unknownSession"}}}
```

`relaysRawOutput` is a new optional field of `attach`. It stays inside protocol version 1: a client that leaves it out, or sends `false`, does not relay raw output, and an older session process ignores the field.
`receivesSizeChanges` is another optional field of `attach`, and it stays inside protocol version 1 too. A client that leaves it out, or sends `false`, never receives `sizeChanged`, so an older client never meets a message that it does not know. An older session process ignores the field and never sends the message. The client whose own `resize` or `attach` changed the size does not get the message, because it knows its size. `openrun attach` does not ask: it sends the size of its own window, and its real terminal lays out the output. A client that draws the screen itself, as the app will, asks for the message and resizes its own `Terminal` when it comes.
The identifier is a UUID. In JSON it is the usual upper case text. People and environment variables see it in lower case.

### A conversation

1. The client connects and sends `hello`. The server answers `hello`.
2. A request that needs one answer (`createSession`, `listSessions`, `readScreen`, `sendText`, `killSession`) gets its answer. The client may send the next request or close.
3. `attach` starts a longer conversation. See the next section.

Between the connection and step 1, the client checks the folder of the socket and the user of the session process, and the session process checks the user of the client. See "The folder of the socket" and "The user at the other end" in "Process model".

The client sends the environment of the person who asked, in `createSession`. The program starts with it, so it sees the user's own `PATH` and account settings, such as `CLAUDE_CONFIG_DIR`. The session process then sets the variables in "Environment variables" over it.

## Attach sequence

```
client                                   session process
  | attach(identifier, size)  ------------>  |
  |                                          |  on the session's own serial context:
  |                                          |    1. resize the terminal when the size differs
  |                                          |    2. take a snapshot that fits in one frame, or
  |                                          |       queue "failure", go back to the old size, and stop
  |                                          |    3. queue "attached" and the snapshot for this client
  |                                          |    4. add the client to the attached clients
  |                                          |    5. queue "sizeChanged" for each other client
  |                                          |       that asked, when the size changed
  | <-------------------- attached(summary)  |
  | <----------------------- snapshot frame  |
  | <------------------------- output frame  |  every later output, in order
  | <------------------------- output frame  |
  | input frame, resize, ...  ------------>  |
  | <--------------------------- exited(..)  |  when the program ends
```

A client's size goes to two places: the session's terminal model and the program's pseudo terminal. The session resizes the model first, because the model checks the size and may refuse it. A refused size then reaches neither, and the program and the screen that clients see keep one size. When the pseudo terminal refuses a size after the model took it, the model goes back to the old size.

### Why there is no gap and no repeat

A `Session` is an actor, so only one piece of its code runs at a time.
The program's output is handled by one method of the session: it updates the terminal, and then queues the same bytes for every attached client.
`attach` is another method of the same actor, and it does not wait for anything.

So the output splits cleanly into two groups:

- Output handled before `attach` ran is inside the terminal when the snapshot is taken. It is in the snapshot, and the client is not registered yet, so the client does not get it again as output.
- Output handled after `attach` ran finds the client registered. It goes to the client's queue behind the snapshot.

The client's queue keeps the order. The client restores the snapshot and then writes each output frame into the restored terminal.
The snapshot can even fall inside an escape sequence or a UTF-8 character. A snapshot keeps the unfinished bytes, and the next output frame completes them.
A client that draws a picture of the snapshot for another terminal must also write those bytes after the picture, because the picture holds only what is finished. `UnfinishedSequence` returns them. The protocol does not change for this: the bytes are already in the snapshot.

Tests check this with 3000 numbered lines of steady output and an attach at four moments. The restored screen and scrollback must show each line once, in order.

### A snapshot that fits in one frame

A snapshot travels in one frame, and a frame carries at most 64 MiB. A wide session with a full scrollback in many colors can need more. A test measured about 80 MB for 1000 columns of wide characters in 256 colors with 10,000 lines of scrollback.
So `Session.attach` captures with `TerminalSnapshot(capturing:byteLimit:)` and the payload limit, before it sends `attached`. A larger snapshot loses its oldest lines of scrollback until it fits, and it keeps as many lines as fit. The client then has the newest part of the scrollback. `openrun read --scrollback` still prints all of it.
The visible screen, the alternate screen, the cursor, the modes and an unfinished sequence stay whole. So the seam of the attach holds as before: output parsed before the snapshot is inside it, and output after it follows it, with no gap and no repeat.

The screens alone can also be too large. An example is an attach at 10,000 rows, which pulls the scrollback onto the screen. The client then gets a `failure` with reason `invalidRequest` in place of `attached`: "The screen of the session does not fit in one frame of 64 MiB, even without scrollback. Attach with fewer columns or rows." The session goes back to its earlier size, and the connection stays open and not attached. The program gets the new size and then the old one. The other clients get no `sizeChanged`, because the size did not change in the end.

`ReattachTests.aSnapshotLargerThanOneFrameLosesOldScrollbackAndKeepsTheScreen` checks both cases in a session of 1000 columns. The client that attaches gets a snapshot near 64 MiB with the newest scrollback, and its screen is the screen that `openrun read` shows, also after more output.

### What `openrun attach` does

1. It resolves the identifier, and sends `attach` with the size of its terminal and `relaysRawOutput` set to `true`, because it writes the raw output to a real terminal. It does not set `receivesSizeChanges`, because its real terminal lays out the output at the size of its own window.
2. It restores the snapshot into a local `Terminal` and makes the first picture from it. This happens before the terminal changes, so a snapshot that cannot be restored ends the tool with an error (exit code 1) and leaves the terminal as it was. A `failure` in place of `attached`, such as for a screen that does not fit in one frame, ends the tool the same way, with the message of the failure.
3. It starts to handle signals, and only then puts the terminal in raw mode. So no signal can leave the terminal raw.
4. It draws the picture: it clears the screen and draws the visible screen of the local terminal in its VT format. When the session is on the alternate screen, it enters the alternate screen first. When the snapshot fell inside an escape sequence or a UTF-8 character, it writes the start of it after the picture (`UnfinishedSequence`). The first output frame then finishes it in the real terminal. Without this, the terminal would show the end of the sequence, such as `1mRED`, as text. The picture starts with `CSI 22 ; 0 t`, which saves the title of the window on its stack. The tool puts the title back when it restores the terminal (step 7). The picture after a suspension saves the title again.
5. It relays: keys go out as input frames, output frames go to the terminal, and SIGWINCH sends `resize`. It sends the size once more when the relay starts, because the window can change between the attach request and the signal handler. The local terminal follows exactly the bytes that reached the terminal, so the tool knows at the end whether the terminal is on the alternate screen. Keys go out in order on a queue of their own. After `KeySender.stop` returns, the keyboard thread reads no more keys: it checks the stop flag and reads under one lock. Keys that it read before `stop` still go to the session. Keys that the recognizer holds for a possible detach at that moment, such as a lone Escape within its short hold, are dropped. `KeySender.pause` works like `stop` for reads: the thread checks the pause flag and reads under one lock, so it reads no key after `pause` returns. `resume` lets it read again. A send waits when the program reads no input and the session process holds as much as it may, and the keyboard thread must still see the detach key then.
6. Control-] detaches. `DetachKeyRecognizer` finds the key in the bytes that the terminal sends (see "The detach key"). The tool sends `detach` behind the keys, waits for it at most 200 milliseconds, and then closes the connection. The program's exit, a lost connection, a failed write to the terminal, SIGINT, SIGTERM, SIGHUP and SIGQUIT also end it.
7. In every case it restores the terminal. It first writes CAN (`0x18`) and ST (`ESC \`), which end any escape sequence or string, such as an operating system command, that the program left open. Without them, a terminal could take what follows, and the message after it, as part of the open sequence. Then it turns off synchronized output (mode 2026), because that mode holds back every later change of the screen. Then it leaves the alternate screen, when the terminal is on it. Then it undoes what the program and the first picture switched on: the scroll region and origin mode (with the cursor saved and restored around them, because both reset moves the cursor), the color palette, the foreground, background and cursor colors (OSC 10 to 12), styles, a hyperlink that is still open (OSC 8 with no address), the character sets, insert mode, reverse video (mode 5), line wrap, the cursor and its shape, the modes that lock the keyboard or change a key (ANSI modes 2 and 20, mode 67), the left and right margins (mode 69), mouse reports (modes 9, 1000, 1002, 1003) and their encodings (1005, 1006, 1015, 1016), focus reports, color scheme reports, visibility reports and size reports (modes 1004, 2031, 2033, 2048), bracketed paste, application keys, and the extended keyboard modes. Then it puts the title back (`CSI 23 ; 0 t`), when the picture saved it. Then it puts the original terminal mode back.

   A saved cursor also keeps origin mode, so when the program set origin mode, the tool resets it after the cursor is restored, and moves the cursor back to its place. The tool finds out whether origin mode is set from the local terminal. The reset before leaving the alternate screen has the same reason: the alternate screen forgets its cursor.

   The tool resets only modes that are off in a plain terminal. It does not touch modes that many terminals turn on by default, such as alternate scroll (1007), grapheme clusters (2027) and the meta key modes (1035, 1036). Those modes would then differ from the user's own setting.

Threads. Only the main thread writes to the terminal, through `TerminalWriter`. One thread receives frames from the session process and hands the output to the writer, at most 1 MiB ahead. The keyboard thread (`KeySender`) and the signal handlers (`AttachSignals`) never write to the terminal. They ask the writer to end, to suspend, or to go on. When two requests to end arrive, an urgent ending wins over an ending that waits for output, also when the urgent one came second. A detach (Control-]) and a signal are urgent: they end the attach at once, and output that still waits is dropped. The exit of the program and a lost connection wait for the output that came before them. Among urgent endings, the first one decides the exit code, so a second signal does not change it. Among endings that wait for output, the first one decides as well. No output follows the closing sequences.

The last message of `openrun attach` (such as `[detached]` or the reason of a lost connection) can include text from the session process, so it is escaped with `PrintableText.escaping`.

A terminal that takes no output. The writer opens the terminal a second time, without blocking, so a terminal that reads nothing, such as a frozen `ssh` or a paused multiplexer, cannot hold the tool in a write. It waits for room with `poll`, and a request wakes it. Control-] and the stop signals therefore end the tool also while the terminal takes no output. In that case the tool puts the original mode back first, because the closing sequences may never reach the terminal, and then gives the closing sequences and the last message one second each.

Suspending. SIGTSTP restores the terminal as at the end (including the title), and then stops the tool. The tool stops itself with SIGSTOP, because a SIGTSTP of its own would reach its own handler again after the continue. A shell reports the tool as stopped by a signal. A signal to end that arrives before the stop wins over the suspension: SIGINT, SIGTERM, SIGHUP or SIGQUIT, also 150 milliseconds after SIGTSTP while the terminal takes no output, ends the tool with 128 plus the signal and the terminal restored, and the tool never stops itself. The tool asks once more, right before SIGSTOP, so the closing sequences of the suspension (which may wait up to one second for a terminal that takes no output) do not hide the signal. The keyboard thread reads no keys from the start of the suspension until the continue has set raw mode again (`KeySender.pause` and `KeySender.resume`). Keys that the user types in that time stay in the terminal for the shell, also while the closing sequences wait for a terminal that takes no output. `KeySender.stop` and the end of attach still work while the reading is paused. A signal that comes after the stop waits for the continue, as for any stopped process. SIGCONT puts the terminal in raw mode again, with the mode that the terminal has then as the one to put back, saves the title again, sends the size, and draws the picture again.

Closing state. The local screen counts the window as on the alternate screen, and as holding the saved title, until the bytes that end that state went out. `TerminalWriter.writeClosing` returns how many bytes of the closing sequences reached the terminal. The alternate screen is done with when the bytes up to the end of `CSI ? 1049 l` went out. The title is done with when all bytes went out, because the title pop (`CSI 23 ; 0 t`) is the last part. When a suspension gives up on a frozen terminal and a signal then ends attach, the last closing still leaves the alternate screen and pops the title. A state that was ended is never ended again, so the title pop is not sent twice. The other sequences give the same result when repeated.

Raw mode starts with TCSANOW and ends with TCSADRAIN, so neither discards the keys that the user typed ahead: the session gets the keys typed before attaching, and the shell gets the keys typed while the tool ends. TCSADRAIN waits for the output to drain, so the tool waits at most 200 milliseconds for that, and switches with TCSANOW when the terminal takes no output. Back in line editing, the kernel marks the keys typed ahead for another pass (PENDIN), and the mode shows the mark until something looks at the input. The tool polls the input once, so the mode reads exactly as it was before attaching.

### The detach key

`openrun attach` passes a program's keyboard mode requests to the real terminal. After a program such as Codex turns on an enhanced mode, the terminal sends Control-] in another form. `DetachKeyRecognizer` (in `Sources/CommandLineTool/`) detaches on all of these:

| Form | Bytes |
|---|---|
| Plain keyboard | `0x1D` |
| Kitty keyboard protocol | `ESC [ 93 ; 5 u` |
| xterm modifyOtherKeys | `ESC [ 27 ; 5 ; 93 ~` |

The kitty form is `CSI 93[:alternates] ; modifiers[:event] [; text] u`. The modifiers value minus one must have the Control bit and no Shift, Alt, Super, Hyper or Meta bit. The Caps Lock and Num Lock bits are ignored. The event may be missing, 1 (press) or 2 (repeat). Event 3 (release) does not detach. Other keys, such as `ESC [ 91 ; 5 u`, pass through.

The recognizer returns the bytes before the key, and the tool sends them to the session. All other bytes pass through unchanged.

A terminal can deliver one key in two reads, for example over `ssh` or in a multiplexer. So the recognizer holds an incomplete end of the input when it could still become one of the three forms above. A lone Escape counts, because it starts the two escape forms. The recognizer joins the held bytes to the next read.

- A hold lasts at most 20 milliseconds. Then `AttachCommand` sends the held bytes to the session, and a later second half no longer detaches. The hold starts when the first held byte arrives. More bytes of the same form do not start it again.
- Bytes that no detach form can start with are never held. An example is `ESC [ 1`, or `ESC [ 9 3 0`. They are sent at once.
- The Escape key reaches the program up to 20 milliseconds late. This is the price of recognizing a split key.
- The keyboard thread of `openrun attach` polls with the time that the hold has left. When the poll times out, it sends the held bytes. Keys that are ready when the poll ends were in the terminal in time, so the thread reads them and joins them to the held bytes first, also when it gets to them late on a busy Mac. The hold therefore counts from when the bytes were read. A poll that a signal interrupts reads nothing, and the next poll waits for the time that the hold has left, so a held Escape never waits for the next key.

The exit code of `openrun attach` is 0 after a detach, and the program's own status (or 128 plus the signal) when the program ends while attached. The session process is another program, so the tool clamps these numbers to 0 to 255. Without the clamp, a status of 300 would reach the shell as 44, because the kernel keeps only the low byte. The exit code is 128 plus the signal when SIGINT, SIGTERM, SIGHUP or SIGQUIT ends the tool, and 1 when the connection is lost or the terminal cannot be written to.

## Query replies

Programs ask the terminal questions, such as "where is the cursor" (`ESC [ 6 n`) or "what are you" (`ESC [ c`). The terminal must send an answer back as input.

libghostty-vt answers through callbacks. `Terminal.setReplyHandler` installs four callbacks and two more answers:

- the callback for bytes that go back to the program (cursor position reports, mode reports, and more),
- the callback for device attributes. The terminal answers only when this callback gives it the values. It reports level 2 with ANSI color,
- the callback for size (`GHOSTTY_TERMINAL_OPT_SIZE`). It answers the XTWINOPS queries `CSI 14 t`, `CSI 16 t`, `CSI 18 t` and `CSI 19 t` from the grid of the terminal, and it enables the in-band size reports of mode 2048. A session has no window, so a cell is a nominal 8 by 16 pixels. For an 80 by 24 grid, `CSI 18 t` gets `ESC [ 8 ; 24 ; 80 t` and `CSI 14 t` gets `ESC [ 4 ; 384 ; 640 t`. The grid is read at each query, so the replies follow a resize, and `Terminal.resize` stores the pixel size of the grid (a cell of 8 by 16 pixels), so the in-band report of mode 2048 after a resize carries pixels too,
- the callback for the color scheme (`GHOSTTY_TERMINAL_OPT_COLOR_SCHEME`). It answers `CSI ? 996 n` with `ESC [ ? 997 ; 1 n` for dark and `ESC [ ? 997 ; 2 n` for light. `TerminalColorScheme.current()` reads the macOS appearance (`AppleInterfaceStyle`) fresh, at most once each second. It asks CFPreferences to refresh its cache first, because the session process runs no main run loop. A change of appearance reaches a running program within about a second. The session process needs no change: `setReplyHandler` uses this default.
- the default foreground and background colors of the terminal. libghostty-vt has no callback for `OSC 10` and `OSC 11` queries. It answers them from the default colors that the embedder sets with `ghostty_terminal_set`. `Terminal.write` sets them from the appearance before it parses output, and only when the appearance changed: black on white in light mode, white on black in dark mode. The reply has the form `ESC ] 10 ; rgb:0000/0000/0000 BEL` and ends with the terminator of the query. `setReplyHandler(nil)` clears the colors. While a reply handler is installed, `write` sets the foreground and the background again each time the appearance changes, so a color set with `setDefaultForegroundColor` or `setDefaultBackgroundColor` lasts only until then. A client that restores a snapshot installs no handler, so its colors stay. The cursor color and the palette are never set by the handler.
- `CSI 15 t` (the size of the screen in pixels). libghostty-vt does not parse this query, so it has no callback. `Terminal.write` looks for the exact bytes `ESC [ 1 5 t` (also when a write ends inside them), parses the bytes up to the end of the query, and then sends `ESC [ 5 ; height ; width t` from the grid and the nominal cell, so the replies keep the order of the queries. For an 80 by 24 grid the reply is `ESC [ 5 ; 384 ; 640 t`.

The default colors are a setting of the terminal, not output. The snapshot carries them, but the picture of `openrun attach` (the visible screen as sequences from a restored snapshot) and the text of `openrun read` do not change. `TerminalReplyTests.theQueriesChangeNoPictureOrText` compares plain text, sequences and hypertext markup, with and without the colors, for eleven kinds of output, also after the restore and more output.

The handler's box is stored in `Terminal.replyBox` before libghostty-vt gets a pointer to it, and the old box lives until the new pointer is in place. If the installation fails half way, the terminal takes the callbacks back, or keeps the box alive when it cannot.

The session process installs a handler on the session's `Terminal` before it starts the program. The handler writes the bytes to the pseudo terminal with `PseudoTerminal.write`, which never waits, unless a real terminal answers instead. An answer goes in behind typed input that waits for room, as a real terminal would send them.

`openrun attach` writes the raw output to the user's terminal window, and that window answers the same queries, as it would over `ssh`. Two answers would confuse the program. So the rule is:

- While at least one attached client relays raw output (`relaysRawOutput` is `true` in its `attach` message), the session process sends no replies. The real terminal of that client answers.
- With no client, or with only clients that do not relay, the session process answers. This holds for the colors (`OSC 10`, `OSC 11`) and for `CSI 15 t` too. With a relaying client attached, the handler of the session process stays silent for all queries.
- A client that restores a snapshot and draws it itself, such as the app will, does not relay. It sends no `relaysRawOutput` or sends `false`, and the session process keeps answering for it. Its copy of the screen installs no handler, so each query gets one answer.

The session process still parses every query when it stays silent, so its screen state is the same either way.

### Size reports

A program that turns on mode 2048 gets an in-band report of each new size, `ESC [ 48 ; rows ; columns ; height ; width t`. libghostty-vt makes the report when the session resizes its terminal. Only a terminal whose window changed knows of a change, so the rule differs from the rule for queries:

- When a relaying client sends `resize`, its own window changed, and its real terminal sends the report. The session process stays silent.
- No terminal reports any other change: a `resize` from a client that does not relay, an `attach` with another size, and the return to the old size after an attach that fails. So the session process sends the report, also while a relaying client is attached. It opens its reply gate only for that resize. The resize parses no output, so no query gets a second reply.

When a program turns mode 2048 on, libghostty-vt also reports the size at once. That report is an answer to output, so it follows the rule for queries.
`QueryReplyTests.eachSizeChangeIsReportedOnceWhileARelayingClientIsAttached` attaches a relaying client and another client. The program reads one report for the attach of the other client at 100 by 30, one for its resize to 120 by 40, and none for the resize of the relaying client to 90 by 25.

### Attaching and detaching while a query is pending

The decision is made once for each query, at the moment the session process parses its bytes.
The session parses output, attaches and detaches on one serial context, so each query meets exactly one state of the client list. The rule is:

- A query that the session parsed before a relaying client attached was answered by the session process. The client's snapshot holds the screen and not the bytes of the query, so the client's terminal never sees it and does not answer again.
- A query that the session parsed while a relaying client was attached is sent to that client as output, and only its terminal answers.
- If that client detaches, or loses its connection, before its terminal has answered, nobody answers. The program gets no reply, as it would when an `ssh` connection drops. The next query is answered by the session process again.

Tests cover no client, an attached client in a pseudo terminal that plays a real terminal and answers `ESC [ c`, an older client that sends no field, a client that attaches after the answer, and a client that detaches before the next query. In each case the program reads exactly one reply.

Limit: two relaying clients attached at once both answer, so the program gets two replies. Attaching two terminal windows to one session is rare, and the app will not relay raw output.

## Speed of dense output

The session process parses every byte that a program writes, so the speed of libghostty-vt sets the speed of a session.
`scripts/build-ghostty-library.sh` builds it with `-Doptimize=ReleaseFast`, the mode that Ghostty ships. Zig's default is Debug, and a Debug build needed more than 3 minutes to parse 16 MB of dense text.
The script writes the mode to `Libraries/ghostty-vt.optimize-mode`. When that file does not name the mode in the script, the script deletes the old output and builds again, so a re-run never leaves a framework of the wrong mode in place.
Before it fetches or checks out anything, the script refuses a Ghostty tree with changes, so an edit is never discarded. It checks again after the checkout. The script uses a Zig tree that it extracted in the same run, from an archive in `Libraries/zig` whose checksum matched the pin (or from a fresh download that matched). It deletes the tree that an earlier run left and extracts again, then checks the `zig` program against its pinned checksum. A Zig in the search path is never used. The checksum of the program alone would not cover the standard library beside it, and extracting again does.

`ThroughputTests` run a program that writes 16 MB of printable text (`yes ... | head -c 16000000`). The session must reach the exit of the program within 5 seconds, once with no client and once with one client that reads all output.
On the development Mac (Apple Silicon, debug build of the Swift code, ReleaseFast libghostty-vt), the runs took 1.7 to 2.5 seconds with no client and 1.3 to 3.5 seconds with one client. The time depends on how busy the Mac is.
The Swift code is a debug build in the tests, so the limit of 5 seconds leaves little room on a slow or busy Mac.

## Environment variables

Every program in a session gets these. They override the same names in the environment that the client sent. A client name that is empty or holds `=` or NUL is refused (see `createSession`), so a client cannot add a second entry for one of these names.

| Variable | Value |
|---|---|
| `OPENRUN_SESSION` | The identifier of the session, in lower case |
| `OPENRUN_SOCKET` | The absolute path of the socket of the session process |
| `TERM` | `xterm-256color` |
| `COLORTERM` | `truecolor` |
| `TERM_PROGRAM` | `OpenRun` |

`OPENRUN_SOCKET` also tells `openrun` inside a session where the session process is. The tool reads it when no `--socket` flag is given.

## Command-line tool

```
openrun new [--folder PATH] [-- PROGRAM ARGUMENTS...]
openrun list
openrun attach IDENTIFIER
openrun read IDENTIFIER [--scrollback]
openrun send IDENTIFIER [--enter] TEXT
openrun kill IDENTIFIER
openrun help
```

Every command takes `--socket PATH`. Errors go to standard error with exit code 1. Wrong arguments exit with code 2: this includes `openrun help` with arguments, `openrun COMMAND-THAT-DOES-NOT-EXIST --help`, and an empty session identifier. The tool checks the arguments before it connects, so these exit with 2 whether or not a session process runs. `--help` after a real command (`openrun read abc --help`) shows the help.
`list` prints one line per session: the identifier, the folder and the command, separated by tabs. A client chose the folder and the arguments, so each field is escaped with `PrintableText.escaping`: a backslash becomes two backslashes, a tab `\t`, a new line `\n`, a carriage return `\r`, and any other control character `\u{XX}` in upper-case hexadecimal. Each session is exactly one line, and the tabs split exactly three columns. The arguments of the command are joined by one space.
Every error message that `openrun` prints is escaped the same way, including failures that the session process reports, so text from a client never drives the terminal of the caller. The tool's own line breaks stay. A message with a list, such as the sessions that start with the typed identifier, is a heading and one line for each entry (`CommandLineToolError.failureWithList`). The tool escapes each line on its own, so every entry is on its own line, and a line break inside client text shows as `\n`.

## Limits

- The session process does not survive a Mac restart, and launchd does not start it yet.
- `openrun attach` draws only the visible screen into the terminal. The scrollback of the session stays in the session. `openrun read --scrollback` prints it.
- Two clients that relay raw output (two `openrun attach` windows on one session) both answer each query, so the program gets two replies. See "Query replies".
- A query that is pending when its relaying client detaches gets no reply.
- A process that starts a session of its own (`setsid`), such as a daemon, outlives `openrun kill` and shutdown. A program that ends by itself leaves its background processes running. Both are owner decisions.
- The scrollback holds about 10,000 lines. libghostty-vt prunes whole pages, so it keeps somewhat fewer after the first prune; a test measured 9,659.
- A frame carries at most 64 MiB. An unfinished escape sequence counts at most 32 MiB of that in a snapshot. A client may fall 8 MiB of output behind before it loses its connection. Snapshots and screens do not count toward this. A first control frame that is larger than 8 MiB is queued whole, and the limit for a write that stalls (10 seconds) ends a client that does not read it.
- A snapshot larger than 64 MiB loses its oldest scrollback. So a client of a very wide session with a full, colorful scrollback gets only the newest lines that fit. A client cannot attach at a size at which the screens alone pass 64 MiB.
- At most 64 clients are connected at once, counting clients whose last messages still go out after they detached. While 64 such clients close, a new client is refused for up to 2 seconds. Other limits and deadlines are in "Limits and deadlines of a client". A client may still send one frame of up to 64 MiB, so 64 clients can make the session process hold 4 GiB for a moment.
- Input that a program does not read waits: 8 MiB in the session process, 1 MiB more for each client, and up to 16 MiB in `openrun attach`. At that limit `openrun attach` stops reading the terminal until the program reads, and the terminal holds the keys. The detach key then waits behind them, and a signal, such as the SIGHUP of a closed window, still ends the tool. `openrun send` returns only when its text is in the backlog. A program that never reads its input therefore makes `openrun send` wait until the program reads or ends.
- Keys that `openrun attach` typed and that have not gone to the program are dropped when it detaches or loses its connection. Text that `openrun send` was told has arrived is not dropped.
- When `openrun attach` detaches while its keys wait for the program, the `detach` message is read through the reserve of the read-ahead when it comes right behind a full read-ahead. When more keys wait in the socket in front of it, it stays stuck behind them. The session process then finds the closed connection within about 100 milliseconds and detaches the client.
- A program that asks queries and never reads the answers stops in its own output once 1 MiB of answers wait. Only answers count for this, so typed input alone never stops the output.
- Any program of the same user can connect to the socket. The socket mode, the folder check and the check of the peer's user keep other users out. The folder check looks at the folder of the socket only, not at the folders above it. It reads the mode and the access control list of that folder, not the access control lists of the socket file and the lock file.
- A stale socket file is removed by its path after a check of its device and inode. A program that replaces it in the moment between that check and the removal still loses its file. Only a program of the same user can do this, because the folder is the user's own.
- A query is recognized by its exact bytes `ESC [ 1 5 t`. `CSI 15 t` written with other parameters, such as `ESC [ 0 1 5 t`, gets no reply.
- When the terminal takes no output, `openrun attach` puts the mode back at once and gives the closing sequences one second. Sequences that do not get through in that time are lost. A closing that got only part of its bytes through is made again whole at the next closing. It starts with CAN, which ends a sequence that was cut short. The terminal can then stay inside a sequence that the program, or a picture cut short, left open, until the next output ends it.
- `openrun attach` stops itself with SIGSTOP on SIGTSTP. In a process group that no shell controls, nothing may continue it, as with any program that stops.
