//! Modal for customizing the CLI agent footer chip layout.
//!
//! Uses the shared [`ChipConfigurator`] with `LeftRightZones` layout to let users
//! drag/drop chips between left, right, and unused banks.

use settings::Setting as _;
use warp_errors::report_if_error;
use warpui::keymap::FixedBinding;
use warpui::{AppContext, Element, Entity, SingletonEntity, TypedActionView, View, ViewContext};

use super::toolbar_item::{CLIAgentToolbarItemKind, CLIAgentToolbarItems};
use crate::Appearance;
use crate::appearance::AppearanceEvent;
use crate::chip_configurator::{
    ChipConfigurator, ChipConfiguratorAction, ChipConfiguratorLayout, ChipEditorModalConfig,
    ChipEditorMouseHandles, ChipEditorSectionsConfig, render_chip_editor_modal,
    render_chip_editor_sections,
};
use crate::terminal::session_settings::{
    CLIAgentToolbarChipSelection, SessionSettings, SessionSettingsChangedEvent,
    ToolbarChipSelection,
};

const MODAL_TITLE: &str = "Edit CLI agent toolbelt";

pub enum CLIAgentToolbarEditorEvent {
    Close,
}

pub struct CLIAgentToolbarEditorModal {
    mouse_handles: ChipEditorMouseHandles,
    chip_configurator: ChipConfigurator,
    is_dirty: bool,
}

pub struct CLIAgentToolbarInlineEditor {
    mouse_handles: ChipEditorMouseHandles,
    chip_configurator: ChipConfigurator,
}

#[derive(Clone, Copy, Debug)]
pub enum CLIAgentToolbarEditorAction {
    Cancel,
    Save,
    Chip(ChipConfiguratorAction),
    ResetDefault,
    /// Dummy action used as on_click for chip bank clicks (no-op).
    Activate,
}

#[derive(Clone, Copy, Debug)]
pub enum CLIAgentToolbarInlineEditorAction {
    Chip(ChipConfiguratorAction),
    ResetDefault,
    /// Dummy action used as on_click for chip bank clicks (no-op).
    Activate,
}

fn open_toolbar_items_from_settings<V: View>(
    chip_configurator: &mut ChipConfigurator,
    ctx: &mut ViewContext<V>,
) {
    let appearance = Appearance::as_ref(ctx);
    let selection = SessionSettings::as_ref(ctx)
        .cli_agent_footer_chip_selection
        .clone();

    // Filter out items that are unavailable due to runtime state (user settings,
    // workspace config, etc.).
    let available: Vec<CLIAgentToolbarItemKind> = CLIAgentToolbarItemKind::all_available()
        .into_iter()
        .filter(|item| item.is_available(ctx))
        .collect();

    // Drop saved items that are no longer available (e.g. a setting was turned off).
    let filter_unavailable = |items: Vec<CLIAgentToolbarItemKind>| -> Vec<CLIAgentToolbarItemKind> {
        items
            .into_iter()
            .filter(|item| available.contains(item))
            .collect()
    };
    let current_left = filter_unavailable(selection.left_items());
    let current_right = filter_unavailable(selection.right_items());

    chip_configurator.open_left_right_zones_with_items(
        current_left,
        current_right,
        available.clone(),
        appearance,
    );
}

fn open_default_toolbar_items<V: View>(
    chip_configurator: &mut ChipConfigurator,
    ctx: &mut ViewContext<V>,
) {
    let appearance = Appearance::as_ref(ctx);
    let filter_runtime = |items: Vec<CLIAgentToolbarItemKind>| -> Vec<CLIAgentToolbarItemKind> {
        items
            .into_iter()
            .filter(|item| item.is_available(ctx))
            .collect()
    };
    let left = filter_runtime(CLIAgentToolbarItemKind::default_left());
    let right = filter_runtime(CLIAgentToolbarItemKind::default_right());
    let available = filter_runtime(CLIAgentToolbarItemKind::all_available());
    chip_configurator.open_left_right_zones_with_items(left, right, available, appearance);
}

fn is_toolbar_editor_at_defaults(chip_configurator: &ChipConfigurator) -> bool {
    let left: Vec<CLIAgentToolbarItemKind> = chip_configurator.left_item_kinds();
    let right: Vec<CLIAgentToolbarItemKind> = chip_configurator.right_item_kinds();
    toolbar_items_match_defaults(&left, &right)
}

fn toolbar_items_match_defaults(
    left: &[CLIAgentToolbarItemKind],
    right: &[CLIAgentToolbarItemKind],
) -> bool {
    CLIAgentToolbarItemKind::default_left().as_slice() == left
        && CLIAgentToolbarItemKind::default_right().as_slice() == right
}

fn save_toolbar_selection<V: View>(
    left: Vec<CLIAgentToolbarItemKind>,
    right: Vec<CLIAgentToolbarItemKind>,
    ctx: &mut ViewContext<V>,
) {
    let selection = if toolbar_items_match_defaults(&left, &right) {
        CLIAgentToolbarChipSelection::Default
    } else {
        CLIAgentToolbarChipSelection::Custom {
            left: CLIAgentToolbarItems::from(left),
            right: CLIAgentToolbarItems::from(right),
        }
    };
    SessionSettings::handle(ctx).update(ctx, |settings, ctx| {
        report_if_error!(
            settings
                .cli_agent_footer_chip_selection
                .set_value(selection, ctx)
        );
    });
}

impl CLIAgentToolbarInlineEditor {
    pub fn new(ctx: &mut ViewContext<Self>) -> Self {
        let mut editor = Self {
            mouse_handles: Default::default(),
            chip_configurator: ChipConfigurator::new(ChipConfiguratorLayout::LeftRightZones),
        };
        editor.reset_from_settings(ctx);

        ctx.subscribe_to_model(&SessionSettings::handle(ctx), |me, _, event, ctx| {
            if matches!(
                event,
                SessionSettingsChangedEvent::CLIAgentToolbarChipSelectionSetting { .. }
            ) && me.chip_configurator.current_dragging_state.is_none()
            {
                me.reset_from_settings(ctx);
                ctx.notify();
            }
        });

        // Chip colors are derived from the theme, so rebuild the chips from
        // settings when the theme changes to keep an open editor readable after a
        // theme switch (this inline editor persists its arrangement on every
        // edit, so reloading preserves the user's layout).
        ctx.subscribe_to_model(&Appearance::handle(ctx), |me, _, event, ctx| {
            if matches!(event, AppearanceEvent::ThemeChanged)
                && me.chip_configurator.current_dragging_state.is_none()
            {
                me.reset_from_settings(ctx);
                ctx.notify();
            }
        });

        editor
    }

    fn reset_from_settings(&mut self, ctx: &mut ViewContext<Self>) {
        open_toolbar_items_from_settings(&mut self.chip_configurator, ctx);
    }

    fn save_current_selection(&self, ctx: &mut ViewContext<Self>) {
        let left = self.chip_configurator.left_item_kinds();
        let right = self.chip_configurator.right_item_kinds();
        save_toolbar_selection(left, right, ctx);
    }

    fn is_at_defaults(&self) -> bool {
        is_toolbar_editor_at_defaults(&self.chip_configurator)
    }
}

impl Entity for CLIAgentToolbarInlineEditor {
    type Event = ();
}

impl TypedActionView for CLIAgentToolbarInlineEditor {
    type Action = CLIAgentToolbarInlineEditorAction;

    fn handle_action(&mut self, action: &Self::Action, ctx: &mut ViewContext<Self>) {
        match action {
            Self::Action::Chip(chip_action) => {
                let should_save = self.chip_configurator.handle_action(chip_action, ctx);
                if should_save {
                    self.save_current_selection(ctx);
                }
                ctx.notify();
            }
            Self::Action::ResetDefault => {
                open_default_toolbar_items(&mut self.chip_configurator, ctx);
                self.save_current_selection(ctx);
                ctx.notify();
            }
            Self::Action::Activate => {
                // no-op — used as the on_click for chip bank items
            }
        }
    }
}

impl View for CLIAgentToolbarInlineEditor {
    fn ui_name() -> &'static str {
        "CLIAgentToolbarInlineEditor"
    }

    fn render(&self, app: &AppContext) -> Box<dyn Element> {
        let appearance = Appearance::as_ref(app);
        render_chip_editor_sections(
            &self.chip_configurator,
            ChipEditorSectionsConfig {
                available_section_label: "Available chips",
                is_at_defaults: self.is_at_defaults(),
                reset_action: CLIAgentToolbarInlineEditorAction::ResetDefault,
                activate_action: CLIAgentToolbarInlineEditorAction::Activate,
                chip_action_wrapper: CLIAgentToolbarInlineEditorAction::Chip,
                mouse_handles: &self.mouse_handles,
            },
            appearance,
        )
    }
}

pub fn init(app: &mut AppContext) {
    use warpui::keymap::macros::*;

    app.register_fixed_bindings([FixedBinding::new(
        "escape",
        CLIAgentToolbarEditorAction::Cancel,
        id!(CLIAgentToolbarEditorModal::ui_name()),
    )]);
}

impl CLIAgentToolbarEditorModal {
    pub fn new(ctx: &mut ViewContext<Self>) -> Self {
        // Chip colors are derived from the theme, so rebuild the chips when the
        // theme changes to keep an open editor readable after a theme switch.
        // Only rebuild while the modal is actually open (has chips) and not
        // mid-drag.
        ctx.subscribe_to_model(&Appearance::handle(ctx), |me, _, event, ctx| {
            if matches!(event, AppearanceEvent::ThemeChanged)
                && me.chip_configurator.current_dragging_state.is_none()
                && me.chip_configurator.has_items()
            {
                open_toolbar_items_from_settings(&mut me.chip_configurator, ctx);
                ctx.notify();
            }
        });
        Self {
            mouse_handles: Default::default(),
            chip_configurator: ChipConfigurator::new(ChipConfiguratorLayout::LeftRightZones),
            is_dirty: false,
        }
    }

    pub fn open(&mut self, ctx: &mut ViewContext<Self>) {
        self.reset();
        open_toolbar_items_from_settings(&mut self.chip_configurator, ctx);
        ctx.notify();
    }

    fn save_to_settings(&mut self, ctx: &mut ViewContext<Self>) {
        if !self.is_dirty {
            return;
        }

        let left = self.chip_configurator.left_item_kinds();
        let right = self.chip_configurator.right_item_kinds();
        save_toolbar_selection(left, right, ctx);
    }

    fn reset(&mut self) {
        self.chip_configurator.reset();
        self.is_dirty = false;
    }

    fn is_at_defaults(&self) -> bool {
        is_toolbar_editor_at_defaults(&self.chip_configurator)
    }
}

impl Entity for CLIAgentToolbarEditorModal {
    type Event = CLIAgentToolbarEditorEvent;
}

impl TypedActionView for CLIAgentToolbarEditorModal {
    type Action = CLIAgentToolbarEditorAction;

    fn handle_action(&mut self, action: &Self::Action, ctx: &mut ViewContext<Self>) {
        match action {
            Self::Action::Cancel => {
                self.reset();
                ctx.emit(CLIAgentToolbarEditorEvent::Close);
            }
            Self::Action::Save => {
                self.save_to_settings(ctx);
                ctx.emit(CLIAgentToolbarEditorEvent::Close);
            }
            Self::Action::Chip(chip_action) => {
                let mutated = self.chip_configurator.handle_action(chip_action, ctx);
                if mutated {
                    self.is_dirty = true;
                }
                ctx.notify();
            }
            Self::Action::ResetDefault => {
                self.is_dirty = true;
                open_default_toolbar_items(&mut self.chip_configurator, ctx);
                ctx.notify();
            }
            Self::Action::Activate => {
                // no-op — used as the on_click for chip bank items
            }
        }
    }
}

impl View for CLIAgentToolbarEditorModal {
    fn ui_name() -> &'static str {
        "CLIAgentToolbarEditorModal"
    }

    fn render(&self, app: &AppContext) -> Box<dyn Element> {
        let appearance = Appearance::as_ref(app);
        render_chip_editor_modal(
            &self.chip_configurator,
            ChipEditorModalConfig {
                title: MODAL_TITLE,
                available_section_label: "Available chips",
                is_at_defaults: self.is_at_defaults(),
                is_dirty: self.is_dirty,
                cancel_action: CLIAgentToolbarEditorAction::Cancel,
                save_action: CLIAgentToolbarEditorAction::Save,
                reset_action: CLIAgentToolbarEditorAction::ResetDefault,
                activate_action: CLIAgentToolbarEditorAction::Activate,
                chip_action_wrapper: CLIAgentToolbarEditorAction::Chip,
                mouse_handles: &self.mouse_handles,
            },
            appearance,
        )
    }
}
