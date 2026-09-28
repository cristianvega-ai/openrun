use warp_core::ui::theme::WarpTheme;
use warpui::color::ColorU;

use crate::ai::agent::conversation::ConversationStatus;
use crate::ai::agent_conversations_model::AgentRunDisplayStatus;
use crate::ui_components::agent_status::{StatusColorStyle, StatusElementStyle};
use crate::ui_components::icons::Icon;

impl StatusElementStyle for ConversationStatus {
    fn status_icon_and_color(&self, theme: &WarpTheme) -> (Icon, ColorU) {
        ConversationStatus::status_icon_and_color(self, theme, StatusColorStyle::Standard)
    }
}

impl StatusElementStyle for AgentRunDisplayStatus {
    fn status_icon_and_color(&self, theme: &WarpTheme) -> (Icon, ColorU) {
        AgentRunDisplayStatus::status_icon_and_color(self, theme)
    }
}
