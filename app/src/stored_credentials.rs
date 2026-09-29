//! Removes the Warp account credential and the anonymous id that earlier versions stored.

use warp_core::user_preferences::GetUserPreferences as _;
use warpui::AppContext;
use warpui_extras::secure_storage::{self, AppContextExt as _};

/// Secure-storage key under which the credentials of the removed account system were stored.
const ACCOUNT_CREDENTIALS_KEY: &str = "User";

/// Private-preferences key under which earlier versions stored a random anonymous id.
const ANONYMOUS_ID_KEY: &str = "ExperimentId";

/// Private-preferences key recording that the removal has been attempted.
const REMOVAL_ATTEMPTED_KEY: &str = "RemovedStoredAccountCredentials";

/// Deletes the stored account credential and anonymous id once per data profile. The attempt is best-effort: a
/// failure is logged and not retried, since the app never reads the credential.
pub(crate) fn remove_stored_account_credentials_once(ctx: &AppContext) {
    let prefs = ctx.private_user_preferences();
    if prefs
        .read_value(REMOVAL_ATTEMPTED_KEY)
        .unwrap_or_default()
        .is_some()
    {
        return;
    }

    match ctx.secure_storage().remove_value(ACCOUNT_CREDENTIALS_KEY) {
        Ok(()) => log::info!("Removed stored account credentials from secure storage"),
        Err(secure_storage::Error::NotFound) => {}
        Err(err) => log::warn!("Unable to remove stored account credentials: {err:?}"),
    }

    if let Err(err) = prefs.remove_value(ANONYMOUS_ID_KEY) {
        log::warn!("Unable to remove the stored anonymous id: {err:?}");
    }

    if let Err(err) = prefs.write_value(REMOVAL_ATTEMPTED_KEY, "true".to_owned()) {
        log::warn!("Unable to record stored account credential removal: {err:?}");
    }
}

#[cfg(test)]
#[path = "stored_credentials_tests.rs"]
mod tests;
