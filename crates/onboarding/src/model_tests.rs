use warp_core::telemetry::testing::MockTelemetryContextProvider;
use warpui_core::{App, ModelHandle};

use crate::model::{OnboardingStateModel, OnboardingStep};

fn add_model(app: &mut App) -> ModelHandle<OnboardingStateModel> {
    app.update(MockTelemetryContextProvider::register);
    app.add_model(|_| OnboardingStateModel::new())
}

fn step(app: &App, model: &ModelHandle<OnboardingStateModel>) -> OnboardingStep {
    model.read(app, |model, _| model.step())
}

#[test]
fn path_is_linear_and_reversible() {
    App::test((), |mut app| async move {
        let model = add_model(&mut app);
        assert_eq!(step(&app, &model), OnboardingStep::Intro);

        for expected in [
            OnboardingStep::Customize,
            OnboardingStep::ThirdParty,
            OnboardingStep::ThemePicker,
        ] {
            model.update(&mut app, |model, ctx| model.next(ctx));
            assert_eq!(step(&app, &model), expected);
        }

        // The last slide completes onboarding instead of advancing.
        model.update(&mut app, |model, ctx| model.next(ctx));
        assert_eq!(step(&app, &model), OnboardingStep::ThemePicker);

        for expected in [
            OnboardingStep::ThirdParty,
            OnboardingStep::Customize,
            OnboardingStep::Intro,
        ] {
            model.update(&mut app, |model, ctx| model.back(ctx));
            assert_eq!(step(&app, &model), expected);
        }

        model.update(&mut app, |model, ctx| model.back(ctx));
        assert_eq!(step(&app, &model), OnboardingStep::Intro);
    });
}

#[test]
fn progress_uses_three_dots() {
    App::test((), |mut app| async move {
        let model = add_model(&mut app);
        let mut positions = Vec::new();
        for _ in 0..3 {
            model.update(&mut app, |model, ctx| model.next(ctx));
            positions.push(model.read(&app, |model, _| model.progress()));
        }
        assert_eq!(positions, vec![(0, 3), (1, 3), (2, 3)]);
    });
}

#[test]
fn defaults_enable_the_cli_agent_toolbar_and_notifications_only() {
    App::test((), |mut app| async move {
        let model = add_model(&mut app);
        let settings = model.read(&app, |model, _| model.settings());
        assert!(settings.cli_agent_toolbar_enabled);
        assert!(settings.show_agent_notifications);
        let ui = settings.ui_customization;
        assert!(!ui.use_vertical_tabs);
        assert!(!ui.show_code_review_button);
        assert!(!ui.tools_panel_enabled());
    });
}

#[test]
fn tools_panel_toggle_sets_both_sub_settings() {
    App::test((), |mut app| async move {
        let model = add_model(&mut app);
        model.update(&mut app, |model, ctx| {
            model.set_tools_panel_enabled(true, ctx)
        });
        let ui = model.read(&app, |model, _| model.ui_customization().clone());
        assert!(ui.show_project_explorer && ui.show_global_search);
        assert!(ui.tools_panel_enabled());

        model.update(&mut app, |model, ctx| {
            model.set_show_global_search(false, ctx)
        });
        let ui = model.read(&app, |model, _| model.ui_customization().clone());
        assert!(ui.tools_panel_enabled());

        model.update(&mut app, |model, ctx| {
            model.set_show_project_explorer(false, ctx)
        });
        let ui = model.read(&app, |model, _| model.ui_customization().clone());
        assert!(!ui.tools_panel_enabled());
    });
}
