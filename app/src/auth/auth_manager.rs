use warpui::{Entity, ModelContext, SingletonEntity};

/// Account-authentication singleton. Accounts are not supported, so it never authenticates and
/// never emits.
pub struct AuthManager;

impl AuthManager {
    pub fn new(_: &mut ModelContext<Self>) -> Self {
        Self
    }

    #[cfg(test)]
    pub fn new_for_test(ctx: &mut ModelContext<Self>) -> Self {
        Self::new(ctx)
    }
}

impl Entity for AuthManager {
    type Event = ();
}

impl SingletonEntity for AuthManager {}
