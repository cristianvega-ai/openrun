# Fixtures of Claude Code

These files come from real runs of Claude Code 2.1.322 in November 2026, with the model `claude-haiku-5-5`.
The prototype for agent threads recorded them, and they were cut down to what the tests need.
`FakeAgent` plays the turns back in place of `claude`.

## The files

| File | What it shows |
|---|---|
| `plain-turn.jsonl` | A plain answer: the start of the process, the user message that the agent took, text that streams, the usage reading, the list of commands, and the end of the turn. |
| `command-turn.jsonl` | A command that the permission hook allowed, with thinking before it. Most pieces of the input and the text were removed. |
| `denied-turn.jsonl` | A command that the permission hook denied with a message, and the answer of the agent. |
| `edit-turn.jsonl` | A Read call and an Edit call that changed `notes.txt`, with the patch of the file. |
| `sub-agent-turn.jsonl` | A task of a sub-agent: the Agent tool call, the start and end of the task, and the message inside it. |
| `image-turn.jsonl` | A user message with a red square of 16 by 16 pixels, and the answer "Red". |
| `stopped-turn.jsonl` | SIGINT during a command: the call is rejected, and the turn ends as stopped. |
| `authentication-failure.jsonl` | A login that reached its time limit: the error text and the failed turn. |
| `history.jsonl` | Lines of the history file of a conversation: a user message, the agent's tool call and its result, a side chain, lines of other kinds, and a kind that does not exist. |
| `permission-request.json` | What Claude Code gives the `PermissionRequest` hook on its standard input. |

The turns of one file follow each other in the order in which the agent wrote them.
Each turn ends with a `result` line and the `command_lifecycle` line after it.

## What was replaced

The repository is public, so nothing that describes the owner or the owner's Mac stays in these files.

- Every working folder is `/work/project`, and every configuration folder is `/config/claude`. Other temporary paths are `/tmp/agent/output`.
- Every conversation, message, request, task and line identifier is a made-up one of the same form, the same in each place where it occurs.
- The account and organization identifiers in the history are made up.
- Each thinking signature is `c2lnbmF0dXJl`.
- The lists of the `system/init` line hold two or three generic entries: the tools, the MCP servers, the slash commands, the agents, the skills, the plugins and the memory paths. The list of commands of `system/commands_changed` holds two.
- The time when the login ends, the reason of the organization's overage setting, and the path of the messaging socket were removed or replaced.
- In the history, the content of an attachment and of the system prompt was replaced by one short sentence. The branch is `main`.
- Lines that held the user name in pieces of a path, such as the input of a Read call as it streamed, were left out.

`FixturePrivacyTests` scans this folder. It fails when a file holds a home folder path, an e-mail address, the user's name, or one of the words that were removed. The test keeps those words only as hashes, so the test itself does not name them.
