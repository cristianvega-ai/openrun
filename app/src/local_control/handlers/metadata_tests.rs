use super::{SurfaceDestination, surface_unavailable_reason};

#[test]
fn vertical_tabs_surface_reports_unavailable_when_setting_is_off() {
    warpui::App::test((), |mut app| async move {
        crate::test_util::settings::initialize_settings_for_tests(&mut app);
        assert_eq!(
            app.update(|ctx| { surface_unavailable_reason(SurfaceDestination::VerticalTabs, ctx) }),
            Some("vertical tabs are unavailable or disabled")
        );
    });
}
