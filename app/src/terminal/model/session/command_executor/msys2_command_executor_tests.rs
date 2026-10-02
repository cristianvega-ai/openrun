use super::*;

fn session() -> HashMap<String, String> {
    HashMap::from([
        ("PATH".to_owned(), "/usr/bin:/c/Windows:/bin".to_owned()),
        ("GIT_CONFIG_COUNT".to_owned(), "1".to_owned()),
        ("GIT_CONFIG_KEY_0".to_owned(), "user.name".to_owned()),
        ("GIT_CONFIG_VALUE_0".to_owned(), "session-user".to_owned()),
        ("DOCKER_HOST".to_owned(), "tcp://127.0.0.1:1".to_owned()),
    ])
}

/// The variables a git started under `variables` is given by the offline environment table, on
/// top of the session's own GIT_CONFIG pair.
fn assert_table_applied(variables: &HashMap<String, String>) {
    for (name, value) in [
        ("GIT_NO_LAZY_FETCH", "1"),
        ("GIT_ALLOW_PROTOCOL", "file"),
        ("GIT_TERMINAL_PROMPT", "0"),
        ("GIT_CONFIG_COUNT", "4"),
        ("GIT_CONFIG_KEY_0", "user.name"),
        ("GIT_CONFIG_VALUE_0", "session-user"),
        ("GIT_CONFIG_KEY_1", "core.fsmonitor"),
        ("GIT_CONFIG_VALUE_1", "false"),
        ("GIT_CONFIG_KEY_2", "log.showSignature"),
        ("GIT_CONFIG_VALUE_2", "false"),
        ("GIT_CONFIG_KEY_3", "core.hooksPath"),
        ("GIT_CONFIG_VALUE_3", "/dev/null"),
    ] {
        assert_eq!(
            variables.get(name).map(String::as_str),
            Some(value),
            "{name}"
        );
    }
}

fn executor() -> MSYS2CommandExecutor {
    MSYS2CommandExecutor::new(
        Some(PathBuf::from(
            r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe",
        )),
        PathBuf::from(r"C:\Program Files\Git\bin\bash.exe"),
    )
}

#[test]
fn the_msys2_shell_gets_the_offline_environment() {
    let environment = msys2_shell_environment("git branch --no-color", Some(session()));
    assert_table_applied(&environment.variables);
    assert_eq!(environment.removals, ["DOCKER_HOST"]);
    assert_eq!(environment.variables["PATH"], "/usr/bin:/c/Windows:/bin");
}

#[test]
fn the_msys2_shell_gets_the_offline_environment_without_session_variables() {
    let environment = msys2_shell_environment("git branch --no-color", None);
    assert_eq!(environment.variables["GIT_NO_LAZY_FETCH"], "1");
    assert_eq!(environment.variables["GIT_CONFIG_KEY_0"], "core.fsmonitor");
    assert_eq!(
        environment.variables["GIT_CONFIG_KEY_1"],
        "log.showSignature"
    );
}

#[test]
fn the_windows_native_shell_of_an_msys2_session_gets_the_offline_environment() {
    let environment = executor().native_shell_environment(Some(session()));
    assert_table_applied(&environment.variables);
    assert_eq!(environment.removals, ["DOCKER_HOST"]);
    let path = environment.path.expect("PATH is converted");
    #[cfg(windows)]
    assert!(
        path.to_string_lossy()
            .to_lowercase()
            .contains(r"c:\windows"),
        "{path:?}"
    );
    #[cfg(not(windows))]
    let _ = path;
    assert!(
        !environment.variables.contains_key("PATH"),
        "PATH is passed separately, in Windows syntax"
    );
}

#[test]
fn the_msys2_executor_reports_the_offline_environment() {
    assert!(executor().offline_environment_applied());
}
