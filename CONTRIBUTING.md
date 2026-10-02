# Contributing

Thanks for helping improve this fork of Warp, an offline terminal. This guide explains how to report issues, propose changes and get your work reviewed.

The fork removes every feature that talks to a server: accounts, built-in AI and agents, Warp Drive, telemetry, crash reporting and autoupdate. [CHANGES.md](CHANGES.md) records what was removed and why. A contribution must not bring any of that back; see [Staying offline](#staying-offline).

## TL;DR

- Search the existing issues, then file one with steps to reproduce.
- For anything larger than a bug fix, open an issue and agree on the approach before writing code.
- Keep each PR focused on one logical change, linked to its issue.
- Add tests, run `./script/presubmit`, and include proof of manual testing.
- Report security problems privately, never in a public issue.

## Filing a Good Issue

Search the existing issues before filing to avoid duplicates, and use the issue templates when filing.

### Bug reports

A good bug report includes:

- A clear title and a one-paragraph summary of the problem.
- Steps to reproduce (with a minimal example where possible).
- Expected vs. actual behavior.
- The version and OS (see `Settings → About`).
- Logs, screenshots, or screen recordings when relevant.

### Feature requests

A good feature request describes the user-facing problem before any proposed implementation. Include:

- The user need or pain point, and who experiences it.
- The current behavior and why it falls short.
- A sketch of the desired behavior or workflow (a short example or mock is helpful but not required).
- Any relevant constraints (compatibility, related features, prior art, etc.).

Larger changes are agreed on the issue first. Discussion alone is not approval to start work, so wait for a maintainer to confirm the direction.

## Opening a Pull Request

1. Branch from the repository's default branch.
2. Implement the change and add tests (see [Testing](#testing)).
3. Run `./script/presubmit` and fix any failures before pushing.
4. Open a PR using the [pull request template](.github/pull_request_template.md) and link the issue it resolves.
5. Keep the PR focused on a single logical change, and update your branch with the default branch before it enters review.

If the PR removes or changes a feature, add a section to [CHANGES.md](CHANGES.md) using the template at the top of that file, plus a bullet in its Contents list. The section says what changed, why, and what users will notice.

**You must include proof of [manual testing](#manual-testing).** For small, isolated, visual changes, include **before and after screenshots**. For larger, broad or interactive changes, also include a **narrated screen recording**.

Maintainers review PRs. You do not need to request reviewers yourself. If a PR has been waiting for a while, add a comment on it asking for a review.

## Staying offline

The app must make no network calls of its own beyond the four that remain: opt-in language server downloads, links the user opens, the opt-in loopback `warpctrl` local control, and the user's own `git` remotes and GitHub through `gh`, run only while a pull request chip is showing in the selected tab (it is in no default layout; users add it; a full-screen program, a running command or a maximized sibling pane hides it, and `gh` stops after a grace period), while the code-review panel is open in the selected tab, while the vertical tabs panel shows pull request badges in its current row mode, or on an explicit user action (push, create a pull request). Never start `gh` or a remote `git` command (`fetch`, `pull`, `push`, `clone`, `ls-remote`) from a timer or a startup hook that has no visible UI behind it.

- Don't add code that contacts a server, a telemetry or crash-reporting service, or an update channel.
- Don't add dependencies on HTTP, WebSocket or telemetry crates. `deny.toml` bans most of them.
- Run `script/offline_audit` before pushing. CI also runs it, and a failure blocks the merge. It fails on Warp hosts, on network-capable code outside the allowed consumers, and on banned dependencies. Exceptions live in `script/offline_audit.allowlist`, one reasoned entry per line.

## Using a Coding Agent

You can use **any coding agent** to implement a contribution, for example Claude Code, Codex or Gemini CLI, or no agent at all. This repository ships agent-readable context (skills under [`.agents/skills/`](.agents/skills/) and [`AGENTS.md`](AGENTS.md)) that any harness supporting these formats can pick up.

You remain responsible for the change: read what the agent wrote, test it, and talk to the maintainers yourself rather than through an agent.

## Development Setup

See [README.md](README.md) and [AGENTS.md](AGENTS.md) for the full engineering guide. Quick start:

```bash
./script/bootstrap   # platform-specific setup
cargo run            # build and run
./script/presubmit   # fmt, clippy, and tests
```

## Testing

Tests are required for most code changes.

### Manual Testing

Manual testing is required for changes that can be manually tested, and almost all changes can be. You can run the app locally with `./script/run`; see [AGENTS.md](AGENTS.md) for more details on how to get set up.

### Automated Tests

- **Bug fixes** should include a regression test that would have caught the bug.
- **Algorithmic or non-trivial logic** needs unit tests.
- **User-facing flows** should have end-to-end coverage under [`crates/integration/`](crates/integration/) whenever the behavior can be exercised that way.

Run unit tests with `cargo nextest run`.

## Code Style

- `./script/format --check` and `cargo clippy --workspace --all-targets --tests -- -D warnings` must pass.
- Prefer imports over path qualifiers, inline format args (`println!("{x}")`), and exhaustive `match` over `_` wildcards.
- See [AGENTS.md](AGENTS.md) for the full style guide, including WarpUI patterns and terminal model locking rules.

## Continuous Integration

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every push to `main` and on every pull request, on hosted macOS runners only (OpenRun supports macOS only). A public repository has five macOS runners at a time, shared by everything the account runs, so the jobs are few and the tests are compiled once:

- **Formatting and static audit**: `./script/format --check`, the guard against test retries, then the static offline audit (hosts, network-capable code, banned crates, `cargo deny check bans licenses sources`) and its self-test. **Clippy (macOS)**: `cargo clippy --workspace --all-targets --tests -- -D warnings`.
- **Build tests**: compiles every test of the workspace once (`cargo nextest archive`) from the cached build of the last push to `main`, and uploads the archive. The jobs below run the tests from that archive with `script/ci_nextest`; none of them compiles.
- **Unit tests and idle session (network sandbox)**, **Integration tests 1-3 (network sandbox)**: every unit test, every integration test (the `crates/integration` suite starts the real app, with a logged-in GUI session on the runner; three jobs split it by test name) and a two-minute idle session run under `script/offline_sandbox_macos`: `sandbox-exec` refuses every address that is not on the machine, and the unified log is read for the refusals. Each job first proves with canaries that a refused access is seen on its runner, and each run writes a log that `script/offline_audit --net-log` checks. A refused access by the app or a tool it started, a missing or incomplete log, or a canary that goes unnoticed fails the job.
- **Security and shell tests**: the tests that cannot or should not run inside the network sandbox. The command-executor sandbox, the offline environment, the restored generators and the generator policy tests apply sandboxes of their own and use the real tools they check (git, npm, corepack, rustup, docker, fish, PowerShell 7; with `CI=true` a missing tool fails them instead of skipping them). A short selection of integration tests runs unsandboxed, so that the app's own per-command `sandbox-exec` wrapper is exercised, with zsh, the bash of macOS (3.2), Homebrew's bash and PowerShell 7.
- **CI result**: fails unless every job succeeded and `script/ci_check_coverage` finds that the jobs together ran every test of the build (each test in a JUnit report), that every test but the sandbox's own ran inside the network sandbox, and that the idle session ran.
- **No retries.** A test that fails once and passes on a retry is flaky, which is not a pass: nextest retries are off in CI, so it fails the job. Fix the test, or file an issue and move it to a non-blocking step with the reason written next to it.

To run a command the way the sandboxed jobs do: `script/offline_sandbox_macos net.log COMMAND...`, then `script/offline_audit --net-log net.log`. To run the tests of a CI archive on a Mac, extract it where it was built (see `script/ci_nextest`); the tests read their sources by the absolute path of the build.

## Commit and Branch Conventions

- Branch names should be prefixed with your handle (e.g. `alice/fix-parser`).
- Commit messages should explain *what* and *why*, not just *what*.

## Code of Conduct

This project adopts the [Contributor Covenant](https://www.contributor-covenant.org/) (v2.1) as its code of conduct. All contributors and maintainers are expected to follow it in every project space. See [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) for the full text. Report violations to the fork's maintainers.

## Reporting Security Issues

See [`SECURITY.md`](SECURITY.md) for the disclosure policy. **Do not open public issues for security vulnerabilities.**

## Getting Help

Open an issue in this repository's tracker, or ask the fork's maintainers.
