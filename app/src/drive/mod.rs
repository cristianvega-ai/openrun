pub mod cloud_action_confirmation_dialog;
pub mod cloud_object_styling;
pub mod folders;
pub mod sharing;

pub use cloud_objects::drive::CloudObjectTypeAndId;

use crate::ui_components::icons::Icon;

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum DriveObjectType {
    Workflow,
    Folder,
}

impl From<DriveObjectType> for Icon {
    fn from(cloud_object_type: DriveObjectType) -> Icon {
        match cloud_object_type {
            DriveObjectType::Workflow => Icon::Workflow,
            DriveObjectType::Folder => Icon::Folder,
        }
    }
}
