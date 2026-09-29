//! Permission checks for local control.
use ::local_control::{ActionKind, ControlError, ErrorCode, PROTOCOL_VERSION};
use warpui::{ModelContext, SingletonEntity};

use crate::local_control::LocalControlBridge;
use crate::settings::LocalControlSettings;

pub(super) fn ensure_protocol_version(protocol_version: u32) -> Result<(), ControlError> {
    if protocol_version == PROTOCOL_VERSION {
        return Ok(());
    }
    Err(ControlError::new(
        ErrorCode::ProtocolVersionUnsupported,
        format!("unsupported protocol version {protocol_version}"),
    ))
}

#[cfg(test)]
pub(crate) fn capabilities() -> Vec<ActionKind> {
    ActionKind::implemented_metadata()
        .into_iter()
        .map(|metadata| metadata.kind)
        .collect()
}

pub(super) fn ensure_action_allowed(
    action: ActionKind,
    ctx: &mut ModelContext<LocalControlBridge>,
) -> Result<(), ControlError> {
    let settings = LocalControlSettings::as_ref(ctx);
    ensure_settings_allow_action(settings, action)
}

pub(crate) fn ensure_settings_allow_action(
    settings: &LocalControlSettings,
    action: ActionKind,
) -> Result<(), ControlError> {
    if !settings.is_enabled() {
        return Err(ControlError::new(
            ErrorCode::LocalControlDisabled,
            format!("{} is disabled for local control", action.as_str()),
        ));
    }
    Ok(())
}
