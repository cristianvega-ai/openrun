use aho_corasick::{AhoCorasick, MatchKind};

lazy_static::lazy_static! {
    /// Matcher for characters which are forbidden in filenames.
    static ref FORBIDDEN_FILENAME_PATTERNS: AhoCorasick = make_forbidden_filenames_matcher();
}

/// This is a helper for [`safe_filename`], which constructs a cached [`AhoCorasick`] matcher to
/// replace forbidden filename characters.
fn make_forbidden_filenames_matcher() -> AhoCorasick {
    // NTFS (Windows) disallows ASCII control characters in path names.
    let ascii_control = 0x00..0x1f;
    // These characters are disallowed by UNIX filesystems, APFS or HFS+ (macOS), or NTFS.
    let forbidden = [b'/', b':', b'#', b'*', b'<', b'>', b'?', b'\\', b'|'];

    let patterns = ascii_control.chain(forbidden).map(|ch| [ch]);
    AhoCorasick::builder()
        .match_kind(MatchKind::LeftmostFirst)
        .build(patterns)
        .expect("Path patterns should compile")
}

/// Replaces characters that are not allowed in a path name. This is _not_ escaping - disallowed
/// characters cannot be escaped in a path.
///
/// See [Comparison of filename limitations](https://en.wikipedia.org/wiki/Filename#Comparison_of_filename_limitations).
pub fn safe_filename(filename: &str) -> String {
    let mut result = String::new();
    FORBIDDEN_FILENAME_PATTERNS.replace_all_with(filename, &mut result, |_, _, dst| {
        // This replaces all forbidden characters with a `_`. We could use the match arguments to
        // replace specific characters with something closer to their original semantics.
        dst.push('_');
        true
    });
    result
}

#[cfg(test)]
#[path = "filename_tests.rs"]
mod tests;
