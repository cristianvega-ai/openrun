use std::sync::Arc;

use warp_core::ui::appearance::Appearance;
use warpui::elements::{
    Align, ConstrainedBox, Container, CrossAxisAlignment, Expanded, Flex, MainAxisAlignment,
    MainAxisSize, ParentElement, Shrinkable, SizeConstraintCondition, SizeConstraintSwitch, Text,
};
use warpui::{
    AppContext, Element, Entity, FocusContext, SingletonEntity, TypedActionView, View, ViewContext,
};

use crate::ai::agent::{AIAgentActionId, AIIdentifiers};
use crate::ui_components::icons::Icon;
use crate::view_components::action_button::{ButtonSize, NakedTheme, PrimaryTheme};
use crate::view_components::compactible_action_button::{
    CompactibleActionButton, MEDIUM_SIZE_SWITCH_THRESHOLD, render_compact_and_regular_button_rows,
};

const ACCEPT_LABEL: &str = "Generate tests";
const CANCEL_LABEL: &str = "Dismiss";

#[derive(Debug, Clone)]
pub enum SuggestedUnitTestsEvent {
    Accept,
    Cancel,
    Blur,
}

#[derive(Debug, Clone)]
pub enum SuggestedUnitTestsAction {
    Accept,
    Cancel,
}

pub struct SuggestedUnitTestsView {
    /// Client and server identifiers for the AI output associated with the suggested prompt.
    identifiers: AIIdentifiers,
    action_id: AIAgentActionId,

    is_hidden: bool,
    is_keybindings_hidden: bool,
    title: String,
    description: String,
    query: String,
    accept_button: CompactibleActionButton,
    cancel_button: CompactibleActionButton,
}

impl SuggestedUnitTestsView {
    pub fn new(
        identifiers: AIIdentifiers,
        action_id: AIAgentActionId,
        query: String,
        title: String,
        description: String,
        ctx: &mut ViewContext<Self>,
    ) -> Self {
        let accept_button = CompactibleActionButton::new(
            ACCEPT_LABEL.to_string(),
            None,
            ButtonSize::Small,
            SuggestedUnitTestsAction::Accept,
            Icon::Check,
            Arc::new(PrimaryTheme),
            ctx,
        );

        let cancel_button = CompactibleActionButton::new(
            CANCEL_LABEL.to_string(),
            None,
            ButtonSize::Small,
            SuggestedUnitTestsAction::Cancel,
            Icon::X,
            Arc::new(NakedTheme),
            ctx,
        );

        Self {
            identifiers,
            action_id,
            is_hidden: false,
            is_keybindings_hidden: false,
            title,
            description,
            query,
            accept_button,
            cancel_button,
        }
    }

    pub fn identifiers(&self) -> &AIIdentifiers {
        &self.identifiers
    }

    pub fn action_id(&self) -> &AIAgentActionId {
        &self.action_id
    }

    pub fn is_hidden(&self) -> bool {
        self.is_hidden
    }

    pub fn is_keybindings_hidden(&self) -> bool {
        self.is_keybindings_hidden
    }

    pub fn query(&self) -> Option<String> {
        (!self.query.is_empty()).then(|| self.query.to_string())
    }

    pub fn set_is_hidden(&mut self, is_hidden: bool) {
        self.is_hidden = is_hidden;
    }

    pub fn hide_keybindings(&mut self, ctx: &mut ViewContext<Self>) {
        self.is_keybindings_hidden = true;
        self.accept_button.set_keybinding(None, ctx);
        self.cancel_button.set_keybinding(None, ctx);
        ctx.notify();
    }

    fn render_icon(&self, appearance: &Appearance) -> Box<dyn Element> {
        Container::new(
            ConstrainedBox::new(
                warpui::elements::Icon::new(
                    Icon::Code2.into(),
                    appearance
                        .theme()
                        .main_text_color(appearance.theme().background())
                        .into_solid(),
                )
                .finish(),
            )
            .with_width(appearance.monospace_font_size())
            .with_height(appearance.monospace_font_size())
            .finish(),
        )
        .with_margin_right(8.)
        .finish()
    }

    fn render_buttons(
        &self,
        appearance: &Appearance,
        app: &AppContext,
    ) -> (Box<dyn Element>, Box<dyn Element>) {
        {
            render_compact_and_regular_button_rows(
                vec![&self.cancel_button, &self.accept_button],
                None,
                appearance,
                app,
            )
        }
    }

    fn render_header_contents(
        &self,
        buttons: Box<dyn Element>,
        appearance: &Appearance,
    ) -> Box<dyn Element> {
        let background = appearance.theme().background();
        let mut col = Flex::column();

        if !self.title.is_empty() {
            let title = Text::new_inline(
                self.title.to_string(),
                appearance.ui_font_family(),
                appearance.monospace_font_size() + 4.,
            )
            .with_color(appearance.theme().main_text_color(background).into_solid())
            .with_selectable(false)
            .finish();
            col.add_child(title);
        }

        if !self.description.is_empty() {
            let description = Text::new_inline(
                self.description.to_string(),
                appearance.ui_font_family(),
                appearance.monospace_font_size(),
            )
            .with_color(appearance.theme().sub_text_color(background).into_solid())
            .with_selectable(false)
            .finish();
            col.add_child(Container::new(description).with_margin_top(2.).finish());
        }

        Container::new(
            Flex::row()
                .with_main_axis_size(MainAxisSize::Max)
                .with_main_axis_alignment(MainAxisAlignment::SpaceBetween)
                .with_cross_axis_alignment(CrossAxisAlignment::Start)
                .with_child(Shrinkable::new(1., Expanded::new(1., col.finish()).finish()).finish())
                .with_child(Align::new(buttons).right().finish())
                .finish(),
        )
        .finish()
    }

    fn render_header(&self, appearance: &Appearance, app: &AppContext) -> Box<dyn Element> {
        let (regular_buttons, compact_buttons) = self.render_buttons(appearance, app);
        let regular_header = self.render_header_contents(regular_buttons, appearance);
        let compact_header = self.render_header_contents(compact_buttons, appearance);

        let size_switch_threshold = MEDIUM_SIZE_SWITCH_THRESHOLD * appearance.monospace_ui_scalar();
        SizeConstraintSwitch::new(
            regular_header,
            vec![(
                SizeConstraintCondition::WidthLessThan(size_switch_threshold),
                compact_header,
            )],
        )
        .finish()
    }

    fn render_body(&self, appearance: &Appearance, app: &AppContext) -> Box<dyn Element> {
        let header = self.render_header(appearance, app);
        let mut col = Flex::column()
            .with_cross_axis_alignment(CrossAxisAlignment::Stretch)
            .with_child(header);
        if !self.query.is_empty() {
            let query: Box<dyn Element> = Text::new(
                self.query.to_string(),
                appearance.ui_font_family(),
                appearance.monospace_font_size(),
            )
            .with_color(
                appearance
                    .theme()
                    .main_text_color(appearance.theme().background())
                    .into_solid(),
            )
            .with_selectable(true)
            .finish();

            col.add_child(Container::new(query).with_margin_top(6.).finish());
        }

        col.finish()
    }
}

impl View for SuggestedUnitTestsView {
    fn ui_name() -> &'static str {
        "SuggestedUnitTestsView"
    }

    fn on_focus(&mut self, _focus_ctx: &FocusContext, ctx: &mut ViewContext<Self>) {
        // We always want the focus to be in the input, not the view.
        ctx.emit(SuggestedUnitTestsEvent::Blur);
    }

    fn render(&self, app: &AppContext) -> Box<dyn Element> {
        let appearance = Appearance::as_ref(app);
        Flex::row()
            .with_main_axis_size(MainAxisSize::Max)
            .with_child(self.render_icon(appearance))
            .with_child(Expanded::new(1., self.render_body(appearance, app)).finish())
            .finish()
    }
}

impl Entity for SuggestedUnitTestsView {
    type Event = SuggestedUnitTestsEvent;
}

impl TypedActionView for SuggestedUnitTestsView {
    type Action = SuggestedUnitTestsAction;

    fn handle_action(&mut self, action: &Self::Action, ctx: &mut ViewContext<Self>) {
        match action {
            SuggestedUnitTestsAction::Accept => ctx.emit(SuggestedUnitTestsEvent::Accept),
            SuggestedUnitTestsAction::Cancel => ctx.emit(SuggestedUnitTestsEvent::Cancel),
        }
    }
}
