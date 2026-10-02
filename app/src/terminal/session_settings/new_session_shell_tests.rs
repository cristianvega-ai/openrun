use serde_json::json;
use settings_value::SettingsValue as _;

use super::NewSessionShell;

#[test]
fn supported_values_round_trip_through_the_settings_file() {
    for shell in [
        NewSessionShell::SystemDefault,
        NewSessionShell::Executable("/bin/zsh".to_owned()),
        NewSessionShell::Custom("/opt/homebrew/bin/fish".to_owned()),
    ] {
        assert_eq!(
            NewSessionShell::from_file_value(&shell.to_file_value()),
            Some(shell)
        );
    }
}

#[test]
fn supported_values_round_trip_through_serde() {
    for shell in [
        NewSessionShell::SystemDefault,
        NewSessionShell::Executable("/bin/zsh".to_owned()),
        NewSessionShell::Custom("/opt/homebrew/bin/fish".to_owned()),
    ] {
        let json = serde_json::to_string(&shell).unwrap();
        assert_eq!(
            serde_json::from_str::<NewSessionShell>(&json).unwrap(),
            shell
        );
    }
}

#[test]
fn stored_wsl_and_msys2_shells_read_as_the_system_default_in_the_settings_file() {
    for stored in [
        json!({"wsl": "Ubuntu"}),
        json!({"msys_2": "C:/msys64/usr/bin/bash.exe"}),
    ] {
        assert_eq!(
            NewSessionShell::from_file_value(&stored),
            Some(NewSessionShell::SystemDefault),
            "{stored}"
        );
    }
}

#[test]
fn stored_wsl_and_msys2_shells_read_as_the_system_default_through_serde() {
    for stored in [
        r#"{"WSL":"Ubuntu"}"#,
        r#"{"MSYS2":"C:/msys64/usr/bin/bash.exe"}"#,
    ] {
        assert_eq!(
            serde_json::from_str::<NewSessionShell>(stored).unwrap(),
            NewSessionShell::SystemDefault,
            "{stored}"
        );
    }
}

#[test]
fn an_unknown_stored_shell_is_still_rejected() {
    assert_eq!(
        NewSessionShell::from_file_value(&json!({"cmd": "cmd.exe"})),
        None
    );
}
