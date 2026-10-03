use std::fs::OpenOptions;
use std::io::Write as _;
use std::os::unix::fs::OpenOptionsExt as _;

use warp::integration_testing::step::new_step_with_default_assertions;
use warp::integration_testing::terminal::util::current_shell_starter_and_version;
use warp::integration_testing::terminal::{
    assert_active_block_output_for_single_terminal_in_tab, assert_input_editor_contents,
    assert_long_running_block_executing_for_single_terminal_in_tab,
    assert_no_visible_background_blocks, wait_until_bootstrapped_single_pane_for_tab,
};
use warp::integration_testing::view_getters::single_terminal_view_for_tab;
use warp::terminal::model::terminal_model::BlockIndex;
use warp::terminal::shell::{Shell, ShellType};
use warpui_core::integration::{TestSetupUtils, TestStep};
use warpui_core::{async_assert, async_assert_eq};

use super::{Builder, new_builder};

/// The script that stands in for a long-running command. It runs until [`release_hold`] creates
/// its release file, so a test decides when the command ends instead of racing a `sleep`.
const HOLD_COMMAND: &str = "./hold.sh";
const HOLD_RELEASE_FILE: &str = "hold.release";
/// The file the script creates as soon as it runs. By then the shell has handed the terminal over
/// to the command: fish reports the command to Warp (the preexec hook) before it switches the
/// terminal from its own line editing mode, which does not echo, to the one external commands
/// get, so text typed in that gap is never echoed.
const HOLD_STARTED_FILE: &str = "hold.started";

/// Writes [`HOLD_COMMAND`] into the test directory.
fn write_hold_script(utils: &mut TestSetupUtils) {
    let dir = utils.test_dir();
    let script = format!(
        "#!/bin/sh\n: > '{}'\nwhile [ ! -e '{}' ]; do sleep 0.05; done\n",
        dir.join(HOLD_STARTED_FILE).display(),
        dir.join(HOLD_RELEASE_FILE).display()
    );
    OpenOptions::new()
        .create_new(true)
        .write(true)
        .mode(0o755)
        .open(dir.join("hold.sh"))
        .expect("could not create the hold script")
        .write_all(script.as_bytes())
        .expect("could not write the hold script");
}

/// Ends the command started with [`HOLD_COMMAND`].
fn release_hold(utils: &mut TestSetupUtils) {
    std::fs::write(utils.test_dir().join(HOLD_RELEASE_FILE), "").expect("could not release hold");
}

fn start_hold_command() -> TestStep {
    TestStep::new("Start the long-running command")
        .with_typed_characters(&[HOLD_COMMAND])
        .with_keystrokes(&["enter"])
        .add_assertion(assert_long_running_block_executing_for_single_terminal_in_tab(true, 0))
        .add_named_assertion("the command is running", |_app, _window_id| {
            let home = std::env::var("HOME")
                .expect("HOME is set for the duration of the integration test");
            async_assert!(
                std::path::Path::new(&home).join(HOLD_STARTED_FILE).exists(),
                "expected the hold script to have started"
            )
        })
}

pub fn test_typeahead() -> Builder {
    new_builder()
        .with_setup(write_hold_script)
        .with_step(wait_until_bootstrapped_single_pane_for_tab(0))
        .with_step(start_hold_command())
        .with_step(
            TestStep::new("Enter text to long running command")
                .with_input_string("foo", None)
                .add_assertion(
                    assert_long_running_block_executing_for_single_terminal_in_tab(true, 0),
                )
                .add_assertion(assert_active_block_output_for_single_terminal_in_tab(
                    "foo", 0,
                )),
        )
        .with_step(
            new_step_with_default_assertions("Input box should have typeahead text")
                .with_setup(release_hold)
                .add_assertion(assert_input_editor_contents(0, "foo"))
                .add_named_assertion(
                    "No typeahead duplicated in background block",
                    assert_no_visible_background_blocks(0, 0),
                ),
        )
}

/// The text the terminal echoes for the ESC-i keybinding that asks the shell to report its input
/// buffer.
const ECHOED_INPUT_REPORTING_KEYBINDING: &str = "^[i";

/// Checks a typeahead command ran as typed.
///
/// Warp writes ESC-i to the pty when a prompt appears. Typeahead lines are already queued in the
/// pty, so the shell can still be between the prompt hook and its line editor, with the terminal
/// in cooked mode, when ESC-i arrives. The terminal then echoes it as the two characters `^[i`
/// in front of the command that the line editor reads next (`^[isleep 1`), and the line editor
/// later receives the ESC-i itself and reports the buffer. Whether that happens depends on how
/// fast the shell and the app are relative to each other: on a loaded CI runner it was seen on
/// seven attempts in a row. zsh, which redraws the rest of the pending input with the line it
/// runs, can also leave the typeahead lines that follow in the command text (`true`, then
/// `sleep 1`, `pwd` and `ls -l` on later lines). Neither changes which command runs, so the
/// first line, without the echoed `^[i`, must be the expected command and the block must have
/// succeeded (an ESC-i that reached the command line as text would turn `sleep 1` into a failing
/// command). Any other command text fails the test.
macro_rules! check_command {
    ($block:expr, $expected:expr) => {
        let block = $block;
        let command = block.command_to_string();
        let without_echo = command.replace(ECHOED_INPUT_REPORTING_KEYBINDING, "");
        let first_line = without_echo.lines().next().unwrap_or_default().trim();
        if first_line == $expected {
            assert!(
                !block.has_failed(),
                "typeahead command `{first_line}` failed: exit code {:?}",
                block.exit_code()
            );
        } else {
            assert_eq!(command, $expected);
        }
    };
}

/// Tests that the shell reports its input buffer to the Warp typeahead model after
/// a long-running command completes.
pub fn test_input_reporting_posix_shells() -> Builder {
    // When the shell can report its input buffer, we can handle typeahead with
    // line editing. When matching user input ourselves (only on pre-4.0 bash),
    // we do not support line edits.
    let (starter, version) = current_shell_starter_and_version();
    let shell = Shell::new(
        starter.shell_type(),
        Some(version),
        None,
        Default::default(),
        None,
    );
    let supports_line_editing = shell.input_reporting_sequence().is_some();

    let mut input_step = TestStep::new("Enter text to long-running command")
        .with_input_string("true", Some(&["enter"]))
        // Test behavior when one of the typeahead commands is itself long-running.
        .with_input_string("sleep 1", Some(&["enter"]))
        .add_assertion(assert_long_running_block_executing_for_single_terminal_in_tab(true, 0));

    if supports_line_editing {
        // Test that we correctly handle line edits on both submitted lines and typeahead.
        input_step = input_step
            .with_keystrokes(&["p", "w", "f", "backspace", "d", "enter"])
            .with_keystrokes(&["l", "s", " ", "-", "a", "backspace", "l"]);
    } else {
        input_step = input_step
            .with_input_string("pwd", Some(&["enter"]))
            // This is the input we expect as typeahead.
            .with_input_string("ls -l", None);
    }

    new_builder()
        .set_should_run_test(move || starter.shell_type() != ShellType::PowerShell)
        .with_setup(write_hold_script)
        .with_step(wait_until_bootstrapped_single_pane_for_tab(0))
        .with_step(start_hold_command())
        .with_step(input_step)
        .with_step(
            new_step_with_default_assertions("Input should be reported to the terminal")
                .with_setup(release_hold)
                .add_named_assertion(
                    "Typeahead is in input editor",
                    assert_input_editor_contents(0, "ls -l"),
                )
                .add_named_assertion("Intermediate commands ran", |app, window_id| {
                    let terminal_view = single_terminal_view_for_tab(app, window_id, 0);
                    terminal_view.read(app, |view, _| {
                        let model = view.model.lock();
                        let blocks = model.block_list();

                        let start_index = blocks
                            .first_non_hidden_block_by_index()
                            .expect("Block should exist");

                        let hold_block = blocks.block_at(start_index).expect("Block should exist");
                        check_command!(hold_block, HOLD_COMMAND);

                        let true_block = blocks
                            .block_at(start_index + BlockIndex::from(1))
                            .expect("Block should exist");
                        assert!(!true_block.is_background());
                        check_command!(true_block, "true");

                        let sleep_1_block = blocks
                            .block_at(start_index + BlockIndex::from(2))
                            .expect("Block should exist");
                        assert!(!sleep_1_block.is_background());
                        check_command!(sleep_1_block, "sleep 1");

                        let pwd_block = blocks
                            .block_at(start_index + BlockIndex::from(3))
                            .expect("Block should exist");
                        assert!(!pwd_block.is_background());
                        check_command!(pwd_block, "pwd");

                        // On shells that support input reporting, there will be
                        // an empty block that formerly held echoed typeahead. On
                        // shells using input matching, the typeahead block is never
                        // created.
                        let next_block = blocks
                            .block_at(start_index + BlockIndex::from(4))
                            .expect("Block should exist");
                        if next_block.is_background() {
                            async_assert!(next_block.is_empty())
                        } else {
                            async_assert_eq!(next_block.index(), blocks.active_block_index())
                        }
                    })
                }),
        )
}

/// PowerShell has different behavior for typeahead in that it ignores newlines.
pub fn test_input_reporting_powershell() -> Builder {
    new_builder()
        .set_should_run_test(|| {
            let (starter, _) = current_shell_starter_and_version();
            starter.shell_type() == ShellType::PowerShell
        })
        .with_setup(write_hold_script)
        .with_step(wait_until_bootstrapped_single_pane_for_tab(0))
        .with_step(start_hold_command())
        .with_step(
            TestStep::new("Enter text to long-running command")
                .with_keystrokes(&["enter"])
                .with_input_string("true", Some(&["enter"]))
                .with_input_string("sleep 1", Some(&["enter"]))
                .add_assertion(
                    assert_long_running_block_executing_for_single_terminal_in_tab(true, 0),
                ),
        )
        .with_step(
            new_step_with_default_assertions("Input should be reported to the terminal")
                .with_setup(release_hold)
                .add_named_assertion(
                    "Typeahead is in input editor",
                    assert_input_editor_contents(0, "truesleep 1"),
                ),
        )
}

/// This tests UNIX-specific signal handling.
pub fn test_background_output() -> Builder {
    use std::fs::OpenOptions;
    use std::io::Write;
    use std::os::unix::prelude::OpenOptionsExt;

    use regex::Regex;
    use warp::integration_testing::block::assert_background_output;
    use warp::integration_testing::terminal::execute_command_for_single_terminal_in_tab;
    use warp::integration_testing::terminal::util::ExpectedExitStatus;

    let (starter, _) = current_shell_starter_and_version();
    let (spawn_command, kill_command) = match starter.shell_type() {
        ShellType::PowerShell => (
            "$process = Start-Process -FilePath './delayed_output.py' -PassThru",
            "kill -SIGUSR1 $process.Id && echo foreground",
        ),
        _ => (
            "./delayed_output.py &",
            "kill -SIGUSR1 %1 && echo foreground",
        ),
    };
    new_builder()
        .with_setup(|utils| {
            let dir = utils.test_dir();
            // Use a Python script because fish can't run functions in the background
            // https://github.com/fish-shell/fish-shell/issues/238
            let script_path = dir.join("delayed_output.py");

            OpenOptions::new()
                .create_new(true)
                .write(true)
                .mode(0o755)
                .open(script_path)
                .expect("could not create script")
                .write_all(
                    br#"#!/usr/bin/env python3
import os
import signal
import time

# Wait for a SIGUSR1 signal, after which we should print out
# more text.
def handler(signo, cur_frame):
  time.sleep(1)
  print("Output 2")
  print("Output 3")
signal.signal(signal.SIGUSR1, handler)

# Print the first line only once the test has seen the command that started this script finish,
# so that the line is background output at the prompt and not part of that command's output.
go = os.path.join(os.path.dirname(os.path.abspath(__file__)), "go")
while not os.path.exists(go):
  time.sleep(0.02)
print("Output 1")
time.sleep(100)
"#,
                )
                .expect("could not write Python script");
        })
        .with_step(wait_until_bootstrapped_single_pane_for_tab(0))
        .with_step(execute_command_for_single_terminal_in_tab(
            0,
            spawn_command.into(),
            ExpectedExitStatus::Success,
            (),
        ))
        .with_step(
            TestStep::new("First line of background output appears")
                .with_setup(|utils| {
                    std::fs::write(utils.test_dir().join("go"), "").expect("could not write file");
                })
                .add_assertion(assert_background_output(0, "Output 1\n")),
        )
        .with_step(execute_command_for_single_terminal_in_tab(
            0,
            // Send the signal to the background process and produce some output.
            kill_command.into(),
            ExpectedExitStatus::Success,
            "foreground",
        ))
        .with_step(
            TestStep::new("Rest of background output appears in a new block").add_assertion(
                assert_background_output(
                    0,
                    // Use a regex because the "job completed" message format is shell-specific.
                    // Depending on timing, the "Output 2" line could be part of the
                    // block for `true`, so it's optional - we expect the next
                    // line to always be in the background block though.
                    Regex::new("^(Output 2\n)?Output 3\n").expect("Regex is valid"),
                ),
            ),
        )
}
