---
title: OpenRun
date: 2026-10-11
---

# OpenRun

This document says what OpenRun is, who it is for, and what it is not.
During the design, it is the only place that holds OpenRun's decisions.
The owner makes each decision. The assistant asks the questions and records the answers.

## Phases

| Phase | Topic | Status |
|---|---|---|
| 1 | What OpenRun is: vision, users, rules, scope, and license | Done |
| 2 | Shape: the libghostty layer, the core, the clients, and the session process | Done |
| 3 | Agents: how OpenRun runs, watches, and coordinates agents | Done for version 1. Questions 7 to 9 wait for version 2. |
| 4 | Data: projects, memory, history, settings, and what leaves the Mac | Done for version 1. Memory and the library wait for version 2. |

## Vision

OpenRun is a native terminal for work with coding agents, on macOS and Linux. The Mac app comes first.
Version 1 is the terminal itself: built on libghostty, with a polished interface.
Version 2 brings the feature set of Claude Code Projects to the user's own terminal, with the agents and accounts the user chooses.
In Claude Code Projects, a coordinator splits a goal into threads that run in parallel, and then assembles the results.
OpenRun looks like a polished Mac app.
How OpenRun coordinates the threads remains open. OpenRun can include its own orchestrator.

## Users

Stage 1 serves the owner.
OpenRun serves people who work in a terminal and run coding agents.
Each user chooses which agents to use.
Stage 1 lasts until version 1 works for the owner's daily use.
After that, OpenRun ships free and open source to any Mac developer who runs coding agents, as a signed download.

## Principles

- The owner understands the codebase from the start.
- The codebase stays small. It holds no Windows code. Linux code stays in the platform parts of the shared core and in the Linux app.
- OpenRun has its own user experience. It looks like a polished Mac app.
- OpenRun is simple and straightforward to use. Bear is the model.
- Users choose their agents and models. OpenRun does not tie them to one provider.
- Users pay for AI through their own agents' subscriptions. OpenRun needs no API key and no subscription of its own.
- OpenRun uses the MIT license. It copies no cmux code.
- OpenRun runs only the unmodified agent programs. It never reads, stores, or forwards the user's agent credentials or tokens.

The suite goals also apply until a phase changes them:

- The app runs fast.
- The app uses native Apple tools where possible.
- Local use is the primary product value. Full local use needs no account.
- A headless core holds the product. Every interface is a client of the core.
- Agents and language models can use the product on day 1.
- Names use full words.

## Out of scope

- Windows.
- iOS in version 1. An iOS companion comes in a later version.
- A fork of Warp.

## Features

| Feature | Version | Status |
|---|---|---|
| Vertical tabs | 1 | Accepted. They are the sessions list in the second pane. |
| Notifications when an agent needs the user | 1 | Accepted. Alerts show in the sessions list. The notification ring design remains open. |
| In-app browser | 1 | Accepted. It opens as a split in the third pane. |
| Split panes | 1 | Accepted |
| Command-line tool and socket interface | 1 | Accepted |
| Sessions that survive a restart | 1, if possible | Wanted. The session process keeps them alive when the app quits or updates. After the Mac restarts, OpenRun rebuilds the layout and resumes each agent's conversation. |
| Each session shows its folder and git branch | 1 | Accepted |
| Usage left on each account, with reset times | 1 | Accepted |
| Three-pane window, as in Bear | 1 | Accepted. The panes hold projects, the sessions in a project, and one session. |
| Themes that color the whole window as one, as in Bear | 1 | Accepted |
| Claude Code Projects features: coordinator, threads, shared memory, library, and routines | 2 | Moved to version 2. Questions 7 to 9 remain open. |
| iOS companion | Later | Accepted for a later version |

## Decision log

Each row holds the date, the decision, and the reason.

| Date | Decision | Reason |
|---|---|---|
| 2026-10-11 | OpenRun is a new terminal built on libghostty, with the approach of cmux. It replaces the plan to fork Warp. | The Warp fork was too large and had license problems. It carried Windows and Linux work and a different user experience. The owner wants to understand the codebase from the start. |
| 2026-10-11 | OpenRun supports only macOS. | The suite supports only macOS. |
| 2026-10-11 | OpenRun's documents live in `documentation/`. | Full words match the owner's naming goal. The documentation standard still names `docs/`. |
| 2026-10-11 | One living product document holds every decision during the design. | Earlier rounds wrote each decision in up to eight places. |
| 2026-10-11 | The rules of the old OpenRun no longer apply: no accounts, no built-in agent, no telemetry, and no server calls. | OpenRun takes a new approach. It stays a terminal app where users choose their agents. |
| 2026-10-11 | OpenRun brings the Claude Code Projects feature set to the user's own terminal, with any model. | The owner has not seen this product yet. |
| 2026-10-11 | OpenRun looks like a polished web app. | This is the owner's user experience goal. |
| 2026-10-11 | Version 1 has vertical tabs, notifications, an in-app browser, split panes, a command-line tool, and a socket interface. | The owner chose these from the cmux feature set. |
| 2026-10-11 | The iOS companion comes in a later version. | Version 1 supports only macOS. |
| 2026-10-11 | The license choice waits. Until then, cmux is a source of ideas only, and OpenRun copies no cmux code. | The owner chooses the license later. cmux code brings the GPL with it. |
| 2026-10-12 | For each thread, the user chooses an agent and one of their accounts for it. The model comes from that agent. OpenRun has no agent of its own. | The owner controls AI spend through subscriptions and wants no new subscription and no API key. The owner picks a session by its model and by the usage left on each account. |
| 2026-10-12 | OpenRun aims to keep the work in its sessions across a restart. | Today a terminal restart loses the work, and starting each session again takes time. |
| 2026-10-12 | OpenRun looks like a polished Mac app. This replaces the goal of a polished web app. | OpenRun is Mac first. The owner corrected the earlier goal. |
| 2026-10-12 | Bear is the model for OpenRun's look and ease of use: simple to use, themes that color the whole window as one, and a three-pane window. | The owner loves these parts of Bear. Ghostty themes only the terminal. |
| 2026-10-12 | Version 1 is the terminal: libghostty with a polished interface and the version 1 features. The Claude Code Projects features move to version 2. | The owner wants the core and the visuals built first. Coordinating threads raises open problems, such as how a waiting coordinator learns that a thread needs it. |
| 2026-10-15 | The three panes hold projects, then the sessions in a project, then one session. The sessions list is the vertical tabs. The third pane splits, and the browser opens as one of its splits. | It follows Bear's order from tags, to notes, to one note. In version 2, the sessions list can become a project's threads. |
| 2026-10-15 | OpenRun uses the MIT license. It copies no cmux code. This settles the license choice that waited on 2026-10-11. | MIT matches Ghostty. The owner writes the codebase and understands it from the start, so OpenRun does not need cmux code. |
| 2026-10-15 | The owner is the only user until version 1 works for daily use. Then OpenRun ships free and open source to Mac developers who run coding agents. | Until then, the design serves only the owner. This closes phase 1. |
| 2026-10-15 | A background session process owns every shell and agent. The app, the command-line tool, and the socket are its clients. Closing or quitting the app leaves the sessions running, and reopening it reattaches them. | It follows the suite rule of a headless core. It keeps agents working when the window closes or the app updates. The cost is two processes and a protocol between them. A Mac restart still ends the sessions. |
| 2026-10-15 | The session process keeps each screen with libghostty-vt. The app draws the screens with its own Metal and CoreText renderer, and encodes input with libghostty-vt. If Ghostty's announced Swift Metal renderer ships and fits, OpenRun switches to it. OpenRun does not embed the full Ghostty core. | Ghostty's maintainers point embedders to libghostty-vt. The full core's API is not stable and serves mainly Ghostty's own app. libghostty-vt draws nothing, so it fits the headless session process. The owner understands every line of the drawing code. |
| 2026-10-15 | After the Mac restarts, OpenRun rebuilds each session: its project, splits, folder, and saved screen text. It runs each agent's resume command with the saved conversation, such as `claude --resume <id>` or `codex resume <id>`. A plain shell reopens in the same folder with its old output above the prompt. | Today a restart loses the work, and starting each session again takes time. The agents already save their conversations. |
| 2026-10-15 | The interface uses only AppKit, with no SwiftUI. The terminal views draw with Metal, and the in-app browser is a WKWebView. | The owner wants one toolkit to understand and the most control over the window, the panes, and keyboard focus. The terminal views need AppKit either way. |
| 2026-10-15 | OpenRun never creates git worktrees, in version 1 or version 2. The user or the agent decides. OpenRun shows the folder and branch of each session. | OpenRun stays out of git. Some agents already make their own worktrees. |
| 2026-10-15 | The app, the session process, and the command-line tool are all Swift, in one package that shares the protocol types. Swift calls libghostty-vt through its C API. | One language to understand. It follows the suite goal of native Apple tools. |
| 2026-10-15 | The app registers the session process as a launch agent with SMAppService. launchd starts it when the app or the command-line tool first connects to its socket, and restarts it after a crash. It exits when the last session closes. It does not start at login, so agents resume after a Mac restart only when the user opens OpenRun or uses the command-line tool. | Agents use the user's subscriptions only after the user opens OpenRun. launchd handles start and crash recovery, so OpenRun needs no code for them. |
| 2026-10-15 | When the app attaches to a session, the session process sends a libghostty-vt snapshot of the screen and scrollback, then forwards the shell's raw output. The app restores the snapshot into its own libghostty-vt and draws from it. Input and commands go back as messages on the Unix socket that the command-line tool also uses. The session process saves the same snapshots to disk for a Mac restart. | The protocol stays small, and OpenRun designs no screen protocol of its own. Parsing each screen twice costs little. |
| 2026-10-15 | OpenRun supports macOS 26 and later. It uses newer APIs behind version checks. | macOS 26 and 27 share the Liquid Glass design, so OpenRun builds one look. It covers most developers' Macs at the public release. This closes phase 2. |
| 2026-10-15 | The session process catches the alert sequences that agents print (OSC 9, OSC 99, OSC 777, and the bell). For agents with hooks, a hook calls `openrun notify` with the reason. Each session's environment names the session and the socket, and the hook does nothing outside OpenRun. OpenRun offers to add the hooks and never edits an agent's settings without asking. | The alert sequences work with any agent and need no setup. Hooks add the reason, such as a permission request or a finished turn. |
| 2026-10-15 | At session start, the hooks tell the session process the conversation ID and the agent's account, through its `CLAUDE_CONFIG_DIR` or `CODEX_HOME`. A resume runs under the same account. A session with no hook comes back as a shell in its folder, and OpenRun does not guess its conversation. | Hooks work whether the user or OpenRun started the agent. The user runs several accounts, and each account keeps its own conversations. A wrong guess would resume the wrong conversation. |
| 2026-10-15 | In version 1, agents act on OpenRun through the `openrun` command-line tool, with a short skill file that teaches its commands. OpenRun has no MCP server. Question 8 decides the Agent Client Protocol. | Any agent can run a command. A skill file costs less context than an MCP tool list, and OpenRun keeps one interface. The Agent Client Protocol matters only if version 2 draws a chat view. |
| 2026-10-15 | OpenRun adds no command rules. Each agent's own permissions and sandbox apply, and its permission prompts reach the user as alerts. The `openrun` tool lets an agent act freely on its own session. Typing into or reading another session asks the user first. | OpenRun does not become a security layer it must get right. The user runs several accounts, so one agent must not drive another without the user's approval. |
| 2026-10-15 | OpenRun runs only the unmodified `claude` and `codex` programs. The user signs in through each agent's own login. OpenRun never reads, stores, or forwards their credentials or tokens, and never uses the Agent SDK with a subscription login. It drives agents only through documented command-line options, hooks, and protocols. It may start them headless, such as with `claude -p` or `codex exec`. Usage figures come only from what the agents report. | Anthropic's terms allow a user to sign in to the unmodified Claude Code with their own subscription, and forbid apps that handle Claude credentials or tokens. OpenAI has stated no rule for apps that drive the official Codex. This closes phase 3 for version 1. |
| 2026-10-15 | In version 1, a project is a folder that the user adds, usually a repository. New sessions in a project start in its folder. The first pane lists the projects and one entry for sessions outside any project. | Agents already keep their conversations by folder. Version 2 can add a goal, instructions, and more repositories to a project. |
| 2026-10-15 | OpenRun keeps its data in `~/Library/Application Support/OpenRun` as readable JSON: projects, layout, session records, and settings. Screen snapshots are encrypted with a key in the Keychain that only OpenRun can read. They have a size limit, and OpenRun deletes them when their session closes. The data is ready to sync later: each record has a stable ID, and data that belongs to one Mac, such as sessions, snapshots, and folder paths, is kept apart from data that can sync. | Every agent runs as the user and can read the user's files. Without encryption, an agent could read another session's output from disk, around the rule that asks the user first. The owner expects synced data later. |
| 2026-10-15 | When OpenRun syncs, it uses iCloud through CloudKit. Shared data syncs: projects without their folder paths, settings, and themes, and later memory, the library, and routines. Sessions, screen snapshots, and folder paths stay on their Mac. Sensitive fields use CloudKit's encrypted values. | CloudKit needs no OpenRun account and no server, so full local use still needs no account. It is Apple's own tool, and the iOS companion can read the same data. |
| 2026-10-15 | Settings live in a native AppKit settings window. OpenRun stores them with its other data and syncs them through CloudKit. Agents and scripts read and change them with `openrun settings get` and `openrun settings set`. There is no config file. | Bear is the model for simple use. Agents can still change settings from day 1. OpenRun parses no file and keeps no file in step. |
| 2026-10-15 | Apart from iCloud sync, OpenRun sends only update checks. Sparkle checks the GitHub release feed, and the user can turn that off. OpenRun has no telemetry and no crash-reporting service. | Local use is the primary product value. Crash reports stay in macOS's own reports, which users can attach to an issue. |
| 2026-10-15 | Version 1 shows the 5-hour and weekly usage left on each account, with reset times. Claude Code reports it through a status line command that OpenRun offers to add, which still shows the user's own status line. For Codex, OpenRun reads it from Codex's app-server. OpenRun shows no cost figures. | The owner picks an account for a session by the usage left on it. Cost estimates use list prices and mean little on a subscription. This closes phase 4 for version 1. |
| 2026-10-15 | All code lives in one Swift package, built and tested with `swift build` and `swift test`. libghostty-vt is a binary target. A short shell script assembles and signs the app bundle. OpenRun has no Xcode project file. | The whole build is `Package.swift` and one script that the owner can read. |
| 2026-10-15 | Version 1 is built in six milestones: the core, the terminal view, the window, agents, restart, and finish. The owner reviews each milestone before the next one starts. | The owner understands the codebase from the start. |
| 2026-10-15 | The code is organized by feature: each feature is its own Swift module. Names use full words, with no acronyms or abbreviations. `AGENTS.md` holds these code standards. | The owner wants to find each feature in the code by its name. The owner dislikes acronyms. |
| 2026-10-17 | `openrun kill` and the shutdown of the session process end every process in the program's terminal session, also processes that moved to another process group: SIGHUP to each process group (SIGCONT too for a stopped one), then SIGKILL after a second to every process still alive. A process that starts a session of its own escapes. A program that exits by itself leaves its background processes running. | A killed session should leave nothing behind, as a closed terminal window does for its jobs. A process that starts its own session has asked to outlive its terminal, as a daemon does. A program that ends by itself has finished its own work, and its background jobs may be meant to go on. |
| 2026-10-17 | With no relaying client attached, the session process answers the OSC 10 and OSC 11 color queries from the macOS appearance (black on white in light mode, white on black in dark mode), and `CSI 15 t` from the nominal cell size of 8 by 16 pixels. | Programs ask for the colors to choose a readable theme and for the pixel size to draw images. Without an answer they wait or guess. The appearance is the only color setting a session has. A window has no real size yet, so the nominal cell gives a stable answer. |
| 2026-10-19 | The socket protocol grows only by addition inside version 1: a new optional field, or a new message that only a client that asks for it receives. The version number changes only when a change would confuse an older program. A change that cannot be made this way needs a new version, and the owner designs a version agreement then. | A client that does not ask never meets a message it does not know. Older clients and older session processes keep working, and the app and the command-line tool can change at their own pace. |
| 2026-10-19 | A client that attaches while `openrun kill` waits for a program that ignores SIGHUP gets `attached`, the last screen, and then the exit status. | The session is still there until the program ends. The client sees the last screen and how the program ended, as it would for an attach just before the kill. A refusal would show a session that is about to disappear as one that never existed. |
| 2026-10-19 | `AGENTS.md` gets a Commits section: at most 100 changed lines in at most 10 files, one logical slice that builds and passes `swift test`, a straight line of commits on `main` with no merge commits, a subject of at most 50 characters, a body in ASD-STE100, and a push to `origin` only after the owner approves it. Milestone 1, which is to land on `main`, is cut again into small commits. | There are no pull requests, so each commit is the unit of review. The owner can read a small commit alone. The first milestone was one large change that is hard to review. |
| 2026-10-19 | OpenRun supports macOS and Linux, starting with Ubuntu. One shared core serves two native apps. The core is the Swift modules that use no AppKit: the terminal emulation, the pseudo terminal, the protocol, the session process, and the command-line tool. The Mac app uses AppKit. The Linux app uses the native tools of the Linux desktop. The Mac app comes first. The Linux app starts after the features of the Mac app settle. This replaces the decision of 2026-10-11 that OpenRun supports only macOS. | The owner wants OpenRun on Ubuntu too. The core holds most of the logic and needs few platform calls. A native app on each system keeps the polished look that one shared interface toolkit would lose. Ghostty has the same shape: one shared core and a native app for each system. |
| 2026-10-19 | The core builds and passes its tests on macOS and on Linux before milestone 2 starts. The owner's Linux machine is the Linux build and test machine. Each feature asks for its platform services, such as the process list and the peer check, through a small interface of its own, with one version for each system. | Milestone 2 adds much shared code. Code that is checked on Linux from the start costs less than a port later. An interface in each feature keeps the platform code next to the feature that needs it, with no grab-bag module. |
| 2026-10-24 | The domain of OpenRun is openrun.cristianvega.ai. Names in reverse domain form, such as a settings domain or a bundle identifier, start with ai.cristianvega.openrun. | The owner chose a domain of their own for the project. |
| 2026-10-24 | Version 1 is built on macOS from start to finish, milestones 2 to 6, with no Linux step between them. The core builds and passes its tests on Linux later, before the Linux app starts. Each feature still asks for its platform services through a small interface of its own: the macOS version comes with the feature, and the Linux version comes with the port. This replaces the decision of 2026-10-19 that the core passes its tests on Linux before milestone 2 starts. | The owner wants a full working Mac version first. A Linux step before milestone 2 would hold up that work. The interfaces keep the later port small. |
| 2026-10-24 | When clients with different window sizes attach to one session, the size of the client that attached or resized last applies. The other clients that asked hear of the new size. | tmux uses the same rule by default. The terminal view of milestone 2 and `openrun attach` will often attach to one session together, and the window that the user changed last is the one in use. Milestone 1 already works this way. |
| 2026-10-24 | A program in a session gets the environment of the client that created the session, as a program in any terminal does. The session process uses that environment only to start the program. It never logs it, never writes it to disk, never shows it to another client, and never sends it off the Mac. Saved sessions leave it out, apart from the account settings that a resume needs, such as `CLAUDE_CONFIG_DIR` and `CODEX_HOME`. This makes the credentials decision of 2026-10-15 exact for the environment. | Agents need their own variables, and a terminal that drops the environment breaks them. The values are the user's own, and they reach only the program that the user started. |
| 2026-10-24 | Version 1 has no limit on the number of sessions or on their total memory for now. Milestone 4 sets one. | Only programs of the same user can connect, and each client already has limits. A program of the same user can use up memory in other ways. Agents can start sessions by themselves, so milestone 4 needs a limit. |
| 2026-10-24 | Until milestone 5, the session process and its clients come from the same build. A snapshot is restored only by the build that made it. Milestone 5 decides what happens when the app updates while an older session process runs. The protocol rule of 2026-10-19 still holds: the socket protocol grows only by addition, and only the snapshot needs the same build. | Milestone 5 adds the restart and the update path, and it needs that answer. Before it, the owner builds both programs together. |
| 2026-10-25 | The TLA+ models of OpenRun are in the top-level folder `specifications/`. Each model is one `.tla` file, with its TLC configuration files (`.cfg`) beside it. The models are the one exception to the rule to write Swift only. The app, `swift build`, and `swift test` do not use them. A commit that adds one model with its configuration files may change more than 100 lines when it changes no other file. It still has at most 10 files. Every other commit keeps the limit of 100 lines in 10 files, and so does a later change to a model. Each model keeps its controls. A control is a configuration that removes one protection of the code. It must fail with a named property, because a model that only passes proves nothing. `scripts/check-specifications.sh` runs the configurations and fails when an outcome differs from the expected one. It downloads the TLA+ tools at a pinned version and checks their SHA-256. The tools, the logs, and the TLC state stay out of git. The script needs Java (it looks in `JAVA_HOME`, then Homebrew `openjdk`, then the `PATH`), and only this check uses Java. When a change alters what a model describes, the same commit updates the model when the limits permit. Otherwise the next commit does. The description covers the attach sequence, size changes, the reply gate, shutdown, typed input and its withdrawal, and the local screen of `openrun attach`. Such a change runs the quick set of the script. A milestone review runs the full set with `--all`. | The TLA+ review of 2026-10-25 reproduced two defects with these models, and its controls show that the models find real defects. The attach sequence, the shutdown, and the input path change again in milestones 2, 4, and 5 of version 1, so the models must keep up with the code. |
| 2026-10-25 | The terminal view of the app in milestone 2 asks for size changes when it attaches (`receivesSizeChanges` is true). After it restores the snapshot, it sends a `resize` with its own window size when that size differs from the size of the snapshot. The window can change while the snapshot is on its way, and the session does not tell a client about a change that the client itself asked for. When a size change comes from the session, the view gives its local terminal that size. It does not answer with a `resize` of its own, so two clients cannot make each other change size again and again. This follows the size row of 2026-10-24: the client that attached or changed its size last sets the size. Milestone 2 decides how the view shows a grid that differs from its window. | The TLA+ model of the attach sequence found a client that changes size before its snapshot arrives and then keeps the old size. `openrun attach` already sends its window size after the restore (`AttachCommand.run`), and the app must do the same. |

## Reference: libghostty and cmux

The assistant checked these facts on 2026-10-11.

- Ghostty uses the MIT license. A product that embeds it can choose its own license.
- The public library is libghostty-vt. It parses terminal sequences and keeps the terminal state.
- libghostty-vt draws nothing. The app supplies the renderer.
- Ghostty proves the behavior of libghostty-vt, but its function signatures still change.
- cmux embeds the full Ghostty core, with Ghostty's own graphics renderer.
- cmux builds that core from its own Ghostty fork. The fork was 781 commits ahead of Ghostty and 1,482 behind.
- cmux uses the GPL-3.0-or-later license for its Mac app and its command-line tool.
- Its server parts use the Business Source License 1.1.
- Code copied from cmux brings the GPL with it.
- cmux is mostly Swift. It offers a command-line tool and a Unix socket interface for automation.

The assistant checked these facts on 2026-10-15.

- libghostty-vt builds as an XCFramework that a Swift package can use. Ghostty's `example/swift-vt-xcframework` shows how.
- libghostty-vt has a render-state API. It gives rows, cells, styles, colors, the cursor, the selection, and dirty tracking to an app's renderer.
- libghostty-vt encodes keys, mouse input, focus, and paste for the program in the terminal.
- libghostty-vt can encode a terminal's full state, with its scrollback, as a snapshot and restore it in another terminal.
- In March 2026, a Ghostty maintainer said libghostty-vt supersedes the embedded API for terminal emulation.
- The embedded API is the full Ghostty core that Ghostty's macOS app uses. It is not stable for other apps. An app can build it from a pinned Ghostty commit. cmux keeps a fork to carry its own patches.
- In July 2026, Mitchell Hashimoto announced a pure Swift Metal renderer and Swift bindings for libghostty-vt, for macOS and iOS. It was not released on 2026-10-15.

Sources: the [Ghostty README](https://github.com/ghostty-org/ghostty), Ghostty's `example` folder, [Ghostty discussion 11722](https://github.com/ghostty-org/ghostty/discussions/11722), [the Swift renderer announcement](https://x.com/mitchellh/status/2072724957902381319), [Ghostling](https://github.com/ghostty-org/ghostling), the [cmux repository](https://github.com/manaflow-ai/cmux) and its `LICENSE` and `.gitmodules` files, and [cmux is built on Ghostty](https://cmux.com/built-on-ghostty.md).

## Reference: Claude Code Projects

The owner supplied the announcement and screenshots on 2026-10-11. The announcement is dated 2026-09-17.

- A project has a goal, repositories or other context, instructions, connectors, plugins, and a model.
- A coordinator chat scopes each request, starts threads, routes messages, reviews outputs, and assembles results.
- Each thread is a full Claude Code session on its own branch and its own copy of the repository.
- When threads change the same code, the overlap resolves as a merge conflict.
- A thread can split its work further with subagents, loops, and workflows.
- Threads add to a shared project memory and read from it.
- A library collects the files that the user adds and the artifacts that threads produce. It can link local folders.
- Routines put recurring work on a schedule.
- The coordinator and each thread have their own model and effort setting.
- The user can steer from a phone, and the work continues after the user leaves.
- Threads run in the cloud. The announcement says local threads come soon.

The screens have three areas:

- A sidebar holds navigation, pinned projects, and earlier sessions.
- The center holds the coordinator chat. Each thread appears there as a card with its status and files.
- A side panel holds the Threads, Library, and Routines views. Threads group into "Waiting on you" and "Resolved".

A thread opens in the side panel as its own chat, with its own model setting.
A file opens in a preview with the thread beside it.

## Reference: agent protocols

The Agent Client Protocol connects an app to a coding agent through JSON-RPC over standard input and output.
Zed created it in August 2025.
Zed runs Gemini CLI, Claude Code, and Codex through it. Claude Code and Codex need adapters.
The assistant checked these facts on 2026-10-15 with the installed agents.

- Claude Code 2.1.300 resumes a conversation with `claude --resume <id>`. It can start one with a chosen ID through `--session-id <uuid>`. Its hooks report the session ID.
- Claude Code 2.1.300 can also run sessions in the background with `--bg`, and reattach with `claude attach`.
- Codex 0.162.1 resumes a conversation with `codex resume <id or name>`, or the latest with `--last`. It has no flag that chooses the ID at start.
- Codex 0.162.1 has hooks as a stable feature. It also has a shared local app-server daemon for its sessions.
- Claude Code sends a status line command JSON that includes `rate_limits.five_hour` and `rate_limits.seven_day`, each with `used_percentage` and `resets_at`. Its `cost.total_cost_usd` is an estimate at list price.
- Codex's app-server, marked experimental, answers `account/rateLimits/read` and sends `account/rateLimits/updated`.

Sources: [Claude Code status line](https://code.claude.com/docs/en/statusline), `codex app-server generate-json-schema`, [Zed external agents](https://zed.dev/docs/ai/external-agents) and [Codex is live in Zed](https://zed.dev/blog/codex-is-live-in-zed).

## Reference: subscription terms

The assistant checked these facts on 2026-10-15.

- Anthropic's Claude Code legal page says subscription sign-in supports ordinary use of Claude Code and Anthropic's own apps.
- Anthropic does not permit other apps to offer Claude sign-in, to route requests through Free, Pro, or Max credentials for their users, or to collect, store, or intermediate Claude credentials or session tokens.
- The same page says this does not prevent a user from signing in to the unmodified Claude Code program with their own subscription, even when another platform runs it.
- Products built on the Agent SDK must use an API key or a cloud provider.
- Plan limits assume ordinary, individual use of Claude Code and the Agent SDK.
- A product may say in plain text that it runs Claude Code. It may not use the Claude Code or Anthropic names or logos in its own name or logo.
- Reports say Anthropic began blocking third-party tools that used subscription sign-in in January 2026, and stopped covering them with subscriptions in April 2026.
- OpenAI lets some third-party apps use a ChatGPT plan through "Sign in with ChatGPT". OpenAI has stated no rule for an app that runs the official Codex program with the user's own sign-in.

Sources: [Claude Code legal and compliance](https://code.claude.com/docs/en/legal-and-compliance), [The Register on the third-party tool ban](https://www.theregister.com/software/2026/02/20/anthropic-clarifies-ban-on-third-party-tool-access-to-claude/5014546), [Using Codex with your ChatGPT plan](https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan), and [Codex discussion 48837](https://github.com/openai/codex/discussions/48837).

## Open questions

### Version 2

**Question 7: Who coordinates the threads?**

1. An agent that the user chooses. It uses OpenRun's command-line tool to start threads and send them work.
2. OpenRun's own orchestrator, with a model that the user chooses.
3. The user. OpenRun shows every thread and its status in one place.

The owner leans to option 1: the coordinator is the main agent session, such as `claude`, with instructions for the role.

**Question 8: What does a thread look like?**

1. A terminal pane that shows the agent's own screen, as in cmux.
2. A chat view that OpenRun draws from the agent's structured output. The terminal stays one action away.
3. Both: the chat view by default, and the terminal on request.

The answer also decides whether OpenRun uses the Agent Client Protocol.

**Question 9: Which Claude Code Projects features does version 2 need first?**
The candidates are the coordinator, parallel threads, shared memory, the library, routines, and work that continues after the user leaves.

### Linux app

These wait until the Linux app starts:

- The toolkit and the language of the Linux app, such as GTK 4 with Swift, or GTK 4 with another language.
- How the Linux app draws the terminal, such as OpenGL or Vulkan with FreeType and HarfBuzz.
- How the session process starts on Linux, such as a systemd user service in place of launchd.
- Where the key for the screen snapshots lives on Linux, such as the Secret Service in place of the Keychain.
- Sync on Linux, where there is no iCloud.
- Updates and packages, such as deb, Flatpak, or Snap, in place of Sparkle.
- Which Ubuntu versions OpenRun supports.
- How the session process answers the OSC 10 and OSC 11 color queries on Linux, where it cannot read the macOS appearance.

### Later versions

- Version 2: Where do memory and the library live?
- Later version: How does the iOS companion see and steer live sessions? CloudKit syncs data, but it does not carry a live terminal.

## Glossary

- OpenRun: the terminal product in this repository.
- The suite: OpenWrite, OpenSay, OpenAct, and OpenRun.
- Ghostty: the open source terminal app that OpenRun builds on.
- libghostty: the libraries taken from Ghostty's core for use in other apps.
- libghostty-vt: the public libghostty library for terminal parsing and terminal state.
- cmux: a native macOS terminal built on Ghostty. It is OpenRun's main reference.
- Bear: a Mac notes app. It is the model for OpenRun's look and ease of use.
- Claude Code Projects: Anthropic's project feature with a coordinator and threads. It is OpenRun's feature reference.
- Agent: a coding agent program, such as Claude Code or Codex.
- Account: a login to an agent's subscription, such as a Claude Max plan or a ChatGPT plan.
- Project: a folder that the user adds, usually a repository. Its sessions start in that folder. The first pane lists the projects.
- Session: one terminal and its splits. The second pane lists the sessions in a project.
- Session process: the background process that owns every session. The app, the command-line tool, and the socket are its clients.
- Thread: one unit of agent work inside a project.
- Coordinator: the part that splits a goal into threads and assembles the results.
