use super::{
    SlashCommandSelectionBehavior, should_close_slash_command_menu_for_exact_match,
    slash_command_selection_behavior,
};
use crate::search::slash_command_menu::static_commands::{SlashCommandKind, commands};

#[test]
fn rename_tab_inserts_input_for_its_required_argument() {
    assert_eq!(
        slash_command_selection_behavior(&commands::RENAME_TAB),
        SlashCommandSelectionBehavior::InsertCommandText("/rename-tab ".to_owned())
    );
}

#[test]
fn commands_without_arguments_execute_on_selection() {
    for command in [
        &commands::OPEN_CODE_REVIEW,
        &commands::OPEN_SETTINGS_FILE,
        &commands::OPEN_REPO,
    ] {
        assert!(command.argument.is_none());
        assert_eq!(
            slash_command_selection_behavior(command),
            SlashCommandSelectionBehavior::Execute
        );
    }
}

#[test]
fn commands_have_typed_identities() {
    for (command, expected) in [
        (&*commands::EDIT, SlashCommandKind::Edit),
        (&*commands::RENAME_TAB, SlashCommandKind::RenameTab),
        (&*commands::SET_TAB_COLOR, SlashCommandKind::SetTabColor),
        (
            &commands::OPEN_CODE_REVIEW,
            SlashCommandKind::OpenCodeReview,
        ),
        (
            &commands::OPEN_SETTINGS_FILE,
            SlashCommandKind::OpenSettingsFile,
        ),
        (&commands::OPEN_REPO, SlashCommandKind::OpenRepo),
    ] {
        assert_eq!(command.kind, expected, "{}", command.name);
    }
}

#[test]
fn open_repo_has_a_default_keybinding() {
    use crate::search::slash_command_menu::static_commands::bindings::{
        DefaultSlashCommandBinding, default_binding_for_command,
    };

    assert!(matches!(
        default_binding_for_command(commands::OPEN_REPO.name),
        DefaultSlashCommandBinding::Single("alt-cmd-o")
    ));
    assert!(matches!(
        default_binding_for_command(commands::RENAME_TAB.name),
        DefaultSlashCommandBinding::None
    ));
}

#[test]
fn menu_closes_for_unique_match_or_started_argument() {
    assert!(should_close_slash_command_menu_for_exact_match(0, false));
    assert!(should_close_slash_command_menu_for_exact_match(1, false));
    assert!(should_close_slash_command_menu_for_exact_match(3, true));
    assert!(!should_close_slash_command_menu_for_exact_match(2, false));
}
