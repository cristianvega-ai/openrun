use super::metal;
use super::renderer::{Device, Renderer};

pub struct RendererManager {
    metal_renderer_manager: metal::RendererManager,
}

impl Default for RendererManager {
    fn default() -> Self {
        Self::new()
    }
}

impl RendererManager {
    pub fn new() -> Self {
        Self {
            metal_renderer_manager: metal::RendererManager::new(),
        }
    }

    /// Returns a [`Renderer`] that can be used to render on the given [`Device`].
    pub fn renderer_for_device(&mut self, device: &Device) -> &mut dyn Renderer {
        match device {
            Device::Metal(device) => self.metal_renderer_manager.renderer_for_device(device),
        }
    }
}
