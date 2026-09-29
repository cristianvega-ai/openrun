use super::*;

#[test]
fn https_client_reports_a_refused_connection_without_panicking() {
    let client = Client::new();

    let result = futures::executor::block_on(client.get("https://127.0.0.1:1/").send());

    assert!(
        result.is_err(),
        "nothing listens on 127.0.0.1:1, so the request must fail"
    );
}
