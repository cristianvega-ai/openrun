use std::borrow::Cow;
use std::cell::RefCell;
use std::collections::HashSet;
use std::sync::LazyLock;
use std::time::Duration;

use pathfinder_geometry::vector::vec2f;
use regex::Regex;
use settings::Setting as _;
use warp_core::ui::theme::WarpTheme;
use warp_core::ui::theme::color::internal_colors;
use warp_errors::{report_error, report_if_error};
use warpui::r#async::{SpawnedFutureHandle, Timer};
use warpui::elements::{
    ChildView, ConstrainedBox, Container, CornerRadius, CrossAxisAlignment, Expanded, Flex,
    MainAxisAlignment, MainAxisSize, MouseStateHandle, ParentElement, Radius, Rect, Shrinkable,
    Text,
};
use warpui::fonts::Weight;
use warpui::keymap::ContextPredicate;
use warpui::ui_components::button::{ButtonVariant, TextAndIcon, TextAndIconAlignment};
use warpui::ui_components::components::{Coords, UiComponent, UiComponentStyles};
use warpui::ui_components::switch::SwitchStateHandle;
use warpui::{
    Action, AppContext, Element, Entity, ModelHandle, SingletonEntity, TypedActionView,
    UpdateModel, View, ViewContext, ViewHandle,
};

use super::privacy::{
    AddRegexModal, AddRegexModalEvent, DeleteHistoryModal, DeleteHistoryModalEvent,
};
use super::settings_page::{
    HEADER_PADDING, MatchData, PageTitle, PageType, SettingsPageMeta, SettingsPageViewHandle,
    SettingsWidget, TOGGLE_BUTTON_RIGHT_PADDING, render_sub_header,
};
use super::{SettingsAction, SettingsSection, ToggleSettingActionPair, flags};
use crate::GlobalResourceHandlesProvider;
use crate::appearance::Appearance;
use crate::modal::{Modal, ModalEvent, ModalViewState};
use crate::persistence::{HistoryScrub, ModelEvent, SavedHistoryDeleted, ScrubBlocker};
use crate::settings::{CustomSecretRegex, HistorySettings, PrivacySettings, RegexDisplayInfo};
use crate::settings_view::privacy::AddRegexModalViewState;
use crate::terminal::History;
use crate::terminal::safe_mode_settings::{
    SafeModeSettings, SecretDisplayMode, get_effective_secret_display_mode,
};
use crate::ui_components::buttons::icon_button;
use crate::ui_components::icons::Icon;
use crate::view_components::{DismissibleToast, Dropdown, DropdownItem};
use crate::workspace::{ToastStack, WorkspaceAction};

const FONT_SIZE: f32 = 12.;

const SAFE_MODE_TITLE: &str = "Secret redaction";
static SAFE_MODE_DESCRIPTION: LazyLock<&'static str> = LazyLock::new(|| {
    "When this setting is enabled, OpenRun scans blocks for potential \
        sensitive information and hides it on screen. This only changes what is \
        displayed: the original text is still kept in the block and, unless you turn \
        off Save command history below, in the saved history and session restore data. \
        You can customize this list via regexes."
});
const SAVE_HISTORY_TITLE: &str = "Save command history and block output";
const SAVE_HISTORY_DESCRIPTION: &str = "Save the commands you run, and the command text and output of the blocks used to restore your previous session, in OpenRun's local database on this computer. \
    When this is off, nothing new is written there, nothing saved earlier is loaded at startup, and blocks from your previous session are not restored (your windows, tabs and panes still are). \
    Up-arrow history keeps working in the running app, but it is forgotten when OpenRun quits. \
    Commands that start with a space are never saved when your shell ignores them (zsh with histignorespace, or bash with HISTCONTROL set to ignorespace or ignoreboth). \
    Your shell's own history file is not affected, and secret redaction only changes what is shown on screen, not what is saved.";
const DELETE_HISTORY_DESCRIPTION: &str = "Permanently delete every command and every block saved for session restore from OpenRun's local database.";
const USER_SECRET_REGEX_TITLE: &str = "Custom secret redaction";
const USER_SECRET_REGEX_DESCRIPTION: &str = "Use regex to define additional secrets or data you'd like to redact. This will take effect \
    when the next command runs. You can use the inline (?i) flag as a prefix to your regex \
    to make it case-insensitive.";

/// What the user is told when "Delete saved history" finishes. The three cases are different
/// facts: history is deleted and SQLite compaction finished, compaction remains pending, or
/// nothing was deleted.
#[derive(Debug, PartialEq, Eq)]
enum DeleteHistoryNotice {
    /// Deleted and SQLite compaction finished.
    Compacted(String),
    /// Deleted and no longer loaded, but old text may remain in the database files for now.
    CompactionPending(String),
    /// Nothing was deleted.
    Failed(String),
}

fn delete_history_notice(result: &Result<SavedHistoryDeleted, String>) -> DeleteHistoryNotice {
    let deleted = match result {
        Ok(deleted) => deleted,
        Err(error) => {
            return DeleteHistoryNotice::Failed(format!("Could not delete saved history: {error}"));
        }
    };
    let counts = format!(
        "Deleted {} saved commands and {} saved blocks.",
        deleted.commands, deleted.blocks
    );
    match deleted.scrub {
        HistoryScrub::Complete => {
            DeleteHistoryNotice::Compacted(format!("{counts} Database compaction completed."))
        }
        HistoryScrub::Incomplete(blocker) => {
            let why = match blocker {
                ScrubBlocker::InUse => {
                    "another program or OpenRun window still has the database open"
                }
                ScrubBlocker::DatabaseLocked => "another program was writing to the database",
                ScrubBlocker::Failed => "the cleanup hit a database error (see the log)",
            };
            DeleteHistoryNotice::CompactionPending(format!(
                "{counts} They will not load again, but their text may still be in OpenRun's \
                 database files, because {why}. OpenRun keeps trying while it runs and tries \
                 again when it next starts."
            ))
        }
    }
}

pub struct PrivacyPageView {
    page: PageType<Self>,
    /// This needs to mirror the length of PrivacySettings::user_secret_regex_list.
    added_user_secret_regex_list_button_handles: Vec<MouseStateHandle>,
    /// Set of indices for regex items that are pending removal
    pending_regex_removals: HashSet<usize>,
    /// Handle to the current debounce timer
    pending_timer: Option<SpawnedFutureHandle>,
    /// Modal state
    add_regex_modal_state: AddRegexModalViewState,
    /// Dropdown for selecting secret redaction display mode
    secret_redaction_display_dropdown: ViewHandle<Dropdown<PrivacyPageAction>>,
    /// Confirmation for deleting the saved command history
    delete_history_modal: ModalViewState<Modal<DeleteHistoryModal>>,
    delete_history_in_progress: bool,
}

#[derive(Clone, Copy)]
pub enum PrivacyPageViewEvent {
    ShowAddRegexModal,
    HideAddRegexModal,
    DeleteHistoryModalChanged,
}

impl PrivacyPageView {
    const BATCH_TIMEOUT_MS: u64 = 700;

    pub fn new(ctx: &mut ViewContext<PrivacyPageView>) -> Self {
        let privacy_settings_handle = PrivacySettings::handle(ctx);
        ctx.observe(&privacy_settings_handle, |_, _, ctx| {
            // It is possible that PrivacySettings are updated without an interaction in this view
            // (e.g. if the server response fetching settings to be synced is received after the
            // view is opened), so notify the view if the model is updated.
            ctx.notify();
        });
        ctx.observe(&privacy_settings_handle, Self::update_button_states);
        ctx.subscribe_to_model(&privacy_settings_handle, |me, model, _, ctx| {
            me.update_button_states(model, ctx);
            ctx.notify();
        });
        ctx.subscribe_to_model(&SafeModeSettings::handle(ctx), |me, _, _, ctx| {
            me.update_secret_display_dropdown(ctx);
            ctx.notify();
        });

        ctx.observe(&HistorySettings::handle(ctx), |_, _, ctx| ctx.notify());

        let delete_history_body = ctx.add_typed_action_view(DeleteHistoryModal::new);
        ctx.subscribe_to_view(&delete_history_body, |me, _, event, ctx| {
            me.handle_delete_history_modal_event(event, ctx);
        });
        let delete_history_modal_view = ctx.add_typed_action_view(|ctx| {
            Modal::new(
                Some("Delete saved history?".to_string()),
                delete_history_body,
                ctx,
            )
            .with_modal_style(UiComponentStyles {
                width: Some(520.),
                height: Some(300.),
                ..Default::default()
            })
            .with_header_style(UiComponentStyles {
                padding: Some(Coords {
                    top: 24.,
                    bottom: 0.,
                    left: 24.,
                    right: 24.,
                }),
                font_size: Some(16.),
                font_weight: Some(Weight::Bold),
                ..Default::default()
            })
            .with_body_style(UiComponentStyles {
                padding: Some(Coords {
                    top: 0.,
                    bottom: 24.,
                    left: 24.,
                    right: 24.,
                }),
                height: Some(200.),
                ..Default::default()
            })
            .with_background_opacity(100)
            .with_dismiss_on_click()
        });
        ctx.subscribe_to_view(&delete_history_modal_view, |me, _, event, ctx| {
            me.handle_delete_history_modal_close(event, ctx);
        });

        let add_regex_body = ctx.add_typed_action_view(AddRegexModal::new);
        ctx.subscribe_to_view(&add_regex_body, |me, _, event, ctx| {
            me.handle_add_regex_modal_event(event, ctx);
        });

        let add_regex_modal_view = ctx.add_typed_action_view(|ctx| {
            Modal::new(Some("Add regex pattern".to_string()), add_regex_body, ctx)
                .with_modal_style(UiComponentStyles {
                    width: Some(600.),
                    height: Some(400.),
                    ..Default::default()
                })
                .with_header_style(UiComponentStyles {
                    padding: Some(Coords {
                        top: 24.,
                        bottom: 0.,
                        left: 24.,
                        right: 24.,
                    }),
                    font_size: Some(16.),
                    font_weight: Some(Weight::Bold),
                    ..Default::default()
                })
                .with_body_style(UiComponentStyles {
                    padding: Some(Coords {
                        top: 0.,
                        bottom: 24.,
                        left: 24.,
                        right: 24.,
                    }),
                    ..Default::default()
                })
                .with_background_opacity(100)
                .with_dismiss_on_click()
        });
        ctx.subscribe_to_view(&add_regex_modal_view, |me, _, event, ctx| {
            me.handle_modal_event(event, ctx);
        });

        let secret_display_dropdown = ctx.add_typed_action_view(|ctx| {
            let mut dropdown = Dropdown::new(ctx);
            dropdown.set_items(
                SecretDisplayMode::all_modes()
                    .iter()
                    .map(|mode| {
                        DropdownItem::new(
                            mode.display_name(),
                            PrivacyPageAction::SetSecretDisplayMode(*mode),
                        )
                    })
                    .collect(),
                ctx,
            );
            dropdown
        });

        let mut privacy_page_view = Self {
            page: Self::build_page(),
            added_user_secret_regex_list_button_handles: Default::default(),
            pending_regex_removals: Default::default(),
            pending_timer: None,
            add_regex_modal_state: AddRegexModalViewState::new(ModalViewState::new(
                add_regex_modal_view,
            )),
            secret_redaction_display_dropdown: secret_display_dropdown,
            delete_history_modal: ModalViewState::new(delete_history_modal_view),
            delete_history_in_progress: false,
        };

        privacy_page_view.update_button_states(privacy_settings_handle, ctx);
        privacy_page_view.update_secret_display_dropdown(ctx);
        privacy_page_view
    }

    fn build_page() -> PageType<Self> {
        let widgets: Vec<Box<dyn SettingsWidget<View = Self>>> = vec![
            Box::new(SecretRedactionWidget::default()),
            Box::new(CommandHistoryWidget::default()),
        ];
        PageType::new_uncategorized(widgets, Some(PageTitle::new("Privacy")))
    }

    fn update_button_states(
        &mut self,
        privacy_settings_handle: ModelHandle<PrivacySettings>,
        ctx: &mut ViewContext<Self>,
    ) {
        let privacy_settings = privacy_settings_handle.as_ref(ctx);
        self.added_user_secret_regex_list_button_handles = privacy_settings
            .user_secret_regex_list
            .iter()
            .map(|_| Default::default())
            .collect();
    }

    fn toggle_safe_mode(&mut self, ctx: &mut ViewContext<Self>) {
        let safe_mode_settings = SafeModeSettings::handle(ctx);
        let new_value = { !*safe_mode_settings.as_ref(ctx).safe_mode_enabled.value() };

        ctx.update_model(&safe_mode_settings, move |safe_mode_settings, ctx| {
            report_if_error!(
                safe_mode_settings
                    .safe_mode_enabled
                    .set_value(new_value, ctx)
            );
        });
        ctx.notify();
    }

    fn toggle_save_command_history(&mut self, ctx: &mut ViewContext<Self>) {
        let history_settings = HistorySettings::handle(ctx);
        let new_value = !*history_settings.as_ref(ctx).save_command_history.value();

        ctx.update_model(&history_settings, move |history_settings, ctx| {
            report_if_error!(
                history_settings
                    .save_command_history
                    .set_value(new_value, ctx)
            );
        });
        if !new_value {
            self.show_delete_history_modal(true, ctx);
        }
        ctx.notify();
    }

    fn show_delete_history_modal(
        &mut self,
        offered_after_turning_off: bool,
        ctx: &mut ViewContext<Self>,
    ) {
        self.delete_history_modal.view.update(ctx, |modal, ctx| {
            modal.body().update(ctx, |body, ctx| {
                body.set_offered_after_turning_off(offered_after_turning_off, ctx);
            });
        });
        self.delete_history_modal.open();
        ctx.emit(PrivacyPageViewEvent::DeleteHistoryModalChanged);
    }

    fn hide_delete_history_modal(&mut self, ctx: &mut ViewContext<Self>) {
        self.delete_history_modal.close();
        ctx.emit(PrivacyPageViewEvent::DeleteHistoryModalChanged);
    }

    fn handle_delete_history_modal_close(
        &mut self,
        event: &ModalEvent,
        ctx: &mut ViewContext<Self>,
    ) {
        match event {
            ModalEvent::Close => self.hide_delete_history_modal(ctx),
        }
    }

    fn handle_delete_history_modal_event(
        &mut self,
        event: &DeleteHistoryModalEvent,
        ctx: &mut ViewContext<Self>,
    ) {
        match event {
            DeleteHistoryModalEvent::Close => self.hide_delete_history_modal(ctx),
            DeleteHistoryModalEvent::Confirm => {
                self.hide_delete_history_modal(ctx);
                self.delete_saved_history(ctx);
            }
        }
    }

    fn delete_saved_history(&mut self, ctx: &mut ViewContext<Self>) {
        if self.delete_history_in_progress {
            return;
        }
        let window_id = ctx.window_id();
        let show_toast = move |toast: DismissibleToast<WorkspaceAction>,
                               persistent: bool,
                               ctx: &mut AppContext| {
            ToastStack::handle(ctx).update(ctx, |toast_stack, ctx| {
                if persistent {
                    toast_stack.add_persistent_toast(toast, window_id, ctx);
                } else {
                    toast_stack.add_ephemeral_toast(toast, window_id, ctx);
                }
            });
        };

        let Some(sender) = GlobalResourceHandlesProvider::as_ref(ctx)
            .get()
            .model_event_sender
            .clone()
        else {
            show_toast(
                DismissibleToast::error(
                    "OpenRun has no local history database to delete from.".to_string(),
                ),
                false,
                ctx,
            );
            return;
        };

        self.delete_history_in_progress = true;
        ctx.notify();
        let (done, outcome) = futures::channel::oneshot::channel();
        ctx.spawn(
            async move {
                sender
                    .send(ModelEvent::DeleteSavedHistory { done: Some(done) })
                    .map_err(|err| format!("could not reach the database writer: {err}"))?;
                outcome
                    .await
                    .map_err(|_| "the database writer stopped before finishing".to_string())?
            },
            move |view, result: Result<SavedHistoryDeleted, String>, ctx| {
                view.delete_history_in_progress = false;
                if let Err(error) = &result {
                    log::warn!("Failed to delete saved history: {error}");
                }
                if result.is_ok() {
                    // The rows are gone from the database whether or not the files are scrubbed,
                    // so the in-memory copy of the saved commands goes either way.
                    History::handle(ctx).update(ctx, |history, _| {
                        history.clear_persisted_commands();
                    });
                }
                match delete_history_notice(&result) {
                    DeleteHistoryNotice::Compacted(text) => {
                        show_toast(DismissibleToast::success(text), false, ctx);
                    }
                    // Stays until dismissed: it says that something is still owed.
                    DeleteHistoryNotice::CompactionPending(text) => {
                        show_toast(DismissibleToast::default(text), true, ctx);
                    }
                    DeleteHistoryNotice::Failed(text) => {
                        show_toast(DismissibleToast::error(text), false, ctx);
                    }
                }
                ctx.notify();
            },
        );
    }

    fn toggle_hide_secrets_in_block_list(&mut self, ctx: &mut ViewContext<Self>) {
        let safe_mode_settings = SafeModeSettings::handle(ctx);
        let new_value = {
            !*safe_mode_settings
                .as_ref(ctx)
                .hide_secrets_in_block_list
                .value()
        };

        ctx.update_model(&safe_mode_settings, move |safe_mode_settings, ctx| {
            report_if_error!(
                safe_mode_settings
                    .hide_secrets_in_block_list
                    .set_value(new_value, ctx)
            );
        });
        ctx.notify();
    }

    fn set_secret_display_mode(&mut self, mode: SecretDisplayMode, ctx: &mut ViewContext<Self>) {
        let safe_mode_settings = SafeModeSettings::handle(ctx);

        ctx.update_model(&safe_mode_settings, move |safe_mode_settings, ctx| {
            report_if_error!(safe_mode_settings.secret_display_mode.set_value(mode, ctx));
        });
        ctx.notify();
    }

    fn queue_regex_removal(&mut self, idx: usize, ctx: &mut ViewContext<Self>) {
        // Check if this removal is already pending
        if self.pending_regex_removals.contains(&idx) {
            return;
        }

        if let Some(timer) = self.pending_timer.take() {
            timer.abort();
        }

        // Add to pending set
        self.pending_regex_removals.insert(idx);
        ctx.notify();

        // Start a new timer only if we don't have one
        if self.pending_timer.is_none() {
            let handle = ctx.spawn(
                async move {
                    Timer::after(Duration::from_millis(Self::BATCH_TIMEOUT_MS)).await;
                },
                |me, _, ctx| {
                    // Only process if we still have pending removals and a timer
                    // (they might have been processed by an add operation)
                    if !me.pending_regex_removals.is_empty() && me.pending_timer.is_some() {
                        me.pending_timer = None;
                        me.process_pending_removals(ctx);
                    }
                },
            );
            self.pending_timer = Some(handle);
        }
    }

    fn update_secret_display_dropdown(&mut self, ctx: &mut ViewContext<Self>) {
        let safe_mode_settings = SafeModeSettings::as_ref(ctx);

        let current_mode = get_effective_secret_display_mode(safe_mode_settings);
        self.secret_redaction_display_dropdown
            .update(ctx, |dropdown, ctx| {
                dropdown.set_selected_by_action(
                    PrivacyPageAction::SetSecretDisplayMode(current_mode),
                    ctx,
                );
            });
    }

    fn process_pending_removals(&mut self, ctx: &mut ViewContext<Self>) {
        let mut indices: Vec<_> = self.pending_regex_removals.iter().copied().collect();
        if indices.is_empty() {
            return;
        }
        indices.sort_unstable_by(|a, b| b.cmp(a)); // Sort in reverse order to remove from highest index first

        let privacy_settings_handle = PrivacySettings::handle(ctx);
        for idx in indices {
            privacy_settings_handle.update(ctx, |privacy_settings, ctx| {
                privacy_settings.remove_user_secret_regex(&idx, ctx);
            });
        }

        self.pending_regex_removals.clear();
        ctx.notify();
    }

    fn show_add_regex_modal(&mut self, ctx: &mut ViewContext<Self>) {
        self.add_regex_modal_state.open(ctx);
        ctx.emit(PrivacyPageViewEvent::ShowAddRegexModal);
    }
    fn hide_add_regex_modal(&mut self, ctx: &mut ViewContext<Self>) {
        self.add_regex_modal_state.close(ctx);
        ctx.emit(PrivacyPageViewEvent::HideAddRegexModal);
    }

    fn handle_modal_event(&mut self, event: &ModalEvent, ctx: &mut ViewContext<Self>) {
        match event {
            ModalEvent::Close => {
                self.hide_add_regex_modal(ctx);
            }
        }
    }

    fn handle_add_regex_modal_event(
        &mut self,
        event: &AddRegexModalEvent,
        ctx: &mut ViewContext<Self>,
    ) {
        match event {
            AddRegexModalEvent::Close => {
                self.hide_add_regex_modal(ctx);
            }
            AddRegexModalEvent::Submit { name, pattern } => {
                self.add_custom_regex(name.clone(), pattern.clone(), ctx);
                self.hide_add_regex_modal(ctx);
            }
        }
    }

    fn add_custom_regex(&mut self, name: String, pattern: String, ctx: &mut ViewContext<Self>) {
        // First process any pending removals
        if !self.pending_regex_removals.is_empty() {
            self.process_pending_removals(ctx);
        }

        let privacy_settings_handle = PrivacySettings::handle(ctx);
        ctx.update_model(
            &privacy_settings_handle,
            |privacy_settings, ctx| match Regex::new(&pattern) {
                Ok(regex) => {
                    let mut new_user_secret_regex_list =
                        privacy_settings.user_secret_regex_list.to_vec();
                    new_user_secret_regex_list.push(CustomSecretRegex {
                        pattern: regex,
                        name: if name.trim().is_empty() {
                            None
                        } else {
                            Some(name.trim().to_string())
                        },
                    });

                    if privacy_settings
                        .user_secret_regex_list
                        .set_value(new_user_secret_regex_list, ctx)
                        .is_err()
                    {
                        report_error!("Failed to add custom regex to secret regex list");
                    }
                    ctx.notify();
                }
                _ => {
                    report_error!(
                        "Invalid regex pattern",
                        extra: { "pattern" => %pattern }
                    );
                }
            },
        );
    }

    pub fn get_modal_content(&self) -> Option<Box<dyn Element>> {
        if self.add_regex_modal_state.is_open() {
            Some(self.add_regex_modal_state.render())
        } else if self.delete_history_modal.is_open() {
            Some(self.delete_history_modal.render())
        } else {
            None
        }
    }
}

impl View for PrivacyPageView {
    fn ui_name() -> &'static str {
        "PrivacyPageView"
    }

    fn render(&self, app: &AppContext) -> Box<dyn Element> {
        self.page.render(self, app)
    }
}

impl Entity for PrivacyPageView {
    type Event = PrivacyPageViewEvent;
}

#[derive(Clone, Debug, PartialEq)]
pub enum PrivacyPageAction {
    ToggleSafeMode,
    ToggleSaveCommandHistory,
    ShowDeleteHistoryModal,
    ToggleHideSecretsInBlockList,
    SetSecretDisplayMode(SecretDisplayMode),
    RemoveCustomRegex(usize),
    AddAllRecommendedRegexes,
    ShowAddRegexModal,
    AddRecommendedRegex(usize),
}

impl TypedActionView for PrivacyPageView {
    type Action = PrivacyPageAction;

    fn handle_action(&mut self, action: &PrivacyPageAction, ctx: &mut ViewContext<Self>) {
        match action {
            PrivacyPageAction::AddRecommendedRegex(idx) => {
                // First process any pending removals
                if !self.pending_regex_removals.is_empty() {
                    self.process_pending_removals(ctx);
                }

                let privacy_settings_handle = PrivacySettings::handle(ctx);
                ctx.update_model(&privacy_settings_handle, |privacy_settings, ctx| {
                    let current_patterns: Vec<&str> = privacy_settings
                        .user_secret_regex_list
                        .iter()
                        .map(|r| r.pattern().as_str())
                        .collect();

                    let recommended_regexes: Vec<_> =
                        crate::terminal::model::secrets::regexes::DEFAULT_REGEXES_WITH_NAMES
                            .iter()
                            .filter(|r| !current_patterns.contains(&r.pattern))
                            .collect();

                    if let Some(regex) = recommended_regexes.get(*idx)
                        && let Ok(pattern) = Regex::new(regex.pattern)
                    {
                        let mut new_user_secret_regex_list =
                            privacy_settings.user_secret_regex_list.to_vec();
                        new_user_secret_regex_list.push(CustomSecretRegex {
                            pattern,
                            name: Some(regex.name.to_string()),
                        });

                        if privacy_settings
                            .user_secret_regex_list
                            .set_value(new_user_secret_regex_list, ctx)
                            .is_err()
                        {
                            report_error!(
                                "Failed to add recommended regex to custom secret regex list"
                            );
                        }
                        ctx.notify();
                    }
                });
            }
            PrivacyPageAction::ToggleSafeMode => self.toggle_safe_mode(ctx),
            PrivacyPageAction::ToggleSaveCommandHistory => self.toggle_save_command_history(ctx),
            PrivacyPageAction::ShowDeleteHistoryModal => {
                self.show_delete_history_modal(false, ctx);
            }
            PrivacyPageAction::ToggleHideSecretsInBlockList => {
                self.toggle_hide_secrets_in_block_list(ctx)
            }
            PrivacyPageAction::SetSecretDisplayMode(mode) => {
                self.set_secret_display_mode(*mode, ctx)
            }
            PrivacyPageAction::RemoveCustomRegex(idx) => {
                self.queue_regex_removal(*idx, ctx);
            }
            PrivacyPageAction::AddAllRecommendedRegexes => {
                // First process any pending removals
                if !self.pending_regex_removals.is_empty() {
                    self.process_pending_removals(ctx);
                }

                let privacy_settings_handle = PrivacySettings::handle(ctx);
                ctx.update_model(&privacy_settings_handle, |privacy_settings, ctx| {
                    privacy_settings.add_all_recommended_regex(ctx);
                });
            }
            PrivacyPageAction::ShowAddRegexModal => {
                self.show_add_regex_modal(ctx);
            }
        }
    }
}

impl SettingsPageMeta for PrivacyPageView {
    fn section() -> SettingsSection {
        SettingsSection::Privacy
    }

    fn should_render(&self, _ctx: &AppContext) -> bool {
        true
    }

    fn update_filter(&mut self, query: &str, ctx: &mut ViewContext<Self>) -> MatchData {
        self.page.update_filter(query, ctx)
    }

    fn scroll_to_widget(&mut self, widget_id: &'static str) {
        self.page.scroll_to_widget(widget_id)
    }

    fn clear_highlighted_widget(&mut self) {
        self.page.clear_highlighted_widget();
    }
}

impl From<ViewHandle<PrivacyPageView>> for SettingsPageViewHandle {
    fn from(view_handle: ViewHandle<PrivacyPageView>) -> Self {
        SettingsPageViewHandle::Privacy(view_handle)
    }
}

#[derive(Default)]
struct SecretRedactionWidget {
    switch_state: SwitchStateHandle,
    add_regex_button_mouse_state: MouseStateHandle,
    add_recommended_button_mouse_states: RefCell<Vec<MouseStateHandle>>,
    add_all_button_mouse_state: MouseStateHandle,
}

impl SecretRedactionWidget {
    /// Ensures there's enough mouse states for the recommended regexes to be added.
    fn ensure_recommended_regex_mouse_states(&self, count: usize) {
        while self.add_recommended_button_mouse_states.borrow().len() < count {
            self.add_recommended_button_mouse_states
                .borrow_mut()
                .push(Default::default());
        }
    }

    /// Renders a section title with consistent styling
    fn render_section_title(&self, title: String, appearance: &Appearance) -> Box<dyn Element> {
        Text::new_inline(title, appearance.ui_font_family(), FONT_SIZE)
            .with_color(appearance.theme().active_ui_text_color().into())
            .finish()
    }

    /// Renders a description paragraph with consistent styling
    fn render_description(
        &self,
        text: String,
        appearance: &Appearance,
        margin_bottom: f32,
    ) -> Box<dyn Element> {
        let description_text_color = description_text_color(appearance.theme()).into_solid();
        appearance
            .ui_builder()
            .paragraph(text)
            .with_style(UiComponentStyles {
                font_color: Some(description_text_color),
                margin: Some(
                    Coords::default()
                        .top(styles::DESCRIPTION_LINE_MARGIN_BOTTOM)
                        .bottom(margin_bottom),
                ),
                ..Default::default()
            })
            .build()
            .finish()
    }

    /// Renders a regex item with consistent container styling
    fn render_regex_item(
        &self,
        content: Box<dyn Element>,
        appearance: &Appearance,
    ) -> Box<dyn Element> {
        let background = appearance.theme().surface_overlay_1();
        Container::new(content)
            .with_background(background)
            .with_corner_radius(CornerRadius::with_all(Radius::Pixels(4.)))
            .with_uniform_padding(8.)
            .with_margin_bottom(4.)
            .finish()
    }

    fn horizontal_divider(&self, appearance: &Appearance) -> Box<dyn Element> {
        Container::new(
            ConstrainedBox::new(
                Rect::new()
                    .with_background(appearance.theme().outline())
                    .finish(),
            )
            .with_height(1.)
            .finish(),
        )
        .with_vertical_margin(24.)
        .finish()
    }

    /// Renders regex content using the RegexDisplayInfo trait
    fn render_regex_content<T: RegexDisplayInfo>(
        &self,
        regex_info: &T,
        appearance: &Appearance,
    ) -> Box<dyn Element> {
        let regex_color = internal_colors::fg_overlay_6(appearance.theme());

        if let Some(name) = regex_info.name() {
            Flex::column()
                .with_child(
                    Text::new_inline(name.to_string(), appearance.ui_font_family(), FONT_SIZE)
                        .with_color(appearance.theme().active_ui_text_color().into())
                        .finish(),
                )
                .with_child(
                    Text::new_inline(
                        regex_info.pattern().to_string(),
                        appearance.ui_font_family(),
                        FONT_SIZE,
                    )
                    .with_color(regex_color.into())
                    .finish(),
                )
                .finish()
        } else {
            Text::new_inline(
                regex_info.pattern().to_string(),
                appearance.ui_font_family(),
                FONT_SIZE,
            )
            .with_color(regex_color.into())
            .finish()
        }
    }

    /// Renders the user regexes and the recommended regexes
    fn render_regex_list(
        &self,
        view: &PrivacyPageView,
        appearance: &Appearance,
        app: &AppContext,
    ) -> Box<dyn Element> {
        let privacy_settings = PrivacySettings::as_ref(app);
        let ui_builder = appearance.ui_builder();
        let mut column = Flex::column();

        for (i, regex) in privacy_settings.user_secret_regex_list.iter().enumerate() {
            if view.pending_regex_removals.contains(&i) {
                continue;
            }

            let text_content = self.render_regex_content(regex, appearance);

            let item = self.render_regex_item(
                Flex::row()
                    .with_cross_axis_alignment(CrossAxisAlignment::Center)
                    .with_child(Expanded::new(1., text_content).finish())
                    .with_child(
                        ui_builder
                            .close_button(
                                20., // diameter
                                view.added_user_secret_regex_list_button_handles[i].clone(),
                            )
                            .build()
                            .on_click(move |ctx, _, _| {
                                ctx.dispatch_typed_action(PrivacyPageAction::RemoveCustomRegex(i));
                            })
                            .finish(),
                    )
                    .finish(),
                appearance,
            );

            column.add_child(item);
        }

        // Get a list of regexes that are recommended but not currently in use
        let current_patterns: Vec<&str> = privacy_settings
            .user_secret_regex_list
            .iter()
            .map(|r| r.pattern().as_str())
            .collect();

        let recommended_regexes: Vec<_> =
            crate::terminal::model::secrets::regexes::DEFAULT_REGEXES_WITH_NAMES
                .iter()
                .filter(|r| !current_patterns.contains(&r.pattern))
                .collect();

        if !recommended_regexes.is_empty() {
            column.add_child(self.horizontal_divider(appearance));

            // Add the "Recommended" header with "Add all" button
            column.add_child(
                Container::new(
                    Flex::row()
                        .with_main_axis_size(MainAxisSize::Max)
                        .with_main_axis_alignment(MainAxisAlignment::SpaceBetween)
                        .with_cross_axis_alignment(CrossAxisAlignment::Center)
                        .with_child(
                            self.render_section_title("Recommended".to_string(), appearance),
                        )
                        .with_child(
                            Container::new(
                                ui_builder
                                    .button(
                                        ButtonVariant::Secondary,
                                        self.add_all_button_mouse_state.clone(),
                                    )
                                    .with_text_and_icon_label(Self::add_button(
                                        "Add all", appearance,
                                    ))
                                    .with_style(Self::add_button_style())
                                    .build()
                                    .on_click(move |ctx, _, _| {
                                        ctx.dispatch_typed_action(
                                            PrivacyPageAction::AddAllRecommendedRegexes,
                                        );
                                    })
                                    .finish(),
                            )
                            .with_margin_bottom(8.)
                            .finish(),
                        )
                        .finish(),
                )
                .finish(),
            );

            self.ensure_recommended_regex_mouse_states(recommended_regexes.len());
            let recommended_button_states = self.add_recommended_button_mouse_states.borrow();

            for (i, regex) in recommended_regexes.iter().enumerate() {
                let text_content = self.render_regex_content(regex, appearance);

                let item = self.render_regex_item(
                    Flex::row()
                        .with_cross_axis_alignment(CrossAxisAlignment::Center)
                        .with_child(Expanded::new(1., text_content).finish())
                        .with_child(
                            icon_button(
                                appearance,
                                Icon::Plus,
                                false,
                                recommended_button_states[i].clone(),
                            )
                            .build()
                            .on_click(move |ctx, _, _| {
                                ctx.dispatch_typed_action(PrivacyPageAction::AddRecommendedRegex(
                                    i,
                                ));
                            })
                            .finish(),
                        )
                        .finish(),
                    appearance,
                );

                column.add_child(item);
            }
        }

        column.finish()
    }

    fn add_button(text: impl Into<Cow<'static, str>>, appearance: &Appearance) -> TextAndIcon {
        TextAndIcon::new(
            TextAndIconAlignment::IconFirst,
            text,
            Icon::Plus.to_warpui_icon(appearance.theme().active_ui_text_color()),
            MainAxisSize::Min,
            MainAxisAlignment::SpaceBetween,
            vec2f(16., 16.),
        )
        .with_inner_padding(3.)
    }

    fn add_button_style() -> UiComponentStyles {
        UiComponentStyles {
            padding: Some(Coords {
                // There's some offset issue with the button component
                left: 8.,
                right: 12.,
                top: 6.,
                bottom: 6.,
            }),
            margin: Some(Coords {
                left: 8.,
                right: 0.,
                top: 0.,
                bottom: 0.,
            }),
            ..Default::default()
        }
    }
}

impl SettingsWidget for SecretRedactionWidget {
    type View = PrivacyPageView;

    fn search_terms(&self) -> &str {
        "secret redaction safe mode hide"
    }

    fn render(
        &self,
        view: &Self::View,
        appearance: &Appearance,
        app: &AppContext,
    ) -> Box<dyn Element> {
        let safe_mode_settings = SafeModeSettings::as_ref(app);
        let privacy_settings = PrivacySettings::as_ref(app);
        let description_text_color = description_text_color(appearance.theme()).into_solid();
        let ui_builder = appearance.ui_builder();

        let secret_redaction_title_row = Container::new(
            Flex::row()
                .with_child(
                    Shrinkable::new(1.0, render_sub_header(appearance, SAFE_MODE_TITLE)).finish(),
                )
                .with_child(
                    Container::new(
                        ui_builder
                            .switch(self.switch_state.clone())
                            .check(*safe_mode_settings.safe_mode_enabled.value())
                            .build()
                            .on_click(move |ctx, _, _| {
                                ctx.dispatch_typed_action(PrivacyPageAction::ToggleSafeMode)
                            })
                            .finish(),
                    )
                    .with_padding_right(TOGGLE_BUTTON_RIGHT_PADDING)
                    .finish(),
                )
                .with_cross_axis_alignment(CrossAxisAlignment::Start)
                .finish(),
        )
        .with_padding_bottom(HEADER_PADDING)
        .finish();

        let mut column = Flex::column()
            .with_child(secret_redaction_title_row)
            .with_child(
                ui_builder
                    .paragraph((*SAFE_MODE_DESCRIPTION).to_owned())
                    .with_style(UiComponentStyles {
                        font_color: Some(description_text_color),
                        font_size: Some(FONT_SIZE + 1.), // One size up from current 12px to 13px
                        margin: Some(
                            Coords::default()
                                .top(-24.)
                                .bottom(styles::DESCRIPTION_LINE_MARGIN_BOTTOM),
                        ),
                        ..Default::default()
                    })
                    .build()
                    .finish(),
            );

        if *safe_mode_settings.safe_mode_enabled {
            // Add the secret display mode dropdown
            let label = super::settings_page::render_dropdown_item_label(
                "Secret visual redaction mode".to_string(),
                None,
                None,
                appearance,
            );

            // Create left column with label and description
            let left_content = Flex::column()
                .with_child(label)
                .with_child(
                    Container::new(
                        ui_builder
                            .paragraph(
                                "Choose how secrets are visually presented in the block list while keeping them searchable. This setting only affects what you see in the block list.",
                            )
                            .with_style(UiComponentStyles {
                                font_color: Some(description_text_color),
                                margin: Some(
                                    Coords::default()
                                        .top(4.)
                                        .bottom(0.),
                                ),
                                ..Default::default()
                            })
                            .build()
                            .finish()
                    )
                    .finish()
                )
                .finish();

            // Create the horizontal row with left content and dropdown
            let dropdown_row = Flex::row()
                .with_cross_axis_alignment(CrossAxisAlignment::Start)
                .with_child(
                    Shrinkable::new(
                        1.0,
                        Container::new(left_content)
                            .with_padding_right(16.) // Space between left content and dropdown
                            .finish(),
                    )
                    .finish(),
                )
                .with_child(ChildView::new(&view.secret_redaction_display_dropdown).finish())
                .finish();

            column.add_child(
                Container::new(dropdown_row)
                    .with_margin_top(8.)
                    .with_margin_bottom(styles::DESCRIPTION_MARGIN_BOTTOM)
                    .finish(),
            );

            // User regexes section
            column.add_child(
                Flex::row()
                    .with_cross_axis_alignment(CrossAxisAlignment::Start)
                    .with_child(
                        Expanded::new(
                            1.,
                            Flex::column()
                                .with_child(self.render_section_title(
                                    USER_SECRET_REGEX_TITLE.to_string(),
                                    appearance,
                                ))
                                .with_child(self.render_description(
                                    USER_SECRET_REGEX_DESCRIPTION.to_owned(),
                                    appearance,
                                    if privacy_settings.user_secret_regex_list.iter().count() > 0 {
                                        10.
                                    } else {
                                        0.
                                    },
                                ))
                                .finish(),
                        )
                        .finish(),
                    )
                    .with_child(
                        ui_builder
                            .button(
                                ButtonVariant::Secondary,
                                self.add_regex_button_mouse_state.clone(),
                            )
                            .with_text_and_icon_label(Self::add_button("Add regex", appearance))
                            .with_style(Self::add_button_style())
                            .build()
                            .on_click(move |ctx, _, _| {
                                ctx.dispatch_typed_action(PrivacyPageAction::ShowAddRegexModal);
                            })
                            .finish(),
                    )
                    .finish(),
            );

            let tab_content = self.render_regex_list(view, appearance, app);

            column.add_child(tab_content);
            column.add_child(self.horizontal_divider(appearance));
        }

        Container::new(column.finish()).finish()
    }
}

#[derive(Default)]
struct CommandHistoryWidget {
    switch_state: SwitchStateHandle,
    delete_button_mouse_state: MouseStateHandle,
}

impl SettingsWidget for CommandHistoryWidget {
    type View = PrivacyPageView;

    fn search_terms(&self) -> &str {
        "save command history block output privacy delete clear saved history commands session restore up arrow"
    }

    fn render(
        &self,
        view: &Self::View,
        appearance: &Appearance,
        app: &AppContext,
    ) -> Box<dyn Element> {
        let history_settings = HistorySettings::as_ref(app);
        let description_text_color = description_text_color(appearance.theme()).into_solid();
        let ui_builder = appearance.ui_builder();

        let title_row = Container::new(
            Flex::row()
                .with_child(
                    Shrinkable::new(1.0, render_sub_header(appearance, SAVE_HISTORY_TITLE))
                        .finish(),
                )
                .with_child(
                    Container::new(
                        ui_builder
                            .switch(self.switch_state.clone())
                            .check(*history_settings.save_command_history.value())
                            .build()
                            .on_click(move |ctx, _, _| {
                                ctx.dispatch_typed_action(
                                    PrivacyPageAction::ToggleSaveCommandHistory,
                                )
                            })
                            .finish(),
                    )
                    .with_padding_right(TOGGLE_BUTTON_RIGHT_PADDING)
                    .finish(),
                )
                .with_cross_axis_alignment(CrossAxisAlignment::Start)
                .finish(),
        )
        .with_padding_bottom(HEADER_PADDING)
        .finish();

        let description = ui_builder
            .paragraph(SAVE_HISTORY_DESCRIPTION.to_owned())
            .with_style(UiComponentStyles {
                font_color: Some(description_text_color),
                font_size: Some(FONT_SIZE + 1.),
                margin: Some(
                    Coords::default()
                        .top(-24.)
                        .bottom(styles::DESCRIPTION_LINE_MARGIN_BOTTOM),
                ),
                ..Default::default()
            })
            .build()
            .finish();

        let mut delete_button = ui_builder
            .button(
                ButtonVariant::Secondary,
                self.delete_button_mouse_state.clone(),
            )
            .with_text_label("Delete saved history".to_string())
            .with_style(UiComponentStyles {
                padding: Some(Coords {
                    left: 12.,
                    right: 12.,
                    top: 6.,
                    bottom: 6.,
                }),
                margin: Some(Coords::default().left(16.)),
                ..Default::default()
            });
        if view.delete_history_in_progress {
            delete_button = delete_button.disabled();
        }

        let delete_row = Flex::row()
            .with_cross_axis_alignment(CrossAxisAlignment::Center)
            .with_child(
                Expanded::new(
                    1.,
                    ui_builder
                        .paragraph(DELETE_HISTORY_DESCRIPTION.to_owned())
                        .with_style(UiComponentStyles {
                            font_color: Some(description_text_color),
                            font_size: Some(FONT_SIZE + 1.),
                            ..Default::default()
                        })
                        .build()
                        .finish(),
                )
                .finish(),
            )
            .with_child(
                delete_button
                    .build()
                    .on_click(move |ctx, _, _| {
                        ctx.dispatch_typed_action(PrivacyPageAction::ShowDeleteHistoryModal);
                    })
                    .finish(),
            )
            .finish();

        Container::new(
            Flex::column()
                .with_child(title_row)
                .with_child(description)
                .with_child(delete_row)
                .finish(),
        )
        .with_margin_top(styles::DESCRIPTION_MARGIN_BOTTOM * 2.)
        .finish()
    }
}

pub fn init_actions_from_parent_view<T: Action + Clone>(
    app: &mut AppContext,
    context: &ContextPredicate,
    builder: fn(SettingsAction) -> T,
) {
    let toggle_binding_pairs = vec![ToggleSettingActionPair::new(
        "secret redaction",
        builder(SettingsAction::PrivacyPageToggle(
            PrivacyPageAction::ToggleSafeMode,
        )),
        context,
        flags::SAFE_MODE_FLAG,
    )];

    ToggleSettingActionPair::add_toggle_setting_action_pairs_as_bindings(toggle_binding_pairs, app);
}

mod styles {
    /// The space between a description and the next toggle.
    pub const DESCRIPTION_MARGIN_BOTTOM: f32 = 12.;

    /// The space between two description lines which are describing the same toggle.
    pub const DESCRIPTION_LINE_MARGIN_BOTTOM: f32 = 6.;
}

fn description_text_color(theme: &WarpTheme) -> warp_core::ui::theme::Fill {
    theme.sub_text_color(theme.surface_2())
}

#[cfg(test)]
#[path = "privacy_page_tests.rs"]
mod tests;
