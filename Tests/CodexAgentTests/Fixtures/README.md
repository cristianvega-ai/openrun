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
| `deaf.jsonl` | Made by hand: an app-server that answers nothing, reads nothing, and ignores SIGTERM. |
| `file-change.jsonl` | A new file: the change with its content, the request of the app-server without the diff, the answer `accept`, and the end of the change. |
| `closed-during-approval.jsonl` | A command that waits for approval when the app-server ends. The app-server ran nothing. |
| `resume.jsonl` | The resume of a thread without its turns: a status before the answer, the answer, and the tokens of the thread. |
| `unsubscribe.jsonl` | Made by hand: the close of the thread of `thread-start.jsonl`, with the answer of the app-server. |
| `interrupt.jsonl` | A stop in the resumed thread: an accepted command that runs on, a second request that the stop declines, `turn/interrupt`, and the end of the background terminal. |
| `usage.jsonl` | The account and its rate limits, read without a thread. |
| `history.jsonl` | Two pages of the turns of the main thread, newest first, with stopped turns. |
| `second-thread.jsonl` | A second thread on the same app-server, in another folder. |
| `never-answers.jsonl` | Made by hand: a thread start that gets no answer. |
| `cut-line.jsonl` | Made by hand from `plain-turn.jsonl`: the output stops in the middle of a line, and the app-server fails. |
| `crash.jsonl` | Made by hand from `plain-turn.jsonl`: the app-server is killed in the middle of the turn. |
| `unknown-model.jsonl` | A turn in the resumed thread with a model that the account cannot use: a warning, an error, and a failed turn. |
| `stop-before-start.jsonl` | Made by hand: the answer to `turn/start`, a stop before `turn/started`, and the end of the turn as interrupted. |
| `unknown-thread.jsonl` | The resume of a thread that Codex does not know, and its refusal. |

## What was replaced

The repository is public, so nothing that describes the owner or the owner's Mac stays in these files.

- Every working folder is `/work/project` or `/work/second`, and the configuration folder is `/config/codex`.
- Every thread, turn, item and message identifier is a made-up one of the same form, the same in each place where it occurs. Each time moves back by the same amount, and each count of tokens and each length of a turn is a fixed multiple of the real one.
- The user agent, the name of the Mac, the plan, the credit balance, the e-mail address, the names of MCP servers and the hooks of plugins are made up, and so is the model.
