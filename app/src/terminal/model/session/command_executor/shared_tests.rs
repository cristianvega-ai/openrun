use super::serialize_variables_for_shell;
use crate::terminal::shell::ShellType;

#[test]
fn serializes_assignments_for_posix_shells() {
    let pairs = [("FOO", "bar"), ("GREETING", "hello world")];
    for shell_type in [ShellType::Bash, ShellType::Zsh] {
        assert_eq!(
            serialize_variables_for_shell(pairs, shell_type),
            r"FOO=bar GREETING=hello\ world"
        );
    }
}

#[test]
fn serializes_assignments_for_fish() {
    assert_eq!(
        serialize_variables_for_shell(
            [("FOO", "bar"), ("GREETING", "hello world")],
            ShellType::Fish
        ),
        r"set -x FOO bar; set -x GREETING hello\ world;"
    );
}

#[test]
fn serializes_assignments_for_powershell() {
    assert_eq!(
        serialize_variables_for_shell([("FOO", "it's")], ShellType::PowerShell),
        "$env:FOO = 'it''s';"
    );
}

#[test]
fn serializes_no_variables_as_empty_string() {
    assert_eq!(
        serialize_variables_for_shell(std::iter::empty(), ShellType::Bash),
        ""
    );
}
