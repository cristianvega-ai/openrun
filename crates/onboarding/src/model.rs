use warp_core::send_telemetry_from_ctx;
use warpui_core::{Entity, ModelContext};

use crate::telemetry::OnboardingEvent;

/// UI customization settings chosen during the "Customize your UI" onboarding slide.
#[derive(Clone, Debug, Default)]
pub struct UICustomizationSettings {
    pub use_vertical_tabs: bool,
    pub show_project_explorer: bool,
    pub show_global_search: bool,
    pub show_code_review_button: bool,
}

impl UICustomizationSettings {
    /// Returns true if any tools-panel sub-setting is enabled.
    pub fn tools_panel_enabled(&self) -> bool {
        self.show_project_explorer || self.show_global_search
    }
}

/// The settings chosen over the course of the onboarding slides.
#[derive(Clone, Debug)]
pub struct SelectedSettings {
    pub ui_customization: UICustomizationSettings,
    /// Whether the CLI agent toolbar is enabled (maps to `should_render_cli_agent_footer`).
    pub cli_agent_toolbar_enabled: bool,
    /// Whether agent notifications (mailbox button, toasts, notification items) are shown.
    pub show_agent_notifications: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum OnboardingStep {
    Intro,
    Customize,
    ThirdParty,
    ThemePicker,
}

#[derive(Clone, Debug)]
pub(crate) enum OnboardingStateEvent {
    SelectedSlideChanged,
    Completed,
}

#[derive(Clone, Debug)]
pub(crate) struct OnboardingStateModel {
    step: OnboardingStep,
    ui_customization: UICustomizationSettings,
    cli_agent_toolbar_enabled: bool,
    show_agent_notifications: bool,
}

impl OnboardingStateModel {
    pub(crate) fn new() -> Self {
        Self {
            step: OnboardingStep::Intro,
            ui_customization: UICustomizationSettings::default(),
            cli_agent_toolbar_enabled: true,
            show_agent_notifications: true,
        }
    }

    pub(crate) fn settings(&self) -> SelectedSettings {
        SelectedSettings {
            ui_customization: self.ui_customization.clone(),
            cli_agent_toolbar_enabled: self.cli_agent_toolbar_enabled,
            show_agent_notifications: self.show_agent_notifications,
        }
    }

    pub(crate) fn step(&self) -> OnboardingStep {
        self.step
    }

    pub fn ui_customization(&self) -> &UICustomizationSettings {
        &self.ui_customization
    }

    pub(crate) fn cli_agent_toolbar_enabled(&self) -> bool {
        self.cli_agent_toolbar_enabled
    }

    pub(crate) fn show_agent_notifications(&self) -> bool {
        self.show_agent_notifications
    }

    pub(crate) fn set_use_vertical_tabs(&mut self, value: bool, ctx: &mut ModelContext<Self>) {
        if self.ui_customization.use_vertical_tabs == value {
            return;
        }
        send_telemetry_from_ctx!(
            OnboardingEvent::SettingChanged {
                setting: "tab_styling".to_string(),
                value: if value { "vertical" } else { "horizontal" }.to_string(),
            },
            ctx
        );
        self.ui_customization.use_vertical_tabs = value;
        ctx.notify();
    }

    pub(crate) fn set_tools_panel_enabled(&mut self, enabled: bool, ctx: &mut ModelContext<Self>) {
        send_telemetry_from_ctx!(
            OnboardingEvent::SettingChanged {
                setting: "tools_panel".to_string(),
                value: if enabled { "enabled" } else { "disabled" }.to_string(),
            },
            ctx
        );
        self.ui_customization.show_project_explorer = enabled;
        self.ui_customization.show_global_search = enabled;
        ctx.notify();
    }

    pub(crate) fn set_show_project_explorer(&mut self, value: bool, ctx: &mut ModelContext<Self>) {
        if self.ui_customization.show_project_explorer == value {
            return;
        }
        send_telemetry_from_ctx!(
            OnboardingEvent::SettingChanged {
                setting: "project_explorer".to_string(),
                value: value.to_string(),
            },
            ctx
        );
        self.ui_customization.show_project_explorer = value;
        ctx.notify();
    }

    pub(crate) fn set_show_global_search(&mut self, value: bool, ctx: &mut ModelContext<Self>) {
        if self.ui_customization.show_global_search == value {
            return;
        }
        send_telemetry_from_ctx!(
            OnboardingEvent::SettingChanged {
                setting: "global_search".to_string(),
                value: value.to_string(),
            },
            ctx
        );
        self.ui_customization.show_global_search = value;
        ctx.notify();
    }

    pub(crate) fn set_show_code_review_button(
        &mut self,
        value: bool,
        ctx: &mut ModelContext<Self>,
    ) {
        if self.ui_customization.show_code_review_button == value {
            return;
        }
        send_telemetry_from_ctx!(
            OnboardingEvent::SettingChanged {
                setting: "code_review".to_string(),
                value: if value { "enabled" } else { "disabled" }.to_string(),
            },
            ctx
        );
        self.ui_customization.show_code_review_button = value;
        ctx.notify();
    }

    pub(crate) fn set_cli_agent_toolbar_enabled(
        &mut self,
        value: bool,
        ctx: &mut ModelContext<Self>,
    ) {
        if self.cli_agent_toolbar_enabled == value {
            return;
        }
        send_telemetry_from_ctx!(
            OnboardingEvent::SettingChanged {
                setting: "cli_agent_toolbar".to_string(),
                value: if value { "enabled" } else { "disabled" }.to_string(),
            },
            ctx
        );
        self.cli_agent_toolbar_enabled = value;
        ctx.notify();
    }

    pub(crate) fn set_show_agent_notifications(
        &mut self,
        value: bool,
        ctx: &mut ModelContext<Self>,
    ) {
        if self.show_agent_notifications == value {
            return;
        }
        send_telemetry_from_ctx!(
            OnboardingEvent::SettingChanged {
                setting: "show_agent_notifications".to_string(),
                value: if value { "enabled" } else { "disabled" }.to_string(),
            },
            ctx
        );
        self.show_agent_notifications = value;
        ctx.notify();
    }

    pub(crate) fn complete(&mut self, ctx: &mut ModelContext<Self>) {
        send_telemetry_from_ctx!(OnboardingEvent::OnboardingSlidesCompleted, ctx);
        ctx.emit(OnboardingStateEvent::Completed);
        ctx.notify();
    }

    pub(crate) fn back(&mut self, ctx: &mut ModelContext<Self>) {
        let prev = match self.step {
            OnboardingStep::Intro => None,
            OnboardingStep::Customize => Some(OnboardingStep::Intro),
            OnboardingStep::ThirdParty => Some(OnboardingStep::Customize),
            OnboardingStep::ThemePicker => Some(OnboardingStep::ThirdParty),
        };

        if let Some(prev) = prev {
            send_telemetry_from_ctx!(OnboardingEvent::SlideNavigatedBack, ctx);
            self.set_step(prev, ctx);
        }
    }

    pub(crate) fn next(&mut self, ctx: &mut ModelContext<Self>) {
        let next = match self.step {
            OnboardingStep::Intro => Some(OnboardingStep::Customize),
            OnboardingStep::Customize => Some(OnboardingStep::ThirdParty),
            OnboardingStep::ThirdParty => Some(OnboardingStep::ThemePicker),
            OnboardingStep::ThemePicker => None,
        };

        if let Some(next) = next {
            send_telemetry_from_ctx!(OnboardingEvent::SlideNavigatedNext, ctx);
            self.set_step(next, ctx);
        }
    }

    pub(crate) fn set_step(&mut self, step: OnboardingStep, ctx: &mut ModelContext<Self>) {
        if self.step == step {
            return;
        }

        self.step = step;

        let slide_name = match step {
            OnboardingStep::Intro => "welcome",
            OnboardingStep::Customize => "customize",
            OnboardingStep::ThirdParty => "third_party",
            OnboardingStep::ThemePicker => "theme_picker",
        };
        send_telemetry_from_ctx!(
            OnboardingEvent::SlideViewed {
                slide_name: slide_name.to_string(),
            },
            ctx
        );

        ctx.emit(OnboardingStateEvent::SelectedSlideChanged);
        ctx.notify();
    }

    /// The `(step_index, step_count)` shown by the bottom-nav progress dots for the current step.
    /// The intro slide has no progress dots and shares the first position.
    pub(crate) fn progress(&self) -> (usize, usize) {
        let step_index = match self.step {
            OnboardingStep::Intro | OnboardingStep::Customize => 0,
            OnboardingStep::ThirdParty => 1,
            OnboardingStep::ThemePicker => 2,
        };
        (step_index, 3)
    }
}

impl Entity for OnboardingStateModel {
    type Event = OnboardingStateEvent;
}

#[cfg(test)]
#[path = "model_tests.rs"]
mod tests;
