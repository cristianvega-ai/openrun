use warpui::elements::{
    Align, ConstrainedBox, Container, CrossAxisAlignment, Element, Flex, MouseStateHandle,
    ParentElement, SavePosition, Shrinkable,
};
use warpui::fonts::Weight;
use warpui::platform::Cursor;
use warpui::presenter::ChildView;
use warpui::ui_components::components::{UiComponent, UiComponentStyles};
use warpui::windowing::{StateEvent, WindowManager};
use warpui::{
    AppContext, Entity, FocusContext, SingletonEntity, View, ViewContext, ViewHandle, WindowId,
};

use super::KeybindingsView;
use super::keybindings_page::KeybindingsEvent;
use crate::appearance::Appearance;
use crate::ui_components::buttons::icon_button;
use crate::ui_components::window_focus_dimming::WindowFocusDimming;
use crate::workspace::{PANEL_HEADER_HEIGHT, WorkspaceAction};

const HEADER_FONT_SIZE: f32 = 16.;

#[derive(Default)]
struct MouseStateHandles {
    close: MouseStateHandle,
}

pub enum ResourceCenterEvent {
    Escape,
}

/// The side panel that lists the app's keyboard shortcuts.
pub struct ResourceCenterView {
    button_mouse_states: MouseStateHandles,
    header_dimming_mouse_state: MouseStateHandle,
    keybindings_view: ViewHandle<KeybindingsView>,
    window_id: WindowId,
}

impl ResourceCenterView {
    pub fn new(ctx: &mut ViewContext<Self>) -> Self {
        let keybindings_view = ctx.add_typed_action_view(KeybindingsView::new);
        ctx.subscribe_to_view(&keybindings_view, move |me, _, event, ctx| {
            me.handle_keybindings_event(event, ctx);
        });

        // Subscribe to window state changes for focus dimming updates
        let state_handle = WindowManager::handle(ctx);
        ctx.subscribe_to_model(&state_handle, |_me, _, event, ctx| match &event {
            StateEvent::ValueChanged { current, previous } => {
                if WindowManager::did_window_change_focus(ctx.window_id(), current, previous) {
                    ctx.notify();
                }
            }
        });

        Self {
            button_mouse_states: Default::default(),
            header_dimming_mouse_state: Default::default(),
            keybindings_view,
            window_id: ctx.window_id(),
        }
    }

    fn handle_keybindings_event(&mut self, event: &KeybindingsEvent, ctx: &mut ViewContext<Self>) {
        match event {
            KeybindingsEvent::Escape => {
                ctx.emit(ResourceCenterEvent::Escape);
            }
        }
    }

    pub fn focus_keybindings(&self, ctx: &mut ViewContext<Self>) {
        ctx.focus(&self.keybindings_view);
        ctx.notify();
    }

    fn render_close_button(&self, appearance: &Appearance) -> Box<dyn Element> {
        SavePosition::new(
            icon_button(
                appearance,
                crate::ui_components::icons::Icon::X,
                false,
                self.button_mouse_states.close.clone(),
            )
            .build()
            .on_click(|ctx, _, _| ctx.dispatch_typed_action(WorkspaceAction::ToggleKeybindingsPage))
            .with_cursor(Cursor::PointingHand)
            .finish(),
            "resource_center_close_button",
        )
        .finish()
    }

    fn render_header_contents(&self, appearance: &Appearance) -> Vec<Box<dyn Element>> {
        let title = Shrinkable::new(
            1.0,
            Align::new(
                Container::new(
                    appearance
                        .ui_builder()
                        .wrappable_text("Keyboard Shortcuts".to_string(), false)
                        .with_style(UiComponentStyles {
                            font_family_id: Some(appearance.ui_font_family()),
                            font_size: Some(HEADER_FONT_SIZE),
                            font_weight: Some(Weight::Semibold),
                            ..Default::default()
                        })
                        .build()
                        .finish(),
                )
                .with_padding_left(6.)
                .finish(),
            )
            .left()
            .finish(),
        )
        .finish();

        vec![title, self.render_close_button(appearance)]
    }

    fn render_header(&self, appearance: &Appearance, app: &AppContext) -> Box<dyn Element> {
        const HEADER_VERTICAL_PADDING: f32 = 5.;
        const HEADER_HORIZONTAL_PADDING: f32 = 6.;
        let header_body = self.render_header_contents(appearance);

        let header_element = ConstrainedBox::new(
            Container::new(
                Flex::row()
                    .with_children(header_body)
                    .with_cross_axis_alignment(CrossAxisAlignment::Center)
                    .finish(),
            )
            .with_padding_left(HEADER_HORIZONTAL_PADDING)
            .with_padding_right(HEADER_HORIZONTAL_PADDING)
            .with_padding_top(HEADER_VERTICAL_PADDING)
            .with_padding_bottom(HEADER_VERTICAL_PADDING)
            .finish(),
        )
        .with_height(PANEL_HEADER_HEIGHT)
        .finish();

        // Apply dimming if window is not focused
        WindowFocusDimming::apply_panel_header_dimming(
            header_element,
            self.header_dimming_mouse_state.clone(),
            PANEL_HEADER_HEIGHT,
            appearance.theme().surface_1().into(),
            self.window_id,
            app,
        )
    }
}

impl Entity for ResourceCenterView {
    type Event = ResourceCenterEvent;
}

impl View for ResourceCenterView {
    fn ui_name() -> &'static str {
        "ResourceCenter"
    }

    fn on_focus(&mut self, focus_ctx: &FocusContext, ctx: &mut ViewContext<Self>) {
        if focus_ctx.is_self_focused() {
            ctx.focus(&self.keybindings_view);
        }
    }

    fn render(&self, app: &AppContext) -> Box<dyn Element> {
        let appearance = Appearance::as_ref(app);
        let header = self.render_header(appearance, app);

        Flex::column()
            .with_child(header)
            .with_child(
                Shrinkable::new(1., ChildView::new(&self.keybindings_view).finish()).finish(),
            )
            .finish()
    }
}
