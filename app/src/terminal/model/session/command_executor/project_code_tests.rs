//! Evidence that a completion generator does not start code a project controls by making a
//! tool discover its interpreter or toolchain (Astra review 3, R3-01).
//!
//! Typing in a directory must never run that directory's code. Some tools run project code when
//! merely asked a question, because the question needs an interpreter and the project says which
//! one. Each fixture below is a hostile project, each tool is the real one (uv, rustup, `find`
//! and `xargs`), each cache is cold (a fresh `UV_CACHE_DIR`, a fresh `RUSTUP_HOME`), and each
//! program the project names writes a marker file. For every generator whose command is one of
//! those questions:
//!
//! * the control runs the generator's command, as the bundled spec defines it, without any
//!   policy, and must leave the marker (the project's code ran: the fixture is sensitive and the
//!   danger is real);
//! * the generator must be denied by the policy in every context (the list in
//!   `generator_policy/denied.rs`, class `project-code`);
//! * for uv, the production suggestions engine, asked for `uv pip uninstall ` (Astra's
//!   reproducer), through the production executor, must leave no marker.
//!
//! The generators of the same kind that stay allowed (`uv tool list`, `rustup docs --path`) are
//! run through the production executor in the same hostile projects and must leave no marker.
//!
//! Missing tools exit 86. CI installs uv and npm 6 (`OPENRUN_TEST_NPM6`) in
//! `.github/actions/macos-test-tools`; the sitecustomize fixture uses macOS system Python.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use typed_path::TypedPathBuf;
use warp_completer::completer::{
    CompleterOptions, CompletionsFallbackStrategy, MatchStrategy, suggestions,
};
use warp_completer::signatures::CommandRegistry;

use super::test_support::*;
use crate::completer::SessionContext;
use crate::terminal::model::session::{Session, SessionInfo};

/// The shell command the bundled spec runs for `(spec, generator)`.
fn bundled(spec: &str, generator: &str) -> String {
    bundled_script_commands(spec)
        .into_iter()
        .find(|(name, _)| name == generator)
        .unwrap_or_else(|| panic!("no fixed-command generator {spec}/{generator}"))
        .1
}

fn executable(path: &Path, body: &str) {
    use std::os::unix::fs::PermissionsExt as _;
    std::fs::write(path, body).unwrap();
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755)).unwrap();
}

fn marker_exists(marker: &Path) -> bool {
    marker.exists()
}

/// A hostile uv project: a `.venv` whose `sitecustomize.py` writes a marker (Astra's fixture),
/// and a `select.sh` that `[tool.uv.pip] python` in `pyproject.toml` names as the interpreter.
struct UvProject {
    _temp: tempfile::TempDir,
    root: PathBuf,
    marker: PathBuf,
    uv_dir: PathBuf,
    python: PathBuf,
}

impl UvProject {
    fn new() -> Option<Self> {
        let uv = require_tool("uv")?;
        // Keep the sitecustomize regression on the macOS system interpreter it reproduced with.
        // Other interpreter layouts can make a virtualenv control insensitive.
        let python = PathBuf::from("/usr/bin/python3");
        if !python.is_file() {
            eprintln!("TEST SKIPPED: required system Python /usr/bin/python3 is not installed");
            std::process::exit(86);
        }
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("project");
        std::fs::create_dir_all(&root).unwrap();
        let marker = temp.path().join("project-code-ran");
        let status = command::blocking::Command::new(&python)
            .args(["-m", "venv", "--without-pip"])
            .arg(root.join(".venv"))
            .status()
            .unwrap();
        assert!(status.success(), "could not create a virtual environment");
        let site_packages = std::fs::read_dir(root.join(".venv/lib"))
            .unwrap()
            .flatten()
            .map(|entry| entry.path().join("site-packages"))
            .find(|path| path.is_dir())
            .expect("the virtual environment has no site-packages");
        std::fs::write(
            site_packages.join("sitecustomize.py"),
            format!(
                "open({:?}, 'a').write('sitecustomize ran\\n')\n",
                marker.display().to_string()
            ),
        )
        .unwrap();
        executable(
            &root.join("select.sh"),
            &format!(
                "#!/bin/sh\necho 'select.sh ran' >> '{}'\nexec '{}' \"$@\"\n",
                marker.display(),
                python.display()
            ),
        );
        Some(Self {
            _temp: temp,
            root,
            marker,
            uv_dir: uv.parent().unwrap().to_owned(),
            python,
        })
    }

    /// The environment of one run: a fresh uv cache (cold interpreter cache), its own home.
    fn environment(&self, run: &str) -> (String, HashMap<String, String>) {
        let cache = self._temp.path().join(format!("uv-cache-{run}"));
        let mut variables = base_environment(&self._temp.path().join("home"));
        variables.insert(
            "UV_CACHE_DIR".to_owned(),
            cache.to_string_lossy().into_owned(),
        );
        // No download, whatever the command does.
        variables.insert("UV_OFFLINE".to_owned(), "1".to_owned());
        let python_dir = self.python.parent().unwrap().display().to_string();
        (
            format!("{}:{python_dir}:/usr/bin:/bin", self.uv_dir.display()),
            variables,
        )
    }

    fn use_venv_python(&self) {
        let _ = std::fs::remove_file(self.root.join("pyproject.toml"));
    }

    fn name_an_interpreter_in_pyproject(&self) {
        std::fs::write(
            self.root.join("pyproject.toml"),
            "[project]\nname = \"x\"\nversion = \"0\"\n[tool.uv.pip]\npython = \"./select.sh\"\n",
        )
        .unwrap();
    }

    fn reset(&self) {
        let _ = std::fs::remove_file(&self.marker);
    }
}

#[test]
fn the_commands_of_the_denied_uv_generators_start_the_projects_python() {
    let Some(project) = UvProject::new() else {
        return;
    };
    // The generators that were allowed and ran project code, with the project that makes each do it.
    // `uv python list` queries every interpreter on PATH: an activated virtual environment, or a
    // relative PATH entry, puts the project's own Python there.
    let cases: [(&str, &str, bool); 3] = [
        ("pip_installed_packages", "venv", false),
        ("pip_installed_packages", "pyproject", true),
        ("installed_pythons", "venv-on-path", false),
    ];
    for (generator, scenario, pyproject) in cases {
        project.reset();
        if pyproject {
            project.name_an_interpreter_in_pyproject();
        } else {
            project.use_venv_python();
        }
        let command = bundled("uv", generator);
        let with_scenario = |path: String| {
            if scenario == "venv-on-path" {
                format!("{}:{path}", project.root.join(".venv/bin").display())
            } else {
                path
            }
        };
        let (path, variables) = project.environment(&format!("control-{generator}-{scenario}"));
        let control = run_unprotected(&command, &project.root, &with_scenario(path), &variables);
        assert!(
            marker_exists(&project.marker),
            "the fixture is insensitive: `{command}` ({scenario}) did not start the project's \
             Python:\n{}",
            control.output
        );
        // The same command through the production executor, as it ran before it was denied.
        project.reset();
        let (path, variables) = project.environment(&format!("executor-{generator}-{scenario}"));
        let _ = run_as_generator(
            production_executor(),
            &command,
            &project.root,
            &with_scenario(path),
            &variables,
        );
        assert!(
            marker_exists(&project.marker),
            "`{command}` ({scenario}) through the production executor did not start the \
             project's Python: the executor's layers do not protect against it, only the \
             policy does, so this test would pass without testing the denial"
        );
    }
}

#[test]
fn uv_tool_list_is_the_one_uv_generator_that_stays_and_starts_no_project_code() {
    let Some(project) = UvProject::new() else {
        return;
    };
    let command = bundled("uv", "installed_tools");
    for pyproject in [false, true] {
        if pyproject {
            project.name_an_interpreter_in_pyproject();
        } else {
            project.use_venv_python();
        }
        for venv_on_path in [false, true] {
            project.reset();
            let (mut path, variables) =
                project.environment(&format!("tool-list-{pyproject}-{venv_on_path}"));
            if venv_on_path {
                path = format!("{}:{path}", project.root.join(".venv/bin").display());
            }
            let ran = run_as_generator(
                production_executor(),
                &command,
                &project.root,
                &path,
                &variables,
            );
            assert!(
                !marker_exists(&project.marker),
                "`{command}` started project code (pyproject interpreter: {pyproject}, venv on \
                 PATH: {venv_on_path}):\n{}",
                ran.output
            );
            assert!(
                ran.success,
                "`{command}` did not run in the hostile project:\n{}",
                ran.output
            );
        }
    }
}

/// Astra's reproducer: the production suggestions engine, asked for `uv pip uninstall `, with the
/// production executor, in a project whose `.venv` has a `sitecustomize.py`, with a cold cache.
#[test]
fn completing_uv_pip_uninstall_in_a_hostile_project_starts_no_project_code() {
    let Some(project) = UvProject::new() else {
        return;
    };
    project.use_venv_python();
    for (index, line) in [
        "uv pip uninstall ",
        "uv pip show ",
        "uv python pin ",
        "uv tool uninstall ",
    ]
    .into_iter()
    .enumerate()
    {
        project.reset();
        let (path, variables) = project.environment(&format!("engine-{index}"));
        let session = Session::new(
            SessionInfo::new_for_test().with_path(Some(path)),
            std::sync::Arc::new(production_executor()),
        );
        let context = SessionContext::new(
            session,
            CommandRegistry::global_instance(),
            TypedPathBuf::from(project.root.to_str().unwrap()),
        );
        let options = CompleterOptions {
            match_strategy: MatchStrategy::CaseInsensitive,
            fallback_strategy: CompletionsFallbackStrategy::None,
            suggest_file_path_completions_only: false,
            parse_quotes_as_literals: false,
        };
        let _ = futures_lite::future::block_on(suggestions(
            line,
            line.len(),
            Some(&variables),
            options,
            &context,
        ));
        assert!(
            !marker_exists(&project.marker),
            "completing `{line}` in a hostile uv project started the project's Python"
        );
    }
}

/// A project with a `rust-toolchain.toml` that names a toolchain by `path`: the rustup proxies
/// then start that directory's `cargo` and `rustc`.
struct CargoProject {
    _temp: tempfile::TempDir,
    root: PathBuf,
    marker: PathBuf,
    path: String,
    variables: HashMap<String, String>,
}

impl CargoProject {
    fn new() -> Option<Self> {
        let rustup = require_tool("rustup")?;
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("project");
        let toolchain = temp.path().join("toolchain");
        std::fs::create_dir_all(root.join("src")).unwrap();
        std::fs::create_dir_all(toolchain.join("bin")).unwrap();
        let marker = temp.path().join("project-code-ran");
        for name in ["cargo", "rustc", "rustdoc"] {
            executable(
                &toolchain.join("bin").join(name),
                &format!("#!/bin/sh\necho '{name} ran' >> '{}'\n", marker.display()),
            );
        }
        std::fs::write(
            root.join("rust-toolchain.toml"),
            format!("[toolchain]\npath = \"{}\"\n", toolchain.display()),
        )
        .unwrap();
        std::fs::write(
            root.join("Cargo.toml"),
            "[package]\nname = \"fixture\"\nversion = \"0.1.0\"\nedition = \"2021\"\n",
        )
        .unwrap();
        std::fs::write(root.join("src/main.rs"), "fn main() {}\n").unwrap();
        let proxies = temp.path().join("proxies");
        std::fs::create_dir_all(&proxies).unwrap();
        for name in ["cargo", "rustc", "rustup"] {
            std::os::unix::fs::symlink(&rustup, proxies.join(name)).unwrap();
        }
        let mut variables = base_environment(&temp.path().join("home"));
        variables.insert(
            "RUSTUP_HOME".to_owned(),
            temp.path()
                .join("rustup-home")
                .to_string_lossy()
                .into_owned(),
        );
        variables.insert(
            "CARGO_HOME".to_owned(),
            temp.path()
                .join("cargo-home")
                .to_string_lossy()
                .into_owned(),
        );
        Some(Self {
            path: format!("{}:/usr/bin:/bin", proxies.display()),
            _temp: temp,
            root,
            marker,
            variables,
        })
    }

    fn reset(&self) {
        let _ = std::fs::remove_file(&self.marker);
    }
}

const CARGO_GENERATORS: [&str; 6] = [
    "bin_list",
    "features_generators",
    "read_manifest",
    "spec",
    "target_list",
    "test_targets",
];

#[test]
fn a_toolchain_path_makes_every_cargo_generator_start_project_code_so_they_are_denied() {
    let Some(project) = CargoProject::new() else {
        return;
    };
    for generator in CARGO_GENERATORS {
        let command = bundled("cargo", generator);
        project.reset();
        let ran = run_unprotected(&command, &project.root, &project.path, &project.variables);
        assert!(
            marker_exists(&project.marker),
            "the fixture is insensitive: `{command}` did not start the toolchain's program:\n{}",
            ran.output
        );
    }
}

#[test]
fn rustup_docs_path_names_a_toolchain_path_without_starting_it() {
    let Some(project) = CargoProject::new() else {
        return;
    };
    let command = bundled("rustup", "rustup_docs");
    project.reset();
    let ran = run_as_generator(
        production_executor(),
        &command,
        &project.root,
        &project.path,
        &project.variables,
    );
    assert!(
        !marker_exists(&project.marker),
        "`{command}` started the project's toolchain:\n{}",
        ran.output
    );
    // And the control for this fixture: the cargo commands in it do start it.
    project.reset();
    run_unprotected(
        "cargo metadata --no-deps --format-version 1",
        &project.root,
        &project.path,
        &project.variables,
    );
    assert!(marker_exists(&project.marker));
}

/// `bazel/build_file` pipes the project's file names into `xargs -I {} sh -c '... "{}"'`. A
/// directory named `$(...)` is a command.
#[test]
fn a_directory_name_runs_a_command_in_the_bazel_build_file_generator() {
    let temp = tempfile::tempdir().unwrap();
    let project = temp.path().join("project");
    let hostile = project.join("a$(touch pwned)");
    std::fs::create_dir_all(&hostile).unwrap();
    std::fs::write(hostile.join("BUILD"), "# build\n").unwrap();
    let command = bundled("bazel", "build_file");
    let variables = base_environment(&temp.path().join("home"));
    let ran = run_unprotected(&command, &project, &system_path(), &variables);
    assert!(
        project.join("pwned").exists(),
        "the fixture is insensitive: `{command}` did not run the command in the directory \
         name:\n{}",
        ran.output
    );
}

/// npm 6 `require()`s the `onload-script` of a project's `.npmrc` whenever it loads. Local-only:
/// set `OPENRUN_TEST_NPM6` to the path of an npm 6 executable.
#[test]
fn npm_6_runs_the_onload_script_of_a_project_npmrc_so_npm_prefix_is_denied() {
    let Some(npm) = std::env::var_os("OPENRUN_TEST_NPM6").map(PathBuf::from) else {
        eprintln!("TEST SKIPPED: set OPENRUN_TEST_NPM6 to the path of npm 6");
        std::process::exit(86);
    };
    let node = require_tool("node").expect("node is needed for npm");
    let temp = tempfile::tempdir().unwrap();
    let project = temp.path().join("project");
    std::fs::create_dir_all(&project).unwrap();
    let marker = temp.path().join("project-code-ran");
    std::fs::write(
        project.join("package.json"),
        "{\"name\":\"x\",\"version\":\"1.0.0\"}",
    )
    .unwrap();
    std::fs::write(
        project.join("onload.js"),
        format!(
            "require('fs').appendFileSync({:?}, 'onload ran\\n');\n",
            marker.display().to_string()
        ),
    )
    .unwrap();
    std::fs::write(
        project.join(".npmrc"),
        format!("onload-script={}\n", project.join("onload.js").display()),
    )
    .unwrap();
    let path = format!(
        "{}:{}:/usr/bin:/bin",
        npm.parent().unwrap().display(),
        node.parent().unwrap().display()
    );
    let variables = base_environment(&temp.path().join("home"));
    run_unprotected("npm prefix", &project, &path, &variables);
    assert!(
        marker_exists(&marker),
        "npm 6 did not run the onload script"
    );
}
