use super::LSPServerType;

#[test]
fn every_server_has_a_manual_install_hint() {
    for server_type in LSPServerType::all() {
        assert!(
            !server_type.manual_install_hint().trim().is_empty(),
            "{} has no manual install hint",
            server_type.binary_name()
        );
    }
}

#[test]
fn node_based_servers_have_a_node_install_hint() {
    for server_type in LSPServerType::all().filter(LSPServerType::requires_node_runtime) {
        assert!(
            server_type.manual_install_hint().starts_with("npm "),
            "{} runs on Node.js but its hint does not use npm",
            server_type.binary_name()
        );
    }
    assert!(!node_runtime::manual_install_hint().trim().is_empty());
}
