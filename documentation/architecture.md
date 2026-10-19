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

The tests follow the same rule. `Tests/SessionProcessHarness` is support code for the integration tests: it starts the real executables.

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
- `write`, for a terminal's answers to queries. It never waits, because the terminal answers while it parses output. The answer joins the backlog even when the backlog is full. When typed input waits for room, the answer goes in right behind that input, because a real terminal sends its bytes in the order it made them. It waits only for the input in front of it, never for room. An answer that waits counts toward the 1 MiB of answers at once (see `waitForAnswerRoom`).
- `waitForAnswerRoom`, which waits while more than 1 MiB of answers wait for the program. The session calls it after each chunk of output. A program that asks without end and never reads the answers then stops in its own output, as typed input stops at 8 MiB.
- `resize`, which sets the size with `TIOCSWINSZ`. The kernel sends SIGWINCH to the program.
- `waitForExit`, which returns a `ProgramExit`.
- `terminate`, which ends the program and every other process of its terminal session. The program is a session leader (see `forkpty` above), so this means every process whose session identifier is the program's, also one that moved to another process group. SIGHUP goes to the program's process group first, then to each other process group of the session. A group with a stopped process also gets SIGCONT, because a stopped process acts on the hang-up only when it runs. After the grace period (one second), SIGKILL goes to every process of the session that is still alive, also when the program itself has already ended. A program that has already ended by itself when `terminate` is called leaves its background processes running. A process that started a session of its own (`setsid`), such as a daemon, is not in the session and keeps running. When the system cannot list the processes, the session counts as unknown, not as empty. `terminate` then sends SIGHUP to the program's process group, the process group of the session leader, and repeats it while it waits. It keeps waiting and signalling until the grace period (one second) has passed, and then sends SIGKILL to that group, repeatedly, for up to one more second (the killing limit). It never takes a failed list for a session with no process left.

`InputBacklog` (internal) keeps the books of the input: the backlog, the input that waits, the owners, and the limits. `PseudoTerminal` keeps one on its queue, writes the bytes, and calls the completions that it returns. Unit tests check it without a program. The two queues of `InputBacklog` (the pieces in the backlog and the input that waits) keep a start index that moves up when the front goes. They drop the unused head when it is half of the storage and holds at least 64 entries. Taking the front costs a constant time on average, so 100,000 one-byte pieces drain in well under one second. The limits and the order of the bytes did not change.

`TerminalSessionProcesses` (internal) finds the processes of the program's session and sends them signals. It uses Darwin calls only. macOS lists no processes by session (`sysctl` with `KERN_PROC_SESSION` fails with ENOENT), so it lists every process with `proc_listallpids` and asks each one for its session with `getsid`. A zombie has ended and is left out. Right before each signal it checks the session of the process again, so a process that ended, and whose identifier went to another program, never gets the signal. A process group gets a signal only when one of its members is still in the session and in that group right before the signal. `members()` throws `TerminalSessionProcesses.ListingFailed` when `proc_listallpids` fails, so a caller can tell a failed list from a session with no process. An empty result means that the session has none.

Why a session identifier is safe to trust: a session identifier is the process identifier of the process that made the session. XNU gives a new process an identifier only when no process, also a zombie, uses that number as its process, process group or session identifier (`forkproc` in `bsd/kern/kern_fork.c`, which keeps the rule of the 4.4BSD `fork`). So while one process of the session lives, no other session can have its number. `terminate` starts only while the program is not yet reaped, looks again at least every 20 milliseconds, and stops for good once the session has no process left. Another session could take the number only after every other process identifier, about 100,000 of them, was handed out in between.

The controlling descriptor is closed once, when the program has ended and the last dispatch source that watched it is gone.

`LoginShell.current()` reads the shell from the user database. `LoginShell.launch` starts it with a leading dash in its name, which makes it a login shell.

### SessionProtocol

This module holds the messages, the frame format, the connection, and the socket location with the check of its folder. `FolderAccessControlList`, an internal type, reads the access control list of the folder for that check. The next sections describe them.

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
Raise `MessageFrame.protocolVersion` when a change would confuse an older program.
The `hello` message itself must stay readable by every version.

### Control messages

A control message is a JSON object with one key, the name of the message. The value holds its fields.
A field without a name in the Swift code is called `_0`.


A session summary holds `identifier`, `folder`, `command` (a list), `size` and `createdAt` (seconds since 1970).
A size holds `columns` and `rows`, each 0 to 65,535.
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
The identifier is a UUID. In JSON it is the usual upper case text. People and environment variables see it in lower case.

### A conversation

1. The client connects and sends `hello`. The server answers `hello`.
2. A request that needs one answer (`createSession`, `listSessions`, `readScreen`, `sendText`, `killSession`) gets its answer. The client may send the next request or close.
3. `attach` starts a longer conversation. See the next section.

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
  | resize, detach  ---------------------->  |
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

