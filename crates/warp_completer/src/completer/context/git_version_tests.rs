use super::*;

fn parse(output: &str) -> Option<GitVersion> {
    GitVersion::parse(output)
}

#[test]
fn plain_and_vendor_version_strings_parse() {
    for (output, expected) in [
        ("git version 2.54.0\n", GitVersion::new(2, 54, 0)),
        ("git version 2.31.0", GitVersion::new(2, 31, 0)),
        ("git version 2.30.9\n", GitVersion::new(2, 30, 9)),
        (
            "git version 2.39.3 (Apple Git-146)\n",
            GitVersion::new(2, 39, 3),
        ),
        ("git version 2.45.1.windows.1\n", GitVersion::new(2, 45, 1)),
        ("git version 2.50.1.vfs.0.0\r\n", GitVersion::new(2, 50, 1)),
        ("git version 2.43.0-rc1\n", GitVersion::new(2, 43, 0)),
        ("git version 2.31.0-rc0", GitVersion::new(2, 31, 0)),
        ("git version 2.20", GitVersion::new(2, 20, 0)),
        (
            "git version 2.36.1.windows.1.extra",
            GitVersion::new(2, 36, 1),
        ),
        ("git version 10.0.1", GitVersion::new(10, 0, 1)),
        ("  git version 2.40.1  \n", GitVersion::new(2, 40, 1)),
        ("git version 1.8.3.1\n", GitVersion::new(1, 8, 3)),
        ("git version 2.31.windows.1", GitVersion::new(2, 31, 0)),
        (
            "warning: something\ngit version 2.40.0\n",
            GitVersion::new(2, 40, 0),
        ),
    ] {
        assert_eq!(parse(output), Some(expected), "{output:?}");
    }
}

#[test]
fn text_that_is_not_a_version_does_not_parse() {
    for output in [
        "",
        "\n",
        "git",
        "git version",
        "git version \n",
        "git version 2",
        "git version 2.",
        "git version 2.x.1",
        "git version two.thirty",
        "git version .31.0",
        "git version 2..31",
        "git version -2.31.0",
        "git version +2.31.0",
        "git version 2.+31.0",
        "git version 2.31x.0",
        "git version 99999999999.1.0",
        "git version 2.99999999999.0",
        "git: command not found",
        "bash: git: command not found\n",
        "'git' is not recognized as an internal or external command",
        "Git version 2.40.0",
        "version 2.40.0",
        "usage: git [-v | --version]",
        "2.40.0",
        "xgit version 2.40.0",
    ] {
        assert_eq!(parse(output), None, "{output:?}");
    }
}

#[test]
fn the_minimum_is_git_2_31() {
    assert_eq!(MINIMUM_GIT_VERSION, GitVersion::new(2, 31, 0));
    for (output, supported) in [
        ("git version 1.8.3.1", false),
        ("git version 2.0.0", false),
        ("git version 2.30.0", false),
        ("git version 2.30.9", false),
        ("git version 2.30.2 (Apple Git-130)", false),
        ("git version 2.31.0", true),
        ("git version 2.31.0-rc0", true),
        ("git version 2.31.1", true),
        ("git version 2.32.0", true),
        ("git version 2.39.3 (Apple Git-146)", true),
        ("git version 2.45.1.windows.1", true),
        ("git version 3.0.0", true),
    ] {
        let version = parse(output).unwrap_or_else(|| panic!("{output:?} should parse"));
        assert_eq!(
            version.honors_environment_overrides(),
            supported,
            "{output:?}"
        );
    }
}

#[test]
fn versions_order_numerically_not_as_text() {
    assert!(GitVersion::new(2, 9, 0) < GitVersion::new(2, 10, 0));
    assert!(GitVersion::new(2, 31, 0) < GitVersion::new(2, 31, 1));
    assert!(GitVersion::new(1, 99, 99) < GitVersion::new(2, 0, 0));
    assert_eq!(GitVersion::new(2, 39, 3).to_string(), "2.39.3");
}
