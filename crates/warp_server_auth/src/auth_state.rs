use anyhow::anyhow;
use parking_lot::RwLock;
use warp_errors::report_error;

use super::credentials::{Credentials, FirebaseAuthTokens};

/// The authentication credentials held by the server client. The app has no accounts, so the
/// credentials are always empty outside of tests.
#[derive(Default)]
pub struct AuthState {
    credentials: RwLock<Option<Credentials>>,
}

impl AuthState {
    pub fn new() -> Self {
        Self::default()
    }

    #[cfg(any(test, feature = "integration_tests", feature = "test-util"))]
    pub fn new_for_test() -> Self {
        Self {
            credentials: RwLock::new(Some(Credentials::Test)),
        }
    }

    /// Returns the current credentials.
    pub fn credentials(&self) -> Option<Credentials> {
        self.credentials.read().clone()
    }

    /// Sets the credentials.
    pub fn set_credentials(&self, credentials: Option<Credentials>) {
        *self.credentials.write() = credentials;
    }

    /// Updates the Firebase auth tokens within the current credentials.
    /// Reports an error if the current credentials are not Firebase.
    pub fn update_firebase_tokens(&self, new_auth_tokens: FirebaseAuthTokens) {
        let mut write_lock = self.credentials.write();
        if let Some(Credentials::Firebase(tokens)) = write_lock.as_mut() {
            *tokens = new_auth_tokens;
        } else {
            report_error!(anyhow!(
                "Tried to update Firebase tokens without Firebase credentials"
            ));
        }
    }

    /// Returns the cached access token, if any exists. This method *will not* check if the JWT is
    /// still valid!
    pub fn get_access_token_ignoring_validity(&self) -> Option<String> {
        let credentials = self.credentials.read();
        credentials.as_ref()?.bearer_token().bearer_token()
    }
}
