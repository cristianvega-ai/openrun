use std::collections::HashSet;

use super::*;

#[test]
fn command_names_and_kinds_are_unique() {
    let mut names = HashSet::new();
    let mut kinds = HashSet::new();
    for command in all_commands() {
        assert!(
            names.insert(command.name),
            "duplicate slash command name: {}",
            command.name
        );
        assert!(
            kinds.insert(command.kind),
            "duplicate slash command kind: {:?}",
            command.kind
        );
    }
}

#[test]
fn every_command_has_an_icon() {
    for command in all_commands() {
        assert!(
            !command.icon_path.is_empty(),
            "{} has no icon",
            command.name
        );
    }
}

#[test]
fn only_terminal_commands_are_registered() {
    let registered = all_commands()
        .into_iter()
        .map(|command| command.name)
        .collect::<HashSet<_>>();
    for removed in [
        "/agent",
        "/new",
        "/clear",
        "/plan",
        "/model",
        "/profile",
        "/fork",
        "/rewind",
        "/queue",
        "/compact",
        "/conversations",
        "/feedback",
        "/version",
    ] {
        assert!(
            !registered.contains(removed),
            "{removed} should not be registered"
        );
    }
}

#[test]
fn no_command_requires_ai() {
    let registry = Registry::new();
    for command in registry.all_commands() {
        assert!(
            Availability::LOCAL
                .union(Availability::REPOSITORY)
                .contains(command.availability),
            "{} has unexpected availability",
            command.name
        );
    }
}

#[test]
fn rename_tab_command_requires_argument() {
    let command = COMMAND_REGISTRY
        .get_command_with_name(RENAME_TAB.name)
        .expect("expected /rename-tab to be registered");
    let argument = command
        .argument
        .as_ref()
        .expect("expected /rename-tab to require an argument");

    assert!(!argument.is_optional);
    assert_eq!(argument.hint_text, Some("<tab name>"));
}

#[test]
fn set_tab_color_command_requires_argument() {
    let command = COMMAND_REGISTRY
        .get_command_with_name(SET_TAB_COLOR.name)
        .expect("expected /set-tab-color to be registered");
    let argument = command
        .argument
        .as_ref()
        .expect("expected /set-tab-color to require an argument");

    assert!(!argument.is_optional);

    let hint = argument
        .hint_text
        .expect("/set-tab-color hint text is set dynamically");
    for color in color_dot::TAB_COLOR_OPTIONS {
        let lower = color.to_string().to_ascii_lowercase();
        assert!(hint.contains(&lower), "hint should mention `{lower}`");
    }
    assert!(hint.contains("none"), "hint should mention `none`");
}
