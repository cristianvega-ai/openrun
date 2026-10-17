---
title: OpenRun architecture
date: 2026-10-15
---

# OpenRun architecture

This document explains the code of the headless core, which is milestone 1 of version 1.
It is for the owner. Read it with `documentation/product.md`, which holds the decisions, and `AGENTS.md`, which holds the rules of the code.
Update it when you add a module or change the protocol.


## Modules

Each feature is its own Swift module, as `AGENTS.md` requires.
A module uses another module only through its public types.

| Module | What it does | Public types |
|---|---|---|
| `TerminalEmulation` | Wraps libghostty-vt: the screen, the scrollback, snapshots, replies to the queries that programs send, and the default colors that a client sets | `Terminal`, `TerminalSnapshot`, `UnfinishedSequence`, `TerminalSize`, `TerminalCursorPosition`, `ScreenFormat`, `ScreenExtent`, `TerminalReplyHandler`, `TerminalColorScheme`, `TerminalColor`, `TerminalEmulationError`, `PrintableText` |
| `PseudoTerminal` | Runs one program on a new pseudo terminal | `PseudoTerminal`, `PseudoTerminalSize`, `ProgramLaunch`, `ProgramExit`, `LoginShell`, `PseudoTerminalError` |
| `SessionProtocol` | The socket protocol that the session process and all clients share | `ClientMessage`, `ServerMessage`, `SessionExit`, `SessionFailure`, `MessageFrame`, `FramedMessage`, `MessageConnection`, `SocketLocation`, `PeerIdentity`, `SessionSummary`, `SessionSize`, `SessionEnvironment`, `SessionProtocolError` |

`TerminalEmulation` is the only module that imports libghostty-vt.
`PseudoTerminal` and `SessionProtocol` depend on no other OpenRun module.

### TerminalEmulation

`Terminal` parses output bytes and keeps the state of the screen.
`TerminalSnapshot` encodes the whole state as bytes, including an escape sequence that is not finished yet, and restores it in another `Terminal`.
`TerminalSnapshot(capturing:byteLimit:)` captures within a byte limit. When the whole state is larger, it restores a copy of the terminal and lowers the scrollback line limit of the copy until a new capture fits. Each try keeps fewer lines than the try before. libghostty-vt drops the oldest whole pages over a line limit, so the snapshot keeps as many lines as fit, to within one page. The screens, the cursor, the modes and an unfinished sequence stay whole. The terminal itself keeps all of its scrollback. When a capture without scrollback is still too large, the result is `nil`.
`Terminal.formatted` writes the screen as plain text, or as text with the sequences that reproduce it.
`UnfinishedSequence(of:)` returns the start of an escape sequence or a UTF-8 character that the terminal has parsed and the program has not finished. It wraps `ghostty_terminal_continuation_alloc`, the documented libghostty-vt call for these bytes. libghostty-vt knows them only when it tracked them from the first byte: a new `Terminal` tracks from its start, and a restored terminal from its snapshot on.

`Terminal` refuses values that no window has. A grid needs 1 to 10,000 columns and rows (`Terminal.maximumGridDimension`), at creation and in `resize`. The scrollback limit must be 0 to 1,000,000 lines (`Terminal.maximumScrollbackLines`); a negative number would reach libghostty-vt as an enormous unsigned one. A snapshot restore checks the limit too. Each refusal throws `TerminalEmulationError` before libghostty-vt is called.

### PseudoTerminal

`PseudoTerminal(launching:)` starts a program as a session leader with the pseudo terminal as its controlling terminal.
It uses `forkpty`, which makes the pseudo terminal, forks, and in the child makes a new session (`setsid`) and opens the terminal as the controlling terminal.

`posix_spawn` with `POSIX_SPAWN_SETSID` does not work for this. It opens files before it makes the new session, so the program starts with the terminal as standard input but without a controlling terminal.
Only a program that opens the terminal itself later, such as `/bin/sh`, then gets one. `ps -o tty=` showed `??` for `sleep`, `zsh`, `perl`, `dash` and `ksh`. Without a controlling terminal, Control-C does nothing and zsh turns job control off.

The child shares the memory of a process that has other threads, so it must not allocate or take a lock.
The parent prepares every C string before the fork. The child calls only system functions with plain numbers and pointers until `execve` replaces it:

- The terminal is descriptors 0, 1 and 2. The child closes every other descriptor up to 10,240, so nothing leaks into the program.
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
