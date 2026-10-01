//! Evidence for the generators that run only in an isolated context
//! (`warp_completer::signatures::generators_allowed_when_isolated`): each one's real command, as
//! the bundled spec defines it, is run through the production executor (sandbox and offline
//! environment together) against a fixture in which the real tool, left alone, reaches a
//! loopback canary or runs a repository program. A pair without such a fixture fails the
//! coverage test, so nothing can be added to the tier without evidence.

use warp_command_signatures::Shell;
use warp_completer::signatures::generators_allowed_when_isolated;

use super::test_support::*;

/// The shell command the bundled spec runs for `(spec, generator)`.
fn bundled_command(spec: &str, generator: &str) -> String {
    let data = warp_command_signatures::dynamic_command_signature_data();
    let spec_data = data
        .get(spec)
        .unwrap_or_else(|| panic!("no bundled spec {spec}"));
    let (_, generator) = spec_data
        .generators()
        .iter()
        .find(|(name, _)| name.0 == generator)
        .unwrap_or_else(|| panic!("no generator {spec}/{generator}"));
    match &generator.process {
        warp_command_signatures::GeneratorProcess::ShellCommand(command) => {
            command.build(Shell::Posix).to_string()
        }
        warp_command_signatures::GeneratorProcess::CommandFromTokens(_) => {
            panic!(
                "{spec}/{generator:?} takes the user's tokens; it must not be in the isolated tier"
            )
        }
    }
}

/// The fixtures that show the tool behind `command` misbehaving when left alone. Empty when the
/// tool is not installed (the fixture said so).
fn scenarios_for(command: &str, canary: &Canary) -> Vec<Scenario> {
    let first_word = command.split_whitespace().next().unwrap_or_default();
    if matches!(first_word, "cargo" | "rustc" | "rustup") || command.contains("rustup docs") {
        rustup_scenario(canary).into_iter().collect()
    } else if command.contains("npm prefix") {
        npm_scenario(canary).into_iter().collect()
    } else if first_word == "git" {
        git_hostile_repository_scenario().into_iter().collect()
    } else if first_word == "docker" {
        docker_scenarios(canary)
    } else {
        panic!("no real-tool fixture covers `{command}`: it cannot be in the isolated tier")
    }
}

#[test]
fn every_restored_generator_is_silent_under_both_layers_and_its_fixture_is_sensitive() {
    let canary = Canary::start();
    let mut checked = Vec::new();
    for (spec, generator) in generators_allowed_when_isolated() {
        let command = bundled_command(spec, generator);
        for mut scenario in scenarios_for(&command, &canary) {
            scenario.commands = vec![command.clone()];
            scenario.control = Control::EveryCommand;
            scenario.assert_control_reaches(&canary);
            scenario.assert_silent_through(&canary, production_executor);
            checked.push(format!("{spec}/{generator} ({})", scenario.name));
        }
    }
    eprintln!("checked under both layers: {checked:?}");
}

/// Why the status-like git generators stay denied: the repository's `clean` filter is a program
/// the offline environment does not switch off. If a future change makes this test fail, those
/// generators can be reconsidered.
#[test]
fn git_commands_that_read_file_contents_still_run_a_repository_filter() {
    let canary = Canary::start();
    let Some(mut scenario) = git_hostile_repository_scenario() else {
        return;
    };
    scenario.commands = commands(&[
        "git --no-optional-locks status --short",
        "git --no-optional-locks diff --diff-filter=AM --name-only -z",
        "git --no-optional-locks ls-files -z --exclude-standard --others --modified --directory --no-empty-directory",
    ]);
    for command in scenario.commands.clone() {
        scenario.reset(&canary);
        run_as_generator(
            production_executor(),
            &command,
            &scenario.cwd,
            &scenario.path,
            &scenario.variables,
        );
        let hooks = scenario.ran_hooks();
        assert!(
            hooks.contains(&"clean".to_owned()),
            "`{command}` no longer runs the repository's clean filter (ran {hooks:?}); the \
             denied git generators that use it can be reconsidered"
        );
        assert!(
            !hooks.contains(&"fsmonitor".to_owned()),
            "`{command}` ran core.fsmonitor despite the offline environment"
        );
    }
}
