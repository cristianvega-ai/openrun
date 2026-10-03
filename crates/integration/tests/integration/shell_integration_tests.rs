//! Tests that need to run against every supported shell.
//!
//! Add a test to this module if any of the following are true:
//! * It needs to run against every shell.
//! * It needs to run against a _specific_ shell or set of shells.
//!
//! When adding a test to this module, please add a brief comment indicating
//! why it belongs here.

use super::integration_tests;

integration_tests! {
    // Test command execution works.
    test_single_command,
    // Test shell process terminates when session is closed.
    test_add_and_close_session,
    // Test powerlevel10k detection (via bootstrap script logic).
    test_detect_powerlevel10k,
    // Test properties of bootstrap.
    test_bootstrap_with_no_script_execution_block,
    test_rc_files_only_sourced_once_during_bootstrapping,
    // Test ctrl-c terminates long-running commands.
    test_ctrl_c,
    // Test copying a block's command gives us the expected command string.
    test_open_context_menu_and_execute_command,
    // Test we get the right metadata from a bootstrapped shell.
    test_block_metadata_received,
    // Test typeahead behavior.
    test_typeahead,
    // Test input reporting behavior.
    test_input_reporting_posix_shells,
    // Test background output behavior.
    test_background_output,
    // Must run against zsh.
    test_zshrc_keypress,
    // Tests bash- and zsh-specific behavior.
    test_alias_guards_on_ps1_set,
    // Tests prompt information from shell.
    test_ps1_value_not_null_or_exit,
    // Tests zsh-specific behavior.
    test_auto_title,
    // The tab title right after the bootstrap, in every shell.
    test_tab_title_after_bootstrap,
    // Tests zsh-specific behavior.
    test_warp_auto_title_disabled,
    // Tests zsh-specific behavior.
    test_warp_honors_user_title_zsh,
    // Tests OSC 7 updates the block's working directory on bash and zsh.
    test_osc7_updates_current_working_directory,
    // Tests shell-specific "autocd" behavior.
    test_completions_with_autocd,
    // Tests bootstrap reports completable executables.
    test_executable_completions,
    // Tests bootstrap reports completable functions.
    test_function_completions,
    // Tests bootstrap reports completable builtins.
    test_builtin_completions,
    // Tests bootstrap reports completable keywords.
    test_keyword_completions,
    // Native shell completions, driven against the user's real shell.
    test_native_shell_completions_menu,
    test_command_runs_cleanly_after_native_shell_completion,
    test_native_shell_completions_used_when_no_bundled_spec,
    test_native_shell_completions_skipped_when_a_bundled_spec_answers,
    test_native_shell_completions_reach_a_spec_command_native_only,
    // Tests initial working directory behavior.
    test_create_session_with_new_tab_while_bootstrapping,
    // Tests initial working directory behavior.
    test_start_shell_in_deleted_directory,
    // Tests prompt information (sent during precmd).
    test_git_prompt,
    // Tests shell initialization.
    test_terminal_announces_capabilities_to_shell,
    // Test runs only on zsh.
    test_color_overrides_in_prompt_dont_crash,
    // Tests zsh-specific behavior with nounset option.
    test_zsh_bootstraps_with_nounset_option,
    test_zsh_cursor_mode_vi_bindings_do_not_corrupt_commands,

    // Tests of custom prompt behavior.
    test_copy_prompt_from_block_honor_ps1_enabled,
    test_copy_prompt_from_input_honor_ps1_enabled,
    test_copy_block_command_and_output_honor_ps1_disabled,
    test_copy_block_command_and_output_honor_ps1_enabled,
    // Tests zsh-specific right-prompt behavior in Warp prompt mode.
    test_warp_prompt_unsets_zsh_rprompt,

    // Disabled due to flakiness on CI.
    #[ignore = "ENG-171: right prompt clipboard assertion is flaky on CI"]
    test_copy_rprompt_from_input_honor_ps1_enabled,

    // Tests of subshell logic from bootstrap script.
    test_can_bootstrap_local_bash_subshell,
    test_can_bootstrap_local_zsh_subshell,
    test_can_bootstrap_local_fish_subshell,

    // Tests loading command history from shell histfile.
    test_command_search_loads_history,
    test_histfile_left_joined_with_persisted_history,

    // Tests default prompt behavior.
    test_context_chips_prompt_at_bootstrap,

    // CTRL-D tests.
    test_ctrl_d_eot,
    test_ctrl_d_exit,
    test_ctrl_d_handled_by_read_during_bootstrapping,
    test_ctrl_d_during_bootstrapping_exits_shell_upon_completion,

    test_git_prompt_chips,
}

/// Tests of behavior that exists in one shell only. They can't run in the zsh job, and a test that
/// is skipped because the shell is wrong is not a pass, so each one lives in a module named after
/// its shell, is ignored by default, and runs in the CI job for that shell:
///
/// ```text
/// WARP_SHELL_PATH=<bash 5.1 or newer> cargo nextest run -p integration \
///     --run-ignored only -E 'test(~shell_integration_tests::bash_only::)'
/// ```
mod bash_only {
    use crate::integration_tests;

    integration_tests! {
        // Test bash handling of a custom PS1 (needs the bash the job installs).
        #[ignore = "ENG-233: bash only: run with WARP_SHELL_PATH=<bash> and --run-ignored"]
        test_custom_ps1_expansion_bash,
        #[ignore = "ENG-233: bash only: run with WARP_SHELL_PATH=<bash> and --run-ignored"]
        test_bash_honor_ps1_expands_dynamic_prompt_once,
        // Tests bash-specific behavior of the tab title.
        #[ignore = "ENG-233: bash only: run with WARP_SHELL_PATH=<bash> and --run-ignored"]
        test_warp_honors_user_title_bash,
        // Tests bash-specific history behavior.
        #[ignore = "ENG-233: bash only: run with WARP_SHELL_PATH=<bash> and --run-ignored"]
        test_histcontrol_env_var,
        // Output of the shell after a command finished is background output, not the command's.
        #[ignore = "ENG-233: bash only: run with WARP_SHELL_PATH=<bash> and --run-ignored"]
        test_exit_status_ignores_stray_terminal_output_bash,
        // Tests PROMPT_COMMAND arrays, which need bash 5.1 or newer.
        #[ignore = "ENG-233: bash 5.1 or newer only: run with WARP_SHELL_PATH=<bash> and --run-ignored"]
        test_bash_bootstraps_with_prompt_command_array,
        #[ignore = "ENG-233: bash 5.1 or newer only: run with WARP_SHELL_PATH=<bash> and --run-ignored"]
        test_bash_bootstraps_with_prompt_command_array_that_sets_ps1,
    }
}

/// PowerShell 7 (`pwsh`) tests; see [`bash_only`] for how they run.
///
/// ```text
/// WARP_SHELL_PATH=$(command -v pwsh) cargo nextest run -p integration \
///     --run-ignored only -E 'test(~shell_integration_tests::pwsh_only::)'
/// ```
mod pwsh_only {
    use crate::integration_tests;

    integration_tests! {
        // PowerShell ignores newlines in typeahead.
        #[ignore = "ENG-233: PowerShell only: run with WARP_SHELL_PATH=<pwsh> and --run-ignored"]
        test_input_reporting_powershell,
        // PSReadLine's vi edit mode.
        #[ignore = "ENG-233: PowerShell only: run with WARP_SHELL_PATH=<pwsh> and --run-ignored"]
        test_pwsh_vi_edit_mode_does_not_corrupt_commands,
        // Completions of member access are PowerShell's own.
        #[ignore = "ENG-233: PowerShell only: run with WARP_SHELL_PATH=<pwsh> and --run-ignored"]
        test_native_shell_completions_powershell_member_access,
    }
}
