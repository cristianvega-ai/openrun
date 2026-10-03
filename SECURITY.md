# Security Policy

We take security seriously and appreciate the efforts of security researchers who help keep users safe.

## Reporting a Vulnerability

If you believe you've found a security vulnerability, please follow responsible disclosure practices and **do not** open a public issue or pull request, as this could expose the vulnerability before a fix is available.

Instead, report it privately to the maintainers of this fork, using the private security-advisory feature of the repository host or another private channel the maintainers have published for this repository.

We will acknowledge your report promptly and work with you to understand and resolve the issue as quickly as possible.

## Data stored locally

OpenRun does not send your data anywhere, but it does keep a local copy of your terminal activity. It is worth knowing when you handle secrets in a terminal.

- **What is stored.** A SQLite database in the app's per-user state directory (a `.sqlite` file and a `-wal` file) holds your command history (up to 10,000 commands, each with its working directory, shell, user, host, git branch, times and exit code) and, for session restore, the command text and output of up to the last 100 blocks per pane (output up to 5,000 lines per block). It also holds the window, tab and pane layout. The database is not encrypted: anyone who can read your files, or a backup of them, can read it.
- **It is a second copy.** Like the shell's own history file (`~/.zsh_history`, `~/.bash_history`), it records commands as you typed them. A secret typed in a command, or printed in output, is stored in plain text in both places. Secret redaction (Settings > Privacy) only hides matches on screen; it does not remove them from the saved history or the saved block output.
- **Commands with a leading space.** A command that starts with a space is left out of the database, and out of the saved block text and output, when the shell ignores such commands: zsh with `histignorespace`, bash with `HISTCONTROL` containing `ignorespace` or `ignoreboth`, and fish always (fish does not record them). This follows the shell's own setting; if your shell does not ignore leading spaces, such a command is saved. PowerShell commands are always saved, whatever their leading space: PowerShell has no such default, so the app applies no leading-space rule to it. A command that carries a secret on its command line is still visible to other users through the process list while it runs, and in your shell's history file if the shell does not ignore it.
- **Turning it off.** Settings > Privacy > Save command history and block output (`privacy.save_command_history`, default on). With it off, nothing new is written to the command history or block tables, and what was saved earlier is not loaded. Layout restore keeps working. Up-arrow history works while the app runs and is forgotten when it quits.
- **Deleting it.** Settings > Privacy > Delete saved history removes every saved command and every saved block's text and output, overwrites the freed pages and compacts the database. It does not reach copies the app does not own: your shell's history file, backups and snapshots of the state directory, and data left on a solid-state drive or in a file system journal. For those, use full-disk encryption and your backup tool's own deletion.
- **Not the same as the repository scan.** Scanning this repository's Git history for secrets is a release check on the source. It says nothing about what the app stores on your computer, and nothing here promises that saved history is free of secrets.
- **Logs.** The application log is not meant to hold the commands you run or their output. A debug message that listed every saved command at startup now logs only a count. If you find command text or output in a log file, please report it.

## How completion generators are kept offline

Completion specs ship generators: shell commands the app runs automatically while you type or press Tab. Three layers keep them from reaching a network:

1. **Allow-list.** Only generators reviewed as local-only run; the list is in `crates/warp_completer/src/signatures/legacy/generator_policy/`. `git status`, `git diff`, `ls-files --modified`, `git-flow` and anything that can fetch stay off. A short second list (`ALLOWED_WHEN_ISOLATED`) holds generators whose tool reached a network or ran repository code in the environment alone (rustup proxies, the docker CLI, `npm prefix`, git's `ls-files` and `diff --cached`); they run only in local sessions, where layers 2 and 3 below were shown with the real tools to stop it.
2. **Offline environment (all local executors).** Every generator subprocess gets variables that switch off the implicit network use of known tools (rustup installing a pinned toolchain, npm's update check, corepack downloads, git's `core.fsmonitor` program, its `gpg.program` for `log.showSignature`, lazy fetches from a partial clone's promisor remote and non-local transports, and others). Every row names, in `app/src/terminal/model/session/command_executor/offline_environment.rs`, the test that exercised it with the real tool (a loopback canary, a marker file, or the tool's own switch where the network call cannot be redirected); a variable no test exercises is not in the table. Sessions that run commands inside your own shell (sub-shells, SSH sessions without a control socket) get it for bash and zsh only; the SSH control-socket executor runs on the remote host and does not.
3. **OS network sandbox.** The subprocess runs under a `sandbox-exec` profile that denies IP networking, loopback included, to it and its children. It fails closed. Unix sockets stay allowed.

What this does not do: it is not a boundary against hostile code (a local daemon reached over a Unix socket can still make network requests for its client; file access is unchanged), and it does not cover commands you type yourself. git older than 2.31 ignores the `GIT_CONFIG_COUNT` overrides, so every completion that runs `git` (the generators, the `git` alias expansion and the branch list for command corrections) requires git 2.31 or newer: each session runs `git --version` once through its own executor, and with an older git, no git, or output that is not a version, no git generator runs (fail closed). The macOS profile is a deny list for the delegation paths that were found by testing (DNS through `mDNSResponder`, background URL sessions through `nsurlsessiond`), not for every system service.

