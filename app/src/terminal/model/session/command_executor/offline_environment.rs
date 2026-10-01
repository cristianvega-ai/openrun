//! The offline environment every completion-generator subprocess runs with.
//!
//! Generator commands (and the alias, history and executable-discovery commands that share the
//! executors) run automatically while the user types. Many everyday tools reach the network on
//! their own when they are merely *asked a question*: rustup installs the toolchain named by a
//! project's `rust-toolchain.toml`, npm checks for a newer version, corepack downloads the pinned
//! package manager, and git runs the `core.fsmonitor` program from a repository's config. This
//! table switches those behaviours off. It is applied last, after PATH, so it overrides whatever
//! the session environment says.
//!
//! This is one layer of three. It does not make a command offline, only stops the *implicit*
//! network use of the tools below. The OS sandbox (SEC-SBX) is what denies the network to
//! whatever is left, and the generator policy decides which generators run at all.
//!
//! Every entry says whether its effect was verified against the real tool. Entries marked
//! "documented, unverified" come from the tool's documentation; the tool was not installed where
//! this was written, so no test exercises them.

use std::collections::HashMap;
use std::path::PathBuf;

use crate::terminal::shell::ShellType;

/// Variables that are simply set. See the comment on each for the evidence.
const FIXED_VARIABLES: &[(&str, &str)] = &[
    // Verified (rustup 1.29.0, `rustup_proxies_do_not_install_a_toolchain`): `cargo metadata`,
    // `rustc --print target-list`, `cargo read-manifest`, `cargo install --list` and
    // `rustup docs --path` in a directory with a `rust-toolchain.toml` for a toolchain that is not
    // installed download that toolchain (two GETs each). `CARGO_NET_OFFLINE=true` does not
    // prevent it; this does.
    ("RUSTUP_AUTO_INSTALL", "0"),
    // Verified (corepack 0.34.6, `corepack_does_not_download_the_pinned_package_manager`): the `yarn`/`pnpm` shims download the package
    // manager pinned by `packageManager` in package.json.
    ("COREPACK_ENABLE_NETWORK", "0"),
    // Verified (npm 11.12.1, `npm_does_not_check_for_updates`): `npm prefix` and other commands end with an
    // update-notifier registry GET. `NO_UPDATE_NOTIFIER=1` does not stop it; this does.
    ("npm_config_update_notifier", "false"),
    // Verified (git 2.54, `git_does_not_lazy_fetch_from_a_promisor_remote`): git fetches a missing
    // object from a partial clone's promisor remote while reading history or diffs.
    // `GIT_NO_LAZY_FETCH` needs git 2.44; older gits ignore it.
    ("GIT_NO_LAZY_FETCH", "1"),
    // The remaining entries are documented, unverified: the tool is not installed on the machine
    // this was written on, so no test runs it. Each is the tool's own documented switch.
    //
    // Git: never prompt for credentials on the terminal. Documented, unverified: a prompt needs a
    // terminal, which no test environment provides.
    ("GIT_TERMINAL_PROMPT", "0"),
    // Go 1.21+: never download a newer toolchain (`go.mod` `toolchain` line); never use a module
    // proxy.
    ("GOTOOLCHAIN", "local"),
    ("GOPROXY", "off"),
    // Homebrew: do not run `brew update` implicitly before install/upgrade/tap-style commands.
    // Homebrew is installed here but its auto-update rewrites the user's real Homebrew checkout,
    // so it was not run against a canary.
    ("HOMEBREW_NO_AUTO_UPDATE", "1"),
    // uv: never touch the network.
    ("UV_OFFLINE", "1"),
    // Deno: no version check.
    ("DENO_NO_UPDATE_CHECK", "1"),
    // Angular CLI: no analytics prompt or upload.
    ("NG_CLI_ANALYTICS", "false"),
    // Nx: no background daemon, no Nx Cloud.
    ("NX_DAEMON", "false"),
    ("NX_NO_CLOUD", "true"),
    // Nextflow: offline mode.
    ("NXF_OFFLINE", "true"),
    // .NET CLI: no telemetry.
    ("DOTNET_CLI_TELEMETRY_OPTOUT", "1"),
    // PowerShell 7 (`pwsh`): no usage telemetry and no check for a newer release. Update check
    // verified (pwsh 7.6.6, `powershell_does_not_check_for_updates`): an interactive `pwsh`
    // sends `CONNECT aka.ms:443` about three seconds after it starts, and with the variable it
    // sends nothing. Telemetry is documented, not observed: the `pwsh -NoProfile -c` that
    // generators run sent no request with or without either variable, so the loopback canary
    // cannot tell the two apart.
    ("POWERSHELL_TELEMETRY_OPTOUT", "1"),
    ("POWERSHELL_UPDATECHECK", "Off"),
    // Azure CLI: no telemetry.
    ("AZURE_CORE_COLLECT_TELEMETRY", "false"),
    // Google Cloud CLI: no component-manager update check.
    ("CLOUDSDK_COMPONENT_MANAGER_DISABLE_UPDATE_CHECK", "1"),
];

/// Variables of the form `KEY_<n>` / `VALUE_<n>` appended to git's `GIT_CONFIG_COUNT` list.
///
/// Verified (git 2.54, `git_fsmonitor_hook_does_not_run`): a repository whose config sets `core.fsmonitor` to a
/// program has git run that program on `status`, `diff`, `ls-files` and other index-reading
/// commands. Command-line configuration (`GIT_CONFIG_COUNT`) outranks repository config, so this
/// turns the hook off. The pair is appended after any pairs the session already defines, never
/// written over them.
const GIT_CONFIG_OVERRIDES: &[(&str, &str)] = &[("core.fsmonitor", "false")];

/// Hosts docker may talk to without leaving the machine.
const LOCAL_DOCKER_HOST_PREFIXES: &[&str] = &["unix://", "npipe://", "fd://"];

/// What to do to a subprocess environment.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct OfflineEnvironment {
    pub set: Vec<(String, String)>,
    pub remove: Vec<&'static str>,
}

impl OfflineEnvironment {
    /// Computes the changes for a subprocess whose environment is `session_vars` layered over the
    /// app's own process environment.
    pub fn for_session(session_vars: &HashMap<String, String>) -> Self {
        Self::compute(|name| {
            session_vars
                .get(name)
                .cloned()
                .or_else(|| std::env::var(name).ok())
        })
    }

    /// Computes the changes given a lookup of the subprocess's effective environment.
    pub fn compute(lookup: impl Fn(&str) -> Option<String>) -> Self {
        let mut environment = Self::default();
        for &(name, value) in FIXED_VARIABLES {
            environment.set.push((name.to_owned(), value.to_owned()));
        }

        let count = lookup("GIT_CONFIG_COUNT")
            .and_then(|count| count.trim().parse::<usize>().ok())
            .unwrap_or(0);
        for (offset, &(key, value)) in GIT_CONFIG_OVERRIDES.iter().enumerate() {
            let index = count + offset;
            environment
                .set
                .push((format!("GIT_CONFIG_KEY_{index}"), key.to_owned()));
            environment
                .set
                .push((format!("GIT_CONFIG_VALUE_{index}"), value.to_owned()));
        }
        environment.set.push((
            "GIT_CONFIG_COUNT".to_owned(),
            (count + GIT_CONFIG_OVERRIDES.len()).to_string(),
        ));

        // Verified with the real docker CLI on the Linux CI runner (`docker_does_not_use_a_remote_host_or_context`;
        // docker is not installed on the development machine, where the test skips): `DOCKER_HOST`
        // beats the current context, and a `tcp://` or `ssh://` host or context endpoint makes
        // the docker CLI contact a remote daemon. Only local sockets are kept; a remote context
        // is replaced by the always-local `default` one.
        if lookup("DOCKER_HOST").is_some_and(|host| !is_local_docker_host(&host)) {
            environment.remove.push("DOCKER_HOST");
        }
        if docker_context_is_remote(&lookup) {
            environment
                .set
                .push(("DOCKER_CONTEXT".to_owned(), "default".to_owned()));
        }
        environment
    }

    /// Applies the changes to an environment map (removals first, then values).
    pub fn apply_to(&self, variables: &mut HashMap<String, String>) {
        for name in &self.remove {
            variables.remove(*name);
        }
        for (name, value) in &self.set {
            variables.insert(name.clone(), value.clone());
        }
    }
}

/// The session environment with the offline table applied (always `Some`), plus the names to
/// strip from the environment the subprocess inherits from the app.
pub fn harden(
    session_vars: Option<HashMap<String, String>>,
) -> (Option<HashMap<String, String>>, Vec<&'static str>) {
    let mut variables = session_vars.unwrap_or_default();
    let environment = OfflineEnvironment::for_session(&variables);
    environment.apply_to(&mut variables);
    (Some(variables), environment.remove)
}

/// Like [`harden`], for a subprocess that does not inherit the app's environment (WSL: only the
/// variables listed in `WSLENV` cross into the guest), so only `session_vars` is consulted and
/// nothing needs stripping.
#[cfg_attr(not(windows), allow(dead_code))]
pub fn harden_isolated(
    session_vars: Option<HashMap<String, String>>,
) -> Option<HashMap<String, String>> {
    let mut variables = session_vars.unwrap_or_default();
    let environment = OfflineEnvironment::compute(|name| variables.get(name).cloned());
    environment.apply_to(&mut variables);
    Some(variables)
}

fn is_local_docker_host(host: &str) -> bool {
    let host = host.trim();
    host.is_empty()
        || LOCAL_DOCKER_HOST_PREFIXES
            .iter()
            .any(|prefix| host.starts_with(prefix))
}

/// Whether the docker context that would be selected points at a non-local daemon.
///
/// Reads `DOCKER_CONTEXT` (or `currentContext` from `$DOCKER_CONFIG/config.json`) and the matching
/// `contexts/meta/*/meta.json`. Any file that is missing or malformed means "not remote", the same
/// answer docker itself reaches by falling back to the default context.
fn docker_context_is_remote(lookup: &impl Fn(&str) -> Option<String>) -> bool {
    let Some(config_dir) = lookup("DOCKER_CONFIG")
        .map(PathBuf::from)
        .or_else(|| lookup("HOME").map(|home| PathBuf::from(home).join(".docker")))
    else {
        return false;
    };

    let context_name = lookup("DOCKER_CONTEXT")
        .filter(|name| !name.is_empty())
        .or_else(|| {
            let config = std::fs::read_to_string(config_dir.join("config.json")).ok()?;
            let config: serde_json::Value = serde_json::from_str(&config).ok()?;
            config.get("currentContext")?.as_str().map(str::to_owned)
        });
    let Some(context_name) = context_name.filter(|name| name != "default") else {
        return false;
    };

    let Ok(entries) = std::fs::read_dir(config_dir.join("contexts").join("meta")) else {
        return false;
    };
    entries.flatten().any(|entry| {
        let Ok(meta) = std::fs::read_to_string(entry.path().join("meta.json")) else {
            return false;
        };
        let Ok(meta) = serde_json::from_str::<serde_json::Value>(&meta) else {
            return false;
        };
        meta.get("Name").and_then(|name| name.as_str()) == Some(context_name.as_str())
            && meta
                .pointer("/Endpoints/docker/Host")
                .and_then(|host| host.as_str())
                .is_some_and(|host| !is_local_docker_host(host))
    })
}

/// A shell statement sequence that applies the same table inside a POSIX shell, for executors
/// that run the command in the user's own shell and so cannot set the environment from outside.
///
/// Only bash and zsh are covered. The statements run inside the generator's command
/// substitution, so nothing leaks into the interactive session. Docker contexts are not
/// inspected here (only a remote `DOCKER_HOST`).
pub fn posix_prologue(shell_type: ShellType) -> Option<String> {
    if !matches!(shell_type, ShellType::Bash | ShellType::Zsh) {
        return None;
    }
    let mut prologue = String::new();
    prologue.push_str("export");
    for (name, value) in FIXED_VARIABLES {
        prologue.push_str(&format!(" {name}={value}"));
    }
    prologue.push(';');
    prologue.push_str(" __openrun_n=${GIT_CONFIG_COUNT:-0};");
    prologue.push_str(" case $__openrun_n in ''|*[!0-9]*) __openrun_n=0;; esac;");
    for (offset, (key, value)) in GIT_CONFIG_OVERRIDES.iter().enumerate() {
        prologue.push_str(&format!(
            " export \"GIT_CONFIG_KEY_$((__openrun_n + {offset}))={key}\" \"GIT_CONFIG_VALUE_$((__openrun_n + {offset}))={value}\";"
        ));
    }
    prologue.push_str(&format!(
        " export \"GIT_CONFIG_COUNT=$((__openrun_n + {}))\"; unset __openrun_n;",
        GIT_CONFIG_OVERRIDES.len()
    ));
    prologue.push_str(" case ${DOCKER_HOST:-} in ''");
    for prefix in LOCAL_DOCKER_HOST_PREFIXES {
        prologue.push_str(&format!("|{prefix}*"));
    }
    prologue.push_str(") ;; *) unset DOCKER_HOST;; esac;");
    Some(prologue)
}

#[cfg(test)]
#[path = "offline_environment_tests.rs"]
mod tests;
