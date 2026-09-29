mod session;

use firebase::FirebaseError;
pub use session::*;
use thiserror::Error;
pub use user_uid::{TEST_USER_EMAIL, TEST_USER_UID, UserUid};
use warp_errors::{AnyhowErrorExt, ErrorExt, register_error};
pub use warp_server_auth::user_uid;

/// Error type when retrieving a user and validating it against Firebase.
#[derive(Error, Debug)]
pub enum UserAuthenticationError {
    /// The user's refresh token is invalid, which can occur after the user changes
    /// a password for Google or GitHub authentication.
    #[error("Firebase returned a token error when fetching an ID token")]
    DeniedAccessToken(FirebaseError),
    /// The user's account is invalid, which can occur after the user requests
    /// account deletion under GDPR or CCPA.
    #[error("Firebase returned a user error when fetching an ID token")]
    UserAccountDisabled(FirebaseError),
    #[error("unexpected error occurred when fetching an ID token: {0:#}")]
    Unexpected(#[from] anyhow::Error),
}

impl ErrorExt for UserAuthenticationError {
    fn is_actionable(&self) -> bool {
        match self {
            UserAuthenticationError::DeniedAccessToken(error) => {
                // If a request to our server failed because the user's refresh token
                // has expired, they should reauthenticate, but there is no value in
                // reporting this back to us.
                log::info!("ignoring denied access token error: {error:#}");
                false
            }
            UserAuthenticationError::UserAccountDisabled(error) => {
                // If the user's account is disabled, they cannot make requests.
                log::info!("ignoring user account disabled error: {error:#}");
                false
            }
            UserAuthenticationError::Unexpected(error) => error.is_actionable(),
        }
    }
}
register_error!(UserAuthenticationError);

impl From<FirebaseError> for UserAuthenticationError {
    fn from(error: FirebaseError) -> Self {
        // These Firebase errors indicate that the user's token is in an errored state
        // and that the user likely just needs to log in again.
        const SOFT_ERRORS: &[&str] = &[
            "TOKEN_EXPIRED",
            "INVALID_REFRESH_TOKEN",
            "MISSING_REFRESH_TOKEN",
        ];
        // These Firebase errors indicate that the user's account is in an errored state
        // and that the user likely can no longer sign in with it.
        const HARD_ERRORS: &[&str] = &["USER_DISABLED", "USER_NOT_FOUND"];
        if SOFT_ERRORS.contains(&error.message.as_str()) {
            UserAuthenticationError::DeniedAccessToken(error)
        } else if HARD_ERRORS.contains(&error.message.as_str()) {
            UserAuthenticationError::UserAccountDisabled(error)
        } else {
            UserAuthenticationError::Unexpected(
                anyhow::Error::from(error)
                    .context("Failed to exchange refresh token with access token."),
            )
        }
    }
}
