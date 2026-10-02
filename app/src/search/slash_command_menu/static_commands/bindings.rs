use warpui::keymap::BindingDescription;

use super::StaticCommand;

pub enum DefaultSlashCommandBinding {
    None,
    Single(&'static str),
}

pub fn default_binding_for_command(name: &'static str) -> DefaultSlashCommandBinding {
    match name {
        "/open-repo" => DefaultSlashCommandBinding::Single("alt-cmd-o"),
        _ => DefaultSlashCommandBinding::None,
    }
}

pub fn binding_description(command: &StaticCommand) -> BindingDescription {
    BindingDescription::new_preserve_case(format!("Slash command: {}", command.name))
}
