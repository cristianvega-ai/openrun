use super::*;

fn session() -> HashMap<String, String> {
    HashMap::from([
        ("PATH".to_owned(), "/usr/bin:/mnt/c/Windows:/bin".to_owned()),
        ("GIT_CONFIG_COUNT".to_owned(), "1".to_owned()),
        ("GIT_CONFIG_KEY_0".to_owned(), "user.name".to_owned()),
        ("GIT_CONFIG_VALUE_0".to_owned(), "session-user".to_owned()),
    ])
}

#[test]
fn the_wsl_guest_gets_the_offline_environment_and_wslenv_lists_it() {
    let guest = guest_environment(ShellType::Bash, "git branch --no-color", Some(session()));
    for (name, value) in [
        ("GIT_NO_LAZY_FETCH", "1"),
        ("GIT_ALLOW_PROTOCOL", "file"),
        ("GIT_CONFIG_COUNT", "3"),
        ("GIT_CONFIG_KEY_0", "user.name"),
        ("GIT_CONFIG_KEY_1", "core.fsmonitor"),
        ("GIT_CONFIG_VALUE_1", "false"),
        ("GIT_CONFIG_KEY_2", "log.showSignature"),
        ("GIT_CONFIG_VALUE_2", "false"),
    ] {
        assert_eq!(
            guest.variables.get(name).map(String::as_str),
            Some(value),
            "{name}"
        );
    }
    // Only what WSLENV lists crosses into the guest.
    let listed: Vec<&str> = guest.wslenv.split(':').collect();
    for name in guest.variables.keys() {
        assert!(
            listed.contains(&format!("{name}/u").as_str()),
            "{name} is not in WSLENV {:?}",
            guest.wslenv
        );
    }
    assert_eq!(listed.len(), guest.variables.len());
    assert!(!guest.variables.contains_key("PATH"));
    assert!(
        guest.command.ends_with("; git branch --no-color")
            && guest.command.contains("/usr/bin:/mnt/c/Windows:/bin"),
        "{}",
        guest.command
    );
}

#[test]
fn the_wsl_guest_gets_the_offline_environment_without_session_variables() {
    let guest = guest_environment(ShellType::Zsh, "git branch --no-color", None);
    assert_eq!(guest.variables["GIT_NO_LAZY_FETCH"], "1");
    assert_eq!(guest.variables["GIT_CONFIG_COUNT"], "2");
    assert_eq!(guest.command, "git branch --no-color");
}

#[test]
fn windows_host_paths_are_dropped_for_bash_compgen_only() {
    let compgen = guest_environment(ShellType::Bash, "compgen -c", Some(session()));
    assert!(!compgen.command.contains("/mnt/c"), "{}", compgen.command);
    let other = guest_environment(ShellType::Zsh, "compgen -c", Some(session()));
    assert!(
        other.command.contains("/mnt/c/Windows"),
        "{}",
        other.command
    );
}

#[test]
fn the_wsl_executor_reports_the_offline_environment() {
    assert!(
        WslCommandExecutor::new("Ubuntu".to_owned(), ShellType::Bash).offline_environment_applied()
    );
}
