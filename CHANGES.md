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
- Left for AI-15: the AI-gated `AgentModeWorkflows` (saved prompts) filter in command search. Left for AI-25: `CustomAction::NewAgentModePane`, which no binding provides any more. Left for AI-11: `resources/bundled/skills/change-keybinding/SKILL.md` still names `workspace:toggle_ai_assistant`. Left for DRV-1: a comment in `drive/workflows/modal.rs` that cites Warp AI command search.
- `set_ai_input_mode_with_query` and `InputTypeAutoDetectionSource::AskAi` stay because `ai/agent_sdk` still uses them.
