use super::*;

fn map(pairs: &[(&str, &str)]) -> HashMap<String, String> {
    pairs
        .iter()
        .map(|(name, value)| ((*name).to_owned(), (*value).to_owned()))
        .collect()
}

#[test]
fn names_compare_exactly_or_ignoring_case() {
    assert!(NameCase::Sensitive.same("PATH", "PATH"));
    assert!(!NameCase::Sensitive.same("PATH", "Path"));
    assert!(!NameCase::Sensitive.same("git_config_count", "GIT_CONFIG_COUNT"));

    assert!(NameCase::Insensitive.same("PATH", "PATH"));
    assert!(NameCase::Insensitive.same("PATH", "Path"));
    assert!(NameCase::Insensitive.same("path", "PATH"));
    assert!(NameCase::Insensitive.same("git_config_count", "GIT_CONFIG_COUNT"));
    assert!(NameCase::Insensitive.same("Npm_Config_Update_Notifier", "npm_config_update_notifier"));
    assert!(!NameCase::Insensitive.same("PATH", "PATHEXT"));
    assert!(!NameCase::Insensitive.same("GIT_CONFIG_KEY_1", "GIT_CONFIG_KEY_10"));
    assert!(!NameCase::Insensitive.same("", "PATH"));
    // The dotless i upper-cases to `I`, as it does for Windows environment names.
    assert!(NameCase::Insensitive.same("GIT_CONF\u{131}G_COUNT", "GIT_CONFIG_COUNT"));
    assert!(!NameCase::Sensitive.same("GIT_CONF\u{131}G_COUNT", "GIT_CONFIG_COUNT"));
}

#[test]
fn the_host_rule_is_case_insensitive_on_windows_only() {
    assert_eq!(NameCase::of_host() == NameCase::Insensitive, cfg!(windows));
}

#[test]
fn lookup_finds_a_differently_spelled_name_only_when_insensitive() {
    let variables = map(&[("Path", "/bin"), ("HOME", "/h")]);
    assert_eq!(
        get_variable(&variables, "PATH", NameCase::Insensitive).map(String::as_str),
        Some("/bin")
    );
    assert_eq!(get_variable(&variables, "PATH", NameCase::Sensitive), None);
    assert_eq!(
        get_variable(&variables, "HOME", NameCase::Sensitive).map(String::as_str),
        Some("/h")
    );
    assert_eq!(
        get_variable(&variables, "USER", NameCase::Insensitive),
        None
    );
}

#[test]
fn lookup_among_several_spellings_does_not_depend_on_hash_order() {
    for _ in 0..50 {
        let variables = map(&[("path", "lower"), ("Path", "title"), ("PATH", "upper")]);
        assert_eq!(
            get_variable(&variables, "PATH", NameCase::Insensitive).map(String::as_str),
            Some("upper"),
            "the exact spelling wins"
        );
        let variables = map(&[("path", "lower"), ("Path", "title")]);
        assert_eq!(
            get_variable(&variables, "PATH", NameCase::Insensitive).map(String::as_str),
            Some("title"),
            "otherwise the first in sorted order"
        );
    }
}

#[test]
fn setting_replaces_every_spelling_when_insensitive() {
    let mut variables = map(&[("path", "a"), ("Path", "b"), ("HOME", "/h")]);
    set_variable(
        &mut variables,
        "PATH",
        "c".to_owned(),
        NameCase::Insensitive,
    );
    assert_eq!(variables, map(&[("PATH", "c"), ("HOME", "/h")]));

    let mut variables = map(&[("Path", "b"), ("HOME", "/h")]);
    set_variable(&mut variables, "PATH", "c".to_owned(), NameCase::Sensitive);
    assert_eq!(
        variables,
        map(&[("Path", "b"), ("PATH", "c"), ("HOME", "/h")]),
        "on a case-sensitive host `Path` is another variable"
    );
}

#[test]
fn removing_drops_every_spelling_when_insensitive() {
    let mut variables = map(&[("docker_host", "a"), ("DOCKER_HOST", "b"), ("HOME", "/h")]);
    remove_variable(&mut variables, "DOCKER_HOST", NameCase::Insensitive);
    assert_eq!(variables, map(&[("HOME", "/h")]));

    let mut variables = map(&[("docker_host", "a"), ("DOCKER_HOST", "b")]);
    remove_variable(&mut variables, "DOCKER_HOST", NameCase::Sensitive);
    assert_eq!(variables, map(&[("docker_host", "a")]));
}
