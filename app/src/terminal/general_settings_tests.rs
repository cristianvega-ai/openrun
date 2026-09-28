use std::collections::HashSet;

use settings::Setting as _;
use warpui_extras::user_preferences::UserPreferences as _;
use warpui_extras::user_preferences::in_memory::InMemoryPreferences;

use super::WelcomeTipsFeaturesUsed;
use crate::resource_center::{Tip, TipAction, TipHint};

#[test]
fn welcome_tips_used_survive_a_stored_tip_that_no_longer_exists() {
    let preferences = InMemoryPreferences::default();
    preferences
        .write_value(
            WelcomeTipsFeaturesUsed::storage_key(),
            r#"[{"Action":"WarpAI"},{"Action":"SplitPane"},{"Action":"AiCommandSearch"},{"Hint":"CreateBlock"}]"#
                .to_owned(),
        )
        .expect("preferences should accept the value");

    let used = WelcomeTipsFeaturesUsed::read_from_preferences(&preferences)
        .expect("removed tips must not discard the rest of the stored tips");

    assert_eq!(
        used.0,
        HashSet::from([
            Tip::Action(TipAction::SplitPane),
            Tip::Hint(TipHint::CreateBlock),
        ])
    );
}
