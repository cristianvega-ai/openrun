# OpenRun

OpenRun is a native macOS terminal for work with coding agents.
`documentation/product.md` holds every product decision. Read it before you change behavior.
The owner makes each decision. Record a new decision in its decision log.

## Organize code by feature

- Each feature is its own Swift module: a target in `Package.swift`, with its code in `Sources/<Feature>/` and its tests in `Tests/<Feature>Tests/`.
  A reader finds a feature's code by the feature's name.
- Name a module after what the feature does, such as `TerminalEmulation`, `PseudoTerminal`, `SessionProtocol`, or `SessionProcess`.
- Do not create grab-bag modules or folders, such as `Common`, `Shared`, `Utilities`, `Helpers`, `Models`, `Managers`, or `Extensions`.
  Code that two features use belongs to the feature that owns the idea.
- Keep each module small, with a narrow public interface.
  A feature uses another feature only through its public types. Everything else stays `internal` or `private`.
- Dependencies between modules point one way, from the executables down to the features they use.
- Keep the executables thin. `Sources/openrun/` and `Sources/openrun-session/` read their start-up input and call a feature module.
- Put one main type in each file, and name the file after it. Split a file when it holds more than one concern.
- Wrap each outside library in one feature module. Only `TerminalEmulation` imports libghostty-vt.

## Use full words in names

- Use full words in every name we create: modules, types, functions, variables, files, folders, commands, flags, environment variables, and settings keys.
- Do not use acronyms or abbreviations.
  Write `identifier`, not `id`; `PseudoTerminal`, not `PTY`; `configuration`, not `config`; `message`, not `msg`; `index`, not `idx`; `CommandLineTool`, not `CLI`.
- A name from an outside interface keeps its own spelling, such as Foundation's `URL` and `UUID`, Darwin's `ioctl`, or libghostty-vt's `ghostty_terminal_new`.
  Use it only at that boundary, and give our wrappers and variables full-word names.
- Product names keep their own spelling, such as OpenRun, Ghostty, libghostty-vt, macOS, and AppKit.

## Language and platform

- Write Swift only, in the Swift 6 language mode with strict concurrency checking.
  libghostty-vt is the one C library.
- Ask the owner before you add a C target or a third-party Swift package.
- The app uses AppKit only, not SwiftUI.
- OpenRun supports macOS 26 and later.

## Build and test

- `scripts/build-ghostty-library.sh` builds libghostty-vt from the Ghostty commit pinned in the script. Run it once before you build.
- `swift build` builds every module. `swift test` runs every test.

## Comments and documents

- Write comments that explain why the code does something, not what it does.
- Write documents in plain English with short sentences and full words.

## Commits

There are no pull requests. Each commit is the unit of review, so each one must be easy to review alone.

- A commit changes at most 100 lines in at most 10 files. Count the added and removed lines that `git diff --cached --shortstat` prints, in every file, tests and documents included.
- Each commit is one logical slice of work that has value by itself. It builds, and `swift test` passes.
- Split larger work into a series of such commits. Each one still builds and works on its own.
- Commits go onto `main` in a straight line, with no merge commits. Work on a temporary branch, such as work in parallel, goes onto `main` one commit at a time.
- Push `main` to `origin` only after the owner approves the push. The repository is public, so a push publishes the commits.

### Commit messages

Follow the standard Git format:

- The subject line has at most 50 characters. It starts with a verb in the imperative, such as "Add", "Change", or "Remove", and has no period at the end.
- A blank line separates the subject from the body.
- The body tells what changed and why. Wrap it at 72 characters.

Write the subject and the body in ASD-STE100 Simplified Technical English:

- Use only words from the ASD-STE100 dictionary, with their approved meanings. Technical names, such as `SocketLocation`, libghostty-vt and SIGTERM, are permitted.
- Give each word one meaning. For example, "fix" means "attach", so write "repair", not "fix".
- Use the active voice, and only the present, past and future tenses.
- Do not use the "-ing" form of a verb.
- Write one topic in each sentence. An instruction has at most 20 words, and a description at most 25.
- A paragraph has at most 6 sentences.
- Do not leave out "the", "a" or "an".

Example:

    Make the stop test wait for a full queue

    The test sent SIGTSTP when the output queue was half full.
    The attach tool then stopped before the test sent the
    signal to end. The test now waits until the queue is full.
