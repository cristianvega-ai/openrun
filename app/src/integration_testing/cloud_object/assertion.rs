use warpui::async_assert;
use warpui::integration::AssertionCallback;

use crate::cloud_object::model::generic_string_model::GenericStringObjectId;
use crate::cloud_object::model::persistence::CloudModel;
use crate::cloud_object::preference::{CloudPreferenceModel, Preference};
use crate::cloud_object::{CloudModelType, GenericCloudObject, Revision};
use crate::server::ids::{HashableId, ServerId, SyncId, ToServerId};

/// Asserts metadata exists for the object with the given key and that the revision in that
/// metadata matches the given expected revision.
pub fn assert_metadata_revision<K, M>(id: &str, expected_revision: i64) -> AssertionCallback
where
    K: HashableId + ToServerId + std::fmt::Debug + Into<String> + Clone + 'static,
    M: CloudModelType<IdType = K, CloudObjectType = GenericCloudObject<K, M>> + 'static,
{
    let id = SyncId::ServerId(ServerId::try_from(id).expect("ID is invalid"));
    Box::new(move |app, _window_id| {
        let revision =
            app.get_singleton_model_handle::<CloudModel>()
                .read(app, |cloud_model, _| {
                    let object = cloud_model
                        .get_object_of_type::<K, M>(&id)
                        .expect("object should exist");
                    object.metadata.revision.expect("revision should exist")
                });
        async_assert!(
            revision
                == Revision::from_unix_timestamp_micros(expected_revision)
                    .expect("revision should parse"),
            "Expected revision to be:{expected_revision:?}\nBut got:\n{revision:?}"
        )
    })
}

/// Asserts that there is a json preference object in the SQLite db with the given storage key and
/// JSON-serialized value.
pub fn assert_cloud_preference_exists(storage_key: &str, value: &str) -> AssertionCallback {
    let expected_preference =
        Preference::new(storage_key.to_owned(), value).expect("error creating preference");
    Box::new(move |app, _window_id| {
        let stored_preference =
            app.get_singleton_model_handle::<CloudModel>()
                .read(app, |cloud_model, _| {
                    let object = cloud_model
                        .get_all_objects_of_type::<GenericStringObjectId, CloudPreferenceModel>()
                        .find(|p| p.model().string_model == expected_preference)
                        .expect("Expected to find a matching preference object");
                    object.model().string_model.clone()
                });
        async_assert!(
            expected_preference == stored_preference,
            "Expected json object contents to match:\n{expected_preference:?}\nBut got:\n{stored_preference:?}"
        )
    })
}
