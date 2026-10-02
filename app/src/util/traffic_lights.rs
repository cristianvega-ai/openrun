//! This module is meant to be a single source of truth for information about the windows' "traffic
//! light" buttons, the minimize, maximize, and close buttons in the corner of the window, so named
//! b/c of their resemblance to traffic lights on MacOS. How (whether or not) these are rendered
//! depends on the platform. The Warp app must use this information to avoid rendering UI elements
//! underneath them.

use warpui::elements::{Empty, MouseStateHandle};
use warpui::platform::FullscreenState;
use warpui::{AppContext, Element, WindowId};

use crate::themes::theme::WarpTheme;

pub fn traffic_light_data(ctx: &AppContext, window_id: WindowId) -> Option<TrafficLightData> {
    // If native window frame is on, the traffic lights are already in the frame.
    if ctx
        .windows()
        .platform_window(window_id)
        .is_some_and(|window| window.uses_native_window_decorations())
    {
        return None;
    }

    if cfg!(target_os = "macos") {
        Some(TrafficLightData {
            width: 64.,
            side: TrafficLightSide::Left,
            scales_with_zoom: false,
        })
    } else {
        None
    }
}

/// Are they in the upper-right or upper-left corner?
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TrafficLightSide {
    Left,
    Right,
}

/// Mouse state handles that the containing View must manage.
#[derive(Default)]
#[cfg_attr(any(target_family = "wasm", target_os = "macos"), allow(dead_code))]
pub struct TrafficLightMouseStates {
    pub minimize_window_button: MouseStateHandle,
    pub maximize_window_button: MouseStateHandle,
    pub close_window_button: MouseStateHandle,
}

impl TrafficLightMouseStates {
    /// True if any of the traffic light buttons are hovered.
    pub fn are_traffic_lights_hovered(&self) -> bool {
        [
            &self.minimize_window_button,
            &self.maximize_window_button,
            &self.close_window_button,
        ]
        .into_iter()
        .any(|state| state.lock().is_ok_and(|state| state.is_hovered()))
    }
}

/// Data the Warp app needs to avoid rendering anything below the traffic lights.
#[derive(Clone, Debug)]
pub struct TrafficLightData {
    width: f32,
    pub side: TrafficLightSide,
    /// Whether the traffic lights can scale with the app's zoom level.
    ///
    /// If `false` that means the traffic light buttons are of fixed size as determined by the OS
    /// and we cannot scale them as the user configures the zoom level.
    scales_with_zoom: bool,
}

impl TrafficLightData {
    /// Horizontal space needed for the traffic light buttons.
    ///
    /// Normally, we don't need to manually adjust any sizes based on zoom level as it is handled
    /// by warpui. However, native traffic light buttons (e.g. on macOS) don't scale with zoom, so
    /// we need to divide by the zoom factor to keep the padding constant.
    pub fn width(&self, zoom_factor: f32) -> f32 {
        if self.scales_with_zoom {
            self.width
        } else {
            self.width / zoom_factor
        }
    }

    pub fn render(
        &self,
        _fullscreen_state: FullscreenState,
        _mouse_states: &TrafficLightMouseStates,
        _theme: &WarpTheme,
        _app: &AppContext,
    ) -> Box<dyn Element> {
        Empty::new().finish()
    }
}
