pub(crate) mod details_action_buttons;

pub(crate) mod cloud_setup_guide_view;
pub(crate) mod telemetry;
pub(crate) mod view;

pub fn init(app: &mut warpui::AppContext) {
    view::init(app);
}
