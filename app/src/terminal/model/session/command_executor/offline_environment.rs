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
//! The git entries need git 2.31 or newer (`GIT_CONFIG_COUNT`). An older git ignores them, so the
//! completion engine runs no generator that starts `git` unless the session's git is known to be
//! 2.31 or newer (`Session::git_version`, probed with `git --version`).
//!
//! This is one layer of three. It does not make a command offline, only stops the *implicit*
//! network use of the tools below. The OS sandbox (SEC-SBX) is what denies the network to
//! whatever is left, and the generator policy decides which generators run at all.
//!
//! Every entry names the test that exercised it against the real tool, and says whether that test
//! observed the network call (a loopback canary), the program that was run (a marker file), or
//! only the tool's own switch (the telemetry notice, a resolved property). An entry that could not
//! be exercised with the real tool is not in the table: the OS sandbox covers it.

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
    // Verified (git 2.54, `git_cannot_lazy_fetch_over_a_network_transport`): `GIT_NO_LAZY_FETCH`
    // is ignored by git older than 2.44. With only
    // local transports allowed, a lazy fetch from a promisor remote that is not a local path
    // fails before it connects ("transport 'http' not allowed"). The variable overrides any
    // `protocol.<name>.allow` setting of the repository.
    ("GIT_ALLOW_PROTOCOL", "file"),
    // Verified (git 2.54, `git_terminal_prompt_is_off`): with a controlling terminal, git asks
    // for a username on /dev/tty when a server answers 401; with this it fails at once.
    ("GIT_TERMINAL_PROMPT", "0"),
    // Verified (Go on the Linux CI runner, `go_does_not_download_a_toolchain` and
    // `go_does_not_fetch_modules`): a `go.mod` that asks for a newer Go makes `go` download that
    // toolchain through GOPROXY, and a `require` of an uncached module is fetched from GOPROXY.
    ("GOTOOLCHAIN", "local"),
    ("GOPROXY", "off"),
    // PowerShell 7 (`pwsh`). Verified against the real tool in
    // `powershell_update_check_and_telemetry_are_switched_off`: an interactive `pwsh` contacts
    // `aka.ms` (update check; macOS, pwsh 7.6.6) and `dc.services.visualstudio.com` (telemetry;
    // Linux CI runner) through a loopback proxy; each variable alone stops the contact it is for
    // and the two together leave no request. The `pwsh -NoProfile -c` that generators run sends
    // nothing with or without them, so for generators these are defence in depth.
    ("POWERSHELL_TELEMETRY_OPTOUT", "1"),
    ("POWERSHELL_UPDATECHECK", "Off"),
    // Effect demonstrated, not the network call (Google Cloud CLI on the Linux CI runner,
    // `gcloud_reads_the_update_check_switch_from_the_environment`): gcloud resolves the
    // `component_manager/disable_update_check` property from this variable.
    ("CLOUDSDK_COMPONENT_MANAGER_DISABLE_UPDATE_CHECK", "1"),
];

/// Variables of the form `KEY_<n>` / `VALUE_<n>` appended to git's `GIT_CONFIG_COUNT` list.
///
/// Each pair is appended after any pairs the session already defines, never written over them.
/// Command-line configuration (`GIT_CONFIG_COUNT`) outranks repository config.
///
/// * `core.fsmonitor`: verified (git 2.54, `git_fsmonitor_hook_does_not_run`). A repository whose
///   config sets it to a program has git run that program on `status`, `diff`, `ls-files` and
///   other index-reading commands.
/// * `log.showSignature`: verified (git 2.54, `git_log_does_not_run_the_repositorys_gpg_program`).
///   With it set, `git log` and `git stash list` verify the signature of each signed commit by
///   running the repository's `gpg.program` (or `gpg.ssh.program`), and a commit object with a
///   `gpgsig` header is enough to make git try.
/// * `core.hooksPath`: verified (git 2.54, `git_repository_hooks_do_not_run`). A repository's
///   `.git/hooks` run when a command writes the index (`post-index-change`) or updates a ref
///   (`reference-transaction`). `/dev/null` is a hooks directory with no hooks.
const GIT_CONFIG_OVERRIDES: &[(&str, &str)] = &[
    ("core.fsmonitor", "false"),
    ("log.showSignature", "false"),
    ("core.hooksPath", "/dev/null"),
];

/// Hosts docker may talk to without leaving the machine.
const LOCAL_DOCKER_HOST_PREFIXES: &[&str] = &["unix://", "npipe://", "fd://"];

/// What to do to a subprocess environment.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct OfflineEnvironment {
    pub set: Vec<(String, String)>,
    pub remove: Vec<&'static str>,
}

impl OfflineEnvironment {
    /// Computes the changes for a subprocess whose environment is `session_vars` layered over
    /// `process_environment`, the app's own.
    pub fn for_session(
        session_vars: &HashMap<String, String>,
        process_environment: impl Fn(&str) -> Option<String>,
    ) -> Self {
        Self::compute(|name| {
            session_vars
                .get(name)
                .cloned()
                .or_else(|| process_environment(name))
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
    harden_with(session_vars, |name| std::env::var(name).ok())
}

/// [`harden`] with the process environment given.
pub fn harden_with(
    session_vars: Option<HashMap<String, String>>,
    process_environment: impl Fn(&str) -> Option<String>,
) -> (Option<HashMap<String, String>>, Vec<&'static str>) {
    let mut variables = session_vars.unwrap_or_default();
    let environment = OfflineEnvironment::for_session(&variables, process_environment);
    environment.apply_to(&mut variables);
    (Some(variables), environment.remove)
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
