use warpui::elements::{
    Container, CrossAxisAlignment, Flex, MainAxisAlignment, MainAxisSize, MouseStateHandle,
    ParentElement,
};
use warpui::ui_components::button::ButtonVariant;
use warpui::ui_components::components::{Coords, UiComponent, UiComponentStyles};
use warpui::{AppContext, Element, Entity, SingletonEntity, TypedActionView, View, ViewContext};

use crate::appearance::Appearance;

const BODY_FONT_SIZE: f32 = 13.;

const DELETE_DESCRIPTION: &str = "This permanently deletes every command OpenRun has saved, \
    and the command text and output of every block it saved for session restore. Your window, \
    tab and pane layout is not changed, and your shell's own history file (for example \
    ~/.zsh_history or ~/.bash_history) is not touched.";

const TURNED_OFF_INTRO: &str = "OpenRun has stopped saving command history. Commands and block \
    output saved earlier stay on disk until you delete them.";

/// Confirmation shown before [`crate::persistence::ModelEvent::DeleteSavedHistory`] is sent. Also
/// offered right after the user turns "Save command history" off.
pub struct DeleteHistoryModal {
    offered_after_turning_off: bool,
    cancel_button_mouse_state: MouseStateHandle,
    confirm_button_mouse_state: MouseStateHandle,
}

#[derive(Debug)]
pub enum DeleteHistoryModalAction {
    Cancel,
    Confirm,
}

pub enum DeleteHistoryModalEvent {
    Close,
    Confirm,
}

impl DeleteHistoryModal {
    pub fn new(_ctx: &mut ViewContext<Self>) -> Self {
        Self {
            offered_after_turning_off: false,
            cancel_button_mouse_state: Default::default(),
            confirm_button_mouse_state: Default::default(),
        }
    }

    /// `true` when the modal is shown because the user just turned history saving off.
    pub fn set_offered_after_turning_off(
        &mut self,
        offered_after_turning_off: bool,
        ctx: &mut ViewContext<Self>,
    ) {
        self.offered_after_turning_off = offered_after_turning_off;
        ctx.notify();
    }

    fn cancel_label(&self) -> &'static str {
        if self.offered_after_turning_off {
            "Keep saved history"
        } else {
            "Cancel"
        }
    }

    fn description(&self) -> String {
        if self.offered_after_turning_off {
            format!("{TURNED_OFF_INTRO} {DELETE_DESCRIPTION}")
        } else {
            DELETE_DESCRIPTION.to_owned()
        }
    }
}

impl Entity for DeleteHistoryModal {
    type Event = DeleteHistoryModalEvent;
}

impl View for DeleteHistoryModal {
    fn ui_name() -> &'static str {
        "DeleteHistoryModal"
    }

    fn render(&self, app: &AppContext) -> Box<dyn Element> {
        let appearance = Appearance::as_ref(app);
        let theme = appearance.theme();

        let button_style = UiComponentStyles {
            font_size: Some(14.),
            padding: Some(Coords::uniform(8.).left(12.).right(12.)),
            ..Default::default()
        };

        let description = appearance
            .ui_builder()
            .paragraph(self.description())
            .with_style(UiComponentStyles {
                font_color: Some(theme.active_ui_text_color().into_solid()),
                font_size: Some(BODY_FONT_SIZE),
                ..Default::default()
            })
            .build()
            .finish();

        let buttons_row = Flex::row()
            .with_main_axis_size(MainAxisSize::Max)
            .with_main_axis_alignment(MainAxisAlignment::End)
            .with_cross_axis_alignment(CrossAxisAlignment::Center)
            .with_child(
                appearance
                    .ui_builder()
                    .button(
                        ButtonVariant::Secondary,
                        self.cancel_button_mouse_state.clone(),
                    )
                    .with_text_label(self.cancel_label().to_string())
                    .with_style(button_style)
                    .build()
                    .on_click(move |ctx, _, _| {
                        ctx.dispatch_typed_action(DeleteHistoryModalAction::Cancel);
                    })
                    .finish(),
            )
            .with_child(
                Container::new(
                    appearance
                        .ui_builder()
                        .button(
                            ButtonVariant::Error,
                            self.confirm_button_mouse_state.clone(),
                        )
                        .with_text_label("Delete saved history".to_string())
                        .with_style(button_style)
                        .build()
                        .on_click(move |ctx, _, _| {
                            ctx.dispatch_typed_action(DeleteHistoryModalAction::Confirm);
                        })
                        .finish(),
                )
                .with_margin_left(12.)
                .finish(),
            )
            .finish();

        Flex::column()
            .with_child(Container::new(description).with_margin_bottom(24.).finish())
            .with_child(buttons_row)
            .finish()
    }
}

impl TypedActionView for DeleteHistoryModal {
    type Action = DeleteHistoryModalAction;

    fn handle_action(&mut self, action: &Self::Action, ctx: &mut ViewContext<Self>) {
        match action {
            DeleteHistoryModalAction::Cancel => ctx.emit(DeleteHistoryModalEvent::Close),
            DeleteHistoryModalAction::Confirm => ctx.emit(DeleteHistoryModalEvent::Confirm),
        }
    }
}
