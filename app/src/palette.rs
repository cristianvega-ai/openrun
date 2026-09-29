use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash, Serialize, Deserialize)]
pub enum PaletteMode {
    Command,
    Navigation,
    LaunchConfig,
    Files,
}

#[derive(Clone, Copy, Debug)]
pub enum PaletteSource {
    Keybinding,
    CtrlTab { shift_pressed_initially: bool },
    QuitModal,
    IntegrationTest,
    ContextChip,
    TitleBarSearchBar,
}
