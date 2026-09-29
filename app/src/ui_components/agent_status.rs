//! Status of an agent run as shown in agent icons, vertical tabs, and notifications.

use warp_core::ui::appearance::Appearance;
use warp_core::ui::color::coloru_with_opacity;
use warp_core::ui::theme::{Fill, WarpTheme};
use warpui::Element;
use warpui::color::ColorU;
use warpui::elements::{ConstrainedBox, Container, CornerRadius, Radius};

use crate::ui_components::icons::Icon;

/// Padding around the status icon rendered by [`render_status_element`].
pub const STATUS_ELEMENT_PADDING: f32 = 2.;

/// The displayed state of an agent run.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AgentStatus {
    /// The agent is working.
    InProgress,
    /// The agent's last turn finished successfully.
    Success,
    /// The agent's last turn failed.
    Error,
    /// The agent is waiting on the user.
    Blocked,
}

impl std::fmt::Display for AgentStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AgentStatus::InProgress => write!(f, "In progress"),
            AgentStatus::Success => write!(f, "Done"),
            AgentStatus::Error => write!(f, "Error"),
            AgentStatus::Blocked => write!(f, "Blocked"),
        }
    }
}

impl AgentStatus {
    pub fn status_icon_and_color(&self, theme: &WarpTheme) -> (Icon, ColorU) {
        match self {
            AgentStatus::InProgress => (Icon::ClockLoader, theme.ansi_fg_magenta()),
            AgentStatus::Success => (Icon::Check, theme.ansi_fg_green()),
            AgentStatus::Error => (Icon::Triangle, theme.ansi_fg_red()),
            AgentStatus::Blocked => (Icon::StopFilled, theme.ansi_fg_yellow()),
        }
    }
}

/// A status that can be rendered by [`render_status_element`].
pub trait StatusElementStyle {
    fn status_icon_and_color(&self, theme: &WarpTheme) -> (Icon, ColorU);
}

impl StatusElementStyle for AgentStatus {
    fn status_icon_and_color(&self, theme: &WarpTheme) -> (Icon, ColorU) {
        AgentStatus::status_icon_and_color(self, theme)
    }
}

/// Renders a status icon on a tinted rounded background.
pub fn render_status_element(
    status: &impl StatusElementStyle,
    icon_size: f32,
    appearance: &Appearance,
) -> Box<dyn Element> {
    let theme = appearance.theme();
    let (icon, color) = status.status_icon_and_color(theme);

    Container::new(
        ConstrainedBox::new(icon.to_warpui_icon(Fill::from(color)).finish())
            .with_width(icon_size)
            .with_height(icon_size)
            .finish(),
    )
    .with_uniform_padding(STATUS_ELEMENT_PADDING)
    .with_background(coloru_with_opacity(color, 10))
    .with_corner_radius(CornerRadius::with_all(Radius::Pixels(4.)))
    .finish()
}
