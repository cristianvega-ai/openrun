#[cfg(not(target_family = "wasm"))]
use std::env;
#[cfg(not(target_family = "wasm"))]
use std::path::PathBuf;
#[cfg(not(target_family = "wasm"))]
use std::time::Duration;

use pathfinder_color::ColorU;
#[cfg(not(target_family = "wasm"))]
use tokio::fs;
use warp_core::ui::color::blend::Blend;
use warp_core::ui::theme::Fill;
#[cfg(not(target_family = "wasm"))]
use warp_errors::report_error;
use warpui::{AppContext, SingletonEntity, ViewContext};

use super::CLIAgentFooter;
#[cfg(not(target_family = "wasm"))]
use super::CLIAgentFooterEvent;
use crate::appearance::Appearance;
use crate::features::FeatureFlag;
use crate::send_telemetry_from_ctx;
use crate::server::telemetry::{PluginChipTelemetryKind, TelemetryEvent};
use crate::settings::CLIAgentSettings;
use crate::terminal::CLIAgent;
#[cfg(not(target_family = "wasm"))]
use crate::terminal::ShellLaunchData;
use crate::terminal::cli_agent_sessions::CLIAgentSessionsModel;
#[cfg(not(target_family = "wasm"))]
use crate::terminal::cli_agent_sessions::plugin_manager::{
    CliAgentPluginManager, PluginInstallError, compare_versions, plugin_manager_for,
    plugin_manager_for_with_shell,
};
#[cfg(not(target_family = "wasm"))]
use crate::terminal::local_shell::LocalShellState;
use crate::view_components::DismissibleToast;
#[cfg(not(target_family = "wasm"))]
use crate::view_components::ToastLink;
use crate::view_components::action_button::ActionButtonTheme;
use crate::workspace::ToastStack;
#[cfg(not(target_family = "wasm"))]
use crate::workspace::WorkspaceAction;

/// How long to wait after session creation before showing the install chip.
/// Gives the plugin time to connect and send its `SessionStart` event.
#[cfg(not(target_family = "wasm"))]
pub(super) const PLUGIN_CHIP_DEBOUNCE: Duration = Duration::from_secs(3);

#[cfg_attr(target_family = "wasm", allow(dead_code))]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum PluginChipKind {
    Install,
    Update,
}

impl From<PluginChipKind> for PluginChipTelemetryKind {
    fn from(kind: PluginChipKind) -> Self {
        match kind {
            PluginChipKind::Install => PluginChipTelemetryKind::Install,
            PluginChipKind::Update => PluginChipTelemetryKind::Update,
        }
    }
}

/// Builds a composite key for per-agent, per-host plugin chip dismissal.
/// Returns `"<agent_prefix>"` for local sessions or `"<agent_prefix>@<host>"` for remote.
pub(super) fn plugin_chip_key(agent_prefix: &str, remote_host: &Option<String>) -> String {
    match remote_host {
        Some(host) => format!("{agent_prefix}@{host}"),
        None => agent_prefix.to_owned(),
    }
}

impl CLIAgentFooter {
    /// Which plugin chip to show, if any.
    pub(super) fn plugin_chip_kind(&self, app: &AppContext) -> Option<PluginChipKind> {
        #[cfg(target_family = "wasm")]
        {
            let _ = (app, self.plugin_operation_in_progress);
            None
        }
        #[cfg(not(target_family = "wasm"))]
        {
            if self.plugin_operation_in_progress || !FeatureFlag::HOANotifications.is_enabled() {
                return None;
            }

            let cli_agent_settings = CLIAgentSettings::as_ref(app);
            if !*cli_agent_settings.show_agent_notifications {
                return None;
            }

            let session = CLIAgentSessionsModel::as_ref(app).session(self.terminal_view_id)?;

            let manager = plugin_manager_for(session.agent)?;
            let min_version = manager.minimum_plugin_version();
            let chip_key = plugin_chip_key(session.agent.command_prefix(), &session.remote_host);
            // If a structured plugin is connected and this agent supports
            // version-based updates, check the reported version.
            if session.supports_rich_status() && manager.supports_update() {
                let needs_update = match &session.plugin_version {
                    // No version reported = pre-versioning plugin, definitely outdated.
                    None => true,
                    Some(v) => compare_versions(v, min_version).is_lt(),
                };
                if !needs_update {
                    return None;
                }
                // Check update chip dismissal.
                let dismissed_version =
                    cli_agent_settings.plugin_update_chip_dismissed_version(&chip_key);
                if !dismissed_version.is_empty()
                    && compare_versions(dismissed_version, min_version).is_ge()
                {
                    return None;
                }
                return Some(PluginChipKind::Update);
            }

            // For agents without auto-install, wait for the debounce timer
            // before showing the install chip.
            if !manager.can_auto_install() && !self.plugin_chip_ready {
                return None;
            }

            let install_chip_dismissed =
                cli_agent_settings.is_plugin_install_chip_dismissed(&chip_key);

            // For remote sessions, we can't check the filesystem.
            if session.is_remote() {
                return (!install_chip_dismissed).then_some(PluginChipKind::Install);
            }

            if manager.is_installed() {
                // Installed but no listener yet. Check the on-disk version as a fallback
                // — the plugin may be too old to send structured events.
                if manager.needs_update() {
                    let dismissed_version =
                        cli_agent_settings.plugin_update_chip_dismissed_version(&chip_key);
                    if !dismissed_version.is_empty()
                        && compare_versions(dismissed_version, min_version).is_ge()
                    {
                        return None;
                    }
                    return Some(PluginChipKind::Update);
                }
                // Up to date on disk — wait for the listener to connect.
                return None;
            }

            // Not installed locally.
            (!install_chip_dismissed).then_some(PluginChipKind::Install)
        }
    }

    /// Whether the chip should open the manual instructions modal instead of auto-operating.
    pub(super) fn should_use_manual_mode(&self, app: &AppContext) -> bool {
        let sessions_model = CLIAgentSessionsModel::as_ref(app);
        let session = match sessions_model.session(self.terminal_view_id) {
            Some(s) => s,
            None => return false,
        };

        // Custom toolbar commands always use manual mode because the user's
        // binary may differ from the agent's standard CLI tool.
        if session.custom_command_prefix.is_some() {
            return true;
        }

        #[cfg(not(target_family = "wasm"))]
        if let Some(manager) = plugin_manager_for(session.agent)
            && !manager.can_auto_install()
        {
            return true;
        }
        if session.is_remote() {
            return true;
        }
        sessions_model.has_plugin_auto_failed(session.agent, &session.remote_host)
    }

    /// Records that the auto plugin operation could not start, shows an error toast,
    /// and re-renders so the chip switches to manual-instructions mode.
    #[cfg(not(target_family = "wasm"))]
    pub(super) fn record_plugin_auto_failure_and_notify(&mut self, ctx: &mut ViewContext<Self>) {
        if let Some(agent) = self.cli_agent(ctx) {
            let remote_host = CLIAgentSessionsModel::as_ref(ctx)
                .session(self.terminal_view_id)
                .and_then(|s| s.remote_host.clone());
            CLIAgentSessionsModel::handle(ctx).update(ctx, |model, _| {
                model.record_plugin_auto_failure(agent, remote_host);
            });
        }
        let window_id = ctx.window_id();
        ToastStack::handle(ctx).update(ctx, |toast_stack, ctx| {
            toast_stack.add_ephemeral_toast(
                DismissibleToast::error(
                    "Could not automatically install plugin. \
                     Please click the chip again for manual installation steps."
                        .to_owned(),
                ),
                window_id,
                ctx,
            );
        });
        ctx.notify();
    }

    /// Shared handler for both install and update plugin operations.
    /// `progress_toast` is shown while the operation runs; `success_toast` on success.
    #[cfg(not(target_family = "wasm"))]
    pub(super) fn handle_plugin_operation<F, Fut>(
        &mut self,
        progress_toast: &str,
        error_label: &str,
        success_toast: &str,
        operation_kind: PluginChipTelemetryKind,
        operation: F,
        ctx: &mut ViewContext<Self>,
    ) -> bool
    where
        F: FnOnce(Box<dyn CliAgentPluginManager>) -> Fut + Send + 'static,
        Fut: std::future::Future<Output = Result<(), PluginInstallError>> + Send + 'static,
    {
        let Some(agent) = self.cli_agent(ctx) else {
            return false;
        };
        let shell_data = {
            let model = self.terminal_model.lock();
            model.active_shell_launch_data().cloned()
        };
        let (shell_path, shell_type) = match shell_data {
            Some(ShellLaunchData::Executable {
                executable_path,
                shell_type,
            })
            | Some(ShellLaunchData::MSYS2 {
                executable_path,
                shell_type,
            }) => (Some(executable_path), Some(shell_type)),
            // Shell not yet resolved (e.g. still bootstrapping).
            None => (None, None),
            // WSL is not supported for auto-install.
            Some(ShellLaunchData::WSL { .. }) => return false,
        };

        // Await the interactive PATH so nvm-installed tools like `claude`
        // are on PATH, matching how LSP operations capture the PATH.
        let path_future = LocalShellState::handle(ctx).update(ctx, |shell_state, ctx| {
            shell_state.get_interactive_path_env_var(ctx)
        });

        self.plugin_operation_in_progress = true;
        ctx.notify();

        let window_id = ctx.window_id();
        let toast_id = "cli-agent-plugin-operation".to_owned();

        ToastStack::handle(ctx).update(ctx, |toast_stack, ctx| {
            toast_stack.add_persistent_toast(
                DismissibleToast::default(progress_toast.to_owned())
                    .with_object_id(toast_id.clone()),
                window_id,
                ctx,
            );
        });

        let toast_id_for_callback = toast_id.clone();
        let error_label = error_label.to_owned();
        let success_toast = success_toast.to_owned();
        ctx.spawn(
            async move {
                let path_env_var = path_future.await;
                let Some(manager) =
                    plugin_manager_for_with_shell(agent, shell_path, shell_type, path_env_var)
                else {
                    return Err((
                        PluginInstallError {
                            message: "No plugin manager available".to_owned(),
                            log: String::new(),
                        },
                        None,
                    ));
                };

                match operation(manager).await {
                    Ok(()) => Ok(()),
                    Err(err) => {
                        let log_path = write_install_log(agent, &err).await;
                        Err((err, log_path))
                    }
                }
            },
            move |me, result, ctx| {
                me.plugin_operation_in_progress = false;

                if result.is_ok() {
                    send_telemetry_from_ctx!(
                        TelemetryEvent::CLIAgentPluginOperationSucceeded {
                            cli_agent: agent.into(),
                            operation: operation_kind,
                        },
                        ctx
                    );
                    ctx.emit(CLIAgentFooterEvent::PluginInstalled(agent));
                } else {
                    send_telemetry_from_ctx!(
                        TelemetryEvent::CLIAgentPluginOperationFailed {
                            cli_agent: agent.into(),
                            operation: operation_kind,
                        },
                        ctx
                    );
                }

                ToastStack::handle(ctx).update(ctx, |toast_stack, ctx| {
                    let toast = match result {
                        Ok(()) => DismissibleToast::success(success_toast.clone()),
                        Err((err, log_path)) => {
                            let remote_host = CLIAgentSessionsModel::as_ref(ctx)
                                .session(me.terminal_view_id)
                                .and_then(|s| s.remote_host.clone());
                            CLIAgentSessionsModel::handle(ctx).update(ctx, |model, _| {
                                model.record_plugin_auto_failure(agent, remote_host);
                            });
                            log::error!("Failed plugin operation log: {}", err.log);
                            let mut toast =
                                DismissibleToast::error(format!("{error_label}: {err}"));
                            report_error!(
                                anyhow::Error::new(err).context("Failed plugin operation"),
                                extra: { "agent" => ?agent }
                            );
                            if let Some(log_path) = log_path {
                                toast = toast.with_link(
                                    ToastLink::new("See logs for details".to_owned())
                                        .with_onclick_action(WorkspaceAction::OpenFilePath {
                                            path: log_path,
                                        }),
                                );
                            }
                            toast
                        }
                    };
                    toast_stack.add_ephemeral_toast(
                        toast.with_object_id(toast_id_for_callback),
                        window_id,
                        ctx,
                    );
                });
                ctx.notify();
            },
        );
        true
    }

    #[cfg(not(target_family = "wasm"))]
    pub(super) fn handle_install_plugin(&mut self, ctx: &mut ViewContext<Self>) -> bool {
        let success_msg = self
            .cli_agent(ctx)
            .and_then(plugin_manager_for)
            .map(|m| m.install_success_message())
            .unwrap_or("Warp plugin installed. Please restart the session to activate.");
        self.handle_plugin_operation(
            "Installing Warp plugin...",
            "Failed to install Warp plugin",
            success_msg,
            PluginChipTelemetryKind::Install,
            |manager| async move { manager.install().await },
            ctx,
        )
    }

    #[cfg(not(target_family = "wasm"))]
    pub(super) fn handle_update_plugin(&mut self, ctx: &mut ViewContext<Self>) -> bool {
        let success_msg = self
            .cli_agent(ctx)
            .and_then(plugin_manager_for)
            .map(|m| m.update_success_message())
            .unwrap_or("Warp plugin updated. Please restart the session to activate.");
        self.handle_plugin_operation(
            "Updating Warp plugin...",
            "Failed to update Warp plugin",
            success_msg,
            PluginChipTelemetryKind::Update,
            |manager| async move { manager.update().await },
            ctx,
        )
    }
}

/// Green-accented theme for the "Install Warp plugin" chip.
pub(super) struct InstallPluginButtonTheme;

impl ActionButtonTheme for InstallPluginButtonTheme {
    fn background(&self, hovered: bool, appearance: &Appearance) -> Option<Fill> {
        let green = appearance.theme().ansi_fg_green();
        let base = appearance.theme().surface_1();
        Some(if hovered {
            base.blend(&Fill::Solid(green).with_opacity(30))
        } else {
            base.blend(&Fill::Solid(green).with_opacity(15))
        })
    }

    fn text_color(
        &self,
        _hovered: bool,
        _background: Option<Fill>,
        appearance: &Appearance,
    ) -> ColorU {
        appearance.theme().ansi_fg_green()
    }

    fn border(&self, appearance: &Appearance) -> Option<ColorU> {
        let green = appearance.theme().ansi_fg_green();
        Some(ColorU::new(green.r, green.g, green.b, 80))
    }

    fn should_opt_out_of_contrast_adjustment(&self) -> bool {
        true
    }
}

/// Writes the detailed plugin installation log to a temp file.
/// Returns the log file path on success, or `None` if writing failed.
#[cfg(not(target_family = "wasm"))]
async fn write_install_log(agent: CLIAgent, err: &PluginInstallError) -> Option<PathBuf> {
    let log_path = env::temp_dir().join("warp-plugin-install.log");
    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S UTC");
    let contents = format!(
        "Warp plugin installation — {agent:?}\n\
         {now}\n\
         \n\
         {log}",
        log = err.log,
    );
    fs::write(&log_path, contents).await.ok()?;
    Some(log_path)
}
