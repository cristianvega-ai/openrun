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
  - While a terminal in a git repository shows the GitHub pull request chip in its prompt or CLI-agent footer, the app runs `gh pr view` and `gh repo view` when the chip appears, when the branch changes, after you run a `gh` or `gt` command in that terminal, and about once a minute.
  - While the code-review panel is open, it does the same for its pull request button.
  - When you click them, the commit and push dialog runs `git push`, and its pull request button runs `gh pr create`.
  - A repository terminal with no pull request chip in its prompt and no open code-review panel runs neither. Removing the chip from the prompt (Edit prompt again) turns the polling off. Local `git status` for the other prompt chips does not touch the network.

Your shell and the programs you run in it, including SSH sessions and CLI agents, use the network as they normally would.

`script/offline_audit` checks the repository for reintroduced Warp hosts, network-capable code and banned dependencies, and CI runs it.

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
