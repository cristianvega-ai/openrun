# OpenRun

OpenRun is a native macOS terminal for work with coding agents.
This repository holds the headless core of version 1: a session process that owns every shell and agent, and the `openrun` command-line tool that talks to it.
`documentation/product.md` holds the product decisions.
`documentation/architecture.md` explains the code.

OpenRun supports macOS 26 and later. The code is Swift only.

## Build

1. Build libghostty-vt once. The script downloads a pinned Ghostty commit and Zig 0.16.0 into `Libraries/`.
   The script holds the SHA-256 checksums of that Zig release (the archive and its `zig` program, for Apple silicon and Intel). It extracts the Zig archive again in each run, from `Libraries/zig` when the archive matches its checksum, or from a fresh download, and then checks the `zig` program against its checksum. A Zig in the search path is never used, and a Zig of another release, even 0.16.1, is never used.
   The script refuses to build when the Ghostty tree in `Libraries/ghostty` has changes, before it fetches or checks out anything, because the library would then not be the pinned commit and an edit would be lost. Remove the folder and run the script again.
   It builds libghostty-vt in `ReleaseFast` mode, as Ghostty does. A Debug build is far too slow for dense output.
   The first build takes a few minutes. When the mode in the script changes, run the script again and it builds again.

   ```sh
   scripts/build-ghostty-library.sh
   ```

2. Build the package.

   ```sh
   swift build
   ```

The two programs are in `.build/debug/`: `openrun-session` and `openrun`.

## Test

```sh
swift test
```

The tests include integration tests. They start the real `openrun-session` and `openrun` programs on short socket paths under `TMPDIR`, and they stop every process they start.
Among other things, they check what needs the real programs:

- Dense output stays fast: a program that writes 16 MB of text must reach its exit within 5 seconds, with and without an attached client (`ThroughputTests`).
- Each terminal query gets one reply: from the session process when no real terminal is attached, and from the real terminal when `openrun attach` is. A program that turned on mode 2048 gets exactly one size report for each size change, also when another client changes the size while `openrun attach` is attached (`QueryReplyTests`).
- A client that asks hears of each size that another client sets, before the output for that size. The client that set the size, and a client that did not ask, hear nothing (`ResizeTests`).
- The program has a controlling terminal: Control-C interrupts a foreground job, and an interactive zsh runs jobs in the background and brings them back with `fg` (`JobControlTests`).
- Input is never lost while its client is there: text past the 8 MiB backlog reaches a slow program complete and in order, a send whose program ends first fails, and a client that floods input meets backpressure while the session process stays small. The backlog holds at least 8 MiB and about 9 MiB at most before the sends stop. Clients that flood input and leave, 30 times over, hold no memory, threads or descriptors, and their input never reaches the program. A client whose input waits can detach with a clean close, and that input never reaches the program, also when its input fills the read-ahead of 1024 messages or 1 MiB. A flood of one-byte frames stops near the limit of 1024 messages. A client that vanishes, or stops sending, while its read-ahead is full is noticed within a second (`InputBacklogTests`).
- Each client costs a bounded amount: silent and slow connections are closed at their deadlines, a client past the limit of 64 is refused, a client that stops reading is closed soon after its program ends, and a process out of descriptors neither spins nor drops every waiting client. 150 clients that attach, read nothing and detach, one after another, hold no more than 64 sockets, and a place frees within the closing limit of 2 seconds. A client that asks for large lists of sessions and reads nothing is closed at the 8 MiB limit (`ConnectionLimitTests`).
- The socket is safe from other users: a folder that others can write to, through its mode or its access control list, or that belongs to another user, is refused by both programs, and a squatter there learns nothing. A file in the place of the folder is refused by name. A lock file is used only when it is a regular file of the user, and gets mode 0600. A file that replaces a stale socket while the session process checks it is left alone, and the listener closes the connections past the 64 that wait for the server. A listener that never answers hello is replaced, a relative socket path reaches every program as an absolute one, an absolute one without its `.` and `..`, and each side refuses a peer of another user. A test cannot start a program as another user, so the last check is tested by making each side expect another user. Of two session processes that start on one socket at the same moment, exactly one survives, 30 times over, and a process that stops removes its socket file only when the file is still its own (`SocketSecurityTests`).
- Clients that break the rules lose only their own connection: a frame of length zero, of an unknown kind, of the wrong direction, with text that is not a message, with keys inside a text frame, or with a length above 64 MiB; a request before `hello`; another protocol version; and a client that says nothing. Each is tried against a running server, and a neighbor that is attached to a session keeps getting its output. A second `hello` and a second `attach` get a failure answer on the same connection, and input before `attach` reaches no program. A request that cannot be decoded (text that is not JSON, a name that is no message, a missing field, a size of 999999 or -1, 64 MiB of nested arrays) gets a failure that names the problem, and then its connection closes (`HostileClientTests`).
- A client that falls behind is dropped only past the 8 MiB limit: with 7 MiB of output waiting it keeps every byte, with 9 MiB it loses its connection, and it can attach again and gets a fresh snapshot. A snapshot larger than 8 MiB reaches a client whole while the program prints. A snapshot that falls inside an escape sequence or a character holds the unfinished bytes, and the output after it completes them. A client can attach while the program is on the alternate screen, and a scrollback of about 10,000 lines survives attaching and attaching again. A snapshot larger than one frame of 64 MiB keeps the whole screen and the newest scrollback that fits, and the screen of the client is the screen that `openrun read` shows. A size at which the screen alone does not fit gets a failure that names the problem, and no `attached` (`ReattachTests`).
- A client that is paused still gets the exit status at shutdown, and a client that is attached when the session process stops ends with the status of its program, `128 + 1` for a program ended by SIGHUP, and leaves the terminal in the mode it found (`ShutdownTests`).
- `openrun attach` to a program on the alternate screen draws the picture on the alternate screen, and detaching leaves it (`AttachCommandTests`).
- The wire format is pinned by hand-written bytes and texts, not by the code that writes it: the number of each frame kind, the big-endian length, the limit of 64 MiB, and the text of every message (`MessageFrameTests`).

The checks of memory, threads and descriptors read the numbers from the system. A check fails when the system does not report a number or reports zero. The commands that the helpers of the tests run (`openrun list`, `openrun read`) must end with status 0 and write nothing to standard error, so a dead session process is an error and not an empty list.

The run takes about five minutes, including the build of the tests. One measured run took 4 minutes 44 seconds.

## Try the core by hand

You need two terminal windows. Run these commands from the repository folder.

In the first window, start the session process. It runs in the foreground and logs to standard error.

```sh
.build/debug/openrun-session
```

It listens on `~/Library/Application Support/OpenRun/session.socket`.
To use another socket, give `--socket PATH` to every program, or set `OPENRUN_SOCKET`. A relative path starts at the current folder.
The folder of the socket must belong to you, and other users must not be able to write to it, neither through its mode nor through an access control list, so `/tmp` does not work. Both programs refuse such a folder with a message that names it.
Only one session process runs on a socket. It holds a lock file next to the socket, `PATH.lock`, for as long as it runs, so a second one refuses to start. The lock file must be a regular file of yours, and the session process sets its mode to 0600. The lock file stays when the process ends.
Both programs talk only to a program of the same user at the other end of the socket.

In the second window, start a session and attach to it.

```sh
export PATH="$PWD/.build/debug:$PATH"
openrun new                       # prints the identifier of a new login shell
openrun list                      # identifier, folder and command of each session
openrun attach 3f2a               # any unique start of the identifier works
```

Type in the attached shell. Press Control-] to detach. The shell keeps running.
`openrun attach` draws the screen also when the program was in the middle of an escape sequence, and detaching ends any sequence that the program left open, so the terminal comes back clean.
When the terminal stops taking output, as a frozen `ssh` does, Control-] and SIGTERM still end `openrun attach` within about a second and put the terminal mode back. SIGTSTP suspends it with the terminal restored, and `fg` draws the session again.
The key works also when a program has turned on the kitty keyboard protocol or xterm's modifyOtherKeys, which change what the terminal sends for Control-].
The key also works when a terminal delivers it in two parts, as `ssh` can. To allow for this, `openrun attach` holds the start of such a key for up to 20 milliseconds, so the Escape key reaches the program up to 20 milliseconds late.
Attach again to see the same screen.

More commands:

```sh
openrun new --folder ~/Projects -- claude   # run a program instead of the shell
openrun send 3f2a --enter "ls -l"           # type into a session without attaching
openrun read 3f2a                           # print the screen as plain text
openrun read 3f2a --scrollback              # include the lines above the screen
openrun kill 3f2a                           # end the session and every process in it
openrun help
```

Every program in a session gets `OPENRUN_SESSION` (its identifier), `OPENRUN_SOCKET`, `TERM=xterm-256color`, `COLORTERM=truecolor` and `TERM_PROGRAM=OpenRun`.

Input that a program has not read yet waits in the session process, up to 8 MiB. Past that, `openrun send` waits until the program reads, and it fails with a message when the program ends first. Nothing that `openrun send` was told has arrived is dropped. Keys that `openrun attach` typed and that have not reached the program yet are dropped when it detaches, so a client that leaves holds no memory.

The session process serves at most 64 clients at once and refuses more with a message. A client counts until its socket is closed. A request that the session process cannot read gets a failure that names the problem, and the connection closes. A client must say hello within 5 seconds, and a frame that stops halfway for 30 seconds, or a write to a client that takes nothing for 10 seconds, ends that client. A client may fall 8 MiB of output behind. Snapshots and screens do not count toward that, so a large scrollback can always be attached. A snapshot travels in one frame of at most 64 MiB, so a very wide session with a full, colorful scrollback sends only the newest lines that fit. At shutdown each client gets up to 2 seconds to take its program's last output and exit status. `documentation/architecture.md` lists every limit.

To stop the session process, press Control-C in its window, or send it SIGTERM.
It removes the socket file, ends every program and every other process in the terminal session of each program, and exits with status 0.
`openrun kill` ends a session the same way: all its processes end, also those that moved to another process group. A process that starts a session of its own, such as a daemon, keeps running, and so do the background processes of a program that ended by itself.
While it stops, a client that is already connected cannot start a new session. It gets the failure "The session process is stopping."

When `openrun new` is given a program name without a slash, the session process searches the `PATH` that the client sent. An entry that is relative or empty means the folder of the new session, because the program starts there. Only a regular file with the execute permission matches.

## Layout

| Folder | Feature |
|---|---|
| `Sources/TerminalEmulation` | The only code that uses libghostty-vt: screen, scrollback, snapshots, replies |
| `Sources/PseudoTerminal` | Runs a program on a pseudo terminal |
| `Sources/SessionProtocol` | The socket protocol that the session process and its clients share |
| `Sources/SessionProcess` | The background process that owns the sessions |
| `Sources/CommandLineTool` | The `openrun` commands |
| `Sources/openrun`, `Sources/openrun-session` | Thin programs that call the features above |

Read `AGENTS.md` for the rules of the code.
