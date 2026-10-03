pub mod app;
pub mod mac;

pub mod headless;

pub use app::AppBuilder;
pub use warpui_core::platform::*;

/// A trait for accessing internal per-platform concrete implementations
/// through a wrapper type.
#[allow(dead_code)]
trait AsInnerMut<Inner: ?Sized> {
    fn as_inner_mut(&mut self) -> &mut Inner;
}
