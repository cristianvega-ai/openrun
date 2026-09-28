use voice_input::{StartListeningError, VoiceInputLifecycleState, VoiceSessionResult};
use warp_errors::report_error;
use warpui::{SingletonEntity, ViewContext};

use super::{CLIAgentFooter, CLIAgentFooterEvent};
use crate::send_telemetry_from_ctx;
use crate::server::server_api::TranscribeError;
use crate::server::team_scope::RequestTeamScope;
use crate::server::telemetry::TelemetryEvent;
use crate::settings::AISettings;
use crate::ui_components::icons::Icon;
use crate::view_components::DismissibleToast;
use crate::workspace::ToastStack;
use crate::workspaces::user_workspaces::UserWorkspaces;

impl CLIAgentFooter {
    pub(super) fn stop_cli_voice_and_reset(&mut self, ctx: &mut ViewContext<Self>) {
        let lifecycle_state = self.cli_voice_input_lifecycle.state();
        if lifecycle_state == VoiceInputLifecycleState::Idle
            && self.cli_recording_handle.is_none()
            && self.cli_transcription_handle.is_none()
        {
            return;
        }
        if let Some(handle) = self.cli_recording_handle.take() {
            handle.abort();
        }
        if let Some(handle) = self.cli_transcription_handle.take() {
            handle.abort();
        }
        voice_input::VoiceInput::handle(ctx).update(ctx, |voice_input, _| {
            if voice_input.is_listening() {
                voice_input.abort_listening();
            }
            voice_input.set_transcribing_active(false);
        });

        self.cli_voice_input_lifecycle.cancel();
        self.update_cli_mic_button_state(ctx);
    }

    // ── CLI agent voice input (self-contained, bypasses editor) ──────

    /// Toggle voice input for CLI agent mode. Records audio and writes the
    /// transcription directly to the PTY, bypassing the editor voice flow.
    pub fn toggle_cli_voice_input(
        &mut self,
        source: &voice_input::VoiceInputToggledFrom,
        ctx: &mut ViewContext<Self>,
    ) {
        if !UserWorkspaces::as_ref(ctx).is_voice_enabled() {
            return;
        }

        if !AISettings::as_ref(ctx).is_voice_input_enabled(ctx) {
            return;
        }

        // For key-based toggling, validate the key state against current voice state.
        if let voice_input::VoiceInputToggledFrom::Key { state } = source {
            match (self.cli_voice_input_lifecycle.state(), state) {
                (VoiceInputLifecycleState::Idle, warpui::event::KeyState::Released) => return,
                (VoiceInputLifecycleState::Listening, warpui::event::KeyState::Pressed) => return,
                _ => {}
            }
        }

        match self.cli_voice_input_lifecycle.state() {
            VoiceInputLifecycleState::Idle => {
                if !crate::ai::AIRequestUsageModel::as_ref(ctx).can_request_voice() {
                    self.show_cli_voice_error_toast("Voice input limit reached", ctx);
                    return;
                }

                let session_result = voice_input::VoiceInput::handle(ctx)
                    .update(ctx, |voice_input, ctx| {
                        voice_input.start_listening(ctx, source.clone())
                    });

                match session_result {
                    Ok(session) => {
                        if !self.cli_voice_input_lifecycle.start() {
                            return;
                        }
                        self.update_cli_mic_button_state(ctx);

                        if let Some(agent) = self.cli_agent(ctx) {
                            send_telemetry_from_ctx!(
                                TelemetryEvent::CLIAgentToolbarVoiceInputUsed {
                                    cli_agent: agent.into(),
                                },
                                ctx
                            );
                        }

                        if matches!(*source, voice_input::VoiceInputToggledFrom::Button) {
                            self.maybe_show_first_time_cli_voice_toast(ctx);
                        }

                        self.cli_recording_handle = Some(ctx.spawn(
                            async move { session.await_result().await },
                            CLIAgentFooter::handle_cli_voice_session_result,
                        ));
                    }
                    Err(StartListeningError::AccessDenied) => {
                        self.show_cli_microphone_access_toast(ctx);
                    }
                    Err(e) => {
                        report_error!(
                            anyhow::Error::new(e).context("Failed to start CLI voice input")
                        );
                    }
                }
            }
            VoiceInputLifecycleState::Listening => {
                voice_input::VoiceInput::handle(ctx).update(ctx, |voice_input, ctx| {
                    if let Err(e) = anyhow::Context::context(
                        voice_input.stop_listening(ctx),
                        "Failed to stop CLI voice input",
                    ) {
                        report_error!(e);
                    }
                });
            }
            VoiceInputLifecycleState::Transcribing => {
                // Don't allow toggling while transcribing.
            }
        }
        ctx.notify();
    }

    pub(super) fn handle_cli_voice_session_result(
        &mut self,
        result: VoiceSessionResult,
        ctx: &mut ViewContext<Self>,
    ) {
        use crate::editor::VoiceTranscriber;
        self.cli_recording_handle = None;

        match result {
            VoiceSessionResult::Audio {
                wav_base64,
                session_duration_ms: _,
            } => {
                let voice_transcriber = VoiceTranscriber::as_ref(ctx);
                if let Some(transcriber) = voice_transcriber.transcriber() {
                    let transcriber = transcriber.clone();
                    let language = AISettings::as_ref(ctx)
                        .voice_input_language_code()
                        .map(str::to_owned);
                    let team_scope = RequestTeamScope::from_scope(
                        &UserWorkspaces::as_ref(ctx).team_context_for_view(ctx),
                    );
                    if !self.cli_voice_input_lifecycle.begin_transcribing() {
                        return;
                    }

                    voice_input::VoiceInput::handle(ctx).update(ctx, |voice, _| {
                        voice.set_transcribing_active(true);
                    });

                    self.cli_transcription_handle = Some(ctx.spawn(
                        async move {
                            transcriber
                                .transcribe(wav_base64, language, team_scope)
                                .await
                        },
                        CLIAgentFooter::apply_cli_transcribed_voice_input,
                    ));
                } else {
                    self.cli_voice_input_lifecycle.fail();
                }
            }
            VoiceSessionResult::Aborted { .. } => {
                self.cli_voice_input_lifecycle.fail();
            }
        }
        self.update_cli_mic_button_state(ctx);
        ctx.notify();
    }

    pub(super) fn apply_cli_transcribed_voice_input(
        &mut self,
        result: Result<String, TranscribeError>,
        ctx: &mut ViewContext<Self>,
    ) {
        if !self.cli_voice_input_lifecycle.complete() {
            return;
        }

        voice_input::VoiceInput::handle(ctx).update(ctx, |voice, _| {
            voice.set_transcribing_active(false);
        });

        match result {
            Ok(transcribed_text) => {
                if !transcribed_text.is_empty() {
                    if self.has_active_cli_agent_input_session(ctx) {
                        ctx.emit(CLIAgentFooterEvent::InsertIntoCLIRichInput(
                            transcribed_text,
                        ));
                    } else {
                        ctx.emit(CLIAgentFooterEvent::InsertIntoCLIPty(transcribed_text));
                    }
                }
            }
            Err(e) => match e {
                TranscribeError::QuotaLimit => {
                    self.show_cli_voice_error_toast("Voice input limit reached", ctx);
                }
                _ => {
                    report_error!(
                        anyhow::Error::new(e).context("Failed to transcribe CLI voice input")
                    );
                    self.show_cli_voice_error_toast("Failed to transcribe voice input", ctx);
                }
            },
        }

        self.cli_transcription_handle = None;
        self.update_cli_mic_button_state(ctx);
        ctx.notify();
    }

    pub(super) fn update_cli_mic_button_state(&self, ctx: &mut ViewContext<Self>) {
        let icon = match self.cli_voice_input_lifecycle.state() {
            VoiceInputLifecycleState::Idle => Icon::Microphone,
            VoiceInputLifecycleState::Listening => Icon::Stop,
            VoiceInputLifecycleState::Transcribing => Icon::DotsHorizontal,
        };
        let is_transcribing = matches!(
            self.cli_voice_input_lifecycle.state(),
            VoiceInputLifecycleState::Transcribing
        );

        self.mic_button.update(ctx, |button, ctx| {
            button.set_icon(Some(icon), ctx);
            button.set_active(is_transcribing, ctx);
        });
    }

    pub(super) fn show_cli_voice_error_toast(&self, message: &str, ctx: &mut ViewContext<Self>) {
        let window_id = ctx.window_id();
        ToastStack::handle(ctx).update(ctx, |toast_stack, ctx| {
            let toast = DismissibleToast::error(message.to_string());
            toast_stack.add_ephemeral_toast(toast, window_id, ctx);
        });
    }

    pub(super) fn show_cli_microphone_access_toast(&self, ctx: &mut ViewContext<Self>) {
        let window_id = ctx.window_id();
        ToastStack::handle(ctx).update(ctx, |toast_stack, ctx| {
            let toast = DismissibleToast::error(String::from(
                "Failed to start voice input (you may need to enable Microphone access)",
            ));
            toast_stack.add_ephemeral_toast(toast, window_id, ctx);
        });
    }

    pub(super) fn maybe_show_first_time_cli_voice_toast(&self, ctx: &mut ViewContext<Self>) {
        let window_id = ctx.window_id();
        AISettings::handle(ctx).update(ctx, |settings, ctx| {
            if let Some(toggle_key) = settings.maybe_setup_first_time_voice(ctx) {
                ToastStack::handle(ctx).update(ctx, |toast_stack, ctx| {
                    let toast = DismissibleToast::success(format!(
                        "Voice input is enabled. You can also press and hold the `{}` key to activate voice input (configure in Settings > AI > Voice)",
                        toggle_key.display_name()
                    ));
                    toast_stack.add_ephemeral_toast(toast, window_id, ctx);
                });
            }
        });
    }
}
