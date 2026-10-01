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
  - `gh` runs only while something on screen shows the pull request. A tab you switch away from stops running `gh` about 30 seconds later, and a pane that a maximized pane covers does the same. A terminal whose prompt is hidden by a full-screen program (`vim`, `less`, `htop`) stops about 30 seconds later, and one whose prompt is hidden by a running command that is not full-screen stops about 3 minutes later (so a command that finishes within 3 minutes starts no extra `gh`), unless a CLI-agent footer with the chip is showing; it looks up GitHub again when the prompt returns. Selecting the tab again looks up GitHub at once. The exception is the vertical tabs panel: while it is open and its rows show pull request badges (expanded rows with "PR link" on, or summary rows), those tabs and panes keep polling. The compact rows show no badge. A window that is minimized or hidden behind others is not detected.
  - When you click them, the commit and push dialog runs `git push`, and its pull request button runs `gh pr create`.
  - A repository terminal with no pull request chip in its prompt and no open code-review panel runs neither, and neither does a tab in the background. Removing the chip from the prompt (Edit prompt again) turns the polling off. Local `git status` for the other prompt chips does not touch the network.

Command completions run only reviewed local generators. The bundled completion specs ship generators, shell commands the app runs while you type (autosuggestions) or press Tab. A generator must never execute shell syntax taken from the words you have typed, touch a network, or execute code the project controls, so only generators on a reviewed allow-list run (251 of the 474 bundled ones, and 21 more on macOS and Linux, see below): they read your repository, files and local daemons (git branches and tags, `package.json` scripts, process lists and the like). The other 223 are disabled (202 on macOS and Linux): generators that call a package registry, GitHub, a cloud CLI, a cluster or a remote host; generators whose tool can reach a network depending on the environment (a rustup proxy installing a toolchain, a remote `DOCKER_HOST`, an `npm` update check, a corepack shim); generators that run code a project or repository controls (`nx`, `lerna`, `Rscript`, and `git status`/`diff`/`ls-files` when the repository config sets `core.fsmonitor`); and generators that put the typed words into the command unquoted. So `npm install <name>`, `cargo add <name>`, `git add <Tab>`, `kubectl --context <Tab>` and `gh pr ...` complete from the static parts of the spec and local files only. The words you have typed reach a generator's command only through a token gate: a generator that takes tokens runs only if every word of the line is made of letters, digits and `. _ / : @ + , = -` (a word starting with `-` must look like a flag), so no shell reads any of it as syntax; the 16 generators that quote the word they use (`kubectl`, `oc` and `kubecolor` contexts, `docker build -f`, `apt list`, ...) also accept spaces and quotes in bash, zsh and fish, but not a backslash, and nothing but the strict form on PowerShell and cmd.exe. A line the gate refuses just gets no suggestions from that generator. Alias expansion for completion runs for `git` aliases only (`git co <Tab>`), behind the same gate; the `npm` and `yarn` script aliases are off. On macOS and Linux local sessions, where every command runs in the network sandbox described below, 21 generators whose tool looked local but reached a network or ran repository code in the environment alone are enabled because the sandbox and the environment table were shown, with the real tools against a loopback canary, to stop that: the `cargo` and `rustup` ones (a rustup proxy installing a pinned toolchain, so `cargo run --bin <Tab>` completes), the `docker` listing ones (a remote `DOCKER_HOST` or context, so `docker start <Tab>` completes), `npm prefix` (an update check) and git's `ls-files` and `diff --cached` (a repository's `core.fsmonitor` program). The `git status`/`diff`/`ls-files --modified` ones stay off because a repository's `clean` filter still runs, and the `yarn` ones because yarn runs the project's `yarn-path`. On Windows, which has no network sandbox, 97 generators run (58 that only read files or use PowerShell process and variable cmdlets, and the 39 local git ones; the other 377 are off). The git ones are one read of the local repository each, with no network and no `fetch`: branches and remotes (`git checkout <Tab>`, `git branch -d <Tab>`, `git push <Tab>`), tags, stashes, worktrees, revisions and commits, aliases and settings, tracked files (`ls-files`) and the staged files (`diff --cached --name-only`), plus the same `git` commands that `hub`, `gt`, `gh`, `lerna`, `pnpm`, `pre-commit`, `turbo`, `vsce` and `checkov` completions run. They run only in a session whose executor applies the offline environment table (a local PowerShell or cmd session, Git Bash/MSYS2 and WSL; not a shell the app reaches through its in-band executor) and only through the strict token gate. The table keeps git from lazy-fetching a missing object from a partial clone's promisor remote (`GIT_NO_LAZY_FETCH`, and `GIT_ALLOW_PROTOCOL=file` for git older than 2.44), from running a repository's `core.fsmonitor` program, and from running its `gpg.program` for `log.showSignature`. `git status`, `git diff` and `ls-files --modified` (so `git add <Tab>` offers files from the file system, not from git), `git-flow`, and anything that can fetch (`ls-remote`, `remote show`, `submodule update`) stay off on every platform. The allow-list is a review, not a proof: only `rustup`, `npm`, `corepack`, `git` and `docker` (from an independent review) were run against a loopback canary; `CHANGES.md` lists what was removed and why.

Every completion generator also runs with an offline environment: variables that stop the tools it starts from going online by themselves (rustup installing the toolchain a project pins, npm's update check, corepack downloading a package manager, git running a repository's `core.fsmonitor` program or fetching from a partial clone's remote, and others listed in `CHANGES.md`). This lowers the risk; it is one layer of a defence, not a guarantee that every allowed generator is offline.

On macOS and Linux every completion command also runs inside an operating-system network sandbox: a `sandbox-exec` profile on macOS and a seccomp filter on Linux deny IP networking (loopback included) to the command and everything it starts, while Unix sockets and files keep working. If the sandbox cannot be applied, the command does not run. Windows has no unprivileged sandbox, so completion generators that start another program stay off there. The sandbox stops tools that go online by themselves; it is not a boundary against hostile code, and a local daemon that makes network requests for its client (a container engine, an SSH control master) is not stopped by it. Details are in `SECURITY.md`.

Your shell and the programs you run in it, including SSH sessions and CLI agents, use the network as they normally would.

`script/offline_audit` checks the repository for reintroduced Warp hosts, network-capable code and banned dependencies, and CI runs it.

CI lints (clippy with `-D warnings`) on Linux, Windows and macOS, runs the unit tests, and runs the whole test suite in a network sandbox. A test that passes only on a retry fails the run. See [CONTRIBUTING.md](CONTRIBUTING.md#continuous-integration); `script/cross_clippy` reproduces the Windows and Linux lint from a Mac.

## Data stored on your computer

The app keeps some of what you do in a local SQLite database in its per-user state directory (the file ends in `.sqlite`, with a `-wal` file beside it while the app runs). Nothing in it is sent anywhere; it is a second copy of your terminal activity on disk, in the same way your shell's own history file (`~/.zsh_history`, `~/.bash_history`) is a copy.

- **Command history.** Every command you run in a session is added to a `commands` table with its working directory, shell, user name, host name, git branch, start and end time and exit code. The table keeps the newest 10,000 commands, and it feeds up-arrow history and history search in later sessions.
- **Block text and output for session restore.** For each pane the app saves the command text, the output (up to 5,000 lines per block, with its colors) and the prompt of up to the last 100 blocks, so that the next launch can restore the scrollback. This is the `blocks` table. The window, tab and pane layout is saved too (working directories, shell, split sizes); it holds no command text or output.
- **Not covered by redaction.** Secret redaction (Settings > Privacy) only changes what is drawn on screen. The original text is what is saved, so a token that was printed in a command or in its output is in the database as typed.
- **Commands you start with a space.** A command that starts with a space is not saved, in the database or in up-arrow history, when your shell ignores it: zsh with `histignorespace`, bash with `HISTCONTROL` containing `ignorespace` or `ignoreboth`, and fish always (fish does not record such commands). The block of such a command is not saved for session restore either. With any other zsh or bash setting, such a command is saved like any other, and so are PowerShell commands: PowerShell has no leading-space default, so the app applies no such rule to it.

You control this in Settings > Privacy:

- **Save command history and block output** (default on; settings file key `privacy.save_command_history`). When it is off, nothing new is written to the `commands` or `blocks` tables, and what is already saved is not loaded at startup, so blocks from your previous session are not restored (your windows, tabs and panes still are). Up-arrow history keeps working in the running app, from your shell's history file and the commands you run in that session, and the commands of that session are forgotten when you quit. Turning it off does not delete anything already saved; the app offers to do that at once.
- **Delete saved history.** Asks for confirmation, then deletes every row of the `commands` and `blocks` tables, overwrites the freed space and compacts the database (`VACUUM`, then truncates the write-ahead log). Your layout, projects and other settings stay. It cannot reach copies outside the database file: your shell's own history file, backups, snapshots, and data a solid-state drive or file system journal may still hold. A command or output already shown in an open window stays on screen until you close it.

The secret scan of this repository's Git history is a different guarantee: it concerns the source tree, not what the app stores on your machine, and nothing here promises that your saved history is free of secrets.

To remove everything the app saved, quit it and delete the state directory's `.sqlite` and `.sqlite-wal` files. Setting `privacy.save_command_history = false` in the settings file before the first launch keeps the database free of commands from the start.

## Building and running

```bash
./script/bootstrap   # platform-specific setup
./script/run         # build and run
./script/presubmit   # fmt, clippy, and tests
```

Building fetches Rust crates and a few git dependencies (forks of upstream Warp libraries hosted on GitHub). That happens at build time only; the built app does not contact them.

The app builds as `warp-oss`. See [AGENTS.md](AGENTS.md) for the engineering guide: architecture, coding style, testing and platform notes.

Bundle identifiers, data directories, the `warposs://` URL scheme and install paths (including the Linux package directory and the Windows registry base) are unchanged from upstream Warp OSS, so existing installs and stored preferences keep working. [CHANGES.md](CHANGES.md) lists them.

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
