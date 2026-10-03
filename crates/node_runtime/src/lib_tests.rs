use super::{DownloadPermit, manual_install_hint};

#[test]
fn download_permit_is_only_granted_when_the_setting_is_on() {
    assert!(DownloadPermit::from_setting(false).is_none());
    assert!(DownloadPermit::from_setting(true).is_some());
}

#[test]
fn manual_install_hint_is_not_empty() {
    assert!(!manual_install_hint().trim().is_empty());
}

#[test]
fn manual_install_hint_names_the_minimum_node_version() {
    let major = super::MIN_NODE_VERSION.major.to_string();
    assert!(manual_install_hint().contains(&major));
}
