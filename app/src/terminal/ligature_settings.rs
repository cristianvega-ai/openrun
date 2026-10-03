use settings::Setting;
use settings::macros::define_settings_group;
use warpui::{AppContext, SingletonEntity};

define_settings_group!(LigatureSettings, settings: [
    ligature_rendering_enabled: LigatureRenderingEnabled {
        type: bool,
        default: false,
        private: false,
        toml_path: "appearance.text.ligature_rendering_enabled",
        description: "Whether to render font ligatures in the terminal.",
    },
]);

pub fn should_use_ligature_rendering(app: &AppContext) -> bool {
    *LigatureSettings::as_ref(app)
        .ligature_rendering_enabled
        .value()
}
