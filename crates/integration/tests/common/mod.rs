use std::env;
use std::io::Write as _;
use std::process::Stdio;

use command::blocking::Command;
use warpui_core::integration::{CANCELED_EXIT_CODE, SKIP_EXIT_CODE};

/// The tests that may be skipped (their `should_run_test` check is false in the environment of the
/// run) when `CI` is set, with the reason each one is allowed to. Any other skip fails the test in
/// CI, so a scenario can't stop running without somebody noticing: an entry here is a reviewed
/// decision, not a default.
const ALLOWED_CI_SKIPS: &[(&str, &str)] = &[];

/// Where a skipped test appends a line (`<test>\t<shell>`), if set. CI prints the file in the job
/// summary, so the skips of a run are listed even though nextest counts a skipped test as passed.
const SKIP_REPORT_ENV_VAR: &str = "OPENRUN_SKIP_REPORT";

fn is_ci() -> bool {
    env::var("CI").is_ok_and(|value| !value.is_empty() && value != "false")
}

/// Setting this outside CI lets a run skip scenarios that don't apply to its shell (for example
/// the whole suite under fish) without failing.
const ALLOW_SKIPS_ENV_VAR: &str = "OPENRUN_ALLOW_SKIPS";

/// Handles a test process that ended with [`SKIP_EXIT_CODE`].
///
/// A skip is not a pass: it is printed in capitals, recorded in the skip report, and fails the test
/// unless it is allowed. In CI the only way is [`ALLOWED_CI_SKIPS`]; elsewhere it is setting
/// [`ALLOW_SKIPS_ENV_VAR`].
fn handle_skip(name: &str) -> Result<(), String> {
    let shell = env::var("WARP_SHELL_PATH").unwrap_or_else(|_| "(default shell)".to_owned());
    println!("TEST SKIPPED: {name} was not run (shell: {shell}); it is not a pass");
    if let Ok(path) = env::var(SKIP_REPORT_ENV_VAR)
        && let Ok(mut file) = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(path)
    {
        let _ = writeln!(file, "{name}\t{shell}");
    }
    if is_ci() {
        return match ALLOWED_CI_SKIPS
            .iter()
            .find(|(allowed, _)| *allowed == name)
        {
            Some((_, reason)) => {
                println!("TEST SKIPPED: allowed in CI: {reason}");
                Ok(())
            }
            None => Err(format!(
                "Test {name} was skipped in CI (shell: {shell}) but is not in ALLOWED_CI_SKIPS. \
                 Run it with a shell it supports, or add it to the list with the reason."
            )),
        };
    }
    if env::var_os(ALLOW_SKIPS_ENV_VAR).is_some() {
        return Ok(());
    }
    Err(format!(
        "Test {name} was skipped (shell: {shell}): its scenario doesn't apply to this shell. \
         Run it with a shell it supports, or set {ALLOW_SKIPS_ENV_VAR}=1 to allow skips."
    ))
}

/// The `integration` binary that runs one test.
///
/// nextest sets `CARGO_BIN_EXE_integration` when it runs the test, to the binary of the build it
/// runs. That is not the path cargo baked in at compile time when the tests were built on another
/// machine or in another directory and run from a nextest archive (`--archive-file`,
/// `--workspace-remap`): the compile-time path is only the fallback for the runners that do not set
/// the variable, such as `cargo test`.
fn integration_binary() -> std::path::PathBuf {
    env::var_os("CARGO_BIN_EXE_integration")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| std::path::PathBuf::from(env!("CARGO_BIN_EXE_integration")))
}

/// Runs a single integration test.
///
/// This runs the `integration` binary from the `warp` crate, passing it the
/// name of the test to execute as the one positional argument. The binary runs once: a failure
/// is a failure of the test.
pub fn run_integration_test(name: &str) -> Result<(), String> {
    let inherited_envs = env::vars_os().filter(|(k, _v)| {
        let k = k
            .to_str()
            .expect("environment variable keys should contain valid unicode");
        // Propagate the PATH to the integration test
        // process, otherwise the shell it spawns might not
        // be able to find the binaries it needs to execute.
        k == "PATH"
            // Propagate any Rust-related variables.
            || k.starts_with("RUST_")
            // Propagate any Warp-specific variables.
            || k.starts_with("WARP_")
            || k.starts_with("WARPUI_")
            // Propagate any wgpu-specific variables.
            || k.starts_with("WGPU_")
    });
    match Command::new(integration_binary())
        .arg(name)
        .env_clear()
        .envs(inherited_envs)
        .env("WARP_INTEGRATION", "1")
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
    {
        Ok(status) => match status.code() {
            Some(0) => {
                println!("Test exited with success.");
                Ok(())
            }
            Some(SKIP_EXIT_CODE) => handle_skip(name),
            Some(CANCELED_EXIT_CODE) => Err(format!("Test {name} was interrupted")),
            Some(exit_code) => Err(format!("Test {name} failed with exit code {exit_code}")),
            None => {
                use std::os::unix::process::ExitStatusExt;
                let signal = status
                    .signal()
                    .and_then(|signal| nix::sys::signal::Signal::try_from(signal).ok());
                if let Some(signal) = signal {
                    Err(format!(
                        "Test {name} failed due to signal {}",
                        signal.as_str(),
                    ))
                } else {
                    Err(format!("Test {name} failed for unknown reason"))
                }
            }
        },
        Err(err) => Err(format!("Test {name} failed with error {err:#}")),
    }
}

#[macro_export]
macro_rules! integration_tests {
    (   $(
            $(#[$args:meta])*
            $name:ident,
        )*
    ) => {
        $(
            $(#[$args])*
            // Ignore unused attributes, in case we're marking a test as
            // ignored twice, once via arguments passed to the macro and once
            // below.
            #[allow(unused_attributes)]
            // For right now, we only want to run integration tests on macOS
            // and Linux (iff the run_on_linux feature is enabled).
            #[cfg_attr(not(any(target_os = "macos", feature = "run_on_linux")), ignore)]
            #[test]
            fn $name() -> Result<(), String> {
                $crate::common::run_integration_test(stringify!($name))
            }
        )*
    }
}
