use serde::Serialize;
use warpui::Element;
use warpui::elements::MouseStateHandle;

use super::{
    InlineBannerButtonState, InlineBannerCloseButton, InlineBannerContent, InlineBannerStyle,
    render_inline_block_list_banner,
};
use crate::appearance::Appearance;
use crate::terminal::view::{InlineBannerId, TerminalAction};

#[derive(Clone, Copy, Debug, Serialize)]
pub enum NotificationsErrorBannerAction {
    Close,
}

#[derive(Default)]
pub struct NotificationsErrorBannerMouseStates {
    pub close: MouseStateHandle,
}

/// State necessary to render the (singleton) notifications error banner.
pub struct NotificationsErrorBannerState {
    pub banner_id: InlineBannerId,
    pub mouse_states: NotificationsErrorBannerMouseStates,
}

pub fn render_inline_notifications_error_banner(
    title: &str,
    state: &NotificationsErrorBannerState,
    appearance: &Appearance,
) -> Box<dyn Element> {
    let close_button = InlineBannerCloseButton(InlineBannerButtonState {
        on_click_event: TerminalAction::NotificationsErrorBanner(
            NotificationsErrorBannerAction::Close,
        ),
        mouse_state_handle: state.mouse_states.close.clone(),
    });

    render_inline_block_list_banner(
        InlineBannerStyle::LowPriority,
        appearance,
        InlineBannerContent {
            title: title.into(),
            close_button: Some(close_button),
            ..Default::default()
        },
    )
}
