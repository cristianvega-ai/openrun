pub mod app;
#[cfg(target_os = "macos")]
pub mod mac;

pub mod headless;

pub mod current {
    pub use super::mac::*;
}

pub use app::AppBuilder;
pub use warpui_core::platform::*;

/// Returns whether the current device is a mobile device with touch input.
///
/// This is a cross-platform wrapper around the platform-specific implementation.
pub fn is_mobile_device() -> bool {
    false
}

/// A trait for accessing internal per-platform concrete implementations
/// through a wrapper type.
#[allow(dead_code)]
trait AsInnerMut<Inner: ?Sized> {
    fn as_inner_mut(&mut self) -> &mut Inner;
}
