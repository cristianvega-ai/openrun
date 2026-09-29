//! Footer control bar shown while a third-party CLI agent (Claude Code, Codex,
//! Gemini CLI, ...) is running in the terminal.
//!
//! A single `ViewHandle<CLIAgentFooter>` is shared between `Input` (which
//! renders it under the rich input composer) and `UseAgentToolbar` (which
//! renders it under the running command). What is shown is determined by the
//! CLI agent toolbar layout in [`SessionSettings`].

mod chips;
pub mod editor;
pub mod toolbar_item;

use std::sync::Arc;

use parking_lot::FairMutex;
use pathfinder_color::ColorU;
use pathfinder_geometry::vector::Vector2F;
use toolbar_item::CLIAgentToolbarItemKind;
use warp_core::ui::color::ContrastingColor;
use warp_core::ui::color::blend::Blend;
use warp_core::ui::color::contrast::MinimumAllowedContrast;
use warp_core::ui::theme::Fill;
use warp_core::ui::theme::color::internal_colors;
use warpui::elements::{
    ChildView, ConstrainedBox, Container, CrossAxisAlignment, DispatchEventResult, Element,
    EventHandler, Flex, MainAxisAlignment, MainAxisSize, ParentElement, Wrap, WrapFill,
    WrapFillEntireRun,
};
use warpui::{
    AppContext, Entity, EntityId, ModelHandle, SingletonEntity, TypedActionView, View, ViewContext,
    ViewHandle,
};

use crate::appearance::Appearance;
use crate::context_chips::display_chip::{DisplayChip, DisplayChipConfig, PromptChipShellCommand};
use crate::context_chips::prompt_type::PromptType;
use crate::context_chips::{self, ContextChipKind};
use crate::settings::{CodeSettings, CodeSettingsChangedEvent};
use crate::settings_view::SettingsSection;
use crate::terminal::cli_agent_sessions::{
    CLIAgentInputState, CLIAgentSessionsModel, CLIAgentSessionsModelEvent,
};
use crate::terminal::session_settings::{
    SessionSettings, SessionSettingsChangedEvent, ToolbarChipSelection,
};
use crate::terminal::view::init::{ATTACH_FILE_KEYBINDING, OPEN_CLI_AGENT_RICH_INPUT_KEYBINDING};
use crate::terminal::{CLIAgent, TerminalModel};
use crate::ui_components::icons::Icon;
use crate::view_components::DismissibleToast;
use crate::view_components::action_button::{
    ActionButton, ActionButtonTheme, ButtonSize, KeystrokeSource, TooltipAlignment,
};
use crate::workspace::ToastStack;
#[cfg(not(target_family = "wasm"))]
use crate::workspace::WorkspaceAction;
use crate::workspace::view::TOGGLE_PROJECT_EXPLORER_BINDING_NAME;

pub struct CLIAgentFooter {
    terminal_view_id: EntityId,
    terminal_model: Arc<FairMutex<TerminalModel>>,
    display_chips: Vec<ViewHandle<DisplayChip>>,
    display_chip_config: DisplayChipConfig,

    file_button: ViewHandle<ActionButton>,
    file_explorer_button: ViewHandle<ActionButton>,
    rich_input_button: ViewHandle<ActionButton>,
    settings_button: ViewHandle<ActionButton>,
}

impl CLIAgentFooter {
    pub fn new(
        terminal_view_id: EntityId,
        terminal_model: Arc<FairMutex<TerminalModel>>,
        prompt: ModelHandle<PromptType>,
        display_chip_config: DisplayChipConfig,
        ctx: &mut ViewContext<Self>,
    ) -> Self {
        let button_size = ButtonSize::AgentInputButton;

        let file_button = ctx.add_typed_action_view(|_ctx| {
            ActionButton::new("", AgentInputButtonTheme)
                .with_icon(Icon::Plus)
                .with_tooltip("Attach file")
                .with_tooltip_keybinding(ATTACH_FILE_KEYBINDING)
                .with_size(button_size)
                .with_tooltip_alignment(TooltipAlignment::Left)
                .on_click(|ctx| {
                    ctx.dispatch_typed_action(CLIAgentFooterAction::SelectFile);
                })
        });
        let file_explorer_button = ctx.add_typed_action_view(|ctx| {
            ActionButton::new("File explorer", AgentInputButtonTheme)
                .with_icon(Icon::FileCopy)
                .with_tooltip("Open file explorer")
                .with_size(button_size)
                .with_tooltip_alignment(TooltipAlignment::Left)
                .with_keybinding(
                    KeystrokeSource::Binding(TOGGLE_PROJECT_EXPLORER_BINDING_NAME),
                    ctx,
                )
                .with_compact_keybinding(true)
                .on_click(|ctx| {
                    ctx.dispatch_typed_action(CLIAgentFooterAction::ToggleFileExplorer);
                })
        });
        let rich_input_button = ctx.add_typed_action_view(|ctx| {
            ActionButton::new("Rich Input", AgentInputButtonTheme)
                .with_icon(Icon::TextInput)
                .with_tooltip("Open Rich Input")
                .with_size(button_size)
                .with_tooltip_alignment(TooltipAlignment::Left)
                .with_keybinding(
                    KeystrokeSource::Binding(OPEN_CLI_AGENT_RICH_INPUT_KEYBINDING),
                    ctx,
                )
                .with_compact_keybinding(true)
                .on_click(|ctx| {
                    ctx.dispatch_typed_action(CLIAgentFooterAction::ToggleRichInput);
                })
        });
        let settings_button = ctx.add_typed_action_view(|_ctx| {
            ActionButton::new("", AgentInputButtonTheme)
                .with_icon(Icon::Settings)
                .with_tooltip("Open coding agent settings")
                .with_size(button_size)
                .with_tooltip_alignment(TooltipAlignment::Left)
                .on_click(|ctx| {
                    ctx.dispatch_typed_action(CLIAgentFooterAction::OpenCodingAgentSettings);
                })
        });

        // Toggle rich input button label when CLI input session opens/closes.
        ctx.subscribe_to_model(
            &CLIAgentSessionsModel::handle(ctx),
            move |me, _, event, ctx| {
                if event.terminal_view_id() != terminal_view_id {
                    return;
                }

                let CLIAgentSessionsModelEvent::InputSessionChanged {
                    new_input_state, ..
                } = event
                else {
                    ctx.notify();
                    return;
                };
                let is_open = matches!(new_input_state, CLIAgentInputState::Open { .. });
                me.rich_input_button.update(ctx, |button, ctx| {
                    let (label, tooltip) = if is_open {
                        ("Hide Rich Input", "Hide Rich Input")
                    } else {
                        ("Rich Input", "Open Rich Input")
                    };
                    button.set_label(label, ctx);
                    button.set_tooltip(Some(tooltip), ctx);
                    button.set_keybinding(
                        Some(KeystrokeSource::Binding(
                            OPEN_CLI_AGENT_RICH_INPUT_KEYBINDING,
                        )),
                        ctx,
                    );
                });
                ctx.notify();
            },
        );

        // The File explorer item's availability follows this setting, so the footer has to
        // repaint when it is toggled rather than waiting for an unrelated re-render.
        ctx.subscribe_to_model(&CodeSettings::handle(ctx), |_, _, event, ctx| {
            if matches!(event, CodeSettingsChangedEvent::ShowProjectExplorer { .. }) {
                ctx.notify()
            }
        });

        let prompt_for_session_settings = prompt.clone();
        ctx.subscribe_to_model(
            &SessionSettings::handle(ctx),
            move |me, _, event, ctx| match event {
                SessionSettingsChangedEvent::CLIAgentToolbarChipSelectionSetting { .. }
                | SessionSettingsChangedEvent::GithubPrChipDefaultValidation { .. } => {
                    me.update_display_chips(&prompt_for_session_settings, ctx);
                    ctx.notify();
                }
                _ => {}
            },
        );
        ctx.observe(&prompt, |me, model, ctx| {
            me.update_display_chips(&model, ctx);
        });

        let mut me = Self {
            terminal_view_id,
            terminal_model,
            display_chips: vec![],
            display_chip_config,
            file_button,
            file_explorer_button,
            rich_input_button,
            settings_button,
        };
        me.update_display_chips(&prompt, ctx);
        me
    }

    pub fn set_current_repo_path(
        &mut self,
        repo_path: Option<std::path::PathBuf>,
        ctx: &mut ViewContext<Self>,
    ) {
        self.display_chip_config.current_repo_path = repo_path;
        ctx.notify();
    }

    pub fn update_session_context(
        &mut self,
        session_context: Option<crate::completer::SessionContext>,
        ctx: &mut ViewContext<Self>,
    ) {
        self.display_chip_config.session_context = session_context.clone();
        for chip_view in &self.display_chips {
            chip_view.update(ctx, |chip, chip_ctx| {
                chip.update_session_context(session_context.clone(), chip_ctx);
            });
        }
    }

    pub fn has_open_chip_menu(&self, app: &AppContext) -> bool {
        self.display_chips
            .iter()
            .any(|chip| chip.as_ref(app).display_chip_kind().has_open_menu())
    }

    fn has_active_cli_agent_input_session(&self, app: &AppContext) -> bool {
        CLIAgentSessionsModel::as_ref(app).is_input_open(self.terminal_view_id)
    }

    fn cli_agent(&self, app: &AppContext) -> Option<CLIAgent> {
        CLIAgentSessionsModel::as_ref(app)
            .session(self.terminal_view_id)
            .map(|session| session.agent)
    }

    pub(crate) fn select_file(&mut self, ctx: &mut ViewContext<Self>) {
        let window_id = ctx.window_id();
        let view_id = ctx.view_id();
        let file_picker_config = warpui::platform::FilePickerConfiguration::new();

        ctx.open_file_picker(
            move |result, ctx| match result {
                Ok(paths) => {
                    if let Some(path) = paths.first() {
                        ctx.dispatch_typed_action_for_view(
                            window_id,
                            view_id,
                            &CLIAgentFooterAction::InsertFilePath(path.clone()),
                        );
                    }
                }
                Err(err) => {
                    let window_id = ctx.window_id();
                    ToastStack::handle(ctx).update(ctx, |toast_stack, ctx| {
                        toast_stack.add_ephemeral_toast(
                            DismissibleToast::error(format!("{err}")),
                            window_id,
                            ctx,
                        );
                    });
                }
            },
            file_picker_config,
        );
    }

    #[cfg(test)]
    pub fn display_chip_kinds(&self, app: &AppContext) -> Vec<ContextChipKind> {
        self.display_chips
            .iter()
            .map(|chip| chip.as_ref(app).chip_kind().clone())
            .collect()
    }
}

impl CLIAgentFooter {
    fn display_chip(
        &self,
        chip_kind: &ContextChipKind,
        app: &AppContext,
    ) -> Option<Box<dyn Element>> {
        self.display_chips
            .iter()
            .find(|chip| chip.as_ref(app).chip_kind() == chip_kind)
            .map(|chip| ChildView::new(chip).finish())
    }

    fn render_toolbar_item(
        &self,
        item: &CLIAgentToolbarItemKind,
        app: &AppContext,
    ) -> Option<Box<dyn Element>> {
        match item {
            CLIAgentToolbarItemKind::ContextChip(chip_kind) => self.display_chip(chip_kind, app),
            CLIAgentToolbarItemKind::FileExplorer => item
                .is_available(app)
                .then(|| ChildView::new(&self.file_explorer_button).finish()),
            CLIAgentToolbarItemKind::RichInput => {
                Some(ChildView::new(&self.rich_input_button).finish())
            }
            CLIAgentToolbarItemKind::FileAttach => Some(ChildView::new(&self.file_button).finish()),
            CLIAgentToolbarItemKind::Settings => {
                Some(ChildView::new(&self.settings_button).finish())
            }
        }
    }
}

impl View for CLIAgentFooter {
    fn ui_name() -> &'static str {
        "CLIAgentFooter"
    }

    fn render(&self, app: &AppContext) -> Box<dyn Element> {
        let appearance = Appearance::as_ref(app);
        let cli_icon_size = ButtonSize::AgentInputButton.icon_size(appearance, app);

        // Extract everything we need from the terminal model up front and drop
        // the lock before calling into helpers like `should_use_manual_mode`
        // and `render_toolbar_item`, which may re-lock the same model and
        // would deadlock since the lock is non-reentrant.
        let background_color = {
            let terminal_model = self.terminal_model.lock();
            let background_color = if terminal_model.is_alt_screen_active() {
                terminal_model
                    .alt_screen()
                    .inferred_bg_color()
                    .unwrap_or_else(|| appearance.theme().surface_1().into_solid())
            } else {
                appearance.theme().surface_1().into_solid()
            };
            background_color
        };

        let session_settings = SessionSettings::as_ref(app);
        let left_items = session_settings
            .cli_agent_footer_chip_selection
            .left_items();
        let right_items = session_settings
            .cli_agent_footer_chip_selection
            .right_items();

        let mut left_buttons = Wrap::row()
            .with_main_axis_size(MainAxisSize::Min)
            .with_cross_axis_alignment(CrossAxisAlignment::Center)
            .with_main_axis_alignment(MainAxisAlignment::Start)
            .with_run_spacing(4.)
            .with_spacing(4.);

        // CLI agent brand icon is always rendered (not configurable).
        if let Some(agent) = self.cli_agent(app)
            && let Some(icon) = agent.icon()
        {
            let icon_color = agent
                .brand_color()
                .map(|c| c.on_background(background_color, MinimumAllowedContrast::NonText))
                .unwrap_or_else(|| appearance.theme().foreground().into_solid());
            left_buttons.add_child(
                Container::new(
                    ConstrainedBox::new(icon.to_warpui_icon(Fill::Solid(icon_color)).finish())
                        .with_width(cli_icon_size)
                        .with_height(cli_icon_size)
                        .finish(),
                )
                .with_padding_right(8.)
                .finish(),
            );
        }

        for item in &left_items {
            if let Some(element) = self.render_toolbar_item(item, app) {
                left_buttons.add_child(element);
            }
        }

        let mut right_buttons = Flex::row()
            .with_cross_axis_alignment(CrossAxisAlignment::Center)
            .with_main_axis_size(MainAxisSize::Min)
            .with_spacing(4.);

        for item in &right_items {
            if let Some(element) = self.render_toolbar_item(item, app) {
                right_buttons.add_child(element);
            }
        }

        let content = Wrap::row()
            .with_main_axis_size(MainAxisSize::Max)
            .with_main_axis_alignment(MainAxisAlignment::SpaceBetween)
            .with_cross_axis_alignment(CrossAxisAlignment::Center)
            .with_child(WrapFillEntireRun::new(left_buttons.finish()).finish())
            .with_child(WrapFill::new(0., right_buttons.finish()).finish())
            .with_run_spacing(context_chips::spacing::UDI_ROW_RUN_SPACING)
            .finish();
        let content = EventHandler::new(content)
            .on_right_mouse_down(|ctx, _, position, _| {
                ctx.dispatch_typed_action(CLIAgentFooterAction::ShowContextMenu { position });
                DispatchEventResult::StopPropagation
            })
            .finish();

        Container::new(content).with_vertical_padding(4.).finish()
    }
}

#[derive(Debug, Clone)]
pub enum CLIAgentFooterAction {
    SelectFile,
    InsertFilePath(String),
    ToggleFileExplorer,
    ToggleRichInput,
    OpenCodingAgentSettings,
    ShowContextMenu { position: Vector2F },
}

impl TypedActionView for CLIAgentFooter {
    type Action = CLIAgentFooterAction;

    fn handle_action(&mut self, action: &Self::Action, ctx: &mut ViewContext<Self>) {
        match action {
            CLIAgentFooterAction::SelectFile => {
                self.select_file(ctx);
            }
            CLIAgentFooterAction::InsertFilePath(path) => {
                let path_with_space = format!("{path} ");
                if self.has_active_cli_agent_input_session(ctx) {
                    ctx.emit(CLIAgentFooterEvent::InsertIntoCLIRichInput(path_with_space));
                } else {
                    ctx.emit(CLIAgentFooterEvent::WriteToPty(path_with_space));
                }
            }
            CLIAgentFooterAction::ToggleFileExplorer => {
                ctx.emit(CLIAgentFooterEvent::ToggleFileExplorer);
            }
            CLIAgentFooterAction::ToggleRichInput => {
                if self.has_active_cli_agent_input_session(ctx) {
                    ctx.emit(CLIAgentFooterEvent::HideRichInput);
                } else {
                    ctx.emit(CLIAgentFooterEvent::OpenRichInput);
                }
            }
            CLIAgentFooterAction::OpenCodingAgentSettings => {
                #[cfg(not(target_family = "wasm"))]
                ctx.dispatch_typed_action_deferred(WorkspaceAction::ScrollToSettingsWidget {
                    page: SettingsSection::ThirdPartyCLIAgents,
                    widget_id: crate::settings_view::cli_agent_settings_widget_id(),
                });
            }
            CLIAgentFooterAction::ShowContextMenu { position } => {
                ctx.emit(CLIAgentFooterEvent::ShowContextMenu {
                    position: *position,
                });
            }
        }
    }
}

pub enum CLIAgentFooterEvent {
    WriteToPty(String),
    /// Insert text into the CLI agent rich input.
    InsertIntoCLIRichInput(String),
    /// Toggle the file explorer side panel.
    ToggleFileExplorer,
    OpenRichInput,
    HideRichInput,
    ToggledChipMenu {
        open: bool,
    },
    TryExecuteChipCommand(PromptChipShellCommand),
    OpenCodeReview,
    ShowContextMenu {
        position: Vector2F,
    },
}

impl Entity for CLIAgentFooter {
    type Event = CLIAgentFooterEvent;
}

pub(crate) struct AgentInputButtonTheme;

impl ActionButtonTheme for AgentInputButtonTheme {
    fn background(&self, hovered: bool, appearance: &Appearance) -> Option<Fill> {
        // Solid surface fills keep the button readable even when its parent
        // isn't `theme.background()` (for example, over an alt-screen CLI agent).
        let theme = appearance.theme();
        Some(if hovered {
            theme.surface_2()
        } else {
            theme.surface_1()
        })
    }

    fn text_color(
        &self,
        _hovered: bool,
        background: Option<Fill>,
        appearance: &Appearance,
    ) -> ColorU {
        // If a caller overrides `background()` with a translucent fill, blend
        // it over `surface_1` so text contrast is computed against the actual
        // rendered color rather than the raw overlay.
        let base_bg = appearance.theme().surface_1();
        let effective_bg = background
            .map(|overlay| base_bg.blend(&overlay))
            .unwrap_or(base_bg);

        appearance.theme().sub_text_color(effective_bg).into_solid()
    }

    fn border(&self, appearance: &Appearance) -> Option<ColorU> {
        Some(internal_colors::neutral_3(appearance.theme()))
    }

    fn should_opt_out_of_contrast_adjustment(&self) -> bool {
        true
    }

    fn font_properties(&self) -> Option<warpui::fonts::Properties> {
        if crate::features::FeatureFlag::CloudModeInputV2.is_enabled() {
            Some(warpui::fonts::Properties {
                weight: warpui::fonts::Weight::Semibold,
                ..Default::default()
            })
        } else {
            None
        }
    }
}

#[cfg(test)]
#[path = "mod_tests.rs"]
mod tests;
