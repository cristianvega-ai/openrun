//! The window's "traffic light" buttons: the close, minimize and zoom buttons that AppKit draws
//! in the upper-left corner of the title bar. OpenRun must not render UI elements underneath them.

/// Horizontal space the buttons take in the upper-left corner of the window.
const TRAFFIC_LIGHTS_WIDTH: f32 = 64.;

/// Horizontal space needed for the traffic light buttons.
///
/// Normally, we don't need to manually adjust any sizes based on zoom level as it is handled
/// by warpui. The buttons are drawn by AppKit and don't scale with zoom, so we divide by the zoom
/// factor to keep the padding constant.
pub fn traffic_light_width(zoom_factor: f32) -> f32 {
    TRAFFIC_LIGHTS_WIDTH / zoom_factor
}
