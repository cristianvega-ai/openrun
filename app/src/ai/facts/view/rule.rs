use std::fmt::Debug;

use markdown_parser::weight::CustomWeight;
use markdown_parser::{FormattedText, FormattedTextFragment, FormattedTextLine};
use warp_core::ui::appearance::{Appearance, AppearanceEvent};
use warp_core::ui::theme::color::internal_colors;
use warpui::elements::{
    Align, Border, ChildView, ConstrainedBox, Container, CornerRadius, CrossAxisAlignment,
    Expanded, Flex, FormattedTextElement, HighlightedHyperlink, Hoverable, MainAxisAlignment,
    MainAxisSize, MouseStateHandle, ParentElement,
};
use warpui::platform::Cursor;
use warpui::ui_components::components::UiComponent;
use warpui::{
    AppContext, Element, Entity, FocusContext, SingletonEntity, TypedActionView, View, ViewContext,
    ViewHandle,
};

use super::{AIFact, CloudAIFact, CloudAIFactModel, is_edit_allowed, style};
use crate::ai::facts::AIMemory;
use crate::cloud_object::model::generic_string_model::GenericStringObjectId;
use crate::cloud_object::model::persistence::{CloudModel, CloudModelEvent};
use crate::cloud_object::{
    CloudObject, GenericStringObjectFormat, JsonObjectType, Owner, Revision,
};
use crate::drive::CloudObjectTypeAndId;
use crate::editor::{
    EditorView, Event as EditorEvent, PropagateAndNoOpNavigationKeys, SingleLineEditorOptions,
    TextOptions,
};
use crate::network::NetworkStatus;
use crate::search_bar::SearchBar;
use crate::server::cloud_objects::update_manager::{UpdateManager, UpdateManagerEvent};
use crate::server::ids::{ClientId, SyncId};
use crate::settings::{AISettings, AISettingsChangedEvent};
use crate::ui_components::icons::Icon;
use crate::view_components::action_button::{ActionButton, NakedTheme};
use crate::workspaces::user_workspaces::UserWorkspaces;

pub const HEADER_TEXT: &str = "Rules";
const DESCRIPTION_TEXT: &str = "Rules enhance the agent by providing structured guidelines that help maintain consistency, enforce best practices, and adapt to specific workflows, including codebases or broader tasks.";

const SEARCH_PLACEHOLDER_TEXT: &str = "Search rules";
const ZERO_STATE_TEXT: &str = "Add a rule above.";

const DISABLED_BANNER_TEXT: &str =
    "Your rules are disabled and won't be used as context in sessions. You can ";
const DISABLED_BANNER_LINK_TEXT: &str = "turn it back on";
const DISABLED_BANNER_TEXT_2: &str = " anytime.";

#[derive(Debug, Clone)]
pub enum RuleViewEvent {
    AddRule,
    Edit(SyncId),
    OpenSettings,
}

#[derive(Debug, Clone)]
pub enum RuleViewAction {
    AddRule,
    Edit(SyncId),
    OpenSettings,
}

#[derive(Default, Debug, Clone)]
pub struct MouseStateHandles {
    pub hover: MouseStateHandle,
}

#[derive(Debug, Clone)]
struct CloudRuleRow {
    fact: CloudAIFact,
    mouse_states: MouseStateHandles,
}

impl CloudRuleRow {
    fn matches_search_term(&self, search_term: &str) -> bool {
        let search_term = search_term.to_lowercase();
        let search_term = search_term.as_str();
        let AIFact::Memory(AIMemory { name, content, .. }) = self.fact.model().string_model.clone();
        name.unwrap_or_default()
            .to_lowercase()
            .contains(search_term)
            || content.to_lowercase().contains(search_term)
    }

    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        other
            .fact
            .metadata()
            .revision
            .cmp(&self.fact.metadata().revision)
    }
}

pub struct RuleView {
    owner: Option<Owner>,
    cloud_global_rules: Vec<CloudRuleRow>,
    search_editor: ViewHandle<EditorView>,
    search_bar: ViewHandle<SearchBar>,
    add_button: ViewHandle<ActionButton>,
    disabled_banner_highlight_index: HighlightedHyperlink,
}

impl RuleView {
    pub fn new(ctx: &mut ViewContext<Self>) -> Self {
        let update_manager = UpdateManager::handle(ctx);
        ctx.subscribe_to_model(&update_manager, |me, _, event, ctx| {
            me.handle_update_manager_event(event, ctx);
        });

        let cloud_model = CloudModel::handle(ctx);
        ctx.subscribe_to_model(&cloud_model, |me, _, event, ctx| {
            me.handle_cloud_model_event(event, ctx);
        });

        let network_status = NetworkStatus::handle(ctx);
        ctx.subscribe_to_model(&network_status, |_me, _, _event, ctx| {
            ctx.notify();
        });

        let owner = UserWorkspaces::as_ref(ctx).personal_drive(ctx);

        ctx.subscribe_to_model(&AISettings::handle(ctx), |_, _, event, ctx| {
            if matches!(
                event,
                AISettingsChangedEvent::MemoryEnabled { .. }
                    | AISettingsChangedEvent::IsAnyAIEnabled { .. }
            ) {
                ctx.notify();
            }
        });

        let ai_rules: Vec<CloudAIFact> = {
            let cloud_model = CloudModel::handle(ctx);
            cloud_model
                .as_ref(ctx)
                .get_all_objects_of_type::<GenericStringObjectId, CloudAIFactModel>()
                .cloned()
                .collect()
        };
        let ai_rules: Vec<CloudRuleRow> = ai_rules
            .into_iter()
            .map(|fact| CloudRuleRow {
                fact,
                mouse_states: Default::default(),
            })
            .collect();

        let appearance = Appearance::handle(ctx);
        ctx.subscribe_to_model(&appearance, move |me, _, event, ctx| {
            if let AppearanceEvent::ThemeChanged = event {
                let appearance = Appearance::as_ref(ctx);
                let search_bar_styles = style::search_bar(appearance);
                me.search_bar.update(ctx, |search_bar, _| {
                    search_bar.with_style(search_bar_styles)
                });
            }
        });

        let search_editor_text = TextOptions::ui_text(None, appearance.as_ref(ctx));
        let search_editor = {
            let options = SingleLineEditorOptions {
                text: search_editor_text,
                propagate_and_no_op_vertical_navigation_keys:
                    PropagateAndNoOpNavigationKeys::Always,
                ..Default::default()
            };
            ctx.add_typed_action_view(|ctx| EditorView::single_line(options, ctx))
        };
        ctx.subscribe_to_view(&search_editor, move |me, _, event, ctx| {
            me.handle_search_editor_event(event, ctx);
        });

        search_editor.update(ctx, |editor, ctx| {
            editor.clear_buffer_and_reset_undo_stack(ctx);
            editor.set_placeholder_text(SEARCH_PLACEHOLDER_TEXT, ctx);
        });
        let search_bar = ctx.add_typed_action_view(|_| SearchBar::new(search_editor.clone()));

        let add_button = ctx.add_typed_action_view(|_| {
            ActionButton::new("Add", NakedTheme)
                .with_icon(Icon::Plus)
                .on_click(|ctx| ctx.dispatch_typed_action(RuleViewAction::AddRule))
        });

        Self {
            owner,
            cloud_global_rules: ai_rules,
            search_editor,
            search_bar,
            add_button,
            disabled_banner_highlight_index: Default::default(),
        }
    }

    fn handle_update_manager_event(
        &mut self,
        event: &UpdateManagerEvent,
        ctx: &mut ViewContext<Self>,
    ) {
        if let UpdateManagerEvent::ObjectOperationComplete { .. } = event {
            self.fetch_ai_rules(ctx);
        }
    }

    fn handle_cloud_model_event(&mut self, event: &CloudModelEvent, ctx: &mut ViewContext<Self>) {
        match event {
            CloudModelEvent::ObjectUpdated { .. }
            | CloudModelEvent::ObjectTrashed { .. }
            | CloudModelEvent::ObjectUntrashed { .. }
            | CloudModelEvent::ObjectCreated { .. }
            | CloudModelEvent::ObjectDeleted { .. } => {
                self.fetch_ai_rules(ctx);
            }
            _ => {}
        }
    }

    fn handle_search_editor_event(&mut self, _event: &EditorEvent, ctx: &mut ViewContext<Self>) {
        ctx.notify();
    }

    fn fetch_ai_rules(&mut self, ctx: &mut ViewContext<Self>) {
        let ai_rules: Vec<CloudAIFact> = {
            let cloud_model = CloudModel::handle(ctx);
            cloud_model
                .as_ref(ctx)
                .get_all_objects_of_type::<GenericStringObjectId, CloudAIFactModel>()
                .cloned()
                .collect()
        };
        self.cloud_global_rules = ai_rules
            .into_iter()
            .map(|ai_fact| CloudRuleRow {
                fact: ai_fact,
                mouse_states: Default::default(),
            })
            .collect();
        ctx.notify();
    }

    pub fn add_ai_rule(
        &mut self,
        name: Option<String>,
        content: String,
        ctx: &mut ViewContext<Self>,
    ) {
        let update_manager = UpdateManager::handle(ctx);
        if let Some(owner) = self.owner {
            let ai_fact = AIFact::Memory(AIMemory {
                is_autogenerated: false,
                name,
                content,
                suggested_logging_id: None,
            });
            update_manager.update(ctx, |update_manager, ctx| {
                update_manager.create_ai_fact(ai_fact, ClientId::default(), owner, ctx);
            });
        }
    }

    pub fn edit_ai_rule(
        &mut self,
        name: Option<String>,
        content: String,
        sync_id: SyncId,
        revision_ts: Option<Revision>,
        ctx: &mut ViewContext<Self>,
    ) {
        let update_manager = UpdateManager::handle(ctx);
        let (is_autogenerated, suggested_logging_id) = CloudModel::as_ref(ctx)
            .get_object_of_type::<GenericStringObjectId, CloudAIFactModel>(&sync_id)
            .map(|ai_fact| {
                let AIFact::Memory(AIMemory {
                    is_autogenerated,
                    suggested_logging_id,
                    ..
                }) = ai_fact.model().string_model.clone();
                (is_autogenerated, suggested_logging_id)
            })
            .unwrap_or((false, None));
        update_manager.update(ctx, |update_manager, ctx| {
            let ai_fact = AIFact::Memory(AIMemory {
                is_autogenerated,
                name,
                content,
                suggested_logging_id,
            });
            update_manager.update_ai_fact(ai_fact, sync_id, revision_ts, ctx);
        });
    }

    pub fn delete_ai_rule(&mut self, id: SyncId, ctx: &mut ViewContext<Self>) {
        let update_manager = UpdateManager::handle(ctx);
        update_manager.update(ctx, |update_manager, ctx| {
            update_manager.delete_object_by_user(
                CloudObjectTypeAndId::GenericStringObject {
                    object_type: GenericStringObjectFormat::Json(JsonObjectType::AIFact),
                    id,
                },
                ctx,
            );
        });
    }

    fn render_header(&self, appearance: &Appearance) -> Box<dyn Element> {
        Flex::row()
            .with_cross_axis_alignment(CrossAxisAlignment::Center)
            .with_child(
                Container::new(
                    ConstrainedBox::new(
                        warpui::elements::Icon::new(
                            Icon::BookOpen.into(),
                            appearance
                                .theme()
                                .main_text_color(appearance.theme().background()),
                        )
                        .finish(),
                    )
                    .with_width(style::ICON_SIZE)
                    .with_height(style::ICON_SIZE)
                    .finish(),
                )
                .with_margin_right(style::ICON_MARGIN)
                .finish(),
            )
            .with_child(
                appearance
                    .ui_builder()
                    .wrappable_text(HEADER_TEXT, true)
                    .with_style(style::header_text())
                    .build()
                    .finish(),
            )
            .finish()
    }

    fn render_description(&self, appearance: &Appearance) -> Box<dyn Element> {
        Container::new(
            appearance
                .ui_builder()
                .wrappable_text(DESCRIPTION_TEXT, true)
                .with_style(style::description_text(appearance))
                .build()
                .finish(),
        )
        .with_vertical_margin(style::ITEM_BOTTOM_MARGIN)
        .finish()
    }

    fn render_add_button(&self) -> Box<dyn Element> {
        Container::new(ChildView::new(&self.add_button).finish())
            .with_margin_left(style::SECTION_MARGIN)
            .finish()
    }

    fn render_disabled_banner(&self, appearance: &Appearance) -> Box<dyn Element> {
        let mut link = FormattedTextFragment::hyperlink(DISABLED_BANNER_LINK_TEXT, "Settings > AI");
        link.styles.weight = Some(CustomWeight::Bold);

        let formatted_text = FormattedTextElement::new(
            FormattedText::new([FormattedTextLine::Line(vec![
                FormattedTextFragment::bold(DISABLED_BANNER_TEXT),
                link,
                FormattedTextFragment::bold(DISABLED_BANNER_TEXT_2),
            ])]),
            style::SUBTEXT_FONT_SIZE,
            appearance.ui_font_family(),
            appearance.ui_font_family(),
            appearance
                .theme()
                .sub_text_color(appearance.theme().background())
                .into(),
            self.disabled_banner_highlight_index.clone(),
        )
        .with_hyperlink_font_color(internal_colors::accent_fg_strong(appearance.theme()).into())
        .register_default_click_handlers(|_, ctx, _| {
            ctx.dispatch_typed_action(RuleViewAction::OpenSettings);
        });

        Container::new(
            Flex::row()
                .with_cross_axis_alignment(CrossAxisAlignment::Center)
                .with_child(
                    Container::new(
                        ConstrainedBox::new(
                            Icon::Info
                                .to_warpui_icon(
                                    appearance
                                        .theme()
                                        .sub_text_color(appearance.theme().background()),
                                )
                                .finish(),
                        )
                        .with_width(style::BANNER_ICON_SIZE)
                        .with_height(style::BANNER_ICON_SIZE)
                        .finish(),
                    )
                    .with_margin_right(style::ROW_ICON_MARGIN)
                    .finish(),
                )
                .with_child(Expanded::new(1., formatted_text.finish()).finish())
                .finish(),
        )
        .with_background(appearance.theme().accent_overlay())
        .with_corner_radius(CornerRadius::with_all(warpui::elements::Radius::Pixels(4.)))
        .with_uniform_padding(style::BANNER_PADDING)
        .with_margin_bottom(style::ITEM_BOTTOM_MARGIN)
        .finish()
    }

    fn render_search_bar_row(&self, filtered_rules: &[CloudRuleRow]) -> Box<dyn Element> {
        let mut row = Flex::row()
            .with_cross_axis_alignment(CrossAxisAlignment::Center)
            .with_child(Expanded::new(1., ChildView::new(&self.search_bar).finish()).finish());

        if !filtered_rules.is_empty() {
            row.add_child(self.render_add_button());
        }
        Container::new(row.finish())
            .with_margin_bottom(style::SECTION_MARGIN)
            .finish()
    }

    fn render_global_rule_row(
        &self,
        ai_row: CloudRuleRow,
        appearance: &Appearance,
        app: &AppContext,
    ) -> Box<dyn Element> {
        let AIFact::Memory(AIMemory { name, content, .. }) =
            ai_row.fact.model().string_model.clone();
        let formatted_name = match name {
            Some(name) => {
                if name.is_empty() {
                    "Untitled".to_string()
                } else {
                    name
                }
            }
            None => "Untitled".to_string(),
        };
        // Truncate content to 3 lines
        let formatted_content = if content.split("\n").count() > 3 {
            content
                .split("\n")
                .take(3)
                .collect::<Vec<&str>>()
                .join("\n")
                + "..."
        } else {
            content
        };

        let fact_text = Flex::column()
            .with_child(
                appearance
                    .ui_builder()
                    .wrappable_text(formatted_name, true)
                    .with_style(style::fact_row_text(appearance))
                    .build()
                    .finish(),
            )
            .with_child(
                appearance
                    .ui_builder()
                    .wrappable_text(formatted_content, true)
                    .with_style(style::fact_row_subtext(appearance))
                    .build()
                    .finish(),
            )
            .finish();

        let mut row = Flex::row()
            .with_main_axis_size(MainAxisSize::Max)
            .with_main_axis_alignment(MainAxisAlignment::SpaceBetween);

        row.add_child(Expanded::new(1., fact_text).finish());

        let mut hoverable = Hoverable::new(ai_row.mouse_states.hover.clone(), |state| {
            let mut bg_color = internal_colors::neutral_1(appearance.theme());
            if state.is_hovered() {
                bg_color = internal_colors::neutral_4(appearance.theme());
            }

            Container::new(row.finish())
                .with_background(bg_color)
                .with_corner_radius(CornerRadius::with_all(warpui::elements::Radius::Pixels(4.)))
                .with_border(
                    Border::all(1.)
                        .with_border_color(internal_colors::neutral_2(appearance.theme())),
                )
                .with_horizontal_padding(style::ROW_HORIZONTAL_PADDING)
                .with_vertical_padding(style::RULE_VERTICAL_PADDING)
                .with_margin_bottom(style::ITEM_BOTTOM_MARGIN)
                .finish()
        });

        if is_edit_allowed(ai_row.fact.clone(), app) {
            hoverable = hoverable
                .with_cursor(Cursor::PointingHand)
                .on_click(move |ctx, _, _| {
                    ctx.dispatch_typed_action(RuleViewAction::Edit(ai_row.fact.sync_id()));
                });
        }

        hoverable.finish()
    }

    fn render_items(
        &self,
        appearance: &Appearance,
        mut filtered_rules: Vec<CloudRuleRow>,
        app: &AppContext,
    ) -> Box<dyn Element> {
        let mut col = Flex::column();

        // Filter the rows based on the search query
        let search_term = self.search_editor.as_ref(app).buffer_text(app);
        if !search_term.is_empty() {
            filtered_rules = filtered_rules
                .iter()
                .filter(|row| row.matches_search_term(search_term.as_str()))
                .cloned()
                .collect();
        }
        // Sort the rows by the last modified timestamp
        filtered_rules.sort_by(|a, b| a.cmp(b));

        for row in filtered_rules {
            col.add_child(self.render_global_rule_row(row, appearance, app));
        }
        col.finish()
    }

    fn render_zero_state(&self, appearance: &Appearance) -> Box<dyn Element> {
        let centered_text = appearance
            .ui_builder()
            .wrappable_text(ZERO_STATE_TEXT, true)
            .with_style(style::description_text(appearance))
            .build()
            .finish();

        Container::new(
            ConstrainedBox::new(
                Align::new(
                    Flex::column()
                        .with_main_axis_size(MainAxisSize::Max)
                        .with_main_axis_alignment(MainAxisAlignment::Center)
                        .with_cross_axis_alignment(CrossAxisAlignment::Center)
                        .with_child(
                            Container::new(Align::new(centered_text).top_center().finish())
                                .with_horizontal_padding(style::ROW_HORIZONTAL_PADDING)
                                .finish(),
                        )
                        .with_child(self.render_add_button())
                        .finish(),
                )
                .finish(),
            )
            .with_height(style::ZERO_STATE_HEIGHT)
            .finish(),
        )
        .with_horizontal_padding(style::ROW_HORIZONTAL_PADDING)
        .with_border(
            Border::all(1.).with_border_color(internal_colors::neutral_2(appearance.theme())),
        )
        .with_margin_bottom(style::SECTION_MARGIN)
        .finish()
    }

    fn render_body(
        &self,
        appearance: &Appearance,
        filtered_rules: Vec<CloudRuleRow>,
        app: &AppContext,
    ) -> Box<dyn Element> {
        Flex::column()
            .with_child(self.render_search_bar_row(&filtered_rules))
            .with_child(self.render_items(appearance, filtered_rules, app))
            .finish()
    }
}

impl Entity for RuleView {
    type Event = RuleViewEvent;
}

impl View for RuleView {
    fn ui_name() -> &'static str {
        "RuleView"
    }

    fn on_focus(&mut self, focus_ctx: &FocusContext, ctx: &mut ViewContext<Self>) {
        if focus_ctx.is_self_focused() {
            ctx.focus(&self.search_editor);
        }
    }

    fn render(&self, app: &AppContext) -> Box<dyn Element> {
        let appearance = Appearance::as_ref(app);
        let mut col = Flex::column()
            .with_child(self.render_header(appearance))
            .with_child(self.render_description(appearance));

        let ai_settings = AISettings::as_ref(app);
        if !ai_settings.is_memory_enabled(app) {
            col.add_child(self.render_disabled_banner(appearance));
        }

        let filtered_rules = self.cloud_global_rules.clone();
        if filtered_rules.is_empty() {
            col.add_child(self.render_zero_state(appearance));
        } else {
            col.add_child(self.render_body(appearance, filtered_rules, app));
        };
        col.finish()
    }
}

impl TypedActionView for RuleView {
    type Action = RuleViewAction;

    fn handle_action(&mut self, action: &RuleViewAction, ctx: &mut ViewContext<Self>) {
        match action {
            RuleViewAction::AddRule => {
                ctx.emit(RuleViewEvent::AddRule);
            }
            RuleViewAction::Edit(sync_id) => {
                ctx.emit(RuleViewEvent::Edit(*sync_id));
            }
            RuleViewAction::OpenSettings => {
                ctx.emit(RuleViewEvent::OpenSettings);
            }
        }
    }
}
