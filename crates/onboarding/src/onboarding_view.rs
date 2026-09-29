use pathfinder_geometry::vector::vec2f;
use ui_components::{Component as _, Options as _, button};
use warp_core::ui::appearance::Appearance;
use warp_core::ui::theme::WarpTheme;
use warpui_core::assets::asset_cache::AssetSource;
use warpui_core::elements::{
    CacheOption, ChildAnchor, Container, Empty, Image, OffsetPositioning, ParentAnchor,
    ParentElement, ParentOffsetBounds, Rect, Shrinkable, Stack,
};
use warpui_core::image_cache::ImageType;
use warpui_core::keymap::macros::*;
use warpui_core::keymap::{FixedBinding, Keystroke};
use warpui_core::presenter::ChildView;
use warpui_core::{
    AppContext, Element, Entity, ModelHandle, SingletonEntity as _, TypedActionView, View,
    ViewContext, ViewHandle,
};

use crate::model::{OnboardingStateEvent, OnboardingStateModel, OnboardingStep, SelectedSettings};
use crate::slides::{
    CustomizeUISlide, IntroSlide, OnboardingSlide, ThemePickerSlide, ThemePickerSlideEvent,
    ThirdPartySlide,
};

#[derive(Clone, Debug)]
pub enum OnboardingViewEvent {
    ThemeSelected { theme_name: String },
    SyncWithOsToggled { enabled: bool },
    OnboardingCompleted(SelectedSettings),
    OnboardingSkipped,
}

pub struct OnboardingView {
    onboarding_state: ModelHandle<OnboardingStateModel>,
    intro_slide: ViewHandle<IntroSlide>,
    customize_slide: ViewHandle<CustomizeUISlide>,
    third_party_slide: ViewHandle<ThirdPartySlide>,
    theme_picker_slide: ViewHandle<ThemePickerSlide>,
    skippable: bool,
    close_button: button::Button,
}

#[derive(Clone, Copy, Debug)]
pub enum OnboardingViewAction {
    UpKey,
    DownKey,
    LeftKey,
    RightKey,
    TabKey,
    EnterKey,
    CmdOrCtrlEnterKey,
    Escape,
}

fn dispatch_onboarding_action_to_slide<V: OnboardingSlide>(
    slide: &mut V,
    action: OnboardingViewAction,
    ctx: &mut ViewContext<V>,
) {
    match action {
        OnboardingViewAction::UpKey => slide.on_up(ctx),
        OnboardingViewAction::DownKey => slide.on_down(ctx),
        OnboardingViewAction::LeftKey => slide.on_left(ctx),
        OnboardingViewAction::RightKey => slide.on_right(ctx),
        OnboardingViewAction::TabKey => slide.on_tab(ctx),
        OnboardingViewAction::EnterKey => slide.on_enter(ctx),
        OnboardingViewAction::CmdOrCtrlEnterKey => slide.on_cmd_or_ctrl_enter(ctx),
        OnboardingViewAction::Escape => slide.on_escape(ctx),
    }
}

impl OnboardingView {
    pub fn new(
        theme_picker_themes: [WarpTheme; 4],
        skippable: bool,
        ctx: &mut ViewContext<Self>,
    ) -> Self {
        let onboarding_state = ctx.add_model(|_| OnboardingStateModel::new());
        ctx.subscribe_to_model(&onboarding_state, |me, _model, event, ctx| {
            // Re-render when slide selection changes.
            if !ctx.is_self_or_child_focused() {
                ctx.focus_self();
            }
            ctx.notify();

            match event {
                OnboardingStateEvent::Completed => me.handle_onboarding_completed(ctx),
                OnboardingStateEvent::SelectedSlideChanged => {}
            }
        });

        let intro_slide = {
            let onboarding_state = onboarding_state.clone();
            ctx.add_typed_action_view(move |_| IntroSlide::new(onboarding_state))
        };

        let customize_slide = {
            let onboarding_state = onboarding_state.clone();
            ctx.add_typed_action_view(move |_| CustomizeUISlide::new(onboarding_state))
        };

        let third_party_slide = {
            let onboarding_state = onboarding_state.clone();
            ctx.add_typed_action_view(move |_| ThirdPartySlide::new(onboarding_state))
        };

        let theme_picker_slide = {
            let onboarding_state = onboarding_state.clone();
            ctx.add_typed_action_view(move |ctx| {
                ThemePickerSlide::new(theme_picker_themes.clone(), onboarding_state, ctx)
            })
        };
        ctx.subscribe_to_view(&theme_picker_slide, |me, _view, event, ctx| {
            me.handle_theme_picker_slide_event(event, ctx);
        });

        Self {
            onboarding_state,
            intro_slide,
            customize_slide,
            third_party_slide,
            theme_picker_slide,
            skippable,
            close_button: button::Button::default(),
        }
    }

    pub fn start_onboarding(&self, ctx: &mut ViewContext<Self>) {
        // Focus the onboarding view so key bindings (Enter, arrow keys, etc.) are routed here
        // instead of to other views (e.g. the editor).
        ctx.focus_self();

        // Preload slide images so they're ready when the user reaches each slide.
        Self::preload_onboarding_images(ctx);
    }

    /// Eagerly loads all onboarding slide images into the asset cache
    /// so they display instantly when the user navigates between slides.
    fn preload_onboarding_images(ctx: &mut ViewContext<Self>) {
        let asset_cache = warpui_core::assets::asset_cache::AssetCache::as_ref(ctx);
        // Preload the shared background image used on all right panels.
        asset_cache.load_asset::<ImageType>(AssetSource::Bundled {
            path: crate::slides::layout::ONBOARDING_BG_PATH,
        });
        for path in CustomizeUISlide::VISUAL_IMAGE_PATHS
            .iter()
            .chain(ThirdPartySlide::VISUAL_IMAGE_PATHS)
            .chain(ThemePickerSlide::VISUAL_IMAGE_PATHS)
        {
            asset_cache.load_asset::<ImageType>(AssetSource::Bundled { path });
        }
    }

    fn handle_onboarding_completed(&mut self, ctx: &mut ViewContext<Self>) {
        let settings = self.onboarding_state.as_ref(ctx).settings();
        ctx.emit(OnboardingViewEvent::OnboardingCompleted(settings));
    }

    fn handle_theme_picker_slide_event(
        &mut self,
        event: &ThemePickerSlideEvent,
        ctx: &mut ViewContext<Self>,
    ) {
        match event {
            ThemePickerSlideEvent::ThemeSelected { theme_name } => {
                ctx.emit(OnboardingViewEvent::ThemeSelected {
                    theme_name: theme_name.clone(),
                });
            }
            ThemePickerSlideEvent::SyncWithOsToggled { enabled } => {
                ctx.emit(OnboardingViewEvent::SyncWithOsToggled { enabled: *enabled });
            }
        }
    }
}

impl Entity for OnboardingView {
    type Event = OnboardingViewEvent;
}

impl View for OnboardingView {
    fn ui_name() -> &'static str {
        "OnboardingView"
    }

    fn render(&self, app: &AppContext) -> Box<dyn Element> {
        let appearance = Appearance::as_ref(app);
        let theme = appearance.theme();

        let mut stack = Stack::new();

        if let Some(img) = theme.background_image() {
            // Render the image behind everything.
            stack.add_child(
                Shrinkable::new(
                    1.,
                    Image::new(img.source(), CacheOption::Original)
                        .cover()
                        .finish(),
                )
                .finish(),
            );

            // Overlay the theme background so the image shows through at img.opacity.
            let overlay_opacity = (100u8).saturating_sub(img.opacity);
            stack.add_child(
                Rect::new()
                    .with_background(theme.background().with_opacity(overlay_opacity))
                    .finish(),
            );
        } else {
            stack.add_child(
                Container::new(Empty::new().finish())
                    .with_background(theme.background())
                    .finish(),
            );
        }

        let slide = match self.onboarding_state.as_ref(app).step() {
            OnboardingStep::Intro => ChildView::new(&self.intro_slide).finish(),
            OnboardingStep::Customize => ChildView::new(&self.customize_slide).finish(),
            OnboardingStep::ThirdParty => ChildView::new(&self.third_party_slide).finish(),
            OnboardingStep::ThemePicker => ChildView::new(&self.theme_picker_slide).finish(),
        };
        stack.add_child(slide);

        if self.skippable {
            let esc = Keystroke::parse("escape").unwrap_or_default();

            let close_button = self.close_button.render(
                appearance,
                button::Params {
                    content: button::Content::Label("Skip".into()),
                    theme: &button::themes::Naked,
                    options: button::Options {
                        size: button::Size::Small,
                        keystroke: Some(esc),
                        on_click: Some(Box::new(|ctx, _app, _pos| {
                            ctx.dispatch_typed_action(OnboardingViewAction::Escape);
                        })),
                        ..button::Options::default(appearance)
                    },
                },
            );

            stack.add_positioned_child(
                close_button,
                OffsetPositioning::offset_from_parent(
                    vec2f(-24., 24.),
                    ParentOffsetBounds::WindowByPosition,
                    ParentAnchor::TopRight,
                    ChildAnchor::TopRight,
                ),
            );
        }

        stack.finish()
    }
}

impl TypedActionView for OnboardingView {
    type Action = OnboardingViewAction;

    fn handle_action(&mut self, action: &Self::Action, ctx: &mut ViewContext<Self>) {
        if matches!(action, OnboardingViewAction::Escape) && self.skippable {
            ctx.emit(OnboardingViewEvent::OnboardingSkipped);
            return;
        }

        match self.onboarding_state.as_ref(ctx).step() {
            OnboardingStep::Intro => self.intro_slide.update(ctx, |slide, ctx| {
                dispatch_onboarding_action_to_slide(slide, *action, ctx)
            }),
            OnboardingStep::Customize => self.customize_slide.update(ctx, |slide, ctx| {
                dispatch_onboarding_action_to_slide(slide, *action, ctx)
            }),
            OnboardingStep::ThirdParty => self.third_party_slide.update(ctx, |slide, ctx| {
                dispatch_onboarding_action_to_slide(slide, *action, ctx)
            }),
            OnboardingStep::ThemePicker => self.theme_picker_slide.update(ctx, |slide, ctx| {
                dispatch_onboarding_action_to_slide(slide, *action, ctx)
            }),
        }
    }
}

pub fn init(app: &mut AppContext) {
    app.register_fixed_bindings([
        FixedBinding::new(
            "up",
            OnboardingViewAction::UpKey,
            id!(OnboardingView::ui_name()),
        ),
        FixedBinding::new(
            "down",
            OnboardingViewAction::DownKey,
            id!(OnboardingView::ui_name()),
        ),
        FixedBinding::new(
            "left",
            OnboardingViewAction::LeftKey,
            id!(OnboardingView::ui_name()),
        ),
        FixedBinding::new(
            "right",
            OnboardingViewAction::RightKey,
            id!(OnboardingView::ui_name()),
        ),
        FixedBinding::new(
            "tab",
            OnboardingViewAction::TabKey,
            id!(OnboardingView::ui_name()),
        ),
        FixedBinding::new(
            "enter",
            OnboardingViewAction::EnterKey,
            id!(OnboardingView::ui_name()),
        ),
        FixedBinding::new(
            "numpadenter",
            OnboardingViewAction::EnterKey,
            id!(OnboardingView::ui_name()),
        ),
        FixedBinding::new(
            "cmdorctrl-enter",
            OnboardingViewAction::CmdOrCtrlEnterKey,
            id!(OnboardingView::ui_name()),
        ),
        FixedBinding::new(
            "cmdorctrl-numpadenter",
            OnboardingViewAction::CmdOrCtrlEnterKey,
            id!(OnboardingView::ui_name()),
        ),
        FixedBinding::new(
            "escape",
            OnboardingViewAction::Escape,
            id!(OnboardingView::ui_name()),
        ),
    ]);
}
