# Warp, offline

This is a fork of the open-source Warp terminal, reworked to run fully offline for enterprise use. It keeps the terminal and drops everything that talked to a server.

## What this is

A GPU-rendered terminal with blocks, a modern input editor, command completions, workflows, a code editor with file tree, code review and global search, tabs, panes and themes, and UI support for the CLI agents you run yourself (Claude Code, Codex, Gemini CLI, OpenCode). That support covers the CLI-agent toolbar, the rich input composer (Ctrl-G), notifications and vertical-tab status.

## What is not here

- No accounts. There is no login, sign-up, SSO, teams or billing; the app is permanently signed out.
- No built-in AI or agents: no Oz, Agent Mode, Warp AI, MCP, skills, codebase indexing or voice input.
- No Warp Drive, cloud sync, session sharing or block sharing.
- No telemetry, crash reporting or experiments, and no autoupdate. Update by installing a newer build.
- No links to Warp's website, docs, blog, Slack or feedback forms.

[CHANGES.md](CHANGES.md) records each removal, why it was made and what it means for users.

## Network access

The app itself opens a network connection, or runs a network tool of yours, only in these cases:

- **Language server downloads**, off by default. Enable `code.language_servers.allow_downloads` (Settings > Code > Projects) to let the editor install missing language servers and the Node.js runtime they need. With it off, only language servers already on your machine are used.
- **Links you open yourself**, such as a URL clicked in terminal output.
- **`warpctrl` local control**, off by default (Settings > Scripting). When enabled it listens on a loopback port and accepts connections from the local machine only.
- **Your own git remotes and GitHub, through `git` and the GitHub CLI (`gh`), only while the UI that needs them is in use.** The app never talks to GitHub itself; it runs the `gh` and `git` on your machine, against the remotes your repository already has, and `gh` uses your own login.
  - The GitHub pull request chip is **not** in the default prompt or the default CLI-agent footer, so a fresh install never runs `gh` on its own. Add the chip yourself to opt in: right-click the prompt, choose Edit prompt and drag the pull request chip into it (or add it to the CLI-agent footer layout). A prompt you saved earlier with the chip keeps it.
  - While a terminal in a git repository has the GitHub pull request chip in its prompt or CLI-agent footer and its tab is selected, the app runs `gh pr view` and `gh repo view` when the tab is shown, when the branch changes, after you run a `gh` or `gt` command in that terminal, and about once a minute.
  - While the code-review panel is open in the selected tab, it does the same for its pull request button.
  - `gh` runs only while something on screen shows the pull request. A tab you switch away from stops running `gh` about 30 seconds later, and a pane that a maximized pane covers does the same. A terminal whose prompt is hidden by a full-screen program (`vim`, `less`, `htop`) stops about 30 seconds later, and one whose prompt is hidden by a running command that is not full-screen stops about 3 minutes later (so a command that finishes within 3 minutes starts no extra `gh`), unless a CLI-agent footer with the chip is showing; it looks up GitHub again when the prompt returns. Selecting the tab again looks up GitHub at once. The exception is the vertical tabs panel: while it is open and its rows show pull request badges (expanded rows with "PR link" on, or summary rows), those tabs and panes keep polling. The compact rows show no badge. The app does not detect a window that is minimized or hidden behind others: the selected tab of such a window keeps polling while its chip is in the prompt. That gap is tracked as ENG-203 (Backlog) and is not fixed.
  - When you click them, the commit and push dialog runs `git push`, and its pull request button runs `gh pr create`.
  - A repository terminal with no pull request chip in its prompt and no open code-review panel runs neither, and neither does a tab in the background. Removing the chip from the prompt (Edit prompt again) turns the polling off. Local `git status` for the other prompt chips does not touch the network.

Command completions use 53 reviewed generators from the 474 bundled definitions; 421 are disabled. They run only in local sessions whose executor applies the offline environment and macOS network sandbox. SSH and in-band sessions use static and file completions. The retained commands read Git metadata, list installed uv tools, locate rustup documentation, or list Docker objects. Project-selected Python, Cargo toolchains, package-manager hooks and unverified tools are denied. [AUDIT.md](crates/warp_completer/src/signatures/legacy/generator_policy/AUDIT.md) records each former accepted generator's decision, tested tool versions, hostile fixture and regression test.

Typed words pass a token gate before a generator builds a command: accepted token-taking generators permit only letters, digits and `. _ / : @ + , = -`, with restrictions on leading `=` and flag-shaped words. Git alias expansion uses the same gate and local-session requirement; npm and yarn script aliases are disabled. Git commands additionally require Git 2.31 or newer. The environment disables repository fsmonitor and signature helpers, optional hooks and every Git transport, including local paths and custom helpers; a partial clone with missing objects can therefore return fewer suggestions. The tests include Git 2.31.0, unpatched 2.43.0, patched backports and Apple Git. An empty protocol list matters: `file` allows repository upload-pack programs, and `none` can name a custom remote helper.

Every local completion command also runs inside a `sandbox-exec` profile that denies IP networking, including loopback, to it and its children. If that sandbox cannot be applied, the command does not run. Unix sockets and files remain accessible. The evidence covers the tested tools and hostile configurations; it does not prove all future tool releases safe, distrust the installed executables, prevent a local daemon from using its own network access, or cover commands you submit yourself. Details are in [SECURITY.md](SECURITY.md#how-completion-generators-are-kept-offline).

Your shell and the programs you run in it, including SSH sessions and CLI agents, use the network as they normally would.

`script/offline_audit` checks the repository for reintroduced Warp hosts, network-capable code and banned dependencies, and CI runs it.

CI uses macOS runners for builds and tests, lints with clippy `-D warnings`, and runs unit and integration tests plus an idle session in a network sandbox. Tests that exercise the app's own sandbox run separately; the shell matrix runs on relevant changes, nightly and on dispatch. The collector refuses remote IP access and DNS delegation, checks canary launch identities, and fails on missing or incomplete evidence. Retried passes and leaked test processes fail the run. See [CONTRIBUTING.md](CONTRIBUTING.md#continuous-integration).

## Data stored on your computer

The app keeps some of what you do in a local SQLite database in its per-user state directory (the file ends in `.sqlite`, with a `-wal` file beside it while the app runs). Nothing in it is sent anywhere; it is a second copy of your terminal activity on disk, in the same way your shell's own history file (`~/.zsh_history`, `~/.bash_history`) is a copy.

- **Command history.** Every command you run in a session is added to a `commands` table with its working directory, shell, user name, host name, git branch, start and end time and exit code. The table keeps the newest 10,000 commands, and it feeds up-arrow history and history search in later sessions.
- **Block text and output for session restore.** For each pane the app saves the command text, the output (up to 5,000 lines per block, with its colors) and the prompt of up to the last 100 blocks, so that the next launch can restore the scrollback. This is the `blocks` table. The window, tab and pane layout is saved too (working directories, shell, split sizes); it holds no command text or output.
- **Not covered by redaction.** Secret redaction (Settings > Privacy) only changes what is drawn on screen. The original text is what is saved, so a token that was printed in a command or in its output is in the database as typed.
- **Commands you start with a space.** A command that starts with a space is not saved, in the database or in up-arrow history, when your shell ignores it: zsh with `histignorespace`, bash with `HISTCONTROL` containing `ignorespace` or `ignoreboth`, and fish always (fish does not record such commands). The block of such a command is not saved for session restore either. With any other zsh or bash setting, such a command is saved like any other, and so are PowerShell commands: PowerShell has no leading-space default, so the app applies no such rule to it.

You control this in Settings > Privacy:

- **Save command history and block output** (default on; settings file key `privacy.save_command_history`). When it is off, nothing new is written to the `commands` or `blocks` tables, and what is already saved is not loaded at startup, so blocks from your previous session are not restored (your windows, tabs and panes still are). Up-arrow history keeps working in the running app, from your shell's history file and the commands you run in that session, and the commands of that session are forgotten when you quit. Turning it off does not delete anything already saved; the app offers to do that at once.
- **Delete saved history.** Asks for confirmation, then deletes every row of the `commands` and `blocks` tables with SQLite secure deletion enabled. It checks write-ahead-log checkpoints and compacts the database. If another reader or writer prevents compaction, the result says compaction is pending; a durable cleanup record triggers retries during activity, at shutdown and on the next launch. Your layout, projects and other settings stay. Completed compaction is a SQLite result, not a forensic-erasure guarantee: identical text in retained settings, the shell's own history, backups, snapshots, drive storage and file-system journals can remain. A command or output already shown in an open window stays on screen until you close it.

The secret scan of this repository's Git history is a different guarantee: it concerns the source tree, not what the app stores on your machine, and nothing here promises that your saved history is free of secrets.

To remove everything the app saved, quit it and delete the state directory's `.sqlite` and `.sqlite-wal` files. Setting `privacy.save_command_history = false` in the settings file before the first launch keeps the database free of commands from the start.

## Platform

OpenRun runs on macOS only. The Windows, Linux and web (wasm) targets, their windowing and rendering layers (winit, wgpu), their packaging and their CI were removed; [CHANGES.md](CHANGES.md#macos-only) lists what went. SSH sessions to Linux hosts still work: the remote shell bootstrap keeps its Linux branches (bash, zsh, fish and PowerShell), and a remote Linux host is described by `TargetOS` in `crates/warp_core/src/platform.rs`.

## Building and running

```bash
./script/bootstrap   # macOS setup
./script/run         # build and run
./script/presubmit   # fmt, clippy, and tests
```

Building fetches Rust crates and a few git dependencies (forks of upstream Warp libraries hosted on GitHub). That happens at build time only; the built app does not contact them.

The app builds as `warp-oss`. See [AGENTS.md](AGENTS.md) for the engineering guide: architecture, coding style, testing and platform notes.

Bundle identifiers, data directories, the `warposs://` URL scheme and install paths are unchanged from upstream Warp OSS, so existing installs and stored preferences keep working. [CHANGES.md](CHANGES.md) lists them.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Report bugs and feature requests, and ask questions, through the issue tracker of the repository this fork is hosted in. Report security problems privately to the fork's maintainers, as described in [SECURITY.md](SECURITY.md).

## Code of Conduct

We follow the [Code of Conduct](CODE_OF_CONDUCT.md). Report violations to the fork's maintainers.

## Licensing

Warp's UI framework (the `warpui_core` and `warpui` crates) is licensed under the [MIT license](LICENSE-MIT).

The rest of the code in this repository is licensed under the [AGPL v3](LICENSE-AGPL).

## Open source dependencies

Some of the open source projects that Warp builds on:

- [Tokio](https://github.com/tokio-rs/tokio)
- [NuShell](https://github.com/nushell/nushell)
- [Fig Completion Specs](https://github.com/withfig/autocomplete)
- [Alacritty](https://github.com/alacritty/alacritty)
- [Hyper HTTP library](https://github.com/hyperium/hyper)
- [FontKit](https://github.com/servo/font-kit)
- [Core-foundation](https://github.com/servo/core-foundation-rs)
- [Smol](https://github.com/smol-rs/smol)
