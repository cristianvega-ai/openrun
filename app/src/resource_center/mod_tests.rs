use std::collections::HashSet;

use serde_json::json;
use settings_value::{LenientSet, SettingsValue as _};

use super::{Tip, TipAction, TipHint};

#[test]
fn retired_welcome_tips_are_dropped_and_current_tips_survive() {
    let stored = json!([
        {"action": "open_warp_drive"},
        {"action": "changelog"},
        {"action": "command_palette"},
        {"hint": "create_block"},
    ]);

    let tips = LenientSet::<Tip>::from_file_value(&stored).expect("an array parses");

    assert_eq!(
        tips.0,
        HashSet::from([
            Tip::Action(TipAction::CommandPalette),
            Tip::Hint(TipHint::CreateBlock),
        ])
    );
}

#[test]
fn stored_welcome_tips_round_trip() {
    let tips = LenientSet::from(HashSet::from([
        Tip::Action(TipAction::SplitPane),
        Tip::Action(TipAction::Workflows),
        Tip::Hint(TipHint::BlockSelect),
    ]));

    let restored = LenientSet::<Tip>::from_file_value(&tips.to_file_value()).expect("round trip");

    assert_eq!(restored, tips);
}
