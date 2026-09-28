use std::path::PathBuf;

use string_offset::ByteOffset;
use warp_ripgrep::search::{Match as RipgrepMatch, Submatch};
use warp_util::local_or_remote_path::LocalOrRemotePath;

use super::GlobalSearch;
use crate::workspace::view::global_search::GlobalSearchMatch;

fn local_match(
    path: &str,
    line_number: u32,
    line_text: &str,
    submatches: Vec<(usize, usize)>,
) -> Vec<GlobalSearchMatch> {
    let raw = RipgrepMatch {
        file_path: PathBuf::from(path),
        line_number,
        line_text: line_text.to_string(),
        submatches: submatches
            .into_iter()
            .map(|(byte_start, byte_end)| Submatch {
                byte_start: ByteOffset::from(byte_start),
                byte_end: ByteOffset::from(byte_end),
            })
            .collect(),
    };
    GlobalSearch::expand_submatches(GlobalSearch::local_match_to_global(raw))
}

#[test]
fn local_matches_become_local_locations() {
    let results = local_match("/repo/src/main.rs", 7, "fn main() {}", vec![(3, 7)]);

    assert_eq!(results.len(), 1);
    assert_eq!(
        results[0].location,
        LocalOrRemotePath::Local(PathBuf::from("/repo/src/main.rs"))
    );
    assert_eq!(results[0].line_number, 7);
    assert_eq!(results[0].column_num, Some(4));
    assert_eq!(results[0].line_text, "fn main() {}");
}

#[test]
fn local_matches_expand_one_row_per_submatch() {
    let results = local_match("/repo/a.rs", 1, "foo foo", vec![(0, 3), (4, 7)]);

    assert_eq!(results.len(), 2);
    assert!(results.iter().all(|m| m.submatches.len() == 1));
}

#[test]
fn local_match_leading_whitespace_is_trimmed_per_submatch() {
    let results = local_match("/repo/a.rs", 1, "    foo", vec![(4, 7)]);

    assert_eq!(results.len(), 1);
    assert_eq!(results[0].line_text, "foo");
    assert_eq!(results[0].column_num, Some(5));
    assert_eq!(results[0].submatches[0].byte_start.as_usize(), 0);
    assert_eq!(results[0].submatches[0].byte_end.as_usize(), 3);
}

#[test]
fn local_match_column_counts_characters_not_bytes() {
    let results = local_match("/repo/a.rs", 1, "€foo", vec![(3, 6)]);

    assert_eq!(results.len(), 1);
    assert_eq!(results[0].column_num, Some(2));
}
