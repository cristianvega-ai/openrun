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

OpenRun is a native macOS terminal for work with coding agents.
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
- The codebase stays small. It holds no Windows or Linux code.
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

- Windows and Linux.
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
