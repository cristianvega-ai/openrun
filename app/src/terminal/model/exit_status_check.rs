//! The exit-status check of the command steps of the integration tests (`execute_command` and its
//! variants).
//!
//! The check reads the block of the command that ran. It finds that block as the other assertions
//! of those steps do (the last command block, which leaves out background blocks), and it lists
//! the blocks that were there when it fails. It used to read the last block that is not hidden,
//! which also counts a background block: output that reaches the terminal after the command
//! finished and before the next prompt, such as a warning of the shell itself, becomes one, and
//! its exit status is the default 0. With such a block last, the check failed a command that had
//! failed when a failure was expected (`false`, in CI run 37150427042), and it would have passed
//! a command that had failed when success was expected.

use std::fmt::Write as _;

use warp_core::command::ExitCode;
use warpui::integration::AssertionOutcome;

use super::block::Block;
use super::blocks::{BlockFilter, BlockList};

/// Different options for asserting the value of the exit code.
pub enum ExpectedExitStatus {
    /// Checks code == 0
    Success,
    /// Checks code != 0
    Failure,
    /// Checks code == expected
    ExactCode(ExitCode),
    /// Any exit status is considered valid.
    Any,
}

/// How many blocks, counted from the end, a failure message lists.
const BLOCKS_IN_REPORT: usize = 4;

/// The text of the command of `block`, without the `^[i` the tty echoed for the input-reporting
/// key when the command was typed ahead.
pub fn command_text_of(block: &Block) -> String {
    let command = block.command_with_secrets_unobfuscated(false /*include_escape_sequences*/);
    command.trim_end_matches("^[i").trim_end().to_owned()
}

/// Whether `block` is the block of `command`.
pub fn is_block_of_command(block: &Block, command: &str) -> bool {
    command_text_of(block) == command.trim_end()
}

/// Lists the last blocks of the list, one per line, for the message of a failure: the index, the
/// ID, whether the block is a background block, its state, its exit status, its command and the
/// start of its output.
pub fn report_last_blocks(block_list: &BlockList) -> String {
    let blocks = block_list.blocks();
    let first = blocks.len().saturating_sub(BLOCKS_IN_REPORT);
    let mut report = String::new();
    for (index, block) in blocks.iter().enumerate().skip(first) {
        let output = block
            .output_grid()
            .contents_to_string_with_secrets_unobfuscated(
                false, /*include_escape_sequences*/
                None,
            );
        let _ = writeln!(
            report,
            "  block {index}: id={} background={} state={:?} exit_code={} command={:?} output={:?}",
            block.id(),
            block.is_background(),
            block.state(),
            block.exit_code().value(),
            command_text_of(block),
            output.chars().take(200).collect::<String>(),
        );
    }
    report
}

/// Checks the exit status of the last command block against `expected`, after checking that it is
/// the block of `command`.
pub fn check_exit_status_of_last_command(
    block_list: &BlockList,
    command: &str,
    expected: &ExpectedExitStatus,
) -> AssertionOutcome {
    let Some(index) = block_list.last_matching_block_by_index(BlockFilter::commands()) else {
        return AssertionOutcome::failure("No block yet".to_string());
    };
    let block = block_list.block_at(index).expect("Block should exist");
    if !is_block_of_command(block, command) {
        return AssertionOutcome::immediate_failure(format!(
            "The last command block is not the block of {command:?}.\n{}",
            report_last_blocks(block_list)
        ));
    }
    let code = block.exit_code();
    let fails = |expectation: &str| {
        AssertionOutcome::immediate_failure(format!(
            "Expected {expectation}, but the block of {command:?} has exit code {}.\n{}",
            code.value(),
            report_last_blocks(block_list)
        ))
    };
    match expected {
        ExpectedExitStatus::Success if code.value() != 0 => fails("exit code 0"),
        ExpectedExitStatus::Failure if code.value() == 0 => fails("a non-zero exit code"),
        ExpectedExitStatus::ExactCode(exact) if code != *exact => {
            fails(&format!("exit code {}", exact.value()))
        }
        _ => AssertionOutcome::Success,
    }
}
