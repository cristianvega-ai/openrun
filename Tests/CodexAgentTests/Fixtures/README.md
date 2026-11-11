# Fixtures of Codex

These files come from real runs of `codex app-server` 0.167.0.
The prototype for agent threads recorded them, and they were cut down to what the tests need.
`FakeCodex` plays them in place of the app-server.

## The form

Each line is one JSON object, one step of an exchange:

- `{"client": METHOD, "expect": {…}}`: OpenRun sends a request or a notification with this method. The members of `expect` must be in its parameters.
- `{"client": "answer", "expect": {…}}`: OpenRun answers a request of the app-server, and the members of `expect` must be in the result.
- `{"server": {…}}`: the app-server writes this line. `"id": "$request"` stands for the identifier of the last request of OpenRun.
- `{"special": …}`: a special case of the fake app-server.

The tests that read the output alone take the `server` lines in order.

## The files

| File | What it shows |
|---|---|
| `handshake.jsonl` | `initialize` with the experimental capability, the answer, `initialized`, and the notifications that come before any thread. |
| `thread-start.jsonl` | A new thread in a folder: the answer with the thread, `thread/started`, and the start of an MCP server. |
| `plain-turn.jsonl` | A plain answer: the user message, text that streams, the token usage, the usage of the account, and the end of the turn. |
| `command-accepted.jsonl` | A command that needs approval: the request of the app-server, the answer `accept`, the end of the command, and the answer of the agent. |
| `command-declined.jsonl` | The next turn of the same thread: a command that needs approval, the answer `decline`, and the end of the command with the status `declined`. |
| `file-change.jsonl` | A new file: the change with its content, the request of the app-server without the diff, the answer `accept`, and the end of the change. |
| `closed-during-approval.jsonl` | A command that waits for approval when the app-server ends. The app-server ran nothing. |
| `unknown-thread.jsonl` | The resume of a thread that Codex does not know, and its refusal. |

## What was replaced

The repository is public, so nothing that describes the owner or the owner's Mac stays in these files.

- Every working folder is `/work/project` or `/work/second`, and the configuration folder is `/config/codex`.
- Every thread, turn, item and message identifier is a made-up one of the same form, the same in each place where it occurs. Each time moves back by the same amount, and each count of tokens and each length of a turn is a fixed multiple of the real one.
- The user agent, the name of the Mac, the plan, the credit balance, the e-mail address, the names of MCP servers and the hooks of plugins are made up, and so is the model.
