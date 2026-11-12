---
title: OpenRun architecture
date: 2026-10-15
---

# OpenRun architecture

This document explains the code of the session process, its clients, and the app.
It is for the owner. Read it with `documentation/product.md`, which holds the decisions, and `AGENTS.md`, which holds the rules of the code.
Update it when you add a module or change the protocol.

## What exists

A background program, the session process, owns every shell and agent that the user starts.
The command-line tool `openrun` and the app connect to it over a Unix socket.
A client can leave, and the programs keep running.

```
  openrun (client)        the app (client)
        \                  /
         \   Unix socket  /
          v               v
        +-------------------+
        |  openrun-session  |   the session process
        |                   |
        |  session A -------+--> pseudo terminal --> /bin/zsh
        |  session B -------+--> pseudo terminal --> claude
        +-------------------+
```

Each session holds three things: a program on a pseudo terminal, a virtual terminal (libghostty-vt) that parses the program's output, and the list of attached clients.

## Modules

Each feature is its own Swift module, as `AGENTS.md` requires.
A module uses another module only through its public types.

| Module | What it does | Public types |
|---|---|---|
| `TerminalEmulation` | Wraps libghostty-vt: the screen, the scrollback, snapshots, replies to the queries that programs send, the default colors that a client sets, and the start of a shell's prompt, and the place in a shell's output where a new width starts | `Terminal`, `ShellPromptScanner`, `ShellPromptTracker`, `PromptKeeping`, `LineEditorAnswer`, `LineEditor`, `TerminalSnapshot`, `UnfinishedSequence`, `TerminalSize`, `TerminalCursorPosition`, `ScreenFormat`, `ScreenExtent`, `TerminalReplyHandler`, `TerminalColorScheme`, `TerminalColor`, `TerminalEmulationError`, `ViewportRowText`, `TerminalSearch` |, `TerminalEventHandler`, `KittyNotificationScanner`
| `TerminalTheme` | The Graphite colors for the light and the dark appearance, and the call that gives them to a terminal | `TerminalTheme` |
| `TerminalRendering` | Draws a terminal with Metal and CoreText: fonts, glyph textures, shaders, rows, cursor, selection and marked text | `TerminalRenderer`, `FontSet`, `FrameStatistics`, `RenderTarget`, `OffscreenTarget`, `DrawableTarget`, `RenderingError`, `ViewportCellRun` |
| `TerminalView` | The AppKit view that shows one terminal and handles its input, selection and scrollback | `TerminalView`, `TerminalViewDelegate`, `OptionKeyRule`, `AppearanceThemes` |
| `PseudoTerminal` | Runs one program on a new pseudo terminal, and names the program in its foreground, its folder and its terminal mode | `PseudoTerminal`, `ForegroundProgram`, `ForegroundState`, `PseudoTerminalSize`, `ProgramLaunch`, `ProgramExit`, `LoginShell`, `PseudoTerminalError` |
| `SessionProtocol` | The socket protocol that the session process and all clients share | `ClientMessage`, `ServerMessage`, `ServerCapabilities`, `SessionExit`, `SessionFailure`, `MessageFrame`, `FramedMessage`, `MessageConnection`, `SocketLocation`, `PeerIdentity`, `SessionSummary`, `ProjectSummary`, `SettingSummary`, `ThreadSummary`, `ThreadImage`, `SessionAlert`, `SessionSize`, `SessionEnvironment`, `SessionProtocolError` |
| `SessionConnection` | The client side of the socket: connect, greet, requests, the match of a typed identifier, the attach conversation, the session changes, the requests of the projects and the settings, and the conversation of an agent thread | `SessionClient`, `SessionAttachment`, `SessionAttachmentEvent`, `ThreadAttachment`, `SessionChangeReceiver`, `SessionIdentifierMatch`, `SessionConnectionError` |
| `SessionLaunch` | How launchd starts the session process when a client needs it: the names of the launch agent, the wake service of the session process, the wake of clients, and the registration with SMAppService | `LaunchAgentNames`, `SessionWakeService`, `SessionWake`, `SessionWakeFailure`, `LaunchAgentRegistration`, `LaunchAgentStatus` |
| `UntrustedText` | The rule for a name that a client or a file gives, and the escape of such text in a message, a log or a terminal | `PlainName`, `QuotedText`, `PrintableText` |
| `DataStorage` | The data folder: its location, its files, and the safe write and read of a JSON document | `DataFolder`, `DataFile`, `DataFileScope`, `DataDocument`, `DataReadResult`, `DataStorageError` |
| `Projects` | The folders that the user adds as projects, their order and names, and the project of a session's start folder | `Project`, `ProjectWithoutFolder`, `ProjectList`, `ProjectFolderPath`, `ProjectStore`, `LoadedProjects`, `ProjectListError` |
| `Settings` | The settings of version 1: their names, kinds, defaults and text forms, the rule for protected settings, and their file | `SettingName`, `SettingValues`, `SettingRequester`, `OptionKeyBehavior`, `LinkDestination`, `NewSessionCommand`, `SettingsStore`, `LoadedSettings`, `SettingError` |
| `AgentThreads` | The record of each agent thread, the list of the records with its rules, and their file | `ThreadRecord`, `ThreadAgent`, `ThreadAccount`, `ThreadList`, `ThreadListError`, `ThreadStore` |
| `GitBranch` | Reads the git branch of a folder from the files of git, with no git program | `GitBranch` |
| `SessionProcess` | The server: sessions, clients, the listening socket, shutdown, the idle exit of the launch agent, the one owner of the projects and the settings, and the agent threads with the processes of their agents | `SessionProcess`, `SessionProcessError` |
| `CommandLineTool` | The `openrun` commands, and the permission hook of an agent thread | `CommandLineTool` |
| `SessionPane` | Connects one terminal view to one session, in a view that any window can hold | `SessionPaneController`, `SessionPaneView`, `SessionPaneContent`, `SessionPaneDelegate`, `SessionStart` |
| `SessionWindow` | One window around one session pane, and a session picker | `SessionWindowController`, `SessionList` |
| `PaneAppearance` | How the panes of the main window look: the theme colors in AppKit, the background of a pane, the top row, its buttons, the selected row and the scroll view of a list | `PaneColor`, `PaneBackgroundView`, `PaneTopRow`, `PaneButton`, `SelectedRowView`, `OverlayScrollView` |
| `ListUpdates` | The rows of a list that changed between two contents, so a table updates them in place | `RowChanges` |
| `ProjectsList` | The first pane of the main window: All Sessions, Needs You, the projects and No Project | `ProjectsListController`, `ProjectsListDelegate`, `ProjectsListContent`, `ProjectDisplay`, `ProjectsListEntry` |
| `SessionsList` | The second pane of the main window: the threads with agents and the terminal sessions as vertical tabs | `SessionsListController`, `SessionsListDelegate`, `SessionsListContent`, `SessionRowDisplay`, `SessionKind`, `SessionsFilter`, `SessionsOrder`, `NewSessionRequest` |
| `MainWindow` | The main window: the three panes as stacked sheets, their widths, the content of the third pane, and the focus between the panes | `MainWindowController`, `MainWindowDelegate`, `PaneContent`, `ContentPaneController`, `PaneLayout` |
| `SessionOverview` | What the session process holds, kept live for the app: the sessions, the projects, the settings and the agent threads from the feed, and the sender of the requests of the app | `SessionOverview`, `SessionOverviewConnection`, `ConnectionStatus`, `SessionRequests`, `SessionRequestFailure` |
| `WindowLayout` | What the main window keeps between two runs of the app in `layout.json`: the rows of the sessions list with their splits, the selection, the filter and the order | `WindowLayout`, `LayoutRow`, `LayoutPane`, `LayoutSplit`, `LayoutEntry`, `WindowLayoutStore` |
| `ListContent` | What the two lists show, made from the facts of the session process and the layout | `ListContent`, `SessionRowFacts`, `ThreadRowFacts`, `RowNeighbor` |
| `SettingsWindow` | The settings window: one pane for each group of settings, and a control for each setting | `SettingsWindowController` |
| `AlertNotifications` | The notifications of macOS for sessions that need the user, behind a type that tests replace | `AlertNotification`, `AlertNotifier`, `SystemAlertNotifier` |
| `OpenRunApplication` | The app: the setup of the launch agent, the host that joins the main window with the session process, the chat panes of the threads, and the menus | `OpenRunApplication` |
| `AgentConversation` | The model of an agent thread: the events of every agent, the transcript that a chat shows, and the state of the thread | `ConversationEvent`, `ConversationEventKind`, `SourceLine`, `Transcript`, `TranscriptItem`, `TranscriptItemContent`, `TranscriptChange`, `TranscriptLimits`, `ThreadState`, `AgentMessage`, `AgentStart`, `AgentStatus`, `AgentText`, `AgentTextDelta`, `BoundedText`, `FileChange`, `JSONValue`, `LineSplitter`, `MessageImage`, `Notice`, `PermissionEnd`, `PermissionRequest`, `PermissionRequestItem`, `ProcessEnd`, `TaskEnd`, `TaskItem`, `TaskMessage`, `TaskStart`, `Thinking`, `TokenUsage`, `ToolCallInput`, `ToolCallInputDelta`, `ToolCallItem`, `ToolCallOutput`, `ToolCallRefusal`, `ToolCallResult`, `ToolCallStart`, `TurnEnd`, `TurnStart`, `UnknownLine`, `UsageReading`, `UsageWindow`, `UserMessage` |
| `ClaudeCodeAgent` | Claude Code in a thread: its command line and environment, the user message line, the decoder of its output, its permission hook, and its history | `ClaudeCodeEnvironment`, `ClaudeCodeHistoryLocation`, `ClaudeCodeHistoryReader`, `ClaudeCodeLaunch`, `ClaudeCodeLaunchError`, `ClaudeCodeOutputDecoder`, `ClaudeCodePermissionHookAnswer`, `ClaudeCodePermissionHookError`, `ClaudeCodePermissionHookRequest`, `ClaudeCodePermissionMode`, `ClaudeCodeToolCallMatcher`, `ClaudeCodeUserMessage`, `ClaudeCodeUserMessageError` |
| `AgentProgram` | Runs an agent program on pipes in a process group of its own, with flow control, and reads the environment of the user's login shell | `AgentProgram`, `AgentProgramError`, `AgentProgramLaunch`, `LoginShellEnvironment` |
| `CodexAgent` | Codex in a thread: the client of `codex app-server`, one app-server for each account, the events of its threads, their approvals, stop, usage and history | `CodexAccount`, `CodexAccountServers`, `CodexAppServer`, `CodexHistoryPage`, `CodexPermissionAnswer`, `CodexRequestError`, `CodexSandbox`, `CodexServerLaunch`, `CodexServerOptions`, `CodexStop`, `CodexThread`, `CodexThreadStart`, `CodexTurn` |
| `MarkdownText` | Markdown as agents write it: its blocks and inline styles while it streams, and their text for display | `MarkdownDocument`, `MarkdownBlock`, `MarkdownBlockKind`, `MarkdownListMarker`, `MarkdownTable`, `MarkdownSpan`, `MarkdownInlineParser`, `MarkdownRenderer`, `MarkdownStyle`, `MarkdownLayoutManager` |
| `ChatView` | The native chat of an agent thread: the transcript, the composer, the states of a thread, and the interface to its host | `ChatViewController`, `ChatViewControllerDelegate`, `ChatThreadFacts`, `ChatThreadCondition`, `ChatChoice`, `ChatAccount`, `ChatOutgoingMessage`, `ChatPermissionAnswer`, `ChatAppearance`, `ChatColors`, `ChatColor` |

The programs in `Sources/openrun`, `Sources/openrun-session` and `Sources/openrun-application` read their start-up input and call `CommandLineTool`, `SessionProcess` and `OpenRunApplication`. They hold no other logic.

### Dependency direction

Dependencies point one way, from the programs down to the features.

```
openrun             -> CommandLineTool -> SessionConnection -> SessionProtocol
                                                              -> SessionLaunch
                                       -> SessionProtocol
                                       -> TerminalEmulation -> libghostty-vt
                                       -> Projects, Settings, UntrustedText
                                       -> ClaudeCodeAgent
openrun-session     -> SessionProcess  -> SessionProtocol
                                       -> SessionLaunch
                                       -> PseudoTerminal
                                       -> GitBranch
                                       -> TerminalTheme -> TerminalEmulation
                                       -> TerminalEmulation -> libghostty-vt
                                       -> Projects, Settings, DataStorage, UntrustedText
                                       -> AgentThreads -> DataStorage, UntrustedText
                                       -> ClaudeCodeAgent, AgentProgram, AgentConversation
openrun-application -> OpenRunApplication -> MainWindow, ProjectsList, SessionsList
                                          -> SessionPane -> TerminalView
                                          -> SessionOverview -> SessionConnection
                                          -> WindowLayout -> DataStorage
                                          -> ListContent -> SessionOverview, WindowLayout, ProjectsList, SessionsList
                                          -> AlertNotifications
                                          -> SettingsWindow -> Settings
                                          -> ChatView, AgentConversation
                                          -> Settings, PseudoTerminal
                                          -> SessionConnection
                                          -> SessionLaunch
SessionConnection -> AgentConversation
SessionWindow     -> SessionPane -> TerminalView
MainWindow        -> ProjectsList -> PaneAppearance -> TerminalTheme
                                  -> ListUpdates
                  -> SessionsList -> PaneAppearance
                                  -> ListUpdates
TerminalView      -> TerminalRendering -> TerminalEmulation -> libghostty-vt
                  -> TerminalTheme     -> TerminalEmulation
Projects          -> DataStorage -> UntrustedText
                  -> UntrustedText
Settings          -> DataStorage -> UntrustedText
                  -> UntrustedText
ClaudeCodeAgent   -> AgentConversation
CodexAgent        -> AgentConversation
                  -> AgentProgram -> PseudoTerminal
                  -> PseudoTerminal
AgentProgram      -> PseudoTerminal
ChatView          -> AgentConversation
                  -> MarkdownText
                  -> TerminalTheme -> TerminalEmulation
```

The session process owns the projects and the settings. Every client reads and changes them through the socket. The tool uses `Projects` only for `ProjectFolderPath`, to find the project of a folder that the user typed, and `Settings` only for the message about an unknown name.
`SessionProtocol` does not use `Projects` or `Settings`. It has its own plain types, `ProjectSummary` and `SettingSummary`, so a client needs no other module to read them.
`UntrustedText`, `DataStorage`, `Projects` and `Settings` use only Foundation and the modules above, so the session process, the tool and the app can all use them.
The session process runs Claude Code in the threads through `AgentConversation`, `ClaudeCodeAgent`, `AgentProgram` and `AgentThreads`. No program uses `CodexAgent` yet.
`SessionConnection` uses `AgentConversation` only for the events of a thread, which it decodes for the app. The tool uses `ClaudeCodeAgent` only for the request and the answer of the permission hook.
`AgentConversation` depends on no other module, and it knows no agent. `ClaudeCodeAgent` does not start a process, and `AgentProgram` knows no agent. `AgentProgram` uses only `ProgramExit` and `LoginShell` of `PseudoTerminal`. `CodexAgent` starts its app-server through `AgentProgram`, and uses only `ProgramExit` of `PseudoTerminal`. None of the four uses AppKit (proposal 13 of 2026-11-10).
`OpenRunApplication` puts `ChatView` in the third pane.

`SessionPane` and `SessionWindow` also use `SessionConnection`, `SessionProtocol` and `TerminalEmulation`. `OpenRunApplication` uses `Settings` only for the typed values of the settings, and `PseudoTerminal` only for the login shell of the user. No program uses `SessionWindow` any more: the main window took its place, and the module goes away when its tests have moved to the pane. `TerminalRendering` does not use `TerminalTheme`: the caller gives it the selection color. `MainWindow` also uses `PaneAppearance`, and `PaneAppearance` uses `TerminalEmulation` for the colors. No app module uses `MainWindow` yet: the app still opens one `SessionWindow` for each session. `MainWindow` does not use `SessionPane`: a host gives the third pane any view, such as `paneView` of a `SessionPaneController`.

`TerminalEmulation` is the only module that imports libghostty-vt.
`PseudoTerminal`, `SessionProtocol`, `SessionLaunch` and `GitBranch` depend on no other OpenRun module. `SessionConnection` depends on `SessionProtocol` and `SessionLaunch`.
So each of the three size types (`TerminalSize`, `PseudoTerminalSize`, `SessionSize`) belongs to one module. `SessionProcess` converts between them at its edge.

The tests follow the same rule. `Tests/SessionProcessHarness` is support code for the integration tests: it starts the real executables and plays the part of a terminal window.
The integration tests run side by side, each on a thread of its own.
At most 8 run at a time (`IntegrationTestSlots`), apart from long tests that mostly wait and start at once.
Floods of input through pseudo terminals slow each other down in the kernel: 3 transfers of 4 MiB at once take 4.2 s each, and one alone takes 0.19 s.
So a test with the tag `floodsTerminalInput`, one that pushes about 1 MiB or more through a pseudo terminal, also takes a lock for the whole Mac (`TerminalFloodLock`, a `flock` on `openrun-terminal-floods.lock` in the temporary folder of the user), and only one such test runs at a time, in every test process of the user.
The lock comes after the slot and goes back before it. A wait for the lock ends after 120 s, and then the test runs without the lock, so a stopped test process of another run cannot block a run for ever. After that wait, each later test of the same process tries the lock once and goes on at once when it is still held, so a stuck lock costs at most one wait of 120 s for each test process.
A test outside `SessionProcessIntegration` that floods a terminal gets the slot and the lock with the trait `.isolatedThread` and the tag, as `WindowBackpressureTests` does.
`PseudoTerminalTests` cannot use the harness, so its one 9 MiB transfer runs outside the lock.
A test that only waits, or whose program never reads, has a normal slot and does not take the lock.
The time that a test shows includes its wait for a slot and for the lock.
`ThroughputTests` run with no other integration test beside them.
So do the two tests that run a `SocketListener` in the test process, because it sets the umask of the whole process while it binds the socket.

`Tests/LiveDisplay` is support code for the tests that need a drawn frame or a picture of a window.
While the screen is locked or the display sleeps, display links do not step and a window capture gives nothing.
The trait `.needsLiveDisplay` skips such a test then, and the test log gives the reason.
It reads `CGDisplayIsAsleep` and the key `CGSSessionScreenIsLocked` of `CGSessionCopyCurrentDictionary`.
`DisplayScheduleTests`, `TerminalViewTests.aViewInAWindowDrawsItsOutputAndThenWaits` and the two opt-in screenshot tests use it.
A test that only needs pixels draws into an `OffscreenTarget` and runs without a screen.

### TerminalEmulation

`Terminal` parses output bytes and keeps the state of the screen.
`TerminalSnapshot` encodes the whole state as bytes, including an escape sequence that is not finished yet, and restores it in another `Terminal`.
`TerminalSnapshot(capturing:byteLimit:)` captures within a byte limit. When the whole state is larger, it restores a copy of the terminal and lowers the scrollback line limit of the copy until a new capture fits. Each try keeps fewer lines than the try before. libghostty-vt drops the oldest whole pages over a line limit, so the snapshot keeps as many lines as fit, to within one page. The screens, the cursor, the modes and an unfinished sequence stay whole. The terminal itself keeps all of its scrollback. When a capture without scrollback is still too large, the result is `nil`.
`Terminal.formatted` writes the screen as plain text, or as text with the sequences that reproduce it.
`Terminal.viewportRowText(at:)` gives the text of each cell of one viewport row and its soft wraps. `Terminal.selectAll()` selects the scrollback and the screen, or the alternate screen alone.
`LineEditorAnswer` finds where a line editor, in its answer to a new size, has erased its lines. After SIGWINCH, zsh and readline move the cursor up by the number of rows that their lines took at the old width, erase from there, and draw the lines again at the new width. That number is right only on a screen that still has the old width, because the primary screen reflows its text. So a copy of the screen keeps the old width until the erase, and takes the new width just after it. zsh's answer ends where it starts its prompt again (see `ShellPromptScanner`), and the answer of a shell with prompt marks ends at its next `OSC 133 ; A`. Readline erases its last row (`CR CSI K`) and then each row above it (`CSI A CSI K`), so its answer ends at the first byte that does not start another erase. The end of editing also ends the answer, because a command then writes for the new size: `OSC 133 ; C`, or for zsh and readline `CSI ? 2004 l`. fish turns bracketed paste off and on while it draws, so only its mark of a command counts.
`ShellPromptScanner` finds the start of a prompt in a program's output. zsh starts each drawing of its prompt in the same way: it turns the text attributes off and erases below the cursor. zsh 5.8.1 and 5.9 write `CSI 0 m`, `CSI 27 m`, `CSI 24 m` and `CSI J`. A bare erase is not a start, because zsh also erases a completion list with it. `CSI 27 m` and `CSI 24 m` must come just before the erase, because fish erases after `sgr0` alone. A shell with semantic prompts, such as fish 4 or nushell, marks the start with `OSC 133 ; A`. `ShellPromptTracker` writes the output to a `Terminal` and keeps the first row of the prompt as a tracked position of libghostty-vt, so the row stays right as the screen scrolls and reflows. A prompt counts only while bracketed paste is on, and a start of zsh only at the first column. `OSC 133 ; C` clears the row, and so does the end of bracketed paste after a start of zsh. A shell that marks its prompt is taken to draw it again after a new size, as kitty and libghostty take it. fish without its start-up files does not, so the kept rows of its prompt stay blank. Only the session process tracks the prompt.
`Terminal.resize(to:keeping:)` can keep a shell's prompt in two ways (`PromptKeeping`). With `.cursorRow`, the shell has erased its lines at the cursor. A reflow can join a blank row at the cursor to the row above, when zsh's prompt starts on a row that continues output without a line end. A line break after the reflow then gives the cursor a row of its own, and no cell is erased. With `.promptRows(aboveCursor:)`, the shell has not answered yet. The screen erases the prompt from its first row down, reflows, and puts the cursor the same number of rows below that first row. Blank rows do not reflow, so the late answer lands on the prompt. kitty keeps a prompt in this way on each resize. Both need a cursor style without a background and a parser outside every sequence. `resize` returns what the screen kept, and every other resize keeps the reflow of libghostty-vt. `Terminal.validate` checks a size before anything else takes it.
`UnfinishedSequence(of:)` returns the start of an escape sequence or a UTF-8 character that the terminal has parsed and the program has not finished. It wraps `ghostty_terminal_continuation_alloc`, the documented libghostty-vt call for these bytes. libghostty-vt knows them only when it tracked them from the first byte: a new `Terminal` tracks from its start, and a restored terminal from its snapshot on.

`Terminal` refuses values that no window has. A grid needs 1 to 10,000 columns and rows (`Terminal.maximumGridDimension`), at creation and in `resize`. The scrollback limit must be 0 to 1,000,000 lines (`Terminal.maximumScrollbackLines`); a negative number would reach libghostty-vt as an enormous unsigned one. A snapshot restore checks the limit too, and so does `setScrollbackLimit`, which changes the limit of a live terminal and reports it in `scrollbackLimit`. libghostty-vt removes scrollback only in whole pages, so a terminal can keep up to about one page of lines more than its limit. A lower limit removes the lines near the screen only when more output comes. Each refusal throws `TerminalEmulationError` before libghostty-vt is called.
`TerminalColor` is a color of three channels, `red`, `green` and `blue`, each from 0 to 255. `Terminal` has calls for the default foreground, background and cursor color and for the default 256-color palette (file `TerminalDefaultColors.swift`). `setDefaultForegroundColor`, `setDefaultBackgroundColor` and `setDefaultCursorColor` set a default, or clear it when the color is `nil`. `setDefaultPalette` takes exactly 256 colors, or `nil` for the built-in palette; any other count throws `TerminalEmulationError`. `defaultForegroundColor`, `defaultBackgroundColor`, `defaultCursorColor` and `defaultPalette` read the defaults back. A snapshot carries the colors that are in force, including the Graphite defaults of the session process. A client can set its own defaults after it restores a snapshot. libghostty-vt keeps a default apart from a color that a program sets with `OSC 4`, `OSC 10`, `OSC 11` or `OSC 12`. A new default does not replace a program color, and a reset by the program brings back the default. `TerminalColorTests.colorsThatAProgramSetsSurviveANewDefault` shows this.
The cap for an unfinished sequence is 32 MiB. A snapshot travels in one frame of at most 64 MiB, and it also holds the screens and the scrollback (more than 15 MiB for a full, densely styled scrollback, and about 80 MB for 1000 columns of wide characters in 256 colors). A cap above the frame size could never fit. A snapshot that is too large loses its oldest scrollback (see "A snapshot that fits in one frame").

The reply handler is described in "Query replies".

The rest of `TerminalEmulation` gives a view what it needs to draw the screen and to send input. Every type has a full-word name, and no other module imports libghostty-vt.

- `RenderState` keeps a picture of the visible screen. `update(from:)` reads a `Terminal`. `beginUpdate(from:)` and `endUpdate()` split the update in two, and only the first one reads the terminal. `dirtiness` is a `RenderDirtiness`: `nothing`, `someRows` or `everything`. `markClean()` resets it after a frame. Output that scrolls the screen marks `everything`, although the rows keep their identifiers.
- `RenderState.forEachRow(onlyChanged:)` gives each `RenderRow` from the top. A row is valid only inside the call. It has a `RowIdentifier` that stays with the row when it moves, `viewportRow`, `isDirty` and `selectedColumns`. `forEachCell(palette:)` gives each `RenderCell`: the text (`base` and `extraScalars`), the `CellWidth`, the `CellStyle` with its `UnderlineStyle`, the resolved colors (`nil` is the default color) and `hasHyperlink`. `colors` is a `RenderColors` and `cursor` is a `RenderCursor` with a `CursorStyle`.
- `TerminalMode` names the modes that a view reads. `Terminal.isModeEnabled` and `setMode` use them. Swift cannot import the mode macros of libghostty-vt, so each mode number comes from `ghostty_mode_new`. `Terminal` also gives `title`, `pointerShape` (a `PointerShape`), `isMouseTrackingActive` and `kittyKeyboardFlags`.
- `TerminalEventHandler` holds the closures for the bell, a new title, a render hold (mode 2026) and a desktop notification (OSC 9 and OSC 777, with at most `notificationByteLimit`, 2048 bytes; libghostty-vt drops a longer OSC). The progress report of ConEmu, `OSC 9 ; 4`, is no notification.
- `KittyNotificationScanner` finds the notifications of kitty, OSC 99, in output, because libghostty-vt parses them and does not report them. It joins the pieces of one notification (`d=0`), decodes base64 (`e=1`), and returns the body, or the title when there is no body. It ignores the other kinds of OSC 99 and a command longer than 2048 bytes. `Terminal.setEventHandler` installs it. It shares the user data pointer with the reply handler (see "Query replies").
- `KeyEncoder` turns a `KeyEvent` (a `PhysicalKey`, `KeyModifiers`, text) into bytes. Call `update(from:optionAsAlternate:)` before each key. It sets the Option choice again after libghostty-vt reads the terminal, because that read removes it. `leftOnly` makes the left Option key send Alt. `MouseEncoder` does the same for a `MouseEvent`. Call its `update` only when the modes or the cell size change, because it forgets the last cell. `FocusReport` makes the bytes of mode 1004, and `PasteText` the bytes of a paste. `PasteText` does not use `ghostty_terminal_paste`, because that function needs the write callback.
- `Terminal.scrollViewport(_:)` takes a `ViewportScroll`. `scrollbar` and `isViewportAtBottom` tell where the viewport is. `selectWord(at:)`, `selectLine(at:)`, `clearSelection()`, `selectedText()` and `hyperlink(at:)` take a `ViewportCell`. `SelectionGesture` turns presses, drags and releases of the pointer into a selection.

`TerminalSearch` finds text in the screen and the scrollback with the search of libghostty-vt (`ghostty_search_*`). Letters of ASCII match in each case. The match that the user is at becomes the selection of the terminal, so the renderer shows it as it shows a selection, and Copy takes it. A step to the older or the newer match first reads the output that came since, and it moves the viewport to the match. The search borrows its terminal, so each call comes from the context that uses the terminal.

### TerminalTheme

`TerminalTheme` holds the colors of the Graphite theme (decision of 2026-10-26): the background, the text, the cursor, the selection and the first 16 colors of the palette. The table "Graphite theme" in `documentation/product.md` lists the values.
`TerminalTheme.graphite(for:)` gives the light or the dark version for a `TerminalColorScheme`. `apply(to:)` sets the default colors of a `Terminal`.
A program can still set its own colors with `OSC 4`, `OSC 10`, `OSC 11` and `OSC 12`. They stay when the theme changes.
The module has no AppKit code. The session process uses its colors to answer color queries, and the view uses them to draw.

### TerminalRendering

`TerminalRenderer` draws a `RenderState` with Metal. After each `RenderState.update`, a caller can give `prepare(from:viewportSize:)` the drawable size in pixels. Without a size, it prepares the whole grid. The caller then uses `draw(into:)` with a `RenderTarget` and calls `markClean()` on the state. `OffscreenTarget` is a texture in memory that tests read or save as a PNG file with `saveImage(to:)`. `DrawableTarget` holds the drawable of a `CAMetalLayer`.
With a drawable size, the atlas checks a new glyph's exact bitmap bounds against the drawable, including overhang, before it uses texture space. It keeps the bounds of at most 1024 hidden glyphs. A size change clears the row cache so newly visible glyphs can enter the atlas.
`FontSet` holds a monospaced font (regular, bold, italic and bold italic) for one point size and one backing scale. It is SF Mono, or an installed monospaced font that `fontName` names; an unknown name or a proportional font gives SF Mono. `CellMetrics` gives the cell, the baseline and the lines in whole pixels. At 13 points and scale 2, a cell is 16 by 31 pixels. The space around the grid is 8 points.
`GlyphAtlas` keeps glyphs in two textures. `GlyphRasterizer` draws clusters with CoreText, which also picks a fallback font for the characters that SF Mono does not have. A glyph in the atlas is reused. Text goes into a texture of coverage, and the shader gives it the color of the cell. An emoji goes into a texture of colors and keeps the colors of its font. An emoji gets smaller to fit inside its cells and never gets larger (decision of 2026-10-27).
`DrawnGlyph` draws some characters in code in place of the font (decision of 2026-10-27): Box Drawing U+2500 to U+257F (`BoxLineArms` for the straight lines and their joints, `BoxDrawingShapes` for the dashes, the rounded corners and the diagonals), Block Elements U+2580 to U+259F (`BlockElements`), Braille U+2800 to U+28FF (`BraillePattern`) and Powerline U+E0B0 to U+E0BF (`PowerlineSymbols`). Each one goes on a `CellCanvas` with the exact size of its cells, from the top left corner, so neighbors join with no gap and no overlap. A light line is one eighth of the cell width, rounded to whole pixels, and a heavy line is two light lines. Straight lines use whole pixels. Curves, diagonals and triangles have smooth edges, and a rounded corner ends straight for its last pixel, so it meets the light lines of its neighbors. The face of a cell does not change the drawing.
The textures grow without moving the pixels already in them, to at most 8192 pixels on a side for coverage and 4096 for colors. When one is full, the renderer tries to replace the textures at most once per frame. A successful replacement rebuilds the row cache. Commands already sent to Metal keep the earlier textures. If marked text fills the atlas after preparation and the frame has not tried a replacement, `draw` returns `false` and the view requests another frame. One visible frame that needs more glyphs than the bounds hold can omit the excess glyphs; it does not overwrite glyphs already in use.
The shaders are Swift text (`ShaderSource`). `ShaderLibrary` compiles them when the renderer starts, because `swift build` does not compile `.metal` files.
`RowQuadrilaterals` turns the cells of one row into `CellQuadrilateral` values, and `RowCache` keeps them by `RowIdentifier`. `prepare(from:viewportSize:)` makes new values only for rows that are dirty or new. It makes all rows again when libghostty-vt marks all of the screen dirty, when the grid or colors change, when the drawable size changes, or when the atlas is replaced.
`FrameBuilder` moves the quadrilaterals of each row to its place and adds the cursor and the text of an input method. `draw(into:)` compares the complete frame by horizontal row band. It redraws only changed bands into a private retained Metal texture, including quadrilaterals that cross a band edge, and presents the whole texture. A new grid, colors, selection color or target size makes a full update. A font change makes a new renderer.
The renderer draws text, styles, wide characters, emoji, the four cursor shapes, selection and marked text. `underlinedRuns` takes runs of cells (`ViewportCellRun`) that get an underline in the text color, for the link under the pointer. The view controls cursor blink and focus; an unfocused view shows a hollow block (`isFocused`). Marked text wraps across rows. The view supplies `markedTextSelection`; `markedTextCaretPosition(at:in:for:)` gives the visible position of a UTF-16 range. An offscreen position can be `nil`.

### TerminalView

`TerminalView` is an `NSView` for one session. It has its own `Terminal`, `RenderState` and `TerminalRenderer`, and a `CAMetalLayer` (`MetalLayerHost`). It does not use the socket or `SessionConnection`. The owner gives it output bytes with `write`. The view sends input bytes, grid changes, title changes and questions through `TerminalViewDelegate`.
The view and its terminal run on the main thread. `write` adds bytes to `TerminalOutputQueue` through `OutputParser`.
The queue keeps output and size markers in the order they arrive. It has no limit of its own; the window limits events before they reach it.
A call of `parseTurn` parses pieces of at most 64 KiB, with a 4 ms budget checked between pieces (`ParseBudget`). It always parses at least one piece, which can take longer than the budget.
A size marker takes effect after earlier output and before later output. After a successful size change, `didApplyGridSize` tells the window to update its hidden grid label.
When output is left, the next turn comes from a run loop source, so events and frames run between the turns.
`DisplaySchedule` holds a display link. A request for a frame starts it, one frame follows, and the link pauses until the next request. A view that is not in a window waits for a window.
At each layout, `GridFit` gives the number of whole cells that fit inside the space around the grid. That fit can differ from the session grid. When the fit changes, the window requests it; the first layout sends no request when it already matches the snapshot. The window also requests the fit when it becomes key. A window cannot become smaller than a grid of 60 columns and 12 rows at its text size (`contentMinSize`, from `TerminalView.size(holding:)`). `terminalViewDidChangeCellSize` tells the window of a new text size or screen scale, and the window then sets its minimum again and grows when it is smaller. It keeps its top left corner and moves only to stay on its screen. A minimum larger than the screen becomes the size of the screen, for the largest text sizes. The window sets its minimum again when it moves to another screen. The hidden-grid label names only a grid that the session applied: while the window waits for its own size, the cells that do not fit are its old size, so the label shows nothing. The window keeps its requests in order. During a drag, the session can confirm an older request while newer ones still wait, so the wait ends only at the newest request or at a grid of another client. The session keeps a shell's prompt in place at a resize (see "Attach sequence"), but it cannot clean rows that went into the scrollback. When a prompt and its input take more rows than the grid has, the shell draws part of them there. The minimum grid keeps a command of 600 characters on the screen. Other clients can still set another size. If a key event happens during attach, the controller keeps the request until the view is ready, but drops it when the window loses key status. The view changes its local terminal in the order of the session's `sizeChanged` messages, after it parses the output that waits for the old size. It passes `keepsCursorAtLineStart` and `promptRowsAboveCursor` on to `Terminal.resize` as a `PromptKeeping` value. A foreign size does not make a resize reply. The grid stays at the top left and is never scaled.
`AppearanceObserver` tells when the macOS appearance changes between light and dark. The view then gives the theme of the other appearance to its terminal and its renderer.
The owner of a view sets `fontName`, `standardFontSize` (the size of Command-0), `optionKeyRule` (`OptionKeyRule`: the left Option key, both or neither is Alt), `scrollbackLimit` and `themes` (`AppearanceThemes`, a `TerminalTheme` for each appearance, Graphite by default). Each change takes effect at once and keeps the screen, the selection and marked text. A new font or size makes a new renderer.
`increaseFontSize`, `decreaseFontSize` and `resetFontSize` change the text by 1 point, between 6 and 72 points (`FontSizeControl`), or go back to 13 points. Each one makes a new renderer and fits the grid again. The view has actions for Command-plus, Command-equals, Command-minus and Command-0. A screen with a new backing scale also makes a new renderer.
`KeyboardInput` uses `KeyEncoder` and `NSTextInputClient` for keys and marked text. Control chords go to `keyDown`; Command chords reach the menu first. The left Option key is Alt, and the right Option key enters characters. Text that arrives without a key press follows the same paste rules as Command-V. This includes dictation, Services and an input-method candidate that the user chose outside a key event. `PasteInput` uses `PasteText`. The delegate asks before an unsafe multiline text, with one question for a paste (`shouldPasteUnsafeText`) and a second for inserted text (`shouldInsertUnsafeText`), so the words of each question fit. A delegate that does not implement the second method gets the paste question. A pending approval expires when the delegate changes, the view moves to another window, or its window closes. `PointerInput` sends mouse reports when the program requests them, while Shift allows selection. `ScrollInput` moves whole rows, sends mouse reports, or sends arrow keys for alternate scroll. Selection, copy, OSC 8 links and the overlay scroll bar also belong to the view.
`MacTextKeys` sends Control-A and Control-E for Command-Left and Command-Right, `ESC b` and `ESC f` for Option-Left and Option-Right, Control-U for Command-Backspace and `ESC DEL` for Option-Backspace with either Option key. They apply only while the program has not turned on the kitty keyboard protocol and no marked text exists.
A drop of files types the path of each file with a space after it (`DroppedFiles`). A path with characters other than letters, digits and `/._-+,:@%=` goes in single quotes. A drop of text and the paths go through the path of a paste. The context menu (`TerminalViewContextMenu.swift`) offers Open Link and Copy Link over a link, Copy with a selection, Paste and Select All. A program that reads the mouse gets the right click unless Shift is down. Select All and Command-A select the scrollback and the screen.
`PlainLinkFinder` finds a plain `http` or `https` address under a cell. It reads the row of the cell and the rows that soft wraps join to it, through `viewportRowText`, and only when the view asks. Punctuation at the end and a closing bracket that the address did not open stay outside, and a blank cell, white space, a symbol or punctuation outside ASCII ends an address. `PlainLinkAuthority` accepts only ASCII letters, digits, `-`, `.`, a port, an IPv6 host and ASCII user information before the path, and a host must end at white space, a path, a closing bracket or quote, or punctuation at the end of the text. A format character anywhere, or a host that Foundation changes, means no link. Letters and digits outside ASCII belong to the path, and Foundation encodes them in the address that opens. An address that goes on above or below the viewport is no link. `LinkHover` underlines such an address and shows a pointing hand while Command is down over a link. It looks again only when the pointer moves to another cell, Command changes, output arrives or the viewport scrolls.
`LinkClick` takes a Command-click on a valid OSC 8 link or a plain address for the whole gesture, so its press, motion and release do not go to the program. Valid `http`, `https` and `mailto` links open at once. Other schemes go through the delegate for confirmation; invalid addresses never open.
The view keeps the selected range of marked text in UTF-16. It gives the input method the marked range and a substring, and uses the renderer's wrapped layout for the candidate position. A new renderer keeps the marked selection when the font size or backing scale changes.
`CursorBlink` follows the program's blink choice while the window is key: half a second shown, half hidden, and one second shown after a key. An unfocused window has a hollow cursor. `BellFlash` gives a 150 ms visual flash. `SynchronizedOutputHold` ends a render hold after one second.

Find (Command-F) shows `TerminalFindBar` at the top right of the view: a search field, the place of the selected match among the matches, the two steps and Done. `TerminalViewFind` takes the items of the Find menu by their tags (`performFindPanelAction`). Find Next goes to the older match, as a search from the prompt wants, and Find Previous to the newer one. After Done, the selected match stays selected.

### PseudoTerminal

`PseudoTerminal(launching:)` starts a program as a session leader with the pseudo terminal as its controlling terminal.
It uses `forkpty`, which makes the pseudo terminal, forks, and in the child makes a new session (`setsid`) and opens the terminal as the controlling terminal.

`posix_spawn` with `POSIX_SPAWN_SETSID` does not work for this. It opens files before it makes the new session, so the program starts with the terminal as standard input but without a controlling terminal.
Only a program that opens the terminal itself later, such as `/bin/sh`, then gets one. `ps -o tty=` showed `??` for `sleep`, `zsh`, `perl`, `dash` and `ksh`. Without a controlling terminal, Control-C does nothing and zsh turns job control off.

The child shares the memory of a process that has other threads, so it must not allocate or take a lock.
The parent prepares every C string before the fork. The child calls only system functions with plain numbers and pointers until `execve` replaces it:

- The terminal is descriptors 0, 1 and 2. The child closes every other descriptor up to 10,240, so nothing leaks into the program.
- All signals go back to their default action, and the signal mask is empty. The session process ignores some signals, and an ignored signal would otherwise survive `exec`.
- The child sets the folder with `chdir`, and `IUTF8` on the terminal.
- A failure in the child (a missing folder, an `execve` error) goes back through a pipe that closes on `execve`. The parent reads it before it returns, so `PseudoTerminal(launching:)` still throws for a program that cannot start. The parent checks the folder first (`stat`, then `access`), so a missing folder, a file, or a folder without search permission always shows as a `chdir` failure. Without that check, a relative `PATH` entry made it show as "program not found".
- A file with the execute permission and no `#!` line makes `execve` fail with ENOEXEC. Like a shell, the child then runs `/bin/sh -- PROGRAM ARGUMENTS...`. The parent prepared that argument list before the fork. When the program still cannot start, the error is the first one, from the program itself.
- After a failed launch the parent waits for the child with `waitpid` and repeats the call when a signal interrupts it (EINTR).
- The first size comes from the `winsize` that `forkpty` applies before the program starts.

Before anything else, the launch refuses a value that would reach the program changed, and nothing starts. A C string ends at its first NUL, so a NUL in the program name, the name the program sees for itself, an argument, the folder, or an environment value would give the program a shorter value or another folder. The system splits an environment entry at its first `=`, so a name with `=` would set a variable of another name, such as `OPENRUN_SOCKET`. An empty name sets no variable. Each case throws `PseudoTerminalError.invalidLaunchValue`, whose message names the problem, such as "The program was not started: argument 2 holds a NUL character." The message never repeats the value, because a value can be a secret. Nothing is cut short.

A program name without a slash is searched in the `PATH` of the launch environment (or in `/usr/bin:/bin:/usr/sbin:/sbin` when it has none). `execve` runs after `chdir`, so a relative entry such as `bin`, a `.`, and an empty entry (`::` or a leading or trailing colon) all mean a place inside the launch folder. The lookup checks the file there and returns the relative path, which names the same file after `chdir`. Only a regular file with the execute permission matches. A folder with the name of the program is skipped.

The kernel reports the exit of a session leader with a controlling terminal before `waitpid` can reap it, because it hangs up the terminal first. The exit event comes once, so the reaper tries again every 5 milliseconds until it succeeds. Without this, an unreaped program stays a zombie and its session never ends.
`waitpid` is tried again after EINTR. Any other error, such as ECHILD after another waiter reaped the program, loses the status for good. The program is then reported as exited with status 127, as a shell's `wait` reports a process whose status it does not know. It is never reported as a success.

The object offers:

- `output`, an `AsyncStream` of the bytes that the program writes. `markOutputConsumed` gives the program flow control: when more than 4 MiB wait, the pseudo terminal stops reading, and the program blocks in its own write.
- `type(_:)`, for typed input. Input that the program has not read yet waits in memory, up to 8 MiB. Past that, `type` waits, without blocking a thread, until the program reads enough. Calls that wait go in whole and in order. A single call with more than 8 MiB waits for an empty backlog. When the program ends, or closes its terminal, before the bytes are in the backlog, `type` throws `PseudoTerminalError.programEnded`. Cancelling the task that waits withdraws the bytes and throws `CancellationError`. Bytes that are in the backlog reach the program.
- `type(_:from:whenSettled:)`, for the keys of an attached client. It returns at once, and the bytes go in behind every earlier input. `whenSettled` runs when they are in the backlog, or will never get there. The bytes belong to their owner until they go to the terminal: `withdrawTypedInput(from:)` removes those that wait for room and those in the backlog that have not started to go out. A piece that started goes out whole, so the program never gets half of a key sequence.
- `write`, for a terminal's answers to queries. It never waits, because the terminal answers while it parses output. The answer joins the backlog even when the backlog is full. When typed input waits for room, the answer goes in right behind that input, because a real terminal sends its bytes in the order it made them. It waits only for the input in front of it, never for room. An answer that waits counts toward the 1 MiB of answers at once (see `waitForAnswerRoom`).
- `waitForAnswerRoom`, which waits while more than 1 MiB of answers wait for the program. The session calls it after each chunk of output. A program that asks without end and never reads the answers then stops in its own output, as typed input stops at 8 MiB.
- `resize`, which sets the size with `TIOCSWINSZ`. The kernel sends SIGWINCH to the program.
- `foregroundState`, a `ForegroundState`: the foreground program, whether it leads the terminal session, its current folder (`proc_pidinfo` with `PROC_PIDVNODEPATHINFO`), and whether the terminal is in line mode (`ICANON`, which `tcgetattr` on the master side reads on macOS). It is nil after the program ended.
- `foregroundProgram`, the name and the arguments of the program that reads the keys, such as `zsh` at a prompt. It reads the foreground process group from the process information of the program (`e_tpgid`), because `tcgetpgrp` on the master side reports the program's own group on macOS. The arguments come from `KERN_PROCARGS2`. It is nil after the program ended.
- `writtenOutputByteCount`, the bytes of output that the program has written so far: the bytes read, and the bytes that still wait on the terminal. `TIOCOUTQ` on the master side counts those; `FIONREAD` there always reports zero on macOS.
- `waitForExit`, which returns a `ProgramExit`.
- `terminate`, which ends the program and every other process of its terminal session. The program is a session leader (see `forkpty` above), so this means every process whose session identifier is the program's, also one that moved to another process group. SIGHUP goes to the program's process group first, then to each other process group of the session. A group with a stopped process also gets SIGCONT, because a stopped process acts on the hang-up only when it runs. After the grace period (one second), SIGKILL goes to every process of the session that is still alive, also when the program itself has already ended. A program that has already ended by itself when `terminate` is called leaves its background processes running. A process that started a session of its own (`setsid`), such as a daemon, is not in the session and keeps running. When the system cannot list the processes, the session counts as unknown, not as empty. `terminate` then sends SIGHUP to the program's process group, the process group of the session leader, and repeats it while it waits. It keeps waiting and signalling until the grace period (one second) has passed, and then sends SIGKILL to that group, repeatedly, for up to one more second (the killing limit). It never takes a failed list for a session with no process left.

`InputBacklog` (internal) keeps the books of the input: the backlog, the input that waits, the owners, and the limits. `PseudoTerminal` keeps one on its queue, writes the bytes, and calls the completions that it returns. Unit tests check it without a program. The two queues of `InputBacklog` (the pieces in the backlog and the input that waits) keep a start index that moves up when the front goes. They drop the unused head when it is half of the storage and holds at least 64 entries. Taking the front costs a constant time on average, so 100,000 one-byte pieces drain in well under one second. The limits and the order of the bytes did not change.
The internal `init(launching:typedInputLimit:)` gives a terminal another limit of typed input, so a test can fill the backlog with 64 KiB. `init(launching:)` always uses 8 MiB.

`TerminalSessionProcesses` (internal) finds the processes of the program's session and sends them signals. It uses Darwin calls only. macOS lists no processes by session (`sysctl` with `KERN_PROC_SESSION` fails with ENOENT), so it lists every process with `proc_listallpids` and asks each one for its session with `getsid`. A zombie has ended and is left out. Right before each signal it checks the session of the process again, so a process that ended, and whose identifier went to another program, never gets the signal. A process group gets a signal only when one of its members is still in the session and in that group right before the signal. `members()` throws `TerminalSessionProcesses.ListingFailed` when `proc_listallpids` fails, so a caller can tell a failed list from a session with no process. An empty result means that the session has none.

Why a session identifier is safe to trust: a session identifier is the process identifier of the process that made the session. XNU gives a new process an identifier only when no process, also a zombie, uses that number as its process, process group or session identifier (`forkproc` in `bsd/kern/kern_fork.c`, which keeps the rule of the 4.4BSD `fork`). So while one process of the session lives, no other session can have its number. `terminate` starts only while the program is not yet reaped, looks again at least every 20 milliseconds, and stops for good once the session has no process left. Another session could take the number only after every other process identifier, about 100,000 of them, was handed out in between.

The controlling descriptor is closed once, when the program has ended and the last dispatch source that watched it is gone.

`LoginShell.current()` reads the shell from the user database. `LoginShell.launch` starts it with a leading dash in its name, which makes it a login shell.

### SessionProtocol

This module holds the messages, the frame format, the connection, and the socket location with the check of its folder. `FolderAccessControlList`, an internal type, reads the access control list of the folder for that check. `PeerProcess` reads the program at the other end of a connection: its process identifier, its terminal session and its audit token. `ApprovalQuestion` is the question of "Requests on another session". The next sections describe them.

### SessionConnection

The client side of the socket, for the command-line tool and the window of the app. It imports no AppKit and knows nothing of standard input or output. A caller can use it from any thread.

- `SessionClient(location:)` connects and greets the session process. Its `capabilities` tell whether the process offers ordered resize confirmations. `request` sends one request and returns its answer. `summaries` lists the sessions, and `session(matching:)` finds the session that a typed identifier means (`SessionIdentifierMatch`).
- `SessionClient.attach` sends `attach`, waits for `attached` and the snapshot, and returns a `SessionAttachment`. A failure before the snapshot is an error of this call, so the caller knows before it changes anything. The client takes no more requests after it.
- The snapshot stays `Data`, the type of the protocol, so the module does not use `TerminalEmulation`. The caller restores it with `TerminalSnapshot(bytes:)`.
- `SessionAttachment.startReceiving` starts a thread that receives the rest. It hands each `SessionAttachmentEvent` to its handler in order, on that thread: `output` and `sizeChanged`, and last `exited`, `closed` or `failed`. A message that does not belong after the snapshot is ignored. The events are `Sendable`, so a window can hand each one on to the main queue. While the handler runs, the socket holds the later frames.
- `send(input:)`, `send(size:)` and `detach()` work from any thread. A size send can request an ordered confirmation. A failure of such a request reaches the attachment handler as an error. `shutdown()` ends the connection and wakes the receiving thread.
- `SessionConnectionError` names each failure. Its text names no command or option of a client, so `CommandLineToolError(_:)` gives each error the words of the tool, such as "choose a socket with --socket".
- A socket that no program listens on (ENOENT or ECONNREFUSED) gives `noSessionProcess`. On the default socket, `SessionClient(location:)` first sends one wake to the launch agent and connects again. A connection that closes before `hello` leads to the same wake, because a launch agent that ends at its idle exit closes such a connection. A wake that fails gives `wakeFailed` with the `SessionWakeFailure`. Tests pass their own wake to `SessionClient(location:wake:)`.
- `SessionClient.receiveApprovalQuestions` turns the connection into an `ApprovalQuestionReceiver`. Its thread hands each question, the end of each question, and last `closed` or `failed` to a handler. `answer(_:allows:)` sends the user's answer from any thread.
- `SessionClient.receiveSessionChanges` turns the connection into a `SessionChangeReceiver`. Its thread hands `sessions` first, then each `sessionChanged` and `sessionEnded`, and last `closed` or `failed`. Check `capabilities.sessionChanges` first.
- `rename(session:to:)`, `raiseAlert(session:text:)` and `clearAlert(session:)` change the facts of a session. See "Facts of a session".
- `projects()`, `addProject(folder:name:currentFolder:)`, `removeProject(_:)`, `renameProject(_:to:)` and `moveProject(_:to:)` read and change the projects. `settings()` and `changeSetting(named:to:)` read and change the settings. Check `capabilities.projectsAndSettings` first. A `SessionChangeReceiver` hands `projects` and `settings` right after `sessions`, and again after each change of them. See "Projects and settings".
- `SessionClient(location:helloTimeLimit:)` gives each `hello` a time limit. A `hello` that takes longer throws `protocolFailure(.timedOut)` and sends no wake. The other initializers keep no limit, so `openrun` and the windows wait as long as the session process takes. Only the setup of the app passes a limit.

### SessionPane

`SessionStart` selects a new login shell or a running session. `SessionPaneController` owns one `SessionPaneView`, its terminal view and its attachment. A host puts `paneView` in its layout and calls `attach()`, which estimates the grid from the size of the pane, so the host lays the pane out first. The host calls `activate()` when its window is key and the pane has the keyboard focus, `deactivate()` when either ends, and `close()` when it removes the pane. `SessionPaneDelegate` tells the host of a new title, a new `minimumSize` and the end of the session. The terminal view takes the keyboard focus at the attach only when the pane or nothing in the window had it. `content` gives, in one `SessionPaneContent` value, all that a host needs to show the pane: the view, the title, the minimum size, the focus view and the inset of the text. The module does not depend on a host, so a host maps that value to its own type.
`AttachedSession` is the pane's interface to an attachment. `SessionAttachment` and a test stand-in implement it.
The window connects and attaches on `ConnectionWork`, a serial queue outside the main thread. The snapshot makes the view, and `AttachmentRelay` gives later events to the main thread in order.
The relay admits at most 1 MiB of output and 128 events until the view applies them. One larger frame can enter an empty relay. The receiver can hold one more frame, and the parser makes a copy of each admitted output frame. A frame can hold at most 64 MiB. When the relay is full, the receiver waits and the socket holds later frames. The window asks the session process to pause output when its queue fills, within the limits in "Slow clients". A program exit or connection failure waits for earlier output to be applied. Closing the window cancels the relay, wakes its receiver and discards pending view output.
Input and size requests go back through the serial connection queue. Each input event stays one frame.
Closing schedules a detach behind ready work. A separate shutdown wakes a send that is still blocked after 200 ms and skips later queued sends.
A whole input event that the session already started can still reach the program after the window closes.
The title comes from the terminal's title, or the session folder when the title is empty. A small label reports grid rows or columns that do not fit. `close()` detaches and leaves the session running. The exit of the program, and a connection failure after the user saw it, reach the host as the end of the session. The questions are sheets on the window of the pane. The controller asks before an unsafe paste, before unsafe inserted text with a question of its own, and before a link that needs confirmation. The link question shows its complete target in a selectable, scrollable sheet. Cancel or a closed window prevents the open.
### SessionWindow

`SessionWindowController` owns one window around one `SessionPaneController`. It tells the pane when the window becomes key, closes the pane with the window, shows the title of the pane, and closes when the session ends. It keeps the minimum size of the window: the minimum of the pane, or the screen when that does not fit, and it grows a window that a larger text size leaves too small.
`SessionList` loads running sessions off the main thread. Its picker shows the folder and full identifier of each session. It handles an empty list and Cancel, and shows a connection failure instead of treating it as an empty list.

### PaneAppearance

`PaneColor` gives the colors of the Graphite theme to AppKit as dynamic colors, so a pane changes at once with the appearance. With Increase Contrast, the dividers and the quiet text take the color of the text, and the selection is clearly stronger. The main window draws its views again, and the progress marks take their colors again, when the display options of the workspace change. `PaneBackgroundView` paints one pane color. `PaneTopRow` is the top row of a pane: 52 points high, the height of the unified toolbar, so its controls sit on the middle line of the traffic lights. Its inset gives way to a stronger constraint of the window, such as the room of the traffic lights. A press on its empty part moves the window, and a double click does what the user chose in System Settings. It paints only its own bounds, because views do not clip to their bounds since macOS 14. `PaneButton` makes a borderless outline symbol button in the quiet text color, with a name for VoiceOver. `SelectedRowView` draws the selection as a soft rounded rectangle, quieter when the window is not key. `OverlayScrollView` keeps thin overlay scrollers in the lists when the user asks for legacy ones.

### ListUpdates

`RowChanges` compares two arrays of rows by their identifiers. It gives the removed rows, the inserted rows, and the rows whose content changed. `apply(to:)` removes and inserts rows in one update of the table and updates the changed rows in their own views, so a list of 100 rows with frequent changes never reloads whole.

### ProjectsList

`ProjectsListController` shows a `ProjectsListContent`: "All Sessions", "Needs You" with the count of rows that need the user, the projects in the user's order with their own counts, and "No Project". It keeps its selection across new content, and selects "All Sessions" when the selected project goes away. `ProjectsListDelegate` gets the selection, a request for a new project, folders dropped from Finder, a removal, a rename in place and a move by drag. The host owns the projects, so the list shows a change only when the host gives new content. A drag moves the row at once, so it does not jump back while the host saves the order.

### SessionsList

`SessionsListController` shows a `SessionsListContent`: the rows of the entry that the first pane selects, in the user's order. Each `SessionRowDisplay` is a thread with an agent or a terminal session (`SessionKind`), with a title, a folder and a branch, its progress, an optional alert and two times. The second line shows the folder and the branch, after the short name of the model for a thread. It is one text that starts at the x of the title, and spare room goes to its end. When it does not fit, only the folder loses its start, by a measured cut. The pane filters the rows with `SessionsFilter` (all, in progress, finished) and orders them with `SessionsOrder`. The host sets both at the start with `arrange(filter:order:)`, and the delegate gets each choice of the user. A row that needs the user shows its alert in place of the second line and a dot in the attention color. A row in progress shows a turning arc that Core Animation draws, which stands still with Reduce Motion. A finished row shows its age, which a timer updates once a minute. The new-session button offers a `NewSessionRequest` for each agent of the content and a terminal. `SessionsListDelegate` also gets the selection, Return on a row, a rename, a close and a move by drag in the user's order.

### MainWindow

`MainWindowController` owns `PaneWindow`, which has no tabs and no title strip, and an `NSSplitViewController` with the three panes. The host gives the two lists their content through `projectsList` and `sessionsList`, and the third pane a `PaneContent` through `showContent(_:)`: any view or view controller, its title, its minimum size, the controls for its top row, and the inset of its text, where the title of the pane starts. While the panes change their widths in an animation or a drag, the pane holds the width of the view, and the view gets the final width in one layout at the end. So a session sends one size request for each change, and the window saves the `PaneLayout` once. `ContentPaneController` holds the content in one place, `contentArea`, where a split tree goes later. `PaneLayout` keeps the widths of the lists and whether each one is hidden, in the defaults that the host gives. The width of a list is the user's choice: only the end of a drag of its edge changes it. A narrow window or a show can squeeze a list down to its minimum, and a constraint of a priority above the hold of the panes grows it back to its chosen width when room comes back, before the content takes the spare room. Menu items from `paneMenuItems()` hide and show the lists and move the keyboard focus between the panes. A drag of an edge does not collapse a list, so `setCollapsed` is the only place that hides one, and the layout, the saved layout and the minimum stay in step. A `sidebar.left` button sits first in the top row of the first visible pane, after the room of the traffic lights, and hides and shows the projects list. In full screen the traffic lights hide, so that row gives their room to its controls. Each top row keeps its controls at its inset from its pane, and a weaker constraint keeps them clear of the traffic lights. So in a hide or a show the controls move with their pane and stop at the traffic lights, and the panes, not the rows, decide the widths. The window keeps the minimum size of the visible lists and the content, as `SessionWindowController` does for one pane. `MainWindowDelegate` learns when the content becomes active, so a `SessionPaneController` can take its grid size back, and when the window closes.

A view that refuses the keyboard focus, such as a session pane after its attach, passes it to the first view inside it that takes it. The window grows to the minimum of the final layout before a list moves, so an animation never asks for a width that the minimum refuses. A show takes the room of the list from the content, and the window grows only by the room that the content cannot spare. A hide gives the room to the content, and the window keeps its width. When the minimum is wider than the screen, the content pane gives up the room that is missing. After a resize or a move to another screen, the window checks its minimum later, outside the layout pass.

A host that shows a `SessionPaneController` in the third pane shows `PaneContent` mapped from `content`, and it forwards these calls:

- `sessionPane(_:didChangeTitle:)`: call `updateContentTitle(_:)` with the title.
- `sessionPaneDidChangeMinimumSize(_:)`: call `updateContentMinimumSize(_:)` with `minimumSize`. Without it, the window keeps the old minimum after the text size grows.
- `sessionPaneDidEnd(_:)`: call `showContent(nil)` or show other content, and call `close()` on the pane.
- `sessionPane(_:didFailWithMessage:)`: show the message where the user sees it, such as in the row of the session.
- `mainWindowContentDidBecomeActive(_:)`: call `activate()` on the pane.
- `mainWindowContentDidResignActive(_:)`: call `deactivate()` on the pane.
- `mainWindowWillClose(_:)`: call `close()` on the pane.

### OpenRunApplication

`ApplicationArguments` chooses the socket from `--socket`, then `OPENRUN_SOCKET`, then the default path. The app runs `LaunchAgentSetup` off the main thread for the default socket. Its questions go through `ModalAlert`, which starts the modal loop from a run loop block. A modal loop never runs inside a Swift concurrency job or a block of the main dispatch queue, because such a block holds the main queue until the alert closes. The blocks that deliver the output of attached windows would wait, the relay would fill, and the session would close the connection of the window. A nondefault socket skips registration and wake, so a development session process must already listen there. The app shows the main window at once. Once setup is ready, the host of the window follows the session process, and the app opens the connection for approval questions. A click on the Dock icon shows the window again after a close. A close of the window and a quit detach the panes, and every session goes on.
`MainMenu` makes the native app, File, Edit, View, Session and Window menus. Edit has Undo, Redo, Cut, Copy, Paste and Select All, which AppKit needs in the menu for their keys to work in a text field, and the Find submenu. The view with the keyboard focus takes the Find items: a terminal or a chat. File starts a session (Command-N), starts one with a command of the settings (the submenu fills from the settings when it opens), closes the selected session (Command-W) and closes the window (Command-Shift-W). View hides and shows the two lists, moves the focus between the panes and changes the text size. Session gives a name to the selected row and goes to the next and the previous row (Command-Shift-] and Command-Shift-[, the keys of the tabs of other Mac apps). The session commands go to the host, and each one is on only when it can act. File > Retry Session Process runs the setup again. It is on only when setup has not succeeded and does not run. File > Register Session Process Again is on except while setup runs. It is also off for a nondefault socket, which has no launch agent, and its action does nothing there. Copy, paste and text-size actions reach the focused view through the responder chain.
Once setup is ready, `ApprovalQuestionConnection` opens the connection for approval questions. It connects again after the session process ends, with a wait that doubles from one second up to 30 seconds, and every 30 seconds after a refusal. `ApprovalQuestionAlerts` shows one question at a time, from a run loop block as `ModalAlert` does, and closes the alert of a question that ends with `abortModal`, since that end comes outside the events of the modal loop. A button chosen after the end sends nothing. `ApprovalQuestionWords` holds the words: the first button denies and takes the keyboard focus, each control character of typed text shows as a sign, such as ⏎ for Return, and each format character, such as a direction override, shows as its code.

#### The host of the main window

`Workspace` joins `MainWindowController` with the session process. It owns a `SessionOverviewConnection`, a `SessionRequests`, the `WindowLayout` with its store, `SessionPanes` and `ThreadPanes`. Its data folder is the folder of its socket, so an app on a temporary socket never touches the data of the user.

- **Content.** After each batch of changes of the feed, the host brings the rows in step with the sessions (`WindowLayout.follow`), makes a `ListContent`, and gives the two lists their content. Before the first list of the sessions it keeps the kept rows. When the selected session ended, the row that took its place in the list gets the selection (`RowNeighbor`). It saves the layout when it changed.
- **The third pane.** `ShownContent` is what the pane shows: nothing, the pane of the first session of the selected row, or a `PaneNotice`. A new pane attaches after the window laid it out, because it estimates its grid from its size. The content takes the keyboard focus when the content before it had the focus, or when the user asked for the session. A row that leaves the list through the filter keeps its place in the third pane.
- **Panes.** `SessionPanes` keeps the pane of each row that the user saw, at most eight, so a switch back is instant. Each pane holds a connection and a terminal with its scrollback, and eight leave most of the 64 clients of the session process free. Past the limit, the pane that the window showed longest ago closes. A pane outside a window sends no size and draws nothing. A close of the window closes every pane.
- **Notices.** While the app does not hear the session process and no row shows, the pane says so, and the connection comes back by itself (after 0.5 s, then twice as long each time, up to 10 s). The pane of a session that lost its connection ends after the user saw why. Its row then shows a notice with Connect Again, so a failure that stays does not show again and again. A session whose program ended shows nothing until the feed removes its row.
- **Sessions.** A new session goes to the session process as a request (`NewSessionLaunch`): the login shell, or a command of the settings as `exec COMMAND` in an interactive login shell, in the folder of the selected project or the home folder, with the grid of the third pane and the environment of the app. Its row takes the selection and the focus when the feed brings it. When the first lists of the feed hold no session and no thread, the host starts a login shell. A close of a row ends its sessions, after a question when the program that reads the keys is not a shell (`CloseQuestion`). A name goes to the first session of the row, so `openrun list` shows it. A move, the filter and the order go to the layout.
- **Threads.** The row of a thread shows its chat. `ThreadPaneController` joins one `ChatViewController` with one `ThreadAttachment`: it applies the events to a `Transcript` in batches on the main thread (`ThreadEventBatches`), and it sends what the user does in the chat to the thread. `ThreadPanes` keeps the chats that the user saw, at most eight, as `SessionPanes` does. The top row of the chat has the name of the agent and Open in Terminal. While the conversation is open in a terminal, the row of the thread shows that terminal session with the button Back to Chat in its top row, and the session gets no row of its own. `ThreadPaneHistory` asks for a page of the earlier turns when the user goes to the top of the chat, and at once when the thread keeps no events. `Transcript.prepend(history:label:)` puts the turns before the items and leaves out a turn that the chat has, because the history also holds the turns of the live events. The menus under the composer send `changeThread`, and the feed brings the new model and mode to the chat and to the row. File > New Thread (Command-T) and the menu of the new-session button make a thread with Claude Code in the folder of the selected project. A name of the row goes to the thread. A close asks first, because it ends the agent. An agent that starts to wait for an answer of the user gives a notification, unless the user looks at its chat. A session process of an older build sends no list of the threads, and the window then offers no thread.
- **Projects.** The session process owns the projects, so an add (from a folder panel or a drop), a name, a move and a removal go there as requests, and the first pane shows the change when the feed brings it.
- **Alerts.** An alert ends when the user selects its session, and at once for the session in view: the session of the third pane while the window is key and the focus is in that pane. That session shows no mark. A new alert of any other session gives a notification of macOS through `AlertNotifier`, unless the setting `notifications` is off. An alert that ended takes its notification away, and an opened notification selects the row. The Dock icon shows the number of rows that need the user.
- **Settings.** `LiveSettings` makes the typed values from the texts of the feed. Each pane gets the font, its size, the Option key rule and the scrollback limit at its start and at each change, also a pane that the window does not show. `ask-before-unsafe-paste` turns the paste question of each pane on and off. The theme stays Graphite.
- **The settings window.** OpenRun > Settings (Command-Comma) shows the `SettingsWindowController`, once the settings of the session process came. A change goes to the session process as `changeSetting`. The session process takes a protected setting only from OpenRun.app, so the window is the one place that changes it. After a refusal the window shows the values of the session process again, with the reason in a sheet.
- **Failures.** A request that fails shows the reason of the session process in a sheet on the window. A sheet does not hold the main queue, so the output of the panes goes on behind it.

### SettingsWindow

`SettingsWindowController` makes the settings window (decision of 2026-10-15). `SettingsPane` names the four panes, General, Appearance, Terminal and Agents, and the settings of each one. Each setting of version 1 has one control in one pane, and a test compares the controls with `SettingName.allCases`. The panes are tabs in the toolbar of the window (`SettingsTabViewController`), and the window takes the height of the pane that shows.
A control (`SettingControl`) shows the text of its setting, as `openrun settings get` prints it, and tells the new text of a change. `ChoiceSettingControl` is a menu, and it keeps a value that it does not know, such as one of a later build. `FlagSettingControl` is a checkbox. `NumberSettingControl` is a field with a stepper, and text that is no number in the range goes back. `TextSettingControl` is a field, with a list of usual values for the model. `CommandListSettingControl` is the table of the new-session commands, which tells its list as one line of JSON.
The window changes nothing itself and knows no socket. It tells its host the name and the new text, the host sends `changeSetting`, and the host gives the window the texts of the feed: at the start, after each change, and after a refusal. So a value that the session process refused never stays on the screen. `SettingsWindowPictureTests` save a picture of each pane when `OPENRUN_RENDER_OUTPUT` names a folder.

### SessionOverview

`SessionOverview` holds the sessions, the projects and the settings as the app last heard them, and takes each event of the feed of the session changes. The end of a connection keeps the last facts.
`SessionOverviewConnection` opens the feed on a thread of its own, so the main thread never waits for the socket. `PendingChanges` holds the events between that thread and the main thread. It keeps one change for each session and one list of each kind, so one hundred sessions that change ten times a second leave at most one hundred events, and a slow main thread never makes the list long. The main thread takes every event that waits in one step and tells its host once for each batch that changed the overview. After the end of a connection, the next try comes after a wait that starts at half a second and doubles up to ten seconds. On the default socket a try wakes the launch agent, so the session process runs while the app runs. `hasSessionList` tells whether a list of the sessions came since the start. A session process of an older build, with no feed of the projects and the settings, gives the reason `OlderSessionProcess`.
`SessionRequests` sends the requests of the app in order on a queue of its own and gives each result to the main thread. It keeps one connection. When that connection ended, it connects again and sends the request once more, because the session process that ended did not get it. A refusal keeps the connection, and `SessionRequestFailure` holds the reason in words that a window can show.

### WindowLayout

`WindowLayout` is the content of `layout.json`, which only the app writes: the rows of the sessions list in the user's order, the selected entry of the first pane, the selected row, and the names of the filter and the order. `LayoutRow` has an identifier that stays, which is the identifier of its first session, and a `LayoutPane`: one session, or a `LayoutSplit` of two panes side by side or one over the other. When a session ends, the other half of its split takes its place. `follow(sessions:)` gives each new session a row at the top and removes the rows with no session. A row or a session that the file names twice stays once. `moveRow` moves a row among the rows that the list shows and leaves the others in place. `WindowLayoutStore` writes on a queue of its own, only the newest layout that waits, and the app waits for the last write when it quits. A key that the file does not hold takes its first value.

### ListContent

`SessionRowFacts` makes a row of the second pane from the facts of its sessions. The title is the name that the user gave, or the title that the program set, or the program with the last name of its folder, such as `zsh — openrun`. The folder shows `~` for the home folder. The alert, the work and the times come from every split of the row, and the session in view shows no alert. `ListContent` gives the first pane its projects with the counts of the rows that need the user, and the rows and the title of each entry. A session that names a project that the list no longer holds is outside every project. `RowNeighbor` gives the row after a removed row, or else the row before it.

### AlertNotifications

`AlertNotifier` shows and removes the notification of a session, and tells when the user opens one. `SystemAlertNotifier` uses the notification center of macOS. It asks for the permission at the first alert, and it shows nothing when the user refuses. A program outside an app bundle, such as one of `swift build`, has no notification center, so the notifier does nothing there.

### GitBranch

`GitBranch.name(forFolder:)` finds the nearest `.git` at or above the folder. It follows a `.git` file with `gitdir:`, as a worktree has, and reads `HEAD`. `ref: refs/heads/NAME` gives NAME, and a detached head gives the first 7 characters of the commit. It reads at most 4096 bytes of a regular file and does not wait for a named pipe. The nearest `.git` decides, so a broken one gives no branch. It runs no git program, because the session process reads the branch once a second while a session works.

### SessionProcess

`SessionProcess.run()` listens until SIGTERM, SIGINT or SIGHUP arrives. Internally:

| Type | Job |
|---|---|
| `SocketListener` | Checks the folder, takes the lock of the socket, checks for a live process, replaces a stale socket only while the path still holds the socket it checked, creates the socket with mode 0600, and accepts connections of the same user. At most 64 accepted connections, the length of its listen queue, wait for the server to take them, and it closes each one past that at once. After a failed accept it waits before it tries again. At shutdown it removes the socket file only when the file is still its own |
| `SocketListener.SocketLock` | The lock file next to the socket, held for the life of the process, so that two processes that start together cannot both pass the checks. It uses only a regular file of the user, opened without following a symbolic link, and sets its mode to 0600 |
| `SessionServer` | An actor. Refuses clients past the limit, reads each client's messages and answers them. A client keeps its place until its socket is closed. It asks the user before a request on another session |
| `CallerPlace` | Where the program of a client runs: in a session, outside every session, or unknown. See "Requests on another session" |
| `AnswererRequirement` | The code requirement that a program must meet to receive and answer approval questions, and to change a protected setting |
| `ApplicationBundle` | The app bundle that holds a program, found from the path of the program. `AnswererRequirement` and `HelperSearchPath` use it |
| `ApprovalQuestions` | An actor. The questions that wait, and the connections of the app that hold them |
| `ClientConnection` | One client. A thread reads from it, and a serial queue writes to it. It ends the connection when a deadline or a limit is missed, answers a request that it cannot decode, tells the server when the client has left, and closes the socket once neither the thread nor the queue uses it |
| `ReadAhead` | Holds the reading thread of a client while the frames that were read and not handled are too many. Keeps room for one small control frame, so a client can detach while its input waits |
| `ConnectionLimits` | Every limit and deadline of a client, in one place. See "Limits and deadlines of a client" |
| `SessionRegistry` | An actor. The sessions, found by identifier. It refuses a session past the limit of the setting `session-limit`, and gives each session the project of its start folder |
| `ProjectKeeper` | An actor on a serial queue of its own. The one owner of the projects: it loads them at the start, saves each change at once, and keeps a change only after its save. See "Projects and settings" |
| `SettingKeeper` | The same for the settings |
| `DataSaveFailure` | The message of a save that failed |
| `Session` | An actor. One program, one `Terminal`, the attached clients, and the facts of the session |
| `SessionChangeFeed` | The latest summary of each session, the projects, the settings, and the connections that watch them. It sends each change under one lock, so every watcher gets the same order |
| `ThreadRegistry` | An actor on a serial queue of its own. The records of the agent threads, which it keeps in `threads.json`, and the runner of each thread in use. See "Threads in the session process" |
| `ThreadRunner` | An actor. One thread in use: the process of its agent, its transcript, the events that it keeps, the messages that wait, the permission requests, and the attached clients |
| `ThreadEventBuffer` | The newest events of a thread, at most 4 MiB, for a client that attaches |
| `AgentProcessSlots` | The threads that may run the process of an agent now, at most the number of the setting `agent-process-limit`, and the threads that wait in line |
| `AgentLaunchProvider` | How an agent starts: its program, the environment of the login shell of the user, read once, and the permission hook |
| `ProcessAncestry` | Finds the agent of a thread among the parents of a process, for the rule on who may use the threads |
| `SessionActivity` | Decides whether a session is in progress, and whether a bell raises the alert |
| `TerminalEvents` | Keeps the bell, the title and the notifications that the terminal reported during one write |
| `InteractiveShell` | Tells a shell that reads commands from the terminal from a shell that runs a command or a script |
| `ShutdownSignals` | Turns the stop signals into a value to wait for |
| `IdleExit` | The time limit of the idle exit of the launch agent, 30 seconds, and the wait for it. See "Launch agent" |
| `SessionLog` | Writes each line of the log to standard error and to the unified log |
| `HelperSearchPath` | The folder `Contents/Helpers` of the bundle that holds the process, which goes first on the `PATH` of each new session |

The log of the session process (`SessionLog`) escapes every line with `PrintableText.escaping` of `UntrustedText`, which makes text from an untrusted source safe to print in a terminal or a log. A log line can include text that a client chose, such as a folder, a command or an error message, and a terminal that shows the log must not obey it.
Each line goes to standard error and to the unified log, with the subsystem `ai.cristianvega.openrun`, because launchd sends the standard error of the launch agent to /dev/null. In the unified log, each path, command line and error text is private, and only the words of OpenRun, counts and identifiers are public. `log show --predicate 'subsystem == "ai.cristianvega.openrun"'` shows the lines.

### CommandLineTool

`CommandLineTool.run` parses the arguments (`CommandLineArguments`), connects with `SessionClient` of `SessionConnection`, and runs one command. It turns a `SessionConnectionError` into a `CommandLineToolError` with the words of the tool.
`NewCommand`, `ListCommand`, `AttachCommand`, `ReadCommand`, `SendCommand`, `KillCommand`, `RenameCommand`, `NotifyCommand`, `ProjectListCommand`, `ProjectChangeCommand`, `SettingsCommand` and `ThreadCommand` hold the commands. `PermissionRequestCommand` is the permission hook of an agent thread (see "The permission requests of a thread"). It is not in the usage text, because only an agent runs it. `ProjectMatch` finds the project that the user typed. `ListedSession` is the shape of one session in `openrun list --json`. `RawTerminalMode` switches the terminal to raw mode and back.
`openrun attach` has three more types. `TerminalWriter` is the one writer of the terminal. `KeySender` reads keys and sends them through `SessionAttachment`. `AttachSignals` turns signals into requests for the writer.

## Requests on another session

A program acts freely on its own session. Before a program in one session types into, reads, attaches to or kills another session, the session process asks the user (decisions of 2026-10-15 and 2026-11-10). A program outside every session, such as Terminal, ssh or the app, acts freely.

- **The caller.** `SocketListener` reads the `PeerProcess` of each connection when it accepts it, before it reads a message: `LOCAL_PEERPID`, `LOCAL_PEERTOKEN`, and `getsid` of that process. The program of a session leads its terminal session, so `SessionRegistry.place(of:)` finds the session whose program has the number of the caller's terminal session. A caller that ended before the check has no terminal session. It counts as unknown, and its request is refused, because it could have run in any session. The registry also keeps the terminal session of each ended session while a process of it lives (`TerminalSessionCensus`), because a job that the program left behind could otherwise act as a program outside every session. Its caller counts as unknown too. No new session can take that number while a process of the old one lives.
- **The question.** `SessionServer` sends an `ApprovalQuestion` through `ApprovalQuestions` to each connection of the app, and the request waits. The request goes on only after an answer that allows it. A session has at most one question that waits, and a second request of it is refused at once, because each alert holds the app. A question ends at the answer, at its time limit of two minutes, when the connection of the caller closes, or when no connection of the app holds it. A later answer changes nothing. The refusal is a `failure` with reason `invalidRequest`, and its message says why.
- **The answerer.** Only a program outside every session that meets `AnswererRequirement` receives questions. The default requirement is OpenRun.app (`ai.cristianvega.openrun`) signed by the team of the session process, checked with `SecCodeCopyGuestWithAttributes` and the audit token. A build with no team, such as an ad hoc one, accepts no program, so each request on another session is refused. `openrun` has no command that answers. `openrun-session --answerer-requirement` sets another requirement, which the tests use to name their own code hash.
- **The model.** `specifications/ApprovalQuestion.tla` models these steps. Its seven controls remove the signature check, the identifier in the answer, the end of a question at its answer, the withdrawal when the caller leaves, the refusal of an unknown caller, the end when no answerer is left, and the time limit.
- **What the rule does not stop.** A program that starts a terminal session of its own, with `setsid`, a tmux server or `launchctl`, counts as outside every session. The rule stops an agent that uses `openrun` plainly. OpenRun is not a security layer against a program that works around it (decision of 2026-10-15). The process identifier can name a later process only after about 100,000 others (see `TerminalSessionProcesses`).
- **The idle exit.** The connection of the app for questions is a client. So the session process does not end at its idle exit while the app runs.

## Facts of a session

The session process keeps the facts of each session in its summary (decisions of 2026-11-10). A client gets them with `listSessions`, or follows them with `receiveSessionChanges`.

| Fact | Where it comes from |
|---|---|
| `name` | `renameSession`, from `openrun rename` or the app. No name means none |
| `title` | The last title that the program set with OSC 0 or OSC 2. An empty title means none |
| `foregroundProgram` | The name of the program that reads the keys (`PseudoTerminal.foregroundState`) |
| `currentFolder` | The current folder of that program. The kernel reports it with every symbolic link resolved, such as `/private/var/...` |
| `branch` | `GitBranch.name(forFolder:)` of the current folder |
| `isInProgress` | See below |
| `lastOutputAt`, `lastInputAt` | The time of the last output of the program, and of the last input from any client |
| `alert` | See below |
| `projectIdentifier` | The deepest project whose folder holds the start folder of the session. The session process resolves the symbolic links of the start folder once, when the session starts. When the projects change, each session whose project changed sends a change |

Every text fact holds no control character and at most 500 Unicode scalars (`SessionSummary.boundedText`), because a program chose it and a client shows it.

**When the session process looks.** It reads the foreground, the folder and the branch when the session starts, once more one second later, and once a second while output or input comes. After two seconds without output or input it looks a last time and stops. A silent session costs no work. So a program that changes its folder or its terminal mode without output and without input after that last look is not seen until the next output or input.

**In progress.** A session is in progress while its program writes output, and for two seconds after the last output. A shell at its prompt does not count: its prompt and the echo of keys are no work. It is also in progress while a program that is not a shell at its prompt runs with the terminal in line mode (`ICANON`), such as `sleep` or a build without output. An agent or an editor reads keys in raw mode, so only its output counts. A shell is at its prompt when its name is a known shell (`sh`, `bash`, `zsh`, `fish`, `dash`, `ksh`, `mksh`, `oksh`, `yash`, `tcsh`, `csh`, `nu`, `elvish`, `xonsh`, `pwsh`), it has no `-c` and no script, and it leads the terminal session or reads keys in raw mode (`SessionActivity`, `InteractiveShell.hasPrompt`).

**The alert.** A session needs the user when its program sends a desktop notification (OSC 9, OSC 777 or OSC 99), rings the bell, or runs `openrun notify`. A notification raises the alert with its text and replaces an alert that is up. The bell raises an alert with no text, only when no alert is up, and not within one second after a typed key, because a shell rings it when a completion fails. Every `input` frame of an attached client ends the alert, because the user is at the session. So focus reports, mouse reports and the answers of the real terminal of a client that relays raw output count as the presence of the user too, and as a typed key for the rule of the bell. `clearSessionAlert` ends the alert too, and a window sends it when the user selects the session. Text from `sendText` does not end it.

**The feed.** `SessionChangeFeed` keeps the latest summary of each session and the connections that watch. A session sends a change only when a fact other than the times and the size changed, and at most once in 250 milliseconds (`Session.changeInterval`), with the newest facts. The times go out with another change, or at the last look after the session went quiet, so output alone does not flood the watchers. A new session comes as `sessionChanged`, and its end as `sessionEnded`. The feed writes to every watcher under one lock, so all watchers see the same order. A watcher that falls behind is a slow client: once 8 MiB wait for it, or a write stalls, the session process ends its connection (see "Limits and deadlines of a client"). A client of the feed must then connect again, ask again, and take the new list in place of all that it knew.

**The rule for callers.** `renameSession`, `raiseSessionAlert` and `clearSessionAlert` follow the place of the caller (see "Requests on another session"). A program outside every session, or a program in the session itself, may change it. Any other caller, also an unknown one, is refused at once with a `failure` with reason `invalidRequest`, and no question goes to the user. The message is "Only a program outside every session, or a program in the session itself, may rename session X." with "alert" or "clear the alert of" in place of "rename".

**The limit.** The session process runs at most as many sessions as the setting `session-limit` allows, 100 by default. A change of the setting applies to the next `createSession`, and the sessions that run stay. `createSession` past the limit gets a `failure` with reason `launchFailed` and the message "The session process already runs 100 sessions, its limit. End a session and try again."

## Projects and settings

The session process is the one owner of the projects and the settings (decisions of 2026-11-10). It loads them when it starts, and it is the only program that writes their files. Every client reads and changes them through the socket.

**The data folder.** It is the folder of the socket, unless `openrun-session --data-folder PATH` names another. A relative path starts at the current folder. So the default socket gives the default data folder, and a session process on a socket in a temporary folder never reads or writes the data of the user. The test harness refuses to start a session process whose data folder is the folder of the user (`UserDataGuard`).

**The start.** A file that cannot be read is set aside (see "Data folder"), a setting that is not valid goes back to its default, and a project without a folder on this Mac holds no session. The log names each of them, with the paths and names private in the unified log. None of them stops the start. When the system cannot read the files at all, the session process starts with no projects or with the defaults, and each change fails until it can read them.

**A change.** `ProjectKeeper` and `SettingKeeper` make each change on a copy, save the copy at once, and keep it only after the save. There is no timer. A save waits for `F_FULLFSYNC`, so a change that a client was told of survives a crash. When the save fails, the state in memory stays as it was, and so does the state on disk: a write replaces the file of the settings in one step, and `ProjectKeeper` writes the old list again, because the projects are two files. The client gets a `failure` with reason `invalidRequest` and the message "The change of the projects could not be saved, so nothing changed: REASON" (or "of the settings"). A change of a setting to its present value writes nothing. Each keeper is an actor on a serial queue of its own, so a save never takes a thread of Swift concurrency that serves output or input, and no attach or typed input waits for a write.

**The feed.** A connection that sent `receiveSessionChanges` gets `sessionList`, then `projectList` and `settingList`, and then each change in the order in which it happened. A change of the projects or the settings sends the whole new list. The keepers give the new list to `SessionChangeFeed` in the step of the change, so every watcher gets the same order.

**The rule for callers.** Any client may read both, add, remove, rename and move projects, and change a setting that is not protected. These are not requests on another session, so no question goes to the user. A protected setting (`session-limit` and `ask-before-unsafe-paste`) changes only for a program outside every session that meets `AnswererRequirement`, the same check as for approval questions. Every other caller gets "The setting NAME is protected. Change it in the settings window of OpenRun." An unknown name and a value that is not valid get the messages of `SettingError`.

**The answerer of an ad hoc build** (decision of 2026-11-10). A session process with a team identifier keeps the rule of "Requests on another session". A session process with no team identifier that runs inside an app bundle, as `Contents/MacOS/openrun-session` of an OpenRun.app with an ad hoc signature does, accepts the main program of that bundle, by the code hash of that program (`cdhash H"..."`). It reads the hash once, at the start, so a later change of the bundle changes nothing until the next start. A program outside an app bundle, such as a development build, accepts nobody, unless `--answerer-requirement` names a program.

**The settings that the session process uses.** It reads six settings itself. `session-limit` applies to the next `createSession`, and `scrollback-limit` to each session that starts after the change. A session that runs keeps its scrollback limit. `claude-code-model` and `claude-code-permission-mode` give the model and the permission mode of a new thread that names none. `claude-code-program` applies to the next start of an agent, and `--agent-program` on the command line of the session process comes before it. `agent-process-limit` applies to the next start too: a higher limit starts the agents of the threads in line, and a lower limit ends no agent. Only the app uses the other settings: `theme`, `font-name`, `font-size`, `option-as-alt`, `new-session-commands`, `open-links-in`, `notifications` and `ask-before-unsafe-paste`. The theme of a session stays with the app for now.

## Process model

- **One session process per user.** launchd starts it as the launch agent of OpenRun.app (see "Launch agent"). It can also run by hand in the foreground, as the tests do. It logs to standard error and to the unified log.
- **One socket.** The default is `~/Library/Application Support/OpenRun/session.socket`. `OPENRUN_SOCKET` or `--socket PATH` overrides it. The flag wins over the variable. A relative path, such as a bare file name, starts at the current folder of the program that reads it. `SocketLocation` makes it absolute at once, so the path that programs get in `OPENRUN_SOCKET` leads to the socket from any folder. It also removes the empty, `.` and `..` parts of every path, relative or absolute. So a long spelling of a short path works, and programs get the short spelling. Symbolic links keep their names. Only a link right before a `..` is resolved first, because the system reads that `..` as the parent of the folder that the link leads to. A `..` after a name that does not exist removes that name. A path longer than 103 bytes after these steps is refused with a clear message, because that is all a Unix socket address holds.
- **The folder of the socket.** Whoever can write to the folder can put a socket of their own at the path. They could then pose as the session process, or keep the real one from starting. So the folder must be a folder, it must belong to the user, and neither its group nor others may write to it. Its access control list may not give that right to anyone else either: an entry that allows a user other than the owner, or any group, to add a file or a folder, delete one, change the list, or take ownership fails the check. Entries that deny pass, and so do entries that allow only reading. To err on the safe side, an entry for a group fails even when the user is its only member, and an entry that only passes on to new files fails too. The check fails closed: an entry whose tag cannot be read, or a permission query that returns an error, refuses the folder in the same way as an entry that lets others change it. Both sides check all of this: the session process before it starts, and every client before it connects (`SocketLocation.checkFolder`). A folder that fails gets a message that names it, and nothing is sent. So `/tmp` and other shared folders do not work. A file in the place of the folder fails with "is not a folder" on both sides. A missing folder passes on the client side, where connecting then fails as usual. The session process creates a missing folder with mode 0700. It sets mode 0700 on the default OpenRun folder when that is a folder, and it recognizes that folder in any spelling of the path (`/./`, `..`, a symbolic link), because it compares resolved paths. A folder chosen with `--socket` keeps its mode and its access control list, and a folder that fails the check stops the start.
- **The user at the other end.** Each side asks the system for the user of the other end of a connection (`getpeereid`, wrapped in `PeerIdentity`). A client refuses a session process of another user before it sends `hello`, and the session process closes a connection of another user before it sends anything. The socket mode 0600 and the folder check keep other users out already. This check holds also when a mode is wrong.
- **Start.** The process takes the lock of the socket first: the file `PATH.lock` next to the socket, held with `flock` for the life of the process. A second process that finds the lock taken refuses to start with "A session process already runs". This makes the check for a live process and the creation of the socket one step, so two processes that start together cannot both survive, and the one that loses never removes the socket of the other. The lock file stays after the process ends, because a lock on a file that someone removed protects nothing. A process that took the lock checks that the file it locked is still the one at the path. The lock file is opened without following a symbolic link. A symbolic link, a named pipe, a folder or another file that is not a regular file at the lock path stops the start with "is not a regular file", and so does a lock file of another user. The process leaves such a file as it is. A lock file that was there before gets mode 0600, so that no other user can open it and hold the lock.
  With the lock taken, a socket file at the path is either stale or belongs to a program that is not a session process of this version. The process connects and says `hello`, and waits 2 seconds for the answer. A `hello`, or a `failure` such as a version refusal, means a live session process, perhaps an older one, and the process refuses to start. A file that nobody listens on is stale, and the process replaces it. A listener that does not answer `hello` in time is no session process: the process logs that it did not answer and replaces its socket file. Before it removes a stale socket file, the process checks that the path still holds the socket it checked (the same device and inode), because the check can take 2 seconds. When the file was replaced meanwhile, the process leaves it, refuses to start, and says that the file was replaced. A file that is not a socket is never deleted.
  The socket is created with mode 0600: the umask is set before `bind`, so the file never has wider permissions. `openrun-session --help` with any other argument is a usage error with exit code 2.
- **Sessions.** A session has a UUID identifier. The command-line tool accepts any unique start of it. A session ends when its program ends, and it then leaves the list. A program that ends by itself leaves its background processes running. `openrun kill` and shutdown end every process of the program's terminal session, also those in other process groups (see `terminate`). A process that starts a session of its own escapes. Both rules are owner decisions of 2026-10-17.
  An attach during the grace period of `openrun kill` gets `attached`, the last screen, and then the exit status, also for a program that ignores SIGHUP. `SessionLifecycleTests.anAttachDuringTheGracePeriodOfKillGetsTheScreenAndThenTheExitStatus` checks this.
  The session creates its `Terminal` and installs the reply handler before it starts the program. The program starts last, so a failure while the session is created never leaves a program running without a session.
- **Threads.** Each client has one reading thread and one serial writing queue. At most 64 clients are connected at once, so the threads are bounded. The sessions and the registry are actors. A `Session` is the only code that touches its `Terminal`.
  A client keeps its place among the 64 until the connection has ended, its reading thread has returned, its writing queue has run its last work, and its socket is closed (`MessageConnection.close`). This includes the up to 2 seconds in which a client that detached still gets what waits for it. So the limit bounds the descriptors and threads of clients too, also when clients attach and detach fast and read nothing.
- **Shutdown.** On SIGTERM, SIGINT or SIGHUP the process removes the socket file first, so no client can connect to a process that is about to leave. It removes the file only when the file at the path is still the one it created (the same device and inode). It keeps the lock of the socket until it exits. It then ends every program and every other process of its terminal session (SIGHUP, with SIGCONT for a stopped group, then SIGKILL after a second; see `terminate`), closes every client, and exits with status 0.
  Each client gets up to 2 seconds to take what still waits for it, such as the output and the exit status of its program. Then its socket closes. So an attached client whose terminal is paused for a moment still gets the exit status. One that takes nothing for 2 seconds loses the rest.
  A client that was already connected can still send `createSession` while the programs end. `SessionRegistry` marks itself as stopping before `terminateAll` first suspends, and `create` refuses from then on, before it starts a program. The client gets a `failure` with reason `launchFailed` and the message "The session process is stopping." The protocol does not change.
- **Slow clients.** A session puts each message on the client's queue. A client that does not request output room loses its connection when more than 8 MiB waits. The client can attach again and gets a fresh snapshot.
  A client that sends `waitsForOutputRoom: true` asks the session to pause output at 7 MiB of queued data. The program can then block on its pseudo terminal. The session resumes when the queue falls to 4 MiB or less. One pause lasts at most 2 seconds in total, however many clients are full. The pause starts when the session first finds a full client, and every wait in it uses the time that remains. A full client that cannot make room by the end of the pause loses its connection. For a snapshot of at least 1 MiB, the client gets a grace period of 30 seconds after attach. The pause can last until the latest such grace ends, but not longer. The grace ends sooner when the client makes room during a wait. When the program ends, the grace ends, and the pause lasts at most 2 seconds from its start. The session waits for one full client at a time, so a full client without grace can stay open until the grace of another client ends. A write that takes no byte for 10 seconds can still end the client during that grace period.
  A faster attached client takes precedence: when it has received at least 4 MiB of output and its queue is at most 4 MiB, a client at the 7 MiB high mark is closed. Progress by a faster client wakes an existing wait and repeats the check. A new client that has not yet received 4 MiB does not take precedence, so the pause can last until its end. The wait holds no actor or thread, so input, detach, termination and other sessions can go on. A client that detaches or a session that ends releases its wait.
  Output counts the bytes of the program's output. A control message counts the bytes of its whole frame, because it is encoded when it is queued. So a client that asks for many large lists of sessions and reads nothing is closed at 8 MiB as well.
  The snapshot, an answer to `readScreen`, and the exit status do not count toward the 8 MiB. A snapshot of a full scrollback in many colors can be larger than 8 MiB alone (a test measured 15 MiB), so counting it would end every attach while the program prints. The output queued after it counts. A connection handles its next request only after its screen answer is written, so screens cannot pile up. A snapshot is at most 64 MiB, the payload limit of one frame (see "A snapshot that fits in one frame").
  The cut applies only when output already waits for the client. A first control frame that is larger than 8 MiB, such as a very large list of sessions, is queued whole. The cut applies from the next frame on. An output frame is at most one read of the pseudo terminal, so only a control frame can be this large.
  A write that takes no byte for 10 seconds also ends the client. So a client that does not read such a first frame ends after 10 seconds.
- **Output flow.** The session parses output at its own pace and pauses for an opted-in client as described above. When it is slower than the program, the pseudo terminal stops reading (see `markOutputConsumed`), so memory stays bounded.
- **Input flow.** Input of a client that is there is never dropped. The backlog of input that a program has not read holds 8 MiB (see `type`). Past that, typed input waits for the program:
  - `sendText` is answered with `acknowledged` once the whole text is in the backlog. When the program ends while the text waits, the answer is a `failure`. Text that was acknowledged reaches the program, also after its client has left.
  - Input frames of an attached client go to the program in order, one after another. The server does not wait for them before it reads the client's next message, so the client can still detach while its program reads nothing.
  - `sendText` on a connection goes in behind the input frames that the same connection sent before it.
  - When a client detaches or leaves, its typed input that has not gone to the program is dropped: the frames that wait for room, and the pieces in the backlog that have not started to go out. Its requests that were read and not handled yet are dropped too. A client that leaves therefore holds no memory, however often it comes and goes.
  - The reading thread of a client reads at most 1 MiB ahead of the messages that are handled, and at most 1024 messages. Each message counts the size of its frame. The thread reads the length field and the kind byte, waits for room, and only then reads the payload. Past the limit, the socket fills up and the client's own sends wait. A client that sends faster than its program reads, or sends large requests faster than they are handled, cannot make the session process grow.
  - Input that the program does not read stays in the read-ahead until it is in the backlog, so it can fill the read-ahead for as long as the program reads nothing. One control frame of at most 1 KiB may then still be read, into a reserve, so a `detach` (or a `resize`) right behind the full read-ahead is handled at once. Input never takes the reserve, and the reserve holds one frame at a time, so the read-ahead stays within 1 MiB and 1024 messages plus that one frame. A `detach` that comes behind more input than the read-ahead holds still waits behind that input, and so does a `detach` behind a `sendText` that waits for room. Such a client can close its connection instead.
  - A reading thread that waits for room checks every 100 milliseconds whether its client has left. A client that vanishes while its input waits is then detached at once, so it no longer keeps the session silent for queries (see "Query replies").
  - A client that shuts down only its sending side (`shutdown` with `SHUT_WR`) has left too, as the protocol reads the end of a client's frames. macOS reports such a socket as closed by the peer even while unread bytes wait, so a waiting reading thread notices it within 100 milliseconds as well. The client is detached, its waiting input is dropped, and it still reads the clean end of the connection.
  - A wait holds no actor and no thread of Swift concurrency. Only the reading thread of that one client waits. Other sessions, other clients, `killSession`, `detach` and shutdown go on. When the program ends, every wait ends with it.

### Limits and deadlines of a client

`ConnectionLimits` holds them, apart from the limit of connections that wait for the server, which is `SocketListener.waitingConnectionLimit`. Each one ends or refuses a client that would otherwise hold memory, a thread or a descriptor without end.

| Limit | Value | What happens |
|---|---|---|
| Clients at once | 64 | A client past the limit gets a `failure` (reason `invalidRequest`) in place of `hello`, and the connection closes. A client counts until its socket is closed |
| Hello | 5 seconds | A connection that has not delivered its whole `hello` by then is closed |
| A frame that stalls | 30 seconds | Between frames a client may wait as long as it likes. Once a frame has started, each part must follow within 30 seconds, or the client is closed |
| A write that stalls | 10 seconds | A write that takes no byte for 10 seconds ends the client |
| Closing | 2 seconds | A closing client gets this long to take what waits for it. Then the socket closes, also when a write is stuck |
| Output that waits | 8 MiB | See "Slow clients" |
| Output room | 7 MiB high mark, 4 MiB low mark, 2 seconds in total | One pause lasts at most 2 seconds, however many opted-in clients are full. A client that has not made room by then loses its connection. A snapshot of at least 1 MiB gives its client up to 30 seconds. See "Slow clients" |
| Read-ahead | 1 MiB and 1024 messages | See "Input flow" |
| Reserve of the read-ahead | One control frame of at most 1 KiB | Read past a full read-ahead, so a client can detach. See "Input flow" |
| Accept after an error | 250 milliseconds | When the process has no descriptor left (EMFILE), the listener waits before it accepts again |
| Connections that wait for the server | 64 | The listener accepts each connection and hands it to the server, which takes it at once. A connection that waits is outside the client limit and has no hello deadline yet. So while the server is busy, at most 64 wait, and the listener closes each connection past that at once, before it reads or sends a byte. 64 is also the length of the listen queue, so the process holds no more waiting connections than the system queues for it |

A frame body is read as its bytes arrive. A frame that announces 64 MiB and sends little holds only what came.
On macOS a failed accept drops the connection that waited. Without the pause, the listener dropped every waiting client at once when the process ran out of descriptors. With it, at most one is dropped in each pause, and the others are served when descriptors free up.
A write uses the socket's send timeout (`SO_SNDTIMEO`) for its deadline, because `MSG_DONTWAIT` does not keep a send on a Unix socket of macOS from blocking. Every send passes `MSG_NOSIGNAL`, because the system refuses `SO_NOSIGPIPE` on a socket whose peer has already closed.

## Agent threads

An agent thread is a chat with one agent, one account and one model (proposal 1 of 2026-11-10).
Five modules hold the parts: `AgentConversation`, the model; `ClaudeCodeAgent`, the adapter of Claude Code; `CodexAgent`, the adapter of Codex; `AgentProgram`, the process on pipes; and `AgentThreads`, the records.
The session process joins them for Claude Code (see "Threads in the session process"), and the app shows a thread as a chat. Codex does not run in a thread yet.

### The event model

An adapter turns each line of its agent's output into `ConversationEvent` values. The kinds are the same for every agent (`ConversationEventKind`): the start of the agent, a user message, the start and end of a turn, text and thinking, tool calls with their input, output, result and refusal, file changes, the tasks of sub-agents, permission requests, the usage of the account, notices, the status of the agent, the end of its process, and a line that this version cannot read.
Each event keeps the start of its source line, at most 16 KiB (`SourceLine`), so a later version can read again what this one did not understand (proposal 4).
A line of a kind that the adapter does not know becomes an `unknown` event, and the stream goes on. So do a line that is not JSON, a line longer than its limit, and a line that the output cuts short.

`Transcript` is a pure value. It applies the events in order and gives the items that a chat shows, and the state of the thread for the list of threads (`ThreadState`). The same events always give the same items with the same identifiers, so the session process, the app and a test agree.
Text that streams grows one item, and the complete text replaces it. The end of a turn closes the items that are still open.
`TranscriptLimits` bound its memory, whatever the agent sends: at most 5,000 items and 8 MiB of text, 1 MiB for one message, and 256 KiB for one detail, such as the output of a tool. The oldest items go first.

### The Claude Code adapter

`ClaudeCodeLaunch` makes the command line. Each flag has a reason:

| Flag | Why |
|---|---|
| `-p` | Runs without the terminal interface. |
| `--input-format stream-json` | Takes user messages as JSON lines on standard input, so one process takes many turns. |
| `--output-format stream-json`, `--verbose` | Writes every event as one JSON line. `stream-json` output needs `--verbose`. |
| `--include-partial-messages` | Streams text and tool input as they come, not only when a message is complete. |
| `--replay-user-messages` | Echoes each user message with its identifier, which marks the message as taken. |
| `--model`, `--permission-mode` | The model and the mode of the thread. `bypassPermissions` is never given. |
| `--permission-prompts none` | Claude Code asks nothing itself. Every question goes to the hook. |
| `--settings` | Adds the `PermissionRequest` hook for this run only, with `"onFailure": "block"` and a limit of 24 hours. The user's own settings, hooks, plugins, MCP servers and CLAUDE.md stay in force. |
| `--session-id`, `--resume` | `--session-id` starts a new conversation with the identifier that OpenRun chose. `--resume` continues it at every later start. |

`ClaudeCodeEnvironment` removes the variables that make Claude Code act as a run inside another run, such as `CLAUDECODE` and `CLAUDE_CODE_MESSAGING_*`. `CLAUDE_CONFIG_DIR` stays, because it selects the account.
`ClaudeCodeUserMessage` makes the line of a user message, with text and images. OpenRun sends no control request.

`ClaudeCodeOutputDecoder` takes the output in pieces of any size and gives events. A line can hold at most 16 MiB.
Text, thinking and tool input stream with item identifiers made from the message identifier and the block index. The complete block of a message takes the identifier of the first streamed block of the same kind. Thus a block that streamed nothing, such as hidden thinking, does not shift the others.
A `result` line ends the turn: done, stopped when Claude Code reports an abort, or failed with the error text. A line from a sub-agent becomes a message of its task.

The hook program, `openrun permission-request`, reads `ClaudeCodePermissionHookRequest` from its standard input and writes `ClaudeCodePermissionHookAnswer` to its standard output.
A refusal by a hook that failed, which Claude Code reports with the type of a refusal by the hook, has the reason `unanswered`, not `user`.
The request names no tool call. `ClaudeCodeToolCallMatcher` finds the call that the request is for: the oldest open call with the same tool name and input. The end of a turn or of the process clears the open calls, and it keeps at most 256.

`ClaudeCodeHistoryLocation` finds the history file of a conversation: `projects/FOLDER/IDENTIFIER.jsonl` in the configuration folder. `FOLDER` is the working folder with each character that is not an ASCII letter or digit changed to `-`. When that file does not exist, it tries the real path of the folder, and then every project folder.
`ClaudeCodeHistoryReader` reads that file from its end, one page of 256 KiB at a time, so a chat shows the newest turns first and never reads the whole file. It leaves out the lines of sub-agents and the lines that Claude Code adds for itself. OpenRun keeps no copy of the history (proposal 3).

### The Codex adapter

One `codex app-server` serves all threads of one account (decision of 2026-11-10).
`CodexAccountServers` keeps one `CodexAppServer` for each account: its `CODEX_HOME` folder, or the default account of the login shell. A server starts when a call needs it, and it ends when no thread and no call uses it. A read of the account or of the usage without an open thread starts a server for that read alone.
`CodexAccountServers.shutDown` cancels the start of a server whose handshake has no answer yet, so it returns within a few seconds whatever the app-server does.
The tasks of a server hold it and its `AgentProgram` weakly. When nobody holds the server, its threads or its `CodexAccountServers` any more, the program goes too, and its group gets SIGKILL, also without `shutDown`.

The app-server speaks JSON-RPC on its standard input and output: one JSON object on each line, without the `jsonrpc` member.
OpenRun's requests have whole-number identifiers. A cancel of the caller ends the wait for an answer at once. An answer to a request of Codex carries its identifier as the JSON text that it came in, so that a number above 2^53 does not change. Each request waits for its answer for at most `answerTimeLimit`, 60 seconds by default. When the output ends, every request that waits fails with `connectionEnded`, and so does every later one.
A line that is not JSON, that has an unknown method, that is longer than 16 MiB, or that the output cuts short becomes an `unknown` event of each open thread, and the connection goes on.
The handshake sends `initialize` with the name and the version of OpenRun and `capabilities.experimentalApi: true`, which the stop needs. Then it sends `initialized`.

| Method | What OpenRun sends |
|---|---|
| `thread/start` | The folder, the model, `approvalPolicy: "untrusted"`, the sandbox `workspace-write` or `read-only`, and the effort as the configuration value `model_reasoning_effort`. |
| `thread/resume` | The same, with the identifier of the thread and `excludeTurns: true`. The history pages give the earlier turns. |
| `turn/start` | The text, each image as a data URL, `clientUserMessageId`, and a new model, `effort` or `sandboxPolicy` for this turn and the later ones. |
| `turn/interrupt`, `thread/backgroundTerminals/list`, `thread/backgroundTerminals/terminate` | The stop. |
| `thread/turns/list` | A page of the history, with `itemsView: "full"`. |
| `account/read`, `account/rateLimits/read` | The account and its usage. |
| `thread/unsubscribe` | The close of a thread. The close does not wait for the answer, which has a time limit of 2 seconds. |

Each notification goes to the thread that it names. A notification without a thread, such as `account/rateLimits/updated`, goes to every open thread.
Codex can send lines of a thread before its answer to the start or the resume. The server keeps the last 64 such lines, and gives them to the thread after its first event. A thread that closed is different: Codex can send its lines until it takes `thread/unsubscribe`. The server drops them until that request has its answer or its time limit of 2 seconds, so a later resume of the thread does not show them again.
`CodexEventMapper` gives the events of each thread: the text as it streams and complete, reasoning only as the fact that it happens, commands with their output and end, file changes with their path, kind and diff, the start and end of each turn, the tokens, the usage, warnings and errors. A notification that a chat does not show becomes a status event, and a method that the mapper does not know becomes an `unknown` event. Each event keeps its line.
Codex gives the tokens of the thread as a total. The end of a turn carries the difference since its start, and the input leaves out the input from the cache, as with Claude Code. The kind of the error of a failed turn, such as `modelNotFound`, comes as a status event beside the end, because `TurnEnd` has no field for it.
The events of a thread go through a channel. The reader of the app-server never waits for a caller, so a thread that nobody reads cannot hold back the answers of the other threads of the account. At most 1,024 events of a thread wait for its caller (`CodexServerOptions.eventLimit`), and at most 8 MiB of the lines that gave them (`eventByteLimit`). The pieces of one streamed item that wait, such as the text of an answer or the output of a command, join into one event (`CodexEventPieces`), so a burst of small pieces counts once. One event of any size can wait alone. When more come, the server closes the thread: its last event is an error notice, its requests end declined, and Codex gets `turn/interrupt` and `thread/unsubscribe`. The memory thus stays bounded.

Codex asks before a command or a file change with `item/commandExecution/requestApproval` or `item/fileChange/requestApproval`. Each request becomes a `permissionRequested` event with the identifier `ITEM/REQUEST`.
A command shows the command, its folder and the reason. A request for a file change has no diff, so it takes the paths and the diffs from the start of the item with the same identifier. When the start comes after the request, the request shows again with the diff.
Only `CodexThread.answerPermission` accepts a request: allow sends `accept`, and deny sends `decline`. A second answer sends nothing. A second request with the identifier of a request that waits gets `decline` at once, and the thread gets a warning.
OpenRun declines a request after `approvalTimeLimit`, 10 minutes by default, at a stop, and at the close of its thread. When the app-server ends, no answer can go, and the request ends as declined. Codex runs nothing that waits (result 3 of the prototype). When Codex withdraws a request with `serverRequest/resolved`, it ends without an answer.
Every other request of the app-server, such as a question for the user or a tool call of the client, gets the error -32601, and the thread gets a warning.

`CodexThread.stop` declines the requests that wait and sends `turn/interrupt`. It also stops a turn whose `turn/started` has not come yet, by the identifier in the answer to `turn/start`. When that answer has not come either, the stop waits for it, for at most 5 seconds, because only the answer names the turn. It waits at most 5 seconds for the end of the turn. A command that runs goes on after the interrupt as a background terminal (result 8 of the prototype), so the stop lists the background terminals of the thread and ends each one.
These methods are experimental. When Codex refuses them, the turn still stopped, and the thread gets a warning that a command may still run.
The output and the end of such a command come after the end of its turn. They become status events, so that the chat does not show the thread as busy again.

`readAccount` gives the kind of the account and its plan. The e-mail address is for display only: the description of `CodexAccount` leaves it out, and OpenRun never logs it.
`readUsage` and `account/rateLimits/updated` give a `UsageReading`. Each window has a name from its length, such as `seven_day` for 10,080 minutes and `5_hour` for 300, and the kind of a limit that the account reached is the status of the reading.

`CodexThread.historyPage` reads a page of turns with `thread/turns/list`, newest page first, and the cursor of the page gives the next older one. The events of a page are oldest first, from the same mapper as a live turn.
Codex keeps only the user message of a turn that stopped while text streamed. Such a turn gets a notice that the answer before the stop is not in the history.

Codex writes some files by itself, and OpenRun edits none of them.
`thread/start` in a new folder writes `[projects."FOLDER"] trust_level = "trusted"` into `config.toml` in the `CODEX_HOME` of the account. OpenRun does not remove the entry.
Codex also writes the rollout file of each thread under `sessions/` in the same folder. `thread/resume`, `codex resume` and the history read it.

### The process on pipes

`AgentProgram` starts an agent program with `posix_spawn` on three pipes, in a process group of its own. The program inherits no other descriptor, and it gets only the environment of its `AgentProgramLaunch`.
The output comes as an `AsyncStream`. Reads stop while more than 4 MiB waits that the reader has not marked as consumed, and they start again below 1 MiB. The program then waits in its own write. The newest 64 KiB of standard error stay for a message when the program fails.
Writes to standard input do not block a thread. They wait in order until the pipe takes them, and they fail when the program ends.
`send(signal:)` signals the whole group, so SIGINT stops a turn with the commands that the agent started. `terminate` sends SIGTERM, and SIGKILL after a grace period.
When the program ends, `ProcessGroupReaper` waits for it without reaping it. The zombie keeps the number of the group, so no signal can reach another program. It ends the rest of the group: SIGTERM, then SIGKILL after one second, for at most two seconds. Then it reaps the program. No zombie stays.
A stopped program has not ended, and `terminate` also sends SIGCONT, so a stopped program acts on SIGTERM. The reaper does no work while the program runs: it looks one time at the start, and then waits for the exit event.
An `AgentProgram` that nobody holds any more sends SIGKILL to its group, so a forgotten object cannot leave an agent behind.
The pipe ends move above descriptor 2 before the program starts, so the pipes work also when the parent has 0, 1 or 2 closed. The test program `agent-program-probe` checks this in a process of its own.

`LoginShellEnvironment` runs the user's login shell one time as `SHELL -l -i -c`, with standard input closed, and reads the environment that it prints between two markers. The shell gets 10 seconds and 1 MiB of output. On a failure the caller uses its own environment.

### The fake agent

The tests never start the real `claude`, because it spends the owner's subscription.
`Tests/FakeAgent` builds the program `fake-agent`. It refuses any command line that `ClaudeCodeLaunch` does not make, and the variable `CLAUDECODE`, with the exit status 64.
It answers each user message line with a recorded turn from `Tests/ClaudeCodeAgentTests/Fixtures`. It puts in the identifier of the conversation and echoes the user message as Claude Code does. `FAKE_AGENT_MODE` selects a special case: a conversation that does not exist, a turn that waits for SIGINT, a line cut short, a crash, or a flood of text.
Without `-p`, the fake agent is the program in a terminal session, as Claude Code is for Open in Terminal: it writes one line, adds the lines of the file in `FAKE_AGENT_TERMINAL_TURN` to the history of its conversation under `CLAUDE_CONFIG_DIR`, and waits for the end of its input.
`FakeAgentTests` run it through `AgentProgram`, the decoder and a transcript.
The fixtures come from real runs of Claude Code 2.1.322, with everything that describes the owner removed. `FixturePrivacyTests` scans every file of the four modules, their tests, the fake agent and the fake app-server for identifiers that are not made up, long opaque values, home folders, e-mail addresses and the words that were removed.

### The fake app-server

The tests never start the real `codex`, because it spends the owner's subscription and writes into the owner's Codex configuration.
`Tests/FakeCodex` builds the program `fake-codex`. It takes only the argument `app-server`, and refuses any other command line with the exit status 64.
`FAKE_CODEX_SCRIPTS` names the recorded exchanges of `Tests/CodexAgentTests/Fixtures`, which it plays one after the other. Each step is a line of OpenRun that it checks, or a line of the app-server that it writes. A line of OpenRun that the step does not expect ends it with the status 2. `Tests/CodexAgentTests/Fixtures/README.md` describes the form.
Special steps play an answer that never comes, the end of the connection while an approval waits, a line cut short, and a crash. While an approval waits for the end, any line of OpenRun ends the fake with the status 3, so a test sees an answer that should not go.
After the last step, each request gets an empty answer, and the end of its input ends the fake.
The tests in `CodexAgentTests` run it through `AgentProgram`, the server and a transcript. Faster tests play the same fixtures on a transport in memory.
The fixtures come from real runs of Codex 0.167.0, with everything that describes the owner removed. `FixturePrivacyTests` scans them too. Its rules for Codex allow only the made-up forms of the identifiers of reasoning items, credits and commands, and only the made-up date of a rollout file.

### Threads in the session process

The session process owns the threads, as it owns the sessions, so the agent of a thread goes on while no window shows it.

- **Records.** `ThreadList` of `AgentThreads` holds one `ThreadRecord` for each thread: the agent, the identifier of its conversation in the history of the agent, the account, the folder, the model, the permission mode, the name and the title. `ThreadRegistry` keeps the list in `threads.json`, at most 1,000 threads, and keeps a change only after its save. The folder of a new thread must exist. The registry keeps its real path (`realpath`), so the folder matches the folder of its project. A thread that names no model or permission mode gets the ones of the settings `claude-code-model` and `claude-code-permission-mode`.
- **The runner.** A thread comes into use with its first message or its first attach. `ThreadRunner`, an actor, then holds its `Transcript`, its `ThreadEventBuffer` and its clients. The agent starts with the first message, through `ClaudeCodeLaunch` and `AgentProgram`, in the folder of the thread. The first start gives the agent the identifier of the conversation, and each later start resumes it.
- **The start of an agent.** `AgentLaunchProvider` reads the environment of the login shell of the user once for each start of the session process, at the first need, because launchd gives the session process a short one. It finds the program of the setting `claude-code-program`, `claude` at first, in the `PATH` of that environment, and it never logs the environment. The agent also gets `OPENRUN_THREAD`, the identifier of its thread. `--agent-program PROGRAM` names another program, and `--own-environment-for-agents` gives the agents the environment of the session process. The tests use both for the fake agent.
- **Messages.** A message goes to the standard input of the agent as one line. While a turn runs, a message waits in the runner, and the next one goes out when the turn ends. At most 16 messages wait. The start of the first message becomes the title of the thread.
- **Events.** Each line of the output becomes events (`ClaudeCodeOutputDecoder`). The runner gives each event to the transcript, to the buffer, and to each attached client as JSON in a `threadEvent` frame. Only this actor touches the three, so a client that attaches gets the kept events and then each later event, with no gap and no repeat. The agent waits in its own write while the runner has not dealt with a chunk.
- **The buffer.** `ThreadEventBuffer` holds at most 4 MiB of events for each thread. Whole turns go first, the oldest first, so the events that stay start at the start of a turn and give a transcript with no half item. OpenRun keeps no lasting copy of the events (proposal 3).
- **History.** `readThreadHistory` gives a page of the earlier turns (`ThreadHistory`). The session process finds the history file of Claude Code in the folder of its settings (`ClaudeCodeHistoryLocation`) and reads it in place, off its actors, with `ClaudeCodeHistoryReader.previousTurns`: about 256 KiB of lines, and then the lines back to the message of the user that starts their turn. It copies the file nowhere. The answer names the place where the page starts, and the next request gives it back, so no reader stays open between two pages. A runner whose conversation had turns before it came into use, as after a restart of the session process, tells a client that attaches that earlier turns exist.
- **Open in Terminal.** `openThreadInTerminal` stops the headless agent, waits for its end, and starts Claude Code on the same conversation in a new terminal session, in the folder of the thread: `--resume` (or `--session-id` for a thread with no turn), the model and the mode, with no headless flag and no hook, because the user answers in the terminal (`ClaudeCodeLaunch.terminalArguments`). A conversation has one owner at a time: a second process would split it in two (proposal 6). So the summary of the thread names the session, and the thread refuses a message until the session ends. `returnThreadFromTerminal` ends the session, and so does the user who leaves the agent there. `SessionChangeFeed` tells the registry of each session that ends. The registry then reads the lines that came into the history file since the terminal started (`ClaudeCodeHistoryReader.events(inFileAt:after:)`, at most the last 4 MiB) and gives their events to the runner, so the turns of the terminal show in each chat as turns, in their order.
- **Stop and end.** A stop sends SIGINT. Claude Code then ends its turn and its process, and the next message resumes the conversation. The messages that waited do not go out, and a notice in the chat says how many. A process that does not end in 5 seconds gets SIGTERM and then SIGKILL. The end of a process gives a `processEnded` event with its status and the end of its standard error. The close of a thread ends its process and removes its record. The conversation stays in the history of the agent.
- **Quiet time and the limit.** A process that had no work for five minutes ends, and the next message starts a new one, which resumes the conversation. A turn that runs keeps its process. At most eight agent processes run at one time (`AgentProcessSlots`, the setting `agent-process-limit`), because one idle Claude Code uses 300 to 400 MB. When every slot is taken, the agent that had no work for the longest time ends to make room. When every agent works, the message waits, the chat says so, and the thread gets the slot of the next agent that ends. A process that OpenRun asked to end takes no new message: the message waits for the end and then starts a new process.
- **Model and mode.** `changeThread` gives a thread another model or permission mode. Claude Code takes both only at its start, so a process with no work ends at once, and a process in a turn ends after the turn. The next message starts a process with the new values, which resumes the conversation. A thread can take each mode up to the one of the setting `claude-code-permission-mode`, in the order of `ClaudeCodePermissionMode.fromStrictestToWidest` (proposal 9). So the user can leave plan mode in the chat, and a wider mode needs the settings window. A new thread follows the same rule, and a stricter setting brings each wider thread down to it.
- **The lists.** The registry gives the `ThreadSummary` of each thread to `SessionChangeFeed`: the facts of the record, the state of the transcript (`idle`, `inProgress`, `needsUser`, `finishedTurn` or `failed`), whether the process runs, the count of the messages that wait, and the project of the folder. Only a watcher that asked with `includesThreads` gets them.
- **Who may use the threads.** Only a program outside every session and every thread may send a request of the threads (decision of 2026-11-10), so an agent cannot drive another agent without the user. `ProcessAncestry` finds the agent of a thread among the parents of the caller.

### The permission requests of a thread

Claude Code starts with a `PermissionRequest` hook, `openrun permission-request`, which blocks the tool when the hook fails (`ClaudeCodeLaunch`). The route follows proposal 2.

1. The agent wants a permission and runs the hook. `PermissionRequestCommand` sends the request of the agent to the session process as `requestToolPermission`.
2. The session process takes the request only from a program that the agent of a thread started. It finds the thread from the parents of the caller, never from a field of the request.
3. The runner emits a `permissionRequested` event, the state of the thread becomes `needsUser`, and the request waits, at most 24 hours.
4. The app shows the request in the chat. Its answer goes as `answerToolPermission`. The session process takes it only from the signed OpenRun.app outside every session and every thread, as for an approval question.
5. The hook gets `toolPermissionAnswer` and prints the decision for the agent.

A stop, the end of the agent, the close of the thread, the time limit, and the end of the connection of the hook all end the request with a denial. The hook exits with 0 and a denial on every failure of its own, so no failure grants. The `openrun` tool has no command that answers.

`specifications/ThreadPermission.tla` models this route with three requests, two threads and three answerers: the trusted app, a signed app that an agent started, and a program with no signature. Its safety checks say that the session process allows a request only with the answer of the user, that a tool runs only with that answer, that a request which has ended is never allowed later, and that a chat shows only the requests of its own agent. Seven controls each remove one protection, and TLC finds the violation that the control names: the signature check, the place check, the caller check, the thread from the caller, the final answer, the block when a hook fails, and the time limit. The model takes as given that Claude Code blocks the tool when the hook fails or prints a denial, which the prototype measured, and that `ProcessAncestry` finds the agent of a caller.

### Chat view

`ChatView` shows one thread. It knows no agent, no process and no socket: it uses no `SessionProtocol`, `SessionConnection` or `SessionProcess`, and no module of the main window.
The host makes a `ChatViewController` with the `ChatThreadFacts` of the thread, gives it each new `Transcript` with the `TranscriptChange` of the event, and puts its view in the pane. The controller asks the host for every action through `ChatViewControllerDelegate`: send, stop, the answer to a permission request, a change of the model or the mode, the earlier history, Open in Terminal, and a link. It never acts by itself.
`ChatAppearance` holds the colors and the fonts. Its default is Graphite, the colors of `TerminalTheme`, and the code font is the font of the terminal.

`TranscriptRowBuilder` turns the items into rows. An agent message splits into text rows and code rows, and a run of tool calls is one row. It parses again only the messages that a change names.
`TranscriptView` keeps a view only for the rows near the screen. `RowLayout` keeps the height of each row, estimated until the row comes near the screen, and the tops as a running sum from the first row that changed. So an update at the end costs the same at 10,000 items as at 10.
While the user is at the bottom, the view follows the newest row. Otherwise the row that the user reads stays at its place when rows above it change their height or open.
Each row uses TextKit 1, because TextKit 2 does not show the tables of Markdown. `MarkdownLayoutManager` draws inline code as a box around the letters.

The composer keeps a draft for each thread in memory. While a turn runs, a sent message waits, and the next message joins it.
Find (Command-F) searches the text of every row, also the rows with no view, and the newest match comes first.

The tests draw pictures of the chat only when `OPENRUN_RENDER_OUTPUT` names a folder. They draw into a bitmap, so they work while the screen is locked, but a picture shows no shadow and no running animation.
`ChatReplayTests` play the recorded turns of Claude Code one event at a time. `ChatSpeedTests` measure the chat in a debug build on an M-series Mac: an update of a stream on 2,000 items takes about 4 ms, the first show of 10,000 items 80 ms, the open of an output of 10,000 lines 5 ms, and a step of a resize 1.3 ms. A full draw of the pane into a bitmap takes about 34 ms. A frame on the screen draws only the rows that changed.

## Launch agent

OpenRun.app registers the session process as a launch agent with SMAppService (`LaunchAgentRegistration`). The property list is `Bundle/ai.cristianvega.openrun.session.plist`, and the bundle script copies it to `Contents/Library/LaunchAgents`. A test compares it with `LaunchAgentNames`.

- **Start on demand.** The agent has the Mach service `ai.cristianvega.openrun.session` and no socket of launchd, so launchd starts it when a message reaches the service, not at login and not at registration. A client connects to the default socket as before. When nothing listens there, or the connection closes before `hello`, the client sends one wake (`SessionWake`) and connects again. The session process answers a wake only after its socket listens (`SessionWakeService`). A wake fails after 15 seconds without an answer, because a registration that launchd cannot start never answers. A nondefault socket chosen with `--socket` or `OPENRUN_SOCKET` gets no wake.
- **The flag.** launchd runs `Contents/MacOS/openrun-session --launch-agent`. With the flag, the process ignores `OPENRUN_SOCKET`, answers wakes, and has the idle exit. A process that was started by hand gets no Mach service, and its socket still serves.
- **Idle exit.** With the flag, the process ends with status 0 after 30 seconds with no session and no client (`IdleExit`). launchd holds a start for 10 seconds after a run shorter than 10 seconds, so the time is longer than that. `SessionServer.closeWhenIdle` checks the clients, waits for the registry, checks the clients again, and closes the socket with no wait in between. The wake service stops just before, so a later wake waits in the Mach port for the next process. A connection that the listener took just before the close closes before `hello`, and its client wakes the next process. `specifications/SessionLifecycle.tla` models the idle exit.
- **Crash.** `KeepAlive` with `Crashed` makes launchd start the agent again after a crash, and not after a clean exit such as the idle exit. Until milestone 5 restores sessions, the restarted process has no session and ends when it is idle. `ProcessType` `Interactive` gives the agent the resource limits of an app, because agents run builds in sessions.
- **The app.** At its start, the app registers the agent when the status is `notRegistered` or `notFound`, and then connects once (`LaunchAgentSetup`). Each `hello` of that connection, the first and the one after a wake, has a time limit of 15 seconds (`SessionWake.answerTimeLimit`). A session process that takes the connection and never answers ends the setup with a message that names the limit, and File > Retry Session Process is on again. When the agent needs approval, or the user turned it off in System Settings, the app tells the user once and waits. A wake that times out gives no evidence that launchd refused the program: a socket path that blocks the session process also times out. The app reports the time limit and tells the user about two menu items. File > Retry Session Process runs the setup again. File > Register Session Process Again unregisters the agent, registers it, and then runs the setup, which asks for approval when needed and connects. It always asks first, because a new registration can end the sessions that run now. Cancel changes nothing. An agent that is not registered has nothing to remove, so the item only registers it. If the unregistration or the registration fails, the app shows the failure question, and Retry Session Process is on. When that happens after the app was ready, the windows that exist stay open, and a later success opens a window only when none exists. The app never registers the agent again by itself. A user who changed the build can also turn the agent off and on in System Settings.
- **Bundle.** `scripts/build-application.sh FOLDER` builds OpenRun.app with `Contents/MacOS/OpenRun` (the program `openrun-application`), `Contents/MacOS/openrun-session`, `Contents/Helpers/openrun` and the property list of the agent. It signs with an Apple Development identity, or ad hoc with `OPENRUN_SIGNING_IDENTITY=-`. With an ad hoc signature, launchd ties the agent to the code hash of `openrun-session`, so each build that changes it needs a new registration.
- **Settings for tests.** `OPENRUN_TEST_WAKE_SERVICE_NAME` names another Mach service, and `OPENRUN_TEST_IDLE_EXIT_MILLISECONDS` a shorter idle time. Only the tests and `scripts/check-launch-agent.sh` set them, so they never touch the agent of the installed app. The session process reads them only with `--launch-agent`, and a client reads the first one.

## Data folder

OpenRun keeps its data as readable JSON in `~/Library/Application Support/OpenRun`, the folder of the socket (`DataFolder.defaultPath`).
A test keeps `DataFolder.defaultPath` and `SocketLocation.defaultPath` in step.
The session process keeps its data in the folder of its socket, or in the folder after `--data-folder`. See "Projects and settings". So the tests, which use a socket in a temporary folder, keep their data there.
The default folder has mode 0700, also when it exists, and each file has mode 0600.
A folder that a caller named gets mode 0700 only when `create` makes it. Otherwise it keeps its mode, as the folder of a socket from `--socket` does.

| File | What it holds | Scope |
|---|---|---|
| `projects.json` | The projects in the user's order: the identifier of each and the name that the user gave | Can sync |
| `project-folders.json` | The folder of each project on this Mac, by identifier | This Mac |
| `settings.json` | The settings that differ from their defaults, each a key beside `format`, and the settings of a later build | Can sync |
| `layout.json` | The rows of the sessions list and their splits, which the app keeps | This Mac |
| `threads.json` | The agent threads: the agent, the conversation, the account, the folder, the model, the permission mode, the name and the title of each one. The conversation itself stays in the history of the agent | This Mac |

Data that can sync and data of this Mac never share a file, so a later sync takes whole files.
Each file is one JSON object with its keys sorted and one key on each line.
Its `format` key holds the format number, so a later build can still read an older file.

A write goes to a temporary file in the same folder, `.NAME.UUID.writing`, with mode 0600 from the start.
After a full flush of the disk (`F_FULLFSYNC`), a rename puts it in the place of the old file. So a reader sees the old file or the new file, never a part.
`DataFolder.create` removes a temporary file that a crash left, once it is older than one minute.

A file that this build cannot read is never deleted and never written over.
That is a file that is not strict JSON (RFC 8259) in UTF-8, that has no format number or the format of a later build, that does not decode, or that is larger than 16 MiB.
Foundation's decoder also takes a byte order mark, a comma before a closing bracket, `01`, a raw tab in a string and `\q`. `DocumentTextScanner` refuses them, at most 64 levels deep, so every file that OpenRun writes is strict JSON and keeps each unknown key.
It gets the name `NAME.unreadable-TIME.json`, with the time in UTC such as `20261110T093000Z`, and the caller starts from the defaults.
When the system cannot read or move a file, the load throws.
A write reads the file first, sets it aside when this build cannot read it, and throws when it cannot read or set it aside.
So no save replaces data that the load did not read.

A write keeps each key at the top of the file that the document does not name in `knownKeys`, such as a key of a later build.
`ObjectMembers` keeps the exact text of its value, because a decoder turns a number into a Double and loses digits.
Keys deeper in the file are not kept.

`ProjectStore` writes `project-folders.json` first and `projects.json` second.
A load adds a folder with no entry at the end of the list.
It keeps an entry with no usable folder but does not show it, and a save writes such entries after the others.
So the projects stay when only `projects.json` is lost, and the names, identifiers and order stay when only `project-folders.json` is lost.
A crash in a remove between the two writes leaves such a hidden entry. A later sync will bring entries of this kind from other Macs.
`ProjectList.projectsWithoutFolder` gives these projects with their identifiers and names, so a client can show them, and `remove(identifier:)` removes one. They count toward the limit of 1,000 projects.
A hidden entry loses its place in the order: a save writes it after the projects that show.
When an old `project-folders.json` comes back, a project that was added in the meantime has no folder there, so it is hidden until the user adds its folder again.

`SettingsStore` reads each setting alone.
A value of the wrong type or out of range goes back to its default, and the load names it in `fallbackNames`.
A setting that this build does not know is an unknown key of the file, so it stays with the exact text of its value.

## The socket protocol

### Frames

Everything on the socket is a sequence of frames.

```
+-----------------------+----------+-------------------------+
| length: 4 bytes       | kind:    | payload:                |
| big endian, counts    | 1 byte   | length - 1 bytes        |
| the kind and payload  |          |                         |
+-----------------------+----------+-------------------------+
```

| Kind | Value | Direction | Payload |
|---|---|---|---|
| control | 1 | both | A JSON message |
| output | 2 | server to client | Bytes that the program wrote |
| input | 3 | client to server | Bytes for the program to read |
| snapshot | 4 | server to client | A `TerminalSnapshot` |
| threadEvent | 5 | server to client | One event of an agent thread, a `ConversationEvent` as JSON |

Control messages are JSON because they are small, rare and easy to read. Terminal bytes are raw because they are frequent and large.

The largest payload is 64 MiB. The receiver checks the length field before it reads or allocates anything, and refuses a larger frame. It reads the kind byte next and refuses an unknown kind. Only then does it read the payload, as the bytes arrive, so the memory grows only with what came. A zero length, an unknown kind, and a connection that closes in the middle of a frame are errors.

### Version

Both sides send their protocol version in their first message, `hello`. The current version is 1.
A session process that gets another version answers with a `failure` whose reason is `incompatibleProtocol` and closes the connection. Its message is "This session process speaks protocol version N, not M." Every version must keep the words "protocol version" and its own number after them, because a client reads the number from there.
A client that gets another version in the answer, or reads one from the failure, stops with an error that names both versions.
A client that the session process refuses for another reason, such as the limit of 64 clients, gets a `failure` with another reason in place of `hello`, and stops with its message. The session process may close the connection before the client's `hello` goes out, so a client reads the answer even when its `hello` could not be sent.
Raise `MessageFrame.protocolVersion` when a change would confuse an older program.
The `hello` message itself must stay readable by every version.

### Control messages

A control message is a JSON object with one key, the name of the message. The value holds its fields.
A field without a name in the Swift code is called `_0`.

Client to server:

| Message | Fields | Answer |
|---|---|---|
| `hello` | `protocolVersion` | `hello` |
| `createSession` | `folder`, `command` (absent for the login shell), `size`, `environment` | `sessionCreated`. An empty `command` list names no program and gets a `failure` with reason `invalidRequest`. A value that would reach the program changed gets a `failure` with reason `launchFailed` whose message names the problem: an environment name that is empty or holds `=` or NUL, or a NUL in an environment value, an argument, the program or the folder |
| `listSessions` | none | `sessionList` |
| `readScreen` | `identifier`, `includeScrollback` | `screen` |
| `sendText` | `identifier`, `text` | `acknowledged` once the text is in the program's input backlog, behind the input frames that this connection sent before. `failure` with reason `unknownSession` when the program ends before that |
| `killSession` | `identifier` | `acknowledged`, after the session is gone and every process of its terminal session has ended (see `terminate`). On a connection that is attached to that session: `acknowledged`, then `exited`, and the connection closes |
| `attach` | `identifier`, `size`, `relaysRawOutput` (optional), `receivesSizeChanges` (optional), `waitsForOutputRoom` (optional) | `attached`, then a snapshot frame, then output frames, and `sizeChanged` when the client asked for it. A size with 0 columns or 0 rows, or one that the terminal refuses, gets a `failure` with reason `invalidRequest`, and the session keeps its size. So does a size at which the screens alone do not fit in one frame (see "A snapshot that fits in one frame"). The `failure` comes in place of `attached`, and the connection stays open and not attached |
| `input` | the bytes, as an input frame | none |
| `resize` | `_0` is the size, `requestsConfirmation` is optional | A new size goes to the other attached clients that asked for it, as `sizeChanged`. While a shell edits a line, it goes where the shell's output starts to use the new width (see "Attach sequence"). When the client requests confirmation, it also gets its own `sizeChanged`, even when the size did not change. A refused confirmation request gets a `failure`, and the connection closes. Without confirmation, there is no answer; a refused size changes nothing |
| `detach` | none | the connection closes |
| `receiveApprovalQuestions` | none | `acknowledged`, then `approvalQuestion` and `approvalQuestionEnded` for as long as the connection stays open. A `failure` with reason `invalidRequest` when the program is not the signed app outside every session |
| `answerApprovalQuestion` | `identifier`, `allows` | none. Only a connection that holds the question can answer it, and only while it waits |
| `receiveSessionChanges` | `includesThreads` (optional) | `sessionList`, oldest first. A session process that offers projects and settings then sends `projectList` and `settingList`. Then `sessionChanged`, `sessionEnded`, `projectList` and `settingList` follow, in the order of the changes, for as long as the connection stays open. An attached connection gets a `failure` with reason `invalidRequest`. After it, every message other than `detach` gets a `failure` with reason `invalidRequest`, and the connection stays open |
| `renameSession` | `identifier`, `name` (absent or empty removes the name) | `acknowledged`. A name with a control character or more than 500 Unicode scalars gets a `failure` with reason `invalidRequest` |
| `raiseSessionAlert` | `identifier`, `text` | `acknowledged`. The alert has the source `notifyCommand`. The session process removes control characters from the text and keeps at most 500 scalars |
| `clearSessionAlert` | `identifier` | `acknowledged` |
| `listProjects` | none | `projectList` |
| `addProject` | `folder`, `name` (optional), `currentFolder` (optional) | `projectAdded` with the new project at the end of the list. The session process resolves the folder: `~` and `~/` start in its home folder, a relative path starts in `currentFolder`, and the symbolic links are resolved. A `failure` with reason `invalidRequest` names the problem: a relative folder with no current folder, a folder that does not exist or is no folder, a folder that is a project already, a name that is not valid, or the limit of 1,000 projects |
| `removeProject` | `identifier` | `acknowledged`. A project without a folder on this Mac can be removed too |
| `renameProject` | `identifier`, `name` (absent or empty: the name of the folder shows) | `acknowledged`. A name with a control character or more than 100 characters gets a `failure` |
| `moveProject` | `identifier`, `place` (0 is the first) | `acknowledged`. A place outside the list gets a `failure` |
| `listSettings` | none | `settingList` |
| `changeSetting` | `name`, `text` | `acknowledged`. An unknown name, a value that is not valid, and a protected setting from a caller that may not change it get a `failure` with reason `invalidRequest` and the message of `SettingError`. See "Projects and settings" |
| `createThread` | `agent` (`claude-code`), `folder`, and optional `model`, `permissionMode` and `name` | `threadCreated`. A `failure` with reason `invalidRequest` for an agent that this build does not run, a folder that does not exist, or a list that is full |
| `listThreads` | none | `threadList` |
| `renameThread` | `identifier`, `name` (absent or empty removes the name) | `acknowledged` |
| `changeThread` | `identifier`, and optional `model` and `permissionMode` | `acknowledged`. The agent takes the new values at its next start. A `failure` with reason `invalidRequest` for a mode that is not in `permissionModes` of the summary, and for a model name that could pass for a flag |
| `openThreadInTerminal` | `identifier`, `size` | `sessionCreated` with the terminal session of the conversation. A `failure` when the conversation is open in a terminal already |
| `returnThreadFromTerminal` | `identifier` | `acknowledged`, after the terminal session of the thread ended. A `failure` when the conversation is not open in a terminal |
| `closeThread` | `identifier` | `acknowledged`, after the agent of the thread ended and its record went away |
| `attachThread` | `identifier` | `threadAttached`, then the kept events as `threadEvent` frames, then `threadReplayComplete`, then each new event. The connection stays open for `sendThreadMessage`, `stopThread`, `answerToolPermission` and `detach`. A second `attachThread` on it gets a `failure`, and so does a request of the threads on a connection that is attached to a session |
| `readThreadHistory` | `identifier`, `before` (optional: the `before` of the page that the client has) | The events of whole turns from the history of the agent, oldest first, as `threadEvent` frames, and then `threadHistoryPage`. Without `before`, the newest page comes. A thread with no conversation, or with no history file, gets no events |
| `sendThreadMessage` | `identifier`, `text`, `images` (optional, each with `mediaType` and `data`) | `threadMessageSent` with the identifier of the message, which its events carry. A `failure` when 16 messages wait already |
| `stopThread` | `identifier` | `acknowledged`, also when no turn runs |
| `requestToolPermission` | `request`: what the agent gave its permission hook, as it came | `toolPermissionAnswer`, when the user answered or the request ended. A `failure` for a program that no agent of a thread started |
| `answerToolPermission` | `thread`, `request`, `allows`, `message` (optional) | `acknowledged`. A `failure` for a program that is not the signed app, and for a request that does not wait any more |

Server to client:

| Message | Fields |
|---|---|
| `hello` | `protocolVersion`, `capabilities` (optional) |
| `sessionCreated` | `_0` is a session summary |
| `sessionList` | `_0` is a list of session summaries |
| `attached` | `_0` is a session summary |
| `snapshot` | the bytes, as a snapshot frame |
| `output` | the bytes, as an output frame |
| `sizeChanged` | `_0` is the size, `keepsCursorAtLineStart` and `promptRowsAboveCursor` are optional. A client that set `receivesSizeChanges` receives it when another client changes the size with `resize` or `attach`. A client that requests confirmation also receives it for its own `resize`. It comes before the output that is laid out for that size. `keepsCursorAtLineStart` is true when the size comes where a shell has erased its lines; a client with a copy of the screen then resizes it with `Terminal.resize(to:keeping:)` and `.cursorRow`, as the session does. `promptRowsAboveCursor` comes when the shell has not answered the size in time; the client then resizes with `.promptRows(aboveCursor:)` and that number |
| `screen` | `text` |
| `exited` | `_0` is `{"exited":{"status":N}}` or `{"signaled":{"signal":N}}` |
| `acknowledged` | none |
| `failure` | `_0` holds `reason` (`incompatibleProtocol`, `unknownSession`, `launchFailed` or `invalidRequest`) and `message` |
| `approvalQuestion` | `_0` holds `identifier`, `askingSession`, `targetSession` (session summaries) and `request`: `type` with `start` and `characterCount`, or `read`, `attach` or `kill`. `start` holds at most 500 Unicode scalars, and `characterCount` counts scalars too |
| `approvalQuestionEnded` | `identifier`. Every connection that holds the question receives it when the question ends |
| `sessionChanged` | `_0` is a session summary: a new session, or a session with new facts |
| `sessionEnded` | `identifier` of a session that ended and left the list |
| `projectList` | `_0` is every project: the projects with a folder in their order, then the projects without a folder on this Mac. A project holds `identifier`, `name` (absent when the user gave none) and `folder` (absent when this Mac does not know it) |
| `projectAdded` | `_0` is the new project |
| `settingList` | `_0` is every setting in the order of `SettingName`, each with `name`, `text` and `isProtected`. `text` is the form that `changeSetting` takes back |
| `threadCreated` | `_0` is a thread summary |
| `threadList` | `_0` is every thread, oldest first |
| `threadAttached` | `_0` is a thread summary |
| `threadEvent` | the event, as a threadEvent frame |
| `threadReplayComplete` | `hasEarlierEvents`: whether the thread had events that it keeps no more. The events before this message are the kept ones, and each later event is new |
| `threadHistoryPage` | `before` (optional): what asks for the page before this one. Absent at the start of the history. The events of the page came before this message |
| `threadMessageSent` | `identifier` of the message |
| `threadChanged` | `_0` is a thread summary: a new thread, or a thread with new facts |
| `threadEnded` | `identifier` of a thread that closed and left the list. A connection that is attached to the thread gets it too |
| `toolPermissionAnswer` | `allows`, `message` (optional): the answer for the permission hook |

A session summary holds `identifier`, `folder`, `command` (a list), `size` and `createdAt` (seconds since 1970).
It can also hold the facts of the session: `name`, `title`, `currentFolder`, `branch`, `foregroundProgram`, `isInProgress`, `lastOutputAt`, `lastInputAt` (seconds since 1970), `alert` and `projectIdentifier`. An alert holds `text`, `raisedAt` and `source` (`bell`, `terminalNotification` or `notifyCommand`). A fact that is not known is absent. See "Facts of a session".
A size holds `columns` and `rows`, each 0 to 65,535.
A thread summary holds `identifier`, `agent`, `folder`, `model`, `permissionMode`, `createdAt`, `lastActivityAt`, `state` (`idle`, `inProgress`, `needsUser`, `finishedTurn` or `failed`), `isProcessRunning` and `waitingMessageCount`. It can also hold `name`, `title`, `accountName`, `projectIdentifier`, `terminalSession` (the session in which the conversation is open now), and the choices of its menus: `models`, and `permissionModes`, the modes that the thread can take now, from the strictest to the widest. A client must take a `state` that it does not know, because a later build can add one.

A control frame from a client that the session process cannot decode gets a `failure` with reason `invalidRequest`, and then the connection closes. Examples are text that is not JSON, a name that is no message of the protocol, a missing field, a field of the wrong type, keys in a control frame, and a value out of range, such as a size of 999999 or -1. The message names the problem in the words of the protocol, such as `A frame is malformed: the field resize._0.rows holds a value that is out of range or in the wrong form.` It never quotes the request, which can hold escape sequences. The first frame gets the same answer in place of `hello`. A frame that breaks the framing (a zero length, a length above the limit, or an unknown kind) closes the connection without an answer, because the bytes after it cannot be read as frames. A frame of a kind that only the server sends also closes the connection without an answer, as before. Other clients notice nothing.
JSON that nests more than 512 levels counts as JSON that cannot be read. The decoder stops at that depth at once, so a frame of 64 MiB of nested arrays costs the memory of the frame and no stack.
An error about a message that does not fit the conversation, such as a `screen` in place of `hello`, names the message and not its fields. A field can be a whole screen, or text that a user typed.

Examples of control payloads:

```json
{"hello":{"protocolVersion":1}}
{"hello":{"capabilities":{"orderedResizeConfirmation":true},"protocolVersion":1}}
{"createSession":{"environment":{"PATH":"/usr/bin"},"folder":"/work","size":{"columns":80,"rows":24}}}
{"attach":{"identifier":"3F2A9C1E-0000-4000-8000-000000000001","relaysRawOutput":true,"size":{"columns":80,"rows":24}}}
{"attach":{"identifier":"3F2A9C1E-0000-4000-8000-000000000001","receivesSizeChanges":true,"size":{"columns":80,"rows":24}}}
{"attach":{"identifier":"3F2A9C1E-0000-4000-8000-000000000001","size":{"columns":80,"rows":24},"waitsForOutputRoom":true}}
{"resize":{"_0":{"columns":100,"rows":30}}}
{"resize":{"_0":{"columns":100,"rows":30},"requestsConfirmation":true}}
{"sizeChanged":{"_0":{"columns":100,"rows":30}}}
{"exited":{"_0":{"exited":{"status":3}}}}
{"failure":{"_0":{"message":"No session has the identifier 3f2a9c1e-…","reason":"unknownSession"}}}
{"receiveSessionChanges":{}}
{"renameSession":{"identifier":"3F2A9C1E-0000-4000-8000-000000000001","name":"Release build"}}
{"raiseSessionAlert":{"identifier":"3F2A9C1E-0000-4000-8000-000000000001","text":"Waiting for input"}}
{"clearSessionAlert":{"identifier":"3F2A9C1E-0000-4000-8000-000000000001"}}
{"sessionChanged":{"_0":{"alert":{"raisedAt":1794303000.25,"source":"notifyCommand","text":"Waiting for input"},"command":["claude"],"createdAt":1794302000.5,"folder":"/work","foregroundProgram":"claude","identifier":"3F2A9C1E-0000-4000-8000-000000000001","isInProgress":false,"size":{"columns":80,"rows":24}}}}
{"sessionEnded":{"identifier":"3F2A9C1E-0000-4000-8000-000000000001"}}
{"hello":{"capabilities":{"orderedResizeConfirmation":true,"projectsAndSettings":true,"sessionChanges":true},"protocolVersion":1}}
{"listProjects":{}}
{"addProject":{"currentFolder":"\/work","folder":"app","name":"App"}}
{"addProject":{"folder":"\/work\/app"}}
{"removeProject":{"identifier":"3F2A9C1E-0000-4000-8000-000000000001"}}
{"renameProject":{"identifier":"3F2A9C1E-0000-4000-8000-000000000001","name":"App"}}
{"moveProject":{"identifier":"3F2A9C1E-0000-4000-8000-000000000001","place":0}}
{"projectList":{"_0":[{"folder":"\/work\/app","identifier":"3F2A9C1E-0000-4000-8000-000000000001","name":"App"},{"identifier":"3F2A9C1E-0000-4000-8000-000000000002"}]}}
{"projectAdded":{"_0":{"folder":"\/work\/app","identifier":"3F2A9C1E-0000-4000-8000-000000000001","name":"App"}}}
{"listSettings":{}}
{"changeSetting":{"name":"font-size","text":"14"}}
{"settingList":{"_0":[{"isProtected":false,"name":"font-size","text":"14"},{"isProtected":true,"name":"session-limit","text":"100"}]}}
{"receiveSessionChanges":{"includesThreads":true}}
{"createThread":{"agent":"claude-code","folder":"\/work\/app","model":"opus","name":"Notes","permissionMode":"plan"}}
{"changeThread":{"identifier":"3F2A9C1E-0000-4000-8000-000000000001","permissionMode":"plan"}}
{"attachThread":{"identifier":"3F2A9C1E-0000-4000-8000-000000000001"}}
{"sendThreadMessage":{"identifier":"3F2A9C1E-0000-4000-8000-000000000001","text":"Go on."}}
{"readThreadHistory":{"before":4096,"identifier":"3F2A9C1E-0000-4000-8000-000000000001"}}
{"threadHistoryPage":{"before":1024}}
{"threadReplayComplete":{"hasEarlierEvents":true}}
{"threadMessageSent":{"identifier":"3F2A9C1E-0000-4000-8000-000000000002"}}
{"requestToolPermission":{"request":"e30="}}
{"answerToolPermission":{"allows":true,"request":"p1","thread":"3F2A9C1E-0000-4000-8000-000000000001"}}
{"toolPermissionAnswer":{"allows":false,"message":"No."}}
```

The encoder of the protocol writes a slash as `\/`. A decoder reads `\/` and `/` the same.

`relaysRawOutput` is a new optional field of `attach`. It stays inside protocol version 1: a client that leaves it out, or sends `false`, does not relay raw output, and an older session process ignores the field.
`keepsCursorAtLineStart` and `promptRowsAboveCursor` are optional fields of `sizeChanged`, so they stay inside protocol version 1 too. The session leaves them out when they do not apply. An older client ignores it and resizes its copy of the screen as before. After output without a line end, that copy can then differ from the session's screen. Until milestone 5 the session process and its clients come from one build (decision of 2026-10-24), so no such client meets it yet.

`receivesSizeChanges` is another optional field of `attach`, and it stays inside protocol version 1 too. A client that leaves it out, or sends `false`, receives no changes from other clients. An older session process ignores the field and never sends those changes. By default the client whose own `resize` or `attach` changed the size gets no `sizeChanged`. `openrun attach` keeps that behavior: its real terminal lays out the output at its own size.

`waitsForOutputRoom` is also optional in version 1. A client that leaves it out, or sends `false`, keeps the earlier disconnect behavior. An older session process ignores the field. The app sends `true`; `openrun attach` leaves it out. See "Slow clients" for the pause, deadlines and precedence of a faster viewer.

The server's `hello` can also hold `capabilities.orderedResizeConfirmation`. A missing field means `false`. A client that needs the confirmation must check the capability before it asks, because an older session process ignores the new request field. The app requires it and rejects an unsupported session process; a snapshot still requires the same build (decision of 2026-10-24).

When an attached client sends `resize` with `requestsConfirmation` true, the session applies the size and enqueues `sizeChanged` for that client in the same actor step. It does so even when the size was already in effect. While a shell edits a line at the cursor, a new width and its confirmation wait for the shell's answer instead (see "Attach sequence"). A newer resize during the wait replaces the older one. The client of the older one then hears of the size that applies, unless its own newer request answers it. The confirmation follows earlier output and earlier foreign size changes and precedes later output. A zero size, a request before attach, or a refused size gets `failure` and closes that connection. The app waits for each ordered size message before changing its local terminal. It follows a foreign size without sending a resize in reply. A key window can request its own size even when its local grid already has it, so a queued foreign size cannot leave the grid stale after the confirmation.

`specifications/AttachSequence.tla` models this order when the screen takes a size. It leaves out the earlier wait while the program has another size. One control applies the local size before its confirmation and fails `SizeOrder`. A second removes the confirmation and fails `ConfirmedSizeAgreement` after a queued foreign size. These controls check different protections.

`specifications/ResizeWait.tla` models the wait with separate sizes for the program, the session screen, and each following client. It includes a newer resize, a replaced confirmation, a stale timeout, a foreground program change, output held by backpressure, a buffered erase from before a resize, an attach, a failed attach, a disconnect, and a size query. Its safety checks cover size agreement, ordered screen operations, confirmations, redraws and size answers. A client that sends an unconfirmed valid resize is excluded from screen-copy agreement. Its earlier confirmed requests still need an answer. Under the stated fairness, its liveness checks require waits and buffered output to end, and confirmations to arrive or their client to leave. Controls remove individual protections and must fail. Reachability controls must also fail, to show that the runs reach the races they name.

The resize model describes the intended behavior. It assumes the implementation identifies an editor and a fresh redraw correctly, gives queries the program size, and preserves the screen when a failed attach rolls back. It also assumes a failed screen resize leaves the screen intact and the program can return to the old size. It does not prove those assumptions about Swift or libghostty-vt. It represents screen changes as an ordered trace, not terminal cells or escape bytes. It omits input and in-band size reports. It treats program exit as cancellation; the other models check exit delivery. It abstracts a slow client's output pause, and it has no clock to check 500 milliseconds. The quick runs bound the number of clients, requests, output pieces and sizes. The two models do not have a checked refinement between them.

`specifications/AttachSequence.tla` also models the output-room wait, in abstract message units. Each protection of the wait is a definition of the model, and each of five controls sets one of them to false. Without the pause, a waiting client holds more output than the high mark, and `OutputWaitBoundsQueue` fails. Without the precedence close, a wait starts while another viewer keeps up, and `NoNewPauseWhileViewerKeepsUp` fails. Without the wake when another viewer drains, a wait goes on after that viewer keeps up, and `NoPauseWhileViewerKeepsUp` fails. The liveness runs do not make the timeout fair, so a wait must end because room appears. So no run checks that the timeout ends a wait for a client that never reads. Without the wake on the waiter's own room, `WaitingForRoomEnds` fails. Without the release of a wait when its client leaves, parsing stops, and `EveryChunkIsParsed` fails. The model makes the choice of a client and its wait one step. The sticky refusal of `ClientConnection.refuseOutputRoomWait` makes the code act the same. The model has no clock, so it does not check the deadlines, the total pause cap, the snapshot grace or the wake at the end of the program.

`specifications/LocalDelivery.tla` separates the server queue from the work that has left it. The local queue includes frames in transit, relay work and view work. It applies the snapshot, output and size markers in order, and lets a client leave. Server capacity counts only the server queue; size agreement after a pause requires both queues to be empty. Three controls must fail. The first lets a size pass output and fails `ApplicationOrder`. The second lets a size pass output and fails `SizeOrder`, because output laid out for the old size reaches a view that has the new size. The third checks size agreement when only the server queues are empty and fails `ServerOnlySizeAgreement`.

The model gives each counted server message one unit. `ApplicationCapacity` bounds the relay to `LocalEventLimit` events and `LocalByteLimit` bytes, and one larger frame may enter an empty relay. `ReceiverCapacity` lets the receiver hold one more frame. Each client attaches once. The two-client run allows three outputs and two resizes; the three-client run allows one output and one resize. Each has two sizes, two server units, two relay events and two relay bytes. It treats each output frame as one piece and omits failed attaches, failed sizes, queries and input. It does not prove an unbounded refinement or a time limit.

The identifier is a UUID. In JSON it is the usual upper case text. People and environment variables see it in lower case.

The four messages of approval questions are additions, and only a client that asks with `receiveApprovalQuestions` receives a question. So they stay inside protocol version 1.

The messages of the session changes and the facts are additions too, and so are the new fields of a summary, which an older client ignores. Only a client that asks with `receiveSessionChanges` gets `sessionChanged` and `sessionEnded`. The server's `hello` holds `capabilities.sessionChanges` as `true`. A missing field means `false`, and an older session process answers the new requests with a `failure`. So they stay inside protocol version 1.

The messages of the projects and the settings, and `projectIdentifier` of a summary, are additions in the same way. The server's `hello` holds `capabilities.projectsAndSettings` as `true`. A missing field means `false`. An older session process answers the new requests with a `failure`, and sends no `projectList` or `settingList` on the feed. So they stay inside protocol version 1.

The messages of the agent threads and the frame kind `threadEvent` are additions too. The server's `hello` holds `capabilities.threads` as `true`. A missing field means `false`, and an older session process answers the new requests with a `failure`. Only a connection that sent `attachThread` or `readThreadHistory` gets a `threadEvent` frame, and only a watcher that sent `includesThreads` as `true` gets `threadList`, `threadChanged` and `threadEnded`. An older client sends neither and reads no new message. So they stay inside protocol version 1.

### A conversation

1. The client connects and sends `hello`. The server answers `hello`.
2. A request that needs one answer (`createSession`, `listSessions`, `readScreen`, `sendText`, `killSession`, `renameSession`, `raiseSessionAlert`, `clearSessionAlert`, and the requests of the projects and the settings) gets its answer. The client may send the next request or close.
3. `attach` starts a longer conversation. See the next section.
4. `attachThread` starts the conversation of an agent thread: the summary, the kept events, `threadReplayComplete`, and then each new event, until `detach` or the close of the thread.

Between the connection and step 1, the client checks the folder of the socket and the user of the session process, and the session process checks the user of the client. See "The folder of the socket" and "The user at the other end" in "Process model".

The client sends the environment of the person who asked, in `createSession`. The program starts with it, so it sees the user's own `PATH` and account settings, such as `CLAUDE_CONFIG_DIR`. The session process then sets the variables in "Environment variables" over it.

## Attach sequence

```
client                                   session process
  | attach(identifier, size)  ------------>  |
  |                                          |  on the session's own serial context:
  |                                          |    1. apply a size that waits for a shell, then
  |                                          |       resize the terminal when the size differs
  |                                          |    2. take a snapshot that fits in one frame, or
  |                                          |       queue "failure", go back to the old size, and stop
  |                                          |    3. queue "attached" and the snapshot for this client
  |                                          |    4. add the client to the attached clients
  |                                          |    5. queue "sizeChanged" for each other client
  |                                          |       that asked, when the size changed
  | <-------------------- attached(summary)  |
  | <----------------------- snapshot frame  |
  | <------------------------- output frame  |  every later output, in order
  | <------------------------- output frame  |
  | input frame, resize, ...  ------------>  |
  | <--------------------------- exited(..)  |  when the program ends
```

A client's size goes to two places: the session's terminal model and the program's pseudo terminal. The session resizes the model first, because the model checks the size and may refuse it. A refused size then reaches neither, and the program and the screen that clients see keep one size. When the pseudo terminal refuses a size after the model took it, the model goes back to the old size.

While a shell edits a line at the cursor, a new width waits for the shell (`LineEditorWait`). That is when the terminal is on the primary screen, and the cursor is in a prompt that the output shows (`ShellPromptTracker`), also behind ssh or another program. bash says nothing about its prompt in its output, so for bash, bracketed paste must be on and bash must be the foreground program and read commands from its terminal (`InteractiveShell`). The arguments decide that: no `-c` and no script. A script can turn on bracketed paste too, but it has no line editor, also when `-i` makes the shell interactive while it runs the script. An agent or another program in the foreground draws in its own way. For all of these, the size applies at once. The session checks the size with `Terminal.validate` and gives it to the pseudo terminal at once. The model keeps the old size until the shell's answer has erased the shell's lines (see `LineEditorAnswer`). Meanwhile its answers to size queries report the size that the program has (`Terminal.reportedSize`). Output that the program wrote before it got the size can hold an erase too, such as one that removed a list of completions. So the answer starts only after the bytes that the session had not parsed when it changed the size of the pseudo terminal (`writtenOutputByteCount`). There the session splits the output: the bytes up to the erase go out as one `output`, then the model takes the new size and the clients get `sizeChanged` with `keepsCursorAtLineStart`, and then the rest of the bytes follow. The model and each client resize with `Terminal.resize(to:keeping: .cursorRow)`, so a prompt after output without a line end keeps its own row on every copy. So the shell's count of rows meets the screen that it counted on, in the model and in each client that follows the size. Every `output` still holds only bytes that the program wrote. A resize that comes during the wait waits too, and a newer one replaces it, so the shell answers one size at a time. A size of zero columns or rows changes nothing, with or without a wait, so it replaces nothing. When no answer comes within 500 ms, the size applies anyway. The model then keeps the rows of a prompt that the output shows, and the clients get `sizeChanged` with `promptRowsAboveCursor`. A prompt can expand a slow command substitution before the shell answers, so the answer can still come. The shell draws that answer for the size of the wait, so the wait goes on until the answer, and a newer resize waits too. Without an answer within four more time limits, the newer resize applies. An attach applies a waiting size at once, with the rows of the prompt, because the attach comes later, and then changes the size as before. `specifications/ResizeWait.tla` models the wait with separate sizes for the program, the session's screen and each client. Its controls each remove one protection, such as the check of the editor, the size answers, the skip of earlier output, or the rule for a size of zero, and must fail. It assumes the detection of the editor and of its answer, and it does not parse terminal bytes.

### Why there is no gap and no repeat

A `Session` is an actor, so only one piece of its code runs at a time.
The program's output is handled by one method of the session: it updates the terminal, and then queues the same bytes for every attached client.
`attach` is another method of the same actor, and it does not wait for anything.

So the output splits cleanly into two groups:

- Output handled before `attach` ran is inside the terminal when the snapshot is taken. It is in the snapshot, and the client is not registered yet, so the client does not get it again as output.
- Output handled after `attach` ran finds the client registered. It goes to the client's queue behind the snapshot.

The client's queue keeps the order. The client restores the snapshot and then writes each output frame into the restored terminal.
The snapshot can even fall inside an escape sequence or a UTF-8 character. A snapshot keeps the unfinished bytes, and the next output frame completes them.
A client that draws a picture of the snapshot for another terminal must also write those bytes after the picture, because the picture holds only what is finished. `UnfinishedSequence` returns them. The protocol does not change for this: the bytes are already in the snapshot.

Tests check this with 3000 numbered lines of steady output and an attach at four moments. The restored screen and scrollback must show each line once, in order.

### A snapshot that fits in one frame

A snapshot travels in one frame, and a frame carries at most 64 MiB. A wide session with a full scrollback in many colors can need more. A test measured about 80 MB for 1000 columns of wide characters in 256 colors with 10,000 lines of scrollback.
So `Session.attach` captures with `TerminalSnapshot(capturing:byteLimit:)` and the payload limit, before it sends `attached`. A larger snapshot loses its oldest lines of scrollback until it fits, and it keeps as many lines as fit. The client then has the newest part of the scrollback. `openrun read --scrollback` still prints all of it.
The visible screen, the alternate screen, the cursor, the modes and an unfinished sequence stay whole. So the seam of the attach holds as before: output parsed before the snapshot is inside it, and output after it follows it, with no gap and no repeat.

The screens alone can also be too large. An example is an attach at 10,000 rows, which pulls the scrollback onto the screen. The client then gets a `failure` with reason `invalidRequest` in place of `attached`: "The screen of the session does not fit in one frame of 64 MiB, even without scrollback. Attach with fewer columns or rows." The session goes back to its earlier size, and the connection stays open and not attached. The program gets the new size and then the old one. The other clients get no `sizeChanged`, because the size did not change in the end. In one rare case the old size cannot come back: the terminal model or the program's pseudo terminal refuses it. The session then keeps the new size, and the other clients that asked get `sizeChanged`.

`ReattachTests.aSnapshotLargerThanOneFrameLosesOldScrollbackAndKeepsTheScreen` checks both cases in a session of 1000 columns. The client that attaches gets a snapshot near 64 MiB with the newest scrollback, and its screen is the screen that `openrun read` shows, also after more output.

### What `openrun attach` does

1. It resolves the identifier, and sends `attach` with the size of its terminal and `relaysRawOutput` set to `true`, because it writes the raw output to a real terminal. It does not set `receivesSizeChanges`, because its real terminal lays out the output at the size of its own window.
2. It restores the snapshot into a local `Terminal` and makes the first picture from it. This happens before the terminal changes, so a snapshot that cannot be restored ends the tool with an error (exit code 1) and leaves the terminal as it was. A `failure` in place of `attached`, such as for a screen that does not fit in one frame, ends the tool the same way, with the message of the failure.
3. It starts to handle signals, and only then puts the terminal in raw mode. So no signal can leave the terminal raw.
4. It draws the picture: it clears the screen and draws the visible screen of the local terminal in its VT format. When the session is on the alternate screen, it enters the alternate screen first. When the snapshot fell inside an escape sequence or a UTF-8 character, it writes the start of it after the picture (`UnfinishedSequence`). The first output frame then finishes it in the real terminal. Without this, the terminal would show the end of the sequence, such as `1mRED`, as text. The picture starts with `CSI 22 ; 0 t`, which saves the title of the window on its stack. The tool puts the title back when it restores the terminal (step 7). A picture that is made again saves the title only when the window does not hold it, and enters the alternate screen only when the window is not on it. After a resize that interrupted the first picture, the window can already hold the title. After a suspension, the closing put the title back and left the alternate screen, unless it gave up on a terminal that takes no output before those bytes went out (see Closing state).
5. It relays: keys go out as input frames, output frames go to the terminal, and SIGWINCH asks the writer for a `resize` request. The main thread handles it: it reads the size of the window, resizes the local terminal, and only then sends `resize` to the session process. So the local terminal has the size of the window before it follows any later output, and wraps lines where the window does. A first picture that waits is made again at the new size. When that fails, the tool ends with exit code 1 and a message, as after a resume. After a resume, the main thread reads the size and resizes the local terminal before it makes the picture, because the window can change while the tool is stopped and no signal reaches it then. The tool asks for the same request when the relay starts, because the window can change between the attach request and the signal handler. The local terminal follows exactly the bytes that reached the terminal, so the tool knows at the end whether the terminal is on the alternate screen. Keys go out in order on a queue of their own. After `KeySender.stop` returns, the keyboard thread reads no more keys: it checks the stop flag and reads under one lock. Keys that it read before `stop` still go to the session. Keys that the recognizer holds for a possible detach at that moment, such as a lone Escape within its short hold, are dropped. `KeySender.pause` works like `stop` for reads: the thread checks the pause flag and reads under one lock, so it reads no key after `pause` returns. `resume` lets it read again. A send waits when the program reads no input and the session process holds as much as it may, and the keyboard thread must still see the detach key then.
6. Control-] detaches. `DetachKeyRecognizer` finds the key in the bytes that the terminal sends (see "The detach key"). The tool sends `detach` behind the keys, waits for it at most 200 milliseconds, and then closes the connection. The program's exit, a lost connection, a failed write to the terminal, SIGINT, SIGTERM, SIGHUP and SIGQUIT also end it.
7. In every case it restores the terminal. It first writes CAN (`0x18`) and ST (`ESC \`), which end any escape sequence or string, such as an operating system command, that the program left open. Without them, a terminal could take what follows, and the message after it, as part of the open sequence. Then it turns off synchronized output (mode 2026), because that mode holds back every later change of the screen. Then it leaves the alternate screen, when the terminal is on it. Then it undoes what the program and the first picture switched on: the scroll region and origin mode (with the cursor saved and restored around them, because both reset moves the cursor), the color palette, the foreground, background and cursor colors (OSC 10 to 12), styles, a hyperlink that is still open (OSC 8 with no address), the character sets, insert mode, reverse video (mode 5), line wrap, the cursor and its shape, the modes that lock the keyboard or change a key (ANSI modes 2 and 20, mode 67), the left and right margins (mode 69), mouse reports (modes 9, 1000, 1002, 1003) and their encodings (1005, 1006, 1015, 1016), focus reports, color scheme reports, visibility reports and size reports (modes 1004, 2031, 2033, 2048), bracketed paste, application keys, and the extended keyboard modes. Then it puts the title back (`CSI 23 ; 0 t`), when the picture saved it. Then it puts the original terminal mode back.

   A saved cursor also keeps origin mode, so when the program set origin mode, the tool resets it after the cursor is restored, and moves the cursor back to its place. The tool finds out whether origin mode is set from the local terminal. The reset before leaving the alternate screen has the same reason: the alternate screen forgets its cursor.

   The tool resets only modes that are off in a plain terminal. It does not touch modes that many terminals turn on by default, such as alternate scroll (1007), grapheme clusters (2027) and the meta key modes (1035, 1036). Those modes would then differ from the user's own setting.

Threads. Only the main thread writes to the terminal, through `TerminalWriter`. The receiving thread of `SessionAttachment` hands the output to the writer, at most 1 MiB ahead. The keyboard thread (`KeySender`) and the signal handlers (`AttachSignals`) never write to the terminal. They ask the writer to end, to suspend, to go on, or (the signal handlers) to follow a change of the window size. The local screen of the tool is only touched by the main thread, also when the window changes size. When two requests to end arrive, an urgent ending wins over an ending that waits for output, also when the urgent one came second. A detach (Control-]) and a signal are urgent: they end the attach at once, and output that still waits is dropped. The exit of the program and a lost connection wait for the output that came before them. Among urgent endings, the first one decides the exit code, so a second signal does not change it. Among endings that wait for output, the first one decides as well. No output follows the closing sequences.

The last message of `openrun attach` (such as `[detached]` or the reason of a lost connection) can include text from the session process, so it is escaped with `PrintableText.escaping`.

A terminal that takes no output. The writer opens the terminal a second time, without blocking, so a terminal that reads nothing, such as a frozen `ssh` or a paused multiplexer, cannot hold the tool in a write. It waits for room with `poll`, and a request wakes it. Control-] and the stop signals therefore end the tool also while the terminal takes no output. In that case the tool puts the original mode back first, because the closing sequences may never reach the terminal, and then gives the closing sequences and the last message one second each.

Suspending. SIGTSTP restores the terminal as at the end (including the title), and then stops the tool. The tool stops itself with SIGSTOP, because a SIGTSTP of its own would reach its own handler again after the continue. A shell reports the tool as stopped by a signal. A signal to end that arrives before the stop wins over the suspension: SIGINT, SIGTERM, SIGHUP or SIGQUIT, also 150 milliseconds after SIGTSTP while the terminal takes no output, ends the tool with 128 plus the signal and the terminal restored, and the tool never stops itself. The tool asks once more, right before SIGSTOP, so the closing sequences of the suspension (which may wait up to one second for a terminal that takes no output) do not hide the signal. The keyboard thread reads no keys from the start of the suspension until the continue has set raw mode again (`KeySender.pause` and `KeySender.resume`). Keys that the user types in that time stay in the terminal for the shell, also while the closing sequences wait for a terminal that takes no output. `KeySender.stop` and the end of attach still work while the reading is paused. A signal that comes after the stop waits for the continue, as for any stopped process. SIGCONT puts the terminal in raw mode again, with the mode that the terminal has then as the one to put back, sends the size, and draws the picture again. That picture saves the title again when the closing put it back (step 4).

Closing state. The local screen counts the window as on the alternate screen, and as holding the saved title, until the bytes that end that state went out. `TerminalWriter.writeClosing` returns how many bytes of the closing sequences reached the terminal. The alternate screen is done with when the bytes up to the end of `CSI ? 1049 l` went out. The title is done with when all bytes went out, because the title pop (`CSI 23 ; 0 t`) is the last part. When a suspension gives up on a frozen terminal and a signal then ends attach, the last closing still leaves the alternate screen and pops the title. A state that was ended is never ended again, so the title pop is not sent twice. The other sequences give the same result when repeated.

Raw mode starts with TCSANOW and ends with TCSADRAIN, so neither discards the keys that the user typed ahead: the session gets the keys typed before attaching, and the shell gets the keys typed while the tool ends. TCSADRAIN waits for the output to drain, so the tool waits at most 200 milliseconds for that, and switches with TCSANOW when the terminal takes no output. Back in line editing, the kernel marks the keys typed ahead for another pass (PENDIN), and the mode shows the mark until something looks at the input. The tool polls the input once, so the mode reads exactly as it was before attaching.

### The detach key

`openrun attach` passes a program's keyboard mode requests to the real terminal. After a program such as Codex turns on an enhanced mode, the terminal sends Control-] in another form. `DetachKeyRecognizer` (in `Sources/CommandLineTool/`) detaches on all of these:

| Form | Bytes |
|---|---|
| Plain keyboard | `0x1D` |
| Kitty keyboard protocol | `ESC [ 93 ; 5 u` |
| xterm modifyOtherKeys | `ESC [ 27 ; 5 ; 93 ~` |

The kitty form is `CSI 93[:alternates] ; modifiers[:event] [; text] u`. The modifiers value minus one must have the Control bit and no Shift, Alt, Super, Hyper or Meta bit. The Caps Lock and Num Lock bits are ignored. The event may be missing, 1 (press) or 2 (repeat). Event 3 (release) does not detach. Other keys, such as `ESC [ 91 ; 5 u`, pass through.

The recognizer returns the bytes before the key, and the tool sends them to the session. All other bytes pass through unchanged.

A terminal can deliver one key in two reads, for example over `ssh` or in a multiplexer. So the recognizer holds an incomplete end of the input when it could still become one of the three forms above. A lone Escape counts, because it starts the two escape forms. The recognizer joins the held bytes to the next read.

- A hold lasts at most 20 milliseconds. Then `AttachCommand` sends the held bytes to the session, and a later second half no longer detaches. The hold starts when the first held byte arrives. More bytes of the same form do not start it again.
- Bytes that no detach form can start with are never held. An example is `ESC [ 1`, or `ESC [ 9 3 0`. They are sent at once.
- The Escape key reaches the program up to 20 milliseconds late. This is the price of recognizing a split key.
- The keyboard thread of `openrun attach` polls with the time that the hold has left. When the poll times out, it sends the held bytes. Keys that are ready when the poll ends were in the terminal in time, so the thread reads them and joins them to the held bytes first, also when it gets to them late on a busy Mac. The hold therefore counts from when the bytes were read. A poll that a signal interrupts reads nothing, and the next poll waits for the time that the hold has left, so a held Escape never waits for the next key.

The exit code of `openrun attach` is 0 after a detach, and the program's own status (or 128 plus the signal) when the program ends while attached. The session process is another program, so the tool clamps these numbers to 0 to 255. Without the clamp, a status of 300 would reach the shell as 44, because the kernel keeps only the low byte. The exit code is 128 plus the signal when SIGINT, SIGTERM, SIGHUP or SIGQUIT ends the tool, and 1 when the connection is lost, the terminal cannot be written to, or the picture cannot be made again after a resize or a resume.

## Query replies

Programs ask the terminal questions, such as "where is the cursor" (`ESC [ 6 n`) or "what are you" (`ESC [ c`). The terminal must send an answer back as input.

libghostty-vt answers through callbacks. `Terminal.setReplyHandler` installs four callbacks and two more answers:

- the callback for bytes that go back to the program (cursor position reports, mode reports, and more),
- the callback for device attributes. The terminal answers only when this callback gives it the values. It reports level 2 with ANSI color,
- the callback for size (`GHOSTTY_TERMINAL_OPT_SIZE`). It answers the XTWINOPS queries `CSI 14 t`, `CSI 16 t`, `CSI 18 t` and `CSI 19 t` from the grid of the terminal, and it enables the in-band size reports of mode 2048. When `Terminal.reportedSize` is set, it and `CSI 15 t` report that size in place of the grid. The session sets it while its screen waits for a shell's answer to a new size. A session has no window, so a cell is a nominal 8 by 16 pixels. For an 80 by 24 grid, `CSI 18 t` gets `ESC [ 8 ; 24 ; 80 t` and `CSI 14 t` gets `ESC [ 4 ; 384 ; 640 t`. The grid is read at each query, so the replies follow a resize, and `Terminal.resize` stores the pixel size of the grid (a cell of 8 by 16 pixels), so the in-band report of mode 2048 after a resize carries pixels too,
- the callback for the color scheme (`GHOSTTY_TERMINAL_OPT_COLOR_SCHEME`). It answers `CSI ? 996 n` with `ESC [ ? 997 ; 1 n` for dark and `ESC [ ? 997 ; 2 n` for light. `TerminalColorScheme.current()` reads the macOS appearance (`AppleInterfaceStyle`) fresh, at most once each second. It asks CFPreferences to refresh its cache first, because the session process runs no main run loop. A change of appearance reaches a running program within about a second.
- the default foreground, background, cursor and palette colors. libghostty-vt answers `OSC 4`, `OSC 10`, `OSC 11` and `OSC 12` from these defaults. Before it parses output, `Terminal.write` applies the reply handler's colors when the appearance changes. The session supplies the Graphite colors for that appearance; a caller that supplies no colors gets plain black and white defaults. The answer keeps the terminator of the query. `setReplyHandler(nil)` clears the defaults. A client that restores a snapshot installs no reply handler, so its own defaults stay until the client changes them.
- `CSI 15 t` (the size of the screen in pixels). libghostty-vt does not parse this query, so it has no callback. `Terminal.write` looks for the exact bytes `ESC [ 1 5 t` (also when a write ends inside them), parses the bytes up to the end of the query, and then sends `ESC [ 5 ; height ; width t` from the grid and the nominal cell, so the replies keep the order of the queries. For an 80 by 24 grid the reply is `ESC [ 5 ; 384 ; 640 t`.

The default colors are a setting of the terminal, not output. The snapshot carries them, but the picture of `openrun attach` (the visible screen as sequences from a restored snapshot) and the text of `openrun read` do not change. `TerminalReplyTests.theQueriesChangeNoPictureOrText` compares plain text, sequences and hypertext markup, with and without the colors, for eleven kinds of output, also after the restore and more output.

libghostty-vt has one user data pointer for all callbacks. `Terminal` sets it once, when the terminal starts, to a `TerminalCallbackBox`. The box lives as long as the terminal. It holds the reply handler (`Terminal.replyBox`) and the event handler. The handler's box is stored before the callbacks are set, and the old box lives until the new callbacks are in place. If the installation fails half way, the terminal takes the callbacks back, or keeps the box alive when it cannot.

A client terminal never installs the write callback. It would answer each query a second time, against the rule below. The view encodes pastes with `PasteText` for this reason.

The session process installs a handler on the session's `Terminal` before it starts the program. The handler writes the bytes to the pseudo terminal with `PseudoTerminal.write`, which never waits, unless a real terminal answers instead. An answer goes in behind typed input that waits for room, as a real terminal would send them.

`openrun attach` writes the raw output to the user's terminal window, and that window answers the same queries, as it would over `ssh`. Two answers would confuse the program. So the rule is:

- While at least one attached client relays raw output (`relaysRawOutput` is `true` in its `attach` message), the session process sends no replies. The real terminal of that client answers.
- With no client, or with only clients that do not relay, the session process answers. This holds for the color queries and for `CSI 15 t` too. With a relaying client attached, the handler of the session process stays silent for all queries.
- The app restores a snapshot and draws it itself, so it does not relay. It sends no `relaysRawOutput` or sends `false`, and the session process keeps answering for it. Its copy of the screen installs no handler, so each query gets one answer.

The session process still parses every query when it stays silent, so its screen state is the same either way.

### Size reports

A program that turns on mode 2048 gets an in-band report of each new size, `ESC [ 48 ; rows ; columns ; height ; width t`. libghostty-vt makes the report when the session resizes its terminal. Only a terminal whose window changed knows of a change, so the rule differs from the rule for queries:

- When a relaying client sends `resize`, its own window changed, and its real terminal sends the report. The session process stays silent.
- No terminal reports any other change: a `resize` from a client that does not relay, an `attach` with another size, and the return to the old size after an attach that fails. So the session process sends the report, also while a relaying client is attached. It opens its reply gate only for that resize. The resize parses no output, so no query gets a second reply.

When a program turns mode 2048 on, libghostty-vt also reports the size at once. That report is an answer to output, so it follows the rule for queries.
`QueryReplyTests.eachSizeChangeIsReportedOnceWhileARelayingClientIsAttached` attaches a relaying client and another client. The program reads one report for the attach of the other client at 100 by 30, one for its resize to 120 by 40, and none for the resize of the relaying client to 90 by 25.

### Attaching and detaching while a query is pending

The decision is made once for each query, at the moment the session process parses its bytes.
The session parses output, attaches and detaches on one serial context, so each query meets exactly one state of the client list. The rule is:

- A query that the session parsed before a relaying client attached was answered by the session process. The client's snapshot holds the screen and not the bytes of the query, so the client's terminal never sees it and does not answer again.
- A query that the session parsed while a relaying client was attached is sent to that client as output, and only its terminal answers.
- If that client detaches, or loses its connection, before its terminal has answered, nobody answers. The program gets no reply, as it would when an `ssh` connection drops. The next query is answered by the session process again.

Tests cover no client, an attached client in a pseudo terminal that plays a real terminal and answers `ESC [ c`, an older client that sends no field, a client that attaches after the answer, and a client that detaches before the next query. In each case the program reads exactly one reply.

Limit: two relaying clients attached at once both answer, so the program gets two replies. The app does not relay raw output.

## Speed of dense output

The session process parses every byte that a program writes, so the speed of libghostty-vt sets the speed of a session.
`scripts/build-ghostty-library.sh` builds it with `-Doptimize=ReleaseFast`, the mode that Ghostty ships. Zig's default is Debug, and a Debug build needed more than 3 minutes to parse 16 MB of dense text.
The script writes the mode to `Libraries/ghostty-vt.optimize-mode`. When that file does not name the mode in the script, the script deletes the old output and builds again, so a re-run never leaves a framework of the wrong mode in place.
Before it fetches or checks out anything, the script refuses a Ghostty tree with changes, so an edit is never discarded. It checks again after the checkout. The script uses a Zig tree that it extracted in the same run, from an archive in `Libraries/zig` whose checksum matched the pin (or from a fresh download that matched). It deletes the tree that an earlier run left and extracts again, then checks the `zig` program against its pinned checksum. A Zig in the search path is never used. The checksum of the program alone would not cover the standard library beside it, and extracting again does.

`ThroughputTests` run an `awk` program that writes 250,000 numbered lines of 64 bytes each, 16 MB in all. Each line holds six digits, a space, 56 printable characters and a line feed. Two tests run it with no client, and one test runs it with one client that reads all output. The numbers let a test see a lost, repeated or moved line.
The session process must use less than 5 seconds of processor time (user and system together) while the program writes its output. `RunningSessionProcess.processorTime` reads it while the process runs.
Each test reads the processor time when it has seen all of the output: at the exit of the program, or, in one test with no client, when the last line is on the screen. In that test the program stays alive after its last line, so the test can check every row of the screen.
Wall time is not the bound, because other programs on a busy Mac take processor time from the session process and make a correct run slow.
A wall-time limit of 60 seconds ends a test that hangs.
On the development Mac (Apple Silicon, debug build of the Swift code, ReleaseFast libghostty-vt), a run used about 1.0 to 1.6 seconds of processor time.
The Swift code is a debug build in the tests, so the limit of 5 seconds leaves little room on a slow Mac.

## Environment variables

Every program in a session gets these. They override the same names in the environment that the client sent. A client name that is empty or holds `=` or NUL is refused (see `createSession`), so a client cannot add a second entry for one of these names.

| Variable | Value |
|---|---|
| `OPENRUN_SESSION` | The identifier of the session, in lower case |
| `OPENRUN_SOCKET` | The absolute path of the socket of the session process |
| `TERM` | `xterm-256color` |
| `COLORTERM` | `truecolor` |
| `TERM_PROGRAM` | `OpenRun` |

`OPENRUN_SOCKET` also tells `openrun` inside a session where the session process is. The tool reads it when no `--socket` flag is given.

A session process that runs from OpenRun.app also puts the folder `Contents/Helpers` of its bundle first on the `PATH` of each session, so agents find `openrun` with no setup (`HelperSearchPath`). It starts from the `PATH` that the client sent, or from the system default. A `PATH` that holds the folder already stays as it is.

## Command-line tool

```
openrun new [--folder PATH] [-- PROGRAM ARGUMENTS...]
openrun list [--json]
openrun attach IDENTIFIER
openrun read IDENTIFIER [--scrollback]
openrun send IDENTIFIER [--enter] TEXT
openrun kill IDENTIFIER
openrun rename IDENTIFIER [NAME]
openrun notify [--session IDENTIFIER] TEXT
openrun project list [--json]
openrun project add PATH [--name NAME]
openrun project remove PROJECT
openrun project rename PROJECT [NAME]
openrun settings list
openrun settings get NAME
openrun settings set NAME VALUE
openrun thread list [--json]
openrun thread new [--folder PATH] [--model MODEL] [--mode MODE] [--name NAME] [-- TEXT]
openrun thread send THREAD TEXT
openrun thread read THREAD [--json]
openrun thread stop THREAD
openrun thread rename THREAD [NAME]
openrun thread close THREAD
openrun help
```

Every command takes `--socket PATH`. Errors go to standard error with exit code 1. Wrong arguments exit with code 2: this includes `openrun help` with arguments, `openrun COMMAND-THAT-DOES-NOT-EXIST --help`, and an empty session identifier. The tool checks the arguments before it connects, so these exit with 2 whether or not a session process runs. `--help` after a real command (`openrun read abc --help`) shows the help.
`list` prints one line per session: the identifier, the folder and the command, separated by tabs. A client chose the folder and the arguments, so each field is escaped with `PrintableText.escaping`: a backslash becomes two backslashes, a tab `\t`, a new line `\n`, a carriage return `\r`, and any other control character `\u{XX}` in upper-case hexadecimal. Each session is exactly one line, and the tabs split exactly three columns. The arguments of the command are joined by one space.
`list --json` prints an object with one key, `sessions`, a list oldest first. Each session has every one of these keys, with `null` for a fact that the session process does not know: `identifier` (lower case), `name`, `title`, `folder`, `currentFolder`, `branch`, `command`, `foregroundProgram`, `isInProgress`, `alert` (`raisedAt`, `source`, `text`), `size` (`columns`, `rows`), `createdAt`, `lastOutputAt`, `lastInputAt` and `projectIdentifier` (lower case). Times are text in ISO 8601, such as `2026-11-10T09:30:00Z`. JSON escapes every control character, so the output never drives a terminal.
`rename` joins the words after the identifier, and the words after `--`, with one space. Without a name, it removes the name.
`project list` prints one line per project: the identifier in lower case, the shown name (the name, or else the last name of the folder), and the folder, separated by tabs. Each field is escaped with `PrintableText.escaping`, as in `list`. The projects with a folder come first, in their order. The projects without a folder on this Mac come last, with an empty folder column, and with an empty name when the user gave none.
`project list --json` prints an object with one key, `projects`, in the same order. Each project has the keys `identifier` (lower case), `name` and `folder`, with `null` for a name or a folder that is not set.
`project add` prints the identifier of the new project in lower case, and a new line. It sends its current folder, so a relative PATH starts there. `--name NAME` gives the project a name.
A PROJECT is a unique start of a project identifier, or the folder of the project (`ProjectMatch`). A word that starts exactly one identifier means that project. Any other word is a folder: a relative path starts at the current folder, `~` is the home folder, and the symbolic links are resolved, as the session process did when it added the project. The tool only makes a folder that does not exist standard, so the project of a deleted folder can still be removed. A word that starts more than one identifier and is the folder of no project lists the candidates.
`project rename` joins the words after PROJECT, and the words after `--`, with one space. Without a name, the project shows the name of its folder. `project remove` and `project rename` print nothing.
`settings list` prints one line for each setting, in the order of `SettingName`: the name, a tab, and the text of the value. A protected setting has a third column, `protected`, so a script that reads the first two columns can ignore it. `settings get NAME` prints the text alone. The text is the form that `settings set` takes back, such as `14`, `on`, `left`, `SF Mono`, or one line of JSON for `new-session-commands`. Only its control characters are escaped (`PrintableText.escapingControlCharacters`), so a backslash stays one backslash, and the text of `settings get` goes back through `settings set` unchanged. No valid value holds a control character.
`settings set` joins the words of VALUE, and the words after `--`, with one space, and prints nothing. A protected setting changes only from OpenRun.app, so the tool gets the message "The setting NAME is protected. Change it in the settings window of OpenRun.", unless `--answerer-requirement` names it.
The `thread` commands use the agent threads (`ThreadCommand`). A THREAD is a unique start of a thread identifier (`ThreadMatch`). The session process refuses them from a program in a session or in a thread, and the tool prints that reason.
`thread list` prints one line for each thread, oldest first: the identifier, the state, the folder and the shown name (the name, or else the title), separated by tabs and escaped as in `list`. `thread list --json` prints an object with one key, `threads`. Each thread has every one of these keys, with `null` for a fact that it does not have: `identifier` (lower case), `agent`, `name`, `title`, `folder`, `model`, `permissionMode`, `accountName`, `state`, `isProcessRunning`, `waitingMessageCount`, `createdAt`, `lastActivityAt` (ISO 8601) and `projectIdentifier` (`ListedThread`).
`thread new` makes a thread with Claude Code in the folder after `--folder`, or in the current folder, and prints its identifier. The words after `--` are the first message. `thread send` joins the words after THREAD, and the words after `--`, with one space. Both return when the session process took the message, and they do not wait for the turn.
`thread read` attaches to the thread, takes the events that the thread keeps, and leaves (`ThreadEvents`). It prints the conversation as plain text (`ThreadText`): one block for each message, tool call, file change, permission request, task, notice and turn that failed or stopped, with an empty line between two blocks. The agent chose that text, so each control character is escaped, and only the line breaks of a message stay. `thread read --json` prints each event as one line of JSON, in the form of a `threadEvent` frame.
`thread stop`, `thread rename` and `thread close` print nothing. No command answers a permission request: only OpenRun.app does that (proposal 2).
`notify` raises the alert of the session in `OPENRUN_SESSION`, or of the session after `--session`, with the words of TEXT joined by one space. It is for the hooks of an agent. When there is no such session, no session process answers within 5 seconds of `hello`, or the session process does not know the session from `OPENRUN_SESSION`, it writes `ESC ] 777 ; notify ; OpenRun ; TEXT ESC \` to `/dev/tty` instead, without waiting. OpenRun and other terminals show that as a notification. A refusal by the rule for callers is an error, with no write to the terminal, and so is a session after `--session` that the session process does not know, or an identifier that matches more than one session. `notify` exits with 0 when the alert went out and with 1 otherwise. It never exits with 2, also not for wrong arguments, because exit code 2 from a hook of Claude Code blocks the action of the agent.
Every error message that `openrun` prints has each control character escaped in the same way, including failures that the session process reports, so text from a client never drives the terminal of the caller. A message keeps its backslashes, because the session process and the modules `Projects` and `Settings` already quote the text of a client in it with `QuotedText`. So such text is escaped once (`PrintableText.escapingControlCharacters`). The tool's own line breaks stay. A message with a list, such as the sessions that start with the typed identifier, is a heading and one line for each entry (`CommandLineToolError.failureWithList`). The tool escapes each line on its own, so every entry is on its own line, and a line break inside client text shows as `\n`.

## Limits

- When a shell's prompt and input take more rows than the grid has, the shell draws part of them into the scrollback, and parts of old prompts can stay there. A window's minimum grid of 60 by 12 makes this rare. Another client can still set a smaller grid. A size from an attach applies at once, so the shell's drawing after it can still leave parts of the old prompt. So can an answer that comes after the limit of 500 ms. A shell without its line editor, such as `bash --noediting`, whose prompt turns on bracketed paste makes each new width wait for that limit. A shell in an SSH login is not the foreground program, so its prompt gets no help.
- The session process runs at most `session-limit` sessions, 100 by default. See "Facts of a session".
- The session process sees a change of folder or terminal mode only while output or input comes, and up to two seconds after it. A command that turns line mode off or on without output after that keeps its old `isInProgress` until the next output or input.
- A shell without its line editor that reads in line mode and does not lead the terminal session, such as `bash --noediting` inside another shell, counts as a command in progress.
- The session process does not survive a Mac restart. launchd starts it again at the next wake.
- A program in an SSH login is not in the launchd domain of the user's desktop and probably cannot reach the Mach service. Over SSH, `openrun` then reaches only a session process that already runs. The owner accepted this for version 1. It was not tested.
- `openrun attach` draws only the visible screen into the terminal. The scrollback of the session stays in the session. `openrun read --scrollback` prints it.
- Two clients that relay raw output (two `openrun attach` windows on one session) both answer each query, so the program gets two replies. See "Query replies".
- A query that is pending when its relaying client detaches gets no reply.
- A process that starts a session of its own (`setsid`), such as a daemon, outlives `openrun kill` and shutdown. A program that ends by itself leaves its background processes running. Both are owner decisions.
- The scrollback holds about `scrollback-limit` lines, 10,000 by default. libghostty-vt prunes whole pages, so it keeps somewhat fewer after the first prune; a test measured 9,659.
- A frame carries at most 64 MiB. An unfinished escape sequence counts at most 32 MiB of that in a snapshot. A client can lose its connection when it falls behind. An opted-in window pauses output but can still be closed for a deadline or a faster viewer. An older session process ignores the opt-in. Snapshots and screens do not count toward the 8 MiB limit. A first control frame that is larger than 8 MiB is queued whole, and the limit for a write that stalls (10 seconds) ends a client that does not read it.
- A snapshot larger than 64 MiB loses its oldest scrollback. So a client of a very wide session with a full, colorful scrollback gets only the newest lines that fit. A client cannot attach at a size at which the screens alone pass 64 MiB.
- At most 64 clients are connected at once, counting clients whose last messages still go out after they detached. While 64 such clients close, a new client is refused for up to 2 seconds. Other limits and deadlines are in "Limits and deadlines of a client". A client may still send one frame of up to 64 MiB, so 64 clients can make the session process hold 4 GiB for a moment.
- Input that a program does not read waits: 8 MiB in the session process, 1 MiB more for each client, and up to 16 MiB in `openrun attach`. At that limit `openrun attach` stops reading the terminal until the program reads, and the terminal holds the keys. The detach key then waits behind them, and a signal, such as the SIGHUP of a closed window, still ends the tool. `openrun send` returns only when its text is in the backlog. A program that never reads its input therefore makes `openrun send` wait until the program reads or ends.
- Keys that `openrun attach` typed and that have not gone to the program are dropped when it detaches or loses its connection. Text that `openrun send` was told has arrived is not dropped.
- When `openrun attach` detaches while its keys wait for the program, the `detach` message is read through the reserve of the read-ahead when it comes right behind a full read-ahead. When more keys wait in the socket in front of it, it stays stuck behind them. The session process then finds the closed connection within about 100 milliseconds and detaches the client.
- A program that asks queries and never reads the answers stops in its own output once 1 MiB of answers wait. Only answers count for this, so typed input alone never stops the output.
- Any program of the same user can connect to the socket. The socket mode, the folder check and the check of the peer's user keep other users out. The folder check looks at the folder of the socket only, not at the folders above it. It reads the mode and the access control list of that folder, not the access control lists of the socket file and the lock file.
- A stale socket file is removed by its path after a check of its device and inode. A program that replaces it in the moment between that check and the removal still loses its file. Only a program of the same user can do this, because the folder is the user's own.
- A query is recognized by its exact bytes `ESC [ 1 5 t`. `CSI 15 t` written with other parameters, such as `ESC [ 0 1 5 t`, gets no reply.
- When the terminal takes no output, `openrun attach` puts the mode back at once and gives the closing sequences one second. Sequences that do not get through in that time are lost. A closing that got only part of its bytes through is made again whole at the next closing. It starts with CAN, which ends a sequence that was cut short. The terminal can then stay inside a sequence that the program, or a picture cut short, left open, until the next output ends it.
- `openrun attach` stops itself with SIGSTOP on SIGTSTP. In a process group that no shell controls, nothing may continue it, as with any program that stops.
