use std::ffi::OsString;

use clap::Parser;

use super::*;

fn set_env_var(name: &str, value: &str) -> Option<OsString> {
    let previous = std::env::var_os(name);
    // Safety: tests that mutate process environment are marked `serial` so we
    // do not race with other environment readers/writers in this crate.
    unsafe { std::env::set_var(name, value) };
    previous
}

fn restore_env_var(name: &str, previous: Option<OsString>) {
    match previous {
        // Safety: tests that mutate process environment are marked `serial` so
        // we do not race with other environment readers/writers in this crate.
        Some(value) => unsafe { std::env::set_var(name, value) },
        // Safety: tests that mutate process environment are marked `serial` so
        // we do not race with other environment readers/writers in this crate.
        None => unsafe { std::env::remove_var(name) },
    }
}

#[test]
#[serial_test::serial]
fn hidden_server_overrides_parse_from_env() {
    let previous_server_root = set_env_var(SERVER_ROOT_URL_OVERRIDE_ENV, "http://localhost:8080");
    let previous_ws = set_env_var(WS_SERVER_URL_OVERRIDE_ENV, "ws://localhost:8082/graphql/v2");

    let args = Args::try_parse_from(["warp"]).unwrap();

    restore_env_var(SERVER_ROOT_URL_OVERRIDE_ENV, previous_server_root);
    restore_env_var(WS_SERVER_URL_OVERRIDE_ENV, previous_ws);

    assert_eq!(args.server_root_url(), Some("http://localhost:8080"));
    assert_eq!(args.ws_server_url(), Some("ws://localhost:8082/graphql/v2"));
}

#[test]
fn no_subcommand_collects_urls_to_open() {
    let args = Args::try_parse_from(["warp", "warp://action/new_tab"]).unwrap();

    assert!(args.command().is_none());
    assert_eq!(args.app_args().urls.len(), 1);
    assert_eq!(args.app_args().urls[0].as_str(), "warp://action/new_tab");
}

#[test]
fn completions_parses_shell() {
    let args = Args::try_parse_from(["warp", "completions", "zsh"]).unwrap();

    assert!(matches!(
        args.command(),
        Some(Command::Completions {
            shell: Some(clap_complete::aot::Shell::Zsh)
        })
    ));
}

#[test]
fn dump_debug_info_parses_as_flag() {
    let args = Args::try_parse_from(["warp", "--dump-debug-info"]).unwrap();

    assert!(matches!(args.command(), Some(Command::DumpDebugInfo)));
}

#[cfg(not(target_family = "wasm"))]
#[test]
fn dump_settings_schema_parses_output_path() {
    let args = Args::try_parse_from(["warp", "dump-settings-schema", "schema.json"]).unwrap();

    let Some(Command::DumpSettingsSchema { output_path }) = args.command() else {
        panic!("Expected `warp dump-settings-schema` command");
    };
    assert_eq!(
        output_path.as_deref(),
        Some(std::path::Path::new("schema.json"))
    );
}

#[test]
fn help_describes_the_app() {
    let help = Args::clap_command().render_long_help().to_string();

    assert!(help.starts_with("The Warp terminal"), "{help}");
}

#[test]
fn removed_cli_subcommands_are_rejected() {
    for removed in ["agent", "login", "whoami", "mcp", "environment", "schedule"] {
        assert!(
            Args::try_parse_from(["warp", removed]).is_err(),
            "`warp {removed}` should not parse"
        );
    }
    assert!(Args::try_parse_from(["warp", "--api-key", "key"]).is_err());
}
