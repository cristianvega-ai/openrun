use warp_util::local_or_remote_path::LocalOrRemotePath;
pub use warp_util::path::*;

/// Returns the display path of a file location.
///
/// When `abbreviate_home` is true, local paths under the user's home directory
/// are abbreviated with a `~/` prefix.
pub fn display_location_path(path: &LocalOrRemotePath, abbreviate_home: bool) -> String {
    match path {
        LocalOrRemotePath::Local(local_path) if abbreviate_home => dirs::home_dir()
            .and_then(|home| local_path.strip_prefix(&home).ok())
            .map(|relative| format!("~/{}", relative.display()))
            .unwrap_or_else(|| local_path.display().to_string()),
        LocalOrRemotePath::Local(_) | LocalOrRemotePath::Remote(_) => path.display_path(),
    }
}
