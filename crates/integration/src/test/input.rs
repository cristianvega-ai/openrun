use std::time::Duration;

use warp::integration_testing::input::{
    AutosuggestionState, assert_autosuggestion_state, input_contains_string,
    tab_completions_menu_is_open,
};
use warp::integration_testing::step::new_step_with_default_assertions;
use warp::integration_testing::terminal::util::ExpectedExitStatus;
use warp::integration_testing::terminal::{
    execute_command_for_single_terminal_in_tab, wait_until_bootstrapped_single_pane_for_tab,
};
use warp::integration_testing::view_getters::single_terminal_view_for_tab;
use warpui_core::async_assert_eq;

use super::new_builder;
use crate::Builder;

/// Ensures that tab completions are hidden when the completions menu is opened
/// but re-appear when the menu is closed.
pub fn test_autosuggestions_are_hidden_when_opening_tab_completions() -> Builder {
    new_builder()
        // Ensure that $HOME contains a directory as a tab-completion candidate.
        .with_setup(|utils| {
            let dir = utils.test_dir();
            std::fs::create_dir(dir.join("foo")).expect("must be able to create dirs for test");
        })
        .with_step(wait_until_bootstrapped_single_pane_for_tab(0))
        // Execute a command so that we can generate autosuggestions.
        .with_step(execute_command_for_single_terminal_in_tab(
            0,
            "cd .".into(),
            ExpectedExitStatus::Success,
            (),
        ))
        .with_step(
            new_step_with_default_assertions("Insert 'cd' into input")
                .with_typed_characters(&["cd "])
                .add_named_assertion(
                    "Ensure cd is in input",
                    input_contains_string(0, String::from("cd ")),
                )
                .add_named_assertion(
                    "Ensure autosuggestion is present",
                    assert_autosuggestion_state(
                        0,
                        AutosuggestionState::ActiveWithText(String::from(".")),
                    ),
                ),
        )
        .with_step(
            new_step_with_default_assertions("Open tab completions menu")
                .with_keystrokes(&["tab"])
                .add_named_assertion(
                    "Ensure tab completions menu is open",
                    tab_completions_menu_is_open(0, true),
                )
                .add_named_assertion(
                    "Ensure autosuggestion is closed",
                    assert_autosuggestion_state(0, AutosuggestionState::Closed),
                ),
        )
        .with_step(
            new_step_with_default_assertions("Close tab completions menu")
                .with_keystrokes(&["escape"])
                .add_named_assertion(
                    "Ensure tab completions menu is closed",
                    tab_completions_menu_is_open(0, false),
                )
                .add_named_assertion(
                    "Ensure autosuggestion is closed",
                    assert_autosuggestion_state(
                        0,
                        AutosuggestionState::ActiveWithText(String::from(".")),
                    ),
                ),
        )
}

/// Checks that the git branch prompt chip value is correctly populated.
pub fn test_git_prompt_chips() -> Builder {
    // Note that we can't use the OUT_DIR for the temp directory
    // here because that would put us in the warp repo. We need to
    // be in a place in the filesystem that's not already a git repo.
    new_builder()
        .use_tmp_filesystem_for_test_root_directory()
        .with_step(wait_until_bootstrapped_single_pane_for_tab(0))
        .with_step(execute_command_for_single_terminal_in_tab(
            0,
            "git init -b main; git config user.email \"test@test.com\"; git config user.name \"Git TestUser\"".into(),
            ExpectedExitStatus::Success,
            (),
        ))
        .with_step(execute_command_for_single_terminal_in_tab(
            0,
            "touch file".into(),
            ExpectedExitStatus::Success,
            (),
        ))
        .with_step(
            new_step_with_default_assertions("Git branch chip should be populated").set_timeout(Duration::from_secs(15)).add_assertion(|app, window_id| {
                    let terminal_view = single_terminal_view_for_tab(app, window_id, 0);
                    terminal_view.read(app, |terminal_view, ctx| {
                        terminal_view.input().read(ctx, |input_view, ctx| {
                            let git_branch = input_view.prompt_render_helper.git_branch(ctx);
                            async_assert_eq!(git_branch, Some("main".to_string()))
                        })
                    })
            }),
        )
}
