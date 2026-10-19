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
- Clients that break the rules lose only their own connection: a frame of length zero, of an unknown kind, of the wrong direction, with text that is not a message, with keys inside a text frame, or with a length above 64 MiB; a request before `hello`; another protocol version; and a client that says nothing. Each is tried against a running server, and a neighbor that is attached to a session keeps getting its output. A second `hello` and a second `attach` get a failure answer on the same connection, and input before `attach` reaches no program. A request that cannot be decoded (text that is not JSON, a name that is no message, a missing field, a size of 999999 or -1, 64 MiB of nested arrays) gets a failure that names the problem, and then its connection closes (`HostileClientTests`).
- A client that falls behind is dropped only past the 8 MiB limit: with 7 MiB of output waiting it keeps every byte, with 9 MiB it loses its connection, and it can attach again and gets a fresh snapshot. A snapshot larger than 8 MiB reaches a client whole while the program prints. A snapshot that falls inside an escape sequence or a character holds the unfinished bytes, and the output after it completes them. A client can attach while the program is on the alternate screen, and a scrollback of about 10,000 lines survives attaching and attaching again. A snapshot larger than one frame of 64 MiB keeps the whole screen and the newest scrollback that fits, and the screen of the client is the screen that `openrun read` shows. A size at which the screen alone does not fit gets a failure that names the problem, and no `attached` (`ReattachTests`).
- `openrun attach` to a program on the alternate screen draws the picture on the alternate screen, and detaching leaves it (`AttachCommandTests`).
- The wire format is pinned by hand-written bytes and texts, not by the code that writes it: the number of each frame kind, the big-endian length, the limit of 64 MiB, and the text of every message (`MessageFrameTests`).

The checks of memory, threads and descriptors read the numbers from the system. A check fails when the system does not report a number or reports zero. The commands that the helpers of the tests run (`openrun list`, `openrun read`) must end with status 0 and write nothing to standard error, so a dead session process is an error and not an empty list.

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
