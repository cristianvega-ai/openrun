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
