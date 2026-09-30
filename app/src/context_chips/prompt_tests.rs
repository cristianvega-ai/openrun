use serde_json::Value;
use settings::Setting as _;
use settings_value::SettingsValue as _;
use warpui::{App, SingletonEntity};

use super::Prompt;
use crate::context_chips::prompt::{PromptConfiguration, PromptSelection};
use crate::context_chips::{ContextChipKind, available_chips};
use crate::settings::WarpPromptSeparator;
use crate::terminal::session_settings::{SavedPrompt, SessionSettings};
use crate::test_util::settings::initialize_settings_for_tests;

fn initialize_app(app: &mut App) {
    initialize_settings_for_tests(app);
}

#[test]
// Legacy prompt configs do not have git diff stats, so it should be added after normalization.
// `did_separate_git_diff_stats` is set to `false`.
fn test_prompt_config_adds_git_diff_stats_for_legacy_config() {
    let config = PromptConfiguration::from_chips(
        [
            ContextChipKind::WorkingDirectory,
            ContextChipKind::ShellGitBranch,
        ],
        false,
        WarpPromptSeparator::None,
    );
    let mut serialized = serde_json::to_value(config).expect("serialize prompt config");

    let Value::Object(ref mut map) = serialized else {
        panic!("expected object");
    };
    map.remove("did_separate_git_diff_stats");

    let legacy_config: PromptConfiguration =
        serde_json::from_value(serialized).expect("deserialize legacy config");
    let normalized = legacy_config.normalize_custom_prompt_config();

    assert_eq!(
        normalized.chip_kinds(),
        vec![
            ContextChipKind::WorkingDirectory,
            ContextChipKind::ShellGitBranch,
            ContextChipKind::GitDiffStats,
        ]
    );
}

#[test]
// Ensure that prompt configs don't re-insert git diff stats if they were explicitly removed.
// `did_separate_git_diff_stats` is set to `true`.
fn test_prompt_config_after_nomalization() {
    let config = PromptConfiguration::from_chips(
        [ContextChipKind::ShellGitBranch],
        false,
        WarpPromptSeparator::None,
    );
    let normalized = config.normalize_custom_prompt_config();

    assert_eq!(
        normalized.chip_kinds(),
        vec![ContextChipKind::ShellGitBranch]
    );
}

fn saved_kinds() -> Vec<ContextChipKind> {
    vec![
        ContextChipKind::WorkingDirectory,
        ContextChipKind::ShellGitBranch,
    ]
}

fn saved_config() -> PromptConfiguration {
    PromptConfiguration::from_chips(saved_kinds(), false, WarpPromptSeparator::None)
}

fn insert_chip_entry(stored: &mut Value, index: usize, entry: Value) {
    stored
        .get_mut("chips")
        .and_then(Value::as_array_mut)
        .expect("chips should be a list")
        .insert(index, entry);
}

#[test]
fn test_prompt_config_skips_removed_chip_kinds_in_settings_file() {
    let mut stored = saved_config().to_file_value();
    insert_chip_entry(
        &mut stored,
        1,
        serde_json::json!({ "chip": "agent_plan_and_todo_list", "config": {} }),
    );

    let config = PromptConfiguration::from_file_value(&stored)
        .expect("a removed chip kind must not discard the whole prompt");
    assert_eq!(config.chip_kinds(), saved_kinds());

    let selection = PromptSelection::from_file_value(&serde_json::json!({
        "custom_chip_selection": stored
    }))
    .expect("a removed chip kind must not discard the prompt selection");
    let PromptSelection::CustomChipSelection(config) = selection else {
        panic!("expected a custom prompt");
    };
    assert_eq!(config.chip_kinds(), saved_kinds());
}

#[test]
fn test_prompt_config_skips_removed_chip_kinds_in_stored_json() {
    let mut stored = serde_json::to_value(saved_config()).expect("serialize prompt config");
    insert_chip_entry(
        &mut stored,
        1,
        serde_json::json!({ "chip": "AgentPlanAndTodoList", "config": {} }),
    );

    let config: PromptConfiguration =
        serde_json::from_value(stored).expect("a removed chip kind must not fail the parse");
    assert_eq!(config.chip_kinds(), saved_kinds());
}

#[test]
fn test_prompt_settings() {
    App::test((), |mut app| async move {
        initialize_app(&mut app);

        let session_settings = SessionSettings::handle(&app);
        let default_prompt = PromptConfiguration::default_prompt();

        let prompt = app.add_singleton_model(Prompt::new);

        // First, the default prompt should be set.
        let current_prompt_chips = prompt.read(&app, |prompt, _| prompt.chip_kinds());
        assert_eq!(current_prompt_chips, default_prompt.chip_kinds());
        session_settings.read(&app, |settings, _| {
            assert_eq!(settings.saved_prompt.to_owned(), PromptSelection::Default)
        });

        // Now, set a new prompt.
        let new_chips = [ContextChipKind::Ssh, ContextChipKind::WorkingDirectory];
        prompt.update(&mut app, |prompt, ctx| {
            prompt
                .update(new_chips.clone(), false, WarpPromptSeparator::None, ctx)
                .expect("Saving prompt failed")
        });

        // The configuration should be updated both in-memory and in settings.
        let new_prompt_chips = prompt.read(&app, |prompt, _| prompt.chip_kinds());
        assert_eq!(
            new_prompt_chips,
            vec![ContextChipKind::Ssh, ContextChipKind::WorkingDirectory]
        );
        session_settings.read(&app, |settings, _| {
            assert_eq!(
                settings.saved_prompt.to_owned(),
                PromptConfiguration::from_chips(new_chips, false, WarpPromptSeparator::None).into()
            );
        });

        // If we reset the prompt, settings are cleared.
        prompt.update(&mut app, |prompt, ctx| {
            prompt.reset(ctx).expect("Saving prompt failed");
        });
        let reset_prompt_chips = prompt.read(&app, |prompt, _| prompt.chip_kinds());
        assert_eq!(reset_prompt_chips, default_prompt.chip_kinds());
        session_settings.read(&app, |settings, _| {
            assert_eq!(settings.saved_prompt.to_owned(), PromptSelection::Default);
        });
    });
}

fn app_with_stored_saved_prompt(app: &mut App, stored: Option<String>) {
    use settings::{PrivatePreferences, PublicPreferences, SettingsManager};
    use warpui_extras::user_preferences::UserPreferences as _;
    use warpui_extras::user_preferences::in_memory::InMemoryPreferences;

    let private = InMemoryPreferences::default();
    if let Some(stored) = stored {
        private
            .write_value(SavedPrompt::storage_key(), stored)
            .expect("write the stored prompt");
    }
    app.update(|ctx| {
        ctx.add_singleton_model(|_| PublicPreferences::new(Box::<InMemoryPreferences>::default()));
        ctx.add_singleton_model(move |_| PrivatePreferences::new(Box::new(private)));
    });
    app.add_singleton_model(|_| SettingsManager::default());
    SessionSettings::register(app);
}

fn stored_saved_prompt(app: &App) -> Option<String> {
    use settings::PrivatePreferences;

    app.read(|ctx| {
        PrivatePreferences::as_ref(ctx)
            .read_value(SavedPrompt::storage_key())
            .expect("read the stored prompt")
    })
}

#[test]
fn an_unset_prompt_setting_resolves_to_the_default_without_the_pr_chip() {
    App::test((), |mut app| async move {
        app_with_stored_saved_prompt(&mut app, None);

        assert_eq!(stored_saved_prompt(&app), None);
        app.read(|ctx| {
            let saved = &SessionSettings::as_ref(ctx).saved_prompt;
            assert!(!saved.is_value_explicitly_set());
            assert_eq!(*saved.value(), PromptSelection::Default);
        });

        let prompt = app.add_singleton_model(Prompt::new);
        let chips = prompt.read(&app, |prompt, _| prompt.chip_kinds());
        assert_eq!(chips, PromptConfiguration::default_prompt().chip_kinds());
        assert!(chips.contains(&ContextChipKind::WorkingDirectory));
        assert!(chips.contains(&ContextChipKind::ShellGitBranch));
        assert!(
            !chips.contains(&ContextChipKind::GithubPullRequest),
            "a fresh install must not run `gh`"
        );
    });
}

#[test]
fn the_pr_chip_stays_available_in_the_prompt_editor() {
    assert!(available_chips().contains(&ContextChipKind::GithubPullRequest));
}

#[test]
fn a_saved_prompt_with_the_pr_chip_keeps_it_after_a_restart() {
    let saved_chips = [
        ContextChipKind::WorkingDirectory,
        ContextChipKind::ShellGitBranch,
        ContextChipKind::GithubPullRequest,
    ];

    let stored = std::rc::Rc::new(std::cell::RefCell::new(None));
    let stored_by_first_run = stored.clone();
    let chips_to_save = saved_chips.clone();
    App::test((), |mut app| async move {
        app_with_stored_saved_prompt(&mut app, None);
        let prompt = app.add_singleton_model(Prompt::new);
        prompt.update(&mut app, |prompt, ctx| {
            prompt
                .update(chips_to_save, false, WarpPromptSeparator::None, ctx)
                .expect("save the prompt");
        });
        *stored_by_first_run.borrow_mut() = stored_saved_prompt(&app);
    });
    let stored = stored
        .borrow_mut()
        .take()
        .expect("the saved prompt must be stored");

    App::test((), |mut app| async move {
        app_with_stored_saved_prompt(&mut app, Some(stored));

        app.read(|ctx| {
            assert!(
                SessionSettings::as_ref(ctx)
                    .saved_prompt
                    .is_value_explicitly_set()
            );
        });
        let prompt = app.add_singleton_model(Prompt::new);
        let chips = prompt.read(&app, |prompt, _| prompt.chip_kinds());
        assert_eq!(chips, saved_chips.to_vec());
    });
}
