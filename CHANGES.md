# CHANGES

This fork turns Warp into a fully offline terminal for enterprise use. Every call to Warp-hosted servers and services has been removed, along with Warp's built-in AI and agent features (Agent Mode, Oz, Warp AI, and others). Core terminal features stay, as does support for third-party CLI agents such as Claude Code and for integrations that the user configures to reach their own services.

Each section below covers one removal (a single commit or a small group of related commits). It lists what was removed or modified, why, and the user-visible impact. See `git log master..offline-terminal` for commit-level detail.

## Contents
<!-- One bullet per section, in commit order: - [Area](#anchor) — one-line summary -->
- [Internal specs, dev-agent config and process skills](#internal-specs-dev-agent-config-and-process-skills) — deleted Warp-internal specs, Warp dev workflows, MCP/skills lock config and Warp-process agent skills
- [Continuous integration](#continuous-integration) — replaced Warp CI, release and triage automation with one GitHub-hosted workflow (fmt, clippy, unit tests)
- [Developer scripts: Warp infrastructure](#developer-scripts-warp-infrastructure) — drop channel config, common skills, gcloud, Sentry, remote-server deploy and release tooling from `script/`, `docker/` and `.vscode/`
- [Packaging: Warp release infrastructure](#packaging-warp-release-infrastructure) — drop Warp's apt/yum/zypper repos and signing keys, the Oz CLI and Warp Agent CLI packages, Sentry, the Windows background-update path and warp.dev metadata from the installers
- [Autoupdater and release-channel update checks](#autoupdater-and-release-channel-update-checks) — removed the GUI autoupdater, channel-version and server-time fetches, update UI, the `FinishUpdate` shell hook and the Linux package-repo helpers
- [Homebrew install-method probe](#homebrew-install-method-probe) — stopped running `brew list --cask warp` at startup, which made Homebrew contact `formulae.brew.sh` and `analytics.brew.sh`
- [Crash reporting: Sentry](#crash-reporting-sentry) — remove Sentry crash and error reporting, the minidump server, Sentry heap-profile and process-sample uploads, and the crash-reporting privacy toggle; `report_error!` now only logs
- [Diff hunk types moved to the editor crate](#diff-hunk-types-moved-to-the-editor-crate) — `DiffDelta`/`DiffType` now live in `warp_editor::diff` instead of `ai::diff_validation`
- [Secret redaction and repository metadata imported directly](#secret-redaction-and-repository-metadata-imported-directly) — kept features import `secret_redaction` and `repo_metadata` instead of AI-module re-exports
- [Code-symbol outline moved out of the AI modules](#code-symbol-outline-moved-out-of-the-ai-modules) — new `crates/code_outline` crate and `app/src/code/outline/` for the `@`-menu symbol search
- [CLI output format moved out of the agent commands](#cli-output-format-moved-out-of-the-agent-commands) — `OutputFormat` now lives in `warp_cli::output_format`, next to `warpctrl`'s users
- [Offline server configuration](#offline-server-configuration) — pointed the OSS build's Warp server, RTC, session-sharing, Oz and Firebase settings at nothing
- [Channel binaries and private config loader](#channel-binaries-and-private-config-loader) — deleted the `warp`/`stable`/`dev`/`preview` GUI binaries, their channel assets and the build-time `warp-channel-config` embedding
- [Computer use and agent screen recording](#computer-use-and-agent-screen-recording) — deleted the `computer_use` crate, the agent's computer-use and screen-recording tools, stored screenshots and the related settings
- [Current input UI made permanent](#current-input-ui-made-permanent) — legacy flag-off input paths removed outside `app/src/ai`
- [Telemetry collection (RudderStack)](#telemetry-collection-rudderstack) — stopped collecting, persisting and sending usage telemetry; removed the RudderStack pipeline and the telemetry privacy toggle
- [Block sharing (web permalinks)](#block-sharing-web-permalinks) — removed the "Share block" modal, block permalinks and embeds, the Shared blocks settings page, and the related menu items, keybindings and server client
- [Referrals, rewards and referral-unlocked themes](#referrals-rewards-and-referral-unlocked-themes) — removed the Referrals page, invite entry points, the reward modal and the server referral client; the two reward themes are always available as "Nebula" and "Opal"
- [Warp TUI front-end](#warp-tui-front-end) — deleted the login-gated "Warp Agent CLI" (`crates/warp_tui`), its app integration, settings, onboarding client and TUI skills
- [TUI dev script](#tui-dev-script) — removed `script/run-tui` and the presubmit note about `warp_tui`
- [Channel-config loader crate](#channel-config-loader-crate) — deleted `crates/warp_channel_config`, which only the removed channel and TUI binaries used
- [Client and server-side experiments](#client-and-server-side-experiments) — removed the local A/B bucketing framework and the server-driven experiment state; every experiment keeps the arm new OSS users already got
- [App-installation detection and the local HTTP server](#app-installation-detection-and-the-local-http-server) — the GUI no longer listens on `127.0.0.1:9277+n`; the jemalloc heap profile is written to a local file instead of served over HTTP
- [Legacy Warp AI assistant and AI command search](#legacy-warp-ai-assistant-and-ai-command-search) — deleted the Warp AI side panel, every "Ask Warp AI" entry point, AI command search (`#`) and its server endpoints
- [SSH remote server](#ssh-remote-server) — removed the SSH extension daemon (downloaded from Warp's CDN, authenticated with Warp credentials) and every remote file, diff, git, search, indexing and agent-context backend it powered; plain SSH, SSH Warpify and blocks and completions over SSH stay
- [Natural-language detection and input auto-detection](#natural-language-detection-and-input-auto-detection) — deleted the `input_classifier` and `natural_language_detection` crates, the classifier singleton, input auto-detection and its settings, toolbar toggle and slash command
- [Session sharing: sharer side and entry points](#session-sharing-sharer-side-and-entry-points) — removed sharing a session and every share entry point (menus, keybindings, palette, `/remote-control`, tab indicator, quit and close warnings); viewing stays until SS-2
- [Settings cloud sync](#settings-cloud-sync) — removed the Warp Drive settings syncer, the "Settings sync" switch, the "not synced" icons and the cloud-sync APIs of the settings crate; settings are local only
- [Workspace LSP metadata moved out of the AI module](#workspace-lsp-metadata-moved-out-of-the-ai-module) — `PersistedWorkspace` (known repos and per-repo language-server enablement) now lives in `app/src/workspace_metadata/`
- [Codebase indexing and project rules](#codebase-indexing-and-project-rules) — removed codebase indexing (embeddings synced to Warp's servers), project rules (`AGENTS.md`/`WARP.md` as agent context), `/init`, `/index` and `/open-project-rules`; Settings > Code > Projects now lists each repo's language servers
- [TUI rendering layer and TUI modes in the core crates](#tui-rendering-layer-and-tui-modes-in-the-core-crates) — deleted the ratatui-backed TUI element library, presenter and runtime from `warpui_core`, the char-cell editor layout, and the TUI settings, logging and execution modes
- [Changelog](#changelog) — removed the changelog model, the "What's New?" resource-center section, the changelog toast and its setting, `/changelog`, the "What's new" and "View latest changelog" entry points and the agent zero-state "Latest updates" section
- [Docker sandbox sessions and local child-agent harnesses](#docker-sandbox-sessions-and-local-child-agent-harnesses) — removed `sbx` Docker sandbox tabs, `/docker-sandbox`, the sandbox shell type and the agent-SDK launcher for local Claude Code/Codex child agents
- [Oz CLI and agent SDK](#oz-cli-and-agent-sdk) — deleted the `oz` command-line interface (every agent, environment, schedule, secret, MCP, memory, artifact and runner subcommand plus `login`/`logout`/`whoami`/`--api-key`), the headless agent SDK driver behind it, and the harness-support/harness-usage server clients
- [Cloud-agent OpenTelemetry trace export](#cloud-agent-opentelemetry-trace-export) — removed the OTLP span exporter that cloud-agent processes sent traces to Warp with, its dispatch-token credential refresh and the `X-Warp-Traceparent` request header
- [Agent build cache and harness usage crates](#agent-build-cache-and-harness-usage-crates) — deleted `crates/build_cache` (persistent build caches for sandboxed cloud agents) and `crates/warp_harness_usage` (usage accounting for third-party harness histories)
- [Hosted web client ties to app.warp.dev](#hosted-web-client-ties-to-appwarpdev) — removed the web client's address-bar sync, open-in-desktop flows, host-page auth handoff and events, remote fonts and assets, and the desktop rewrite of Warp web links into app intents
- [remote_tty websocket terminal transport](#remote_tty-websocket-terminal-transport) — deleted the web/dev-only PTY-over-websocket transport and its `remote_tty` Cargo feature
- [Web client crates, scripts and build profiles](#web-client-crates-scripts-and-build-profiles) — deleted the wasm bundle/serve scripts, the `serve-wasm`, `warp_web_event_bus` and `managed_secrets_wasm` crates, and the wasm Cargo profiles
- [Warp Drive: panel, menus, actions and deep links](#warp-drive-panel-menus-actions-and-deep-links) — removed the Drive panel and index, its left-panel tab, menu, create/import actions, palette source, settings page, `warp://drive` links and web intents; local workflows now always show in command search
- [Warp Drive: sharing, export and cloud-object dialogs](#warp-drive-sharing-export-and-cloud-object-dialogs) — removed the sharing/guest/link-sharing dialog and pane-header share button, Drive export, the grab-edit-access modal, cloud-object activity toasts and the shared-object limit banner settings
- [Language server downloads are opt-in](#language-server-downloads-are-opt-in) — the LSP crates can only download with a permit built from the new `allow_language_server_downloads` setting (default off); missing servers show a manual install hint instead of an install button
- [AI command prediction and passive suggestions](#ai-command-prediction-and-passive-suggestions) — deleted Agent Predict (AI next-command and prompt ghost text), prompt suggestions, suggested code-diff banners, their settings and server endpoints; history-based autosuggestions and command corrections are unchanged
- [AI-generated commit messages, pull request text and block titles](#ai-generated-commit-messages-pull-request-text-and-block-titles) — the code-review commit and create-PR dialogs no longer ask Warp's AI for text; removed the two text-generation settings and the now-empty Active AI settings category
- [CLI-agent support moved out of the AI module](#cli-agent-support-moved-out-of-the-ai-module) — CLI agent settings, review/diff and image types, agent status and notifications now live outside `crate::ai`
- [AI gates removed from CLI-agent support](#ai-gates-removed-from-cli-agent-support) — the CLI agents settings page, Rich Input auto-open/auto-toggle and Rich Input image paste no longer depend on AI being enabled
- [Accounts: login, sign-up and SSO](#accounts-login-sign-up-and-sso) — removed every login, sign-up, SSO, web-handoff, paste-token and reauth flow and the Account page; the app is permanently in the no-account state and deletes the previously stored credential once
- [Rules, facts, memory and saved prompts](#rules-facts-memory-and-saved-prompts) — removed the AI Rules (Knowledge) pane and settings page, agent memory and rule suggestions, saved prompts (Agent Mode workflows) and their slash commands, menus, panes and modals
- [CLI-agent footer split out of the agent footer](#cli-agent-footer-split-out-of-the-agent-footer) — the third-party CLI agent toolbar is now its own `CLIAgentFooter` view in `terminal/view/cli_agent_footer/`, with its own item type, layout editor and lenient stored-layout parsing
- [MCP (Model Context Protocol)](#mcp-model-context-protocol) — deleted the `mcp` crate, the MCP server managers, gallery, OAuth and file-based discovery, the MCP settings page, Drive item and slash commands, the agent's MCP tool and resource actions, MCP execution-profile permissions and the Figma MCP prompt chip
- [Launch, feature-intro and vertical-tabs intro modals](#launch-feature-intro-and-vertical-tabs-intro-modals) — deleted the Oz, OpenWarp, orchestration and Warp Agent CLI launch modals, the feature-intro popover and the vertical-tabs intro flow, with their one-time flags and debug actions
- [Onboarding: AI slides, callout tutorial and Get Started](#onboarding-ai-slides-callout-tutorial-and-get-started) — onboarding is now four slides (welcome, customize, CLI agents, theme); removed the agent-intention flow, the AI-access and offer slides, the in-terminal callout tutorial that started an agent, the Get Started pane and coding entrypoints
- [Skills](#skills) — deleted the skills feature (`SKILL.md` discovery, the `/skills` and `/open-skill` commands, the `@`-menu skills category, the `read_skill` tool, bundled and channel-gated skill files) and the "Fix with Warp Agent" and tab-config-editor agent buttons that invoked bundled skills
- [AI plan documents and to-do popup](#ai-plan-documents-and-to-do-popup) — removed the plan (AI document) pane, the plan menu and plan/to-do chips, the to-do popup and the plan-related shortcuts and attachments
- [Voice input](#voice-input) — deleted voice input end to end (microphone capture, Wispr Flow transcription through Warp's server, the mic buttons, the toggle-key shortcut, the `/voice` command and the voice settings), plus the unused `WarpDriveContextEnabled` setting

- [Warp Drive: environment-variable collections](#warp-drive-environment-variable-collections) — removed the environment-variable collection objects, editor pane, invocation blocks, subshell invocation, workflow env-var selectors and the search filter
- [Warp Drive: 1Password and LastPass secrets](#warp-drive-1password-and-lastpass-secrets) — removed the external secret manager integration, whose only entry point was environment-variable collections
- [Session sharing: viewer, joins and shared-session model state](#session-sharing-viewer-joins-and-shared-session-model-state) — removed joining and viewing another user's shared session (the viewer network, presence, tombstones, join links and the viewer paths through the terminal model, input, panes and workspace) and the shared-session state and replication in the terminal model and input editor
- [Session-sharing protocol dependency](#session-sharing-protocol-dependency) — dropped the `session-sharing-protocol` crate and its patch entry, so no crate can build the relay wire types
- [Warp-distributed CLI-agent plugins](#warp-distributed-cli-agent-plugins) — removed the install/update flows, the "Enable notifications" chips, the manual-instructions pane and the OpenCode debug actions for the `claude-code-warp`, `codex-warp`, `gemini-cli-warp` and `opencode-warp` plugins; the OSC 777/9 listener stays
- [Agent tips](#agent-tips) — removed the rotating "Tip:" line under the agent warping indicator and the cloud-mode loading screen, the Show agent tips setting and its toggle
- [Cloud mode, ambient-agent terminal UI and handoff](#cloud-mode-ambient-agent-terminal-ui-and-handoff) — removed the cloud-agent terminal (setup, follow-up input, tombstones, queued cloud prompts), local-to-cloud and cloud-to-cloud handoff, auto-handoff on sleep, the cloud environment and host selectors and the cloud slash commands, tab types, panes and settings
- [Tolerant stored inline-menu heights](#tolerant-stored-inline-menu-heights) — stored per-menu heights ignore keys of removed menus (`skill_menu`, `prompts_menu`, `plan_menu`) instead of failing to parse and discarding all heights
- [Repository metadata: standing queries and force-included paths](#repository-metadata-standing-queries-and-force-included-paths) — removed the skill-only standing-query results, force-included path list and `StandingQueryResultsUpdated` events from `repo_metadata`
- [AI credits, usage, billing and promotions UI](#ai-credits-usage-billing-and-promotions-ui) — removed the AI request-usage and credit-availability models, the buy-credits banner and auto-reload modal, the usage popover, Turn panel and usage footer, the Billing and usage settings page, and the pricing-promotion, free-AI-removal, build-plan-migration and Codex modals
- [Cloud notebooks](#cloud-notebooks) — removed Warp Drive notebooks: the notebook pane and view, the notebook manager, edit-access batons, embedded Drive workflows in the markdown editor, notebook search (`notebooks:` filter, `@` menu category, embed picker) and the plan-notebook buttons; the local markdown file viewer stays
- [Integration test triage](#integration-test-triage) — deleted the two integration tests for the removed Warp Drive "Create a New Personal/Team Workflow" actions; documented the remaining failures (SSH tests that need a gcloud IAP tunnel to a Warp-owned GCP VM)
- [Persisted values of removed enum variants](#persisted-values-of-removed-enum-variants) — audit of settings, sqlite state and user files for removed enum variants; a removed pane kind no longer costs the whole tab, a stale `mcp_server` pane row no longer blocks saving the session, and stale prompt chips, welcome tips and non-workflow YAML documents no longer discard their neighbours
- [Ambient-agent task model, cloud-load path and restoration](#ambient-agent-task-model-cloud-load-path-and-restoration) — removed the ambient-agent spawn, GitHub-auth and telemetry code, the cloud conversation and task fetch/poll/RTC path of `AgentConversationsModel`, `AmbientAgentTaskId` plumbing in terminal, pane and workspace code, the CLI-agent cloud transcript branch and `AgentViewEntryOrigin::{CloudAgent, ThirdPartyCloudAgent}`; deleted `presigned_upload.rs` and the `AIClient` spawn, attachment and follow-up calls
- [Retired cloud values in settings and tab configs](#retired-cloud-values-in-settings-and-tab-configs) — a `cloud` tab-config pane opens as a terminal; retired `cloud_agent`/`docker_sandbox` default session modes read as Terminal
- [Orchestration and child agents](#orchestration-and-child-agents) — removed multi-agent orchestration: the `run_agents`/`start_agent`/`send_message_to_agent`/`wait_for_events` tools, the orchestration pill bar, child-agent panes, the inter-agent event streams and the `/orchestrate` command
- [Cloud workflows](#cloud-workflows) — removed Warp Drive workflows: the workflow pane and modal, workflow aliases and enums (static and dynamic), "Save as workflow", AI metadata generation, the cloud-workflow sync plumbing and the Shared Workflows plan counter; local, project, global and app workflows stay, with text-only arguments
- [Settings: Warp Agent, profiles, custom models and cloud platform pages](#settings-warp-agent-profiles-custom-models-and-cloud-platform-pages) — removed the Warp Agent and Agent profiles settings pages, the profile and custom-router editor panes, the Cloud platform group (Environments, API keys) and the AI toggles on the Features and Privacy pages; Third party CLI agents is now a top-level settings page
- [Plans, billing, pricing and upgrade prompts](#plans-billing-pricing-and-upgrade-prompts) — removed the pricing model, plan/tier gating for shared objects, purchase, overage and add-on credit APIs, the billing and admin-panel links on the Teams page, every "Upgrade" call to action, and the plan/billing GraphQL types
- [Cloud environments, schedules, runners, managed secrets and isolation platform](#cloud-environments-schedules-runners-managed-secrets-and-isolation-platform) — removed Oz cloud environments, scheduled agents, self-hosted workers and runners, Oz API keys, managed secrets, the isolation platform, the Gemini Enterprise and OIDC Bedrock credential mints, and `OzConfig`
- [Agent management view and conversation list](#agent-management-view-and-conversation-list) — removed the agent management view, the left-panel conversation list and its delete dialog, the header-toolbar and `warpctrl` entries for them, and the legacy Warp-agent toast; notifications, tab icons and the notifications mailbox now describe CLI-agent sessions only
- [Offline guardrails (draft)](#offline-guardrails-draft) — `script/offline_audit`, its allowlist, cargo-deny bans with wrappers and a non-blocking `offline-audit` CI job that report what still reaches Warp services
- [Default session mode is a terminal setting](#default-session-mode-is-a-terminal-setting) — the Settings > Features default-mode dropdown no longer greys out without AI, and the Agent mode is gone; the default tab config applies to new tabs
- [Workspace shell: agent tabs, agent deep links and the Oz session type](#workspace-shell-agent-tabs-agent-deep-links-and-the-oz-session-type) — removed the New Agent Tab command and its menu items, binding and URI, the agent-mode tab and pane actions, the `warp://conversation` and `warp://linear` deep links, the Oz and agent tab-config types, the code-diff pane, the palette's conversation search and the workspace's AI subscriptions and context flags

<!-- Section template (copy for each removal, append new sections at the end of the file):

## <Area>
**Why:** <reason it was removed or changed>

**Removed:**
- `<crate / module / file / feature flag / setting>` — <what it did>

**Modified:**
- `<path>` — <what changed and why>

**User-visible impact:** <what a user will notice>

**Notes:** <stubs left behind, follow-ups, open questions>
-->

## Internal specs, dev-agent config and process skills
**Why:** These files described Warp's internal product/engineering process (feature specs, release and changelog tooling, issue triage, cloud verification on Oz runners, telemetry) or configured tools that fetch Warp-hosted content. None of it applies to an offline enterprise fork, and several skills instruct coding agents to call Warp services.

**Removed:**
- `specs/`, `agents/specs/`, `.agents/specs/` — Warp product and tech specs for past and in-flight features.
- `.warp/` — Warp-team workflows (release cherry-picks, feature-release PRs against `warp-internal`, keychain copy for Warp-Dev auth, bundling by channel) and the `gui-integration-test-video` skill.
- `.warpindexingignore` — ignore list for Warp's AI codebase indexing of this repo.
- `.mcp.json` — project MCP config that launched the GitHub MCP server via `npx`.
- `skills-lock.json` — lock file pinning shared skills fetched from `warpdotdev/common-skills`.
- `.agents/skills/` (also visible through the `.claude/skills` symlink): `add-telemetry`, `changelog-draft` (with its scripts), `classify-changelog-pr`, `cross-platform-cloud-verification`, `dedupe-issue-local`, `triage-issue-local`, `review-pr-local`, `gui-onboarding-verification-skill`, `gui-reproduce-bug-report-local`, `tui-verify-change`, `gui-create-launch-modal`. These covered Warp telemetry, the changelog/release process, warpdotdev issue triage, Oz cloud-agent runners, `WARP_API_KEY` dogfood builds, and a launch modal that depends on sign-in state and cloud-synced settings.

**Modified:**
- None. The remaining generic engineering skills (`add-feature-flag`, `remove-feature-flag`, `gui-integration-test`, `gui-settings-ui`, `gui-ui-guidelines`, `rust-unit-tests`, `tui-testing`, `tui-ui-guidelines`, `promote-feature`, `logging-and-error-reporting`) are left unedited for a later rewrite.

**User-visible impact:** None for terminal users. Contributors lose the Warp-internal specs, workflows and process skills. Coding agents no longer have access to the removed skills.

**Notes:** No build script, `include_str!` or `include_dir!` referenced the deleted paths. The `specs/` copy in `flake.nix` targets the vendored `warp-workflows` git dependency, not this repo. References left for later tasks:
- `script/bootstrap`, `script/run`, `script/resolve_common_skills`, `script/windows/bootstrap.ps1` still install skills from `warpdotdev/common-skills`. They recreate `skills-lock.json` by fetching from GitHub.
- `AGENTS.md`, `CONTRIBUTING.md` and `FAQ.md` still describe `specs/`, `skills-lock.json` and the common-skills install.
- Kept skills still name deleted skills: `tui-verify-change` in `gui-integration-test`, `gui-ui-guidelines` and `tui-ui-guidelines`, and `gui-integration-test-video` in `gui-integration-test`, `rust-unit-tests` and `tui-testing`.
- Code comments cite deleted specs by path: `app/src/settings_view/mcp_servers_page.rs`, `app/src/settings_view/mcp_servers_page_tests.rs`, `app/src/settings_view/mcp_servers/list_page.rs`, `app/src/settings_view/mod_tests.rs`, `app/src/preview_config_migration.rs`, `app/src/terminal/model/session/command_executor.rs`, `app/src/ai/blocklist/block/view_impl/common.rs`, `crates/warp_util/src/git.rs`, `crates/warp_server_client/src/base_client.rs`, `crates/warp_multi_agent_client/src/lib.rs`.
- The app's own handling of `.warp/`, `.mcp.json` and `.warpindexingignore` in users' projects is product code and is unaffected by this change.
- `.github/workflows/changelog_draft.yml` and `create_release.yml` call the deleted `changelog-draft` skill. The CI replacement commit removes them.

## Continuous integration
**Why:** Warp's GitHub automation ran on Warp infrastructure and called Warp services: Namespace and larger-runner pools, GCP workload identity for SSH tests, Trunk test analytics, the private `warp-channel-config` repo via `WARP_CHANNEL_CONFIG_ACCESS_SSH_KEY`, Sentry uploads, Apple notarization, Azure code signing, `OZ_MGMT_*` cloud-agent jobs, Slack notifications, and repo-sync to `warp-internal`. None of that is available or wanted in an offline enterprise fork.

**Removed:**
- `.github/workflows/`: all 21 workflows (Warp CI, release cutting, create/delete release, changelog draft, build-cache population, agent-dev image publish, repo-sync, PR-check sync, approval checks, stale/fix-PR cleanup, external-contributor labelling, docs notifications, feature-flag cleanup, docubot, and the dedupe/triage/PR-review skill updaters), plus `README.md` and `release_configurations.json` (release-channel, Sentry and Slack settings).
- `.github/actions/`: `prepare_environment`, `get_channel_config`, `docubot` and `bundle_arch_package`.
- `.github/STAKEHOLDERS`, `.github/issue-triage/`, `.github/scripts/`, `.github/PULL_REQUEST_TEMPLATE/` (cherry-pick and feature-flag release templates).
- `.github/ISSUE_TEMPLATE/config.yml` (contact links to Warp docs, Slack, Discord and the website) and the SSH-specific issue templates `03_ssh_tmux.yml` and `04_ssh_legacy.yml`.

**Modified:**
- `.github/workflows/ci.yml` — new minimal workflow for `push` and `pull_request` on `ubuntu-latest`. It has three jobs: `./script/format --check`; `cargo clippy --locked --workspace --all-targets -- -D warnings`; and `cargo nextest run --locked --workspace -E 'not package(integration)'` (nextest installed with `taiki-e/install-action`). It installs the apt build and test packages from `script/linux/install_build_deps`, `install_runtime_deps` and `install_test_deps`, uses `protobuf-compiler` from apt, and pulls Git LFS objects. It uses no secrets. A `TODO(offline-audit)` comment marks where the offline-audit job goes.
- `.github/ISSUE_TEMPLATE/01_bug_report.yml`, `02_feature_request.yml` — generic forms with no Warp links, AI debugging IDs or Linear labels. The bug report has an optional session-type field (local/SSH) in place of the separate SSH templates.
- `.github/pull_request_template.md` — generic description, testing and checklist sections, including a reminder to update `CHANGES.md`. The Agent Mode checkbox and the `CHANGELOG-*` lines are gone.
- `.github/dependabot.yml` — dropped the private `github-private` registry and its PAT secret, the `warpdotdev/tech-leads` assignees and the Namespace action group. Cargo security updates and grouped GitHub Actions updates remain.

**User-visible impact:** None in the app. Contributors get one CI check, which runs on GitHub-hosted runners. CI no longer runs integration tests, doc tests, Windows/macOS/wasm builds, release-flag compilation, license, WGSL or ShellCheck checks, or Diesel schema checks. Releases are no longer cut or published automatically.

**Notes:**
- Scripts with no remaining callers: `script/sentry_upload_dif.sh`, `script/sentry_create_release.sh`, `script/create_release_tag_and_branch`, `script/push-dev-image`, `script/deploy_remote_server_to_test_vm`, `script/linux/sign_arch_packages`, `script/windows/build_inno_sign_tool_command.ps1`, `script/windows/test_tui_installer.ps1`. `docker/agent-dev/Dockerfile` was only built by the deleted image-publish workflow.
- Comments that cite deleted workflows: `script/install_cargo_test_deps` (wgslfmt version kept in sync with `ci.yml`), `script/linux/bundle` and `crates/remote_server/src/preinstall_check.sh` (both cite `create_release.yml`).
- `AGENTS.md` and `CONTRIBUTING.md` still tell contributors to add `CHANGELOG-*` lines from the PR template.
- The build still fetches git dependencies from `github.com/warpdotdev/*` repos listed in `Cargo.lock`.

## Developer scripts: Warp infrastructure
**Why:** The developer scripts pulled a private config tool from Warp's GitHub, fetched Warp's shared agent skills from `warpdotdev/common-skills`, required a Google Cloud login, uploaded to Sentry and GCS, and deployed to Warp's VMs and image registry. None of that works offline or without Warp accounts.

**Removed:**
- `script/install_channel_config` — installed the private `warp-channel-config` tool. `warp-oss` does not need it.
- `script/resolve_common_skills` — downloaded Warp's shared agent skills from `warpdotdev/common-skills`. `skills-lock.json` was already removed with the process skills. The `--install-common-skills*` / `--skip-common-skills` flags and the `WARP_SKIP_COMMON_SKILLS_INSTALL` / `WARP_COMMON_SKILLS_*` variables are gone.
- `script/sentry_create_release.sh`, `script/sentry_upload_dif.sh`, `script/macos/update_sentry_cocoa` — created Sentry releases, uploaded debug files and downloaded the Sentry Cocoa SDK.
- `script/deploy_remote_server`, `script/deploy_remote_server_to_test_vm` — deployed the SSH remote server to dev hosts and Warp's GCP test VM.
- `script/push-dev-image`, `docker/agent-dev/` — built and pushed the cloud-agent / warp-server development image.
- `script/create_release_tag_and_branch` — Warp's release tagging workflow.
- `script/test_factory_files_skill.py` — tests for the factory-files skill, which validates against warp-server. Removed from `script/presubmit` too.
- `script/font_fallback/` — regenerated font fallback tables from `gs://warp-static-assets`. Also removed its `downloaded_fonts` entry from `.gitignore` and `.dockerignore`.

**Modified:**
- `script/run` — always builds `warp-oss`. Removed the channel config install, local/OSS detection, common-skills install, the `--host-id` cloud-mode flag and the legacy `with_local_server` / `with_local_session_sharing_server` / `with_sandbox_telemetry` feature mapping (those variables were read only by `warp-channel-config`). It now passes only `FEATURES` to `script/macos/run`.
- `script/macos/run` — builds `WarpOss.app` only. Removed the WarpLocal paths, `FRAMEWORK_OVERRIDE`, the `cocoa_sentry` framework copy and the Sentry-only rpath step.
- `script/run-tui` — always builds `warp-tui-oss`. No channel config.
- `script/install_cargo_build_deps` — no channel config install.
- `script/bootstrap`, `script/macos/bootstrap`, `script/linux/bootstrap`, `script/windows/bootstrap.ps1` — removed gcloud install and auth, `--skip-gcloud-auth` / `WARP_SKIP_GCLOUD_AUTH`, common-skills installation and `sentry-cli`.
- `script/linux/install_test_deps`, `docker/linux-dev/` — no Google Cloud apt repo or `google-cloud-cli`. The README no longer mounts `~/.config/gcloud` and runs `warp-oss`.
- `script/wasm/bundle`, `script/wasm/run` — removed the channel-config feature mapping. The local wasm run uses the `oss` channel.
- `.vscode/tasks.json`, `.vscode/launch.json` — removed the WarpLocal, local session-sharing, `with_local_server` and `fast_dev` configs. The remaining build and debug configs use `warp-oss` / `WarpOss.app`.

**User-visible impact:** None for end users. Developers need no Google Cloud account and no access to Warp's private repos. `./script/run` and `./script/bootstrap` no longer download anything from Warp.

**Notes:** `app/build.rs` still calls the deleted `update_sentry_cocoa` when the `cocoa_sentry` feature is on. The default build does not enable it, and removing Sentry from `app/` and `Cargo.toml` is a separate change. `AGENTS.md` still documents the common-skills flags, `resolve_common_skills` and `WITH_LOCAL_SERVER`, and will be updated separately.

## Packaging: Warp release infrastructure
**Why:** The Linux, macOS and Windows packaging registered Warp's package repositories and signing keys on user machines, packaged Warp's cloud-agent CLIs, linked Sentry, signed with Warp's Apple team, supported the auto-updater's silent install, and pointed at warp.dev. An offline enterprise build must not contact or trust Warp's release servers.

**Removed:**
- `resources/linux/debian/common/postinst.repo.template`, `postrm.repo.template` — installed Warp's GPG key and the `releases.warp.dev` apt source on install, and removed them on purge.
- The `%post` GPG key and yum/zypper repo setup in `resources/linux/rpm/app/warp.spec.template`.
- `resources/linux/{debian,rpm,arch}/cli/` — packages for the Oz CLI ("the orchestration platform for cloud agents").
- The `cli` (Oz CLI) and `tui` (Warp Agent CLI, `warp_tui`) artifacts in `script/linux/bundle`, `script/macos/bundle` and `script/windows/bundle.ps1`, including the `oz` binary renames and `-stable` package suffix logic.
- `script/windows/tui-installer.iss`, `script/windows/test_tui_installer.ps1` — the Warp Agent CLI installer and its test.
- `script/macos/add_framework_rpath` — added the Frameworks rpath needed only for the Sentry framework.
- The Windows installer's `/update=1` background-update path: waiting on the app mutex, force-killing the running app and cleaning up the minidump crash reporter.

**Modified:**
- Linux package metadata (`control.template`, `warp.spec.template`, `PKGBUILD.template`) — the maintainer and vendor are now `OpenRun Maintainers`, the homepage is `https://github.com/cristianvega-ai/openrun`, the license is `AGPL-3.0-only`, and the description no longer advertises AI or Warp Drive.
- `script/linux/bundle_{deb,rpm,arch,appimage,install}` — removed the repo naming (`warpdotdev*`) and the repo template appends. RPM signing now runs only when `RPM_SIGNING_KEY_ID` is set, with no `rpm --import` from `releases.warp.dev`.
- `script/linux/bundle`, `script/windows/bundle.ps1`, `script/macos/bundle` — removed `crash_reporting` / `cocoa_sentry` from the default features, along with `FRAMEWORK_OVERRIDE` and the `frameworks_dir` output. `warpctrl` is the only standalone artifact left. The in-app CLI wrapper is named `warp-<channel>` (`warp-oss` for OSS) instead of `oz*`.
- `script/macos/bundle` — codesigning and notarization now read `APPLE_TEAM_ID` and `WARP_NOTARIZATION_APPLE_ID` from the environment instead of Warp's hard-coded team ID. Removed the GCP Secret Manager note and the note tied to a Warp account. `--selfsign` and `--nosign` still work without any credentials.
- `script/windows/windows-installer.iss` — the publisher is `OpenRun Maintainers`. The publisher and support URLs point to the fork's GitHub. `AppUpdatesURL` was removed, and `AppMutex` always prompts the user to close a running instance.
- `flake.nix` — neutral description, and the homepage is the fork's GitHub.
- `script/linux/test_bundle_warpctrl`, `script/macos/create_warpctrl_wrapper` — updated for the new feature set and dropped the Oz wording.

**User-visible impact:** Installing a .deb or .rpm no longer adds a Warp package repository or trusts Warp's signing key, so the system package manager never contacts `releases.warp.dev`. No Oz CLI or Warp Agent CLI packages or installers are produced. Windows installers no longer offer an update URL or support silent background updates.

**Notes:** Bundle identifiers (`dev.warp.*`), the `warposs://` scheme, `/opt/warpdotdev/` install paths, `warp-terminal*` package names and the Windows `Software\Warp.dev\` registry key are unchanged on purpose, so installed data and preferences stay where they are. The bundle scripts still accept the local/dev/preview/stable channels, whose binaries are being removed separately.

## Autoupdater and release-channel update checks
**Why:** The GUI autoupdater polled Warp's server (`/client_version`, `/client_version/daily`, `/current_time`) and `releases.warp.dev` (`channel_versions.json`, release bundles, `changelog.json`). It downloaded and installed new builds and relaunched the app. On Linux it offered to add Warp's apt/yum/zypper/pacman repositories and maintainer signing key. An offline enterprise build must not contact Warp's release infrastructure or replace itself; administrators distribute updates.

**Removed:**
- `app/src/autoupdate/` — the `AutoupdateState` and `RelaunchModel` singletons, the update poll loop and the platform installers:
  - macOS: bundle download, swap and relaunch, and old-executable cleanup.
  - Linux: package-manager detection and the "Install Update" tab that pre-filled apt/dnf/zypper/pacman commands, including the one-time setup of the `releases.warp.dev/linux/pacman` repo and the `linux-maintainers@warp.dev` PGP key.
  - Windows: installer download, the `/update=1` relaunch and installer-log error reporting.
  - The changelog fetch helpers (`get_current_changelog`, `fetch_channel_versions` with its `releases.warp.dev` fallback).
- `ServerApi::fetch_channel_versions`, `ServerApi::server_time` with its cache, `ServerTime` (used only for update-by deadlines) and `FETCH_CHANNEL_VERSIONS_TIMEOUT`. `ServerTime` is also gone from `RootView`, `WorkspaceArgs` and `Workspace::new`.
- Workspace update UI:
  - the "Update Warp" tab-bar pill and its overflow menu
  - the update items and red update dot on the avatar menu
  - the out-of-date, unable-to-update and unable-to-launch banners
  - the banner "More info" button, which only linked to the update-failure docs
- Workspace actions `ApplyUpdate`, `DownloadNewVersion`, `CheckForUpdate`, `AutoupdateFailureLink` and `ToggleTabBarOverflowMenu`. Also the `workspace:update_and_relaunch` and `workspace:check_for_updates` bindings, the `AutoupdateState_UpdateReady` key context, the `AutoUpdate` binding group, `Icon::AutoUpdate` with `bundled/svg/autoupdate.svg`, and `ContextFlag::PromptForVersionUpdates`.
- Settings: the update status and the "Check for updates", "Relaunch Warp" and "Update Warp manually" links in the Account page's `VersionInfoWidget`. Also `MainPageAction::{Relaunch, DownloadUpdate, CheckForUpdate}`, `MainSettingsPageEvent::CheckForUpdate` and `SettingsViewEvent::CheckForUpdate`.
- The resource center's version footer, which only appeared alongside the autoupdate menus.
- Startup and shutdown hooks in `lib.rs`: `check_and_report_update_errors`, `remove_old_executable`, spawning the updated app on quit, applying a pending update on quit and cancelling a relaunch. Also the daily update check after login in `auth_manager.rs`.
- The hidden `--finish-update` CLI flag (`warp_cli::AppArgs::finish_update`, `finish_update_flag()`), the `IgnoredAfterAutoUpdate` single-instance exception on Linux and Windows, and `from_relaunch` in the `AppStartup` telemetry payload.
- `AppExecutionMode::can_autoupdate`.
- The `FinishUpdate` shell hook: `DProtoHook::FinishUpdate`, `FinishUpdateValue`, the `finish_update` ANSI handler callback and the terminal `FinishUpdate` event.
- Shell bootstrap functions `warp_finish_update` and `warp_handle_dist_upgrade` (bash, zsh, fish) and `Warp-Finish-Update` and `Warp-Handle-DistUpgrade` (PowerShell). The dist-upgrade function restored `warpdotdev.list` after an Ubuntu release upgrade so apt could reach `releases.warp.dev`. The Rust side only ever inserted them into the "Install Update" tab, and nothing else in the bootstrap calls them.
- The Linux "Package type" line in `warp dump-debug-info`.
- The `memchr` dependency of `app` and its `[workspace.dependencies]` entry; only the Windows installer-log parser used it. The `memchr` profile override stays because other crates still pull it in.

**Modified:**
- `crates/warp_core/src/platform.rs` — new `TargetOS` enum (`MacOS`, `Linux`, `Windows`). `ShellType::rc_file_paths` in `warp_terminal` and the Warpify success block use it instead of `channel_versions::overrides::TargetOS`, and `warp_terminal` no longer depends on `channel_versions`.
- `app/src/changelog_model.rs` — minimal compile fix. `check_for_changelog` no longer fetches anything and reports "no changelog" immediately, which is what the OSS channel already received. Its response-parsing helpers are deleted.
- `app/src/settings_view/main_page.rs` — `VersionInfoWidget` shows only the version and its copy button, and its search term is now "version".
- `crates/integration/src/test.rs` — `test_open_and_close_context_menu_with_keybinding` asserted that the removed tab-bar overflow menu was closed. It now asserts that the block context menu is closed, like the other close-menu steps.
- Comments that described autoupdate behavior in `appearance.rs`, the `lib.rs` termination hooks and `settings/tui_autoupdate.rs`.

**User-visible impact:** Warp no longer checks for, downloads or installs updates. It shows no update banners, pills or menu items, and never offers commands that add Warp's package repositories or signing key. Settings > Account and Settings > About still show the version with a copy button. New versions are installed through your own distribution channel.

**Notes:**
- `AutoupdateConfig`, `ChannelState::show_autoupdate_menu_items` and `ChannelState::releases_base_url` in `crates/warp_core/src/channel/*` are no longer used by the GUI; CFG-1 deletes them. `FeatureFlag::{Autoupdate, AutoupdateUIRevamp}` and the `autoupdate` and `autoupdate_ui_revamp` Cargo features stay for FLAGS-1.
- The autoupdate telemetry variants in `server/telemetry/events.rs` (`UnableToAutoUpdateToNewVersion`, `AutoupdateRelaunchAttempt` and the Windows installer events) are never emitted now. TEL-4 deletes the file.
- `ChangelogModel` stays for CHG-1, including its now-unused `server_api` field and constructor argument.
- `crates/channel_versions` stays: `ChangelogModel` (`Changelog`), `app/src/ai/block_context.rs` (`TargetOS`) and the TUI autoupdater (`crates/warp_tui`, `app/src/settings/tui_autoupdate.rs`) still use it. SRV-1 deletes the crate.
- The TUI's own autoupdater, including its `/update=1` Windows installer path, is out of scope and goes with the TUI. W0-B handles the installer `.iss` scripts.

## Homebrew install-method probe
**Why:** On every startup without a signed-in user (the normal state of this build), the app ran `brew list --cask warp` to find out whether Warp came from Homebrew. The only use of the answer was the `DownloadSource` telemetry event. Running `brew` makes Homebrew contact `formulae.brew.sh` and post to `analytics.brew.sh`, a third-party network side effect of starting the terminal.

**Removed:**
- `app/src/download_method.rs` (`determine_and_report`, `check_download_source`) and its call in `lib.rs`.

**Modified:**
- None.

**User-visible impact:** None visible. Warp no longer runs `brew` at startup, so Homebrew no longer makes network requests on its behalf.

**Notes:**
- The `DownloadSource` type and `TelemetryEvent::DownloadSource` in `server/telemetry/events.rs` are never emitted now. TEL-4 deletes them.
- No other subprocess of `brew`, `mas`, `winget`, `apt`, `dnf` or `pacman` was used for update or install detection outside the autoupdater removed in the previous section. `crates/build_cache` only checks whether `brew` and `apt-config` are on `PATH` to pick build-cache modes, and runs neither.

## Crash reporting: Sentry
**Why:** Crash and error reporting sent panics, native crashes (minidumps and Cocoa exception reports), `report_error!` events, log breadcrumbs, SQLite errors, heap profiles and process samples to Warp's Sentry project. The macOS build could also download the Sentry Cocoa SDK at build time. An offline enterprise build must not upload diagnostics to a Warp-owned service.

**Removed:**
- `app/src/crash_reporting/` — Sentry init/uninit, tags (application stage, GPU device, antivirus product, virtual environment, windowing system, client type, task ID, experiment groups, settings page), user identity, the `Crash` debug helper, and the Linux/Windows minidump server (`sentry_minidump.rs`).
- `app/src/platform/mac/objc/crash_reporting.{h,m}` and, in `app/build.rs`, `build_and_link_sentry`, `download_sentry_framework` (which ran `script/macos/update_sentry_cocoa`), `compile_sentry_objc_lib` and the Swift-runtime link flags that only the static Sentry framework needed.
- The `sentry` and `sentry-log` workspace dependencies, and the `sentry`, `sentry-log`, `minidumper` and `crash-handler` dependencies of `app`, `warp_logging`, `warp_errors`, `warp_terminal` and `ai`.
- Cargo features: `crash_reporting` (in `app`, `ai`, `warp_errors`, `warp_logging`, `warp_terminal`, `warp_tui`), `cocoa_sentry`, `heap_usage_tracking` and `log_expensive_frames_in_sentry`, together with every `cfg` block that used them.
- The `osx_frameworks` (Sentry.framework) bundle metadata for the stable, preview and dev bins.
- The hidden `minidump-server` worker subcommand in `warp_cli`.
- `warp_logging`'s `SentryLogger` wrapper and log filter. The terminal-server log receiver no longer runs inside the main Sentry hub.
- `PtySpawnHooks::{before_spawn, after_spawn}` in `warp_terminal`, which stopped and restarted Cocoa Sentry around shell spawns.
- The Sentry heap-profile upload on excessive memory use (`profiling::dump_jemalloc_heap_profile` and its jemalloc/pprof helpers), the dogfood process-sample upload in `workspace/view.rs` and the SQLite error capture in `persistence/sqlite.rs`. (The Windows auto-update log upload went away with the autoupdater.)
- `script/prepare_bundled_pprof` and the pprof `Contents/Helpers` bundling in `script/macos/{bundle,run}`, which only served the heap-profile upload.
- The crash-reporting privacy setting: `IsCrashReportingEnabled` (`privacy.crash_reporting_enabled`), `CRASH_REPORTING_ENABLED_DEFAULTS_KEY`, `PrivacySettings::is_crash_reporting_enabled` and its setter, sync to Warp Drive and the server, `PrivacySettingsChangedEvent::UpdateIsCrashReportingEnabled`, the "Send crash reports" widget and command-palette toggle on the Privacy page, the toggle in the login/onboarding privacy overlay, and `AuthClient::set_is_crash_reporting_enabled` / `SyncedUserSettings::is_crash_reporting_enabled` in `warp_server_client`.
- `crash_reporting_enabled` in the remote-server protocol (`Initialize` field 4 and `UpdatePreferences` field 1 are now `reserved`), `InitializeParams`, `RemoteServerAuthContext` and `RemoteServerClient::update_preferences`, along with the daemon's Sentry setup.
- `WorkspaceAction::Crash` ("Crash the app") and crash recovery's Sentry-only state (`is_crash_recovery_process_running`, `Event::CrashRecoveryProcessTornDown`).

**Modified:**
- `warp_errors` — `report_error!` and `report_if_error!` are kept and now only write to the local log: actionable errors at Error level and non-actionable ones at Warn level, with `extra:` fields appended to the log line. `ErrorExt::report_error`, `AnyhowErrorExt::report_error`, `with_error_context` and `should_ignore_log_for_sentry` are gone.
- `app/src/lib.rs` — no Sentry hub/init/teardown and no buffering of pre-init errors. They are reported with `report_error!` where they happen. `initialize_app` lost its `pre_sentry_errors` parameter.
- `server/telemetry/events.rs` — dropped `AppStartupInfo::is_crash_reporting_enabled`, whose value came from Sentry init (same compile-fix pattern as the autoupdater's `from_relaunch`).
- `crash_recovery.rs` — local crash recovery is unchanged apart from the Sentry hooks. It never uploaded anything.
- `root_view.rs` — windows no longer register a GPU-selection callback, which existed only to tag Sentry events.
- `workspace/mod.rs` — the "Write heap profile to disk" binding is registered only with `dhat_heap_profiling`, and the debug panic action is labelled "Trigger a panic".
- `app/src/remote_server/mod.rs` — codebase index limit updates still go to connected daemons, without the crash preference.
- `script/linux/bundle`, `script/macos/bundle`, `script/linux/test_bundle_warpctrl` — the dev/preview/stable channel bundles enable `jemalloc_pprof` without `heap_usage_tracking`.
- `.gitignore`, `.dockerignore` — dropped the `app/Carthage` and `app/frameworks/**` entries, which were only the Sentry framework download location.
- `.agents/skills/logging-and-error-reporting/SKILL.md` — now says errors are logged locally only and explains `report_error!` in terms of log level and actionability instead of Sentry events, breadcrumbs and grouping.
- Comments that described Sentry uploads, grouping or issue links were rewritten or removed (code review diff errors, SQLite, watcher, editor tests, `warpui` window/scene/view handle, terminal, drive export, teams page, voice input, the `.cargo/config.toml` and release-profile comments, and others).

**User-visible impact:** Warp no longer sends crash reports, error events or diagnostics anywhere. The "Send crash reports" switch is gone from Settings > Privacy, from the login privacy overlay and from the command palette. A saved `privacy.crash_reporting_enabled` value in `settings.toml` is ignored. Crash recovery on Linux and Windows, local logs, the log bundle and the "Write heap profile to disk" command (with `dhat_heap_profiling`) still work.

**Notes:**
- `heap_usage_tracking` was removed rather than kept as a local feature: it enabled `crash_reporting`, and its purpose was the automatic Sentry heap-profile upload above 10 GB. Local heap profiling is still available through `dhat_heap_profiling`, and through `jemalloc_pprof` / `jemalloc_auto_heap_profiling`.
- Left for their owning tasks: `CrashReportingConfig`, `ChannelState::sentry_url` / `is_crash_reporting_available` and the `crash_reporting_config` fields in the bins (CFG-1); the `CocoaSentry`, `CrashReporting` and `LogExpensiveFramesInSentry` feature-flag variants (FLAGS-1); the unused `AutoupdateMinidumpCleanupFailed` event variant (TEL-4); `isCrashReportingEnabled` / `crashReportingEnabled` in `crates/graphql` and the schema (SRV-1); the `Sentry` MCP product icon and the Sentry mention in an ambient-agent tip (AI plan).
- `script/wasm/install_build_deps` still downloads Sentry's `wasm-split` tool from GitHub to strip debug info from the wasm bundle. It is a build-time tool that sends no data, and is left to WASM-1.

## Diff hunk types moved to the editor crate
**Why:** The code editor, diff viewer, code review and markdown viewer apply line-based diff hunks through `DiffDelta` and `DiffType`, which lived in the AI crate's diff-validation module. Moving them out lets those kept features stop depending on `crates/ai` before it is deleted.

**Removed:**
- `DiffDelta` and `DiffType` (with its `creation`/`deletion`/`update` constructors) from `crates/ai/src/diff_validation/mod.rs`.

**Modified:**
- `crates/editor/src/diff.rs` (new, `warp_editor::diff`) — the same two types, unchanged.
- `crates/ai` — depends on `warp_editor` and imports the types from there for fuzzy diff matching; the rest of `diff_validation` (`ParsedDiff`, `AIRequestedCodeDiff`, fuzzy matching) stays in the AI crate.
- Import updates: `app/src/code/{diff_viewer, inline_diff, local_code_editor, local_code_editor_wasm, wasm}.rs`, `app/src/code/editor/{model, view}.rs`, `app/src/code_review/{code_review_view, hidden_lines}.rs`, `app/src/notebooks/editor/model.rs`, the AI callers under `app/src/ai/{blocklist, document}/`, and `crates/warp_tui`.

**User-visible impact:** None. This is a move with no behavior change.

**Notes:** The `warp_editor` dependency of `crates/ai` goes away when the AI crate is deleted.

## Secret redaction and repository metadata imported directly
**Why:** Secret redaction is kept, but several non-AI modules reached the `secret_redaction` crate through re-exports in the AI modules. The AI crate's `index` module also re-exported `repo_metadata` types. Importing from the owning crates removes these paths through AI code before it is deleted.

**Removed:**
- The `redact_secrets` re-export from `app/src/ai/agent/redaction.rs`, which now only redacts agent request inputs.
- The `find_secrets_in_text` re-export from `app/src/ai/blocklist/block/secret_redaction.rs`.
- The `repo_metadata` re-exports in `crates/ai/src/index/mod.rs`: `BuildTreeError`, `DirectoryEntry`, `Entry`, `FileId`, `FileMetadata`, `is_git_internal_path`, `should_watch_directory_in_git_path` and `matches_gitignores`.

**Modified:**
- `app/src/terminal/{view, model/block}.rs`, `app/src/integration_testing/secret_redaction/assertion.rs`, `app/src/env_vars/view/env_var_collection.rs`, `app/src/notebooks/notebook.rs`, `app/src/workflows/workflow_view.rs` and `app/src/settings_view/mcp_servers/edit_page.rs` — import `redact_secrets`, `find_secrets_in_text` and `find_secrets_in_text_with_levels` from `secret_redaction`.
- The AI callers of `redact_secrets` (`app/src/ai/agent_sdk/driver/terminal.rs`, `app/src/ai/blocklist/{block, action_model/execute/grep}.rs`) and the AI block redaction tests import from `secret_redaction` too.
- `crates/ai/src/index/{file_outline, full_source_code_embedding}/**` import the `repo_metadata` types directly.

**User-visible impact:** None. The same functions are called.

**Notes:** `app/src/server/telemetry/secret_redaction.rs` has its own regex set and never went through the AI modules, so it is unchanged. Telemetry removal deletes it.

## Code-symbol outline moved out of the AI modules
**Why:** The `@` context menu in the terminal input and the CLI-agent rich input composer can search code symbols. The repository outline behind that search lived in `crates/ai` (`index::file_outline`) and `app/src/ai/outline/`. The composer keeps `@` file and code-symbol mentions, so the outline moves out of the AI modules before they are deleted.

**Removed:**
- `crates/ai/src/index/file_outline/` and the `Outline`, `Symbol` and `build_outline` re-exports from `ai::index`.
- The shared file-parsing thread pool (`THREADPOOL`) from `crates/ai/src/index/mod.rs`.
- `app/src/ai/outline/` (`pub mod outline` in `app/src/ai/mod.rs`).
- The `syntax_tree` and `streaming-iterator` dependencies of `crates/ai`, which only the outline used.

**Modified:**
- `crates/code_outline` (new) — the tree-sitter outline builder (`build_outline`, `Outline`, `FileOutline`, `Symbol`, `FileSymbols`) and its tests, unchanged apart from imports. It also owns the file-parsing Rayon pool, which keeps its `warp-code-indexing-N` thread names. The crate has a `jemalloc` feature that turns off the glibc `malloc_trim` call, as `ai/jemalloc` did. The app's `jemalloc` feature enables it.
- `app/src/code/outline/` — `RepoOutlines`, `RepoOutlinesEvent` and `OutlineStatus` (native and wasm versions), moved from `app/src/ai/outline/` without changes.
- `crates/ai` — depends on `code_outline`; the codebase-index merkle tree uses `code_outline::THREADPOOL`, so indexing and outlining still share one pool.
- Import updates: `app/src/lib.rs`, `app/src/search/ai_context_menu/code/{mod, data_source, data_source_tests}.rs`, the test setup helpers `app/src/test_util/terminal.rs`, `app/src/pane_group/mod_tests.rs`, `app/src/workspace/view_tests.rs`, `app/src/terminal/input_tests.rs`, and the AI callers `app/src/ai/{blocklist/context_model, get_relevant_files/controller}.rs`.

**User-visible impact:** None. Symbol search in the `@` menu behaves as before.

**Notes:**
- `RepoOutlines` still reads the AI gates (`AISettingsChangedEvent::IsAnyAIEnabled`, `UserWorkspaces::is_codebase_context_enabled`, `CodeSettingsChangedEvent::CodebaseContextEnabled`) and `crate::ai::persisted_workspace::all_working_directories`. The tasks that remove those settings and move `persisted_workspace` (AI-10) update these call sites, leaving `outline_codebase_symbols_for_at_context_menu` as the only switch.
- `code_outline::THREADPOOL` is public only because the AI merkle tree shares it. Once AI-10 deletes `full_source_code_embedding`, it can become private and `crates/ai` can drop the dependency.
- `Outline::to_file_symbols` and `FileSymbols` only serve the AI `get_relevant_files` controller. Remove them when that controller is deleted.

## CLI output format moved out of the agent commands
**Why:** `warpctrl` (`warp_cli::local_control`), which is kept, takes a `--output-format` flag whose type, `OutputFormat`, was defined in `warp_cli::agent` alongside the Oz agent subcommands. Moving it lets the agent command modules be deleted without touching `warpctrl`.

**Removed:**
- `OutputFormat` from `crates/warp_cli/src/agent.rs`.

**Modified:**
- `crates/warp_cli/src/output_format.rs` (new, `warp_cli::output_format`) — the same enum and `Display` impl. The type doc now says "command results" instead of "agent results"; the doc does not appear in `--help`.
- `crates/warp_cli/src/{lib, lib_tests}.rs` and `crates/warp_cli/src/local_control/{mod, commands, output}.rs` — import from the new module.
- `app/src/ai/agent_sdk/**` — import from the new module.

**User-visible impact:** None. The flag values (`json`, `ndjson`, `pretty`, `text`) and the default (`pretty`) are unchanged.

**Notes:** None.
## Offline server configuration
**Why:** `warp-oss` was hard-wired to Warp's production endpoints (`app.warp.dev`, `rtc.app.warp.dev`, `sessions.app.warp.dev`, `oz.warp.dev`) and to the Firebase API key of Warp's identity project. Even logged out it called `app.warp.dev` at startup (GraphQL `FreeAvailableModels`). This change is an early safety net: the client code that talks to Warp still exists until later removals, but it no longer has a server to reach.

**Removed:**
- `WarpServerConfig::production()` and `OzConfig::production()` (`crates/warp_core/src/channel/config.rs`), including the hard-coded Firebase Web API key.

**Modified:**
- `crates/warp_core/src/channel/config.rs` — new `WarpServerConfig::offline()` and `OzConfig::offline()`. The server root, RTC and Oz URLs use the host `offline.invalid`; RFC 6761 reserves `.invalid` as never resolvable, so requests fail at the DNS lookup without opening a socket. There is no session-sharing server and the Firebase API key is empty.
- `crates/warp_core/src/channel/state.rs` (`ChannelState::init()`, the default config before a binary installs its own, which unit tests also use) and `app/src/bin/oss.rs` use the offline config.
- `crates/warp_tui/src/bin/oss.rs` — compile fix only: uses the offline config. AI-02 deletes the crate.
- `crates/warp_server_client/src/auth/session.rs` — Firebase token exchange fails without sending anything when the API key is empty. The exchange endpoints are hard-coded to `securetoken.googleapis.com` and `identitytoolkit.googleapis.com`, so without this check a user with Warp credentials stored by an earlier build would still send their refresh token to Google.
- `crates/warp_core/src/channel/state_tests.rs` — sample URLs use `example.com`.

**User-visible impact:** Nothing that needs Warp's servers can succeed any more: sign-in and token refresh, Warp Drive sync, session sharing, server-backed AI features and the logged-out free-model list all fail immediately. Links built from the server or Oz root URL (for example the privacy page's data-management link) now open `http://offline.invalid/…` until the tasks that remove them land.

**Notes:**
- `offline()` is a temporary shim: CFG-1 deletes `WarpServerConfig` and `OzConfig` along with it. The empty-key check goes with `warp_server_client` in SRV-1.
- The server-URL overrides (`--server-root-url`, `--ws-server-url`, `--session-sharing-server-url` and their `WARP_*` env vars) are already ignored on `Channel::Oss` (`Channel::allows_server_url_overrides`); only `Integration` and the internal channel binaries honor them. CFG-1 removes them.
- `app/src/bin/integration.rs` is unchanged. It already sends server traffic to the black-hole address `192.0.2.0:9`.
- Runtime check: a 90-second launch with an isolated HOME made no socket connections to remote hosts. The app's only DNS lookups were failed queries for `offline.invalid`, replacing the baseline's `app.warp.dev`. The Homebrew lookups in that run (`formulae.brew.sh`, `analytics.brew.sh`) came from the install-method probe, which is removed in its own section.
- Hard-coded Warp hosts outside the channel config that are left for later tasks: `*.warp.dev` host matching with no traffic of its own in `crates/http_client`, `crates/warp_errors`, `crates/websocket` and `ChannelState::uses_staging_server` (SRV-1, CFG-1); the `app-installation-detection` CORS allowlist; and browser links (SWP-10).
- Runtime check: a 90-second launch with an isolated HOME made no socket connections to remote hosts. The app's only DNS lookups were failed queries for `offline.invalid`, replacing the baseline's `app.warp.dev`. Homebrew still contacts `formulae.brew.sh` and `analytics.brew.sh` because install detection runs `brew list --cask warp`; that is removed with app-installation detection.
- Hard-coded Warp hosts outside the channel config that are left for later tasks: the `releases.warp.dev` pacman repo in `app/src/autoupdate/linux.rs` (UPD-1); `*.warp.dev` host matching with no traffic of its own in `crates/http_client`, `crates/warp_errors`, `crates/websocket` and `ChannelState::uses_staging_server` (SRV-1, CFG-1); the `app-installation-detection` CORS allowlist; and browser links (SWP-10).

## Channel binaries and private config loader
**Why:** The `warp` (local), `stable`, `dev` and `preview` binaries loaded their `ChannelConfig` from Warp's private `warp-channel-config` generator. That config carries Warp's server URLs and the telemetry, crash-reporting and autoupdate settings for each channel. The generator is not available outside Warp, and those builds contradict the offline goal. The only binaries left are `warp-oss` (the default) and `integration` for tests.

**Removed:**
- `app/src/bin/{local,stable,dev,preview}.rs` and their `[[bin]]` targets (`warp`, `stable`, `dev`, `preview`).
- `[package.metadata.bundle.bin.{stable,preview,dev,warp}]` in `app/Cargo.toml`: bundle identifiers and names for those binaries.
- `app/channels/{stable,local,dev,preview}`: per-channel icons and Linux `.desktop` files.
- `app/build.rs::generate_channel_config_if_needed`: for release bundles it ran `warp-channel-config` and wrote each channel's JSON to `OUT_DIR` for embedding.
- The `warp_channel_config` dependency of the `warp` crate.

**Modified:**
- `app/build.rs`: when `CARGO_BIN_NAME` is unset, the Windows resource embedding now falls back to the `oss` icon instead of `local`.
- `app/examples/generate_default_settings.rs`: dropped `--channel dev|preview|stable`. It now always generates defaults for a release `warp-oss` build (settings gated on `RELEASE_FLAGS`), which is what `--channel stable` did.
- `AGENTS.md`: the bundle command names `warp-oss`.

**User-visible impact:** None for `warp-oss`, which was already what `cargo run` built. The other channel binaries and their bundles can no longer be built.

**Notes:**
- `crates/warp_channel_config` (workspace member and `[workspace.dependencies]` entry) stays for now because `crates/warp_tui` still uses it in its `stable`/`dev`/`preview`/`local` binaries and `build.rs`. Delete it once AI-02 removes `warp_tui`; CFG-1 also lists it.
- The `preview_channel` Cargo feature stays because it still gates a default in `app/src/settings/input.rs`. FLAGS-1 removes it.
- Scripts that still name the deleted binaries or channel directories (W0-B / SWP-05): the channel branches in `script/{linux,macos,wasm}/bundle` and `script/windows/bundle.ps1` (`WARP_BIN` = `warp`/`dev`/`preview`/`stable`, `preview_channel`); `app/channels/$CHANNEL` paths in `script/compile_icon`, `script/linux/bundle_install` and `script/windows/windows-installer.iss` (these still work for `oss`); and `cargo run --bin warp` in `script/test_warpctrl_early_dispatch`. `resources/channel-gated-skills/dogfood/test-warp-ui/SKILL.md` also runs `cargo run --bin warp`; the AI plan deletes the channel-gated skills.

## Computer use and agent screen recording
**Why:** Computer use let Warp's agent drive the desktop (mouse, keyboard, screenshots) and record the screen, with screenshots and recordings uploaded to Warp-managed storage and shown on Oz run pages. It is part of the built-in agent, which the offline fork removes, and the stored-screenshot and recording paths called Warp servers.

**Removed:**
- `crates/computer_use` — the platform input, screenshot and ffmpeg recording backends (macOS, X11/Wayland, Windows), the overlay and the `use_computer` binary. Its workspace entry and the now-unused workspace dependencies `ashpd` and `objc2-core-graphics` are gone.
- `crates/ai` — the `UseComputer`, `RequestComputerUse`, `StartRecording` and `StopRecording` action types and their results (`UseComputerResult`, `ScreenshotSource`, `RequestComputerUseResult`, `StartRecordingResult`, `StopRecordingResult`, `ScreenDimensions`), their proto conversions and conversion errors, `computer_use_enabled` on the run-agents and start-agent execution modes, and the orphaned `action/convert_tests.rs`.
- `app/src/ai/blocklist/action_model/{recording_controller, recording_finalize, recording_telemetry}.rs` (with tests) — the `RecordingController` singleton, recording finalization and upload on run end or cancel, and recording telemetry.
- `app/src/ai/blocklist/action_model/execute/{use_computer, request_computer_use, start_recording, stop_recording}.rs` — the four executors.
- `app/src/ai/stored_screenshots.rs` and `AIClient::download_stored_screenshot` — on-demand download of screenshots offloaded to Warp storage.
- AI block UI: computer-use approval and action rows, "View screenshot" lightbox, recording cards, "Open recording" (Oz run page) and recording-span footers; `RecordingSpanInfo` and the recording-span cache on the action model.
- Execution profiles: the computer-use permission and computer-use model (`ComputerUsePermission`, `AIExecutionProfile::{computer_use, computer_use_model}`, the file-format fields, the editor dropdowns and the settings-page summary lines), and the computer-use model catalog (`ModelsByFeature::computer_use`, `get_*_computer_use_*`).
- Settings: `CloudAgentComputerUseEnabled` (`agents.warp_agent.other.cloud_agent_computer_use_enabled`) and its "Computer use in Cloud Agents" widget on the Warp Agent page; `is_computer_use_permissions_editable`.
- Workspace policy: the team/workspace computer-use autonomy setting (`computer_use_setting`, `TeamAiAutonomySettings::computer_use`) and its GraphQL fields and types (`computerUseSetting`, `ComputerUseAutonomyValue`, `ComputerUseSettingInfo`, `computerUseAgent`, and the integration `computerUseEnabled` fields in `schema.graphql`).
- Oz CLI and cloud agents: the `--computer-use` / `--no-computer-use` flags, `LaunchMode::CommandLine::computer_use_override`, `computer_use_enabled` on `AgentConfigSnapshot`, the agent config file and remote child launches, and computer-use resolution for cloud-mode and handoff spawns.
- Request plumbing: the computer-use tools, `computer_use_agent` model, `supports_background_computer_use` and `supports_stored_screenshots` request settings, the computer-use subagent type and background-session teardown, and `ComputerUseUnavailable` reporting.

**Modified:**
- `app/src/lib.rs` — no longer registers `RecordingController`.
- `app/src/ai/blocklist/action_model/execute/shell_command.rs` — shell commands no longer open or commit recording action groups.
- Proto match sites in `convert_conversation.rs`, `conversation_yaml.rs` and `task/helper.rs` treat computer-use and recording tool calls and results as unsupported tools (wildcard arms).
- `app/src/ai/agent/api/impl.rs` — the request `Settings` literal ends in `..Default::default()` so the dropped flags stay unset.
- `crates/warp_tui` — compile fixes only (labels, approval text, orchestration fields); AI-02 deletes the crate.
- `AGENTS.md` — the GUI verification note no longer points at `computer_use`.

**User-visible impact:** None for terminal users; computer use was only reachable through the built-in agent. Stored `computer_use` / `computer_use_model` profile fields and the cloud-agent setting are ignored on load. Agent config files for the Oz CLI now reject a `computer_use_enabled` key.

**Notes:**
- Kept: `warpui_core::integration::{video_recorder, capture_recorder}` and `crates/integration/src/test/video_recording.rs`, which record integration-test runs and never used `RecordingController`.
- Left for AI-32: the `AgentModeComputerUse`, `LocalComputerUse`, `BackgroundComputerUse` and `StoredScreenshots` flags and the empty Cargo features `agent_mode_computer_use`, `background_computer_use`, `local_computer_use` and `stored_screenshots` (with their `app/src/features.rs` registration).
- Left for TEL-4: the `ComputerUseApproved`, `ComputerUseCancelled` and `ComputerUseUnavailable` variants in `app/src/server/telemetry/events.rs` (no callers remain).
- Left for AI-11: bundled and channel-gated skills that mention computer use (`resources/channel-gated-skills/dogfood/{test-warp-ui, verify-ui-change-in-cloud}`, `resources/bundled/skills/oz-platform`).
- Left for AI-16 / AI-30: the `use_computer_stats` usage counter in `persistence::model` and `get_conversation_usage.rs`.
- Screenshot conversation artifacts (`ScreenshotArtifact`, `ai/artifacts`) belong to the cloud-agent artifacts feature and are left for its removal task.
- `warp_multi_agent_api` still defines the computer-use messages; the proto dependency goes with the agent core (AI-29/AI-30).

## Current input UI made permanent
**Why:** Today's release input UX is the only UX this fork keeps. Treating the newer-UI flags as permanently on removes the legacy code paths so that the later AI removal only has one input implementation to strip.

**Modified:**
- Flags treated as permanently on in all code outside `app/src/ai/**`: `AgentView`, `InlineHistoryMenu`, `InlineMenuHeaders`, `InlineRepoMenu`, `AtMenuOutsideOfAIMode`, `AIContextMenuEnabled`, `CLIAgentRichInput`, `AgentToolbarEditor`, `ConfigurableToolbar`, `WarpifyFooter` (`InlineSlashCommands` is a Cargo feature only). Every flag check was removed and the flag-on branch kept, in `terminal/{view.rs, input.rs, block_list_element.rs, block_list_viewport.rs, prompt_render_helper.rs, profile_model_selector.rs}`, `terminal/input/*`, `terminal/view/*`, `terminal/model/{block.rs, blocks.rs}`, `terminal/shared_session/*`, `terminal/local_tty/terminal_view_adaptor.rs`, `context_chips/*`, `editor/view/mod.rs`, `settings/*`, `settings_view/*`, `workspace/*`, `pane_group/mod.rs`, `code_review/code_review_view.rs`, `search/slash_command_menu/static_commands/commands.rs` and `server/telemetry/events.rs`.

**Removed:**
- `terminal/input/universal.rs`: the legacy Universal Developer Input renderer (only used with `AgentView` off).
- `terminal/view/block_banner/`: the legacy in-block Warpify banner, together with the block-banner geometry in `terminal/model/block.rs` (`BlockSection::BlockBanner`), its rendering in `block_list_element.rs`, and the `ShowSubshellBanner` / `DismissWarpifyBanner` actions and `RememberForWarpification`. The Warpify footer replaced it.
- Legacy input behavior: the `* ` AI input prefix, the legacy "New agent conversation" keybinding (`input:start_new_agent_conversation`), the classic-input AI mode and follow-up icons, the editor's inline `@` and image buttons, the legacy natural-language-detection settings copy, the AI context stripes on blocks, the clearing of block selections when typing, and the agent-mode setup banner insertion.
- The `FeatureFlag.AgentView` keymap context flag (`AGENT_VIEW_ENABLED`). The bindings that used it now depend only on the agent view state.
- Tests that forced one of these flags off: 13 LRC prompt-queue tests and the `*`/`!` prefix tests in `terminal/input_tests.rs`, two tests in `terminal/view_tests.rs`, one slash-command availability test, and the `test_cancelled_run_agents_card_renders_cancelled_state` integration test.
- Unit tests that only covered the legacy UI (they relied on the flags defaulting to off in tests): the legacy up-arrow history menu tests (`test_history_up*`, `test_vim_escape_with_history_menu`), `test_clear_selection_after_insert`, `test_agent_mode_set_while_typing_slash_command` and `test_image_attachment_preserves_lock_state`. Tests that forced a flag on were cleaned of the now-redundant overrides.

**User-visible impact:** None for release users; this is the input UI they already have. The legacy UI that was only reachable with a flag turned off is gone.

**Notes:**
- The `FeatureFlag` variants and Cargo features stay until FLAGS-1 (AI-32).
- Tests adjusted to the kept UI: `test_insert` (typing keeps selections), `test_insert_into_input`, `test_reinput_blocks`, `test_viewport_iter_most_recent_at_bottom` (empty blocks are skipped), `test_scroll_position_doesnt_change_when_block_finished` (zero state block turned off), `test_auto_detection_toggle`, `test_input_config_transitions` and `test_remove_ignored_suggestion_on_ai_query_execution`. The subshell integration test now checks the Warpify footer instead of the removed banner.
- `app/src/ai/**` was not touched, so AI code there still checks these flags. Unit tests leave flags off by default, so four tests still set an override because they exercise that AI code: `status_blocked_auto_closes_rich_input`, `status_in_progress_auto_opens_rich_input_after_blocked`, `unregister_cli_agent_session_restores_unlocked_input_config` (CLI agent toolbar in `ai/blocklist/agent_view/agent_input_footer`, `AgentView` input policy) and `test_shell_lock_respected_when_slash_command_typed` (`ai/blocklist/input_model.rs`). Remove them with those checks.
- Four dead-code warnings remain in AI files, for code that only the removed legacy paths used; the AI tasks delete it: `ai/blocklist/history_model.rs::last_conversation_id`, `ai/blocklist/view_util.rs::render_ai_follow_up_icon` (and its re-export in `ai/blocklist/mod.rs`), and `ai/agent/conversation.rs::{create,clear}_optimistic_cli_subagent_task_for_test`.
- AI-only behavior on the kept flag-on paths (agent view entry points, the model selector, the voice button plumbing and the agent-mode setup banner removal hook) is left for the AI tasks to strip.

## Telemetry collection (RudderStack)
**Why:** The app queued usage events in memory and sent them in batches to RudderStack, Warp's analytics pipeline. It also wrote unsent events to a JSON file at quit and uploaded them on the next launch, could append every event to a local telemetry log file, and recorded "Active App Usage" and daily app-focus events on timers. An offline enterprise build must not collect, persist or send usage data.

**Removed:**
- `app/src/server/telemetry/collector.rs`: the `TelemetryCollector` singleton. It flushed to RudderStack every 30s, sent active-usage events every 60s, uploaded the events persisted at the last quit, and flushed or persisted again at shutdown.
- `app/src/server/telemetry/rudder_message.rs` and `LICENSE-RUDDER-SDK-RUST.txt`: the RudderStack message types (adapted from rudder-sdk-rust) and their license. The license entry is also gone from `script/prepare_bundled_resources` and `script/windows/prepare_bundled_resources.ps1`.
- `app/src/server/telemetry/context.rs`: the OS and user-agent context attached to RudderStack messages.
- `app/src/server/telemetry/context_provider.rs`: `AppTelemetryContextProvider`, which supplied the user ID and anonymous ID for events. Its singleton registration is gone from `lib.rs` and from about 30 test setups.
- In `app/src/server/telemetry/mod.rs`: `TelemetryApi` (the HTTPS client, the batch sender, persistence to `rudder_telemetry_events.json`, and telemetry-to-file via `persist_events_to_telemetry_log_file`) and `clear_event_queue`.
- `app/src/server/telemetry_ext.rs` and its tests: the conversion of queued events into RudderStack batch messages.
- `ServerApi::{send_telemetry_event, flush_telemetry_events, flush_persisted_events_to_rudder, persist_telemetry_events}` and the `telemetry_api` field.
- `ServerApi::send_agent_tip_shown_analytics_event` (a POST to `/analytics/agent-tip-shown`) and its caller in `ai/blocklist/block/status_bar.rs`.
- The `SessionAbandonedBeforeBootstrap` send in `TerminalView::drop`, which called `ServerApi::send_telemetry_event` directly instead of going through the macros. The `privacy_settings_snapshot` and `background_executor` fields existed only for it and are gone, as is the never-assigned `bootstrap_start` field.
- `AuthManager`'s post-login identify and login events and the forced flush that followed them. The `notify_login` call stays.
- `crates/warpui_core/src/app_focus_telemetry.rs` and its tests, `AppContext::{record_app_focus, record_app_blur, try_record_daily_app_focus_duration}`, and the `on_become_active`, blur and terminate hooks in `lib.rs` that called them.
- In the `warpui_core` event store: the `IdentifyUser` and `AppActive` payloads and `record_identify_user_event`/`record_app_active_event`.
- `AppExecutionMode::send_telemetry_at_shutdown` (`warp_core`) and the telemetry-file rotation in `warp_logging::rotate_log_files`.
- The telemetry privacy toggle:
  - `IsTelemetryEnabled` (`privacy.telemetry_enabled`, storage key `TelemetryEnabled`) in `WarpDrivePrivacySettings`, and `TELEMETRY_ENABLED_DEFAULTS_KEY`.
  - `PrivacySettings::{is_telemetry_enabled, set_is_telemetry_enabled}` and `PrivacySettingsChangedEvent::UpdateIsTelemetryEnabled`.
  - The org-forced telemetry state: `PrivacySettings::{is_telemetry_force_enabled, set_is_telemetry_force_enabled}` and `UserWorkspaces::is_telemetry_force_enabled`.
  - The telemetry fields of `PrivacySettingsSnapshot`, `should_disable_telemetry`, and the test-only `mock`.
  - `AuthClient::set_is_telemetry_enabled` and `SyncedUserSettings::is_telemetry_enabled`.
- Telemetry UI:
  - On the Privacy settings page: the "Help improve Warp" widget (`AppAnalyticsWidget`) and `PrivacyPageAction::ToggleTelemetry`.
  - The "app analytics" Command Palette toggle and `flags::TELEMETRY_FLAG`.
  - The telemetry switch in the login and auth privacy overlay (`auth/login_slide.rs`, `auth/auth_view_body.rs`, `auth/auth_view_shared_helpers.rs`).
  - The trigger in `workspace/view.rs` that showed the telemetry-policy banner to existing users.
- Tests that asserted on emitted or persisted events: `notebooks::test_edit_telemetry`, the event-queue assertions in `warp_tui`'s `nld_slash_command_toggles_and_reports_its_effects`, `server/telemetry/mod_tests.rs`, the `telemetry_ext` tests, the app-focus tests, and the app-active event-store tests. The event-store session tests now use named events.

**Modified:**
- `send_telemetry_from_ctx!` and `send_telemetry_from_app_ctx!` (`warp_core`), plus `send_telemetry_sync_from_ctx!`, `send_telemetry_sync_from_app_ctx!` and `send_telemetry_on_executor!` (`server/telemetry/macros.rs`), are now no-ops. They evaluate and discard their arguments, so the existing call sites still type-check, with no dependency on `ServerApiProvider`, `PrivacySettings` or the `TelemetryContextModel` singleton. Trait imports that only the old macro bodies used were removed.
- `app/src/server/telemetry/events.rs`: added a module-level `#![allow(dead_code)]` so events whose last call site is deleted don't warn, and dropped a doc comment that mentioned RudderStack.
- `ai::blocklist::telemetry_banner::should_collect_ai_ugc_telemetry`: dropped the `is_telemetry_enabled` parameter, and with it the `GlobalAIAnalyticsCollection` branch that required telemetry to be on. Its callers were updated.
- `PrivacySettings::get_snapshot` no longer takes a context. The server settings sync no longer sends `telemetry_enabled`, and the Warp Drive preference sync covers only cloud conversation storage.
- Session sharing (`terminal/shared_session/{sharer,viewer}/network.rs`) sends `telemetry_context: None` instead of OS info.
- `server/telemetry/secret_redaction.rs`: dropped `redact_secrets_in_value`, which only served RudderStack payloads. `redact_secrets_in_string` stays because the agent SDK harness (`ai/agent_sdk/driver/{harness/mod.rs, termination/unix.rs}`) still calls it; the module goes when the AI tasks remove those callers or TEL-4 deletes `app/src/server/`.
- `system/info.rs` and `remote_server/unix/mod.rs`: removed comments that described the RudderStack pipeline.

**User-visible impact:** No usage data is collected, written to disk or sent. The Privacy page no longer shows "Help improve Warp", the login privacy overlay has no telemetry switch, and the Command Palette no longer offers to enable or disable app analytics. An existing `privacy.telemetry_enabled` value in the settings file is ignored. A `rudder_telemetry_events.json` left in the state directory by an earlier version is no longer read or deleted.

**Notes:**
- The no-op macros are temporary shims. Also kept until then: the `TelemetryEvent` trait, `TelemetryContextProvider` and `MockTelemetryContextProvider` (still registered by some tests), the `warpui_core` event store and its `record_telemetry_*` macros (which nothing calls now), `events.rs`, and `PrintTelemetryEvents`. TEL-2 and TEL-3 delete the call sites; TEL-4 deletes the framework and `app/src/server/`.
- `TelemetryConfig`, `RudderStackConfig`, `RudderStackDestination` and `ChannelState::{rudderstack_non_ugc_destination, rudderstack_ugc_destination, telemetry_file_name, is_telemetry_available}` are no longer used. CFG-1 removes them.
- These have no remaining code; FLAGS-1 removes them:
  - Feature flags: `SendTelemetryToFile`, `WithSandboxTelemetry`, `RecordAppActiveEvents` and `GlobalAIAnalyticsCollection`.
  - Cargo features: `send_telemetry_to_file`, `record_app_active_events` and `global_ai_analytics_collection`.
- Left for the AI tasks (not sinks):
  - `ai/blocklist/telemetry_banner.rs` (`TelemetryBanner` and `should_collect_ai_ugc_telemetry`), `TerminalView::insert_telemetry_banner` (still called during new-user onboarding, behind the off-by-default `GlobalAIAnalyticsBanner` flag) and `GeneralSettings::telemetry_banner_dismissed`.
  - The analytics opt-out copy in `crates/onboarding/src/slides/theme_picker_slide.rs`.
  - The AI-owned telemetry enums and the Oz OTLP trace export in `app/src/tracing`.
- Minimal compile fixes in AI-owned files: `ai/blocklist/{block.rs, input_model.rs, action_model/execute/grep.rs, action_model/execute/run_agents.rs, block/status_bar.rs, telemetry_banner.rs}`, `ai/agent_sdk/driver.rs`, `coding_entrypoints/create_project_view.rs`, `tui/mod.rs`, and the test setups in `ai/blocklist/{history_model_tests.rs, prompt/prompt_alert_tests.rs}`.

## Block sharing (web permalinks)
**Why:** Sharing a block uploaded its command, output and prompt to Warp's server (GraphQL `ShareBlock`) and returned a `warp.dev` permalink or HTML embed. The Shared blocks settings page listed and deleted those uploads (`GetBlocksForUser`, `UnshareBlock`), and the modal could ask Warp's AI endpoint (`/ai/generate_block_title`) for a title. An offline build has no server to host blocks.

**Removed:**
- `app/src/terminal/share_block_modal.rs` (and its tests) — the "Share block" modal: permalink and embed creation, display options, secret redaction toggle, AI title generation and the "Manage permalinks" link.
- `app/src/settings_view/show_blocks_view.rs` and `SettingsSection::SharedBlocks` — the Shared blocks settings page (list, open and unshare uploaded blocks), its nav item, page handle and slug (`"Shared blocks"`).
- `app/src/server/server_api/block.rs` (`BlockClient`, `ServerApiProvider::get_block_client`) and `app/src/server/block.rs` (the server-side block representation, `DisplaySetting` and the embed size constants).
- `app/src/ai/generate_block_title/` — request/response types for the block title endpoint, which only the modal used.
- The block context-menu item "Share block..." / "Share...", `ContextMenuAction::OpenShareBlockModal`, `TerminalAction::OpenShareModal`, the `terminal:open_share_block_modal` binding ("Share selected block", Cmd-Shift-S on macOS) and `terminal::Event::ShareModalOpened`.
- The `workspace:show_settings_shared_blocks_page` binding ("Open Settings: Shared Blocks"), the `CreateBlockPermalink` and `ViewSharedBlocks` custom actions, and their two entries in the macOS Blocks menu ("Share selected block", "View Shared Blocks...").
- The pane group's share-block modal state (`share_block_modal`, `terminal_with_open_share_block_modal`) and its test.
- `Block::full_content_height_with_display_options` and `Block::server_pwd` in the terminal model, and `warpui::browser::escape_html_attribute`, which only served block sharing.
- `TelemetryEvent::{CopyBlockSharingLink, GenerateBlockSharingLink}`, whose payload types were deleted.

**Modified:**
- `terminal/view.rs` — the block context menu keeps Copy, Copy command, Copy output, Copy filtered output, the prompt copy items, Paste, Find, filter, bookmark and scroll actions. The separator that preceded "Share block..." now precedes the session-sharing items.
- `settings_view/mod.rs` — the Scripting page (when enabled) is inserted after Warpify in the sidebar instead of before Shared blocks.
- `resource_center/{sections, utils}.rs` — the block-actions tip no longer mentions sharing, and the keybinding reference no longer lists the share binding.
- `util/tooltips.rs` — the secret-redaction tooltip no longer mentions shared blocks.

**User-visible impact:** Blocks can no longer be shared as links or embeds. "Share block..." is gone from the block context menu along with its Cmd-Shift-S shortcut on macOS, "Share selected block" and "View Shared Blocks..." are gone from the Blocks menu, and Settings no longer has a Shared blocks page. Copying block commands and output, bookmarks, find and filters work as before. Blocks shared before this change stay on Warp's servers and can no longer be managed from the app.

**Notes:**
- The shared-block title-generation setting (`SharedBlockTitleGenerationEnabled`, `AISettings::is_shared_block_title_generation_enabled`), its widget on the Warp Agent settings page, the `SHARED_BLOCK_TITLE_GENERATION_FLAG` keybinding context flag and `TelemetryEvent::ToggleSharedBlockTitleGenerationSetting` are left for AI-09. Nothing reads the setting to generate titles any more.
- `TelemetryEvent::ContextMenuOpenShareModal` is no longer emitted; TEL-4 deletes it. The `SharedBlockTitleGeneration` feature flag and Cargo feature are left for FLAGS-1.
- The `ShareBlock`, `UnshareBlock` and `GetBlocksForUser` operations in `crates/graphql` have no callers now and go with the crate in SRV-1.
- `AuthViewVariant::ShareRequirementCloseable` stays because Warp Drive sharing still uses it (AUTH-1/DRV-1).

## Referrals, rewards and referral-unlocked themes
**Why:** The referral program ran on Warp's servers. The Referrals settings page fetched the user's referral link and claim count (GraphQL `GetReferralInfo`) and sent invite emails (`SendReferralInviteEmails`). At startup every window asked the server whether a logged-in user had referred someone or been referred, to unlock two reward themes and show a "you earned a theme" modal. The offline build has no accounts and no server, so the program is removed and the reward themes are simply available to everyone.

**Removed:**
- `app/src/settings_view/referrals_page.rs` and `SettingsSection::Referrals` — the Referrals page (referral link, copy link, email invites, swag reward meter), its nav item, page handle, slug (`"Referrals"`) and the `workspace:show_settings_referrals_page` binding.
- `app/src/server/server_api/referral.rs` — `ReferralsClient`, `ReferralInfo` and `ServerApiProvider::get_referrals_client`.
- `app/src/referral_theme_status.rs` — `ReferralThemeStatus`, which queried the server and stored unlock state in user defaults (`ReferralThemeActive`, `ReceivedReferralTheme`), and `GlobalResourceHandles::referral_theme_status`.
- `app/src/reward_view.rs` and the workspace reward modal (`reward_modal`, `reward_modal_pending`, `WorkspaceState::is_reward_modal_open`, the hand-off that delayed it behind the changelog) and `ContextFlag::ShowRewardModal`.
- Referral entry points: `WorkspaceAction::ShowReferralSettingsPage`, the "Invite People..." command and macOS app-menu item (`workspace:show_invite_modal`, `CustomAction::ReferAFriend`), "Invite a friend" in the account menu, the "Invite a friend to Warp" button in the resource center, and `EarnRewardsWidget` ("Earn rewards by sharing Warp with friends & colleagues" / "Refer a friend") on the Account settings page.
- Assets used only by these views: `bundled/svg/referral-*.svg` (swag icons) and `bundled/svg/send.svg`.
- The `referral_code` parameter of `AuthManager::create_anonymous_user` and `warp_server_client::AuthClient::create_anonymous_user`. Every caller passed `None`.
- The workspace reward-modal tests.

**Modified:**
- `themes/theme_chooser.rs` — the theme chooser lists every built-in theme. `ThemeChooser::new` no longer takes the referral model.
- `themes/{theme, default_themes}.rs` — the two reward themes are ordinary built-in themes named "Nebula" (dark, formerly "Warp Referral") and "Opal" (light, formerly "Referred to Warp" / "Received Referral Reward"). Their backgrounds are renamed to `jpg/nebula_bg.jpg` and `jpg/opal_bg.jpg`.
- `workspace/view.rs` — changelog handling no longer holds back a pending reward modal. `build_settings_views` lost its unused `GlobalResourceHandles` parameter.
- `lib.rs`, `global_resource_handles.rs` and the `terminal/input_tests.rs` test setup — the referral model is no longer created.
- `crates/integration` session-restoration test and its `restored_settings.sqlite` fixture — the restored settings pane is on Appearance instead of the removed Referrals page.

**User-visible impact:** Nebula and Opal appear in the theme picker for everyone, and a saved selection of either theme keeps working. The Referrals settings page, the "Invite People..." command and menu item, "Invite a friend" in the account menu, the resource-center invite button, the Account-page rewards row and the "you earned a theme" modal are gone. A restored settings pane that was showing Referrals opens on the default page.

**Notes:**
- The `ThemeKind::SentReferralReward` / `ReceivedReferralReward` variant names and the `ReferralReward` serde alias are kept on purpose. They are the values stored in `settings.toml` and user defaults, so renaming them would reset users' theme choice. This is the only remaining `referral` match in `app/src` apart from the telemetry below. Both themes stay `schemars(skip)`, so the generated settings schema still omits these legacy value names.
- `TelemetryEvent::CopyInviteLink` ("Copy Link" on the referral modal) is no longer emitted. TEL-4 deletes it.
- The `GetReferralInfo` and `SendReferralInviteEmails` operations in `crates/graphql` have no callers now, and `CreateAnonymousUser` always sends `referral_code: None`. They go with the crate in SRV-1. Anonymous-user creation itself is removed by AUTH-1.

## Warp TUI front-end
**Why:** `crates/warp_tui` was the "Warp Agent CLI", a headless terminal UI whose only purpose was to front Warp's own agent. It required a Warp account (device-code login), talked to Warp's servers for onboarding markers, usage and MCP, had its own autoupdater, and re-exported large parts of the app's AI and server APIs through `app/src/tui_export.rs`. None of that has a place in an offline terminal without built-in AI.

**Removed:**
- `crates/warp_tui` — the TUI crate: the `warp-tui`, `warp-tui-oss`, `warp-tui-dev`, `warp-tui-preview` and `warp-tui-stable` binaries, its autoupdater, its channel-config embedding `build.rs`, benches and tests.
- `app/src/tui/` (device login model, TUI MCP manager, user info, TUI telemetry), `app/src/tui_export.rs` and `app/src/tui_export/`, `app/src/tui_onboarding_markers*.rs`, `app/src/tui_test_support.rs`.
- `app/src/lib.rs` — `LaunchMode::Tui`, `TuiEntryPoint`, `TuiMountFn`, `run_tui`, `run_tui_cli_command`, `run_tui_worker_if_requested`, the `.tui` secure-storage service suffix, the TUI-only app callbacks, the non-blocking startup IAP authentication path, the TUI API-key refresher and the per-launch-mode `set_settings_mode` call (the settings mode now always defaults to GUI).
- Persistence scopes `PersistenceScope::Tui` and `PersistedDataScope::TuiFrontend` (the separate `tui/warp.sqlite` database).
- Settings groups `TuiAutoupdateSettings`, `TuiThemeSettings`, `TuiVoiceSettings`, `TuiZeroStateSettings` (`app/src/settings/tui_*.rs`) and the TUI-only AI settings `TuiStatusline` (`agents.statusline`) and `TuiUsageDisplayMode` (`agents.usage_display_mode`).
- `app/src/server/server_api/tui_onboarding.rs`, the `tuiOnboardingMarkers` GraphQL query (`crates/graphql/src/api/queries/tui_onboarding_markers.rs`) and its entries in the client schema (`crates/warp_graphql_schema/api/schema.graphql`, `client-schema.ts`).
- `app/src/ai/tui_api_keys.rs` — the cross-process API-key revision file.
- `CLIAgent::WarpTui` and the `CLIAgentType::WarpTui` telemetry value, together with the logic that detected `warp`/`warp-tui`/`run-tui` in a pane and hid the input box and "Use agent" footer (`is_running_warp_tui`, `supports_cli_agent_footer`).
- `UserWorkspaces::warp_agent_cli_upgrade_link` (the `?source=warp-agent-cli` upgrade URL) and its tests.
- The TUI slash-command data sources (`TuiSlashCommandDataSource`, `TuiZeroStateDataSource`) and TUI-only helpers (`record_autodetection_toggle_from_slash_command`, `saved_prompt_text_for_id`, `AgentModeAutoDetectionSettingOrigin::SlashCommand`).
- The bundled `tui-migrate-setup` skill (`resources/bundled/skills/tui-migrate-setup`), its `TuiOnly` activation and its template variables, plus the `warp_core::paths` helpers that only it used (`gui_config_local_dir`, `gui_mcp_config_file_path`, `gui_app_id_for_channel`).
- Other code that only the TUI reached: `CodeEditorModel::new_tui` and the char-cell visual-row kill helpers, `vim_visual_selection_ranges`, `PtyIntent::Interrupt`/`write_interrupt`, the TUI terminal-manager adapter (`create_tui_model`) and its `SshRemoteServerSupport` switch, `web_logout_url_with_continue`, `warp_cli::is_worker_invocation`, `AIExecutionProfile::default_profile_for_tui` and the TUI profile seeding, `AgentViewEntryOrigin::Tui`, `HandoffSurface::Tui`, and AI orchestration/handoff/MCP helpers exported only through `tui_export` (location snapshot, `harness_is_selectable`, `oz_run_url`, `OZ_ENVIRONMENTS_URL`, handoff environment/model setters, `WatchedRunStatusChanged`, the MCP `AuthenticationRequired`/`CredentialsChanged` events and credential accessors).
- The `tui` feature in `app/Cargo.toml` and the `release-tui` / `release-tui-debug-assertions` profiles in the workspace `Cargo.toml`.
- `.agents/skills/tui-testing` and `.agents/skills/tui-ui-guidelines`.

**Modified:**
- Test-only constructors that were gated on `any(test, all(feature = "tui", feature = "test-util"))` are now `cfg(test)`; MCP helpers gated on `any(feature = "tui", test)` are now `cfg(test)`.
- `app/src/terminal/local_tty/terminal_manager.rs`, `app/src/terminal/model_events.rs` — the local terminal manager has a single constructor; SSH remote-server use depends only on the feature flag and the session type.
- `AGENTS.md` — removed the TUI front-end sections, the `script/run-tui` command and TUI testing guidance. The kept skills (`add-feature-flag`, `remove-feature-flag`, `promote-feature`, `gui-ui-guidelines`, `gui-integration-test`, `gui-settings-ui`, `rust-unit-tests`) no longer point at `crates/warp_tui` or the TUI skills.
- Doc comments in `crates/settings`, `crates/editor`, `crates/warp_terminal`, `crates/warp_channel_config`, `crates/warpui_core` and shared app modules no longer name `warp_tui` or describe TUI consumers.

**User-visible impact:** The Warp Agent CLI binaries no longer exist. In the GUI, running `warp`, `warp-dev` or `warp-tui` in a pane is an ordinary command: it is no longer treated as a CLI agent that hides the input box and footer. TUI-only settings (`agents.statusline`, `agents.usage_display_mode`, TUI theme, voice, zero-state and autoupdate) are ignored if present in `settings.toml`. The `tui-migrate-setup` bundled skill is gone.

**Notes:**
- Left for AI-04 (TUI rendering layer and modes in core crates): the `tui` features of `warpui_core` and `warp_terminal` (nothing enables them now), `ratatui`, `SettingsMode::Tui`, `ExecutionMode::Tui`, `LogFrontend::Tui` and the app branches that match them (`settings/mod.rs::user_preferences_toml_file_path`, `settings/init.rs`, `settings/cloud_preferences_syncer.rs`, `warp_managed_paths_watcher.rs`, the deferred global-server autostart in `ai/mcp/file_based_manager.rs` and `use_tui_loopback` in `ai/mcp/templatable_manager/native.rs`, `settings/schema_generation.rs`), `warp_core::paths::{tui_config_local_dir, tui_mcp_config_file_path, tui_state_dir}`, the char-cell editor layout in `crates/editor` (`RenderState::new_tui`, `char_cell_display`) and its remaining branches in `app/src/code/editor/model.rs`, and `settings::set_settings_mode` (no longer called).
- Left for AI-24: the TUI-only static slash commands (`/exit`, `/logout`, `/theme`, `/voice`, `/upgrade`, `/statusline`, …) and `SlashCommandSurfaces::{TuiOnly, GuiAndTui}`. Left for AI-33: `SettingSurfaces::TUI`.
- Left for SRV-1: the `tui_version` field in `crates/channel_versions` (SRV-1 deletes the crate).
- `app/src/ai/**` still has doc comments describing GUI/TUI sharing; the AI tasks that delete those modules remove them.
- Left for the AI onboarding/launch-modal task (ai.md: `workspace/view/agent_cli_launch_modal/` and its `one_time_modal_model.rs` state): the GUI modal that advertised the Warp Agent CLI. Left for the account/auth removal: the `warp-agent-cli` OAuth client id in `crates/warp_server_client/src/auth/session.rs`, used by the shared device-authorization flow.
- `ProfileSource::SettingsCollection { migrates_legacy_cloud_profiles: false }` in `ai/execution_profiles/profiles.rs` (the non-migrating settings backend) was only reached by the TUI and is now unreachable; its test in `ai/llms_tests.rs` was removed. The AI task that deletes execution profiles removes the branch.
- One dead-code warning is left on purpose: the `CodeEditorModelEvent::UnifiedDiffComputed` payload was only kept alive by the `warp_tui` re-export of `CodeEditorModelEvent` and is now read only by tests. It belongs to the AI code-diff accept flow (`CodeSource::AIAction`) and goes with that flow.
- The server APIs that `tui_export.rs` re-exported (`AuthStateProvider`, `ServerApiProvider`, `changelog_model`, `TelemetryEvent`, `server::ids`, `team_scope`, `server_api::ai`) are no longer pinned by the TUI; the server tasks can now delete them.
- Existing `tui/warp.sqlite` databases, the TUI config directory and `.tui` keychain entries on users' machines are left untouched.

## TUI dev script
**Why:** The Warp Agent CLI (`crates/warp_tui`) is gone, so the script that built and ran it has nothing left to build. The packaging side (the `tui` bundle artifact and the Windows TUI installer) was already removed in [Packaging: Warp release infrastructure](#packaging-warp-release-infrastructure).

**Removed:**
- `script/run-tui` — built and ran a local `warp-tui-oss` binary.

**Modified:**
- `script/presubmit` — dropped the comment about `warp_tui` enabling `warp/tui` through feature unification.

**User-visible impact:** None for users. Contributors can no longer run the TUI.

**Notes:** None.

## Channel-config loader crate
**Why:** `crates/warp_channel_config` loaded a per-channel `ChannelConfig` from Warp's private `warp-channel-config` generator (or from JSON embedded at build time). Its last users were the `warp_tui` channel binaries; the GUI channel binaries that also used it were removed earlier (see [Channel binaries and private config loader](#channel-binaries-and-private-config-loader)). `warp-oss` builds its config in code.

**Removed:**
- `crates/warp_channel_config` and its `[workspace.dependencies]` entry in the root `Cargo.toml`.

**Modified:** None.

**User-visible impact:** None.

**Notes:** `rg warp_channel_config` found no other users before the deletion.

## Client and server-side experiments
**Why:** Warp ran two experiment systems. The client framework hashed the per-install anonymous ID into A/B buckets and reported each assignment to telemetry (`ExperimentTriggered`). The server framework read an `experiments` list from the `GetUser` and `GetWorkspacesMetadataForUser` GraphQL responses, sent the anonymous ID as `X-Warp-Experiment-Id` so the server could bucket the client, cached the list in SQLite and flipped feature flags from it at runtime. An offline build has no server to assign experiments and must not vary behavior per install, so each experiment is fixed to the arm a new OSS user got.

**Removed:**
- `app/src/experiments/` — `Experiment`, `Layer`, bucket ranges, the `ExperimentOverrides` user-preference override, `experiments::init` and the layer validation tests. Its layers were `LoginLayer`, `BlockOnboardingLayer`, `ImprovedPaletteSearchLayer` and the empty `RenderingLayer`.
- `app/src/server/experiments/` — the `ServerExperiment` enum, the `ServerExperiments` singleton and its `ExperimentsUpdated` event, the GraphQL/string conversions and the `convert_to_server_experiment!` macro.
- `ServerApiProvider::handle_experiments_fetched` and its calls after a user fetch (`auth_manager.rs`) and a workspace-metadata poll (`update_manager.rs`).
- `settings_view::handle_experiment_change` (`main_page.rs`). It re-registered the settings-sync toggle binding when experiments changed; the startup registration in `init_actions_from_parent_view` is unchanged.
- Persistence: `ModelEvent::SaveExperiments`, `save_experiments`, the `server_experiments` read in `read_sqlite_data`, `PersistedData::experiments`, and the `ServerExperiment` / `NewServerExperiment` models in `crates/persistence/src/model.rs`.
- The `experiments` field from the `GetUser` and `GetWorkspacesMetadataForUser` selections and the `warp_graphql::experiment::Experiment` enum; `WorkspacesMetadataResponse::experiments` and `UserProperties::server_experiments`.
- `EXPERIMENT_ID_HEADER` (`X-Warp-Experiment-Id`) in `warp_server_client`, which was sent on `GetUser` and `/client/login`.
- The `ServerExperiments` subscriptions in `UserWorkspaces::new`, `RunAgentsCardView` and `OrchestrationConfigBlock`, and the experiment override check in `UserWorkspaces::update_session_sharing_enablement`.
- Test setup: `experiments::init` and the `ServerExperiments` singleton in `test_util/terminal.rs`, `pane_group/mod_tests.rs`, `terminal/input_tests.rs` and `workspace/view_tests.rs`; `orchestration_controls_tests.rs`, which only tested the runner experiment gate.

**Modified (permanent arm per experiment):**
- Client experiments, bucketed by anonymous ID:
  - `ImprovedPaletteSearch` (100% `Experiment`): Tantivy full-text search is on for every install. `lib.rs` now calls `FeatureFlag::UseTantivySearch.set_enabled(true)` unconditionally at the same point in startup.
  - `BlockOnboarding` (30% `VariantOne`, 70% `VariantTwo`; every install was in one of the two):
    - `workspace/view.rs`: both arms suppressed the Warp AI warm welcome when the workspace was built, so `should_show_ai_assistant_warm_welcome` now starts `false`.
    - `root_view.rs`: `VariantOne` skipped the onboarding survey after sign-in; `VariantTwo` did not. Kept `VariantTwo`, the majority arm and the one that changes nothing. The check only ran on `AuthComplete`, which the logged-out build never reaches.
  - `AuthFlowInstructions` (25% `Control`, 25% `Experiment`, 50% unassigned, which behaved like `Control`): kept `Control`. The auth-token input placeholder is always "Auth Token"; the "Browser auth token" variant is gone.
- Server experiments: a logged-out user never receives any, so the permanent arm is "not enrolled" for all of them, and no runtime flag override happens:
  - `SessionSharingExperiment` / `SessionSharingControl`: no override. `CreatingSharedSessions` follows the team tier policy, as it already did without an experiment.
  - `DisableAgentModeExperiment`, `AgentModeAnalyticsExperiment`, `CodebaseContextExperiment` / `Control`, `BuildPlanAutoReload{Control, BannerToggle, PostPurchaseModal}`, `PromptSuggestionsViaMaa{Control, OutOfBandExperiment}` and `OzMultiHarness{Control, Experiment}`: the flags they set (`AgentMode`, `AgentModeAnalytics`, `AIRules`, `SuggestedRules`, the codebase-context flags, `BuildPlanAutoReload*`, `PromptSuggestionsViaMAA`, `AgentHarness`) keep their build defaults.
  - `EnvVarsEarlyAccessExperiment`, `WindowsLaunchExperiment`, `SuggestedCodeDiffs{Control, Experiment}` and `PromptSuggestionsViaMaaExperiment` were already no-ops.
  - `MacosRunners{Control, Experiment}`: `orchestration_controls::runner_controls_enabled()` returns `false`, so the orchestration cards never show the remote Runner picker. This is a minimal compile fix in AI code; the parameter it no longer needs is gone from its six call sites.
- `UserWorkspaces::update_session_sharing_enablement` no longer takes a context.

**User-visible impact:** None for the OSS build. Command-palette search stays full-text, and the Warp AI warm welcome still starts hidden. The client no longer sends the experiment-ID header and never flips feature flags from server data.

**Notes:**
- The `server_experiments` table stays in the schema and keeps any rows written by earlier versions; DB-1 drops it.
- `TelemetryEvent::ExperimentTriggered` is never emitted now. TEL-4 deletes it.
- `FeatureFlag::UseTantivySearch` and its `use_tantivy_search` Cargo feature stay. FLAGS-1 can make full-text search unconditional and drop the `set_enabled` call in `lib.rs`.
- Stale comments left in files owned by other tasks: the `CreatingSharedSessions` doc in `crates/warp_features/src/lib.rs` still links `ServerExperiment` (FLAGS-1); the `ExperimentId` storage-key comment in `crates/warp_server_auth/src/anonymous_id.rs` (AUTH-2, which deletes the anonymous ID); the "warp drive preferences experiment" comment in `settings/cloud_preferences_syncer.rs` (settings sync removal).
- `crates/warp_graphql_schema/api/schema.graphql` still declares `experiments` on `User`; SRV-1 deletes the schema.
- The remote-runner picker code in `run_agents_card_view.rs`, `orchestration_config_block.rs` and `orchestration_controls.rs` is now unreachable. AI-19 deletes it with orchestration.

## App-installation detection and the local HTTP server
**Why:** Every GUI instance started an HTTP server on `127.0.0.1`, port 9277 plus a per-channel offset (9282 for `warp-oss`). It served two routes. `/install_detection` answered CORS requests from `https://warp.dev`, any `*.warp.dev` origin and `localhost:8080/8082`, so Warp's web pages could tell that the desktop app was installed. `/debug/pprof/heap` returned a jemalloc heap profile when the `jemalloc_pprof` feature was on. An offline build must not expose an endpoint for Warp's websites, and a developer heap dump does not need a network listener.

**Removed:**
- `crates/app-installation-detection` (the CORS router for `*.warp.dev`) and `crates/http_server` (the `HttpServer` singleton, its private tokio runtime and the port table), with their `[workspace.dependencies]` entries and the dependencies in `app` and `crates/integration`.
- `LaunchMode::should_start_local_http_server` and the `HttpServer` registration in `initialize_app` (`lib.rs`).
- `profiling::make_router` and its axum handler `handle_get_heap`.
- The comment in the wasm-only `Workspace::open_link_on_desktop` that described the `localhost:9277/install_detection` endpoint.

**Modified:**
- `app/src/profiling.rs` — with `jemalloc_pprof`, `dump_heap_profile_to_disk` now writes the jemalloc heap profile (gzipped pprof, unsymbolized as before) to `jemalloc-heap-<timestamp>.pb.gz` in the profile output directory. That is the working directory for dev builds, or the state directory for release bundles. `dhat_heap_profiling` still takes precedence when both features are on.
- `app/src/workspace/mod.rs` — the "Write heap profile to disk" command-palette action (`workspace:dump_heap_profile`) is registered with either `dhat_heap_profiling` or `jemalloc_pprof`, so jemalloc builds keep an on-demand heap dump.
- `app/Cargo.toml` — `tracing-subscriber` now enables `env-filter` itself. `app/src/tracing/native.rs` uses `EnvFilter`, which had only compiled because `app-installation-detection` turned the feature on through Cargo feature unification.

**User-visible impact:** Warp no longer opens a listening socket at startup. Warp's web pages can no longer detect the desktop app. Developer builds with `jemalloc_pprof` get their heap profile from the command palette as a file, instead of `curl http://127.0.0.1:<port>/debug/pprof/heap`.

**Notes:**
- `local_control` (`warpctrl`) did not depend on `http_server`. It runs its own axum listener on an ephemeral loopback port, only when `FeatureFlag::WarpControlCli` is enabled and the user opts in, so it is off by default. It keeps the `axum` dependency of `app`.
- Remaining users of `axum`: `app` (only `local_control`), `crates/serve-wasm` (with `axum-extra`) and `crates/mcp` as a dev-dependency. Remaining users of `tower-http`: `reqwest` 0.13 (its client-side redirect and decompression layers) and `crates/serve-wasm`. The `tower-http` workspace dependency stays for `serve-wasm`, which WASM-1 deletes; `tower-http` then remains only as a `reqwest` internal.
- Left for WASM-1: `settings/app_installation_detection.rs` (`UserAppInstallDetectionSettings`, a web-only setting that the host page writes) and `NativeRedirectWidget` in `settings_view/features_page.rs` (the web-only "Open links in desktop app" toggle). Neither talks to the removed server. They drive the web app's open-in-desktop flows in `wasm_nux_dialog.rs`, `drive/index.rs`, `notebooks/notebook.rs`, `workflows/workflow_view.rs`, `terminal/view/pane_impl.rs` and `Workspace::open_link_on_desktop`, which redirects to `warp.dev/download`.
- `rg 'http_server|9277|install_detection'` still matches unrelated code: the OSC 9277 in-band generator marker in `warp_terminal` and the shell bootstrap scripts, MCP test names such as `explicit_http_server` (AI plan), and SVG path data.
- The runtime capture of `warp-oss` shows no listening socket. The baseline had `127.0.0.1:9282 LISTEN`.

## Legacy Warp AI assistant and AI command search
**Why:** The Warp AI side panel and AI command search sent every question to Warp's servers (the `generateDialogue` and `generateCommands` GraphQL mutations). They are built-in AI features, which the offline fork removes.

**Removed:**
- `app/src/ai_assistant/` — the Warp AI side panel (`AIAssistantPanelView`, transcript, requests model and its request-limit cache, markdown utilities), `AskAIType`, the panel keybindings (`ai_assistant_panel:*`) and its tests.
- AI command search: `search/command_search/{warp_ai.rs, ai_queries/}` and `search/ai_queries/` (the "translate with Warp AI" source and the Agent Mode prompt-history source), the `CommandSearchItemAction::{OpenWarpAI, TranslateUsingWarpAI, AcceptAIQuery, RunAIQuery}` results, `QueryFilter::NaturalLanguage` (the `#` filter atom) in `warp_search_core`, the out-of-credits "Upgrade" header in command search, and the zero-state `#` sample query and prompt-history chip.
- The `#` trigger in the terminal input, `InputAction::ShowAiCommandSearch` with its `input:toggle_natural_language_command_search` binding, `CustomAction::AISearch` and its app-menu item, and the `EnableAiCommandSearchHashTrigger` setting (`terminal.input.enable_ai_command_search_hash_trigger`) with its settings-page toggle and keymap flag.
- "Ask Warp AI" / "Attach as agent context" entry points: the terminal, block and alt-screen context-menu items, the input context-menu "AI command search" and "Ask Warp AI" items, the block toolbelt AI button, the `terminal:ask_ai_assistant*` bindings, `CustomAction::AttachSelectionAsAgentModeContext` and its app-menu item, and `ContextMenuAction::AskAI`, `AskAISource`, `TerminalAction::AskAIAssistant`, the `AskAIAssistant` terminal and pane-group events, `PaneEvent::NewPaneInAIMode`, `TerminalView::{ask_ai, ask_blocklist_ai}`. Both the Agent Mode and the Warp AI branches went, since Agent Mode is treated as permanently off.
- Workspace: the panel and its focus handling, the header "Warp AI" button, the warm-welcome popup (and its `DismissedWarpAIWarmWelcome` preference key), `WorkspaceAction::{ToggleAIAssistant, ClickedAIAssistantIcon, ShowAIAssistantWarmWelcome, ClickedAIAssistantWarmWelcome, DismissAIAssistantWarmWelcome}`, the "Toggle Warp AI" binding and the disabled Agent Mode binding that shared its `workspace:toggle_ai_assistant` name.
- The Warp AI panel width (`ModalType::WarpAIWidth`, `WindowSnapshot::warp_ai_width`); window snapshots now write `NULL` to the `windows.warp_ai_width` column.
- Tips: `TipAction::{AiCommandSearch, WarpAI}`, `WelcomeTipFeature::AiCommandSearch`, `VoltronItem::AiCommands`, and the "AI command search" items in the resource center and the welcome tips.
- `warpctrl surface ai-assistant toggle` (`ActionKind::SurfaceAiAssistantToggle`, `SurfaceDestination::AiAssistant`).
- `AIClient::{generate_commands_from_natural_language, generate_dialogue_answer}` and their `ServerApi` implementations.
- `crates/integration/src/test/ai_assistant.rs` (`test_ask_warp_ai_keybinding_for_selected_block`).
- AI code that only the removed `pub mod ai_assistant` kept from being reported as dead: `AIClient::{get_ai_conversation_format, download_conversation_transcript_to_path, report_agent_event}`, `AIAgentConversationFormat`, `AIAgentSerializedBlockFormat`, `ReportAgentEvent{Request,Response}`, `AIWorkflowOrigin::{CommandSearch, LegacyWarpAI}`, and never-read `mime_type` / `size_bytes` fields on the task-attachment and file-artifact records. `ATTACH_AS_AGENT_MODE_CONTEXT_TEXT` and `NEW_AGENT_PANE_LABEL` lost their last users.

**Modified:**
- `app/src/ai/execution_context.rs` — `WarpAiExecutionContext` / `execution_context_for_session` moved here from `ai_assistant/`, so the agent core still builds.
- `app/src/ai/request_usage_model.rs` — now holds the GraphQL `RequestLimitInfo` / `RequestLimitRefreshDuration` conversions that lived in `ai_assistant/mod.rs`.
- `search/command_search/view.rs` — `CommandSearchView::new` no longer takes an `AIClient`, `reset_state` no longer takes an execution context, and `CommandSearchEvent::{Close, ItemSelected}` no longer carry the query and filter (they were only used for the `#` buffer handling). Data-source errors still show as a plain header.
- `terminal/block_list_element.rs` — the block toolbelt is three slots wide; the bookmark, filter and overflow buttons keep their positions.
- `workspace/view_tests.rs::test_switch_focus_panels` now uses the resource center's keyboard shortcuts page as the right-side panel. `terminal/input_tests.rs` keeps one test that `#` stays literal input; the two tests of the removed setting and hotkey are gone. The `local_control` catalog-size tests expect 83 actions.
- `server/telemetry/events.rs` — the `CommandSearchItemAction` conversion drops the removed arms (compile fix only).
- `resources/bundled/skills/warpctrl/SKILL.md` — drops the removed `surface ai-assistant toggle` example.

**User-visible impact:** The Warp AI panel, its header button and welcome popup, "Ask Warp AI" / "Attach as agent context" menu items and keybindings (ctrl-shift-space, ctrl-shift->), and AI command search are gone. Typing `#` at the start of the input is plain text (a shell comment). Command search still covers history, workflows and environment variables. The block hover toolbelt no longer has an AI button. `warpctrl` no longer accepts `surface ai-assistant toggle`. A stored `enable_ai_command_search_hash_trigger` key in `settings.toml` is ignored.

**Notes:**
- Users who used AI command search or Warp AI have `AiCommandSearch` / `WarpAI` tip entries in the private `WelcomeTipsFeaturesUsed` value. That value no longer parses, so their welcome-tips progress resets once; the next tip they use rewrites it.
- Left for DB-1: the `windows.warp_ai_width` column (still in `crates/persistence` `schema.rs` and the model structs).
- Left for the server plan (`crates/graphql` owner): the now-unused `mutations::{generate_commands, generate_dialogue}` and `queries::get_ai_conversation_format` operations.
- Left for TEL-4: telemetry variants whose callers are gone (`OpenedWarpAI`, `ToggleWarpAI`, `InputAskWarpAI`, `InputAICommandSearch`, `AICommandSearchOpened`, `CommandSearchResultType::{OpenWarpAI, TranslateUsingWarpAI, AIQuery}`, `OpenedWarpAISource`, `AICommandSearchEntrypoint`).
- Left for AI-15: the AI-gated `AgentModeWorkflows` (saved prompts) filter in command search. Left for AI-11: `resources/bundled/skills/change-keybinding/SKILL.md` still names `workspace:toggle_ai_assistant`. Left for DRV-1: a comment in `drive/workflows/modal.rs` that cites Warp AI command search.
- `set_ai_input_mode_with_query` and `InputTypeAutoDetectionSource::AskAi` stay because `ai/agent_sdk` still uses them.
- Follow-up fix (HOTFIX-1): the first commit left `CustomAction::NewAgentModePane` in the app's AI menu after its last binding was removed. Debug builds build the menus at startup and assert that every menu action has a named binding, so they panicked with `action should have a name: NewAgentModePane` (this also broke GUI integration tests such as `test_auto_title`). The menu entry, the `NewAgentModePane` variant and its ctrl-space default in `util/bindings.rs` are now deleted, as is the separator that would otherwise have opened the AI menu. Release builds skip the assert and showed a disabled `<NO DESCRIPTION>` item at the top of the AI menu instead.

## SSH remote server
**Why:** The "SSH extension" installed the `oz` binary onto the remote host by curling `app.warp.dev/download/cli` (or copying it over SCP), ran it as a daemon, and authenticated it with the user's Warp credentials. An offline build can't download it, and bundling cross-built daemons for every remote OS and architecture is out of scope. Plain SSH never needed it: blocks and completions over SSH run through the ControlMaster-based `RemoteCommandExecutor`.

**Removed:**
- `crates/remote_server` (client, manager, SSH transport, installer and `install_remote_server.sh`/`preinstall_check.sh`, protocol, the `remote_server.proto`/`diff_state.proto` definitions and their conversions) and `app/src/remote_server/` (daemon `ServerModel`, Unix proxy, SSH/SCP install transport, `auth_context`, `auth_provider`, `codebase_index_model`, `codebase_index_status`, `handoff_snapshot`, buffer/diff-state trackers, ripgrep search).
- Worker subcommands `remote-server-proxy` and `remote-server-daemon` (`WorkerCommand::{RemoteServerProxy, RemoteServerDaemon}`, `RemoteServerIdentityArgs`), `LaunchMode::{RemoteServerProxy, RemoteServerDaemon}`, `ExecutionMode::RemoteServerDaemon`, `PersistenceScope::RemoteServerDaemon` and `PersistedDataScope::CodebaseIndicesOnly` (the daemon's own database is no longer opened; the schema is untouched), the daemon-only "unavailable" secure-storage provider, and the `RemoteServerManager` and `RemoteCodebaseIndexModel` singletons.
- SSH session wiring: `RemoteServerController`, the SSH extension install choice block and install-failed banner, the remote-server loading footer and setup-state prompt text, `RemoteServerCommandExecutor`, `SessionType::WarpifiedRemote`'s `host_id`, and the `SshInitShell`/`RemoteServerBlockRequested`/`RemoteServerReady`/`RemoteServerFailed` events. SSH sessions always use the ControlMaster executor again.
- The `ExitShell` shell hook (`DProtoHook::ExitShell`, handler and events) and the matching `WARP_IS_SSH` export and exit traps in the bash and zsh bootstrap scripts. It existed only to tear down the proxy subprocess.
- Remote backends: `RemoteDiffStateModel`, `RemoteGitRepoStatusModel` and `RemoteGitHubRepoModel` in code review; remote, server-local and synced buffers in `GlobalBufferModel` (with `SyncClock` and the remote conflict and disconnect banners); `FileModel` remote files; remote file-tree roots and lazy directory loading; remote global search; remote markdown files; remote `@`-menu file listing; host-scoped repo detection.
- In `crates/repo_metadata`: `RemoteRepoMetadataModel`, `RepositoryIdentifier::Remote`, the proto-mirror update types in `file_tree_update.rs`, the daemon's incremental-update emission and symlink-target watches. In `crates/warp_util`: `RemoteNavigationResult` and `FileSaveError::RemoteError`. In `warp_server_auth`: the daemon auth helpers (`apply_remote_server_auth_context`, `set_remote_server_bearer_token`).
- Remote parts of AI code as minimal compile fixes: `remote_agent_context`, `remote_context_files`, `skills/remote`, remote codebase search and indexing context, remote file reads and diff application for agents, the remote handoff-snapshot upload target, and the remote codebase rows in Settings > Code > Indexing.
- The Warpify setting `warpify.ssh.ssh_extension_install_mode` and its dropdown, the remote-server telemetry events, `SetSshExtensionInstallMode`, and the remote fields of `SSHControlMasterError` and `GlobalSearchQueryCompleted`.
- `crates/integration/src/test/remote_server.rs`, `app/src/integration_testing/remote_server.rs` and the remote-server SSH test host helpers.

**Modified:**
- `app/src/util/repo_detection.rs` — repo detection runs only for local sessions; remote sessions resolve to no repository.
- `warp_files::FileModel`, `GlobalBufferModel`, `DiffStateModel`, `GitRepoStatusModel`, `GitHubRepoModel`, `RepoMetadataModel` — now wrap only their local backend. `GlobalBufferModel::open` and `LocalCodeEditorView::new_with_global_buffer` take a `PathBuf`.
- `DiffStateModel` methods and `WorkingDirectoriesModel::get_or_create_diff_state_model` lost their `preferred_session` argument, which only routed remote requests.
- `CodingPanelEnablementState::RemoteSession` lost `has_remote_server`: the file tree, global search and code review show their "not supported in remote sessions" state for every SSH session.
- The tmux-deprecation banner and the ControlMaster-error banner no longer point to the SSH extension.
- `util::path::display_path_with_host`/`display_name_with_host` became `display_location_path` and `LocalOrRemotePath::display_name`, since there are no host labels.
- Tests that exercised remote behavior were deleted; the global search submatch tests now run on local matches.

**User-visible impact:** Warp never offers to install the SSH extension and never downloads, copies or runs anything on remote hosts. SSH sessions, SSH Warpify, blocks, completions and command corrections over SSH work as before (through the ControlMaster connection). The remote file tree, remote editor, remote code review, remote global search and remote agent file access over SSH are gone; those panels show their remote-session placeholder.

**Notes:**
- `LocalOrRemotePath::Remote`, `RemotePath` and `HostId` stay in `warp_util`. Nothing constructs a remote path now, but about 130 files still name the type, many of them AI skills and project-rules code. Collapsing it to `PathBuf` (and folding the single-variant `RepositoryIdentifier`, `DiffSessionType`, `GetRelevantFilesRequestTarget` and `SnapshotUploadTarget`) is left for after the AI removal.
- Remote-host skills plumbing in AI code (`SkillPathOrigin::Remote`, `BundledSkills::remote_by_host`, `SkillManager::remote_home_directories`) is now unreachable; its setters are test-only. The AI skills removal deletes it. `CodebaseIndexManager::new_with_snapshot_storage`, `defer_persisted_index_restore` and `SnapshotStorage::from_dir` in `crates/ai` were only used by the daemon; the codebase-indexing removal deletes them.
- `FeatureFlag::{SshRemoteServer, RemoteCodebaseIndexing, RemoteCodeReview}` stay for FLAGS-1; all code they gated is deleted.
- `SessionType` and `BootstrapSessionType` are now identical enums.
- The only protos were in `crates/remote_server`, which is deleted whole, so no `reserved` field numbers were needed.

## Natural-language detection and input auto-detection
**Why:** Natural-language detection (NLD) classified what the user typed as a shell command or an agent prompt and switched the input mode on its own. It exists only to route input to Warp's built-in agent, which the offline fork removes. Its ONNX classifier was also embedded from Git LFS at build time, and its `ort` backend pulled in a runtime-download stack (`ureq`, `native-tls`, `openssl`).

**Removed:**
- `crates/input_classifier` (the heuristic and BERT-tiny ONNX classifiers, the Git LFS model files and the `evaluate` binary) and `crates/natural_language_detection` (word lists and stemmer), with their `[workspace.dependencies]` entries. `app/src/input_classifier.rs` and the `InputClassifierModel` singleton.
- Auto-detection in `ai/blocklist/input_model.rs`: `InputTypeAutoDetectionSource` and every decision-source argument, `detect_and_set_input_type` with its history and prompt-history matching (`most_recent_close_match`, `resolve_history_match`), `should_run_input_autodetection`, `enable_autodetection`, the detection abort handle and suppression window, `last_ai_autodetection_{ts,source}`, `InputConfig::{new, unlocked_if_autodetection_enabled}`, and the policy's `is_autodetection_enabled`, `config_on_ai_settings_changed` and `PolicyConfigUpdate`.
- Auto-detection in the terminal input: the `with_ai_input_detection` background job in `terminal/input/decorations.rs`, the re-detection on edits, settings changes, inline-menu close and command completion, the "re-enable autodetection" paths, `enable_auto_detection`, `set_input_mode_natural_language_detection`, `InputAction::{EnableAutoDetection, ToggleInputAutoDetection}` with the `input:enable_auto_detection` binding, the `AI_Input_Autodetection` / `NLD_In_Terminal` keymap flags, the unused `input:set_mode_unlocked_{agent,terminal}` keybinding caches, the "(autodetected) … to override" message-bar hint, the auto-detection false-positive telemetry, the UDI auto-detection segment (`InputToggleMode::AutoDetection`) and the dogfood "(nld overridden)" block-prompt marker.
- Settings: `AIAutoDetectionEnabled` (`agents.warp_agent.input.ai_auto_detection_enabled`), `NLDInTerminalEnabled` (`agents.warp_agent.input.nld_in_terminal_enabled`) and `AICommandDenylist` (`agents.warp_agent.input.ai_command_denylist`), with the one-time NLD migration in `settings/initializer.rs`, the Warp Agent page's natural-language-detection section, denylist editor and toggle bindings, and the terminal zero-state "autodetect agent prompts" checkbox.
- The agent-footer NLD toggle button, `/natural-language-detection`, and the NLD checkbox in the onboarding callout (with the callout's now-unused checkbox support).
- The NLD prompt-history snapshot: `BlocklistAIHistoryModel`'s prompt-history candidates, the `nld_prompts` startup read (`process_ai_queries_for_nld_history_match`) and its plumbing through `PersistedData` and `lib.rs`.
- `EmptyCompletionContext` (only detection used it) and the unused `difflib` dependency.

**Modified:**
- `InputType` now lives in `ai/blocklist/input_model.rs`, with the same variants and serde form.
- The input behaves as it did for users with NLD off (the default): the default config is shell and locked, restored pane configs load locked, `!` and Escape lock the mode explicitly, and nothing switches modes on its own. The input-mode policy only gates locked AI input and reacts to agent-view entry and exit.
- `AgentViewEntryOrigin::Input` no longer carries `was_prompt_autodetected`, so entering the agent view from input never auto-submits the prompt. `TelemetryAgentViewEntryOrigin::Input` and `InputBufferSubmitted` drop the matching fields (compile fixes).
- `AgentToolbarItemKind::NLDToggle` stays so stored toolbar layouts that list it still load (the layout parser is strict), but it is never shown or offered.
- `.gitattributes` no longer lists the deleted model paths. `app/Cargo.toml` keeps the `nld_*` features as empty entries for AI-32.
- Tests: removed the auto-detection tests (history-match matrix, auto-detection toggles, decision sources, the NLD prompt-history seed, the NLD settings defaults and the TUI `/natural-language-detection` tests) and the ones that relied on autodetected input (`test_agent_mode_set_when_block_attached`, `test_terminal_only_ai_enter_enters_agent_view_and_clears_buffer`). `input_tests::initialize_app` no longer turns NLD on, and the tests that forced NLD on or off run without it.

**User-visible impact:** Terminal input never switches between shell and agent mode on its own; the mode changes only on explicit user action. The "Natural language detection" settings section, its toggles and the command denylist are gone, as are the agent-footer auto-detection button, the zero-state and onboarding checkboxes and `/natural-language-detection`. Existing values for the three settings are ignored.

**Notes:**
- Git LFS: no build input is an LFS asset any more. The only LFS-tracked files left are the Windows `*.pdb` debug symbols in `app/assets/windows`, which neither `build.rs` nor the bundle scripts read, so the `lfs: true` checkouts in `ci.yml` are no longer needed (CI not edited).
- Left for AI-32: the `NldPromptHistoryMatch` and other NLD feature flags, the empty `nld_*` Cargo features and their use in `script/{macos,linux}/bundle` and `script/windows/bundle.ps1`.
- Left for AI-08 / AI-27: delete `AgentToolbarItemKind::NLDToggle` once stored layouts skip unknown items.
- Left for TEL-4: the NLD telemetry variants in `server/telemetry/events.rs` (`AgentModeChangedInputType`, `AgentModePotentialAutoDetectionFalsePositive`, `AgentModeToggleAutoDetectionSetting` and their payload types).
- Left for AI-26: the `is_locked` flag of `InputConfig` now only records explicit locks. AI code still derives `is_autodetected_user_query` from it (always `false` in practice).
- `rg 'autodetect'` outside `app/src/ai` still matches unrelated code: URL autodetection (`crates/editor`, `crates/markdown_parser`, the `osc8` integration test), prompt-plugin detection in `crates/warp_terminal`, the web-intent redirect in `wasm_nux_dialog.rs`, and telemetry in `events.rs`.

## Session sharing: sharer side and entry points
**Why:** Session sharing streamed a live terminal session (PTY output, input edits, agent responses, presence) to other users through Warp's `sessions.app.warp.dev` relay, gated on a Warp account. An offline build has no relay and no accounts, so this client can no longer share its own sessions. This change removes the sharer side and every entry point that starts, stops or manages a share. Viewing someone else's session (the viewer) is left in place for SS-2.

**Removed:**
- `terminal/shared_session/sharer/` (the sharer `Network` model and its tests), `share_modal/` ("Share session" modal and quota-denied body), `role_change_modal/` (viewer role request, sharer grant and sharer response modals), `permissions_manager.rs` (`SessionPermissionsManager` singleton), `participant_avatar_view.rs` (pane-header participant avatars and role menus) and `settings.rs` (`SharedSessionSettings`: onboarding-block flag, inactivity timers, viewer-driven sizing killswitch).
- `terminal/view/shared_session/sharer/` (the `Sharer` view state and the sharer inactivity warning modal).
- The sharer glue in `terminal/local_tty/terminal_view_adaptor.rs`: starting and ending the share, the prompt/model/input-mode/selected-conversation broadcasts, guest and ACL handling, viewer command/PTY/agent-prompt handling on the sharer, network reconnect handling and the stop-on-detach hook. `TerminalManager::session_sharer` and the `terminal_view_adaptor_tests.rs` (sharer prompt authorization) go with it.
- `IsSharedSessionCreator`, the auto-share-after-bootstrap path (`SharedSessionStatus::SharePendingPreBootstrap`) and the `SharePending`/`ActiveSharer` statuses with `is_sharer`, `is_active_sharer`, `is_share_pending` and `is_sharer_or_viewer`.
- `SharedSessionScrollbackType`, `max_session_size` and the sharer-only `SharedSessionActionSource` variants.
- Sharer-side model plumbing in `TerminalModel`: the ordered-terminal-event sender for viewers and the helpers that fed it (agent responses, conversation replay markers, cloud-mode setup-phase end, command start/finish, resize, PTY bytes), and `disable_secret_obfuscation_for_shared_sesson_creator`.
- `TerminalView` sharer methods: `attempt_to_share_session`, `stop_sharing_session`, `on_session_share_started`, the share modal openers, role grant/response handling, inactivity timers, viewer-reported resizing (`resize_from_viewer_report`, `active_viewer_driven_size`, `SizeUpdateReason::ViewerSizeReported`), `is_sharing_session`, `handle_shared_session_cancel_action` and the sharer `Event`s (`StartSharingCurrentSession`, `StopSharingCurrentSession`, `EstablishedSharedSession`, `FailedToShareSession`, `ExtendSessionRetention`, `SharedSessionViewerInput`, the ACL/guest/role events, `OpenShareSessionModal`, `OpenShareSessionDeniedModal`).
- Entry points:
  - The "Share session..."/"Stop sharing"/"Copy session sharing link" block, input and blocklist context-menu items.
  - The "Share session"/"Stop sharing session" pane-header overflow items and "Share session"/"Stop sharing"/"Stop sharing all" tab menu items.
  - The `terminal:share_current_session` and `terminal:stop_sharing_current_session` bindings and palette entries.
  - `CustomAction::ShareCurrentSession` and the "Share Session" item in the Drive menu.
  - `TerminalAction::{OpenShareSessionModal, StopSharingCurrentSession, MakeAllParticipantsReaders, OpenSharedSessionViewerRoleMenu}` and `WorkspaceAction::{OpenShareSessionModal, StopSharingSessionFromTabMenu, StopSharingAllSessionsInTab, OpenSharedSessionQrCode}`.
  - The `/remote-control` slash command, the `/remote-control` and "Stop sharing" footer chips of the agent and CLI-agent toolbars, and their `Start/StopRemoteControl` events.
- Indicators: the tab bar "shared" indicator (`Indicator::Shared`), the pane-header participant avatars and the "Sharing started / Remote control active" banner variants.
- `PaneGroup` sharer state: the share-session modal, the role-change modal, `number_of_shared_sessions`, `shared_session_view_ids`, `is_terminal_pane_being_shared`, `CloseSharedSessionPaneRequested`, and the transitive child-agent share tracking (`inherit_share_for_local_child`, `host_terminal_shared_session_source_type`, `transitively_shared_child_panes`).
- `session_management::num_shared_sessions` and the shared-session lines of the quit warning (`UnsavedStateSummary::shared_sessions`) and the log-out warning.
- The close-shared-session confirmation dialog (`workspace/close_session_confirmation_dialog.rs`, `OpenDialogSource`) and its settings widget (`ConfirmCloseSharedSessionWidget`), plus the settings `ShouldConfirmCloseSession` (`general.should_confirm_close_session`) and `ShouldConfirmSharedSessionEditAccess`.
- `ContextFlag::CreateSharedSession`.
- The shared-session `Manager`'s sharer half (`started_share`, `stopped_share`, `share_failed`, `stop_all_shared_sessions`, `shared_view_by_*`, and the `ShareAttempted`/`StartedShare`/`StoppedShare`/`FailedToShare` events).
- Tests for all of the above.

**Modified:**
- `terminal/shared_session/manager.rs` now tracks only joined (viewed) sessions. Log-out clears joined sessions, and a user change still rejoins them.
- `terminal/view/shared_session/adapter.rs` is viewer-only (the `Kind` enum is gone); `viewer.rs` loses the role-request menu, so a viewer asks for edit access only through the "Request edit access" button.
- The pane header shows the plain sharing icon for a viewed session instead of the sharer's avatar.
- The sharing dialog (`drive/sharing/dialog`) no longer subscribes to `SessionPermissionsManager`; the viewer terminal manager stops forwarding guest and ACL updates to it.
- `SharedSessionScrollbackType::first_block_index` became `shared_session::first_scrollback_block_index`, used for the viewer's banner placement.
- Agent and CLI toolbar layouts: `AgentToolbarItemKind::ShareSession` is no longer offered or rendered. The variant stays only so saved layouts that contain it still deserialize (a `Vec` with an unknown item fails as a whole, which would reset the user's layout and block writes to it), and it is dropped when a custom layout is read.
- AI-side share entry points, as minimal compile fixes:
  - The agent SDK driver no longer shares its terminal: `should_share`, `--share` guest requests, `wait_for_session_shared`, share-retention extension on setup failure, `ShareSessionError`/`ShareSessionFailed`, the "Sharing session at:" output, the `SharedSessionEstablishment` setup step and the viewer-input idle refresh are gone.
  - `BlocklistAIController` no longer forwards response events or synthetic cancellations to viewers.
  - Child-agent panes (`pane_group/child_agent`, `terminal_pane.rs`) no longer inherit the host's share.
  - The docker sandbox stops passing `IsSharedSessionCreator`.
- `workspace/sync_inputs.rs` (synchronized input across panes) was checked and is independent of session sharing. It is unchanged.

**User-visible impact:** Warp can no longer share a session. Every "Share session", "Stop sharing" and `/remote-control` entry is gone from menus, the command palette, keybindings, the tab bar and the agent footers, as are the sharing tab indicator and the "Confirm before closing shared session" setting. Closing a tab or quitting no longer mentions shared sessions. Viewing a session someone else shares still works for now (SS-2 removes it); viewers lose the participant avatars, the role menu and the right-click "Copy session sharing link" item, while "Copy link" remains in the pane-header menu.

**Notes:**
- Left for SS-2 (viewer, model and protocol): the viewer code in `terminal/shared_session/viewer/` and `terminal/view/shared_session/`, `UriHost::{SharedSession, Session}`, `WebIntent::SessionView`, the remaining shared-session state in `TerminalModel`, `input.rs`, `pane_group`, `block_list_element`, `alt_screen` and `local_tty`, `SharedSessionSource` and `SharedSessionStatus`, `PresenceManager` (including the sharer constructor its tests use), `CommandExecutionSource::SharedSession`, and the `session-sharing-protocol` dependency. `session_sharing_protocol::sharer::SessionSourceType` is still imported by that viewer and model code and by `server/telemetry/events.rs`, so `rg 'sharer::' app/src` still matches those protocol imports.
- The viewer's URI entry points are still reachable, so they stay for SS-2.
- Left for the AI tasks, as dead code: `BaseUserQuery::{decode_b64, for_viewer, unattributed}` (viewer prompts accepted by the sharer), `PendingCliHarnessPromptQueue::queue` (its only producer was the sharer), `IdleTimeoutSender::refresh` and `DebugWindowController::refresh_from_last_armed` in the agent SDK driver, `AIClient::setup_failure_debug_authorization` (the sharer's check of a viewer's debug prompt), and `BlocklistAIController`'s `sharer_participant_id`.
- Left for FLAGS-1: the `CreatingSharedSessions` and `HOARemoteControl` feature flags and the `creating_shared_sessions`/`hoa_remote_control` Cargo features. `server/experiments` and the team tier policy still set `CreatingSharedSessions`, but nothing reads it.
- Left for TEL-4: the sharing telemetry variants in `server/telemetry/events.rs`.

## Settings cloud sync
**Why:** Settings sync uploaded cloud-synced settings to Warp's server as Warp Drive `Preference` objects and applied values written by other devices. It needs a Warp account and Warp's servers, and neither exists in the offline build.
- `app/src/settings/cloud_preferences_syncer.rs`: the `CloudPreferencesSyncer` singleton, covering local/cloud reconciliation, the startup settings-file hash check, the retry loop and duplicate-preference cleanup. Its tests went with it, including the flaky `test_sync_local_pref_to_cloud_on_initial_sync_for_returning_user`. `server/cloud_objects/fake_object_client.rs` was also deleted; only those tests used it.
- The `CloudPreferencesSettings` group and its `IsSettingsSyncEnabled` setting (`account.is_settings_sync_enabled`).
- Settings UI:
  - The "Settings sync" switch on the Account page, with its docs link and the "settings sync" search term.
  - The `ToggleSettingsSync` action, command-palette toggle, `settings_sync` context flag, login gate and telemetry event.
  - The "not synced to your other devices" local-only icon: `LocalOnlyIconState`, `render_local_only_icon`, `UiBuilder::local_only_icon_with_tooltip`, `cloud-off.svg` and the per-page tooltip mouse-state maps. The settings render helpers (`render_body_item*`, `render_sub_header`, `render_sub_sub_header`, `render_dropdown_item*`, `render_ai_setting_toggle`/`_label`) lost that parameter.
- `crates/settings`:
  - The `SettingsManager` cloud APIs: `clear_cloud_settings_local_state`, `all_storage_keys`, `sync_regardless_of_users_syncing_setting`, `is_current_value_syncable`, `cloud_syncing_mode_for_storage_key`, `supported_platforms_for_storage_key`, `is_private_for_storage_key`, `read_local_setting_value` and `are_equal_settings`.
  - The clear and syncability callbacks, `SettingsEvent::LocalPreferencesUpdated` and the `from_cloud_sync` flag of `update_setting_with_storage_key`.
  - `Setting::{set_value_from_cloud_sync, current_value_is_syncable, is_setting_syncable_on_current_platform}` and `SettingsMode::should_sync_to_cloud`.
- `AppExecutionMode::can_sync_preferences` in `warp_core`.
- Filters that only decided what to upload:
  - Custom-theme path portability: `Theme`/`SystemThemes::current_value_is_syncable`, `ThemeKind::is_custom_theme_reference_syncable` and `custom_theme_path_is_portable`.
  - `TomlBackedUserPreferences::file_content_hash`, together with the `sha2` dependency of `warpui_extras`.
- Code that waited for or fed the syncer:
  - `RootView::handle_cloud_preferences_syncer_event` and the `AuthManager` user-fetch hook.
  - `PrivacySettings::maybe_sync_with_warp_drive_prefs`.
  - The logout step that cleared cloud-synced settings from user defaults.
  - `UpdateManagerEvent::CloudPreferencesUpdated` and `CloudModel::get_all_cloud_preferences_by_storage_key`.
- The `CLOUD_PREFERENCES_*` experiment values in `crates/graphql` and the schema.
- `app/src/cloud_object/preference.rs`, moved from `settings/cloud_preferences.rs`: keeps the `StringModel`/`JsonModel` impls of the `Preference` Drive object type, which the cloud-object layer still loads until DRV-5. `QueueItem::UpdateCloudPreferences` is renamed `UpdatePreference`.
- Window backdrop: the legacy `appearance.window.override_blur_texture` → `backdrop = acrylic` migration used to be staged until the cloud load finished. It now runs once during settings init.
- Code that waited for the first cloud load now runs without it:
  - Post-login onboarding settings are applied as soon as login completes.
  - One-time modal checks for existing users run on auth completion.
  - Legacy custom endpoints are migrated at startup.
  - The execution-profile migration neither waits for nor uploads through the syncer.
  - None of these login paths can complete offline.
- `PrivacySettings`: after a server settings fetch, the default secret-redaction regexes are initialized directly. They used to be initialized after the Warp Drive preferences loaded.
- `integration_testing::notebook::assert_cloud_preference_exists` now takes a storage key and a value, and the `crates/integration` session-restoration test uses it.
- Comments that described settings cloud sync were rewritten or removed.
**User-visible impact:**
- Settings are local only. The TOML settings file, user defaults and the settings UI work as before.
- There is no "Settings sync" switch on the Account page or in the command palette, and no "not synced" icons next to settings.
- A saved `account.is_settings_sync_enabled` value is ignored.
- The `SyncToCloud`/`RespectUserSyncSetting` attributes and `Setting::sync_to_cloud()` stay for SYNC-1, as do the comments on setting definitions that explain each setting's sync choice. The runtime no longer reads the attribute: `SettingsManager` doesn't store it.
- `WarpDrivePrivacySettings` stays. It stores the telemetry and cloud-conversation-storage toggles, which are not about settings sync.
- `ChangeEventReason::CloudSync` stays. Team-driven enterprise secret redaction uses it (TEAM-1).
- Left for DRV-5: the `Preference` cloud-object type. That covers `cloud_object_models`, `JsonObjectType::Preference`, its sync-queue and update-manager handling, and persisted rows.
- With the syncer gone, nothing in the GUI build calls `UpdateManager::bulk_create_generic_string_objects` or constructs `GenericStringObjectInput`, so `cargo check --bin warp-oss --features gui` reports 2 dead-code warnings for them. DRV-5 deletes both.
- Data left on disk: the private preference `SettingsFileLastSyncedHash` and any `Preference` rows in SQLite (DB-1).
- Logged-out users never get the default secret-redaction regexes. This predates the change: they were only ever initialized after a login. AUTH-1 may want to run `initialize_default_regexes_once` at startup.
- The login slide still says "sync settings across devices" (AUTH-1).

## Workspace LSP metadata moved out of the AI module
**Why:** `PersistedWorkspace` holds the list of known repos and which language servers are enabled for each one (`LspTask`, `enable_lsp_server_for_path`, the `workspace_language_server` rows). The code editor, code review, the repo pickers and the settings page depend on it, and the LSP stays in the offline build. It lived under `app/src/ai/`, which is being deleted.

**Removed:**
- `app/src/ai/persisted_workspace_tests.rs` — an empty file that no module included.

**Modified:**
- `app/src/ai/persisted_workspace.rs` moved to `app/src/workspace_metadata/mod.rs`, unchanged. Every `crate::ai::persisted_workspace` import now points at `crate::workspace_metadata`.

**User-visible impact:** None.

**Notes:** The codebase-indexing and project-rules parts of the model are removed in the next section.

## Codebase indexing and project rules
**Why:** Codebase indexing built a Merkle tree of each repository, uploaded node hashes and code fragments to Warp's servers to compute embeddings, and queried the server for relevant fragments when the built-in agent searched a codebase. Project rules read `AGENTS.md`/`WARP.md` files (and the global `~/.agents/AGENTS.md`) only to attach them to built-in agent requests, and `/init` combined both with an AI request that generated a rules file. All of it is built-in AI that talks to Warp, which the offline fork removes.

**Removed:**
- `crates/ai/src/index/full_source_code_embedding/` — `CodebaseIndexManager`, the Merkle tree, chunkers, sync and store clients, snapshot persistence (including the daemon-only `new_with_snapshot_storage`, `defer_persisted_index_restore` and `SnapshotStorage::from_dir`), `.warpindexingignore` handling and `DEFAULT_SYNC_REQUESTS_PER_MIN`. Also the embedding and Merkle-tree events in `crates/ai/src/telemetry.rs`, `CodeContextLocation::Fragment` / `FileFragmentLocation`, and the dependencies only indexing used (`arborium`, `async-fs`, `async-trait`, `base16ct`, `bincode`, `code_outline`, `dunce`, `generic-array`, `ignore`, `languages`, `line-span`, `nix`, `notify-debouncer-full`, `persistence`, `priority-queue`, `rayon`, `repo_metadata`, `string-offset`, `tokio`, `watcher`, dev-deps `filetime`, `virtual-fs`).
- `crates/ai/src/project_context/` — `ProjectContextModel` and global-rules discovery. The project-rules half of `repo_metadata`'s standing queries (`project_rules()`, `upserted_project_rules`, `RepoDetectionSource::ProjectRulesIndexing`).
- App modules: `ai/codebase_auto_indexing.rs`, `ai/metadata_project_rules.rs`, `ai/blocklist/codebase_index_speedbump_banner.rs`, `terminal/view/init_project/` (the `/init` flow and its LSP server selector), `terminal/view/inline_banner/agent_mode_setup.rs` (the "Optimize Warp for this codebase?" banner that launched `/init`), `ai/blocklist/block/toggleable_items.rs` (used only by that selector), `integration_testing/codebase_context/` and `settings_view/code_indexing_page.rs`.
- Singletons `CodebaseIndexManager`, `ProjectContextModel` and `SyncQueue<SyncTask>`, from `lib.rs` and the test setup helpers. `LaunchMode::supports_indexing`, `RepoOutlines::new_with_indexing_enabled`.
- Entry points: the `/init`, `/index` and `/open-project-rules` slash commands and `Availability::CODEBASE_CONTEXT`; `TerminalAction::{GenerateCodebaseIndex, WriteCodebaseIndex, InitProject, IndexProjectSpeedbump, OpenProjectRulesPane, CodebaseIndexSpeedbumpBanner, AgentModeSetupSpeedbumpBanner}` with the `terminal:generate_codebase_index`, `workspace:write_codebase_index` and `workspace:init_project_rules` bindings; `InputEvent::OpenProjectRulesPane`, `SettingsViewEvent::OpenProjectRulesPane`, `CodeSource::ProjectRules`; code review's "Initialize codebase" button and "Repo is initialized with …" note; the agent view's `/init` callout and `AgentViewEntryOrigin::SlashInit`; the pending-repo-init hook that ran `/init` after opening a repo.
- Agent plumbing that only served these features: `SlashCommandRequest::InitProjectRules`, `AIAgentInput::InitProjectRules`, `BlocklistAIActionEvent::InitProject`, project-rules and codebase context in agent requests, the full-source-embedding path in `get_relevant_files` (outline-based search stays), codebase indexing during cloud-environment preparation in `ai/agent_sdk` (`SetupStep::EnvironmentCodebaseIndexing`), the `/init` and project-rules agent tips, and the file-backed and project-rules lists in the Rules pane.
- Server client: `AIClient::{update_merkle_tree, generate_code_embeddings}` and the `StoreClient` implementation for `ServerApi`; `AIRequestUsageModel::codebase_context_limits`.
- Settings: `CodebaseContextEnabled` (`code.indexing.agent_mode_codebase_context`), `AutoIndexingEnabled` (`code.indexing.agent_mode_codebase_context_auto_indexing`), the private `CodebaseIndexSpeedbumpBannerDismissedForRepoPaths`, `CodebaseIndexSpeedbumpBannerGloballyDismissed` and `AgentModeSetupBannerShownForRepoPaths`; the codebase indexing and auto-indexing toggles, their keymap flags (`IsCodebaseIndexingEnabled`, `IsAutoIndexingEnabled`) and command-palette toggles; the "Codebase Context" toggle on the Agent profiles page. `UserWorkspaces::{is_codebase_context_enabled, teams_allow_codebase_context, team_disabling_codebase_context}` and `UserWorkspacesEvent::CodebaseContextEnablementChanged`.
- Persistence: `ModelEvent::{DeleteCodebaseIndexMetadata, UpsertProjectRules, DeleteProjectRules}` and the `project_rules` table reads and writes (`PersistedData::project_rules`, `model::{ProjectRules, NewProjectRules}`). The schema is untouched.
- LSP telemetry that only `/init` sent: `LspTelemetryEvent::{ServerEnablementSkipped, ServerInstallCompleted}`, `LspEnablementSource::InitFlow`.

**Modified:**
- `ai::workspace::WorkspaceMetadata` moved to `app/src/workspace_metadata/metadata.rs`; the index-only `WorkspaceMetadataEvent` and `is_expired` went. `PersistedWorkspace` keeps the list of known repos and per-repo language-server state and no longer listens to index, rules, AI-history or team events. `ModelEvent::UpsertCodebaseIndexMetadata` is now `UpsertWorkspaceMetadata`, and `PersistedData::codebase_indices` is `workspace_metadata`; both still use the `workspace_metadata` table, so known repos and enabled language servers survive.
- Settings > Code > "Indexing and projects" is now **Projects** (`settings_view/projects_page.rs`, `SettingsSection::Projects`, a monolith page): every known repo with its enabled, disabled and suggested language servers, with enable/disable, install, restart and view-logs actions. The session-restore slug stays "Indexing and projects"; `from_slug` also accepts "Projects".
- `RepoOutlines` (the `@`-menu code symbols) is gated only by `outline_codebase_symbols_for_at_context_menu`; it no longer reacts to the AI or codebase-context settings. `all_working_directories` moved into `code/outline/native.rs`. `code_outline::THREADPOOL` is private and its threads are named `warp-code-outline-*`.
- The environment-creation modal and the directory tab-color picker list known repos from `PersistedWorkspace` instead of indexed repos. Repo pickers say "repos" instead of "indexed repos".
- `AITip::is_tip_applicable`, `AITipModel::maybe_refresh_tip` and `BlocklistAIContextModel::pending_context` lost the working-directory parameters that only the removed tips and rules needed; `GetRelevantFilesController` has no constructor subscription.

**User-visible impact:** Warp never indexes, uploads or syncs code. `/init`, `/index` and `/open-project-rules` are gone, as are the indexing banners, the "Initialize codebase" button and the codebase indexing toggles. Settings > Code > Projects shows each known repository's language servers. `AGENTS.md`/`WARP.md` files are ordinary files to Warp; third-party CLI agents still read them. Stored values for the removed settings are ignored.

**Notes:**
- Left for FLAGS-1: `FeatureFlag::{FullSourceCodeEmbedding, CodebaseIndexPersistence, CodebaseIndexSpeedbump, RemoteCodebaseIndexing, CrossRepoContext}` and their Cargo features; all gated code is gone.
- Left for SRV-1 (`crates/graphql` owner): the now-unused `full_source_code_embedding` types and the `generate_code_embeddings`, `populate_merkle_tree_cache`, `update_merkle_tree`, `codebase_context_config`, `get_relevant_fragments`, `rerank_fragments` and `sync_merkle_tree` operations, plus the team `codebase_context` settings fields. Left for DB-1: the `project_rules` table. `workspace_metadata.queried_ts` is still read and written back so existing ordering is kept.
- Left for TEL-4: telemetry variants whose callers are gone (`ToggleCodebaseContext`, `ToggleAutoIndexing`, `FullEmbedCodebaseContextSearch*`, `AgentModeSetupBanner*`, the init-flow action types, the `SlashInit` entry origin).
- Left for AI-23: the onboarding callout's "Initialize" end state still submits `/init` as an agent query, and two onboarding TODO comments mention `/init`. Left for AI-28/AI-29: the agent's `InitProject` tool completes without doing anything; `AIAgentContext::ProjectRules` conversions; `EntrypointType::InitProjectRules` in `ai_types` (serialized). Left for AI-15: the Rules pane, which now lists only Drive rules.
- `repo_metadata::BudgetExceededBehavior::FailFast` is only exercised by its own tests now. `InputSuggestionsMode::IndexedReposMenu` / `InlineMenuType::IndexedReposMenu` keep their identifiers to avoid churn in `terminal/input.rs`.
- A restored code pane that was opened on a project-rules file reopens its tabs without its old source (the saved `CodeSource` no longer parses and falls back to `None`).

## TUI rendering layer and TUI modes in the core crates
**Why:** The Warp TUI front-end (`crates/warp_tui`) was removed earlier (see [Warp TUI front-end](#warp-tui-front-end)). What it left behind in the shared crates was a second rendering backend and a set of "TUI surface" switches that nothing selects any more. Keeping them means carrying a terminal-UI toolkit, a second layout engine in the editor and dead mode branches in the settings, logging and MCP code.

**Removed:**
- `crates/warpui_core`:
  - the `tui` Cargo feature and the `ratatui` dependency (with `libc` and `unicode-segmentation`, which only the TUI code used);
  - `src/elements/tui/` (the `TuiElement` library: text, flex, stack, scrollable, selectable, viewported list, shimmering text, buffers and events), `src/presenter/tui.rs`, `src/runtime/` (the crossterm-driven TUI event loop, renderer and terminal color probe), `src/core/app/tui.rs`, `src/core/view/tui.rs`, `src/core/view/context/tui.rs` and their tests;
  - the `tui_integration` test and the `tui_file_viewer` example;
  - `StoredView`, the enum that let GUI and TUI views share a window's view registry; windows store `Box<dyn AnyView>` directly again;
  - TUI-only helpers: `elements::animation` (`AnimationClock`, `KeyframeTimeline`), `text::TuiGridPoint`, `text::byte_offset_for_char_offset`, `Keystroke::displayed_expanded`, `MouseState::set_click_count`, and the TUI keymap-validation regression tests in `keymap/matcher_tests.rs`.
- `crates/warp_terminal`: the `tui` feature, `KeystrokeWithDetails::to_pty_bytes` (single-event key encoding for the crossterm front-end) and `tmux_passthrough` (used to emit OSC 777 from the TUI).
- `crates/warpui`: `platform::create_system_clipboard`, the windowless clipboard constructor the TUI used.
- `crates/editor` (`warp_editor`): the char-cell layout mode. That covers `RenderState::new_tui` and `char_cell()`, `LayoutMode`, `CharCellState`, `CharCellTextIndex`, `CharCellTemporaryBlock`, `render/model/char_cell_display.rs` (`DisplayLattice`, `DisplayRow`, `DisplayRowKind`), the `char_cell_*` wrapping helpers, `SelectionModel::has_pending_selection`, the `char_cell_bench` benchmark and their tests. `ColumnUnit` is gone as well: `SoftWrapPoint` columns and `SelectionModel::goal_xs` are plain `Pixels` again. The `unicode-linebreak`, `unicode-segmentation` and `unicode-width` dependencies went with it, and `unicode-linebreak` left `[workspace.dependencies]`.
- `crates/settings`: `SettingsMode::Tui`, the process-wide settings mode (`set_settings_mode`, `settings_mode()`) and `SettingsMode::should_migrate_native_settings`.
- `crates/warp_logging`: `LogFrontend::Tui` and its `warp-cli` log subdirectory.
- `crates/warp_core`: `ExecutionMode::Tui` (client id `warp-tui`), `AppExecutionMode::is_tui`, and the TUI paths `tui_config_local_dir`, `tui_mcp_config_file_path` and `tui_state_dir`.
- App branches that only ran for the TUI surface:
  - `settings/mod.rs::user_preferences_toml_file_path` always uses the GUI config directory;
  - `settings/init.rs` no longer asks the settings mode before the one-time native-store migration;
  - `warp_managed_paths_watcher.rs` no longer creates or watches the TUI config directory, and `active_mcp_config_file_path` is gone (the GUI MCP file is watched directly);
  - `ai/mcp/file_based_manager.rs` loses the deferred global-server autostart (`defer_global_warp_autostart`, `global_warp_servers_activated`, `activate_global_warp_servers`) and its two tests;
  - `ai/mcp/templatable_manager/native.rs` loses the loopback OAuth callback (`use_tui_loopback`), so MCP OAuth always uses the `warposs://mcp/oauth2callback` scheme;
  - `ai/mcp/file_mcp_watcher.rs::should_watch_repository` no longer takes a settings mode.

**Modified:**
- `settings/schema_generation.rs` — `x-warp-surfaces` lists only `gui`.
- `app/examples/generate_default_settings.rs` — dropped the required `--surface gui|tui` argument; it always writes the GUI settings file.
- Slash-command tests (`search/slash_command_menu/static_commands/commands_tests.rs`, `terminal/input/slash_commands/mod_tests.rs`) — dropped the assertions and tests that listed TUI-mode commands; the GUI assertions stay.
- `crates/warp_logging` tests — the frontend-directory, bundle and crash-recovery tests use the CLI frontend instead of the TUI one.
- Doc comments in `warpui_core` (`core/app.rs`, `core/view/context.rs`, `elements/shimmer_math.rs`, `elements/gui/hoverable.rs`) and `warpui` (`platform/app.rs`) no longer describe a TUI backend.

**User-visible impact:** None in the GUI. MCP servers that need OAuth always use the app's URL-scheme callback, which is what the GUI already did.

**Notes:**
- `SettingsMode` keeps a single `Gui` variant. It is still the parameter type of `SettingSurfaces::includes` and `SlashCommandSurfaces::includes`. AI-33 removes `SettingSurfaces` (with `SettingSurfaces::TUI` and the `surface:` annotation) and can drop `SettingsMode` with it. AI-24 removes the TUI-only static slash commands (now unreachable, since no surface selects them) and `SlashCommandSurfaces::{TuiOnly, GuiAndTui}`.
- `OAuthCallbackMode::Loopback` in `crates/mcp` has no production caller now; AI-14 deletes the MCP crate.
- Left in place: `CLIAgentNotification::new` in `warp_core::cli_agent_protocol` (only the removed TUI built notifications; the GUI only parses them), the `warp`/`warp-tui` note in `crates/input_classifier/src/util.rs` (AI plan) and the TUI comments in `crates/ai` (AI plan). The `tui_version`/`tui_updates` fields in `crates/channel_versions` are for SRV-1.
- The GUI-facing generalizations the TUI work introduced in `warpui_core` (for example `T: Entity` bounds on view APIs and `AppContext::weak_app`, which a `warpui` test uses) are kept.
- Existing `warp-cli` log directories, `.warp_cli*` config directories and `tui/` state directories on users' machines are left untouched.

## Changelog
**Why:** The changelog came from Warp's release-channel feed (`channel_versions.json` on Warp's servers). The autoupdater removal already stopped fetching it (see [Autoupdater and release-channel update checks](#autoupdater-and-release-channel-update-checks)), which left `ChangelogModel` always answering "no changelog" and every changelog entry point opening an empty panel.

**Removed:**
- `app/src/changelog_model.rs` — the `ChangelogModel` singleton (and its unused `server_api` field), `check_for_changelog`, `ChangelogHeader`, `ChangelogRequestType` and its events. Its registration is gone from `lib.rs` and the test setup helpers (`test_util/terminal.rs`, `pane_group/mod_tests.rs`, `terminal/input_tests.rs`, `workspace/view_tests.rs`).
- `app/src/resource_center/section_views/changelog_section.rs` (`ChangelogSectionView`), `Section::Changelog`, `SectionViewHandle::Changelog`, `ChangelogSectionData` and `FeatureSection::WhatsNew`.
- `app/src/settings/changelog.rs` — `ChangelogSettings` / `ShowChangelogAfterUpdate` (`general.show_changelog_after_update`), plus `ShowChangelogWidget` and `FeaturesPageAction::ToggleShowChangelogAfterUpdate` on the Features settings page.
- `Settings::{has_changelog_been_shown, mark_changelog_shown}` and the `ChangelogVersions` private user-preference key.
- Workspace entry points: `WorkspaceAction::ViewLatestChangelog`, the "View latest changelog" command-palette bindings (`workspace:view_changelog`), `CustomAction::ViewChangelog` and its app-menu item and default shortcut, the "What's new" item in the user menu, the launch-time changelog check in `root_view.rs`, and `Workspace::{check_for_changelog, view_latest_changelog, handle_changelog_event}`.
- The workspace "update toast" stack (`update_toast_stack`, the `UpdateToastVisible` keymap context and the chip positioning next to the feature-intro popover). After the autoupdater removal the changelog toast was the only thing it showed. The unused `OPENING_WARP_DRIVE_ON_START_UP` flag, read only by the changelog check, is gone too.
- `is_changelog_modal_open` in `workspace/util.rs`, which nothing ever set.
- The `/changelog` slash command (`SlashCommandKind::Changelog`, `CHANGELOG`) and its handler, plus `test_changelog_slash_command_clears_buffer_on_success`.
- AI zero state (`ai/blocklist/agent_view/zero_state_block.rs`), a minimal compile fix: the "Latest updates" section that listed Warp Agent entries from `ChangelogModel` (with its "View changelog" link to `docs.warp.dev/changelog`), `AgentViewZeroStateAction::ToggleOzUpdates` and the `should_render_oz_updates_section` tests.

**Modified:**
- `resource_center/main_page.rs` — "Getting Started" and "Maximize Warp" expand based only on welcome-tip progress. Before, both stayed collapsed until the current version's changelog had been shown, which no longer happens. `FeatureSectionView` loses its `show_tips_progress` flag, which was only false for the changelog section.
- `resource_center/sections.rs` — the section list starts empty. With `AvatarInTabBar` (on by default) it now has no sections at all.
- `resource_center/mod.rs` — `TipAction::Changelog` stays, marked as not shown, because saved welcome-tip progress (`welcome_tips_features_used`) may contain it and must still deserialize.

**User-visible impact:** There is no changelog anywhere: no "What's new" menu item, no "View latest changelog" command or shortcut, no `/changelog`, no post-update toast and no "Show changelog toast after updates" setting (`general.show_changelog_after_update` is ignored if present). The resource center's main page no longer has a "What's New?" section. With the default `AvatarInTabBar` layout it now shows only its footer and the keyboard-shortcuts button, and the keybindings page is unchanged. The agent zero state no longer shows "Latest updates".

**Notes:**
- `crates/channel_versions` is still used: `app/src/ai/block_context.rs` imports `channel_versions::overrides::TargetOS`. It also still defines `Changelog`, `oz_updates` and `tui_version`/`tui_updates`. Left for SRV-1.
- `FeatureFlag::{Changelog, OzChangelogUpdates}` and their Cargo features stay for FLAGS-1. `TelemetryEvent::OpenChangelogLink` is no longer emitted; TEL-4 deletes it.
- Left for the AI settings removal: `ShouldShowOzUpdatesInZeroState` / `ShouldExpandOzUpdates` in `settings/ai.rs`, the "Show Warp Agent changelog" toggle in `settings_view/warp_agent_page.rs` and the `SHOW_OZ_UPDATES_IN_ZERO_STATE_FLAG` keymap flag. They no longer control anything.
- Left for LINKS-1: the resource center's Docs/Slack/Feedback footer and the warp.dev links in the "Advanced Setup" content section (shown only when `AvatarInTabBar` is off). With the changelog gone, the default main page has no content of its own, so LINKS-1 may reduce the resource center to the keybindings page.
- Existing `ChangelogVersions` entries in users' preferences are left in place and never read.

## Docker sandbox sessions and local child-agent harnesses
**Why:** Docker sandbox sessions were built on the agent SDK: opening one ran `sbx` to start a container, prepared an Oz cloud-agent environment inside it and reported an environment snapshot to Oz. Local third-party child harnesses (Claude Code or Codex children started by an Oz orchestrator) were launched through the agent SDK's harness driver. Both go with the Oz CLI and agent SDK, which have no place in an offline fork (ai.md decision D8, master decision 9).

**Removed:**
- `app/src/terminal/view/docker_sandbox/`, `app/src/terminal/local_tty/docker_sandbox.rs`, `crates/warp_terminal/src/local_tty/docker_sandbox.rs` — sandbox tab creation, `sbx` path resolution, in-container environment setup and the sandbox shell starter.
- The sandbox shell type: `ShellLaunchData::DockerSandbox`, `ShellStarter::DockerSandbox`, `SessionPlatform::DockerSandbox`, `AvailableShell`'s `Config::DockerSandbox`, the `sbx run` PTY spawn path in `crates/warp_terminal/src/local_tty/unix.rs` (with its test), the Windows rejection arm and `PtySpawnError::UnsupportedShellStarter`, and `bootstrap::raw_init_shell_script_for_shell`, which only the sandbox used.
- Entry points: `DefaultSessionMode::DockerSandbox`, the "Local Docker Sandbox" new-session menu item and its sidecar, `WorkspaceAction::AddDockerSandboxTab`, the `/docker-sandbox` slash command (`SlashCommandKind::CreateDockerSandbox`, `InputEvent::CreateDockerSandbox`) and its test.
- `app/src/pane_group/pane/local_harness_launch.rs` and its tests — prepared and ran hidden local Claude Code/Codex child agents through the agent SDK harness driver.
- `CliAgentPluginManager::has_local_marketplace_override` and the Claude/Codex marketplace-override detection (with tests), which only that launcher used.

**Modified:**
- `pane_group/pane/terminal_pane.rs` — a StartAgent request for a local third-party harness now ends in an error child conversation ("Local child agents do not support third-party harnesses.") instead of launching.
- `terminal/model/session/command_executor.rs`, `terminal/writeable_pty/pty_controller.rs`, `terminal/local_shell/mod.rs`, `terminal/local_tty/terminal_manager.rs`, `shell_indicator.rs`, `integration_testing/terminal/util.rs`, `ai/blocklist/agent_view/agent_input_footer/mod.rs`, `settings_view/features_page.rs`, `workspace/view.rs` — dropped their sandbox arms and comments.

**User-visible impact:** No Docker sandbox tabs, no `/docker-sandbox` command and no "Local Docker Sandbox" default session mode. A stored `general.default_session_mode = "docker_sandbox"` no longer parses, so the default (Terminal) applies. A restored pane that was a sandbox session reopens with the default shell, because its persisted launch data no longer parses.

**Notes:**
- `FeatureFlag::LocalDockerSandbox` stays for FLAGS-1. `Icon::Docker` and `docker.svg` stay because the cloud-environment UI still uses them (AI-18).
- `crates/isolation_platform` still has a `docker_sandbox` isolation type (workload tokens for cloud agents running inside a sandbox); AI-18 deletes that crate.
- Deferred to AI-19: `ai/local_harness_setup.rs`. It is the orchestration picker's policy for which local harnesses are selectable, and its only users are `ai/orchestration/` and the RunAgents executor, which AI-19 deletes.
- Deferred to the tasks that delete their last users (AI-17a, AI-19, AI-21, AI-24, AI-27): `ai/harness_availability.rs` (the server-fetched list of cloud harnesses, their models and auth secrets) and `ai/harness_display.rs` (harness names, icons and colors). Their consumers are the ambient-agent harness/model/auth-secret selectors, orchestration config, agent management, the conversation details panel, the agent footer and the profile/model selector.

## Oz CLI and agent SDK
**Why:** The `oz` command-line interface ("the orchestration platform for cloud agents") and the agent SDK that implemented it existed only to run, schedule and manage Warp cloud agents against Warp servers: `oz agent run`, environments, schedules, managed secrets, MCP and memory stores, artifacts, runners, federated identity tokens and API-key login. None of it can work in an offline build, and the SDK was the only consumer of a large part of the Oz server surface (ai.md decision D15, master decision 9).

**Removed:**
- `app/src/ai/agent_sdk/` (109 files) — the headless agent driver (`oz agent run`), its harness drivers for Claude Code/Codex/Gemini/OpenCode, transcripts, workspace snapshots and checkpoints, environment preparation, git and Bedrock credential refresh, MCP startup, artifact upload, output formatting, and every Oz subcommand handler.
- `crates/warp_cli`: the Oz subcommand modules (`agent`, `api_key`, `artifact`, `config_file`, `environment`, `federate`, `harness_support`, `integration`, `mcp`, `memory_store`, `model`, `provider`, `runner`, `schedule`, `scope`, `secret`, `share`, `skill`, `task`, plus `json_filter`, `sort_order`, `date_time`), `CliCommand`, `Command::CommandLine`, `GlobalOptions` (`--api-key`/`WARP_API_KEY`, `--output-format`), `--debug`, the `OZ_*`/`WARP_*` run-id, CLI and harness env-var names, the feature-flag gating of Oz subcommands, and the Oz help text and examples. Its `chrono`, `humantime`, `jaq-all` and `uuid` dependencies went with them.
- `app/src/lib.rs`: `LaunchMode::CommandLine`, the `api_key` launch field and `AuthInitialization` (startup API-key login), `determine_agent_source`, the `oz` binary-name and `WARP_CLI_MODE` checks, the windowless (`is_gui`/`is_headless`) launch path and its macOS background-only activation (`platform/mac.rs`), the `OZ_RUN_ID` ambient-task id and the runner-context IAP identity mint, `ScheduledAgentManager` (only `oz schedule` used it), and the `lib_tests.rs` tests for those paths.
- `ExecutionMode::Sdk`, `AppExecutionMode::is_autonomous` and `is_sandboxed` (they were only true for `oz agent run [--sandboxed]`), the sandboxed-agent command denylist resolver, and the CLI default execution profile (`DefaultProfileState::Cli`, `AIExecutionProfile::create_default_cli_profile`).
- `app/src/server/server_api/{harness_support.rs, harness_usage/}` and their tests — the harness-support and harness-usage clients the SDK used to talk to Oz. `server/server_api/{managed_mcp.rs, download.rs}`, `server/iap_identity_minter.rs` and `server/telemetry/secret_redaction.rs`, whose only callers were in the SDK, and the `AIClient`, integrations, factory and update-manager methods and request/response types that only the SDK called (agents, memory stores, skills, transcripts, git credentials, file artifacts, run events, schedule history, handoff snapshot allocation).
- `WorkspaceAction::{InstallOz, UninstallOz}`, their key bindings and toasts, and the Oz half of `workspace/cli_install.rs`. The `warpctrl` install stays.
- `warp_completer`'s completion signatures for the `oz`, `oz-preview` and `oz-dev` commands and its clap-to-signature converter.
- `UserWorkspaces::team_scope_for_cli[_object]` and `TeamScopeForCli`, which resolved `--team`/`--personal` flags.
- The device-authorization login flow (`AuthManager::authorize_device`, `AuthClient::request_device_code`/`exchange_device_access_token`, the `warp-agent-cli` OAuth client), which only `oz login` used, and `AuthManager::authenticate_api_key`.
- SDK-only helpers in AI modules and their tests: `LocalAgentTaskSyncModel`'s CLI-session registration, idle waiters and confirmed terminal states; the controller's native-prompt binding and `QueuedQueryModel`'s native setup barrier; `OrchestrationEventService` exit-commit handles; `PendingCliHarnessPromptQueue` (the SDK drained it; [Session sharing](#session-sharing-sharer-side-and-entry-points) removed its only producer) and `TerminalView::submit_text_to_cli_agent_pty`; the dormant local-Claude wake event; `--skill` repo resolution (`ai/skills/global_skills.rs`, `clone_repo_for_skill`); CLI-spawned ephemeral MCP servers; and the Oz "platform" plugins (`oz-harness-support`, `orchestration`) in the Claude Code and Codex plugin managers.
- The `docker_sandbox` isolation-platform type in `crates/isolation_platform` (Warp-hosted Docker Sandbox runners).
- `app/Cargo.toml`: `comfy-table`, `inquire`, `jaq-json`, `jaq-all`, `regex-automata`; root `[workspace.dependencies]`: `humantime`, `jaq-json`, `jaq-all`.

**Modified:**
- `crates/ai/src/harness.rs` (new, `ai::harness::Harness`) — the harness enum moved out of `warp_cli::agent` because cloud-agent, orchestration and CLI-agent UI code still uses it; name parsing is now a plain match instead of clap's `ValueEnum`. `crates/ai/src/skills/skill_spec.rs` (new, `ai::skills::SkillSpec`) — moved from `warp_cli::skill` for the skills and orchestration code. `cloud_object_models` no longer depends on `warp_cli`.
- `server/server_api/presigned_upload.rs` now owns `UploadTarget`/`UploadField`/`UploadFieldValue` (moved from `harness_support.rs`); `server_api/ai.rs` now owns the task-scoped public-API helpers it still uses.
- `warp_cli::Args` is now the plain Warp app parser (`name = "warp"`): worker subcommands, `completions`, `--dump-debug-info`, `dump-settings-schema`, URLs to open, and the hidden server-URL overrides. `lib_tests.rs` covers those.
- `run()` launches the GUI directly; a `standalone` build (the `warpctrl` bundle) still prints help instead of starting the GUI. `ServerApiProvider::new` no longer takes an agent source. `AIExecutionProfilesModel::new` and `custom_endpoints::init` no longer take a launch mode.
- Minimal compile fixes in AI code that the SDK fed: the `UploadArtifact` agent action is rejected as invalid (there is no artifact store), handoffs spawn without a workspace snapshot (the snapshot builder lived in the SDK), the dormant local-Claude wake path in `BlocklistAIController` is gone, `conversation_details_panel` no longer offers "continue locally" for third-party cloud runs (the transcript rehydration lived in the SDK), and the ambient-agent view no longer special-cases the harness auth-check command.
- `script/windows/windows-installer.iss` — the `warp-<channel>.cmd` helper no longer sets `WARP_CLI_MODE`.
- `warp_core::channel::ChannelState`'s test-only mock server (`test-util`) is now created on its own thread. The removed OAuth client used to build it on the main thread during `ServerApi` setup; without that, the first URL lookup ran on a background executor inside a tokio runtime, and `mockito::Server::new` panicked there.

**User-visible impact:** There is no `oz` command and no "Install Oz CLI" action. `warp-oss --help` shows only the app's own options and subcommands (`completions`, `dump-settings-schema`, `--dump-debug-info`). `--api-key` and `WARP_API_KEY` are no longer accepted. Invoking the binary through an `oz`-named symlink or with `WARP_CLI_MODE` set now launches the app. Typing `oz` in a Warp terminal no longer gets Warp's own command completions.

**Notes:**
- `FeatureFlag` variants for Oz CLI commands (`ProviderCommand`, `IntegrationCommand`, `ArtifactCommand`, `APIKeyManagement`, `CloudAgentRunners`, `AgentHarness`, …) and the `standalone` Cargo feature stay for FLAGS-1 (AI-32). `warp_cli`'s `integration_tests` feature stays.
- `ExecutionMode::Tui` stays for AI-04. `Channel::cli_command_name()` (`oz`, `warp-oss`, …) stays as the completions fallback name until CFG-1 reduces `Channel`.
- Left for AI-19: `ai/local_harness_setup.rs`, the dormant-Claude wake listener in `orchestration_event_streamer.rs`, the CLI-harness task mapping in `LocalAgentTaskSyncModel` (now only registered by tests). Nothing binds `BlocklistAIController::native_prompt_conversation_id` any more (the SDK did), so it is always `None` and the bound-prompt routing in `controller/startup_queue.rs` and `controller/shared_session.rs` never runs; it goes with the shared-session prompt paths. Left for AI-14: MCP event fields that only the SDK read (`CloudEnvMcpScanComplete`/`InitialGlobalMcpScanComplete` wait sets, `ParsedTemplatableMCPServerResult::variable_values`, `TemplatableMCPServerManagerEvent::StateChanged::state`) and the `is_headless: false` in MCP OAuth. Left for AI-17a: the snapshot-less handoff pipeline. Left for AI-18: `IapManager`'s managed WIF mint (no longer constructed; its comments still cite `oz federate`). Left for AI-10: the `/init` detection of `oz environment create` in `terminal/view.rs`. Left for AI-11: the `warp_cli_binary_name` bundled-skill variable. Left for AUTH-1: `AuthState::initialize_for_credential_validation`, API-key credentials and the rest of the auth stack.
- These dead-code warnings are expected until AI-14 lands: `ai/mcp/{file_based_manager, parsing, templatable_manager}.rs` (unread event and result fields).
- AI code comments that still mention `AgentDriver` (MCP managers, skills, startup-queue tests) go with their modules.

## Cloud-agent OpenTelemetry trace export
**Why:** `app/src/tracing/` installed an OpenTelemetry OTLP exporter when a process was started as a Warp cloud agent (`WARP_CLOUD_AGENT_OTLP_ENDPOINT` plus a dispatch token) and sent the spans tagged `tags.cloud_agent` to Warp's collector, refreshing its credentials through the managed-secrets client. With the Oz CLI and agent SDK gone nothing starts the app that way, and an offline fork sends no traces to Warp (ai.md decision D15, master decisions 1 and 9).

**Removed:**
- `app/src/tracing.rs` and `app/src/tracing/{native.rs, cloud_agent_auth.rs, cloud_agent_auth_tests.rs}`: the OTLP exporter and subscriber, the shutdown-aware tracer and active-span registry, the cloud-agent span filter, the dispatch-token credential refresh and the `Initialization` handle `run_internal` carried to shutdown.
- `app/src/lib.rs`: the `run_internal` span, the exporter warning and shutdown hooks, the `start_auth_refresh` call, `LaunchMode::as_str_for_tracing` and the `tags.cloud_agent` `instrument` attributes on `run`, `initialize_app` and `launch`.
- The other `tags.cloud_agent` spans, which existed only to be exported: `instrument` attributes on `ServerApi` agent-task and workspace-metadata calls, `persistence::initialize` and `ManagedSecretManager::get_task_secrets`, and the `generate_multi_agent_output` stream span in `warp_multi_agent_client` (with its `tracing`/`tracing-futures` deps).
- `http_client`: the `X-Warp-Traceparent` header added to every Warp request when a span context was active, `current_trace_link_header` and its tests.
- Dependencies: `opentelemetry`, `opentelemetry-http`, `opentelemetry-otlp`, `opentelemetry_sdk`, `tracing-opentelemetry` and `tracing-subscriber` from `app`, `http_client` and `[workspace.dependencies]`; `tracing` from `warp_managed_secrets`.

**Modified:**
- `run_internal` installs `tracing`'s no-op subscriber directly, as the removed module did for every non-cloud-agent launch. The workspace enables `tracing`'s `log` feature, which turns spans and events into log lines when no subscriber is set.

**User-visible impact:** None. The exporter only ran in cloud-agent processes.

**Notes:** `crates/build_cache` still has a `tags.cloud_agent` span and `tracing-opentelemetry` field names; the crate is deleted in [Agent build cache and harness usage crates](#agent-build-cache-and-harness-usage-crates). `ManagedSecretManager::get_task_secrets` keeps its inner async function until AI-18 deletes `managed_secrets`.

## Agent build cache and harness usage crates
**Why:** Both crates served only the agent SDK removed in [Oz CLI and agent SDK](#oz-cli-and-agent-sdk). `build_cache` set up persistent build and dependency caches inside sandboxed cloud-agent VMs through Namespace's `spacectl`. `warp_harness_usage` parsed captured Claude Code and Codex histories into usage snapshots that the SDK reported to Oz (ai.md decision D15, master decision 9).

**Removed:**
- `crates/build_cache` (repository and tech-stack discovery, cache planning, `spacectl` cache mounts and the `validate_spacectl` example).
- `crates/warp_harness_usage` (JSONL capture parsing, Claude Code and Codex usage extraction, counters, tool attribution and the usage API types).
- Their `[workspace.dependencies]` entries and `app/Cargo.toml` dependencies.

**User-visible impact:** None.

## Hosted web client ties to app.warp.dev
**Why:** The wasm build is Warp's hosted web client. It is served from `app.warp.dev` and embedded in Warp's web app. Its web-only code did several things that tie it to Warp's web app:
- read and rewrote the `app.warp.dev` address bar;
- sent users to Warp's login and download pages;
- loaded fallback fonts and larger images from Warp's asset server;
- took the signed-in user from the host page, and sent events back to it.

The desktop app also rewrote clicked Warp web links into in-app intents. Offline enterprise use has no web client, so none of this applies.

**Removed:**
- **Web URL intents and address-bar sync:**
  - `app/src/uri/{web_intent_parser, browser_url_handler, browser_url_resolution}.rs`. These parsed `<server root>/{session, conversation, drive, settings, action, app}` URLs into `warposs://` intents and read and wrote the browser address bar.
  - In `lib.rs`: the desktop `set_before_open_url` hook that applied the rewrite to every opened link, the wasm startup intent parsing, and `LaunchMode::add_url`.
  - The tests for all of the above, in `uri_tests.rs` and `terminal/shared_session/mod_tests.rs`.
  - In `pane_group`: `PaneGroup::{update_browser_url, handle_pane_link_updated}`, and the terminal pane's `JoinedSession` subscription with `retrieve_shared_session_link`.
  - `PaneContent::shareable_link` and `ShareableLink`/`ShareableLinkError`, which existed only to fill the address bar. This removed 17 pane implementations.
- **Web viewer chrome:**
  - `app/src/wasm_nux_dialog.rs`, the first-run "open in desktop or stay on web" dialog.
  - `workspace/view/wasm_view.rs`, and the parts of `workspace/view.rs` that used it:
    - the simplified web tab bar (a Warp logo linking to `warp.dev`, "Open in Warp", and "View all cloud runs" pointing at the Oz site);
    - the workspace-level conversation transcript details panel and its mobile overlay;
    - `SimplifiedWasmTabBarContent` and its tests, and the `Workspace_CloudConversationWebViewer` keymap context (the command-palette binding no longer excludes it);
    - `Workspace::{open_link_on_desktop, redirect_to_sign_in}`;
    - `WorkspaceAction::{OpenLinkOnDesktop, ToggleConversationTranscriptDetailsPanel, SignInAnonymousWebUser}`;
    - `WorkspaceState::is_transcript_details_panel_open` and the `warp_logo` mouse state.
- **"Open on Desktop" and "Run in Warp" entry points:**
  - The entry points themselves: the Drive index, notebook and workflow context menus, the workflow footer button, the shared-session pane-header menu, and the "Open in Warp" button on the conversation-ended tombstone.
  - Their actions: `DriveIndexAction::OpenObjectLinkOnDesktop`, `NotebookAction::OpenLinkOnDesktop`, `WorkflowAction::OpenLinkOnDesktop`, `TerminalAction::OpenSharedSessionOnDesktop` and `ConversationEndedTombstoneAction::OpenInWarp`.
  - `AgentManagementTelemetryEvent::TombstoneOpenInWarp`.
- **Web-only settings:**
  - `settings/app_installation_detection.rs` (`UserAppInstallDetectionSettings`, which the host page wrote).
  - `settings/native_preference.rs` (`NativePreferenceSettings`: `general.user_native_preference` and the dialog-dismissed flag).
  - The "Open links in desktop app" toggle (`NativeRedirectWidget`) and `FeaturesPageAction::ToggleOpenLinksInDesktopApp`.
- **Web auth handoff:**
  - `AuthOnboardingState::WebImport` and `auth/web_handoff.rs` (`WebHandoffView`).
  - `RootView::{web_handoff, handle_web_handoff_event}` and `AuthManager::initialize_user_from_session_cookie`.
  - The web branch of anonymous sign-up that navigated the page to Warp's login URL.
- **Host-page events:**
  - The `user_handoff` FFI and the `WarpEvent` re-export in `platform/wasm.rs`.
  - The `LoggedOut`, `SessionJoined`, `ThemeBackgroundChanged` and `ErrorLogged` emit sites, in `auth/mod.rs`, the shared-session viewer, `appearance.rs` and `crates/warp_logging/src/wasm.rs`.
- **Web link-only context modes:**
  - `ContextFlag::{HideOpenOnDesktopButton, DynamicBrowserUrl}`.
  - `ContextFlag::set_{shared_session, conversation, warp_drive_link, settings_link, warp_home_link}_only`, which the web intent parser called.
  - `ContextFlag::set` and its `FromStr`, which only the web URL's query string used.
- `app/src/font_fallback.rs`, which fetched fallback fonts from `{server_root_url}/assets/client/static/fallback-fonts/` on wasm.
- **Remote assets:**
  - `asset_macro::remote_asset!` and the wasm branch of `bundled_or_fetched_asset!`, which fetched from the page origin.
  - `warp_util::assets::{make_absolute_url, hashed_asset_path, hashed_asset_url, REMOTE_ASSETS_DIR}` and `app/assets/remote/`.
  - `copy_async_assets` in `app/build.rs`, which wrote hashed copies for Warp's asset server when `ASSET_TARGET_DIR` was set.
  - The dependencies only these used: `sha2` in `asset_macro` and in the app build script, and `hex` and `gloo` in `warp_util`.

**Modified:**
- `bundled_or_fetched_asset!` is now `async_asset!`. It always bundles from `app/assets/async`. It is used by the default themes and four modals.
  - The wasm `exclude = "async/**"` in `crates/warp_assets` and the `ui_components` example is gone, because wasm no longer fetches those files.
  - The onboarding layout comment that described the web split was rewritten.
- The pane-header conversation details button and the pane-level details panel are no longer compiled out on wasm. The workspace-level panel they deferred to is gone.
  - `TerminalView::should_show_wasm_{conversation_details_panel, pane_header_details_button}` were removed, with their five tests.
- `RootView::new` picks the auth and onboarding state the same way on every target. `UserAccountDisabled` now logs out on every target, and `DeniedAccessToken` does nothing on any target.
- `Workspace::render_panels` no longer takes `hide_vertical_tabs`, which only the simplified web tab bar set.
- `terminal/view/pane_impl.rs`: with "Open on Desktop" gone, the shared-session viewer's pane-header menu check collapsed into one condition.
- Comments in `terminal/view.rs` and `agent_conversations_model.rs` that pointed at the removed web panel were updated.

**User-visible impact:** None in the desktop app. Every removed control was web-only, or was gated on a web-only setting that is always unset on desktop. The link rewrite only matched the offline server root (`http://offline.invalid`) after NET-0, so opening links behaves the same.

**Notes:**
- The `wasm32-unknown-unknown` target isn't installed on this machine. Wasm-only code was checked with `rg`, not the compiler.
- With the setters gone, every `ContextFlag` stays enabled. The 58 remaining `ContextFlag::X.is_enabled()` checks, mostly in files that the Drive, AI and settings tasks are editing, are left for WASM-2 to inline.
- The generic wasm dependencies in `app/Cargo.toml` (`js-sys`, `wasm-bindgen`, `gloo`, `web-sys`, `serde-wasm-bindgen`) stay for WASM-2. They may matter for wasm feature unification.
- `Credentials::SessionCookie` and `LoginToken::SessionCookie` in `warp_server_auth`/`warp_server_client` are no longer produced (AUTH-2/SRV-1).
- `TelemetryEvent::{WebSessionOpenedOnDesktop, WebCloudObjectOpenedOnDesktop}` are no longer emitted (TEL-4).
- `uri::parse_url_paths` (Drive web links pasted into notebooks) is Drive code and stays for the DRV tasks.
- Stored values of the removed web settings (`UserNativePreference`, `UserNativePreferenceDialogDismissed`, `UserAppInstallStatus`) are ignored. The desktop app never wrote them.
- The `set_before_open_url` hook in `warpui_core` stays; the OSC 8 integration tests use it.

## remote_tty websocket terminal transport
**Why:** `remote_tty` was a web and dev-only terminal backend. It drove a PTY over a websocket to Warp's ssh-proxy-server (`127.0.0.1:3030` by default) and was off in every shipped build. The desktop app always uses `local_tty`.

**Removed:**
- `app/src/terminal/remote_tty/` — the event loop and terminal manager for the websocket transport.
- The `remote_tty` Cargo feature in `app/Cargo.toml` and `crates/warp_terminal/Cargo.toml`.
- The `cfg(feature = "remote_tty")` branches in `pane_group/mod.rs`, `terminal/mod.rs`, `terminal/local_tty/mod.rs`, `terminal/model/session.rs`, `terminal/model/session/command_executor.rs` and `terminal/view/docker_sandbox/mod.rs`.

**Modified:**
- Comments in `terminal/available_shells.rs` and `workspace/view.rs` that mentioned the remote transport were updated.

**User-visible impact:** None.

**Notes:**
- `script/wasm/bundle` still names the feature; it is deleted with the web scripts in the next section.

## Web client crates, scripts and build profiles
**Why:** The browser build of the client was a hosted product on app.warp.dev. With the web client's ties gone, nothing builds or serves it. The scripts also downloaded a prebuilt `wasm-split` binary from Sentry's GitHub releases.

**Removed:**
- `script/wasm/` — the wasm bundle, run and dependency-install scripts, and the dev index page. `install_build_deps` fetched `wasm-split` from `getsentry/symbolicator`.
- `crates/serve-wasm` — a local axum server for the wasm bundle.
- `crates/warp_web_event_bus` — the channel between the wasm app and its host page. It was a dependency of `app` and `warp_logging` on wasm only.
- `crates/managed_secrets_wasm` — wasm bindings for the managed-secrets envelope encryption.
- `tower` and `tower-http` from `[workspace.dependencies]`, which only `serve-wasm` used.
- The `release-wasm`, `release-wasm-debug_assertions` and `dev-wasm` Cargo profiles.
- `jq` and `brotli` from `script/linux/install_build_deps` and `jq` from `script/windows/bootstrap.ps1`. They existed to read the wasm-bindgen version and compress web bundles. The macOS bootstrap keeps `jq`, which `script/macos/run` uses.

**Modified:**
- `Cargo.toml`: the `default-members` comment no longer mentions `serve-wasm`, and the `release-cli` comment no longer refers to `release-wasm`.

**User-visible impact:** None in the desktop app.

**Notes:**
- `wasm32-unknown-unknown` isn't installed on this machine, so the wasm-only dependency sections were edited without compiling them.
- Doc comments in `crates/managed_secrets` that mention `managed_secrets_wasm` stay for AI-18, which deletes that crate.
- `flake.nix` still lists `jq` and `brotli` in its build inputs; left as is.
- The wasm-only dependencies of `app` and other crates (`js-sys`, `wasm-bindgen`, `gloo`, `web-sys`, `serde-wasm-bindgen`) and the `cfg(wasm)` branches are left for WASM-2.

## Warp Drive: panel, menus, actions and deep links
**Why:** Warp Drive stores, syncs and shares objects through Warp's servers. The offline build removes it entirely (user decision 1). This change removes the surfaces a user reaches Drive through. The cloud-object models and sync machinery stay until DRV-2 to DRV-5 remove them.

**Removed:**
- `app/src/drive/{panel, index, items/*, cloud_object_naming_dialog, empty_trash_confirmation_dialog, drive_helpers, settings, import/*}` with their tests — the Drive panel and index (spaces, folders, trash, sorting, drag and drop), the per-object item views including the AI fact and MCP server items, the create/rename and empty-trash dialogs, the import modal, and the anonymous-user object limits.
- `WarpDriveSettings`: `warp_drive.enabled`, `warp_drive.sorting_choice` and the private sharing-onboarding flag, plus `DriveSortOrder`, `DriveIndexVariant`, `OpenWarpDriveObjectSettings`, `OpenWarpDriveObjectArgs` and the "auto-open welcome folder" preference.
- Left panel: the Warp Drive tab, the `workspace:left_panel_warp_drive` (Ctrl-4 / Alt-4) and `workspace:toggle_warp_drive` bindings, the `EnableWarpDrive` context flag, `LeftPanelDisplayedTab::WarpDrive` and `ToolPanelView::WarpDrive`. The Drive index width is no longer read or written; the `windows.warp_drive_index_width` column is left for DB-1.
- The "Drive" app menu; `CustomAction::{NewPersonal*, NewTeam*, SearchDrive}`; `WorkspaceAction::{Create{Personal,Team}{Notebook,Workflow,Folder,EnvVarCollection,AIPrompt}, ImportTo{Personal,Team}Drive, ExportAllWarpDriveObjects, OpenWarpDrive, ToggleWarpDrive, ViewObjectInWarpDrive, OpenObjectSharingSettings, UndoTrash}` with their keybindings, including `workspace:search_drive` and `workspace:export_all_warp_drive_objects`.
- Command palette: `search/command_palette/warp_drive/` (with `data_sources_tests.rs`), the `drive:` filter (`QueryFilter::Drive`), `PaletteMode::WarpDrive`, and the palette's workflow, notebook and env-var item actions.
- Command search: the cloud-workflow and env-var-collection sources (`command_search/workflows/cloud_workflows_data_source.rs`, `command_search/env_var_collections/`) and their accept actions.
- Settings: `settings_view/warp_drive_page.rs` and `SettingsSection::WarpDrive`; the "Warp Drive" tools-panel toggle on the Appearance page; the Warp Drive chip, its preview images and `UICustomizationSettings::show_warp_drive` in onboarding.
- warpctrl: `surface.warp_drive.open` and `surface.warp_drive.toggle` (`warpctrl surface warp-drive`), and their mention in the bundled warpctrl skill.
- Deep links: `UriHost::Drive` (`warp://drive/...`), `WebIntent::DriveObject`, `uri/parse_url_paths.rs`, the `root_view:open_drive_object_*` actions, `NewWorkspaceSource::{NotebookById, WorkflowById}`, notebook links to Drive objects, and `ContextFlag::set_warp_drive_link_only`.
- Navigation into Drive: `cloud_object/breadcrumbs.rs` and `ui_components/breadcrumb.rs`, the breadcrumb headers and "View in Warp Drive" events in the notebook, workflow, env-var and workflow-modal views, "Show in Warp Drive" in AI documents, and the notebook "Move to <team> space" menu items.
- `app/src/billing/` — the shared-object quota ("creation denied") modal and its workspace state.
- The workspace login gate: `WorkspaceAction::blocked_for_anonymous_user` and `From<&WorkspaceAction> for LoginGatedFeature`. With the team-Drive create/import actions gone (and session sharing removed by SS-1), no workspace action needs a login.
- `Modal`'s header icon (`set_header_icon`, `set_header_icon_color`); the creation-denied modal was its only user.
- The terminal's Drive-sharing onboarding block, the block "Save as workflow" hover button and the "Save as workflow" context-menu items, all gated on Drive being enabled.
- The Drive agent tip and the `HitDriveObjectLimitCloseable` sign-up prompt.
- `integration_testing/warp_drive` and the `test_create_folder_from_command_palette` integration test; the Drive-only unit tests in `workspace/view_tests.rs` and `cloud_object/model/model_tests.rs`.
- The `UpdateSortingChoice` telemetry variant, whose payload type is gone.

**Modified:**
- `search/command_search/view.rs`, `zero_state.rs` — local workflows (app, global, `~/.warp/workflows`, project `.warp/workflows`) are always registered, and the `workflows:` filter is always offered. They used to sit behind `is_warp_drive_enabled`, which is always false with no account.
- `terminal/input/prompts/data_source.rs` — the saved-prompts menu fuzzy-matches prompts itself instead of going through the deleted Drive palette source.
- `CloudObject` — `to_warp_drive_item` is gone and `containing_objects_path` returns names, for the text breadcrumbs command search still shows.
- `workspace/view/left_panel.rs` owns `MIN_SIDEBAR_WIDTH` / `MAX_SIDEBAR_WIDTH_RATIO`; `configure_empty_workspace` no longer auto-opens Drive; `/add-prompt` opens the prompt editor pane directly.
- `TipAction::OpenWarpDrive` is kept but no longer in any section, because welcome tips are serialized with it.

**User-visible impact:** There is no Warp Drive panel, menu, settings page, palette section or `warp://drive` link handling. Cloud notebooks, workflows and env-var collections already in the local database can still be restored in panes until DRV-2 to DRV-4 remove them. Local workflows now show in command search, where the offline build had hidden them. A saved window whose left panel was on the Drive tab restores without its left-panel snapshot.

**Notes:**
- Kept for later tasks: `drive/workflows/` (DRV-4); `drive/folders` and the access-level types in `drive/sharing/mod.rs` (DRV-5); `drive/cloud_action_confirmation_dialog.rs` (Teams page, TEAM-1); `drive/cloud_object_styling.rs` and `DriveObjectType`, still used for object icon colours by vertical tabs, filter chips and search items (DRV-2 to DRV-4); `drive/export.rs` and `drive/sharing/{dialog, qr_code, style}` (next section); `integration_testing/cloud_object`, used by the cloud notebook and workflow integration tests (DRV-3/DRV-4).
- Dead code left for its owners: in `CloudModel` / `CloudViewModel` / `UpdateManager` / `SyncQueue` the trash, sort and leave/rename helpers (DRV-5); the `search/notebooks` fuzzy matcher (DRV-3); `WorkflowModal::open_with_new` (DRV-4); `NotebookView::online_only_operation_allowed` (DRV-3); `ai::facts::view::is_syncing` (AI-15).
- `OpenWarpDriveObjectInPane` (terminal and pane-group events) stays: AI citations and plans use it to open cloud objects in panes, and the AI tasks own it.
- `WarpDrivePrivacySettings` is not Drive-only: it holds the telemetry and cloud-conversation-storage toggles, so TEL-1 and the AI plan own it.
- The Drive login purpose in `auth/login_slide.rs` and `onboarding::WARP_DRIVE_FEATURES` are left for AUTH-1.

## Warp Drive: sharing, export and cloud-object dialogs
**Why:** Sharing, guest access, link sharing and export all work on Warp Drive objects through Warp's servers, and the offline build removes Drive (user decision 1). The same sharing dialog also served session sharing and AI-conversation sharing, which cannot work offline: NET-0 configured no session server, and conversation links point at warp.dev.

**Removed:**
- `app/src/drive/sharing/{dialog/*, qr_code, style}` — the sharing dialog (guests, teams, "anyone with the link", access levels, inherited ACLs, invite by email, the shared-session QR code), plus `ShareableObject` and the `SubjectExt` / `UserKindExt` / `TeamKindExt` display helpers. The `qrcode` dependency goes with it.
- `pane_group/pane/view/header/sharing.rs` — the pane-header share and "view-only" buttons, `PaneAction::ShareContents` and its `pane:share_pane_contents` binding, `CustomAction::SharePaneContents`, `PaneConfiguration::{set_shareable_object, toggle_sharing_dialog, open_sharing_qr_code}` and their events, and `HeaderRenderContext::sharing_controls`.
- Callers that only fed the dialog: the notebook, workflow, env-var and AI-document views, the agent-view pane header, the shared-session sharer/viewer paths (`update_shared_session_pane_header`, `open_shared_session_qr_code`, `WorkspaceAction::OpenSharedSessionQrCode`), the AI block "Copy share link" / "Share conversation" menu items and the conversation-list "Share conversation" item.
- `app/src/drive/export.rs` (`ExportManager` singleton) with its tests, the notebook and env-var "Export" menu items, `notebooks::export_notebook`, and the "Export your data" link in the auth-override warning.
- `app/src/cloud_object/grab_edit_access_modal.rs` — the notebook "steal edit access" modal. When another user is actively editing, the notebook now just stays read-only.
- `app/src/cloud_object/toast_message.rs` — the "saved to", "moved to", trash, permanent-deletion and conflict toasts for cloud objects, and `WorkspaceAction::{HandleConflictingWorkflow, HandleConflictingEnvVarCollection}` behind the conflict toasts.
- `app/src/settings/shared_object_limit_banner.rs` — `SharedObjectLimitBannerSettings`, the dismissal state for the plan-limit banner in the Drive index.
- The link-sharing policy checks `is_anyone_with_link_sharing_enabled` / `is_direct_link_sharing_enabled` with their tests, and the chip-editor options only the dialog used (`WordBlockEditorView::{with_layout, with_styles, set_propagate_navigation_keys, set_editor_buffer_text}`, the horizontal layout, the `Navigate` event).

**Modified:**
- `util/filename.rs` — `safe_filename` (and its test) moves here from `drive/export.rs`; AI document export still uses it.
- `drive/sharing/mod.rs` keeps only `SharingAccessLevel` and `ContentEditability`, which the cloud-object views and `CloudViewModel` still use until DRV-2 to DRV-5.
- `HeaderRenderContext` loses its lifetime parameter, updated at every `render_header_content` signature.

**User-visible impact:** Panes no longer have a share button or a read-only indicator, and there is no sharing dialog, QR code or link-copy option for Drive objects, shared sessions or AI conversations. Notebooks and env-var collections can no longer be exported, and cloud-object operations no longer show activity toasts.

**Notes:**
- `SharingDialogSource` and the `OpenedSharingDialog` telemetry variant live in `server/telemetry/events.rs` and are left for TEL-4. `SharedSessionActionSource::SharingDialog` is left for SS-2 (SS-1 landed first and kept the viewer-side enum).
- Dead code left for its owners: `terminal/view/shared_session/adapter.rs` `started_at` (SS-2); the `UpdateManager` permission, guest and leave operations and `ObjectOperationResult::num_objects` (DRV-5); `CloudModel::get_all_exportable_object_ids` and `CloudModelType::can_export` (DRV-5); `workflows/export_workflow.rs` (DRV-4).
- `integration_testing/cloud_object` stays for the cloud notebook and workflow integration tests (DRV-3, DRV-4).
- `app/src/ai/blocklist/mod.rs` already has an unused re-export of `render_ai_follow_up_icon` on `offline-terminal`, left by the AI input change; it is not part of this change.

## Language server downloads are opt-in
**Why:** The code editor's language servers were installed on demand from upstream sources: GitHub releases (`rust-analyzer`, `clangd`), the Go module proxy (`gopls`), the npm registry (`pyright`, `typescript-language-server`) and nodejs.org (a private Node.js when none was installed). An offline enterprise build must not reach those hosts unless the user allows it, and the `lsp` crate took its HTTP client from the Warp server API provider.

**Removed:**
- The `http_client` dependency of `crates/lsp` and the client held by every server candidate and by `LspServerConfig`.
- The unconditional "Install {server}" behavior: the "+" install button in Settings, the footer's install button and the install path in `PersistedWorkspace::handle_install_lsp` no longer run while downloads are off.

**Modified:**
- `crates/node_runtime` defines `DownloadPermit` (only constructor: `from_setting(bool) -> Option<Self>`) and `Downloader` (a plain `http_client::Client` plus a permit). `install_npm` and `fetch_npm_package_version` take a `&Downloader`, and `node_runtime::manual_install_hint()` names the Node.js version needed. `crates/lsp` re-exports `DownloadPermit` and `Downloader`.
- `crates/lsp`: `LanguageServerCandidate::{install, fetch_latest_server_metadata}` and the GitHub helpers in `install.rs` take a `&Downloader`, so no download path compiles without a permit, including `go install` for `gopls`. `LSPServerType::candidate()` and `is_working_on_path` take no client; local detection needs none. New `LSPServerType::{manual_install_hint, requires_node_runtime}` give static install instructions.
- New setting `CodeSettings::allow_language_server_downloads` (`code.language_servers.allow_downloads`, default false, never synced). Settings > Code > Projects starts with its toggle, and the command palette has "Enable/Disable language server downloads" (`AllowLanguageServerDownloads` context flag). The deep link slug is `language_server_downloads`.
- With downloads off, a missing server appears in Settings as "Not installed" with its manual install command (and the Node.js hint for npm-based servers) and no "+" button. The editor footer shows "{binary} not installed" with the same instructions as a tooltip, an "Enable downloads in Settings" button and a "Re-check" button (`PersistedWorkspace::recheck_lsp_installation`). An install attempted anyway shows the toast "Automatic downloads are disabled" with an "Open settings" link.
- `PersistedWorkspace` builds the `Downloader` from the setting in `handle_install_lsp`, and the installation check behind `detect_lsp_workspace_status` is shared with the re-check.

**User-visible impact:** Language servers found on `PATH`, or downloaded earlier into the data directory, keep working. Nothing new is downloaded until the user turns on the setting.

**Notes:** Committed as one commit rather than the planned crate and app pair, because the crate change alone leaves the app unbuildable. The new setting has no telemetry.

## AI command prediction and passive suggestions
**Why:** Agent Predict and passive suggestions sent the user's recent commands, their output, working directory and history to Warp's servers (`/ai/generate_input_suggestions`, `/ai/predict_am_queries`, `/ai/generate_am_query_suggestions` and the `GeneratePassiveSuggestions` requests on `/ai/passive-suggestions`) to predict the next command, ghost-text agent prompts, and offer prompt and code-diff suggestions. They are built-in AI features, which the offline fork removes.

**Removed:**
- `app/src/ai/predict/` — `NextCommandModel` (AI next-command prediction: zero-state, partial and "cycle" suggestions), the request/response types for the three endpoints above, and the prompt-suggestion keybinding helpers.
- `app/src/ai/blocklist/passive_suggestions/` — the legacy and MAA passive-suggestion models (prompt suggestions and suggested code diffs after a command or agent response, static prompt suggestions).
- `terminal/view/passive_suggestions.rs`, `terminal/view/inline_banner/prompt_suggestions.rs` (the prompt-suggestion banner above the input and the zero-state prompt suggestion types) and `terminal/view/inline_banner/passive_code_diff.rs` (the out-of-band suggested code-diff banner).
- Terminal input: the `NextCommandModel` / `IntelligentAutosuggestionResult` plumbing, the AI ghost-text prediction for agent prompts, the prompt-suggestion banner, zero-state prompt suggestions, `InputAction::{CycleNextCommandSuggestion, InsertZeroStatePromptSuggestion, TryHandlePassiveCodeDiff}` (with the Cmd/Ctrl-Shift-E passive-diff binding and the down-arrow cycle on an empty input), the input events that only fed prompt suggestions (`Enter`, `CtrlEnter`, `UnhandledCmdEnter`, `AutosuggestionAccepted`, `TryHandlePassiveCodeDiff`), and the `Code_Suggestions`, `PassiveCodeDiffKeybindingsEnabled` and `CtrlEnterAcceptsPromptSuggestion` keymap flags.
- Editor: `AutosuggestionType` (command vs. AI-query and "intelligent" autosuggestions), `EditorView::{with_next_command_model, maybe_populate_intelligent_autosuggestion}`, the "Cycle suggestions" hint, and the Ctrl-C check for pending passive AI blocks.
- Terminal view: the passive-suggestion models and their event handlers, prompt-suggestion banner state and acceptance, the "Execute this plan" static suggestion, `TerminalAction::ResolvePromptSuggestion` with its `terminal:accept_prompt_suggestions` binding ("Accept Prompt Suggestion"), the Ctrl-C passive-suggestion handling, `CodeDiffAction`, hidden passive AI block cleanup, the `HasPendingPromptSuggestion` keymap flag, and `terminal/command_corrections_denylist.rs` (the list of command corrections that deferred to Next Command).
- Workspace: the "Prompt Suggestions unavailable" modal (`WorkspaceAction::OpenPromptSuggestionsUnavailableModal`, `FreeAiRemovalModalVariant::PromptSuggestions`) and the zero-state suggestion field of `WorkspaceAction::{NewTabInAgentMode, NewPaneInAgentMode}`.
- Settings: `IntelligentAutosuggestionsEnabled` (`agents.warp_agent.active_ai.intelligent_autosuggestions_enabled`), `AgentModeQuerySuggestionsEnabled` (`agents.warp_agent.active_ai.agent_mode_query_suggestions_enabled`), `CodeSuggestionsEnabled` (`agents.warp_agent.active_ai.code_suggestions_enabled`), `NaturalLanguageAutosuggestionsEnabled` (`agents.warp_agent.active_ai.natural_language_autosuggestions_enabled`) and the private `ShouldShowCodeSuggestionSpeedbump`, with their getters, the Next Command, Prompt suggestions, Suggested code banners and Natural language autosuggestions widgets and toggle bindings on the Warp Agent page, and their keymap flags.
- Server client: `ServerApi::{generate_ai_input_suggestions, generate_am_query_suggestions, predict_am_queries}`, and the passive-suggestion routing in `crates/warp_multi_agent_client` (every request now goes to the multi-agent endpoint).
- Agent-core calling paths that only served passive suggestions: `AIAgentInput::{TriggerPassiveSuggestion, PassiveSuggestionResult}`, `PassiveSuggestionTrigger`, `ShellCommandCompletedTrigger`, `PassiveSuggestionResultType`, `PassiveCodeDiffEntry`, `PassiveRequestType::PassiveSuggestion`, their proto conversions and redaction, the controller's zero-state, passive-result, passive-code-diff and unit-test-suggestion request builders, `AIBlock::handle_passive_code_diff_action`, `CodeDiffView::new_passive` and the code-suggestion speedbump in `CodeDiffView` and `SuggestedUnitTestsView`, and `ai_types::{PassiveSuggestionTriggerType, EntrypointType::{PromptSuggestion, ZeroStateAgentModePromptSuggestion, TriggerPassiveSuggestion}}`.
- Helpers that lost their last caller: `UserWorkspaces::{is_prompt_suggestions_toggleable, is_code_suggestions_toggleable, is_next_command_enabled}`, `PromptAlertState::tooltip_text`, `PromptAlertView::state`, `persistence::commands::get_previous_commands`.
- `TelemetryEvent::{AgentModePrediction, ZeroStatePromptSuggestionUsed}` and the telemetry `AIAgentInput::{TriggerSuggestPrompt, PassiveSuggestionResult}` arms, whose payload types were deleted.
- Tests of the removed code: the passive-suggestion model and input-suggestion request tests, `ctrl_c_does_not_accept_prompt_suggestion_banner`, `passive_suggestions_suppressed_for_shared_ambient_viewer`, the two passive request-params tests in `controller_tests.rs`, `test_spend_limit_tooltips_identify_scope`, the passive routing tests in `warp_multi_agent_client`, and the `assert_exchange_has_trigger_suggest_prompt` integration assertion.

**Modified:**
- `terminal/input/autosuggestions.rs` (new) — the history lookups and command validation behind the gray inline autosuggestion, moved unchanged from `NextCommandModel`: most recent matching command (same directory first), the commands that followed the same command in a similar context (`next_commands_from_similar_history`, formerly `get_similar_history_context` with no extra preceding commands), and `is_command_valid`. Its tests moved to `autosuggestions_tests.rs`.
- `terminal/input.rs` — switching the input to AI mode (the CLI rich input) still clears a pending command autosuggestion; accepting an autosuggestion always counts toward the right-arrow hint; `Input::new` no longer takes the `ServerApi`; `input_ctrl_enter` only submits the CLI rich input when `submit_on_ctrl_enter` is on.
- `terminal/view.rs` — command corrections always populate the autosuggestion (the deny list only applied when Next Command was on).
- `terminal/input_tests.rs` — the two CLI rich-input Ctrl-Enter tests now assert only whether the input was submitted.
- `crates/integration/src/test.rs` — dropped the removed field from a `NewPaneInAgentMode` action.

**User-visible impact:** None for the default experience: the gray inline autosuggestion from command history (accept with the right arrow), its ignore button and command corrections behave as before. The Warp Agent settings page no longer lists Next Command, Prompt suggestions, Suggested code banners or Natural language autosuggestions, and the "Accept Prompt Suggestion" binding (ctrl-enter on macOS, alt-shift-enter elsewhere) is gone from Keyboard shortcuts. Stored values of the four settings are ignored.

**Notes:**
- `rg 'PassiveSuggestion|prompt_suggestions' app` still matches: the external proto variants `GeneratePassiveSuggestions` and `Message::PassiveSuggestionResult` in exhaustive matches over `warp_multi_agent_api` types in `ai/agent/api/{convert_conversation, convert_from}.rs` and `ai/agent/conversation_yaml.rs`, so stored conversations that contain them still restore (removed with the crate in AI-30); `contains_static_prompt_suggestion_input` in the AI block renderer (AI-28); the `is_prompt_suggestions_toggleable` team-policy field in `workspaces/` (AI-29); the `prompt_suggestions_via_maa` Cargo feature (FLAGS-1); and the `TogglePromptSuggestionsSetting` telemetry payload (TEL-4).
- Nothing creates passive AI blocks any more. The AI block's passive rendering (`is_passive_conversation`, `PassiveRequestType::{CodeDiff, UnitTestSuggestion}`, `AIAgentInput::AutoCodeDiffQuery`, the `PassiveCodeDiffLoaded`, `DismissedPassiveBlock` and `ContinuePassiveCodeDiffWithAgent` events, `SuggestedUnitTestsView`) is left for AI-27 / AI-28.
- Left for TEL-4: telemetry variants whose callers are gone (`PromptSuggestionShown`, `SuggestedCodeDiffBannerShown`, `SuggestedCodeDiffFailed`, `PromptSuggestionAccepted`, `StaticPromptSuggestionsBannerShown`, `StaticPromptSuggestionAccepted`, `Toggle{IntelligentAutosuggestions, PromptSuggestions, CodeSuggestions, NaturalLanguageAutosuggestions}Setting`) and their payload enums (`PromptSuggestionViewType`, `PromptSuggestionFallbackReason`, `ToggleCodeSuggestionsSettingSource`).
- Left for FLAGS-1: `FeatureFlag::{CycleNextCommandSuggestion, PartialNextCommandSuggestions, PromptSuggestionsViaMAA, PredictAMQueries}` and their Cargo features. `ValidateAutosuggestions` still gates `is_command_valid`.
- Left for AI-16: `FreeAiRemovalModalVariant` now has only its `Notice` variant.

## AI-generated commit messages, pull request text and block titles
**Why:** The code-review commit dialog sent the working-tree diff and branch name to Warp's `/ai/generate_code_review_content` endpoint to draft a commit message when it opened, and "Create PR" sent the branch diff and commit subjects to the same endpoint for a PR title and description. Both are built-in AI text generation, which the offline fork removes. The shared-block title-generation setting was left over from the block-sharing removal.

**Removed:**
- `app/src/ai/generate_code_review_content/` (request/response types) and `AIClient::generate_code_review_content` with its `ServerApi` implementation.
- `code_review/git_actions.rs` — `generate_commit_message` and `create_pr_with_ai_content`; the commit chain and create-PR no longer take an `AIClient`.
- `DiffStateModel::generate_commit_message`, the local model's implementation and `DiffStateModelEvent::CommitMessageGenerated`, and the `autogenerate_pr_content` / `autogenerate_content` arguments of the commit-chain and create-PR operations.
- Git dialog: `should_send_git_ops_ai_request`, the open-time commit-message request and `apply_generated_commit_message`, and the "Generating commit message…" placeholder.
- `util/git.rs` — `get_diff_for_commit_message`, `get_diff_for_pr`, `get_branch_commit_messages`, `sanitize_pr_title` and their size caps, which only prepared input for the AI request; `create_pr` lost its title/body arguments.
- Settings `GitOperationsAutogenEnabled` (`agents.warp_agent.active_ai.git_operations_autogen_enabled`) and `SharedBlockTitleGenerationEnabled` (`agents.warp_agent.active_ai.shared_block_title_generation_enabled`), their getters, widgets, toggle bindings ("commit and pull request generation", "shared block title generation") and the `Git_Operations_Autogen` / `Shared_Block_Title_Generation` keymap flags.
- The "Active AI" category of the Warp Agent settings page (with its master switch in the header), which had no settings left.
- `UserWorkspaces::is_git_operations_ai_enabled`, which only gated the removed generation.

**Modified:**
- `code_review/git_dialog/{commit, pr}.rs` — the commit dialog always opens with the "Type a commit message" placeholder and Confirm stays disabled until the user types a message; Create PR always runs `gh pr create --fill` against the detected default branch.
- `code_review/code_review_view.rs` — no longer lists the removed event.

**User-visible impact:** The code-review commit dialog no longer pre-fills a generated commit message; the user types it. Commit, commit-and-push, commit-and-create-PR, push and create-PR work as before, and pull requests get their title and body from `gh pr create --fill`. The Warp Agent settings page no longer has an Active AI section. Stored values of the two settings are ignored.

**Notes:**
- Left for AI-22: `WarpAgentPageAction::ToggleActiveAI` and its "Active AI" toggle binding; the `IsActiveAIEnabled` setting still gates rule suggestions (AI-15).
- Left for TEL-4: `TelemetryEvent::{ToggleSharedBlockTitleGenerationSetting, ToggleGitOperationsAutogenSetting}`, which nothing emits now.
- Left for FLAGS-1: `FeatureFlag::SharedBlockTitleGeneration` and its Cargo feature. `FeatureFlag::GitOperationsInCodeReview` still gates the git dialogs.
- Left for AI-29: the `is_git_operations_ai_enabled` team-policy field in `workspaces/` and `crates/graphql`.

## CLI-agent support moved out of the AI module
**Why:** Support for third-party CLI agents running in the terminal (Claude Code, Codex, Gemini CLI, OpenCode and others) is kept. That covers the CLI agent toolbar, the Rich Input composer (Ctrl-G), notifications and the mailbox, vertical-tab status and the CLI agents settings page. Much of its code lived in `crate::ai`, which later tasks delete wholesale, so the pieces it needs move to non-AI modules first.

**Removed:**
- `CLIAgent::from_harness` and the `warp_cli::agent::Harness` import in `terminal/cli_agent.rs`. The cloud-harness mapping now lives with the other harness display helpers as `ai/harness_display.rs::cli_agent`, which is deleted along with `Harness`.
- The Uber-only special case in CLI agent detection, which treated `aifx agent run claude` as Claude for members of one team (`UBER_TEAM_UID`, the `UserWorkspaces` lookup), and its tests. `CLIAgent::detect` no longer takes an `AppContext`.
- `CLIAgentSessionStatus::to_conversation_status`.
- The `disable_telemetry_path` test helper in the notification model tests. The model never reads `ShowAgentNotifications`, so the helper had no effect.

**Modified:**
- New `settings/cli_agent.rs` with a `CLIAgentSettings` group. Moved from `AISettings` with unchanged setting type names (the storage keys) and `toml_path`s:
  - `ShouldRenderCLIAgentToolbar`
  - `AutoToggleRichInput`
  - `AutoOpenRichInputOnCLIAgentStart`
  - `AutoDismissRichInputAfterSubmit`
  - `SubmitRichInputOnCtrlEnter`
  - `CLIAgentToolbarEnabledCommands`
  - `ShowAgentNotifications`: it controls the in-app notification mailbox, its toolbar button and the toasts, which carry CLI agent notifications.
  - `PluginInstallChipDismissedMap` and `PluginUpdateChipDismissedForVersionMap`

  `ToolbarCommandMap`, the `CompiledCommandsForCodingAgentToolbar` singleton, the toolbar-command and plugin-chip helpers, and their tests moved with them. The group is registered in `settings/init.rs` and `test_util/settings.rs`. Readers in the terminal view and input, the toolbar, context chips, workspace, settings pages and onboarding now use `CLIAgentSettings`.
- `DefaultTabConfigPath` (`general.default_tab_config_path`) moved to `GeneralSettings` (`terminal/general_settings.rs`), along with `default_tab_config_path()` and `resolved_default_tab_config()`. The companion `DefaultSessionMode` setting stays in `AISettings` for now.
- `CLAUDE_ORANGE` moved from `ai/blocklist/view_util.rs` to `terminal/cli_agent.rs`.
- `CurrentHead`, `DiffBase` and `DiffSetHunk` moved to the new `code_review/diff_set.rs`, and `AgentReviewCommentBatch` to `code_review/comments/batch.rs`. Their `warp_multi_agent_api` conversions are now free functions in `ai/agent`: `current_head_to_api_ref`, `current_head_to_diff_hunk_api`, `diff_base_to_api_ref`, `diff_base_to_diff_hunk_api`, `diff_set_hunk_to_api` and `comment.rs::attached_review_comment_to_api`. They replace the `From` impls, `DiffSetHunk::convert_to_api` and `From<AttachedReviewComment> for api::ReviewComment`, so `code_review/comments` no longer depends on the agent API.
- `ImageContext` moved to `util/image.rs`.
- New neutral status module `ui_components/agent_status.rs`:
  - It holds `AgentStatus` (in progress, success, error, cancelled, blocked), `StatusColorStyle`, `StatusElementStyle` and `render_status_element`. The last two moved from `ai/conversation_status_ui.rs`, which keeps only the AI impls.
  - `IconWithStatusVariant`, `agent_icon.rs` and `vertical_tabs.rs` use `AgentStatus`. `CLIAgentSessionStatus::to_agent_status` maps to it directly.
  - Oz statuses convert through `From<&ConversationStatus>` in `ai/agent/conversation.rs`; the transient-error and waiting-for-events states render as in progress.
  - Feeding CLI status into Oz conversation history now goes through `From<&CLIAgentSessionStatus> for ConversationStatus` on the AI side.
- `ai/agent_management/notifications/` and `AgentNotificationsModel` moved to `app/src/agent_notifications/` (`model.rs`, `item.rs`, `item_rendering.rs`, `toast_stack.rs`, `view.rs`). The mailbox keybindings are registered by `agent_notifications::init`, called from `lib.rs`.

**User-visible impact:** None. Existing settings files and stored preferences keep working because the keys are unchanged. Typing `aifx agent run claude` no longer shows the CLI agent toolbar automatically; users of such wrappers can add the command under Settings → Third party CLI agents.

**Notes:**
- `agent_notifications` keeps the Oz notification origin and source variants, the conversation-history and artifact handling, and the `AgentManagementEvent` name; AI-21 strips them.
- `terminal/cli_agent.rs` still imports `ai::skills::SkillProvider` (AI-11 removes it). `terminal/cli_agent_sessions` still uses `ai::blocklist::InputConfig` (AI-26 removes it).
- The Warp-distributed plugin installers are untouched; SWP-09 removes them.

## AI gates removed from CLI-agent support
**Why:** AI is permanently off in this fork: `AISettings::is_any_ai_enabled` is always false because there are no accounts, and `FeatureFlag::AgentMode` counts as off. Checks on those gates were disabling parts of the third-party CLI agent support that is kept.

**Removed:** None.

**Modified:**
- `settings_view/cli_agents_page.rs`: the "Third party CLI agents" settings page always renders. It was gated on `FeatureFlag::AgentMode`.
- `terminal/view.rs`: opening Rich Input automatically when a CLI agent session starts, and closing and reopening it automatically when the agent blocks, no longer require `is_any_ai_enabled`.
- `terminal/input.rs`: images pasted into the CLI agent Rich Input attach even when AI is off. Other inputs still need AI to attach images.

**User-visible impact:** The CLI agents settings page appears. The "auto open Rich Input" and "auto show/hide Rich Input" settings take effect. Pasted screenshots attach in Rich Input.

**Notes:**
- Audited `terminal/cli_agent_sessions/**`, `terminal/view/use_agent_footer/**` and `terminal/input/cli_agent.rs`. They contain no AI gates on CLI paths. The `is_any_ai_enabled` check in `use_agent_footer` only gates Warp's own "Use agent" footer, and the CLI branch returns before it.
- The `AgentView`/`CLIAgentRichInput` overrides in the `terminal/view_tests.rs` Rich Input tests stay. The flag checks they satisfy are in `agent_input_footer/{toolbar_item.rs, mod.rs}` (AI-08) and `ai/blocklist/input_model.rs` (AI-06/AI-26).
- `FeatureFlag::HOANotifications` and `FeatureFlag::ImageAsContext` are on by default through Cargo features. They still gate the notification mailbox and toasts, and the Rich Input image chips. Later tasks must treat them as permanently on, not as AI-only flags.
## Accounts: login, sign-up and SSO
**Why:** The offline build has no accounts (decision 6). The app now always runs in what used to be the logged-out state: nothing can log in, nothing offers to, and no stored credential is ever read, so an old Firebase refresh token can never reach a server again.

**Removed:**
- `app/src/auth/`: the login and sign-up views (`auth_view_modal`, `auth_view_body`, `auth_view_shared_helpers`), the post-onboarding `login_slide`, `auth_override_warning_*` (the "another account is signing in" modal), `login_error_modal`, `login_failure_notification`, `needs_sso_link_view`, `paste_auth_token_modal`, `user_properties`, `web_handoff` (wasm), and the log-out path (`maybe_log_out`, `log_out`, `log_out_and_open_web`, `web_logout_url*`, `remove_cloud_persisted_settings`) with its tests.
- `AuthManager` login machinery: auth-redirect handling and CSRF state, user refresh, API-key and device-code login, anonymous Firebase users (`create_anonymous_user`, anonymous linking and custom tokens), sign-in/sign-up/upgrade/SSO URL builders, login-gated feature prompts, reauth and the server "is onboarded" flag. `AuthManager` is now an empty, event-less singleton kept only for existing test setups (AUTH-2 deletes it).
- Root view: the `Auth`, `ConfirmIncomingAuth`, `NeedsSsoLink`, `WebImport`, `LoginSlide` and `PostAuthOnboarding` states, account-first onboarding (account classes, post-auth offer routing, pending post-auth settings and tutorial), the `root_view:log_out` and `root_view:handle_incoming_auth_url` actions, and the paste-token modal. A new window now goes to onboarding (if the user hasn't completed it) or straight to the workspace.
- Workspace: the account avatar, the name / "Sign up" / "Upgrade" / "Billing and usage" / "Log out" entries of the user menu, the require-login and auth-override modals, the reauth ("Your login has expired") and anonymous-user banners, the `LogOut`, `Reauth`, `SignupAnonymousUser`, `SignInAnonymousWebUser`, `AttemptLoginGatedAIUpgrade` and `CopyAccessTokenToClipboard` actions and bindings, `blocked_for_anonymous_user`, and the sign-up event chain from terminal, input and pane group.
- Settings: the Account page (`settings_view/main_page.rs`, `SettingsSection::Account`, the "Open Settings: Account" binding and custom action). A persisted or deep-linked `Account` slug now opens the default page (Appearance). The sign-up buttons and "Create an account" links on the Warp Agent, Warp Drive, Billing and usage and agent-profile pages, and the login-gated upgrade links there, in command search and in the workflow editor.
- "Log out" and the debug "Create anonymous user" items in the app menu; the `app:maybe_log_out` and `app:log_out` global actions.
- `UriHost::Auth` (`warp://auth/desktop_redirect`), the web-checkout success flag that rode on it, and the replace-window fallback only that route used.
- Oz CLI: the `login`, `logout` and `whoami` commands (`ai/agent_sdk/admin.rs`) and the global `--api-key` / `WARP_API_KEY` option, including the GUI's `--api-key` startup login. Commands that need an account now fail immediately with "This command requires a Warp account, which this build does not support."
- Onboarding: the "Already have an account? Log in" link on the intro slide, the theme slide's "Privacy Settings" link (it opened the login slide), and the "paste your token" fallback on the AI access and offer slides.
- Left panel: the "Sign in" button on the locked Warp Drive and conversation panels.
- Persistence: the Logout v0 database pause/delete/rebuild (`PauseAndRemoveDatabase`, `ReconstructAndResume`) and the `UpsertCurrentUserInformation` write (the `current_user_information` table is left for DB-1).
- `warp_server_auth`: `PersistedUser` and its secure-storage persistence, `PersistAction`, `initialize_for_credential_validation`, and the `WARP_USER_SECRET` build-time credential.
- Cargo features `skip_login` and `fast_dev` (in `app`, `warp_server_client` and `warp_server_auth`).
- `ServerApi::notify_login` and the anonymous-user creation error type.
- The privacy-settings fetch/upload that ran after login (`PrivacySettings::fetch_or_update_settings` and helpers) and `disable_default_regex_trigger`.
- Logout-only reset helpers (`BlocklistAIHistoryModel::reset`, `OrchestrationPillBarModel::reset`, `AIRequestUsageModel::reset_server_availability`, `NotebookManager::reset`, `EnvVarCollectionManager::reset`, `SyncQueue::clear`, `UpdateManager::reset_initial_load`, `PersistedWorkspace::on_user_changed`) and the pricing-promotion click telemetry that only the removed upgrade link sent.

**Modified:**
- `warp_server_auth::AuthState::initialize` — no longer reads the keychain or `WARP_USER_SECRET`; it starts logged out (tests and the integration channel still get the test user).
- `app/src/stored_credentials.rs` (new) — on the first launch of a data profile, deletes the `User` entry (the account and its Firebase refresh token) from secure storage, then records the attempt so it never touches the keychain again. Best-effort: a failure is logged and not retried.
- `settings/initializer.rs` — the new-user defaults and the remaining setting migration now run at every launch, keyed to "has not completed onboarding" (`HasCompletedOnboarding`) instead of the server's "not onboarded" flag. The Windows font-size default now only applies when the user hasn't set a size.
- Secret redaction — **bug fix:** the recommended secret patterns were only seeded into the custom pattern list on the login path, and new accounts were deliberately skipped, so logged-out users never got them. `SettingsInitializer` now seeds them from the local defaults at every launch, once per profile (`HasInitializedDefaultSecretRegexes`), so patterns a user removes stay removed. Secret redaction itself is still off by default. Covered by `settings::initializer::tests::app_launch_seeds_recommended_secret_regexes_once`.
- `lib.rs` — the first-frame callback (GPU power detection, graphics-backend dropdown refresh) and the crash-recovery frame callback were only registered for logged-in users; both are now always registered. **Bug fix:** on Linux and Windows the crash-recovery child was never released after the first successful frames for logged-out users; it now is.
- Workspace user menu — the gear button the logged-out path already showed stays as a plain settings menu (What's new, Settings, Keyboard shortcuts, Documentation, Feedback, logs, Slack; the links are LINKS-1's).
- Subscribers to `AuthManager` events (conversations, harness availability, self-hosted workers, execution profiles, built-in MCP servers, one-time modals, billing pages, host selector, input footer) no longer subscribe; the events never fired without an account.
- Integration channel: onboarding is skipped in `RootView::new`, which the logged-in test user used to do implicitly.

**User-visible impact:** There is no way to log in, sign up or link SSO, and no screen, banner, menu item or button asks you to. Existing Warp users start logged out; their stored credential is removed from the keychain on first launch, and they see the local onboarding once if they never completed it on this machine. The recommended secret-redaction patterns are now present for everyone (they apply once secret redaction is turned on). Settings no longer has an Account page; the version is still shown on About. `warp://auth` links are rejected. The Oz CLI can no longer authenticate.

**Notes:**
- `VersionInfoWidget` was not moved into `about_page.rs`: the About page already shows the version with a copy button, so moving it would show the version twice. It was deleted with the Account page.
- Left for AUTH-2: the user model and `AuthStateProvider` users, `AuthManager` and its test setups, `is_logged_in` / `is_anonymous_or_logged_out` / `is_onboarded` checks elsewhere, the `IsAnonymousUser` context flag, `apply_onboarding_settings`' `has_account` parameter, and renaming `AuthOnboardingState`.
- Left for AI tasks (dead code now that login and logout never run): the cloud-load path in `ai/agent_conversations_model.rs` (AI-17), the one-time launch-modal triggers in `workspace/one_time_modal_model.rs` (AI-23), and the upgrade/offer events of the AI onboarding slides, which root view now ignores (AI-23). `BillingAndUsagePageAction::{OpenUrl, ContactSupport}` are never constructed (BILL-1).
- Left for DRV tasks: "Sign in to edit" tooltips for shared Drive objects (`ContentEditability::RequiresLogin`) and the anonymous-object-limit gates, both unreachable without an account.
- Left for TEL-4: the login/logout telemetry variants. For WASM-1: `warp_web_event_bus::WarpEvent::LoggedOut`. For AI-11: the `test-warp-ui` dogfood skill still documents `--api-key`.
- The login slide's "sync settings across devices" copy was removed with `login_slide.rs`; the unused `onboarding::WARP_DRIVE_FEATURES` list went with it.
- The TUI's separate secure-storage namespace (`<data domain>.tui`) is not cleaned up; the TUI was removed before this change.
- The spec's `log_out` grep still matches `log_outcome`/`log_output` identifiers and the MCP servers' own OAuth log-out (AI-14).
- `crates/integration/src/test/settings_navigation.rs` still named the removed `SettingsSection::CodeIndexing` (left broken by the codebase-indexing removal); it now asserts `SettingsSection::Projects`, the page that replaced it.

## Rules, facts, memory and saved prompts
**Why:** AI Rules (facts and memory) were stored as Warp Drive objects, synced to Warp's servers and attached to built-in agent requests. Saved prompts (Agent Mode workflows) were Drive workflows that were only usable by the built-in agent. Suggested rules and suggested prompts came from the agent's responses. All of it is built-in AI or Drive-synced state that the offline fork removes.

**Removed:**
- `app/src/ai/facts/` (`AIFactManager`, the Rules pane view and the memory/rule editors), `settings_view/knowledge_page.rs` (Settings > Agents > Knowledge), `pane_group/pane/ai_fact_pane.rs`, `drive/items/{ai_fact, ai_fact_collection}.rs`, `crates/cloud_object_models/src/ai_fact.rs` (`AIFact`, `AIMemory`, `CloudAIFactModel`, `ServerAIFact`) and the `JsonAIFact` GraphQL format.
- `ai/blocklist/{suggested_rule_modal, suggested_agent_mode_workflow_modal, suggestion_chip_view}.rs`, the "Suggestions:" footer of an AI block (rule and prompt chips, "Dismiss" and "Don't show again", "Manage rules"), `search/ai_context_menu/rules/` (the `@` menu "Rules" category and `QueryFilter::Rules`), `terminal/input/prompts/` (the `/prompts` inline menu), `terminal/input/slash_commands/data_source/saved_prompts*`, `integration_testing/rules/` and `crates/integration/src/test/rules.rs`.
- `Workflow::AgentMode`: `Workflow` now has only the `Command` variant, so `prompt()`, `is_agent_mode_workflow()` and the agent-mode serialization went. `DriveObjectType::{AgentModeWorkflow, AIFact, AIFactCollection}`, sync-queue and update-manager support for AI facts (`QueueItem::UpdateAIFact`, `UpdateManager::{create_ai_fact, update_ai_fact}`) and `is_for_agent_mode` in the workflow editor and `WorkflowOpenSource`.
- Slash commands `/add-rule`, `/open-rules`, `/add-prompt` and `/prompts`; `QueryFilter::AgentModeWorkflows` (the `prompts:` filter of the command palette and command search); `AIBlockAction`/`AIBlockEvent` variants for opening rules and suggestions; the "Save as prompt" item of the AI block context menu; `TerminalAction::{OpenAddRulePane, OpenRulesPane, OpenAddPromptPane}`.
- Menus and bindings: `CustomAction::{OpenAIFactCollection, NewPersonalAIPrompt, NewTeamAIPrompt}` with `workspace:{open_ai_fact_collection, create_personal_ai_prompt, create_team_ai_prompt}`, and their entries in the AI and Drive menus. The AI menu is now built only when it has an item (today MCP servers, which AI-14 removes), so no empty menu is left.
- `SettingsSection::Knowledge`, the `AISettings` settings `MemoryEnabled` (`agents.knowledge.rules_enabled`) and `RuleSuggestionsEnabled`, and the `AI_Rules` and `Suggested_Rules` keymap flags. Agent requests always send `rules_enabled: false`.
- The `AIFactManager` singleton, from `lib.rs` and the workspace test setup.
- Persisted panes: `LeafContents::AIFact`, `AIFactPaneSnapshot`, the `ai_memory_panes` reads and writes and the `AIFactPane`/`NewAIFactPane`/`AI_FACT_PANE_KIND` model types. `save_app_state` still deletes the `ai_memory_panes` rows (foreign key to `pane_leaves`) until DB-1.

**Modified:**
- `SuggestedLoggingId` now lives in `ai/agent/mod.rs`. The agent-core `Suggestions`, `SuggestedRule` and `SuggestedAgentModeWorkflow` types stay until AI-29; nothing renders them.
- `AcceptSlashCommandOrSavedPrompt` is `AcceptSlashMenuItem` (slash command or skill). `InputSuggestionsMode::PromptsMenu`, `InlineMenuType::PromptsMenu` and the cloud-mode slash menu "Prompts" section are gone. `/prompts` is no longer allowed in the CLI agent composer.
- `SettingsSection::from_slug` no longer accepts "Knowledge". The settings navigation tests use the Profiles page where they used Knowledge.
- `@` attachments no longer accept `<rule:...>`.
- `ai/agent_sdk`: `--saved-prompt` is rejected at run time (AI-12 deletes the agent SDK).
- The searcher test that ranked a saved prompt against a workflow now uses two command workflows.

**User-visible impact:** There is no Rules pane, Knowledge settings page, rule or prompt suggestions, saved prompt or `/prompts` menu. Command search and the command palette list only command workflows. Existing Drive objects of these kinds are ignored, and a session that was restored with a Rules pane opens without it.

**Notes:**
- A restored `ai_memory` leaf now fails with "Unrecognized pane kind", the same way removed MCP panes do.
- Left for AI-13/AI-22: the `WarpDriveContextEnabled` setting (`agents.knowledge.warp_drive_context_enabled`) and the `warp_drive_context_enabled` request field; its page went with Knowledge.
- Left for TEL-4: telemetry variants whose callers are gone (`KnowledgePaneOpened`/`KnowledgePaneEntrypoint`, `AISuggestedRule*`, `*SuggestedAgentModeWorkflow*`, `ExecutedWarpDrivePrompt`, `SlashCommandAccepted` details).
- Left for AI-12: `Prompt::SavedPrompt` and `--saved-prompt` in `crates/warp_cli` and `ai/agent_sdk`. Left for AI-29: `Suggestions`, `SuggestedRule`, `SuggestedAgentModeWorkflow` in `ai/agent`, and `Conversation::dismiss_current_suggestions`. Left for FLAGS-1: `FeatureFlag::{AIRules, SuggestedRules, SuggestedAgentModeWorkflows, AgentModeWorkflows, KnowledgeSidebar}`.

## CLI-agent footer split out of the agent footer
**Why:** The toolbar shown under a running third-party CLI agent (Claude Code, Codex, Gemini CLI, OpenCode) was the CLI mode of `AgentInputFooter`, which is Warp's own agent-view footer and is deleted with the agent view. The CLI toolbar had to stand on its own first so the later AI tasks can delete the agent footer and the voice, credits and plugin code around it.

**Removed:**
- The CLI mode of `AgentInputFooter` (`ai/blocklist/agent_view/agent_input_footer/`): the CLI buttons and plugin chips, the CLI display chips, the CLI voice flow, `render_cli_mode_footer`, and the CLI actions and events. The footer is agent-view only now; AI-27 deletes it.
- `AgentToolbarItemKind::{RichInput, Settings}`, `ToolbarAvailability`, `available_in`, `cli_default_left`/`cli_default_right`, `all_available_for_cli_input` and `defaults_for_mode`, and `AgentToolbarEditorMode`.
- The cloud-routing indicators (live cloud session, new cloud VM) that the CLI footer showed for a third-party agent running in a cloud session, and their four tests. Cloud agents are removed by AI-17 and AI-19.
- The `ToggleCodeReview` footer action and `UseAgentToolbarEvent::ToggleCodeReviewPane`. No control dispatched them.
- The `FeatureFlag::AgentView` and `CLIAgentRichInput` overrides in `status_blocked_auto_closes_rich_input` and `status_in_progress_auto_opens_rich_input_after_blocked`, and the `CLIAgentRichInput` override in `unregister_cli_agent_session_restores_unlocked_input_config`. Nothing on the CLI path reads `CLIAgentRichInput` any more.

**Modified:**
- New `terminal/view/cli_agent_footer/` with the `CLIAgentFooter` view: the agent icon, context chips, Rich Input toggle, attach file (and the picked-path insertion), file explorer, settings, the plugin install/update chips (`plugin_chip.rs`), and the CLI voice flow (`voice.rs`, behind the `voice_input` feature). `Input` owns one shared `CLIAgentFooter` beside the agent footer and renders it under the Rich Input composer; `UseAgentToolbar` renders it under the running command and forwards its events. `Input::attach_file`, chip-menu focus routing and the session-context and repo-path updates reach both footers.
- `CLIAgentToolbarItemKind` (`cli_agent_footer/toolbar_item.rs`) replaces `AgentToolbarItemKind` in the CLI layout. Serde names are unchanged and the `ImageAttach` alias stays. `CLIAgentToolbarChipSelection::Custom` holds `CLIAgentToolbarItems`, which skips entries that no longer parse instead of rejecting the whole saved layout (both the serde path and the settings-file path). Layouts saved with `ModelSelector`, `NLDToggle`, `ShareSession` or any other removed item now load with those items dropped. The `agents.third_party.cli_agent_toolbar_chip_selection_setting` key and the `CLIAgentToolbarChipSelectionSetting` type name are unchanged.
- `ToolbarChipSelection` gained an associated `Item` type; `chip_configurator` no longer knows any item type. Editors implement `ConfigurableToolbarItem` (label, icon, context chip) and controls round-trip through their serialized form.
- The CLI layout editors moved to `cli_agent_footer/editor.rs` (`CLIAgentToolbarEditorModal`, `CLIAgentToolbarInlineEditor`). The workspace has a second modal and an `is_cli_agent_toolbar_editor_open` state for it. The agent-view editor keeps only its own mode.
- `AgentInputButtonTheme` and `ActiveMicButtonTheme` moved to the CLI footer module. The cloud-agent selectors and the agent footer import them from there.
- `settings_view/cli_agents_page.rs` no longer depends on `ai_shared.rs`: it carries its own toggle, switch, description-style and toolbar-editor helpers.
- `terminal/view.rs`: `is_rich_input_chip_in_cli_toolbar` reads `CLIAgentToolbarItemKind`.

**User-visible impact:** None for the CLI toolbar, Rich Input and the plugin chips. Stored CLI toolbar layouts that mention removed items keep working. The "third-party agent running in a cloud session" indicator no longer appears (cloud agents are removed).

**Notes:**
- `AgentToolbarItemKind::{NLDToggle, ShareSession}` and the `without_retired_items` shim stay for the agent-view layout only; they go with `AgentToolbarItemKind` in AI-27.
- Voice input stays in the CLI footer (`voice.rs`, `VoiceInput` item, `ToggleCLIAgentVoiceInput`); AI-13 deletes it.
- The plugin install/update chips and `write_install_log` are unchanged apart from moving; SWP-09 removes them.
- The `AgentView` overrides in `unregister_cli_agent_session_restores_unlocked_input_config` and `input_tests.rs::test_shell_lock_respected_when_slash_command_typed` stay: both exercise `ai/blocklist/input_model.rs`, which AI-26 owns.
- The CLI footer's chips take their `DisplayChipConfig` from `Input` without the ambient-agent model, since cloud sessions are going away.
## MCP (Model Context Protocol)
**Why:** MCP let the built-in agent call tools and read resources from MCP servers the user installed, from a Warp-hosted gallery and managed servers synced through Warp Drive (with team sharing and server-side OAuth client registration). The agent that consumed them is being removed, and the gallery, sharing and managed servers cannot work offline (ai.md AI-14).

**Removed:**
- `crates/mcp` (server runtime over `rmcp`, SSE/streamable-HTTP transports, OAuth including the loopback callback) and the `rmcp` dependency from `app`, `crates/ai` and `[workspace.dependencies]`; `handlebars`, `chrono`, `uuid` and `warp_errors` from `cloud_object_models`.
- `app/src/ai/mcp/` (the legacy and templatable server managers, gallery, file-based discovery for Claude, Codex, Warp and agent config files, installation persistence, parsing, logs, built-in servers) and the `TemplatableMCPServerManager`, `FileBasedMCPManager`, `FileMCPWatcher` and `MCPGalleryManager` singletons with their test-helper registrations.
- `settings_view/{mcp_servers_page*, mcp_servers/}` and `SettingsSection::AgentMCPServers` (nav entry, slug, palette page, saved-session slug), the "Auto-spawn servers from third-party agents" setting (`FileBasedMcpEnabled`) and its toggle, `MCPExecutionPath` (the login-shell PATH used to launch servers) and the code in `TerminalView` that fed it.
- The MCP Drive items (`drive/items/mcp_server{,_collection}.rs`), `DriveObjectType`/`WarpDriveItemId::MCPServer[Collection]`, `JsonObjectType::{MCPServer, TemplatableMCPServer}`, `cloud_object_models/src/mcp*.rs` (`MCPServer`, `TemplatableMCPServer` and their cloud models) and their branches in the sync queue, update manager, object client, persistence and `ServerCloudObject`; the MCP gallery GraphQL query fields and `create_managed_mcp_client_config`; the `active_mcp_servers`, `mcp_server_installations`, `mcp_environment_variables` and `mcp_server_panes` reads and writes (`ModelEvent::*MCP*`, `PersistedData::mcp_*`, `AppState::running_mcp_servers`, `MCP_SERVER_PANE_KIND` and the row structs). The tables stay until DB-1.
- The agent's `CallMCPTool` and `ReadMCPResource` actions, results and executors, their API conversions, persistence variants, redaction arms, permission checks, the request-time `MCPContext`, and the MCP tool-call and resource renderers in the AI block (`RequestedActionViewType`, the JSON tree view and `ui_components/json_tree.rs`). The MCP config file "protected path" write denial and the "open MCP config" button in code diffs went with them.
- `McpStaticConfig`/`McpOAuthProviderConfig` in `warp_core::channel` (and every binary's `mcp_static_config: None`), `ContextFlag::ShowMCPServers`, `ExecutionMode::can_inherit_process_path_for_mcp`, `AppExecutionMode::can_autostart_mcp_servers` and `warp_home_mcp_config_file_path` with the `~/.warp/.mcp.json` watcher.
- MCP OAuth deep links: `UriHost::Mcp` (`warposs://mcp/...`), `warposs://settings/mcp` and the `root_view:open_mcp_settings_*` actions.
- `/add-mcp`, `/mcp` and `/open-mcp-servers`, `TerminalAction`/`InputEvent::{OpenViewMCPPane, OpenAddMCPPane}`, the "Open MCP Servers" action, binding and menu items, the "Open Settings: MCP Servers" binding and the MCP agent tips.
- The MCP parts of execution profiles: `mcp_permissions`, `mcp_allowlist` and `mcp_denylist` (model, settings profile file, onboarding autonomy presets, the profile editor, the profiles page and the profile summary), and `AISettings::is_mcp_permission_editable`.
- Telemetry variants and payload types for MCP (`MCPServerAdded`, `MCPTemplateCreated`, ...).
- Figma MCP: the "Get/Enable Figma MCP" prompt chip, Figma-PNG detection (`ImageContext::is_figma`, `editor/view/figma_utils`), the Figma bundled skills catalog (`resources/bundled/mcp_skills`) and the `add-mcp-server` and `factory-mcp` bundled skills, `BundledSkillActivation::RequiresMcp`, `Icon::Figma[Colored]`.
- `warp_core::ui::external_product_icon` (brand icons that only MCP server cards used, including the Sentry one) and the unused Heroku, Notion, Resend, Sentry, You.com, Composio and Figma SVGs; `AvatarContent::ExternalProductIcon`, `RedNotificationDot::default_styles`, `CloudObjectUuid[Lookup]` and `semantic_creator`.

**Modified:**
- `GenericStringObjectFormat` in the GraphQL crate keeps the `JsonMCPServer` and `JsonTemplatableMCPServer` variants (the schema-bound enum needs every server value); the Drive sync paths skip them like any unknown format.
- Protobuf conversions ignore MCP tool calls from the server: the request no longer advertises `CallMcpTool`/`ReadMcpResource` tools and sends no MCP context.
- The Drive menu no longer lists MCP servers. The AI menu keeps only its rules item until AI-15 removes it.
- Persisted agent-action serialization drops the MCP variants (nothing deserialized them).

**User-visible impact:** No MCP servers page, `/add-mcp`, `/mcp`, `/open-mcp-servers`, MCP Drive folder, Settings > MCP servers, `warposs://settings/mcp` or MCP OAuth callback. Agent profiles have no "Call MCP servers" permission. Servers a user configured in `.mcp.json`, Claude or Codex config files are no longer started by the app (third-party CLI agents keep using their own config).

**Notes:**
- Cargo features and `FeatureFlag` variants named for MCP (`McpServer`, `McpOauth`, `FileBasedMcp`, `McpDebuggingIds`, `MCPGroupedServerContext`, `McpJsonTreeView`, `WellKnownMcpIds`, `FactoryMcp`, `FigmaDetection`) stay for FLAGS-1.
- Left for other tasks: `ToolCallStats::{read_mcp_resource_stats, call_mcp_tool_stats}` in `persistence::model` and the GraphQL usage query (AI-30/SRV-1); `mcp_servers` in `cloud_agent_config.rs` and `scheduled_ambient_agent.rs` (AI-18/AI-29); `mcp_servers_json` in the simple-integration GraphQL types and the schema files (SRV-1); the two MCP tips in `terminal/view/ambient_agent/tips.rs` (AI-17a); the `factory-files` and `claude-api` bundled skills that mention MCP (AI-11); the `.mcp.json` entry in the preview-config migration test (CFG-1); the MCP tables and columns in `persistence/schema.rs` and migrations (DB-1).
- `simple_logger`'s rotation support was added for MCP server logs and no longer has a caller.
## Launch, feature-intro and vertical-tabs intro modals
**Why:** These were marketing and onboarding surfaces for Oz, orchestration, the Warp Agent CLI and the agent inbox, or announced Warp product launches. None applies to an offline terminal without Warp AI.

**Removed:**
- `workspace/view/{launch_modal, openwarp_launch_modal, orchestration_launch_modal, agent_cli_launch_modal, feature_intro_modal}/`: the Oz "Introducing Oz" tab and modal, the OpenWarp, orchestration and Warp Agent CLI launch modals, and the bottom-right feature-intro popover with its `FEATURE_INTROS` registry.
- `workspace/hoa_onboarding/`: the vertical-tabs intro flow (welcome banner, vertical-tabs callout, agent-inbox callout, tab-config step) and its `HasCompletedHOAOnboarding` preference helpers.
- `OneTimeModalModel` state, triggers and accessors for all of the above, so the model now tracks only the build-plan migration, auto-handoff sleep and free-AI-removal modals (later tasks delete those). Also removed `check_and_trigger_all_modals`, `mark_free_ai_removal_notice_seen` and the handoff-chip toolbar migration (with the `DidAddHandoffChipToToolbar` setting), which lost their only caller when the AuthManager subscription went with the login removal.
- Settings: `did_check_to_trigger_agents_3_launch_modal`, `did_check_to_trigger_oz_launch_modal`, `did_check_to_trigger_orchestration_launch_modal`, `did_check_to_trigger_agent_cli_launch_modal`, `seen_feature_intro_ids` (all private one-time flags in `AISettings`) and `did_check_to_trigger_openwarp_launch_modal` (`GeneralSettings`).
- Actions, debug bindings and context flags: `WorkspaceAction::{OpenOzLaunchModal, ResetOzLaunchModalState, OpenOpenWarpLaunchModal, ResetOpenWarpLaunchModalState, OpenOrchestrationLaunchModal, ResetOrchestrationLaunchModalState, OpenAgentCliLaunchModal, ResetAgentCliLaunchModalState, OpenFeatureIntroModal, ResetFeatureIntroModalState, DismissFeatureIntroModal, ShowHoaOnboardingFlow}`, the Escape binding for the feature-intro popover and `FEATURE_INTRO_MODAL_OPEN`.
- The Workspace fields, focus helpers and render blocks for those modals, plus the `ModalWithTab` helper and the unused `update_toast_positioning`.
- Telemetry enum leftovers: `CloudModeEntryPoint::OzLaunchModal` and `InputUXChangeOrigin::ADELaunchModal`.
- Banner and promo images under `app/assets/async/png/` (`oz_*`) and `app/assets/async/png/onboarding/` (`openwarp_launch_banner`, `orchestration_launch_banner`, `agent_cli_launch_banner`, `custom_model_router_intro_banner`, `hoa_welcome_banner`).

**Modified:**
- The vertical-tabs panel now follows the `use_vertical_tabs` setting without the "keep open during HOA onboarding" exception, and the tab bar no longer has an onboarding-only always-visible rule.
- `terminal/view.rs`, `workspace/util.rs`: dropped the Oz launch modal checks.
- Three tests for the removed one-time modals were deleted from `one_time_modal_model_tests.rs`; the auto-handoff and free-AI-removal tests stay.

**User-visible impact:** No launch or "what's new" modal appears at startup, no feature-intro popover appears, and the vertical-tabs intro tour is gone. Stored one-time flags are ignored.

**Notes:**
- `FeatureFlag::{OzLaunchModal, OpenWarpLaunchModal, OrchestrationLaunchModal, AgentCliLaunchModal, HOAOnboardingFlow}` and their Cargo features stay for FLAGS-1.
- The build-plan migration, free-AI-removal and auto-handoff sleep modals are left to AI-16 and AI-17a. Nothing sets `has_completed_initial_modal_checks` any more, so the free-AI-removal notice can no longer open; AI-16 deletes it.
- `FeatureFlag::CodeLaunchModal` gates the unrelated code-toolbelt tooltip and is untouched.

## Onboarding: AI slides, callout tutorial and Get Started
**Why:** Onboarding sold Warp AI and Oz: it asked for an "intention" (agent-driven development or terminal), sent the user through model, autonomy and AI-access slides and a post-sign-in offer, then ran a callout tutorial in the terminal that ended by submitting `/init` or a prompt to an agent. None of that exists without accounts and Warp AI.

**Removed:**
- `crates/onboarding`: `agent_slide`, `ai_access_slide`, `ai_setup_slide`, `intention_slide`, `offer_slide`, `upgrade_auth_prompt`, `two_line_button`, the whole `callout/` module (the in-terminal tutorial, including its `/init` step), `components/` (callout and opt-out dialogs) and the `callout`/`callout_flow` examples.
- `OnboardingIntention` (and `AgentDrivenDevelopment`), `SessionDefault`, `AI_FEATURES`, `OnboardingAuthState`, `OfferVariant`, the model list, autonomy, `disable_oz`, the pricing promotion, the "Are you sure you don't want AI?" dialog, the plan-activated toast, the app-refocus refresh, and the `ai` crate dependency (`LLMId`). Also the unused `instant`, `log` and `warp_errors` dependencies.
- The "Terms of Service" disclaimer on the theme slide (a warp.dev link); the "opt out of analytics" wording had already gone with the login removal.
- Telemetry events for the removed slides, dialogs and callouts, and the account-first payload metadata.
- `app/src/ai/onboarding.rs`, `app/src/workspace/view/onboarding.rs` (`OnboardingTutorial`), `WorkspaceAction::{StartAgentOnboardingTutorial, AddGetStartedTab}`, `TerminalAction::OnboardingFlow` with its debug bindings, `Event::OnboardingTutorialCompleted`, and `AgentViewEntryOrigin::{Onboarding, OnboardingCallout}`.
- The Get Started pane (`pane_group/pane/get_started_{pane,view}.rs`, `LeafContents::GetStarted`, `IPaneType::GetStarted`, the persistence read and write), `app/src/coding_entrypoints/` (open, create-project and clone-repo buttons) and `TerminalView::{create_new_project, agent_clone_repository}`.
- The tab-config chip that only the vertical-tabs intro flow could show ("Access your tab configs here"), its dismiss action and bindings, the `SESSION_CONFIG_TAB_CONFIG_CHIP_OPEN` context flag, and the pending-tutorial state around the session config and params modals. The session config modal itself stays (debug-only for now).
- `view_components/callout_bubble.rs`: the bubble renderer and arrow types, which nothing uses any more; the checkbox and color helpers stay.
- Images that only the removed slides used (`onboarding/agent_intention/`, `welcome_agent.png`, `warp-logo-neutral.svg`).

**Modified:**
- `OnboardingView` (was `AgentOnboardingView`) hosts four slides: welcome, "Customize your Warp" (tab styling, tools panel, code review), "Customize third party agents" (CLI agent toolbar and notifications) and the theme picker. The last slide finishes onboarding. `SelectedSettings` is now a struct.
- Defaults follow the old terminal path: horizontal tabs, tools panel and code review off, CLI agent toolbar and notifications on. `show_conversation_history` is gone from the customize slide and from `apply_onboarding_settings`, which no longer touches AI settings, execution profiles or the default session mode.
- The welcome slide's subtitle no longer advertises agents.
- `Workspace::open_vertical_tabs_panel_if_enabled` is now called by `RootView` after onboarding completes.
- The workspace no longer creates a Get Started tab or starts a tutorial when a new window opens.

**User-visible impact:** First launch shows four slides and then the terminal. There is no AI choice, no tutorial in the terminal, no Get Started tab and no open/create/clone buttons on an empty window. A stale `get_started` tab in a saved session fails to restore until DB-1 deletes its rows.

**Notes:**
- `ai/agent_tips.rs` went in the separate "Agent tips" section below.
- `terminal/view/block_onboarding/onboarding_prompt_block.rs` has no AI content (it is the prompt-style chooser used by settings import), so it stays.
- `crates/onboarding/src/bin/main.rs` still builds as a demo of the four slides.
- `FeatureFlag::AgentOnboarding` still gates showing the slides at startup. `GetStartedTab`, `HOAOnboardingFlow` and `AccountFirstOnboarding` are no longer read. FLAGS-1 removes all four.
## Skills
**Why:** Skills are Markdown instruction files (`SKILL.md`) that Warp discovered on disk (`.agents/skills`, `.claude/skills`, `.codex/skills` and similar provider folders), bundled into the app, and handed to the built-in agent. They exist only to steer Warp's agent, which this fork does not ship. The third-party CLI agents keep handling their own `/skill` commands, so the slash-menu skill list for the CLI Rich Input is dropped too (decision D3).

**Removed:**
- `crates/ai/src/skills/` (skill parsing, providers, references, specs) and `app/src/ai/skills/` (`SkillManager`, its file watchers, bundled-skill loading, `resolve_skill_spec`, skill telemetry).
- `terminal/input/skills/` (the `/skills` and `/open-skill` inline selector) and `search/ai_context_menu/skills/` (the `@`-menu skills category), with `InputSuggestionsMode::SkillMenu`, `InlineMenuType::SkillMenu`, `QueryFilter::Skills` and `AIContextMenuSearchableAction::InsertSkill`.
- The `/skills` and `/open-skill` slash commands (`SlashCommandKind::{InvokeSkill, EditSkill}`) and skill-command detection while typing (`DetectedSkillCommand`, `SlashCommandEntryState::SkillCommand`).
- The agent's `read_skill` tool and executor (`AIAgentActionType::ReadSkill`, `ReadSkillResult`, `ReadSkillExecutor`), the `InvokeSkill` agent input, the `SkillInvoked` output message, the `Skills` agent context, and the skills field of `run_agents` requests and remote child launches.
- `CodeSource::Skill` and `SkillOpenOrigin` (`code/editor_management.rs`), the "Open skill" buttons on read-file and edit-file action rows, and the conversation details panel's skill section.
- The `RunTabConfigSkill` chain (code footer, code view, pane group, workspace): the tab-config editor footer with its `/update-tab-config` button, and its `FooterMode::TabConfig`.
- `WorkspaceAction::FixSettingsWithOz` and the "Fix with Warp Agent" buttons on the settings-file error banner and the settings sidebar alert, which invoked the bundled `modify-settings` skill. With them went the banner's secondary-button slot and `BannerButtonVariant`.
- The skill-provider force-included repository paths registered at startup and in test setup, `warp_core::paths::warp_home_skills_dir`, and the `~/.warp/skills` watch in `WarpManagedPathsWatcher` (with `filter_repository_update*`).
- `CLIAgent::supported_skill_providers` and `skill_command_prefix` (`terminal/cli_agent.rs`), the last `ai::skills` import outside the AI module.
- `resources/bundled/skills/` (thirteen bundled skills, including `claude-api`, `oz-platform`, `warpctrl` and `factory-files`), `resources/channel-gated-skills/` (dogfood-only skills such as `test-warp-ui`, which documented `--bin warp` and `--api-key`), and `script/copy_conditional_skills`.
- `is_tab_config_toml`, `AIQueryRouting::is_local` and `render_provider_icon_button`, which only the skill paths still used, and the `warp_managed_paths_watcher` tests (they covered only the skill-directory helpers).

**Modified:**
- `script/prepare_bundled_resources`, `script/windows/prepare_bundled_resources.ps1` and `flake.nix` no longer copy channel-gated skills or list the `claude-api` license. The channel argument is still accepted.
- Cloud-mode slash menu (`slash_commands/cloud_mode_v2_view.rs`): the Skills section is gone, leaving Commands as the only section; `apply_v2_slash_section_filter` and the originating-command reselection went with it (AI-17a deletes the rest).
- `input_context_for_request` no longer takes a conversation id (it only fed the skills-changed check). `SlashCommandRequest` no longer carries `InvokeSkill`.
- `app/resources/tab_configs/new_tab_config_template.toml` no longer suggests asking Oz to update the config.
- `TelemetryEvent`'s `AIAgentInput` mirror lost its `InvokeSkill` variant.
- Tests: deleted the skill-only suites and the `SkillManager` singleton from the test setup helpers; the remaining tests dropped their skill arguments.

**User-visible impact:** `/skills` and `/open-skill` are gone, as is the `@` menu's Skills entry. The Rich Input no longer lists skills for the running CLI agent; type the agent's own skill command. Settings-file errors show only "Open file". The tab-config editor has no agent button. A stored per-menu height for the skills menu is ignored (its key was `skill_menu`).

**Notes:**
- Left for AI-12/AI-17b/server API removal: `SpawnAgentRequest::{skill, runtime_skills}` and the task filter's `skill_spec` in `server_api/ai.rs`, and the `skill_spec` fields in `crates/cloud_object_models` (`cloud_agent_config.rs`, `scheduled_ambient_agent.rs`).
- Left for AUTH/SRV: `global_skills` in `warp_server_auth::User` and the GraphQL `get_user` query.
- Left for FLAGS-1: the `PRCommentsSkill`, `ListSkills`, `OzPlatformSkills`, `BundledSkills` and `SkillArguments` flags and their Cargo features; `impl.rs` now sends `supports_bundled_skills: false`.
- Left for the multi-agent API cleanup (AI-29): the proto-facing `ReadSkill`/`InvokeSkill` message and tool handling in `agent/api/convert_*`, `task/helper.rs` and `conversation_yaml.rs`. They are wire types from `warp_multi_agent_api`; nothing maps them to client actions any more.
- Left for a `repo_metadata` cleanup: the standing-query and force-included-path machinery in `crates/repo_metadata` (`standing_queries.rs`, `Entry::build_tree_with_standing_queries`, `register_force_included_paths`, `set_project_skill_provider_paths`, `RepoMetadataEvent::StandingQueryResultsUpdated`) existed for skill discovery and now has no callers.
- Left for SWP: the launch modals' copy mentioning skills (`oz_launch.rs`, `openwarp_launch_modal`), and dev-workflow docs in `AGENTS.md`, `CONTRIBUTING.md` and `FAQ.md` about coding-agent skills.

## AI plan documents and to-do popup
**Why:** Plans are documents the built-in agent writes, versions and syncs to Warp Drive as notebooks, and the plan pane, plan menu and to-do popup are the only ways to read and act on them. With the built-in agent going away they have no purpose.

**Removed:**
- `app/src/ai/ai_document_view.rs` (the plan editor, its version history and "attach to agent" actions), `pane_group/pane/ai_document_pane.rs` with `IPaneType::AIDocument`, `LeafContents::AIDocument` / `AIDocumentPaneSnapshot`, the deferred-pane restoration that only this pane used (`IPaneType::DeferredPlaceholder`, `process_deferred_panes`), and the `PaneGroup` plan-pane functions.
- `terminal/input/plans/` (the `/plan` picker menu: `InputSuggestionsMode::PlanMenu`, `InlineMenuType::PlanMenu`), the `@`-menu "Plans" category (`AIContextMenuCategory::Plans`, `AIContextMenuSearchableAction::InsertPlan`, `QueryFilter::Plans`) and the `<plan:...>` attachment inserted by "Attach to active session" on a plan notebook.
- `ai/agent/todos/popup.rs` (the to-do list popup), `ai/blocklist/prompt/plan_and_todo_list.rs` (the plan and to-do chip), `ContextChipKind::AgentPlanAndTodoList` and the agent footer entry that hosted it.
- `ai/document/orchestration_config_block.rs` (the orchestration config card on a plan) and its telemetry (`PlanConfigApprovalToggled`, `AgentProposedConfig`).
- `ai/blocklist/inline_action/create_or_edit_document.rs` (the "plan created" card in an AI block), the plan streaming preview in `AIBlock`, and the auto-open of the plan pane.
- Actions and events: `WorkspaceAction::{ToggleAIDocumentPane, HideAIDocumentPanes, OpenAIDocumentPane}`, `TerminalAction::{ToggleAIDocumentPane, ToggleTodoPopup, CloseTodoPopup}`, the `cmdorctrl-alt-p` / `cmd-meta-p` bindings, the "to view plan" hint in the agent message bar, and the matching terminal, input, block, footer and chip events.
- Persistence: the `ai_document_panes` reads and writes, `ModelEvent::SaveAIDocumentContent` and the `AIDocumentPane` / `NewAIDocumentPane` model types. `save_app_state` still clears `ai_document_panes` (foreign key to `pane_leaves`) until DB-1.
- Integration tests `test_copy_ai_document_as_markdown_from_overflow_menu` and `test_restored_ai_document_populates_code_block_after_first_layout`, with `integration_testing/ai_document.rs`.

**Modified:**
- `AIDocumentModel` keeps only what the agent's create, edit and read document actions need: the pane visibility tracking and the SQLite restore hook are gone.
- A session that was saved with a plan pane restores without it (the leaf fails with "Unrecognized pane kind", like the removed Rules and MCP panes).
- Stored agent toolbar layouts that list the plan and to-do chip no longer parse that entry, which falls back like any other unknown value.

**User-visible impact:** No plan pane, plan picker, plan or to-do chip, to-do popup or plan shortcut. Plan notebooks in Drive stay ordinary notebooks.

**Notes:**
- Left for AI-28/AI-29: `AIDocumentModel` (`app/src/ai/document/`) and the `CreateDocuments`, `EditDocuments` and `ReadDocuments` agent actions with their executors, history restore and conversation conversion. The plan says to delete `ai/document/` here, but those AI model modules stay until the agent core goes. `AIAgentTodoList` also stays with the agent.
- Left for DRV-3: `notebook.ai_document_id`, `AIDocumentId` in the notebook cloud model and GraphQL types, `DriveObjectType::Notebook { is_ai_document }`, `Notebook { is_plan }` in vertical tabs and the `is_plan` accessors in `notebooks/`.
- Left for AI-19: `OrchestrationConfigState::to_orchestration_config` is now only used by its tests. Left for DB-1: the `ai_document_panes` table.

## Warp Drive: environment-variable collections
**Why:** An environment-variable collection is a Warp Drive object that syncs through Warp's servers, and Drive is removed (user decision 1). Its entry points (the Drive index, the command palette and workflow parameterization) were already gone or depended on cloud objects.

**Removed:**
- `app/src/env_vars/` (README included) — the collection object model, `EnvVarCollectionManager` singleton, the editor pane view (variables, secrets from external managers, command dialog, unsaved-changes dialog), and the invocation block shown in the blocklist.
- `app/src/search/env_var_collections/` — the fuzzy matcher for collections.
- `pane_group/pane/env_var_collection_pane.rs`, `IPaneType::EnvVarCollection`, `LeafContents::EnvVarCollection`, `EnvVarCollectionPaneSnapshot`, `pane_group::Event::InvokeEnvVarCollection`, `PaneGroup::env_var_collection_pane_by_pane_id`, and the vertical-tabs `TypedPane` and `SummaryPaneKind` arms.
- `workflows/workflow_view/env_var_selector.rs`, the "Environment variables" dropdown in the workflow info box (`WorkflowsInfoBoxViewEvent`, `WorkflowsInfoBoxViewAction::SelectEnvironmentVariables`) and in the workflow and alias editors, `AliasBar::{set_current_env_vars, current_env_vars}`, and the argument-editor row that hosted the selector.
- `terminal/view.rs`: the collection block and everything that drove it (`pending_env_var_collection`, `env_vars`, `active_env_var_collection_block`, `cancel_env_var_block`, `add_env_var_block_to_blocklist`, `invoke_environment_variables`, `invoke_env_vars_in_{current_session,subshell}`, `set_and_execute_subshell_command`, `display_non_local_environment_variable_error`, `reset_focus_after_rich_block`), `RichContentMetadata::EnvVarCollectionBlock`, and the 60 s bootstrap timeout used for collection subshells.
- Terminal model: `BlocklistEnvVarMetadata`, `Block::{env_var_metadata, cloud_env_var_collection_state}`, `AfterBlockCompletedEvent::cloud_env_var_collection_id`, `TerminalModel::{set_env_var_collection_name, start_command_execution_from_env_var_collection}`, `SubshellInitializationInfo::env_var_collection_name`, `CommandExecutionSource::EnvVarCollection`, and `SubshellSource`. Subshell flags now carry the spawning executable name as a `String`.
- Input: `EnvVarCollectionState`, the environment-variable command prefix that the workflow info box could insert, and the `selected_env_vars` argument of `insert_workflow_into_input` and `reset_workflow_state`. Workflow aliases and up-arrow history no longer carry an env-var id into the input.
- `cloud_object_models::env_vars` (`EnvVar`, `EnvVarValue`, `EnvVarCollection`, the cloud and server aliases), `JsonObjectType::EnvVarCollection` and its `ENVVARCOLLECTION` string, the `env-vars` `ObjectType` string, `PersistedGenericStringObject::EnvVarCollection`, `ServerCloudObject::EnvVarCollection`, `QueueItem::UpdateEnvVarCollection`, the sync-queue create and dependency arms, the `UpdateManager` create, update, conflict, transfer and duplicate arms, the `CloudModel` collection accessors, `Workflow::default_env_vars`, and the GraphQL `JsonEnvVarCollection` arms in `server_api/object.rs` and `server/graphql/schema` (the format is now skipped like an unknown one; the enum itself stays for SRV-1).
- `DriveObjectType::EnvVarCollection`, `Icon::EnvVarCollection` with `env-var-collection.svg`, `BindingGroup::EnvVarCollection`, `QueryFilter::EnvironmentVariables` (the `env_vars:` palette filter) and their style arms.
- Telemetry variants `EnvVarCollectionInvoked` and `EnvVarWorkflowParameterization`, `EnvVarTelemetryMetadata` and `CommandSearchResultType::EnvVarCollection`.
- `NewEnvVarCollectionPane`, `EnvVarCollectionPane` and `ENV_VAR_COLLECTION_PANE_KIND` from `crates/persistence/src/model.rs`.
- Helpers only the collection views used: `view_components::alert::{Alert::basic, AlertConfig::error, AlertFlavor::Error}` and the `Alert` re-export, `ui_components::menu_button::highlight_icon_button_with_context_menu`, and the alias argument-editor width constant.

**Modified:**
- `terminal/model/session/command_executor/shared.rs` — new `serialize_variables_for_shell(pairs of (&str, &str), ShellType)`, the small `export` serializer that used to live in `env_vars`. The SSH `RemoteCommandExecutor` and the WSL executor use it for the environment and the `PATH` they prepend to a command; the output is unchanged.
- `terminal/bootstrap.rs` — `init_subshell_command` and the subshell script no longer take collection variables; the script starts with `export WARP_HONOR_PS1=...;`.
- `terminal/warpify/{mod,success_block}.rs` — `subshell_bootstrap_success_block_bytes` drops the collection check and its argument.
- `persistence/sqlite.rs` — `save_app_state` no longer writes collection panes and the restore path no longer reads them. It still clears the `env_var_collection_panes` table, which has a foreign key to `pane_leaves` (DB-1 owns the schema).
- `terminal/local_shell/mod.rs` — the `LocalShellState` doc no longer points to the removed secret-manager caller.
- `ai/blocklist/inline_action/requested_command_attribution.rs` — a citation of a collection is no longer matched against the command, and `is_command_copied_from_document` drops its `shell_type` argument (minimal compile fix; the module belongs to the AI tasks).
- `Block::is_eligible_to_tag_in_agent` and `Block::should_hide` no longer consult the collection metadata.

**User-visible impact:** Environment-variable collections can no longer be created, opened, invoked (in the current session or as a subshell) or attached to workflows and aliases, and the `env_vars:` filter in the command palette is gone. A saved tab that contained a collection pane is dropped on the next restore, because its pane kind is no longer recognized (the rest of the window restores normally).

**Notes:**
- Old `env_var_collection` rows in `pane_leaves`, the `env_var_collection_panes` table, `generic_string_objects` rows of type `ENVVARCOLLECTION`, `schema.rs` and the integration `tests/data/*.sqlite` fixtures are left for DB-1.
- `Workflow::Command::environment_variables` and the alias `env_vars` field stay for DRV-4; saving a workflow from the editor now writes `None` for the former.
- `WorkflowAliasEnvVarsAttached` in `server/telemetry/events.rs` no longer has an emitter and is left for TEL-4. `crates/graphql` `JsonEnvVarCollection` and the schema stay for SRV-1.
- `crates/local_control/src/protocol_tests.rs` keeps `"drive.env_var_collection.open"` as a negative test of an unknown action name.
- The external secret managers stay in this commit (their types moved to `cloud_object_models::external_secret` so it builds) and are removed in the next section.

## Warp Drive: 1Password and LastPass secrets
**Why:** The integration let an environment-variable collection resolve a variable from the `op` (1Password) or `lpass` (LastPass) CLI. Its only entry point was the collection editor, which is removed with Warp Drive (user decision 1), so nothing can reach it.

**Removed:**
- `app/src/external_secrets/` — `SecretManager`, the installed checks and the list and fetch commands for `op` and `lpass`, and the docs links.
- `app/src/search/external_secrets/` — the searchable secret list (data source, fuzzy matcher, search item, searcher and view).
- `cloud_object_models::external_secret` — `ExternalSecret`, `OnePasswordSecret` and `LastPassSecret`, which had moved out of the deleted `env_vars` module in the previous commit.
- `Icon::OnePassword` and `Icon::LastPass` with `onepassword.svg` and `lastpass.svg`.

**User-visible impact:** Secrets can no longer be picked from 1Password or LastPass in Warp, and the app no longer runs `op` or `lpass`. Users can still run those CLIs in a terminal.

**Notes:** Nothing else referenced these modules. The external secret types were never stored outside collection objects, so no data migration is involved (existing `ENVVARCOLLECTION` rows are left for DB-1).
## Session sharing: viewer, joins and shared-session model state
**Why:** Session sharing streamed a live terminal session through Warp's `sessions.app.warp.dev` relay, gated on a Warp account. SS-1 removed sharing a session; this change removes the other half, joining and viewing someone else's shared session (including viewing cloud-agent runs), and the shared-session state that the terminal model, input editor, panes and workspace carried for it. An offline build has no relay and no accounts, so none of this can run.

**Removed:**
- `app/src/terminal/shared_session/` (the viewer network, event loop and history model, the orchestration viewer model, presence manager and participant selections, shared handlers, agent-conversation replay, the `Manager` singleton and its heartbeat) and `app/src/terminal/view/shared_session/` (the `SharedSessionAdapter`, `Viewer`, the conversation-ended tombstone view, the cloud-conversation continuation and its routing helpers, and the viewer `TerminalView` impl). Also `terminal/view/inline_banner/shared_sessions.rs`, `ai/blocklist/controller/shared_session.rs`, `crates/warp_terminal/src/shared_session.rs` and the protocol `BlockId`/`BufferId` conversions in `warp_terminal`.
- Join entry points: `UriHost::SharedSession`, `WebIntent::SessionView`, `WarpWebLink::Session`, `RootView::join_shared_session_*`, `NewWorkspaceSource::SharedSessionAsViewer` (and retargeting a pending auth/onboarding workspace to it), `Workspace::add_tab_for_joining_shared_session`, the wasm `SimplifiedWasmTabBarContent::SharedSession`, `PaneGroup::{new_for_shared_session_viewer, create_shared_session_viewer, create_ambient_orchestration_child_pane, attach_execution_session_to_ambient_pane}` and the failed-viewer-child recovery, `WorkspaceAction::{CopySharedSessionLinkFromTab, OpenOrAttachAmbientAgentConversation}`, `TerminalAction::{OpenSharedSessionOnDesktop, CopySharedSessionLink, RequestSharedSessionRole, SharedSessionViewerAltScroll}`, and the `Workspace_ViewOnlySharedSession` binding predicates.
- `TerminalModel`: `shared_session_status`, `shared_session_source` and their helpers, the write-to-pty channel for viewers, agent-conversation replay markers, the scrollback loaders, `start_command_execution_for_shared_session`, `CommandStartKind::SharedSession`, `SizeUpdateReason::SharerSizeChanged` and the sharer-driven `natural_rows`/`natural_cols`, `Block::is_scrollback_block_for_shared_session`, the `update_old_blocks` argument of `BlockList::resize`, and the `TextSelectionChanged`/`AgentTaggedInChanged` event chains whose only consumers were broadcasts to viewers. `SharedSessionStatus` and `SharedSessionSource` go with the module. `Handler::should_validate_dcs_hook_session_id`, a bypass that only viewers used, is deleted.
- `Input`: viewer prompt, upload, freeze and unfreeze paths, the CRDT buffer replication (`latest_buffer_operations`, `DeferredRemoteOperations`, `buffer_block_id`), AI-query routing to a remote sharer (`maybe_route_ai_query_to_remote_target`), `CommandExecutionSource::SharedSession`, the cloud follow-up attachment upload, and the `SendAgentPrompt`, `CancelSharedSessionConversation`, `SubmitSetupFailureDebugFollowup` and `EditorUpdated` events.
- `TerminalView` and panes: the viewer banners and tombstones, the request-edit-access button, presence avatars and participant selection rendering, viewer sizing, the long-running-command interaction broadcast, `write_viewer_bytes_to_pty`, and the alt-screen and blocklist horizontal scrolling (`horizontal_clipped_scroll_state` through `block_list_element`, `block_list_viewport` and `ViewportState::new`) that existed to follow a viewer's window.
- The Ctrl-C "cancel the third-party harness" state machine in `CLIAgentSessionsModel` (`observe_ctrl_c_write`, the grace window, `CLIAgentSessionStatus::Cancelled` and its notification and task-sync arms) and the `CtrlCCancelsThirdPartyHarness` call site: its only trigger was a viewer's forwarded Ctrl-C.
- Server-side shared-session configuration (allowed by the orchestrator for SS-2): `session_sharing_server_url` and its overrides on `WarpServerConfig`/`ChannelState`, the `--session-sharing-server-url` flag and `SESSION_SHARING_SERVER_URL_OVERRIDE_ENV`, the integration-binary setting, and `ContextFlag::set_shared_session_only`.
- Drive and pane sharing leftovers: `ShareableObject::Session`, `UserKind::SharedSessionParticipant`, `TeamKind::SharedSessionTeam` and their `Role` conversions, `From<ProfileData> for UserProfileWithUID`, the pane-header shared-session link and QR-code events, and the telemetry variants for starting, stopping, joining, granting roles, jumping to a participant and copying a session link (`StartedSharingCurrentSession` and eight more) plus `OpenedSharingDialogEvent::session_id`.
- AI-side plumbing that only carried the viewer: exchange `response_initiator` and every `ParticipantId` argument of the `BlocklistAIController` send methods, `QueuedQuery`'s shared-session prompt rows, attachment preparation and `PromptReady`, the controller's startup-queue injection path (`route_native_startup_injection` and helpers) with `controller/startup_queue.rs`, `BaseUserQuery::{decode_b64, for_viewer, unattributed}`, `BlocklistAIHistoryEvent::LocalSharedSessionEstablished`, the `session_id` argument of `AIClient::update_agent_task` (and its GraphQL input field), the task-attachment download helpers in `ai/attachment_utils.rs`, `AgentViewEntryOrigin::SharedSessionSelection`, `EntrypointType::SharedSession`, `CLIAgentInputEntrypoint::SharedSessionSync`, `NotExecutedReason::WaitingOnSharer`, the cloud-routing indicator buttons of the agent footer, `QueuedPromptsPanel::can_send_prompt`, the cloud-mode tips that advertised session sharing and `--share`, and the participant avatar colour of the query row.
- Their tests, and the `test_latest_buffer_operations` integration test.

**Modified:**
- The cloud-mode composer pane no longer starts life as a shared-session viewer. `MockTerminalManager::create_cloud_mode_model` builds the dummy cloud-mode model with a static prompt, `TerminalModel::new_for_cloud_mode_shared_session_viewer` is now `new_for_cloud_mode`, `is_cloud_agent_conversation` and `ambient_agent_task_id` key only off the transcript status, and `PaneGroup::create_cloud_mode_terminal` loses its viewer argument.
- Ambient session ids are `uuid::Uuid` (`ambient_agent/model.rs`, `ambient_agents/{task,spawn}.rs`, `agent_conversations_model`). `SessionJoinInfo::from_task` no longer synthesizes a join link when the task has none.
- Child-agent restoration (`pane_group/child_agent`) drops the attach-live and viewer-join recovery paths; a remote child is restored from its transcript.
- `QueuedPromptsPanel` and `QueuedQuery` no longer distinguish shared-session rows; `QueuedQueryModel::ready_query`/`ready_head` became `unlocked_query`/`unlocked_head`.
- `AgentConversationsModel` merges `Attachable` into `ActiveUnattachable`.
- The command palette, `@` context menu, prompt chips and agent-input footer lose their "is a shared-session viewer" flags (file search and file categories are always offered).
- `SharedSessionActionSource::SharingDialog`, left behind by DRV-1, goes with the enum.

**User-visible impact:** Opening a `warp://shared_session/<id>` link or a web session link no longer joins anything, and cloud-agent runs can no longer be watched live in a pane (a run's transcript still opens read-only). Panes no longer show viewer banners, participant avatars, "Request edit access" or "Copy link". Nothing else changes for local sessions, except that horizontal scrolling of a block list or the alt screen no longer follows a viewer.

**Notes:**
- Kept on purpose: `UriHost::Session`. It is the `warp://session/<id>` pane-focus link built by `crates/warp_terminal/src/focus_env.rs`, not a sharing link. The editor's CRDT buffer API (`Operation`, `Event::UpdatePeers`, the peer-edit entry points) stays: it is editor-internal and only lost its consumers here; a later editor cleanup can drop it.
- Left for AI-28 (needs AI blocks gone): `AIConversation::{is_viewing_shared_session, set_is_viewing_shared_session}` and the viewer branches in `ai/agent/conversation.rs`, `history_model.rs` (`set_viewing_shared_session_for_conversation`), `terminal_pane.rs`, `cli_controller.rs`, `agent_message_bar.rs` and `ai_document_view.rs`; the action model's view-only mode (`BlocklistAIActionModel::{set_view_only, is_view_only, mark_action_as_remotely_executing, apply_finished_action_result}`, `CodeDiffState::ViewOnly`, `RequestedCommand::sync_command_from_result_for_viewer`, `AIBlock` diff population); and the finished-result guard in `handle_preprocess_actions_result`.
- Left for AI-19: the viewer-mode consumer registry, ancestor SSE seed and `FamilyDrainMode::Observer` in `orchestration_event_streamer.rs`, `VIEWER_MODE_SEED_FETCH_LIMIT`, and `viewer_mode_consumer_count_for_test`; the native-run queue barrier and steering delivery mode in `queued_query.rs` and `BlocklistAIController::{native_prompt_conversation_id, steer_head_prompt_for_request}` (their binder went with the agent SDK).
- Left for AI-29 (`server_api/ai.rs`): `AIClient::{prepare_attachments_for_upload, download_task_attachments, setup_failure_debug_authorization}` and the attachment request/response types, and `server_api/presigned_upload.rs` (no caller is left).
- Left for FLAGS-1: the `CreatingSharedSessions`, `ViewingSharedSessions`, `SharedSessionWriteToLongRunningCommands`, `AgentSharedSessions`, `SessionSharingAcls` and `CtrlCCancelsThirdPartyHarness` flags and the `creating_shared_sessions`, `viewing_shared_sessions`, `shared_session_long_running_commands`, `agent_shared_sessions` and `session_sharing_acls` Cargo features.
- Left for TEAM-1: `UserWorkspaces::update_session_sharing_enablement` and `session_sharing_policy` on the workspace tier. Left for TEL-4: `OpenedSharingDialog`/`SharingDialogSource` telemetry. Left for AUTH-1: `AuthViewVariant::ShareRequirementCloseable`. Left for SRV-1: the shared-session parts of the GraphQL schema.
- `Icon::QrCode` and its SVG have no user left (the QR code went with the Drive sharing dialog) and can go with the next icon sweep.

## Session-sharing protocol dependency
**Why:** After the sharer (SS-1) and viewer (SS-2) code is gone, nothing links against the relay's wire types, so the crate that defines them (a git dependency on a private Warp fork) has no reason to stay in the build.

**Removed:**
- `session-sharing-protocol` from `[workspace.dependencies]`, from the `[patch]` section, and from the `Cargo.toml` of `app`, `warp_terminal`, `warp_server_client`, `cloud_objects`, `cloud_object_models` and `cloud_object_persistence`; `lazy_static` from `cloud_object_persistence`'s dev-dependencies, which only its protocol-typed tests used.

**Modified:**
- `Cargo.lock` no longer lists `session-sharing-protocol`.

**User-visible impact:** None.

**Notes:** `cargo tree --workspace -i session-sharing-protocol` finds nothing. The build-time git dependencies on other `warpdotdev/*` forks are unchanged.

## Warp-distributed CLI-agent plugins
**Why:** The notification plugins for Claude Code, Codex, Gemini CLI and OpenCode are installed from Warp-owned sources (`warpdotdev/claude-code-warp`, the Codex marketplace, `github.com/warpdotdev/gemini-cli-warp`, the `opencode-warp` npm package). The chips that ran those installs made the app reach GitHub, npm and the agents' marketplaces on the user's behalf, which conflicts with the offline goal.

**Removed:**
- `terminal/cli_agent_sessions/plugin_manager/` (the per-agent install/update/version-check managers, the manual instruction texts, `PluginModalKind`, `MINIMUM_PLUGIN_VERSION` and its tests).
- `terminal/view/cli_agent_footer/plugin_chip.rs`: the "Enable notifications" / "Update Warp plugin" chips, their dismiss button and per-agent themes, the debounce timer, the install log written to the temp directory and the progress/success/error toasts.
- `terminal/view/plugin_instructions_block.rs`, `RichContentType::PluginInstructionsBlock` and `RichContentMetadata::PluginInstructionsBlock`, `WorkspaceView::open_plugin_instructions_pane`, and the `Event::OpenPluginInstructionsPane` / `InputEvent::{RegisterPluginListener, OpenPluginInstructionsPane}` / `CLIAgentFooterEvent::{PluginInstalled, OpenPluginInstructionsPane}` plumbing through `Input`, `TerminalView`, `TerminalPane` and `PaneGroup`.
- The plugin `CLIAgentFooterAction` variants (install, update, the two instruction panes, dismiss).
- The `[Debug] Install OpenCode Warp plugin` and `[Debug] Use local OpenCode Warp plugin` actions and bindings, and the helper that edited `~/.config/opencode/opencode.json`.
- The chip-dismissal settings `PluginInstallChipDismissedMap` and `PluginUpdateChipDismissedForVersionMap` (private, never in the settings file).
- Session state that only served the flows above: `CLIAgentSession::{plugin_version, remote_host, custom_command_prefix, is_remote}`, `CLIAgentSessionsModel::{record_plugin_auto_failure, has_plugin_auto_failed}`, the `plugin_version` field of the event payload and of the `CLIAgentNotification` wire struct, `TerminalView::active_session_remote_host`, and `TerminalModel::active_shell_launch_data` (added for plugin auto-install).
- Telemetry: `CLIAgentPlugin{ChipClicked, ChipDismissed, OperationSucceeded, OperationFailed, Detected}` and `PluginChipTelemetry{Kind, Action}`.
- Tests: the plugin manager tests, the failure-tracking and `plugin_version` session tests.

**Modified:**
- `CLIAgentFooter` no longer renders a plugin chip; the agent icon is followed directly by the configured toolbar items.
- `register_cli_agent_listener_without_session_start_event` (Codex and Grok proactive registration) sends a `SessionStart` event with an empty payload.
- The tooltip on "Auto show/hide Rich Input based on agent status" says "Requires a notification plugin for your coding agent".

**User-visible impact:** No install or update chip appears under Claude Code, Codex, Gemini CLI or OpenCode, and Warp no longer installs, updates or version-checks any plugin. A plugin the user installs by hand (for example from an enterprise mirror) still lights up rich status, notifications, vertical-tab status and Rich Input auto-toggle, because the OSC 777 / OSC 9 listener and the CLI-agent session model are unchanged. Agents without a plugin keep the plain toolbar, Rich Input and command detection.

**Notes:**
- Left for FLAGS-1: `FeatureFlag::{OpenCodeNotifications, CodexNotifications, GeminiNotifications}` now gate nothing (their doc comments still describe the chips), and `CodexPlugin` still gates Codex structured events in the listener.
- The `CLIAgentPlugin*` telemetry variants are deleted here with their callers; TEL-4 still deletes the rest of `events.rs`.
- Left for SWP-10: the `docs.warp.dev/terminal/integrations-and-plugins` link in `resource_center/sections.rs`.

## Voice input
**Why:** Voice input recorded audio from the microphone and sent it to Warp's `/ai/transcribe` endpoint (Wispr Flow behind Warp's server), billed against Warp's voice quota. It is an AI feature that depends on a Warp-hosted service, so it goes with the rest of Warp's AI. `WarpDriveContextEnabled` only controlled whether Warp Drive objects were attached to Warp AI requests; Warp Drive and Warp AI are both removed.

**Removed:**
- `crates/voice_input` (`cpal` capture, resampling, WAV/base64 encoding) and, with it, the `cpal`, `hound`, `rubato` and `objc2-av-foundation` dependencies.
- `app/src/voice/` (`Transcriber`/`VoiceTranscriber` singleton), `app/src/ai/voice/` (transcribe request/response types), `app/src/server/voice_transcriber.rs`, `ServerApi::transcribe` and `TranscribeError`.
- `editor/view/voice.rs`: the editor's voice state machine, the mic button and cursor icon, the "Try Voice Input" new-feature popup, `EditorAction::ToggleVoiceInput`, `EditorEvent::VoiceStateUpdated`, `VoiceTranscriptionOptions`, `EditorView::render_controls` (it could only ever return the voice button) and the modifier-key handling that started voice from a held key.
- `terminal/view/cli_agent_footer/voice.rs`, the footer's mic button, `ActiveMicButtonTheme`, `CLIAgentToolbarItemKind::VoiceInput`, `CLIAgentFooterEvent::InsertIntoCLIPty`, `UseAgentToolbarEvent::InsertIntoCLIPty` and `insert_text_into_cli_agent_pty` (only voice used them), `TerminalAction::ToggleCLIAgentVoiceInput`, and the toggle-key plumbing in the alt-screen and block-list elements.
- The mic button and voice events of `AgentInputFooter` and of the universal developer input button bar.
- Settings: `VoiceInputEnabled` (`agents.voice.voice_input_enabled`), `VoiceInputToggleKey` (`agents.voice.voice_input_toggle_key`), `VoiceInputLanguage` (`agents.voice.voice_input_language`, and the `VOICE_INPUT_LANGUAGES` catalog), `DismissedVoiceInputNewFeaturePopup`, `ExplicitlyInteractedWithVoice`, `EnteredAgentModeNumTimes` (only counted for the popup) and `WarpDriveContextEnabled` (`agents.knowledge.warp_drive_context_enabled`) with its `warp_drive_context_enabled` request field and keymap flag. The "Voice" category and the "voice input" toggle binding on the Warp Agent settings page go too.
- `/voice`, the voice agent tip, the `IS_VOICE_INPUT_ENABLED` keymap flag, `render_filterable_dropdown_item` (only the language picker used it), and `Icon::Microphone` with its SVG.
- Server-side voice fields: `warp_ai_policy.is_voice_enabled` (`UserWorkspaces::is_voice_enabled`, the gql fragment field and the two queries that selected it) and the `is_unlimited_voice`, `voice_request_limit` and `voice_requests_used_since_last_refresh` request-limit fields with `can_request_voice`.
- The macOS microphone entitlement (`com.apple.security.device.audio-input`) and `NSMicrophoneUsageDescription`, the AVFoundation link in `crates/warpui/build.rs`, `MicrophoneAccessState` and `microphone_access_state` from the platform delegates, `App::enable_windowless_microphone_access_query`, and the ALSA build dependency (`libasound2-dev`, `alsa-lib`) in `script/linux/install_build_deps`, `flake.nix` and CI.
- The tests that exercised voice: `test_voice_input_toggle_preserves_lock_state` (a known flaky test), `test_input_config_transitions` (the other one; it drove the voice toggle), the `VOICE_INPUT_LANGUAGES` catalog tests and the Hermes voice-paste test.

**Modified:**
- `AgentToolbarItemKind::VoiceInput` stays as an inert shim next to `NLDToggle`/`ShareSession` so a saved agent-view toolbar layout that lists it still loads; it renders nothing, is never offered, and `without_retired_items` drops it. AI-27 deletes it with `AgentToolbarItemKind`. Saved CLI-footer layouts need no shim: `CLIAgentToolbarItems` already skips unknown entries (a test now includes `VoiceInput`).
- `get_agent_tips` is gone; the tip pool is the fixed default list.
- The `gui` and `voice_input` Cargo features of `app` are kept but empty: `gui = []` and `voice_input = []`. Scripts and gates still pass `--features gui`. FLAGS-1 (AI-32) removes both.

**User-visible impact:** No microphone button, `/voice` command, voice settings or voice tip, and the app no longer asks for microphone access. Existing `agents.voice.*` keys in `settings.toml` are ignored.

**Notes:**
- Left for TEL-4: telemetry variants `ToggleVoiceInputSetting`, `VoiceInputUsed` and `CLIAgentToolbarVoiceInputUsed` in `server/telemetry/events.rs`.
- Left for AI-16: `AiCreditsUsageBucket::Voice` and its handling in `settings_view/billing_and_usage/`.
- `ai/agent/api/impl.rs` still sets the protobuf `warp_drive_context_enabled` field, to `false`; AI-29 deletes the request builder.
- The GraphQL schema file keeps its voice fields; the client no longer selects them.

## Agent tips
**Why:** The tips advertised Warp Agent, Oz and cloud-agent features, most with `docs.warp.dev` and `oz.warp.dev` links. They only ever rendered inside agent and cloud-mode UI.

**Removed:**
- `ai/agent_tips.rs`: the `AITip` trait, `AITipModel`, the `AgentTip` list and its keybinding, feature and AI-setting applicability rules.
- `terminal/view/ambient_agent/tips.rs` (the cloud-mode tip list) and the tip line on the cloud-mode loading screen.
- The tip line in `BlocklistAIStatusBar` (the "Tip:" text under the warping indicator, its refresh and click telemetry).
- The `ShowAgentTips` setting (`agents.warp_agent.input.show_agent_tips`), its toggle and binding on the Warp Agent settings page, and the `SHOW_AGENT_TIPS_FLAG` context flag.
- The `AITipModel` singleton and its revalidation subscriptions in `lib.rs`, and its registration in the test setup helpers.

**User-visible impact:** No tips appear under the agent status line or on the cloud-mode loading screen.

**Notes:**
- `TelemetryEvent::{AgentTipShown, AgentTipClicked, ToggleShowAgentTips}` stay in `server/telemetry/events.rs` for TEL-4.
- `FeatureFlag::AgentTips` and its Cargo feature stay for FLAGS-1. The `resource_center` tips (`TipsCompleted`) are the unrelated "Welcome tips" checklist and are unchanged.
## Cloud mode, ambient-agent terminal UI and handoff
**Why:** Cloud mode drove a terminal view as the front end of a Warp-hosted cloud agent run: it spawned the run on Warp's servers, joined the run's shared session as a viewer, showed setup progress, took follow-up prompts, inserted "conversation ended" tombstones and handed local conversations over to a cloud VM. An offline fork has no cloud agents to spawn or join (ai.md AI-17a, master decisions 1 and 9).

**Removed:**
- `app/src/terminal/view/ambient_agent/` (the `AmbientAgentViewModel`, its status/progress/loading/harness/setup UI, cancel and error handling, the first-time cloud setup and team-required views and the cloud tips in `tips.rs`, which also carried the Sentry mention), and every `ambient_agent_view_model` field, parameter and event across `TerminalView`, `Input`, the agent footer, blocks, context chips, model and profile selectors, the pane group and the shared-session viewer.
- The handoff pipeline: `ai/blocklist/handoff/` (snapshot upload, launch and touched-file collection), `workspace/auto_handoff.rs`, `Input`'s `&` handoff compose mode (`handoff_compose.rs`, `InputPrefixMode::CloudHandoff`, `InputAction::ActivateCloudHandoff`), the footer handoff chip and its toolbar-migration setting, `TerminalAction::{EnterCloudAgentView, CancelAmbientAgentTask}` and the `Workspace` actions `OpenLocalToCloudHandoffPane`, `AutoHandoffActiveAgentToCloud`, `AddAmbientAgentTab` and the debug handoff/sleep actions.
- Modals: the auto-handoff-on-sleep modal, the cloud-agent capacity modal, the auth-secret create/confirm dialogs and the "create environment" modals opened from the cloud composer.
- Composer and footer: `cloud_mode_v2_history_menu.rs`, `cloud_mode_v2_view.rs`, the cloud-mode-V2 rendering in `terminal/input/agent.rs`, `agent_input_footer/environment_selector.rs`, the host, harness and auth-secret selectors, the cloud model picker, the "Cloud Agent" entry in the new-tab menu and the `agent_management` agent-type selector.
- Shared-session continuation: `cloud_conversation_continuation*.rs` and `conversation_ended_tombstone_view*.rs`.
- Slash commands `/cloud-agent`, `/handoff`, `/host`, `/harness`, `/environment` and `/continue-locally`, their `SlashCommandKind` variants and the `NOT_CLOUD_AGENT`, `CLOUD_AGENT` and `CLOUD_MODE_V2_COMPOSER` availability bits.
- Pane and tab types: `LeafContents::AmbientAgent` and `AmbientAgentPaneSnapshot`, `pane_group/ambient_pane_restoration.rs`, `PanesLayout::AmbientAgent`, `PaneMode::Cloud` in launch configs and `TabConfigPaneType::Cloud`. The persistence model structs `AmbientAgentPane` and `NewAmbientAgentPane` are gone; the `ambient_agent_panes` table is left for DB-1 and is still cleared on save.
- Settings: `DefaultSessionMode::CloudAgent`, `ShouldForceDisableCloudHandoff`, `ShouldForceDisableAmpersandHandoff`, `AutoHandoffOnSleepEnabled`, `DidShowAutoHandoffSleepModal`, `did_add_handoff_chip_to_toolbar` and the "Cloud handoff" category of Settings > Warp Agent.
- URIs: `NewCloudAgentConversation`, `FocusCloudMode` and `AutoHandoffToCloud` (the `warp://` and `warpdev://` actions and their query parsing).
- Telemetry: `SpawnNewCloudAgent`, `AgentTypeSelectorOpened` and the cloud dispatch events of the launch modal.
- The "New agent" trial buttons on the billing pages and `submit_to_cloud_agent` in the onboarding callout.
- Tests for all of the above; `TerminalView::new_for_test_with_cloud_mode`, `TerminalModel::new_for_cloud_mode_shared_session_viewer` and `is_dummy_cloud_mode_session`, and the Oz-environment-startup-command hiding of blocks (`is_oz_environment_startup_command` and its `BlockList` state).

**Modified:**
- `TerminalView::is_cloud_agent_session` looks only at the model; `TerminalView::new` and `Input::new` lost their ambient parameters.
- A remote `StartAgent` child launch now creates a child conversation in an error state ("Remote child agents are not supported."). Completed remote children always restore as a passive transcript.
- `AgentToolbarItemKind::HandoffToCloud` stays as a load-only variant so saved toolbar layouts still deserialize; it is never offered or rendered. `DefaultSessionMode` values of `cloud_agent` in settings files no longer parse and fall back to the default.
- The orchestration "create environment" modal (`settings_view/handoff_environment_creation_modal.rs`) keeps only its orchestration entry point. Orchestration run cards no longer auto-open the create-secret modal.
- `render_agent_shortcuts_view` lost its cloud parameter; `InlineMenuView` lost `compact_layout`.

**User-visible impact:** No cloud-agent tab, pane, slash command, footer chip or `&` prefix; nothing to hand a conversation off to, and no sleep or capacity prompts. A tab config with `type = "cloud"` and a launch configuration with a cloud pane no longer load; a saved window whose pane was a cloud agent restores as an empty terminal.

**Notes:**
- Also resolves two STATUS leftovers: the handoff that spawned without a workspace snapshot went with the whole pipeline, and the Sentry mention in the ambient-agent tips went with `ambient_agent/tips.rs` (which also held the two MCP tips left there by the MCP removal).
- Pieces that belonged to AI-17b and had to go here to compile: `LeafContents::AmbientAgent` and its persistence, `ambient_pane_restoration`, the remote child launch and the ambient handling in `hydration.rs`.
- Left for AI-17b: `ai/ambient_agents/` and `AmbientAgentTaskId` plumbing (`TerminalView::ambient_agent_task_id`, `TerminalModel` task ids, `ConversationRestorationInNewPaneType::Historical.ambient_agent_task_id`), the cloud-load path of `agent_conversations_model.rs`, `AgentViewEntryOrigin::{CloudAgent, ThirdPartyCloudAgent}`, `OpenCloudAgentSetupGuide`, the `Tombstone*` and `SlashCommandContinueLocally` telemetry variants, `server_api` spawn structs and `presigned_upload.rs`.
- Left for the task that deletes `QueuedQueryModel`: `QueuedQueryOrigin::InitialCloudMode` and its locked-row handling in the queued-prompts panel. Left for AI-18: `harness_availability`, `auth_secret_types`, the auth-secret and environment pages. Left for AI-19: `ai/orchestration/remote_child.rs`. Left for FLAGS-1: the `CloudMode`, `CloudModeSetupV2`, `CloudModeInputV2`, `HandoffCloudCloud`, `HandoffLocalCloud` and `OzHandoff` feature flags. Left for DB-1: the `ambient_agent_panes` table.
## Tolerant stored inline-menu heights
**Why:** The per-menu drag-resize heights are stored as a map keyed by inline-menu type. Earlier removals deleted the `SkillMenu`, `PromptsMenu` and `PlanMenu` variants, so a settings file or stored value that still names `skill_menu`, `prompts_menu` or `plan_menu` failed to parse as a whole. The settings layer then dropped every stored height, logged an error and inhibited writes for the key, so later resizes were not saved either.

**Modified:**
- `InputSettings::inline_menu_custom_content_heights` now holds `InlineMenuHeights` (`app/src/settings/input.rs`), a newtype over `HashMap<InlineMenuType, f32>`. Reading it, from the settings file or from stored JSON, skips entries whose key is not a current `InlineMenuType` or whose height is not a number and keeps the rest. Writing is unchanged, and so are the setting's name, default and (private) visibility.
- `InlineMenuPositioningModel` unwraps and wraps the newtype when it loads and persists heights.
- Tests in `app/src/settings/input_tests.rs`: stale keys are ignored (file and serde forms), non-numeric heights are ignored, values round-trip, and a non-object value is still rejected.

**User-visible impact:** A stale `skill_menu`, `prompts_menu` or `plan_menu` entry no longer resets the other menus' heights or blocks saving new ones. Users without stale entries see no change.

**Notes:** Stale keys are dropped from the file the next time a height is saved.
## Repository metadata: standing queries and force-included paths
**Why:** `crates/repo_metadata` carried a second tree-building path that existed only for skill discovery. It kept "standing query" results (project skill files found below ignored or shallow directories) and a list of force-included paths that were built even when gitignored or past the depth or file budget. Skills are gone and nothing calls the registration functions, so the list was always empty and the results were never read.

**Removed:**
- `crates/repo_metadata/src/standing_queries.rs` (`StandingQueryDefinitions`, `StandingQueryContent`, `StandingQueryResults`, `StandingQueryResultsDelta`) and its tests.
- `Entry::build_tree_with_standing_queries` and its symlinked-skill bookkeeping, `matches_force_included_path`, `BuildTreeOptions::force_included_paths`, and the force-included-path parameter of `should_watch_repo_directory` and `repo_watch_filter`.
- `register_force_included_paths` and `set_project_skill_provider_paths` on `LocalRepoMetadataModel` and `RepoMetadataModel`, `DirectoryWatcher::register_force_included_paths`, the stored standing results and definitions, `standing_query_results` and the test helper `insert_test_standing_results`.
- `RepositoryMetadataEvent::StandingQueryResultsUpdated` and `RepoMetadataEvent::StandingQueryResultsUpdated`, with their match arms in `app/src/code/file_tree/view.rs` and `app/src/search/files/model.rs`.
- Tests that only covered force-included or skill behavior (ignored skill directories loaded for a provider path, force-included watch descent, budget exemption for force-included paths, standing-query deltas, skill symlink refreshes).

**Modified:**
- `Entry::build_tree_with_options` (was the private `build_tree_with_force_included_paths_and_ancestor`) is the single tree-building entry point; `compute_file_tree_mutations` no longer returns standing results.
- Ignored directories are now always unloaded placeholders under `IncludeLazy`, and the file budget applies to every directory. Both were already the behavior whenever no force-included paths were registered, which is always.

**User-visible impact:** None. The file tree, `@`-context file search and repository watchers build and update the same trees as before.

**Notes:** Closes the `repo_metadata` item left by the Skills section.
## AI credits, usage, billing and promotions UI
**Why:** Without Warp accounts and Warp-hosted models there are no credits to meter, buy or display. The models behind these surfaces polled Warp's servers for request limits, credit availability and bonus grants, and the surfaces pushed users toward plans, top-ups and Warp-run promotions.

**Removed:**
- `ai/{request_usage_model, credit_availability, pricing_promotion}` and the `AIRequestUsageModel` and `PricingPromotionState` singletons, with their registrations in `lib.rs` and the test setup helpers.
- `terminal/buy_credits_banner.rs` and `terminal/enable_auto_reload_modal.rs`: the "buy credits" banner above the input, the auto-reload modal and the events that carried them from the input up to the workspace (`OpenAutoReloadModal`). The `BuyCreditsBannerOpen` binding context is gone too.
- `workspace/bonus_grant_notification_model.rs` and its toast.
- `ai/blocklist/usage/`: the per-conversation usage popover, the usage footer and its rollup, and the per-turn "Turn" panel. In the agent view this took the usage button, the context-window button and the prompt-cache-expiry dot, plus the `TerminalAction::ToggleUsageFooter` and `AIBlockAction::{ToggleIsUsageFooterExpanded, ToggleIsTurnPanelExpanded, SetIsTurnPanelExpanded}` actions and the matching block and rich-content events. The block's refund notice ("We've refunded you N credits") and the negative-feedback refund mutation went with it.
- `ai/blocklist/prompt/prompt_alert.rs`, the "out of credits", spend-limit, delinquent and offline chip in the input footers.
- `settings_view/billing_and_usage*` (the page, its v1/v2 dispatch, usage history, overage-limit modal and billing-cycle sections), `SettingsSection::BillingAndUsage`, its nav entry, the `workspace:show_settings_billing_and_usage_page` binding and the `warp://settings/billing_and_usage` deep link. A stored "Billing and usage" page slug now opens the default page.
- `workspace/view/{free_ai_removal_modal, build_plan_migration_modal, codex_modal}.rs`, their debug actions and bindings, `OneTimeModalModel`'s free-AI-removal and build-plan-migration triggers, `warp://codex`, and `AgentViewEntryOrigin::CodexModal`.
- The `/usage`, `/cost`, `/manage-billing` and `/upgrade` slash commands.
- Settings: the quota-reset banner state (`AIRequestQuotaInfo`, `CycleInfo`, and the `AISettings` methods that maintained them, plus the "Monthly AI credits reset" popup on the prompt chips), `did_check_to_trigger_free_ai_removal_modal`, `build_plan_migration_modal_dismissed` and `bonus_grants_shown`.
- Server and GraphQL: `AIClient::{get_request_limit_info, get_ai_credit_availability, get_conversation_usage_history, provide_negative_feedback_response_for_ai_conversation}` and their queries and mutations, the `aiCreditAvailability` field on the workspaces-metadata query and its piggyback into `UserWorkspaces` and `TeamUpdateManager`, the unused `generateDialogue` mutation, and the `use_computer_stats` field of the conversation tool-usage metadata (in `persistence` and `warp_graphql`).
- The usage widget on the Agent profiles page, the AI credit limits in the team-deletion and leave/remove-member confirmations (`TeamDeleteDisabledReason::RemainingBonusCredits`, the `*ReloadCredits` dialog variants), the free-credits banner of the cloud-agent setup form, and the `Warp` review destination in code review (comments are sent only to a running CLI agent).
- The plan header presentation helper and `ui_components/tab_selector.rs` (used only by the billing page), and unused `FeaturePopup::alert_icon` and `Dropdown::with_drop_shadow`.

**Modified:**
- `AgentToolbarItemKind::{ContextWindowUsage, UsageSummary}` stay as unrendered variants so stored toolbar layouts still deserialize, like `NLDToggle`; they are no longer offered, in the defaults or in the editor.
- `FailedOutputPresentation::OutOfCredits`, its Subscribe button and the "won't count towards your usage" notice are gone; a quota-limit error renders as a plain message. `should_show_failed_output_usage_notice` became `should_show_failed_output_debug_footer` because it also gated the debug footer.
- `AgentMessageBar` and `TerminalInputMessageBar` no longer render promotion pills, so they have no typed actions and are created with `add_view`.
- Settings navigation tests that used Billing and usage as the page after the Agents group now use the next remaining page.

**User-visible impact:** No credit balances, usage totals, billing page, upgrade prompts or promotional modals appear anywhere. The `/usage`, `/cost`, `/manage-billing` and `/upgrade` commands and the `warp://codex` and `warp://settings/billing_and_usage` links no longer exist.

**Notes:**
- Left for BILL-1: `app/src/pricing/` (`PricingInfoModel::{addon_credits_options, promotion_message}` are now unused), `UserWorkspaces::{purchase_addon_credits, refresh_ai_overages, update_addon_credits_settings, purchase_policy}` and their events, `SunsettedToBuildDataUpdated`, `WorkspaceAction::ShowUpgrade`, the add-on credit and usage-based-pricing workspace settings and billing-cycle data, `AdminActions`, the `billing_and_usage_page_v2` Cargo feature and `FeatureFlag::BillingAndUsagePageV2`.
- Left for AI-17a: `CloudAgentCapacityModal`'s billing link, `show_out_of_credits_modal`, `CloudAgentStartupFailure::OutOfCredits`. Left for AI-17b: `PlatformErrorCode::InsufficientCredits`.
- Left for AI-21 and AI-30: `UsageDisplayUnit`, `format_usage`/`usage_label`/`format_credits` (used by the conversation details panel and the agent management view), `AIConversation::{turn_panel_data, turn_panel_records, usage_totals}` and the `ConversationUsageMetadataUpdated` history event.
- Left for AI-22 and AI-29: `AISettings::can_use_warp_credits_for_fallback` (the "Warp credits as BYOK fallback" switch on the Warp Agent page and the `allow_use_of_warp_credits` request field).
- Left for TEL-4: telemetry variants whose callers are gone (`AutoReloadModalClosed`/`AutoReloadModalAction`, `OutOfCreditsBannerClosed`/`OutOfCreditsBannerAction`, `CodexModalOpened`, `CodexModalUseCodexClicked` and the buy-credits, usage-popover and free-AI-removal events).
- The old free-AI-removal telemetry and the `FreeAiRemovalModalVariant` enum are deleted with the modal.

## Cloud notebooks
**Why:** Cloud notebooks are Warp Drive objects: they are stored, synced and shared through Warp's servers, and the offline build removes Drive entirely (user decision 1). Local markdown files opened in the rendered viewer (`notebooks/file`, which uses `notebooks/editor`) are not Drive objects and stay.

**Removed:**
- `notebooks/{notebook.rs, notebook/details_bar.rs, manager.rs, active_notebook_data.rs}` with their tests — `NotebookView` (the editable cloud notebook with title editor, details bar and edit-access banner), the `NotebookManager` singleton (which loaded cloud notebooks at startup, tracked open panes and saved on quit) and `ActiveNotebookData`.
- `pane_group/pane/notebook_pane.rs`, `IPaneType::Notebook`, `NotebookPaneSnapshot::CloudNotebook`, `Workspace::{open_notebook, add_tab_for_cloud_notebook}`, `WorkspaceAction::OpenNotebook` and the notebook pane kind in vertical tabs (`TypedPane::Notebook`, `SummaryPaneKind::Notebook`, the `is_plan` icon).
- `search/notebooks/` (fuzzy matcher and data source), `search/notebook_embedding/` (the "Embed" picker) and `search/ai_context_menu/notebooks/`, with `QueryFilter::Notebooks` (`notebooks:` / `n:`), `AIContextMenuCategory::Notebooks` and `BindingGroup::Notebooks`.
- Embedded Drive workflows in the markdown editor: `notebooks/editor/{embedded_item.rs, embedding_model.rs}`, the "Embed" item in the block insertion menu, `EditorViewAction::{OpenEmbeddedObjectSearch, RemoveEmbeddingAt, EditWorkflow}`, the matching events, `RichTextEditorConfig::embedded_objects_enabled`, the editor model's `CloudModel` subscription and `Icon::EmbedBlock` with `block-embed.svg`.
- `WorkflowType::Notebook` and `WorkflowSource::Notebook`.
- `DriveObjectType::Notebook { is_ai_document }` and its colour.
- Edit access ("baton") for notebooks: `UpdateManager::{grab_notebook_edit_access, give_up_notebook_edit_access, update_notebook_title}`, `ObjectOperation::TakeEditAccess`, `ObjectClient::{grab,give_up}_notebook_edit_access` with their GraphQL mutations, `CloudViewModel::object_current_editor` (`Editor`, `EditorState`), and `CloudModelEvent::NotebookEditorChangedFromServer`.
- The plan "Open plan" artifact button and its `OpenPlan` / `OpenPlanNotebook` events, `ArtifactType::Plan`, and `MenuSource::TextEditor` in the notebook context menu (only the notebook title used it).
- Integration tests `test_notebook_pane_tracking`, `test_close_notebook_tab`, `test_close_notebook_window`, `test_restore_snapshot_with_notebooks` (with `restored_notebooks.sqlite`) and the editable-Mermaid notebook test; `integration_testing/notebook/` and `view_getters::notebook_view`.

**Modified:**
- `cloud_object/notebook_model.rs` — the `CloudModelType` impl for `CloudNotebookModel` moved here from `notebooks/mod.rs`, next to the rest of the cloud-object code that DRV-5 deletes.
- Notebook command blocks now run as `WorkflowType::Local` with `WorkflowSource::Local`.
- `notebooks/telemetry.rs`, `NotebookLocation` — cut down to what the file viewer sends (`NotebookLocation` is `LocalFile` only).
- `persistence/sqlite.rs` — a `notebook_panes` row without a local path (a cloud notebook pane) fails to restore, like the removed AI document pane; its leaf is dropped.
- Context-menu tests moved from `notebooks/context_menu_tests.rs` to the file viewer (`notebooks/file/mod_tests.rs`), and pane-group and workspace tests that used a notebook pane as a generic pane use a file pane.
- `test_interleaving_command_and_embedding` became `test_interleaving_command_and_code_blocks`.
- `assert_cloud_preference_exists` moved to `integration_testing/cloud_object`, `assert_open_in_warp_banner_open` to `integration_testing/terminal`.

**User-visible impact:** Cloud notebooks in the local database can no longer be opened, and a saved window with a cloud notebook pane restores without it. The rendered markdown viewer, its context menu, find bar and runnable command blocks are unchanged, except that a `warp-embedded-object` block in a markdown file is no longer rendered. The `@` menu has no Notebooks category and command search has no `notebooks:` filter. "Open plan" buttons no longer appear on plan artifacts.

**Notes:**
- Left for DRV-5: the cloud-object side of notebooks (`CloudNotebook` / `CloudNotebookModel`, `ObjectType::Notebook`, `ModelEvent::Upsert{Notebook,Notebooks}`, the SQLite notebook reads and writes, `QueueItem::UpdateNotebook`, the notebook create, update and owner-transfer requests, `CloudModel::get_notebook*`). Generic tests in `update_manager_tests`, `sync_queue_tests` and `model_tests` still use notebooks as sample objects. GraphQL notebook types go with `crates/graphql` (SRV-1).
- Left for AI-28/AI-29: `CloudNotebookModel::ai_document_id` and `conversation_id` (and `AIDocumentId` in the notebook cloud model and GraphQL types). `AIDocumentModel` still creates and reconciles plan notebooks through them, and `<plan:...>` attachments and plan-restore in the blocklist controller read them. They can go once that model does. `Artifact::Plan.notebook_uid` stays for the same reason.
- `ContentEditability::RequiresLogin` ("Sign in to edit") stays for the workflow view (DRV-4) and `CloudViewModel`; its notebook tooltip went with `NotebookView`. The anonymous-user object-limit prompts were removed with Drive (DRV-1); `TelemetryEvent::AnonymousUserHitCloudObjectLimit` is left for TEL-4, and the shared-notebook tier limits (`UserWorkspaces::has_capacity_for_shared_notebooks`, `SharedNotebooksPolicy`) for TEAM-1/BILL-1.
- `uri::parse_url_paths` was already deleted with the Drive deep links (DRV-1), so nothing was left to remove.
- Left for TEL-3/TEL-4: `NotebookTelemetryAction`, `NotebookActionEvent`, `NotebookTelemetryMetadata` and the telemetry calls in the file viewer; `WorkflowSelectionSource::Notebook`.
- The editor crates still parse `warp-embedded-object` fenced blocks (`crates/editor`, `crates/markdown_parser`); with no conversion registered the buffer skips them, so a markdown file containing one renders without that block. Removing the parser support is left for the sweep.

## Integration test triage
**Why:** `cargo nextest run --workspace --features warp/gui -E 'package(integration)'` ended with failures. Each one was re-run alone and compared with the project baseline commit `cb2416204` to tell regressions from failures that predate the project.

**Removed:**
- `test_create_personal_workflow_pane_from_command_palette` and `test_create_team_workflow_pane_from_command_palette` (`crates/integration/src/test/workflows.rs`, registered in `tests/integration/ui_tests.rs` and `src/bin/integration.rs`). They ran the "Create a New Personal Workflow" and "Create a New Team Workflow" command-palette actions, which went with the Warp Drive panel, menus and actions. Both pass at baseline.
- Test helpers with no caller left: `assert_no_workflow_pane_open`, `assert_no_team_workflow_pane_open`, `assert_open_workflow_pane_count_equals`, `assert_open_team_workflow_pane_count_equals` (`app/src/integration_testing/workflow/assertion.rs`) and `go_offline`/`go_online` (`app/src/integration_testing/assertions.rs`).

**User-visible impact:** None. Test-only change.

**Notes:**
- Still failing, unchanged, and they also fail at baseline: `shell_integration_tests::{test_ssh_into_sh, test_ssh_into_ash, test_ssh_wrapper_into_bash, test_ssh_wrapper_into_zsh}` and `ui_tests::test_ssh_with_shell_override`. They SSH to a VM in Warp's GCP project (`warp-ssh-integration-testing`) through `gcloud compute start-iap-tunnel`, so they need the `gcloud` CLI, Google credentials and network access. They time out at "Wait for password prompt". They can only pass with that infrastructure and are expected to fail in this offline fork. The remote-subshell tests that use the same tunnel (`test_can_bootstrap_remote_{bash,zsh}_subshell`) are already `#[ignore]`d.
- The settings-file tests that were flaky under machine load (`test_settings_file_hot_reload_applies_new_values`, `test_settings_file_migration_from_native_store`, `test_execution_profiles_load_from_settings_file`, `test_execution_profile_model_persists_and_hot_reloads_settings_file`, `test_preview_config_dir_migration`) passed in both full runs and alone. Re-run them alone if they time out under load.
- Left for DRV-4/TEAM-1: the tests that still drive cloud objects, teams or the RTC websocket (`crates/integration/src/test/websockets.rs`, `join_a_workspace`, `create_a_personal_workflow`) still pass but cover code those tasks delete; `WorkflowView::is_team_workflow` has no test caller left.

## Persisted values of removed enum variants
**Why:** Removing a variant from an enum that is (de)serialized into user data makes every stored value that names it fail to parse. The settings layer then drops the whole setting, logs an error and, for the settings file, blocks writes to that key (this is what hid every inline-menu height behind one stale key). This section is the audit of `git diff cb2416204..offline-terminal` for such enums, and the fixes for every case that was worse than "that one value falls back to its default or is skipped".

**Audit (type: removed variants; where persisted; behavior on a stale value):**

| Type | Removed variants | Persisted in | Behavior on a stale value |
|---|---|---|---|
| `InlineMenuType` | `PromptsMenu`, `SkillMenu`, `PlanMenu` | settings file / stored JSON (`inline_menu_custom_content_heights`) | Was: whole setting lost, writes blocked. Fixed earlier by AI-11b (`InlineMenuHeights`). |
| `TipAction` (in `Tip`) | `AiCommandSearch`, `WarpAI` | private preference `WelcomeTipsFeaturesUsed` (`HashSet<Tip>`) | Was: whole set lost, welcome-tip progress reset. **Fixed**: `LenientSet<Tip>`. |
| `ContextChipKind` | `AgentPlanAndTodoList` | custom prompt (`PromptConfiguration.chips`), CLI-agent toolbar layout, agent toolbar layout, block `prompt_snapshot` JSON | Prompt, stored JSON: chip skipped already. Prompt, settings file: **was whole prompt setting lost, writes blocked; fixed** (`LenientVec<PromptChip>`). CLI-agent toolbar: entry skipped already (test added). Agent toolbar: AI-27 (shims). Block prompt snapshot: that block's snapshot alone is dropped. |
| `LeafContents` pane kinds (`get_started`, `ai_document`, `ai_memory`, `ambient_agent`, `env_var_collection`, `mcp_server`) and cloud notebook panes (a `notebook` row without a local path) | those panes | sqlite `pane_leaves.kind` | Was: the whole tab was dropped (and the active tab index shifted). **Fixed**: only the pane is skipped; a split collapses to its remaining pane; a tab with nothing left is dropped and the active tab index follows its tab. |
| `mcp_server_panes` rows | pane kind removed by AI-14 | sqlite `mcp_server_panes` (FK to `pane_leaves`) | Was: every later `save_app_state` failed on the foreign key, so the session was never saved again. **Fixed**: the delete is back in `save_app_state` (DB-1 drops it together with the table). |
| `Workflow::AgentMode` | `AgentMode` (`type: agent_mode`) | `~/.warp/workflows` and project `.warp/workflows` YAML; sqlite `workflows.data` | YAML: was the whole file lost, including its other documents. **Fixed**: only unsupported documents are skipped. sqlite: that row is skipped. |
| `DefaultSessionMode` | `CloudAgent`, `DockerSandbox` | settings file (`default_session_mode`) | Setting falls back to its default, writes to the key blocked. Excluded (AI-17b). |
| `TabConfigPaneType` | `Cloud` | `tab_configs/*.toml` (`type = "cloud"`) | That tab-config file fails to load and is reported. Excluded (AI-17b). |
| `AgentToolbarItemKind` | voice, share-session, NLD, model selector and other agent items | settings file / stored JSON (agent toolbar layout) | Excluded (AI-27, has shims). |
| `LeftPanelDisplayedTab` | `WarpDrive` | sqlite `panels.left_panel` JSON | That tab's left-panel state falls back to the default. |
| `CodeSource` | `ProjectRules`, `Skill` | sqlite `code_panes.source_data` JSON | Source dropped, the code pane still restores. |
| `ShellLaunchData` | `DockerSandbox` | sqlite `terminal_panes.shell_launch_data` JSON | Launch data dropped, the pane restores with the default shell. |
| `AIAgentContext` | `Skills` | sqlite `ai_queries.input` JSON (up-arrow history) | That history entry is skipped. |
| `JsonObjectType`, `GenericStringObjectFormat` | env-var collection, AI fact, MCP server, templatable MCP server | sqlite `object_metadata.object_type` strings | Rows skipped. |
| `CLIAgent` | `WarpTui` | `agents.third_party.cli_agent_toolbar_enabled_commands` values (names) | `CLIAgent::from_serialized_name` falls back to `Unknown`. |
| `PaneMode` | `Cloud` | launch-config YAML `pane_mode` (the app only ever writes `terminal`) | That launch-config file is skipped with a warning. |
| `SettingsSection` | `Account`, `Referrals`, `SharedBlocks`, `WarpDrive`, `AgentMCPServers`, `Knowledge`, `CodeIndexing` | sqlite `settings_panes.current_page` slug | `from_slug` misses, the pane opens on the default page. |
| Keybinding action names (strings) | every removed action | `keybindings.yaml` | The entry has no editable binding to attach to and is ignored; the rest of the file applies. Tests added. |
| `ThemeKind` | none (the referral themes keep their persisted variant names) | settings file | Not affected. |

Not persisted anywhere (runtime, telemetry or protocol only): `PaletteMode`, `IPaneType`, `ModalType`, `EntrypointType`, `LspEnablementSource`, `CodeContextLocation`, `FileWritePermissionDeniedReason`, `PersistedAIAgentActionType` (no reader), `SlashCommandKind`, `TelemetryEvent` and the `*Action`/`*Event` enums. sqlite readers for cloud objects, AI queries, object actions, workspace metadata, language servers and conversations were checked and skip bad rows individually.

**Modified:**
- `settings_value`: new `LenientVec<T>` and `LenientSet<T>`. Both read with serde and with `SettingsValue::from_file_value`, skip entries that fail to parse, and reject non-lists. They are the collection counterpart of `CLIAgentToolbarItems` and `InlineMenuHeights`.
- `PromptConfiguration.chips` is a `LenientVec<PromptChip>`; the hand-written serde-only `deserialize_prompt_chips` is gone. The `WelcomeTipsFeaturesUsed` setting is a `LenientSet<Tip>`.
- `app/src/persistence/sqlite.rs`: `read_node` / `read_root_node` return `Option`. Unrecognized leaf kinds are skipped with a warning; a branch keeps its remaining children and collapses into a lone child. `read_sqlite_data` no longer shifts the active tab index when tabs are dropped and clamps it. `save_app_state` clears `mcp_server_panes` again.
- `app/src/user_config/util.rs`: workflow files are parsed document by document (`WorkflowDocument`), skipping unsupported documents.
- Tests: `persistence/sqlite_tests.rs` (removed pane kinds keep the window, the tab and the surviving panes and keep the active tab; a stale `mcp_server` row does not block saving), `context_chips/prompt_tests.rs` (both storage forms), `terminal/general_settings_tests.rs`, `user_config/util_tests.rs`, `cli_agent_footer/toolbar_item_tests.rs`, `keyboard_tests.rs`, `warpui_core` `keymap_tests.rs`, `settings_value` `lib_tests.rs`.

**User-visible impact:** Users upgrading with a saved session that had a Get Started, plan, memory, cloud-agent, env-var or MCP pane open keep their other panes and tabs, and their session keeps being saved. A custom prompt or welcome-tip progress that mentioned a removed chip or tip survives. A workflow file that mixes normal and agent-mode workflows still loads the normal ones.

**Notes:** `DefaultSessionMode` and tab-config `type = "cloud"` (AI-17b) and `AgentToolbarItemKind` (AI-27) are left to their owners; both need the same treatment or a documented decision. DB-1 removes the `mcp_server_panes` delete in `save_app_state` when it drops the table. Stale `mcp_server` / `get_started` / `ai_*` / `ambient_agent` / `env_var_collection` rows stay in the database until the next session save clears them.

## Ambient-agent task model, cloud-load path and restoration
**Why:** After cloud mode and handoff went (AI-17a), the rest of the ambient-agent client was unreachable: the code that spawned runs, uploaded attachments, authorised GitHub, fetched and polled the run list, and threaded a run's task id through terminal, pane and workspace state (ai.md AI-17b).

**Removed:**
- `ai/ambient_agents/`: `spawn.rs` and its tests, `github_auth_notifier.rs` (the `GitHubAuthNotifier` singleton and its registrations), `telemetry.rs` (`CloudAgentTelemetryEvent` and its calls in the environment form) and, from `task.rs`, the live-session, follow-up, attachment and duration helpers that only those used. The `AmbientConversationStatus` derivation went with them.
- `AgentConversationsModel`: the initial task and cloud-metadata load, the 30-second poll, the RTC refresh throttle, `fetch_tasks_for_filters`, the task-backed list entries (`entry_for_task`, `AgentConversationEntryId::AmbientRun`, `AgentConversationProvenance::AmbientRun`, `is_cloud_agent_run`, `ExecutionLocation` on entries), the task-derived display statuses and `reset`. `UpdateManagerEvent::AmbientTaskUpdated` and its handler went too, so `UpdateManagerEvent` has one variant. The conversation list, the zero-state block and `ActiveAgentViewsModel` now key on `AIConversationId` (`ConversationOrTaskId`, `register_ambient_session` and `get_terminal_view_id_for_ambient_task` are gone).
- Terminal and workspace: `ConversationTranscriptViewerStatus::ViewingAmbientConversation`, `TerminalModel::{ambient_agent_task_id, is_cloud_agent_conversation}`, `TerminalView::{ambient_agent_task_id, active_conversation_task_id, is_cloud_agent_session}`, the cloud tab indicator (`Indicator::AmbientAgent`), the `ambient_agent_task_id` parameter of the transcript-viewer, workspace-action and focus-change functions, `ConversationRestorationInNewPaneType::Historical.ambient_agent_task_id` and `HistoricalCLIAgent`, and `ActiveConversationContext::is_cloud` in the block list.
- The `InsufficientCredits` platform error code in the local task-status classifier (a quota error now reports a plain status message) and the out-of-credits wording in its tests.
- The CLI-agent cloud transcript path: `CloudConversationData` (now plain `AIConversation`), `CLIAgentConversation`, `restore_cli_agent_block_snapshot` and `enter_agent_view_for_restored_cli_agent`; `AgentViewEntryOrigin::{CloudAgent, ThirdPartyCloudAgent}`.
- `WorkspaceAction::OpenCloudAgentSetupGuide` with the `warp://action/cloud_agent_setup` URI, and the GitHub-auth completion hook of `warp://settings/environments`.
- `server_api/presigned_upload.rs`; from `server_api/ai.rs` the `spawn_agent`, `submit_run_followup`, `get_block_snapshot`, `setup_failure_debug_authorization`, `prepare_attachments_for_upload` and `download_task_attachments` calls with their request and response types.
- `ai/orchestration/remote_child.rs` (dead since a remote `StartAgent` child became an error child), `AIAgentInput::StartFromAmbientRunPrompt`, the `CloudAgentCapacityModal*` and `ComputerUse*` telemetry variants, and the block-header lookup of agent-run titles for conversation search.

**Modified:**
- `HttpStatusError` is imported from `warp_server_client` directly.
- The details panel lost its task constructors and fetch-error notice; the conversation-list, agent-management and notifications views lost the source, environment and cloud-run handling that read task entries.

**User-visible impact:** None in normal use. Nothing can start, list or reopen a cloud run; `warp://action/cloud_agent_setup` is rejected as an unknown action.

**Notes:**
- Kept for later tasks because live code of theirs still uses it: `AmbientAgentTask`, `AmbientAgentTaskId` and the task cache with `get_or_async_fetch_task_data` (AI-19 orchestration, `local_agent_task_sync_model`); the `ai/artifacts/` buttons and `artifact_download.rs` and the entry display fields and filters for source, environment, artifacts, session status and executor (AI-21 agent-management view, details panel and notifications; AI-29 for the `Artifact` type); `ai/ambient_agents/{scheduled,github_auth_url}.rs` (AI-18 scheduled agents and the environment form); the controller, action-model and `send_message` executor `ambient_agent_task_id` (AI-19); `ServerAIConversationMetadata::ambient_agent_task_id` (AI-30).
- Left for the server plan: `PlatformErrorCode::InsufficientCredits` (a cynic input enum that must match the GraphQL schema), `ObjectUpdateMessage::AmbientTaskUpdated` and the `AmbientTaskUpdated` GraphQL type (now ignored), the `warp://conversation` URI and the cloud conversation loader (`load_conversation_from_server`, `NewWorkspaceSource::FromCloudConversationId`). Left for the `QueuedQueryModel` deleter: `finish_native_setup`. Left for FLAGS-1: `AmbientAgentsRTC`, `ScheduledAmbientAgents` and the `ambient_agents_*` Cargo features.

## Retired cloud values in settings and tab configs
**Why:** The cloud-mode removal deleted `DefaultSessionMode::CloudAgent` and `TabConfigPaneType::Cloud`, so files written by earlier builds can still name them. This checks what such a file does now.

**Modified:**
- `DefaultSessionMode` reads the retired values `cloud_agent` and `docker_sandbox` (and their `CloudAgent`/`DockerSandbox` serialized spellings) as the default mode, Terminal, instead of rejecting the setting. Before, the setting fell back to its default but writes to the key were blocked, so the user could not change it from the UI. Other unknown names are still rejected. The enum's `SettingsValue` and `Deserialize` impls are written by hand for this.
- `TabConfigPaneType::Terminal` accepts `cloud` as an alias, so a tab config with `type = "cloud"` loads and opens that pane as a terminal instead of failing the whole file with a parse error.

**Added:** tests for both cases (`settings::ai::tests::retired_default_session_modes_read_as_the_default_mode`, `user_config::tests::test_load_tab_configs_opens_retired_cloud_pane_type_as_terminal`).

**User-visible impact:** Upgrading users with a cloud tab config keep it (as a terminal tab). This supersedes the "no longer load" note in the cloud-mode section.

**Notes:** Launch configurations always produce terminal panes, so they have no pane mode to migrate.
## Orchestration and child agents
**Why:** Orchestration let one Warp agent plan a task, spawn "child" agents (local Oz, remote cloud workers or third-party CLI harnesses), message them and wait for their events. It depended on Warp's agent server, its cloud runs and its event/message endpoints, and on the ambient-agent machinery removed alongside it. An offline fork has no agent to orchestrate and nothing to run children against (ai.md AI-19).

**Removed:**
- `app/src/ai/orchestration/` (edit state, config state, providers, option snapshots, validation and `remote_child.rs`), `ai/agent_events/` (the agent-event stream driver and message hydrator), `ai/local_harness_setup.rs` and `crates/ai`'s `orchestration_config`. This takes the test-only `OrchestrationConfigState::to_orchestration_config`, the CLI-harness bootstrap and the dormant Claude wake listener with it.
- `ai/blocklist/orchestration_{child_tracker,event_streamer,events,topology}.rs` and `child_agent_launch.rs`: the per-conversation event streamers (including the viewer-mode registry, ancestor SSE stream and `FamilyDrainMode::Observer`), the child tracker and the topology walker. The `OrchestrationEventService`, `OrchestrationEventStreamer` and `OrchestrationPillBarModel` singletons and their test-setup registrations are gone, as is `test_child_pill_after_reopening_closed_parent_tab` with `integration_testing/orchestration_navigation.rs`.
- The `StartAgent`, `RunAgents`, `SendMessageToAgent` and `WaitForEvents` executors, `AIAgentActionType::{RunAgents, SendMessageToAgent, WaitForEvents}` and their results, `StartAgentExecutionMode`, and the tool-call, result and history conversions for them. Server tool calls of those kinds now fall through to "unexpected tool", and messages of the matching proto types have no client representation.
- Inline cards: `run_agents_card_view`, `orchestration_controls`, `host_picker`, the "create environment" modal that hung off the cards (and `settings_view/handoff_environment_creation_modal.rs` with its orchestration form configuration), and `block/view_impl/orchestration.rs` (the send-message and received-message transcripts).
- Agent-view and pane UI: `agent_view/orchestration_{avatar,conversation_links,pill_bar,pill_bar_model}.rs`, the pane-header breadcrumb row and parent-navigation card, `pane_group/child_agent/`, the hidden child-pane tracking, swap, split-off, "open in new tab/pane" and re-adopt paths of `PaneGroup` and `Workspace`, `HiddenPaneReason::ChildAgent`, and the reveal/stop/kill/cycle actions of the terminal view (including the `ctrl-alt-[` / `ctrl-alt-]` child-cycling bindings). Esc from an agent view no longer navigates to a parent conversation and the back button always reads "for terminal".
- Inputs, messages and commands: `AIAgentInput::{MessagesReceivedFromAgents, EventsFromAgents, OrchestrationConfigUpdate}`, the matching output messages and their rendering/redaction/persistence arms, `UserQueryMode::Orchestrate`, `/orchestrate`, and `harness::parse_orchestration_harness` / `parse_local_child_harness`.
- Conversation model: the child-agent state of `AIConversation` and `AgentConversationData` (`parent_agent_id`, `agent_name`, `orchestration_harness_type`, `parent_conversation_id`, `is_remote_child`, `last_event_sequence`, `pinned`, per-plan orchestration configs), the history model's child index and child/remote-child constructors, `BlocklistAIHistoryEvent::{NewConversationRequestComplete, OrchestrationConfigUpdated}` and `ConversationStatus::WaitingForEvents`. The request metadata no longer carries a parent agent id or agent name.
- Queued prompts: the native-run setup barrier, the `Steering` delivery mode and the `DispatchStateChanged` event of `QueuedQueryModel`; `BlocklistAIController`'s `native_prompt_conversation_id`, `steer_head_prompt_for_request` and pending-event injection.
- Sync and telemetry: the terminal-view to CLI-harness task mapping and status bridging of `LocalAgentTaskSyncModel`, the whole `ai/blocklist/telemetry.rs` orchestration event family, and the `ChildAgent` and `OrchestrationPillBar` agent-view entry origins.
- Usage: the orchestration credit rollup (`usage/rollup.rs`) and the "View details" per-agent breakdown of the usage footer.
- Server client: the agent message send/read/delivered, event-sequence and event-stream (SSE) calls, `orchestration_handoff` and the messaging types.
- Settings: `agents.warp_agent.other.orchestration_message_display_mode` and its dropdown and command-palette entries, the `run_agents` permission of execution profiles (the profile field, its file format entry and its editor and read-only rows), and `AISettings::is_orchestration_enabled`.
- UI helpers only the orchestration UI used: `IconWithStatusVariant::CustomAvatar` and the rounded-square badge shape, the per-call background/border/overlay-layer overrides of `Dropdown`, the overlay and orientation options of `FilterableDropdown`, and the `set_disabled`/`set_tooltip` setters of the compactible buttons.
- The ambient-agent leftovers of AI-17b: the task cache of `AgentConversationsModel` (`get_task_data`, `get_or_async_fetch_task_data`, `evict_and_refetch_task`, `update_task_as_running_with_session`, the fetch back-off state, `get_all_environment_ids_and_names`, `AgentConversationsModelEvent::TasksUpdated`), `BlocklistAIController::{ambient_agent_task_id, attachments_download_dir}`, the `ambient_agent_task_id` field of `RequestParams` and `ConversationData` (the request metadata now sends an empty task id), and the `display_name`, `conversation_id`, `is_terminal_run_state`, `is_terminal` and `TaskScope::is_team` helpers of `ai/ambient_agents/task.rs`.
- Tests for all of the above, including the test-only child-conversation helpers.

**Modified:**
- Conversation status, agent-run list status and the tab and header badges now read the conversation's own status; they no longer roll up a child subtree.
- `select_conversations_to_evict` (the on-disk conversation cap) keeps the most recently modified conversations instead of whole parent/child trees.
- The queued-prompts panel and input no longer consult a startup barrier.

**User-visible impact:** No `/orchestrate`, no orchestration cards or settings, no pill bar or child panes, and no child-agent keybindings. Conversations that an older build stored as children of an orchestrator lose their parent link and show up in history as ordinary conversations; the profile file's `run_agents` key and the removed setting are ignored on load.

**Notes:**
- Stored data written by older builds stays readable: `AgentConversationData` and execution-profile files ignore the removed child-agent keys and `run_agents` (covered by `agent_conversation_data_ignores_removed_child_agent_fields` and `file_collection_ignores_the_removed_run_agents_permission`). None of the removed enums (`ConversationStatus::WaitingForEvents`, `UserQueryMode::Orchestrate`, the action/result variants) is persisted.
- Proto message types from `warp_multi_agent_api` (`OrchestrationConfigSnapshot`, `MessagesReceivedFromAgents`, `EventsFromAgents`, `RunAgents`, and so on) are external and stay named in the message-conversion arms that ignore them.
- Left for FLAGS-1: the `OrchestrationLaunchModal`, `MultiLevelOrchestration`, `CloudAgentRunners` flags and the `orchestration_launch_modal` Cargo feature.
- Left for AI-17b: `AgentSource::Orchestration` and the `last_event_sequence` and `children` fields of `AmbientAgentTask`. Left for AI-18: `cloud_environments/catalog.rs`'s orchestration default environment and the now-unused `cloud_agent_settings`, `connected_self_hosted_workers`, `harness_availability` and `auth_secret_types` items. Left for AI-20: `ai/document/plan_publication.rs`. Left for AI-20: the environment filter dropdown and the always-empty task branch of `ConversationDetailsData::from_agent_conversation_entry` in `agent_management/` (the environment dropdown now offers only All and None). Left for AI-29: the unused `server_api` attachment, spawn, follow-up and run-list calls (`TaskListFilter`, `build_list_agent_runs_url`, `ListRunsResponse`, the `as_query_param` helpers they use) and `server/retry_strategies.rs`, which nothing calls any more.
## Cloud workflows
**Why:** Cloud workflows are Warp Drive objects: they are stored, synced, shared and versioned through Warp's servers, and their enums, aliases and metadata generation add more server calls (user decision 1). Local workflows (the user's own YAML files in `~/.warp/workflows`, project `.warp/workflows`, the bundled global workflows and the app workflows) are plain files and stay.

**Removed:**
- `workflows/{manager.rs, workflow_view.rs, workflow_view/, aliases.rs, workflow_enum.rs, export_workflow.rs}` — the `WorkflowManager` singleton, the workflow view (pane content used to view, edit and create a cloud workflow, with its argument editor, alias bar and alias argument selector), workflow aliases (the `WorkflowAliases` setting group with the `WorkflowAlias` type, the alias completer, and running an alias from the input) and workflow enums (`WorkflowEnum`, `EnumVariants`), plus export of a workflow with its enums to YAML.
- `drive/workflows/` — the create/edit workflow modal (`WorkflowModal`, including `open_with_new`), the enum creation dialog, the argument-type selector, the AI assist that generated a title, description and arguments from a command, and `AIClient::generate_metadata_for_command`.
- `pane_group/pane/workflow_pane.rs`, `IPaneType::Workflow`, `LeafContents::Workflow`, `WorkflowPaneSnapshot`, the workflow kind in vertical tabs (`TypedPane::Workflow`, `SummaryPaneKind::Workflow`, the Drive-object detail sidecar) and `integration_testing/workflow/{assertion,step}.rs`.
- "Save as workflow": `TerminalAction::{OpenWorkflowModal, OpenWorkflowModalForAIWorkflow, OpenWorkflowModalForBlock, OpenWorkflowModalWithCloudWorkflow}`, `InputContextMenuAction::SaveAsWorkflow`, the `terminal:toggle_teams_modal` binding, the matching terminal, pane-group and workspace events, and the workspace's workflow modal, `is_workflow_modal_open` state and update-manager subscription that refreshed the info box after a cloud edit.
- Dynamic and static enum suggestions in the input (`InputSuggestionsMode::{StaticWorkflowEnumSuggestions, DynamicWorkflowEnumSuggestions}`, `DynamicEnumSuggestionStatus`, the dynamic-enum approval menu and `terminal/dynamic_enum_suggestions.rs`, `Input::set_enum_variants`).
- `search/ai_context_menu/workflows/` and `AIContextMenuCategory::Workflows` — the "Workflows" category of the `@` menu, which listed cloud workflows.
- Cloud-object plumbing that only existed for workflows: `CloudWorkflow`, `CloudWorkflowModel`, `ServerWorkflow`, `WorkflowId`, `CloudWorkflowEnum` and `ServerWorkflowEnum` (`cloud_object_models`), `ObjectType::Workflow`, `ObjectIdType::Workflow`, `JsonObjectType::WorkflowEnum` and `CloudObjectTypeAndId::Workflow` (`cloud_objects`), `ObjectClient::{create_workflow, update_workflow, transfer_workflow_owner}`, `InitialLoadResponse::{updated,deleted}_workflows`, `ObjectsToUpdate::workflows`, `ServerCloudObject::{Workflow, WorkflowEnum}`, the workflow persistence adapters and `ModelEvent::{UpsertWorkflow, UpsertWorkflows}`, `QueueItem::{CreateWorkflow, UpdateWorkflow, UpdateWorkflowEnum}` with the enum-dependency inference of the sync queue, and the `UpdateManager` create/update/duplicate/move/conflict paths for workflows and the copying of enums when a workflow is moved to another drive.
- `WorkflowType::{Cloud, AIGenerated}`, `AIWorkflowOrigin`, `WorkflowSource::{Team, PersonalCloud, WarpAI}`, `WorkflowViewMode`, `WorkflowSelectionSource::{WarpDrive, WarpAI, WorkflowView, AgentMode, Alias}` and the `WorkflowViewType::Team` sidebar entry of the workflow browser.
- `ContentEditability` (with `RequiresLogin`), `CloudViewModel::{object_editability, access_level}` and the `SharedWorkflowsPolicy` counter on the team plan page (`UserWorkspaces::has_capacity_for_shared_workflows`).
- `CloudModel::{get_workflow*, get_all_active_workflows, active_workflows_in_space, overwrite_workflow*, workflow_enums_with_owner, ...}`, `buttons::{accent_icon_button, highlight}` and `Dropdown::set_selected_to_none` (only the workflow view used them).
- Telemetry variants whose payload was the cloud workflow ID: `WorkflowAlias{Added,Removed,ArgumentEdited,EnvVarsAttached}`, `ExecutedWarpDrivePrompt` and `TelemetryCloudObjectType::Workflow`; `WorkflowTelemetryMetadata` lost its `workflow_id`, `workflow_space` and `enum_ids` fields.
- Integration tests `test_open_workflow_in_pane`, `test_restore_snapshot_with_workflows` and `test_restore_snapshot_with_common_shareable_metadata_ids` (they verified cloud workflow panes and metadata) with their `restored_workflows.sqlite` and `test_duplicate_shareable_ids.sqlite` fixtures.

**Modified:**
- `workflows/workflow.rs` now defines `Workflow`, `Argument` (name, description, default value) in the app; the types no longer live in `cloud_object_models`. `Workflow::Command` lost `environment_variables`; `ArgumentType` is gone because arguments are text only, and an `arg_type: Enum` key or `environment_variables` in a YAML file is ignored. `Workflow` keeps its `Deserialize` impl, so the per-document parsing of local workflow YAML (`WorkflowDocument`) is unchanged. `ArgumentsState` moved from `drive/workflows/arguments.rs` to `workflows/arguments.rs` (the notebook command blocks use it).
- `WorkflowType` has only `Local`. The info box (`workflows/info_box.rs`) shows the collapse and close buttons only; the workflow browser sidebar is All, My Workflows (the local files), Repository Workflows and the categories.
- `RunAISuggestedCommand` runs the command as a `WorkflowType::Local` with `WorkflowSource::App`.
- `SessionContext::new`, `SyncQueue::new` and `initialize_queue_dependencies` no longer take an `AppContext`/`ModelContext` that only the alias snapshot and the workflow dependency inference used.
- `persistence/sqlite.rs`: a `workflow` pane row is skipped on restore like other removed pane kinds; `save_app_state` still clears `workflow_panes` so a stale row cannot block saving (DB-1 removes the table). `StartedCommandMetadata::cloud_workflow_id`, `HistoryEntry::workflow_id`, `PersistedCommand::workflow_id`, `Block::cloud_workflow_id` and `AfterBlockCompletedEvent::cloud_workflow_id` are gone; the history still links a command to a local workflow by its command text.
- Tests that used workflows as sample cloud objects (`update_manager_tests`, `sync_queue_tests`, `model_tests`, the workspace tests) now use notebooks, folders or preferences; workflow-only tests (enum dependencies, moving a workflow with its enums, duplicate-by-name of workflows) were deleted. `integration_testing::assertions::create_a_personal_workflow` became `create_a_personal_folder`.
- New tests: `test_sqlite_restore_and_save_survive_stale_workflow_pane_rows` and `workflow_file_ignores_fields_of_removed_argument_types_and_environment_variables`.

**User-visible impact:** Workflows saved to Warp Drive can no longer be opened, run, edited or aliased. The cloud rows stay in the local database, unread. Local workflows are unchanged: they show in the workflow browser (Ctrl-Shift-R), command search and `workflows:` filter, run through the info box with `{{argument}}` highlighting and Shift-Tab cycling, and load from YAML as before. A saved window with a workflow pane restores without it. The "Save as workflow" entries, the Ctrl-Shift-S "Toggle team workflows modal" binding and the "Workflows" category of the `@` menu are gone. Arguments no longer offer enum suggestion menus.

**Notes:**
- Left for DRV-5: the rest of the cloud-object infrastructure (`CloudModel`, `UpdateManager`, `SyncQueue`, `ObjectClient`, `ObjectActions`, the sort/space/trash helpers of `CloudViewModel` and the now-unused `CloudObjectMetadataExt`, `get_top_folder_trashed_ts`, `ObjectActions::{insert_action, get_action_history_summary_for_action_type}`), `DriveObjectType::Workflow` and `warp_drive_icon_color` (still used to colour the command-palette Workflows filter), and `Input::team_scope`.
- Left for DB-1: the `workflows`, `workflow_panes` tables, `blocks.cloud_workflow_id`, the diesel `NewWorkflow`/`Workflow`/`WorkflowPane` models and `WORKFLOW_PANE_KIND` in `crates/persistence`, and old `object_metadata` rows of type `WORKFLOW` and `GENERIC_STRING_JSON_WORKFLOWENUM`.
- Left for SRV-1: the GraphQL workflow types, mutations (`create_workflow`, `update_workflow`, `transfer_workflow_owner`, `generate_metadata_for_command`) and `JsonWorkflowEnum`, which the schema still declares; the client ignores workflows and workflow enums in server responses.
- Left for TEL-4: `WorkflowExecuted`, `WorkflowSelected`, `DeletedWorkflow`, `SaveAsWorkflowModal`, `AutoGenerateMetadata{Success,Error}` and the unused `WorkflowSelectionSource` variants `CommandPalette` and `SlashMenu`.
- Left for FLAGS-1: `FeatureFlag::{WorkflowAliases, DynamicWorkflowEnums, SharedWithMe}` and their Cargo features. Left for TEAM-1/BILL-1: `SharedWorkflowsPolicy` in `workspaces/workspace.rs` and its GraphQL conversion. Left for AI-29: `DriveObjectPayload::Workflow`, `AIAgentCitation::WarpDriveObject` (a click on one is now a no-op).
## Settings: Warp Agent, profiles, custom models and cloud platform pages
**Why:** With Warp's hosted agent, credits and cloud accounts gone, these pages configured nothing that still exists: models and inference endpoints, agent permission profiles, Oz API keys and cloud environments. What stays under the old "Agents" group is the page for third-party CLI agents.

**Removed:**
- `settings_view/{warp_agent_page, agent_profiles_page, execution_profile_view, custom_inference_modal, custom_router_view, set_default_model_modal, remove_custom_endpoint_confirmation_dialog, ai_shared}.rs` (with their tests) and `settings_view/{platform_page, platform/}` (the Oz Cloud API keys page and its create/expire widgets).
- The execution-profile and custom-router editor panes (`pane_group/pane/{execution_profile_editor_pane, custom_router_editor_pane}.rs`, `LeafContents::{ExecutionProfileEditor, CustomRouterEditor}`, the matching `IPaneType` values, vertical-tabs entries, the workspace `open_*` methods, `SettingsViewEvent::{OpenCustomRouterEditor, OpenCustomRouterFile, OpenExecutionProfileEditor}`, `pane_group::Event::OpenAgentProfileEditor` and its terminal and AI-block emitters), `ai/execution_profiles/editor/` (the editor view and the `ExecutionProfileEditorManager` singleton, including its registration in `lib.rs`) and `ai/custom_model_router_editor.rs`. The link to "Manage command execution setting" in the command-permission notice went with them.
- `SettingsSection::{WarpAgent, AgentProfiles, CloudEnvironments, WarpCloudAgentAPIKeys}`, their nav entries, the "Agents" and "Cloud platform" umbrellas, the `custom_router` deeplink widget, the `warp://settings/{warp_agent, platform, environments}` deep links, and the `workspace:show_ai_settings_page` and `workspace:show_settings_environments_page` bindings. The Environments page no longer registers as a settings page (`EnvironmentsPageView` stays as the environment-management pane until AI-18).
- `WarpAgentPageAction::ToggleActiveAI` and its binding, with the page.
- Settings and flags: `AISettings::{can_use_warp_credits_for_fallback, should_show_oz_updates_in_zero_state, should_expand_oz_updates}` (the "Show Warp Agent changelog" toggle), `flags::{SHOW_OZ_UPDATES_IN_ZERO_STATE_FLAG, WARP_CREDIT_FALLBACK_FLAG, SHOW_TERMINAL_ZERO_STATE_BLOCK_FLAG, CLOUD_CONVERSATION_STORAGE_FLAG, CLOUD_CONVERSATION_STORAGE_EDITABLE_FLAG}` and their context wiring, `RequestParams::allow_use_of_warp_credits` and the `api_keys_with_warp_credit_fallback_setting` helper, `AIExecutionProfilesModel::should_preserve_onboarding_profile` and its `preserve_profile_onboarding_overrides` field.
- The "Store AI conversations in the cloud" switch on the Privacy page (widget, action, binding), the "Show help block in new sessions" switch on the Features page (widget, action, binding), the "Configure" button on the inline history menu, and `SettingsTelemetryEvent` (its only event, `EnvironmentsPageOpened`).
- Helpers that only these pages used: the `AgentToolbarInlineEditor`, `WarningBoxTitle::Formatted`, `Dropdown::{set_render_popup_externally, render_menu_as_overlay, selected_action}`, `FilterableDropdown::{set_vertical_margin, set_placeholder, clear_footer}`, `Modal::{with_max_height_percentage, with_dismiss_keystroke, set_title}`, the model-chip, custom-size-header, labelled-icon and info-banner settings widgets, the custom-router file writer and error list in `user_config`, the long-context pricing warning helpers, the per-profile permission `is_*_editable` checks on `AISettings`, and the profile-permission setters on `BlocklistAIPermissions`.

**Modified:**
- "Third party CLI agents" is a top-level settings page directly above the Code group. Arrow-key navigation, search auto-expansion and the nav tests now use the Code group as the only umbrella.
- `SettingsSection::from_slug` maps the stored names of the removed Warp Agent pages (`Warp Agent`, `Oz`, `AI`, `Profiles`, `AgentProfiles`) to the Third party CLI agents page, and the removed cloud pages (`Environments`, `CloudEnvironments`, `Oz Cloud API Keys`, `OzCloudAPIKeys`) to the default page, so restored settings tabs and `surface.settings.open --page` keep working.
- The secret-redaction description no longer mentions Warp Drive objects or Oz prompts.
- The profile, custom-endpoint and onboarding-profile tests were adjusted to the smaller surface; the settings navigation integration tests use the Code umbrella, and one new test covers a search that selects the Third party CLI agents page. `language_server_downloads_widget_id` is public so those tests can address the Projects page.
- AI blocks and inputs that offered "open Warp Agent settings" links (API keys, model defaults, profile management) point at the agents page until AI-24/AI-27/AI-28 delete them.

**User-visible impact:** Settings no longer has Warp Agent, Profiles, Environments or API keys pages, and no "Agents" or "Cloud platform" groups; Third party CLI agents sits at the top level. The Privacy page loses the AI conversation storage switch and the Features page loses the help-block switch (both were already hidden without AI).

**Notes:**
- Left for AI-24/AI-27/AI-28: the AI-block and input code that still emits `OpenSettings` for the agents page (`ai/blocklist/block*`, `terminal/input/models/`, `terminal/profile_model_selector.rs`), `TerminalSettings::show_terminal_zero_state_block` and the zero-state block, the `SlashCommandsInTerminalModeWidget` on the Features page (still gated on AI being enabled, so hidden), and `DefaultSessionModeWidget`, whose dropdown is disabled while AI is off (AI-25 collapses `DefaultSessionMode`).
- Left for AI-29: `AIExecutionProfilesModel`'s editing API (`create_profile`, `delete_profile`, `set_*`, `add_to_*`/`remove_from_*`, `default_profile_id`), now used only by tests and integration helpers; `ai/custom_endpoints::{add, save, remove}`, `UserWorkspaces::{get_agent_attribution_setting, is_gemini_enterprise_credentials_toggleable}` and the `is_cloud_conversation_storage_enabled` setting with its workspace policy; `ai/custom_model_routers` and the custom-router config loader; the `allow_use_of_warp_credits` field of the multi-agent request proto (still a generated field; the client always sends the default).
- Left for AI-18: `settings_view/{environments_page, update_environment_form, agent_assisted_environment_modal, ...}` and the environment-management pane. `SettingsPageEvent::{EnvironmentSetupModeSelectorToggled, AgentAssistedEnvironmentModalToggled}` stay for that pane.
- Left for TEL-4: `TelemetryEvent::ToggleActiveAI`. Left for DB-1: `EXECUTION_PROFILE_EDITOR_PANE_KIND` in `crates/persistence`; stored `pane_leaves` rows of that kind are skipped on restore (test `test_sqlite_restore_skips_stale_profile_editor_pane_and_keeps_the_split`), and no editor pane state is written any more.

## Plans, billing, pricing and upgrade prompts
**Why:** The offline build has no accounts, plans or billing (decision 6), so plan tiers, pricing, purchases and every "Upgrade" prompt lead nowhere, and the prompts opened `warp.dev` pages, which decision 3 removes.

**Removed:**
- `app/src/pricing/` (`PricingInfoModel`, its singleton and its test-helper registrations) and the `pricingInfo` piggyback on the workspaces-metadata query. `WorkspacesMetadataWithPricing` is gone; `TeamClient` methods return `WorkspacesMetadataResponse` directly.
- `UserWorkspaces`: `upgrade_link*`, `admin_billing_link_*`, `generate_upgrade_link`, `generate_stripe_billing_portal_link`, `update_usage_based_pricing_settings`, `purchase_addon_credits`, `refresh_ai_overages`, `update_addon_credits_settings`, `purchase_policy`, `set_user_purchase_policy`, `usage_based_pricing_settings`, the user-level purchase policy and `is_at_tier_limit_*` / `has_capacity_for_shared_{notebooks,workflows}` (plan limits on shared objects). Their `UserWorkspacesEvent`s (`GenerateUpgradeLink*`, `GenerateStripeBillingPortalLink*`, `UpdateWorkspaceSettings*`, `AiOveragesUpdated`, `PurchaseAddonCredits*`, `SunsettedToBuildDataUpdated`) went with them.
- `WorkspaceClient`: `generate_stripe_billing_portal_link`, `update_usage_based_pricing_settings`, `refresh_ai_overages`, `purchase_addon_credits`, `update_addon_credits_settings` and `PurchaseAddonCreditsOutcome`. Only `remove_user_from_workspace` is left.
- Workspace and team data: `Workspace::{stripe_customer_id, bonus_grants_purchased_this_month, billing_cycle_usage, has_billing_history}`, `Team::{stripe_customer_id, has_billing_history}`, the usage-based-pricing and add-on-credit workspace settings, the usage-visibility, purchase-add-on-credits, pay-as-you-go, credits-auto-reload, usage-based-pricing and shared notebook/workflow tier policies, AI overages, delinquency status, service agreements, the plan-classification helpers on `BillingMetadata` and `CustomerType::to_display_string`. Stored workspace and team JSON still deserializes; unknown fields are ignored.
- GraphQL (`crates/graphql`): the `BonusGrant*`, `BillingCycleUsage*`, `UsageEntry`, `AiCreditsUsage*` (including `AiCreditsUsageBucket::Voice`), `AiOverages`, `AddonCreditsOption`, `PricingInfo`, `PlanPricing`, `StripeSubscriptionPlan`, `ServiceAgreement*` and `DelinquencyStatus` types, the `purchaseAddonCredits`, `stripeBillingPortal` and `updateWorkspaceSettings` mutations and the `getAiOveragesForWorkspace` query, plus the matching fields on the workspaces-metadata query and the create-team mutation. `VOICE` was also removed from the `AICreditsUsageBucket` enum in `crates/warp_graphql_schema/api/schema.graphql`; SRV-1 deletes the schema whole, so nothing else shares it.
- `settings_view/admin_actions.rs` (`AdminActions`: admin-panel, contact-support and contact-sales links) and its tests.
- Teams page: the "Upgrade"/"Compare plans" and "Manage billing" links, the "Open admin panel" button and its section on the teamless page, the seat-cap and payment-status warning banner (which also disabled the invite-by-email form), the "Need more seats?" upgrade line, the per-seat cost notice, the "Plan usage limits" section, the plan badge and the past-due/unpaid badges, the plan-capacity tooltip on the member count, the "workspace admin panel" link in the invite-link help text, and the "Manage plan" link under the team-deletion help text. `TeamDeleteDisabledReason::ActivePaidSubscription` is gone.
- `WorkspaceAction::ShowUpgrade`, `WorkflowModalEvent::AiAssistUpgradeError` and the workflow editor's `display_upgrade_error`; the "Upgrade" link under a plan-gated model in the model picker.
- `render_customer_type_badge`, `render_cta_line`, `render_cta_banner`, `WordBlockEditorView::set_interaction_state`, `WorkspaceView::team_uid`, `Icon::StripeLogo` with `stripe.svg`.
- The `billing_and_usage_page_v2` Cargo feature and `FeatureFlag::BillingAndUsagePageV2`. BILL-1 removes it now instead of leaving it to FLAGS-1 because nothing references it.
- Tests for the removed behavior: plan-usage-visibility and purchase-policy tests (`workspace_tests.rs`), add-on price tests (`billing_tests.rs`), and the purchase, `admin_billing_link`, billing-metadata and user-level purchase-policy tests in `user_workspaces_tests.rs` and `update_manager_tests.rs`.

**Modified:**
- `TeamsWidget::page_sections_for` no longer takes the viewer's email: a native-workspace user with nothing to join sees the "no teams to join" state whether or not they administer the workspace.
- AWS Bedrock and Gemini Enterprise credential refresh now refresh on `TeamsChanged` only (the workspace-settings-updated event no longer exists).
- `BillingMetadata` and `Tier` stay as the container for the remaining tier policies (BYO keys and endpoints, session sharing, AI autonomy, native workspaces, multi-admin and so on).

**User-visible impact:** No "Upgrade", "Compare plans", "Manage billing", "Open admin panel", "Contact sales" or plan-limit text remains in the Teams page or the model pickers. A team member list is never capped or blocked by a plan.

**Notes:**
- Left for TEAM-1: the rest of `workspaces/` and the Teams page; `BillingMetadata`/`Tier` and their remaining policies, `CustomerType`, `team_billing_metadata`/`current_workspace_billing_metadata` and the BYO accessors in `billing_workspace_settings.rs` (used by AI request building and the model pickers until AI-29 removes them); `WorkspaceMemberUsageInfo` and `total_requests_used_since_last_refresh`.
- Left for AI-29: `DisableReason::{RequiresUpgrade, OutOfRequests}` and their "upgrade your plan" tooltips in `ai/llms.rs` and `server_api/ai.rs`.
- Left for AI-17a: `OUT_OF_CREDITS_TASK_FAILURE_MESSAGE` ("Upgrade your Warp plan...") in `ai/ambient_agents/mod.rs`.
- Left for FLAGS-1: `FeatureFlag::{UsageBasedPricing, PricingTransparency}`.
- Left for TEL-4: `TelemetryEvent::UserMenuUpgradeClicked`.
## Cloud environments, schedules, runners, managed secrets and isolation platform
**Why:** Oz cloud agents ran inside a "cloud environment" (Docker image, repos, setup commands) that users created, scheduled and shared through Warp Drive, executed on Warp-hosted or self-hosted runners, and authenticated with Oz API keys and server-side managed secrets. All of it needed Warp's servers, and none of it has anything to run against offline (ai.md AI-18).

**Removed:**
- Environments: `ai/cloud_environments/` (the environment catalog and the `AmbientAgentEnvironment` model), the Environments settings page and its forms (`settings_view/{environments_page, update_environment_form, agent_assisted_environment_modal, delete_environment_confirmation_dialog}`), the environment-management pane (`EnvironmentManagementPane`, `LeafContents::EnvironmentManagement`, `IPaneType::EnvironmentManagement`, its vertical-tabs entry and the `open_environment_management_pane` action), `terminal/view/init_environment/` with the `/create-environment` slash command, `TerminalAction::{SetupCloudEnvironment, SetupCloudEnvironmentAndStart, TriggerEnvironmentSetupSelection, OpenEnvironmentManagementPane}`, `AIAgentInput::CreateEnvironment`, `AgentViewEntryOrigin::CreateEnvironment`, the `warp://action/create_environment` deep link with its `root_view:create_environment*` actions, the `workspace:show_settings_environments_page` binding, the environment selector and sidecar of `context_chips/display_menu.rs`, the environment and harness filters of the agent-management view (`EnvironmentFilter`, `HarnessFilter`, `ViewAgentRunsForEnvironment`), the environment and runner sections and the "View in Oz" links of the conversation details panel, and the `last_task_run_ts` metadata field with the `GetCloudEnvironments` fetch.
- Cloud-object types: `AmbientAgentEnvironment`, `ScheduledAmbientAgent` and `CloudAgentConfig` with their `Server*`/`Cloud*` aliases, sync-queue items, update-manager create/update/move paths and `JsonObjectType::{CloudEnvironment, ScheduledAmbientAgent, CloudAgentConfig}`. `ai/ambient_agents/{scheduled, github_auth_url}.rs`, `AgentConfigSnapshot` (with its `mcp_servers`, `skill_spec` and harness fields, and the field on `AmbientAgentTask`), `AgentSource::ScheduledAgent`, the `skill_spec`, `environment_id` and `schedule_id` list filters, and the server-client calls `create_agent_task`, `list_connected_self_hosted_workers` and `get_available_harnesses`.
- Runners, workers and harnesses: `ai/{connected_self_hosted_workers, runner_display, harness_availability, auth_secret_types, cloud_agent_settings}.rs`, `ai/cloud_agent_config/`, the `CloudEnvironmentCatalog`, `HarnessAvailabilityModel` and `ConnectedSelfHostedWorkersModel` singletons (and their test-setup registrations), the `CloudAgentSettings` settings group, the `FactoryClient` (runner CRUD) and the app-side `IntegrationsClient` (GitHub connection and image suggestion).
- Oz API keys and managed secrets: the Platform settings page (`platform_page`, `platform/`), `crates/managed_secrets` (envelope encryption and the `ManagedSecretManager`/`get_task_secrets` client, including its `ActorProvider` impl for `AuthState`) and `server_api/managed_secrets.rs`, the `AuthClient` calls `list_api_keys`, `create_api_key`, `expire_api_key` and `list_agent_identities`, and `ApiKeyUid`.
- Identity minting: the `IapManager` Workload Identity Federation mint (`IapIdentityTokenMinter`, `ManagedIapMint`, the STS/IAM exchange, the bootstrap-JWT environment variable and the on-disk IAP cache; `IapManager::new` loses its mint argument), the AWS Bedrock OIDC credential refresh (`AwsCredentialsRefreshStrategy` and `aws-sdk-sts`), and Gemini Enterprise credential minting (`ai/geap_credentials.rs`, `crates/ai/src/geap_credentials.rs`, the request-time refresh in the response stream, the credentials error card and the Gemini Enterprise settings section). All three minted credentials from a Warp-signed OIDC identity token.
- Isolation platform: `crates/isolation_platform`, its `WorkloadToken` header on server requests (`AMBIENT_WORKLOAD_TOKEN_HEADER`, `get_ambient_workload_token_valid_until`, `pinned_ambient_agent_headers_for_task`, `AmbientHeaderPolicy::workload_only`), the OOM-score adjustment for sandboxed shells in `warp_terminal::local_tty::unix`, and the `DetectedIsolationPlatform` telemetry event.
- `OzConfig` (`oz_root_url`, `workload_audience_url`) from `warp_core::channel::{config, state}` and from the `oss` and `integration` binaries; `ChannelState::{oz_root_url, workload_audience_url}`. The AgentMemory citation chip (which opened the Oz dashboard) goes with them: `AIAgentCitation::AgentMemory`, `AIConversation::fetched_memories` and the telemetry variant.
- GraphQL client types no caller uses any more: the managed-secret, runner, simple-integration, cloud-environment, scheduled-history, GitHub-info, harness, warp.dev-image, task-secret, task-attachment, task-git-credential, API-key and OAuth-transaction queries and mutations, and `warp_graphql::managed_secrets`.
- Dependencies: `warp_managed_secrets`, `warp_isolation_platform` and `aws-sdk-sts`, and the three `warpdotdev/tink-rust` `[patch]` entries the managed-secrets crate needed.
- Tests for all of the above.

**Modified:**
- `SettingsSection` loses `CloudEnvironments` and `WarpCloudAgentAPIKeys`; the "Cloud platform" nav umbrella is gone. The old slugs (`Environments`, `CloudEnvironments`, `Oz Cloud API Keys`, `OzCloudAPIKeys`) parse to the default page, so a stored settings pane or warpctrl caller lands on the first page instead of failing. `warp://settings/environments` and `warp://settings/platform` open the default settings page.
- `SettingsPageEvent` keeps only `FocusModal`; the settings telemetry module (whose only event was `EnvironmentsPageOpened`) is deleted.
- `ChipMenuType::Environments`, `CopyButtonPlacement`, the warning box's title/description/button options and the filterable dropdown's test hooks were only used by the removed UI and are simplified or removed.
- `AgentManagementFilters` no longer carries `environment` or `harness`; persisted filters that still contain those keys deserialize (covered by `test_agent_management_filters_ignore_retired_fields`).
- Persisted cloud objects of the three retired kinds are skipped when the local database is read (the generic-string-object reader already drops unknown `JsonObjectType`s; covered by `retired_json_object_types_no_longer_parse`).

**User-visible impact:** No Environments or Platform (API keys) settings pages, no `/create-environment`, no environment picker, no cloud-agent run details for environments and runners, and no Gemini Enterprise or OIDC Bedrock credential refresh. Existing users with a stored `Environments` or `Oz Cloud API Keys` settings page open the default page. Cloud objects of the retired kinds stay in the local database (DB-1 drops them) but are never loaded.

**Notes:**
- Left for AI-21: `ai/agent_management/cloud_setup_guide_view.rs` still documents `/create-environment` and `oz integration create`. Left for AI-27: the remaining task-mode branch of `ConversationDetailsPanel` and its `PanelMode::Task`.
- Left for AI-29: `AISettings::gemini_enterprise_credentials_enabled`, the Gemini Enterprise team-policy helpers in `workspaces/user_workspaces` (`is_gemini_enterprise_credentials_enabled`, `gemini_enterprise_host_enablement_setting`), `RenderableAIError::GeminiEnterpriseCredentialsExpiredOrInvalid`, `ApiKeys.google_cloud_credentials` on the request, and the unused `AIClient::{list_ambient_agent_tasks, get_ambient_agent_task}` calls.
- Left for SRV-1: the GraphQL schema types for everything above (`JsonCloudEnvironment`, `JsonScheduledAmbientAgent`, runners, managed secrets, API keys), `ServerApi::ambient_headers`' cloud-agent-id and source headers, and the `CloudEnvironments`, `CreateEnvironmentSlashCommand`, `ScheduledAmbientAgents` and `WarpManagedSecrets` flags (FLAGS-1).
- Left for DRV-5: `UpdateManager::move_object_to_location` and its helpers, whose only caller was the environment page.
- `crates/managed_secrets_wasm` was already deleted by WASM-1; the `managed_secrets_wasm` doc comments went with `crates/managed_secrets`.
- The removal is one commit because the modules reference each other (the catalog, harness model and settings group are singletons registered together, and the cloud-object variants thread through the sync queue, update manager and SQLite reader).

## Agent management view and conversation list
**Why:** The agent management view (a full-window list of Oz cloud runs and local conversations with filters, cards and a cloud setup guide) and the left-panel conversation list only browsed Warp-agent and cloud-run data, which no longer exists in the offline terminal. The notification model, the toast stack, the mailbox and the tab icons also still carried Warp-agent (Oz) and conversation origins next to the third-party CLI-agent ones.

**Removed:**
- `ai/agent_management/` (view, cloud setup guide, details action buttons, telemetry), `workspace/view/conversation_list/`, `workspace/delete_conversation_confirmation_dialog.rs` and `view_components/agent_toast.rs` (the legacy Warp-agent toast that `HOANotifications` had already bypassed).
- Workspace: the agent-management view state, the header-toolbar button (`HeaderToolbarItemKind::AgentManagement`), `WorkspaceAction::{ToggleAgentManagementView, OpenAgentManagementView, ViewAgentRunsForEnvironment, ToggleConversationListView, OpenConversationListView, ExecuteDeleteConversation}`, the `workspace:toggle_agent_management_view` and `workspace:toggle_conversation_list_view` bindings, `CustomAction::ToggleConversationListView` with its View-menu item, the `ToolPanelView::ConversationListView` tool panel (and with it the tool-panel availability states), and the "toggle conversation list" agent-view shortcut hint.
- Settings: `show_conversation_history` (`agents.warp_agent.other.show_conversation_history`) with its Appearance and Warp Agent page toggles, and `DidDismissAgentManagementHelpPage`.
- `warpctrl`: `surface conversation-list open` and `surface agent-management open` (`surface.conversation_list.open`, `surface.agent_management.open`).
- Notifications (`agent_notifications/`): `NotificationSourceAgent` (Oz/CLI) and `NotificationOrigin` (Conversation/CLISession), notification artifacts, the conversation-history, active-agent-view and queued-query subscriptions, the `ConversationNeedsAttention` event, and the artifact-buttons rendering. `AgentManagementEvent` is now `AgentNotificationsEvent`. Items carry a `CLIAgent` and are de-duplicated by terminal view.
- Tabs and icons: `SummaryPaneKind::OzAgent`, the `is_ambient` flag and cloud-lobe rendering of `IconWithStatusVariant`, the conversation-derived branch and the run-card helpers of `ui_components/agent_icon.rs`, and the Warp-agent conversation title, status and "Warp Agent" badge in vertical tabs. `AgentTabTextPreference::ConversationTitle` is now `SessionTitle`.
- `AgentConversationsModel`: the `AgentManagementFilters` family, `ConversationUpdateKind`, the loading state, copy-link resolution, creator listing, and the entry fields nothing reads any more (creator, executor, usage, cost, run time, session status, source, environment, harness, artifacts, provenance, capabilities).
- `ConversationDetailsPanel` (still hosted by the terminal pane until AI-27): the cloud task mode, environment, runner and executor sections, the action-buttons row, the "Continue locally" and "View in Oz" buttons, and `ConversationDetailsData::{from_agent_conversation_entry, from_conversation_metadata}`.
- Dead helpers: `AgentSource::Orchestration`, `AgentSource::{display_name, is_user_initiated}`, the `last_event_sequence` and `children` fields of `AmbientAgentTask`, `cancel_task_with_toast`, `ArtifactButtonsRow::{with_theme, is_empty}`, `harness_display::{cli_agent, brand_color}`, `conversation_utils::delete_conversation`, `QueuedQueryModel::has_autofireable_prompt`, `ActiveAgentViewsModel`'s unused getters, `ui_components/menu_button.rs` (no users left), and the unused `FilterableDropdown` and `DropdownStyle` options.

**Modified:**
- `HeaderToolbarChipSelection::Custom` holds `LenientVec<HeaderToolbarItemKind>`, so a stored `agent_management` entry drops only itself. `LeftPanelDisplayedTab::ConversationListView` reads as `FileTree` in stored left-panel snapshots. Tests: `header_toolbar_chip_selection_skips_removed_items_in_settings_file`, `test_left_panel_snapshot_with_removed_conversation_list_tab_falls_back_to_file_tree`.
- `WindowSnapshot` no longer carries agent-management filters; the `windows.agent_management_filters` column is written as NULL and never read.
- `ConversationStatus::should_trigger_notification` moved next to `ConversationStatus`.

**User-visible impact:** No agent management panel, header-toolbar button, conversation-list tab or their shortcuts. CLI-agent (Claude Code, Codex, ...) notifications, toasts, the mailbox and tab icons work as before.

**Notes:**
- Left for AI-27: `ConversationDetailsPanel`, `ai/artifacts/buttons.rs` and `artifact_download.rs` (only the panel uses them), the `AgentViewEntryOrigin::ConversationListView` variant, `OzAgent` in `IconWithStatusVariant`, and the Oz desktop notification in `terminal/view.rs`.
- Left for AI-29: the whole task model in `ai/ambient_agents/task.rs` and its `server_api/ai.rs` calls (now unused), `UsageDisplayUnit`, `format_usage`, `usage_label`, `AIConversation::usage_totals` and `ConversationUsageMetadataUpdated` (the details panel and history plumbing still use them); `AIConversation::{turn_panel_data, turn_panel_records}` were not used by the removed views (only by tests) and stay for AI-29/AI-30. Left for DB-1: the `windows.agent_management_filters` column. Left for FLAGS-1: `AgentManagementView`, `AgentManagementDetailsView`, `AgentViewConversationListView`, `InteractiveConversationManagementView` and their Cargo features.

## Offline guardrails (draft)
**Why:** the fork is only offline if nothing puts Warp hosts, Warp server clients or network code back. The removal tasks are still landing, so this draft acts as a progress meter; SWP-17 finalisation makes it blocking.

**Added:**
- `script/offline_audit` (python3 and ripgrep) with three groups of checks. `hosts` is the zero-tolerance grep for Warp domains, services, keys and the Metal-skip build hook. `network` lists network-capable Rust (`reqwest`, `http_client`, `hyper`, sockets, `url_source` and others), `curl`/`wget` in scripts and non-git subprocesses, and each hit must fall under an allowed consumer. `deps` reads `cargo metadata` for banned workspace crates, banned external crates, wrapper rules and `cargo deny check bans licenses sources`. Informational lists cover the removed-feature wording review list, browser-opening call sites and every hard-coded URL host.
- `script/offline_audit --report` lists every finding and exits 0. The default mode exits 1 on any finding. `--net-log FILE` checks an `strace` log of a sandboxed run and fails on any connect or send to a non-loopback address or to port 53.
- `script/offline_audit.allowlist`: reasoned exceptions (`CHANGES.md`, the audit's own patterns, `deny.toml`, the build-time `warpdotdev` git forks, historical migrations, the secure-storage key string, the third-party DirectX compiler binaries, `http_client`, `node_runtime`, `local_control` and developer bootstrap scripts). Entries that match nothing are reported.
- `deny.toml`: `[graph]` (all features, no dev edges) and `[bans] deny` with wrappers for `reqwest`, `hyper`, `axum`, `tower-http` and `interprocess`, and outright bans for `cynic`, `tungstenite`, `async-tungstenite`, `oauth2`, `rmcp`, `session-sharing-protocol`, `warp_multi_agent_api`, the Sentry and minidump crates and the OpenTelemetry exporters.
- `.github/workflows/ci.yml`: an `offline-audit` job that runs the static audit, then the whole test suite (including `integration`) under `unshare --user --map-root-user --net` with `strace`, and checks the recorded connections. It has `continue-on-error: true`.

**User-visible impact:** none; this is repository tooling.

**Notes:**
- The audit fails today by design: hosts, network and dependency findings remain in code that the pending tasks delete. The report groups them by directory to map them onto owner tasks.
- `tower-http` is allowed as a dependency of `reqwest` only, because reqwest 0.13 depends on it unconditionally (sweep.md 9.3 asks for no `tower-http` at all). `hyper` also allows `hyper-util` and `hyper-rustls`, which are part of reqwest's transport.
- Comment lines are skipped in the `network` check (`--include-comments` restores them); `hyper` is matched as a whole word so `hyperlink` and the Hyper terminal do not count; `git` and `gh` subprocesses are counted but never reported.
- Unchanged in the draft and left to finalisation: the two-minute idle `integration` session of 9.4a, the SSH integration tests (`test_ssh_*`), which the CI job excludes with a filter until they are deleted or ignored, and dropping `continue-on-error`.
- The runtime step of the CI job could not be run locally (it needs Linux, `unshare` and `strace`); the log parser was tested against a hand-written `strace` sample.

## Default session mode is a terminal setting
**Why:** "Default mode for new sessions" (Settings > Features) chooses what a new tab opens: a plain terminal or one of the user's tab configs. Its dropdown was disabled whenever AI was off, which is always the case now, so users could not pick a default tab config. The Agent mode it also offered opens the agent view and cannot exist here.

**Removed:**
- `DefaultSessionMode::Agent`, the "Agent" option of the dropdown and the `agent` search term. A stored `agent` value reads as Terminal, like the retired `cloud_agent` and `docker_sandbox`.
- The AI gating of the setting: the dropdown's enable/disable on `is_any_ai_enabled` and its refresh on `IsAnyAIEnabled`, the AI check in `AISettings::default_session_mode` (which no longer takes an `AppContext`), and the "New Terminal Tab" and "New Agent Tab" menu shortcuts that swapped depending on an Agent default.
- The agent-view auto-entry for new tabs and panes: `DefaultSessionModeBehavior` (workspace and pane group), `Workspace::enter_agent_view_on_active_tab`, the unused `PaneGroup::add_terminal_pane_ignoring_default_session_mode`, `AgentViewEntryOrigin::DefaultSessionMode` and its telemetry twin. `add_new_session_tab_with_default_mode` and `add_new_session_tab_internal_with_default_session_mode_behavior` are merged into `add_new_session_tab`; `add_session` and `add_session_in_directory` lose the behavior argument.

**Modified:**
- The Features page shows the dropdown enabled with Terminal plus every loaded tab config. New tabs (`AddDefaultTab`: the tab bar `+`, Cmd-T, the vertical-tabs `+`) already opened the default tab config without an AI check; two tests now cover that with AI off (`test_add_default_tab_opens_default_tab_config_while_ai_is_off`, and the revert to Terminal when the default config file is missing).
- The default worktree config always uses `pane_type = "terminal"`. The new-session menu sidecar has no Agent item.
- `WarpConfig::set_tab_configs` (test-only) seeds tab configs in workspace tests.

**User-visible impact:** Users can choose Terminal or a tab config as the default for new sessions from Settings > Features. The setting used to be greyed out.

**Notes:**
- The Features page has no other terminal setting greyed out by the AI toggle. `SlashCommandsInTerminalModeWidget` (AI-gated, hidden) and `show_terminal_zero_state_block` are left to AI-24/AI-27/AI-28. `AtContextMenuInTerminalModeWidget` ("@" context menu) is not AI-gated but is an AI-context feature: AI-24.
- Left for AI-25: the "Agent" item of the unified new-session menu and the "New Agent Tab" menu item, binding and `AddAgentTab` action (all already hidden or disabled without AI), the `default_session_mode_internal`/`DefaultSessionMode` types still living in `AISettings` (they must survive it), and the agent-oriented tab helpers (`add_terminal_tab_in_ai_mode` and friends).

## Workspace shell: agent tabs, agent deep links and the Oz session type
**Why:** The agent view can no longer be entered (AI is permanently off), so the workspace entry points into it were dead: the New Agent Tab command, the agent-mode tab and pane actions, the Oz session type and agent pane type of tab configs, the `warp://` deep links that opened an agent conversation, the code-diff pane for AI edits and the command palette's conversation search. The workspace also kept subscriptions and keymap flags for AI settings and conversation history that nothing could trigger. This is the workspace, pane-group and app-shell half of ai.md AI-25.

**Removed:**
- New Agent Tab: `WorkspaceAction::{AddAgentTab, NewTabInAgentMode, NewPaneInAgentMode, FixInAgentMode, StartNewConversation}`, `CustomAction::NewAgentTab`, the `workspace:new_agent_tab` binding, the "New Agent Tab" item of the File menu, the "Agent" item of the new-session menu, `Workspace::{add_terminal_tab_in_ai_mode, add_terminal_pane_in_ai_mode, add_terminal_tab_with_new_agent_view}`, `PaneGroup::{start_agent_mode_in_new_pane, add_terminal_pane_in_agent_mode}`, `AGENT_MODE_PANE_DEFAULT_MINIMUM_WIDTH`, `PaneNode::pane_flex_sum_along_axis` and the integration test `test_agent_mode_pane_minimum_size`.
- Actions nothing dispatched: `WorkspaceAction::{OpenAgentToolbarEditor, ContinueConversationLocally, InsertForkSlashCommand}` (the agent toolbar editor still opens from the terminal footer's event).
- Deep links: `warp://conversation/<id>`, `warp://linear/work` and `warp://action/new_agent_conversation` (now rejected as unknown), `app/src/linear.rs`, the `root_view:open_conversation_viewer`, `root_view:open_cloud_conversation_in_existing_window` and `root_view:open_linear_issue_work_in_{new,existing}_window` actions, `NewWorkspaceSource::{FromCloudConversationId, AgentSession}`, `NewWorkspaceSource::is_content_deep_link` with `Workspace::opened_from_content_deep_link` (no source is a content deep link any more), and `Workspace::{open_cloud_conversation_from_server_token, open_linear_issue_work}`.
- `warpctrl`: the `agent` and `cloud-agent` values of `tab create --type` (`TabType::{Agent, CloudAgent}` in `local_control`, `CliTabType` in `warp_cli`).
- Tab configs: `SessionType::Oz`, `TabConfigPaneType::Agent`, `PaneMode` and `PaneTemplateType::PaneTemplate::pane_mode`, the deferred agent-view entry (`TerminalView::{set,clear}_enter_agent_view_after_pending_commands`), the `pane_type` parameter of the default worktree config, `GuidedModalSessionType::Oz` and, in the "Create your first tab config" modal, the session-type pill selector (`render_session_type_pills*`, `SelectSessionType`, `SessionConfigModal::configure`, `visible_session_types`, `SessionType::{icon, pill_label}`), which had shown only Terminal since Oz was hidden.
- Code-diff pane: `CodeDiffPane`, `CodeDiffPaneModel`, `IPaneType::CodeDiff`, `pane_group::Event::OpenCodeDiff`, `terminal::Event::OpenCodeDiff`, `AIBlockEvent::OpenCodeWithDiff` and the `CodeDiff` kinds of the vertical-tabs summary. Editing an AI diff no longer opens it in a pane.
- Command palette: `search/command_palette/conversations/`, `CommandPaletteItemAction::{NavigateToConversation, ForkConversation, NewConversationInProject, NewConversation}`, `ItemSummary::{Conversation, ForkConversation, NewConversation, Project}` and the Conversations chip of the zero state. `search/command_search/projects/` (the "new conversation in project" source, referenced nowhere) and `ProjectManagementModel::all_projects` went with it.
- Workspace subscriptions and flags: the `AISettings` and `BlocklistAIHistoryModel` subscriptions, the `ActiveAgentViewsModel` focus notification, the "code review opened" mark on the active conversation, the `IsAnyAIEnabled`, `IsActiveAIEnabled`, thinking-display, prompt-submission, long-running-command-submission, agent-footer, agent-command-history, denylist-bypass and base-model-picker keymap flags (and their `settings_view::flags` constants), and the `AISettings` subscription of the right panel.

**Modified:**
- `TabConfigPaneType::Terminal` also accepts `agent` (next to `cloud`), so a tab config with `type = "agent"` opens a terminal instead of failing to load. Launch configs no longer write `pane_mode`; a stored `pane_mode` (`terminal` or `agent`) is ignored. `default_worktree.toml` says `type = "terminal"`; `materialize_default_worktree_config` still replaces `{{pane_type}}` (and drops `[params.pane_type]`) in copies that earlier builds wrote to `~/.warp/default_tab_configs/`. Tests: `user_config::tests::test_load_tab_configs_opens_retired_pane_types_as_terminal` (the former `..._retired_cloud_pane_type_as_terminal`, extended to `agent`), `test_materialize_default_worktree_config_accepts_template_with_pane_type_param`, `launch_configs::tests::test_retired_pane_mode_field_is_ignored`, `uri::tests::test_agent_deeplinks_are_rejected`.
- Code-review comments can only be sent to a terminal that runs a CLI agent: the right panel's `ai_enabled` argument is gone and the "AI is disabled" reason became "no CLI agent is running in the terminal" (same result as before, since AI is off).
- The "Jump to latest agent task" binding (`workspace:jump_to_latest_toast`) is gated on `HOANotifications` instead of `AgentMode` and the AI keymap flag, so it now jumps to the newest unread CLI-agent notification, as the toggle-mailbox binding next to it already did.
- `onboarding_slides_skip_content_deep_link_terminal` became `onboarding_slides_wrap_terminal_workspace`.

**User-visible impact:** No New Agent Tab command or menu item, and no Agent entry in the new-tab menu (both were disabled or hidden without AI). `warpctrl tab create --type agent|cloud-agent`, `warp://conversation/...`, `warp://linear/...` and `warp://action/new_agent_conversation` are rejected. Tab configs and launch configs from earlier builds that name the agent type still load as terminals. `Cmd-Shift-G` ("Jump to latest agent task") is active when a CLI agent has an unread notification.

**Notes:**
- The audit table in "Persisted values of removed enum variants" is superseded for `PaneMode` (the type is gone; the field is ignored) and `TabConfigPaneType` (now `cloud` and `agent` are both aliases).
- Left for the task that lands after AI-24 (their dispatchers are in `terminal/input*`, which AI-24 deletes): `WorkspaceAction::{ForkAIConversation, SummarizeAIConversation, RestoreOrNavigateToConversation, OpenConversationTranscriptViewer}` with `workspace/global_actions.rs`, `Workspace::{fork_ai_conversation, restore_or_navigate_to_conversation, restore_conversation_in_*, load_cloud_conversation_into_new_transcript_viewer, summarize_active_ai_conversation}`, the `PaneGroup` transcript-viewer and loading-conversation panes, `AgentConversationsModel::resolve_open_action`, and the `pane_group::Event::OpenConversationHistory` chain with `PaletteMode::Conversations` and `QueryFilter::Conversations`.
- Left for AI-26: the `ensure_agent_mode` field of `WorkspaceAction::InsertInInput` (set by `code/view.rs` and AI blocks; `Input::ensure_agent_mode_for_ai_features`). Left for AI-27/AI-28: the rewind dialog (`workspace/rewind_confirmation_dialog.rs`, `ShowRewindConfirmationDialog`, `ExecuteRewindAIConversation`), the agent toolbar editor modal, `RunAISuggestedCommand`, the `ACTIVE_AGENT_VIEW` keymap flags, and the `BlocklistAIHistoryEvent` handling in `terminal_pane.rs`. Left for AI-29: the AI fields of `TerminalPaneSnapshot`. Dead code left for their deleters: `ActiveAgentViewsModel::{handle_pane_focus_change, get_focused_conversation}`, `BlocklistAIHistoryModel::set_has_code_review_opened_to_true`, `CodeDiffView::set_original_pane_id`, `TelemetryEvent::{AgentModeClickedEntrypoint, LinearIssueLinkOpened}` (TEL-4).
