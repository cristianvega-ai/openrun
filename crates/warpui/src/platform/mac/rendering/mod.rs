mod metal;
mod renderer;
mod renderer_manager;

pub use renderer::{Device, MetalDevice, Renderer};
pub use renderer_manager::RendererManager;

pub use self::metal::is_integrated_gpu;

/// Returns `true` if a low power GPU is available for rendering. Typically, this is true for
/// machines with two GPUs -- a dedicated discrete high-performance GPU and a lower power
/// integrated GPU.
pub fn is_low_power_gpu_available() -> bool {
    let devices = objc2_metal::MTLCopyAllDevices();
    let gpu_count = devices.count();
    gpu_count > 1 && (0..gpu_count).any(|i| metal::is_integrated_gpu(&devices.objectAtIndex(i)))
}
