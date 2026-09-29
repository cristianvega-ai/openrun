//! Representation of Warp user credentials.
//!
//! The primary representation is [`Credentials`], which is the source of truth for how a user is
//! authenticated to Warp.
//!
//! The short-lived [`AuthToken`] derived from them is included in server requests.
//! When using Firebase, this is an OAuth2 access token.
use chrono::{DateTime, FixedOffset, Local};
use serde::{Deserialize, Serialize};

/// Represents the different ways a user can authenticate with Warp.
#[derive(Clone, Debug)]
pub enum Credentials {
    /// Firebase authentication with ID token and refresh token.
    Firebase(FirebaseAuthTokens),
    /// API key for direct server authentication.
    ApiKey { key: String },
    /// Request-scoped or externally managed bearer token.
    Bearer(String),
    /// Test credentials used in unit tests and integration tests.
    #[cfg(any(test, feature = "integration_tests", feature = "test-util"))]
    Test,
}

impl Credentials {
    /// Returns the Firebase auth tokens if this is a Firebase credential.
    pub fn as_firebase(&self) -> Option<&FirebaseAuthTokens> {
        match self {
            Credentials::Firebase(tokens) => Some(tokens),
            Credentials::ApiKey { .. } => None,
            Credentials::Bearer(_) => None,
            #[cfg(any(test, feature = "integration_tests", feature = "test-util"))]
            Credentials::Test => None,
        }
    }

    /// Returns the API key string if this is an API key credential.
    pub fn as_api_key(&self) -> Option<&str> {
        match self {
            Credentials::ApiKey { key, .. } => Some(key),
            Credentials::Firebase(_) => None,
            Credentials::Bearer(_) => None,
            #[cfg(any(test, feature = "integration_tests", feature = "test-util"))]
            Credentials::Test => None,
        }
    }

    /// Returns the Firebase refresh token if this is a Firebase credential.
    pub fn refresh_token(&self) -> Option<&str> {
        match self {
            Credentials::Firebase(tokens) => Some(&tokens.refresh_token),
            Credentials::ApiKey { .. } => None,
            Credentials::Bearer(_) => None,
            #[cfg(any(test, feature = "integration_tests", feature = "test-util"))]
            Credentials::Test => None,
        }
    }

    /// Returns the short-lived token to use in HTTP requests to the server.
    pub fn bearer_token(&self) -> AuthToken {
        match self {
            Credentials::Firebase(tokens) => AuthToken::Firebase(tokens.id_token.clone()),
            Credentials::ApiKey { key, .. } => AuthToken::ApiKey(key.clone()),
            Credentials::Bearer(token) => AuthToken::Bearer(token.clone()),
            #[cfg(any(test, feature = "integration_tests", feature = "test-util"))]
            Credentials::Test => AuthToken::NoAuth,
        }
    }
    /// Returns whether these credentials are externally managed and should not trigger local token
    /// refresh or reauth flows.
    pub fn is_externally_managed(&self) -> bool {
        match self {
            Credentials::Bearer(_) => true,
            Credentials::Firebase(_) | Credentials::ApiKey { .. } => false,
            #[cfg(any(test, feature = "integration_tests", feature = "test-util"))]
            Credentials::Test => false,
        }
    }
}

/// Represents different types of authentication tokens.
#[derive(Debug, Clone)]
pub enum AuthToken {
    /// Firebase short-lived access token.
    Firebase(String),
    /// API key for direct server authentication.
    ApiKey(String),
    /// Request-scoped or externally managed bearer token.
    Bearer(String),
    /// No authentication token available (e.g. test credentials).
    #[cfg_attr(
        not(any(test, feature = "integration_tests", feature = "test-util")),
        allow(dead_code)
    )]
    NoAuth,
}

impl AuthToken {
    /// Returns the token string to use in an Authorization header, or `None` if auth is not
    /// header-based or there is no auth.
    pub fn as_bearer_token(&self) -> Option<&str> {
        match self {
            AuthToken::Firebase(token) => Some(token),
            AuthToken::ApiKey(key) => Some(key),
            AuthToken::Bearer(token) => Some(token),
            AuthToken::NoAuth => None,
        }
    }

    /// Returns the bearer token as an owned string, or `None` if auth is not header-based.
    pub fn bearer_token(&self) -> Option<String> {
        match self {
            AuthToken::Firebase(token) => Some(token.clone()),
            AuthToken::ApiKey(key) => Some(key.clone()),
            AuthToken::Bearer(token) => Some(token.clone()),
            AuthToken::NoAuth => None,
        }
    }
}

/// A long-lived Firebase refresh token, exchanged for a short-lived access token.
#[derive(Debug, Clone)]
pub struct RefreshToken(String);

impl RefreshToken {
    pub fn new(token: impl Into<String>) -> Self {
        Self(token.into())
    }

    pub fn get(&self) -> &str {
        self.0.as_str()
    }

    /// Returns the url for trading this token into an access token.
    pub fn access_token_url(&self, api_key: &str) -> String {
        // See https://firebase.google.com/docs/reference/rest/auth for info on these
        // authentication endpoints.
        format!("https://securetoken.googleapis.com/v1/token?key={api_key}")
    }

    /// Returns the POST body to include when trading this token into an access token.
    pub fn access_token_request_body(&self) -> Vec<(&str, &str)> {
        vec![
            ("grant_type", "refresh_token"),
            ("refresh_token", self.get()),
        ]
    }

    /// Returns the proxy URL for trading this token into an access token.
    /// Used when the initial request to Firebase fails and we want to try and proxy the request
    /// through our server.
    pub fn proxy_url(&self, server_root: &str, api_key: &str) -> String {
        format!("{server_root}/proxy/token?key={api_key}")
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct FirebaseAuthTokens {
    /// ID tokens are Firebase tokens, which are short-lived tokens that are used to authenticate
    /// requests to the server. These are obtained by exchanging long-lived refresh tokens.
    pub id_token: String,
    /// Refresh tokens are long-lived tokens that can be exchanged for short-lived access tokens
    /// (stored in the id_token field). We use the refresh token to get a new ID token when the
    /// current one expires.
    pub refresh_token: String,
    /// When the ID token expires. If the token has expired, or will expire soon, we should
    /// fetch a new ID token using the user's refresh token.
    pub expiration_time: DateTime<FixedOffset>,
}

impl FirebaseAuthTokens {
    pub fn from_response(
        id_token: String,
        refresh_token: String,
        expires_in: String,
    ) -> Result<Self, anyhow::Error> {
        let local_time = Local::now();
        Ok(Self {
            id_token,
            expiration_time: local_time.with_timezone(local_time.offset())
                + chrono::Duration::seconds(
                    expires_in.parse::<i64>().map_err(anyhow::Error::from)?,
                ),
            refresh_token,
        })
    }
}

#[cfg(test)]
#[path = "credentials_tests.rs"]
mod tests;
