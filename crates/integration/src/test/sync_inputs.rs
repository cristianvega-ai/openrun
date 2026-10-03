use std::fs::OpenOptions;
use std::io::Write as _;
use std::os::unix::fs::OpenOptionsExt as _;
use std::path::Path;
use std::sync::{Arc, OnceLock};

use warp::cmd_or_ctrl_shift;
use warp::integration_testing::step::new_step_with_default_assertions;
use warp::integration_testing::terminal::util::ExpectedExitStatus;
use warp::integration_testing::terminal::{
    assert_active_block_output, assert_command_executed, assert_long_running_block_executing,
    assert_no_block_executing, execute_command, run_alt_grid_program, wait_until_bootstrapped_pane,
    wait_until_bootstrapped_single_pane_for_tab,
};
use warp::integration_testing::view_getters::{terminal_view, workspace_view};
use warp::workspace::WorkspaceAction;
use warpui_core::integration::TestStep;
use warpui_core::{async_assert, async_assert_eq};

use super::{Builder, new_builder};
use crate::util::get_input_buffer;

pub fn test_input_syncing_is_off_by_default() -> Builder {
    new_builder()
        .with_step(wait_until_bootstrapped_single_pane_for_tab(0))
        .with_step(
            new_step_with_default_assertions("create one additional pane")
                .with_keystrokes(&[cmd_or_ctrl_shift("d")]),
        )
        .with_step(wait_until_bootstrapped_pane(0, 1))
        .with_step(
            new_step_with_default_assertions(
                "type something into pane 2 and check both pane contents",
            )
            .with_keystrokes(&["b"])
            .add_named_assertion("Check that pane 1 is still empty", |app, window_id| {
                let input1 = get_input_buffer(app, window_id, 0, 0);

                async_assert!(
                    input1.is_empty(),
                    "pane 1 should be empty but it contains {}",
                    input1
                )
            })
            .add_named_assertion(
                "Check that pane 2 has the correct contents",
                |app, window_id| {
                    let input2 = get_input_buffer(app, window_id, 0, 1);

                    async_assert!(
                        input2 == "b",
                        "pane 2 should contain 'b' but it contains {}",
                        input2
                    )
                },
            ),
        )
}

pub fn test_can_sync_input_editor_text_in_tab() -> Builder {
    new_builder()
        .with_step(wait_until_bootstrapped_single_pane_for_tab(0))
        .with_step(
            new_step_with_default_assertions("create one additional pane")
                .with_keystrokes(&[cmd_or_ctrl_shift("d")]),
        )
        .with_step(wait_until_bootstrapped_pane(0, 1))
        .with_step(
            new_step_with_default_assertions("turn syncing on in tab").with_action(
                move |app, _, _| {
                    let window_id =
                        app.read(|ctx| ctx.windows().active_window().expect("no active window"));
                    let workspace_view_id = workspace_view(app, window_id).id();

                    app.dispatch_typed_action(
                        window_id,
                        &[workspace_view_id],
                        &WorkspaceAction::ToggleSyncTerminalInputsInTab,
                    );
                },
            ),
        )
        .with_step(
            new_step_with_default_assertions(
                "type something into pane 2 and check pane 1 and 2 contents",
            )
            .with_keystrokes(&["b"])
            .add_named_assertion(
                "check that pane 1 and 2 have the same contents",
                |app, window_id| {
                    let input1 = get_input_buffer(app, window_id, 0, 0);
                    let input2 = get_input_buffer(app, window_id, 0, 1);

                    async_assert!(
                        input1 == "b" && input2 == "b",
                        "Both panes should contain 'b', pane 1: '{input1}', pane 2: '{input2}'"
                    )
                },
            ),
        )
}

pub fn test_can_run_command_in_synced_panes_in_tab() -> Builder {
    let command = "echo typedInPane2";
    let expected_output = "typedInPane2";

    new_builder()
        .with_step(wait_until_bootstrapped_single_pane_for_tab(0))
        .with_step(
            new_step_with_default_assertions("create one additional pane")
                .with_keystrokes(&[cmd_or_ctrl_shift("d")]),
        )
        .with_step(wait_until_bootstrapped_pane(0, 1))
        .with_step(
            new_step_with_default_assertions("turn syncing on in tab").with_action(
                move |app, _, _| {
                    let window_id =
                        app.read(|ctx| ctx.windows().active_window().expect("no active window"));
                    let workspace_view_id = workspace_view(app, window_id).id();

                    app.dispatch_typed_action(
                        window_id,
                        &[workspace_view_id],
                        &WorkspaceAction::ToggleSyncTerminalInputsInTab,
                    );
                },
            ),
        )
        .with_step(
            execute_command(
                0,
                0,
                command.to_owned(),
                ExpectedExitStatus::Success,
                expected_output,
            )
            .add_named_assertion(
                "assert that the same command ran in pane 0",
                assert_command_executed(0, 1, command.to_owned()),
            ),
        )
}

/// The long-running command of [`test_synced_panes_long_running_commands`]. It leaves a file for
/// each pane that runs it, once it is running. The shell reports that a command starts (the
/// preexec hook) before the command does: PowerShell sends it from its line-editor wrapper, and
/// the terminal settings of the line editor are changed again after that. Text typed in between
/// is lost, so the test types only when both panes have a running script.
const HANG_SCRIPT: &str = "#!/bin/sh\ntouch \"running.$$\"\nexec sleep 1000000\n";

fn running_scripts(dir: &Path) -> usize {
    std::fs::read_dir(dir)
        .map(|entries| {
            entries
                .filter_map(Result::ok)
                .filter(|entry| entry.file_name().to_string_lossy().starts_with("running."))
                .count()
        })
        .unwrap_or(0)
}

pub fn test_synced_panes_long_running_commands() -> Builder {
    let test_dir = Arc::new(OnceLock::new());
    let test_dir_for_setup = test_dir.clone();
    new_builder()
        .with_setup(move |utils| {
            let dir = utils.test_dir();
            OpenOptions::new()
                .create_new(true)
                .write(true)
                .mode(0o755)
                .open(dir.join("hang.sh"))
                .expect("could not create the script")
                .write_all(HANG_SCRIPT.as_bytes())
                .expect("could not write the script");
            test_dir_for_setup
                .set(dir)
                .expect("the test directory is set once");
        })
        .with_step(wait_until_bootstrapped_single_pane_for_tab(0))
        .with_step(
            new_step_with_default_assertions("create one additional pane")
                .with_keystrokes(&[cmd_or_ctrl_shift("d")]),
        )
        .with_step(wait_until_bootstrapped_pane(0, 1))
        .with_step(
            new_step_with_default_assertions("turn syncing on in tab").with_action(
                move |app, _, _| {
                    let window_id =
                        app.read(|ctx| ctx.windows().active_window().expect("no active window"));
                    let workspace_view_id = workspace_view(app, window_id).id();

                    app.dispatch_typed_action(
                        window_id,
                        &[workspace_view_id],
                        &WorkspaceAction::ToggleSyncTerminalInputsInTab,
                    );
                },
            ),
        )
        .with_step(
            TestStep::new("Execute a long-running script in both panes")
                .with_typed_characters(&["./hang.sh"])
                .with_keystrokes(&["enter"])
                .add_named_assertion(
                    "check that the script ran in pane 0",
                    assert_long_running_block_executing(true, 0, 0),
                )
                .add_named_assertion(
                    "check that the script ran in pane 1",
                    assert_long_running_block_executing(true, 0, 1),
                )
                .add_named_assertion("check that both scripts are running", move |_, _| {
                    let running = running_scripts(test_dir.get().expect("set by the setup"));
                    async_assert_eq!(running, 2, "scripts that are running")
                }),
        )
        .with_step(
            TestStep::new("Send text to both panes")
                .with_typed_characters(&["foo"])
                .add_named_assertion(
                    "check that foo was sent to pane 0",
                    assert_active_block_output("foo", 0, 0),
                )
                .add_named_assertion(
                    "check that foo was sent to pane 1",
                    assert_active_block_output("foo", 0, 1),
                ),
        )
        .with_step(
            TestStep::new("Exit the script in both panes")
                .with_keystrokes(&["ctrl-c"])
                .add_named_assertion(
                    "check that no command is running in pane 0",
                    assert_no_block_executing(0, 0),
                )
                .add_named_assertion(
                    "check that no command is running in pane 1",
                    assert_no_block_executing(0, 1),
                ),
        )
}

/// Tests that as you use synced inputs and terminals switch between
/// alt-screens and the block-list, the correct terminal view maintains focus.
pub fn test_synced_inputs_terminal_mode_change_view_focus() -> Builder {
    let mut builder = new_builder().with_step(wait_until_bootstrapped_single_pane_for_tab(0));

    for i in 1..=3 {
        builder = builder
            .with_step(
                new_step_with_default_assertions(format!("create pane {i} in tab 0").as_str())
                    .with_keystrokes(&[cmd_or_ctrl_shift("d")]),
            )
            .with_step(wait_until_bootstrapped_pane(0, i));
    }

    builder = builder.with_step(
        new_step_with_default_assertions("create 2nd tab")
            .with_keystrokes(&[cmd_or_ctrl_shift("t")]),
    );

    for i in 1..=3 {
        builder = builder
            .with_step(
                new_step_with_default_assertions(format!("create pane {i} in tab 1").as_str())
                    .with_keystrokes(&[cmd_or_ctrl_shift("d")]),
            )
            .with_step(wait_until_bootstrapped_pane(1, i));
    }

    builder = builder.with_step(
        new_step_with_default_assertions("turn syncing on across all tabs").with_action(
            move |app, _, _| {
                let window_id =
                    app.read(|ctx| ctx.windows().active_window().expect("no active window"));
                let workspace_view_id = workspace_view(app, window_id).id();

                app.dispatch_typed_action(
                    window_id,
                    &[workspace_view_id],
                    &WorkspaceAction::ToggleSyncAllTerminalInputsInAllTabs,
                );
            },
        ),
    );

    let exit_vim_step = TestStep::new("Close vim")
        .with_keystrokes(&["escape"])
        .with_typed_characters(&[":q!"])
        .with_keystrokes(&["enter"]);

    let vim_steps = run_alt_grid_program(
        "vim",
        1,
        3,
        exit_vim_step,
        vec![
            TestStep::new("While vim is running, check focused terminal").add_named_assertion(
                "tab 1 terminal 3 is focused",
                |app, window_id| {
                    let terminal_view_id = terminal_view(app, window_id, 1, 3).id();
                    app.update(|app_ctx| {
                        async_assert_eq!(
                            app_ctx.check_view_or_child_focused(window_id, &terminal_view_id),
                            true
                        )
                    })
                },
            ),
        ],
    );

    builder = builder.with_steps(vim_steps);

    builder = builder.with_step(
        TestStep::new("check focused terminal after exiting vim").add_named_assertion(
            "tab 1 terminal 3 is focused",
            |app, window_id| {
                let terminal_view_id = terminal_view(app, window_id, 1, 3).id();
                app.update(|app_ctx| {
                    async_assert_eq!(
                        app_ctx.check_view_or_child_focused(window_id, &terminal_view_id),
                        true
                    )
                })
            },
        ),
    );

    builder
}
