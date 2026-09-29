//! Generic model for tracking the selected item in an inline menu.
use warpui::elements::MouseStateHandle;
use warpui::{Entity, ModelContext};

use crate::terminal::input::inline_menu::view::InlineMenuAction;

#[derive(Default)]
pub struct InlineMenuMouseStates {
    pub accept: MouseStateHandle,
    pub accept_secondary: MouseStateHandle,
    pub dismiss: MouseStateHandle,
}

/// This model is generic over the action type `A` (the same type used by the `SearchMixer`).
/// It serves as a denormalized copy of the selected item that can be read/subscribed to
/// without requiring a strict dependency on the inline menu view itself.
pub struct InlineMenuModel<A: InlineMenuAction> {
    selected_item: Option<A>,
    mouse_states: InlineMenuMouseStates,
}

impl<A: InlineMenuAction> Default for InlineMenuModel<A> {
    fn default() -> Self {
        Self::new()
    }
}

impl<A: InlineMenuAction> InlineMenuModel<A> {
    pub fn new() -> Self {
        Self {
            selected_item: None,
            mouse_states: InlineMenuMouseStates::default(),
        }
    }

    /// Returns a reference to the currently selected item, if any.
    pub fn selected_item(&self) -> Option<&A> {
        self.selected_item.as_ref()
    }

    pub fn mouse_states(&self) -> &InlineMenuMouseStates {
        &self.mouse_states
    }

    pub(super) fn update_selected_item(&mut self, item: Option<A>, ctx: &mut ModelContext<Self>) {
        self.selected_item = item;
        ctx.emit(InlineMenuModelEvent::UpdatedSelectedItem);
    }

    pub(super) fn clear_selected_item(&mut self, ctx: &mut ModelContext<Self>) {
        if self.selected_item.is_some() {
            self.selected_item = None;
            ctx.emit(InlineMenuModelEvent::UpdatedSelectedItem);
        }
    }
}

#[derive(Debug, Clone)]
pub enum InlineMenuModelEvent {
    UpdatedSelectedItem,
}

impl<A: InlineMenuAction> Entity for InlineMenuModel<A> {
    type Event = InlineMenuModelEvent;
}

#[cfg(test)]
#[path = "model_tests.rs"]
mod tests;
