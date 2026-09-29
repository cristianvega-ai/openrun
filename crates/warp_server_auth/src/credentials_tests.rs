use super::RefreshToken;

#[test]
fn test_refresh_token_urls() {
    let refresh_token = RefreshToken::new("rt".to_string());

    assert_eq!(
        refresh_token.access_token_url("api_key"),
        "https://securetoken.googleapis.com/v1/token?key=api_key"
    );
    assert_eq!(
        refresh_token.access_token_request_body(),
        vec![("grant_type", "refresh_token"), ("refresh_token", "rt")],
    );
    assert_eq!(
        refresh_token.proxy_url("https://staging.warp.dev", "api_key"),
        "https://staging.warp.dev/proxy/token?key=api_key"
    );
}
