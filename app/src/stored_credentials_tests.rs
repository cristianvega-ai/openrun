use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use settings::{PrivatePreferences, PublicPreferences};
use warp_core::user_preferences::GetUserPreferences as _;
use warpui::App;
use warpui_extras::secure_storage::{self, AppContextExt as _};
use warpui_extras::user_preferences;

use super::{ACCOUNT_CREDENTIALS_KEY, ANONYMOUS_ID_KEY, remove_stored_account_credentials_once};

#[derive(Default)]
struct RecordingSecureStorage {
    values: Mutex<HashMap<String, String>>,
    removals: Arc<Mutex<usize>>,
}

impl secure_storage::SecureStorage for RecordingSecureStorage {
    fn write_value(&self, key: &str, value: &str) -> Result<(), secure_storage::Error> {
        self.values
            .lock()
            .unwrap()
            .insert(key.to_owned(), value.to_owned());
        Ok(())
    }

    fn read_value(&self, key: &str) -> Result<String, secure_storage::Error> {
        self.values
            .lock()
            .unwrap()
            .get(key)
            .cloned()
            .ok_or(secure_storage::Error::NotFound)
    }

    fn remove_value(&self, key: &str) -> Result<(), secure_storage::Error> {
        *self.removals.lock().unwrap() += 1;
        self.values
            .lock()
            .unwrap()
            .remove(key)
            .map(|_| ())
            .ok_or(secure_storage::Error::NotFound)
    }
}

#[test]
fn removes_stored_account_credentials_and_anonymous_id_only_once() {
    App::test((), |mut app| async move {
        let removals = Arc::new(Mutex::new(0));
        app.update(|ctx| {
            ctx.add_singleton_model(|_| {
                PublicPreferences::new(
                    Box::<user_preferences::in_memory::InMemoryPreferences>::default(),
                )
            });
            ctx.add_singleton_model(|_| {
                PrivatePreferences::new(
                    Box::<user_preferences::in_memory::InMemoryPreferences>::default(),
                )
            });
            let storage = RecordingSecureStorage {
                removals: removals.clone(),
                ..Default::default()
            };
            storage
                .values
                .lock()
                .unwrap()
                .insert(ACCOUNT_CREDENTIALS_KEY.to_owned(), "{}".to_owned());
            ctx.add_singleton_model(move |_| -> secure_storage::Model { Box::new(storage) });
        });

        app.read(|ctx| {
            ctx.private_user_preferences()
                .write_value(ANONYMOUS_ID_KEY, "anonymous-id".to_owned())
                .unwrap();

            remove_stored_account_credentials_once(ctx);
            assert_eq!(
                ctx.private_user_preferences()
                    .read_value(ANONYMOUS_ID_KEY)
                    .unwrap(),
                None
            );
            assert!(matches!(
                ctx.secure_storage().read_value(ACCOUNT_CREDENTIALS_KEY),
                Err(secure_storage::Error::NotFound)
            ));

            remove_stored_account_credentials_once(ctx);
        });

        assert_eq!(*removals.lock().unwrap(), 1);
    });
}
