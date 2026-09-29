use super::{Argument, Availability, SlashCommandKind, StaticCommand};

fn command(availability: Availability) -> StaticCommand {
    StaticCommand {
        kind: SlashCommandKind::Edit,
        name: "/test",
        description: "test",
        icon_path: "bundled/svg/file-code-02.svg",
        availability,
        argument: Some(Argument::optional().with_hint_text("<hint>")),
    }
}

fn local_session_with_repo() -> Availability {
    Availability::LOCAL | Availability::REPOSITORY
}

#[test]
fn always_available_in_any_context() {
    let command = command(Availability::ALWAYS);
    assert!(command.is_active(local_session_with_repo()));
    assert!(command.is_active(Availability::LOCAL));
    assert!(command.is_active(Availability::empty()));
}

#[test]
fn repository_requirement_needs_a_repository() {
    let command = command(Availability::REPOSITORY);
    assert!(command.is_active(local_session_with_repo()));
    assert!(!command.is_active(Availability::LOCAL));
}

#[test]
fn local_requirement_needs_a_local_session() {
    let command = command(Availability::LOCAL);
    assert!(command.is_active(Availability::LOCAL));
    assert!(!command.is_active(Availability::empty()));
}

#[test]
fn all_requirements_must_be_satisfied() {
    let command = command(Availability::LOCAL | Availability::REPOSITORY);
    assert!(command.is_active(local_session_with_repo()));
    assert!(!command.is_active(Availability::LOCAL));
    assert!(!command.is_active(Availability::REPOSITORY));
}

#[test]
fn argument_hint_uses_shared_command_prefix_and_text() {
    let hint = command(Availability::ALWAYS)
        .argument_hint()
        .expect("command has an argument hint");

    assert_eq!(hint.input_prefix, "/test ");
    assert_eq!(hint.text, "<hint>");

    let mut without_argument = command(Availability::ALWAYS);
    without_argument.argument = None;
    assert_eq!(without_argument.argument_hint(), None);
}
