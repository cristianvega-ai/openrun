use ai::api_keys::ApiKeyManager;
use settings::Setting as _;
use warp_core::send_telemetry_from_ctx;
use warpui::{Entity, ModelContext, SingletonEntity, WindowId};

use super::view::free_ai_removal_modal::{
    FreeAiRemovalModalTelemetryEvent, FreeAiRemovalModalVariant,
};
use crate::ai::{AIRequestUsageModel, AIRequestUsageModelEvent};
use crate::auth::AuthStateProvider;
use crate::channel::{Channel, ChannelState};
use crate::root_view::has_completed_local_onboarding;
use crate::settings::AISettings;
use crate::terminal::general_settings::GeneralSettings;
use crate::workspaces::user_workspaces::UserWorkspaces;
use crate::workspaces::workspace::CustomerType;

/// Holds the canonical state of whether a one-time modal is currently being shown, and the
/// window it is shown in.
pub struct OneTimeModalModel {
    is_build_plan_migration_modal_open: bool,
    /// Whether the free-AI-removal notice modal is currently being shown.
    is_free_ai_removal_modal_open: bool,
    /// Whether the initial one-time modal checks have run. Event-driven re-checks wait for them.
    has_completed_initial_modal_checks: bool,
    /// Whether `UserWorkspaces` has emitted `TeamsChanged`, meaning workspace billing
    /// data reflects more than the local cache and "no workspace" can be trusted to
    /// mean a solo (Free) user rather than not-yet-loaded data.
    has_fetched_workspaces: bool,
    /// The window ID where the currently open one-time modal should be displayed.
    /// This is captured when a modal is first opened and ensures the modal stays on that window.
    target_window_id: Option<WindowId>,
}

impl OneTimeModalModel {
    pub fn new(ctx: &mut ModelContext<Self>) -> Self {
        // Subscribe to UserWorkspaces to detect when sunsetted_to_build_ts changes
        ctx.subscribe_to_model(
            &crate::workspaces::user_workspaces::UserWorkspaces::handle(ctx),
            |me, _, event, ctx| {
                use crate::workspaces::user_workspaces::UserWorkspacesEvent;
                match event {
                    UserWorkspacesEvent::SunsettedToBuildDataUpdated => {
                        // When sunsetted_to_build_ts is updated, check if we should show the modal
                        me.check_and_trigger_build_plan_migration_modal(ctx);
                    }
                    UserWorkspacesEvent::TeamsChanged => {
                        me.has_fetched_workspaces = true;
                        me.maybe_recheck_free_ai_removal_modal(ctx);
                    }
                    _ => {}
                }
            },
        );

        // The base-credit allowance that gates the free-AI-removal notice loads
        // asynchronously, so re-evaluate the notice whenever request usage updates.
        ctx.subscribe_to_model(&AIRequestUsageModel::handle(ctx), |me, _, event, ctx| {
            if let AIRequestUsageModelEvent::RequestUsageUpdated = event {
                me.maybe_recheck_free_ai_removal_modal(ctx);
            }
        });

        Self {
            is_build_plan_migration_modal_open: false,
            is_free_ai_removal_modal_open: false,
            has_completed_initial_modal_checks: false,
            has_fetched_workspaces: false,
            target_window_id: None,
        }
    }

    /// Returns the window ID where the currently open one-time modal should be displayed.
    pub fn target_window_id(&self) -> Option<WindowId> {
        self.target_window_id
    }

    /// Returns true if any one-time modal is currently open.
    pub fn is_any_modal_open(&self) -> bool {
        (self.is_build_plan_migration_modal_open || self.is_free_ai_removal_modal_open)
            && self.target_window_id.is_some()
    }

    pub fn update_target_window_id(&mut self, window_id: WindowId, ctx: &mut ModelContext<Self>) {
        let was_any_modal_visible = self.is_any_modal_open();
        self.target_window_id = Some(window_id);
        let is_any_modal_visible = self.is_any_modal_open();
        if was_any_modal_visible != is_any_modal_visible {
            ctx.emit(OneTimeModalEvent::VisibilityChanged {
                is_open: is_any_modal_visible,
            });
        }
    }

    /// Returns whether the free-AI-removal notice modal is currently open.
    pub fn is_free_ai_removal_modal_open(&self) -> bool {
        self.is_free_ai_removal_modal_open && self.target_window_id.is_some()
    }

    pub fn mark_free_ai_removal_modal_dismissed(&mut self, ctx: &mut ModelContext<Self>) {
        self.set_free_ai_removal_modal_open(false, ctx);
    }

    #[cfg(debug_assertions)]
    pub fn force_open_free_ai_removal_modal(&mut self, ctx: &mut ModelContext<Self>) {
        self.set_free_ai_removal_modal_open(true, ctx);
    }

    fn set_free_ai_removal_modal_open(
        &mut self,
        is_open: bool,
        ctx: &mut ModelContext<Self>,
    ) -> bool {
        if self.is_free_ai_removal_modal_open != is_open {
            self.is_free_ai_removal_modal_open = is_open;
            ctx.emit(OneTimeModalEvent::VisibilityChanged { is_open });
            return true;
        }
        false
    }

    /// Re-evaluates the free-AI-removal notice outside the initial startup check, e.g.
    /// when workspace billing data arrives after startup.
    fn maybe_recheck_free_ai_removal_modal(&mut self, ctx: &mut ModelContext<Self>) {
        if !self.has_completed_initial_modal_checks || self.is_any_modal_open() {
            return;
        }
        self.check_and_trigger_free_ai_removal_modal(ctx);
    }

    fn check_and_trigger_free_ai_removal_modal(&mut self, ctx: &mut ModelContext<Self>) -> bool {
        // Never show one-time modals on WASM. `check_and_trigger_all_modals` already
        // guards its own call, but `maybe_recheck_free_ai_removal_modal` calls
        // this directly (e.g. from an async billing/usage update), so the guard belongs here too.
        if cfg!(target_family = "wasm") {
            return false;
        }

        if *AISettings::as_ref(ctx).did_check_to_trigger_free_ai_removal_modal {
            return false;
        }

        // Anonymous users have no BYOK or upgrade path; leave them unmarked so the
        // decision is made after they sign in.
        if AuthStateProvider::as_ref(ctx)
            .get()
            .is_anonymous_or_logged_out()
        {
            return false;
        }

        let customer_type = UserWorkspaces::as_ref(ctx)
            .current_workspace()
            .map(|workspace| workspace.billing_metadata.customer_type);
        let is_warp_ai_enabled = *AISettings::as_ref(ctx).is_any_ai_enabled;
        let has_byok_or_byoe = ApiKeyManager::as_ref(ctx).has_any_key();
        let completed_new_onboarding = has_completed_local_onboarding(ctx);
        let has_zero_base_credits = AIRequestUsageModel::as_ref(ctx).request_limit() == 0;

        let decision = free_ai_removal_modal_decision(
            customer_type,
            is_warp_ai_enabled,
            has_byok_or_byoe,
            completed_new_onboarding,
            has_zero_base_credits,
            self.has_fetched_workspaces,
        );
        if decision == FreeAiRemovalModalDecision::Defer {
            return false;
        }

        AISettings::handle(ctx).update(ctx, |settings, ctx| {
            if let Err(e) = settings
                .did_check_to_trigger_free_ai_removal_modal
                .set_value(true, ctx)
            {
                log::warn!("Failed to mark free AI removal modal as seen: {e}");
            }
        });

        if decision == FreeAiRemovalModalDecision::MarkSeenSilently {
            return false;
        }

        let should_show = !matches!(ChannelState::channel(), Channel::Integration);
        if should_show {
            send_telemetry_from_ctx!(
                FreeAiRemovalModalTelemetryEvent::Shown {
                    variant: FreeAiRemovalModalVariant::Notice,
                },
                ctx
            );
        }
        self.set_free_ai_removal_modal_open(should_show, ctx);
        should_show
    }

    pub fn is_build_plan_migration_modal_open(&self) -> bool {
        self.is_build_plan_migration_modal_open && self.target_window_id.is_some()
    }

    pub fn mark_build_plan_migration_modal_dismissed(&mut self, ctx: &mut ModelContext<Self>) {
        self.set_build_plan_migration_modal_open(false, ctx);
    }

    #[cfg(debug_assertions)]
    pub fn force_open_build_plan_migration_modal(&mut self, ctx: &mut ModelContext<Self>) {
        self.set_build_plan_migration_modal_open(true, ctx);
    }

    fn set_build_plan_migration_modal_open(
        &mut self,
        is_open: bool,
        ctx: &mut ModelContext<Self>,
    ) -> bool {
        if self.is_build_plan_migration_modal_open != is_open {
            self.is_build_plan_migration_modal_open = is_open;
            ctx.emit(OneTimeModalEvent::VisibilityChanged { is_open });
            return true;
        }
        false
    }

    fn check_and_trigger_build_plan_migration_modal(
        &mut self,
        ctx: &mut ModelContext<Self>,
    ) -> bool {
        use crate::workspaces::user_workspaces::UserWorkspaces;

        // Check if already dismissed
        let general_settings = GeneralSettings::as_ref(ctx);
        if *general_settings
            .build_plan_migration_modal_dismissed
            .value()
        {
            return false;
        }

        // Check if user is authenticated
        let auth_state = crate::auth::AuthStateProvider::as_ref(ctx).get();

        if auth_state.is_anonymous_or_logged_out() {
            return false;
        }

        // Check if current workspace has sunsetted_to_build_ts set
        let user_workspaces = UserWorkspaces::as_ref(ctx);
        let Some(target_window_id) = self
            .target_window_id
            .or_else(|| ctx.windows().active_window())
        else {
            return false;
        };
        let Some(current_team) = user_workspaces.team_for_window(target_window_id) else {
            return false;
        };

        // Check if user is admin of the team
        let Some(user_email) = auth_state.user_email() else {
            return false;
        };

        if !current_team.has_admin_permissions(&user_email) {
            return false;
        }

        // Check if service agreement has sunsetted_to_build_ts set
        let has_sunsetted_to_build = user_workspaces
            .current_workspace()
            .and_then(|workspace| workspace.billing_metadata.service_agreements.first())
            .is_some_and(|agreement| agreement.sunsetted_to_build_ts.is_some());

        if !has_sunsetted_to_build {
            return false;
        }

        // All conditions met, show the modal
        self.target_window_id = Some(target_window_id);
        self.set_build_plan_migration_modal_open(true, ctx)
    }
}

/// The outcome of evaluating the free-AI-removal notice conditions.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum FreeAiRemovalModalDecision {
    /// Show the modal and write the seen marker.
    Show,
    /// Write the seen marker without showing the modal.
    MarkSeenSilently,
    /// Not enough data to decide; re-evaluate on the next billing/experiments update.
    Defer,
}

fn free_ai_removal_modal_decision(
    customer_type: Option<CustomerType>,
    is_warp_ai_enabled: bool,
    has_byok_or_byoe: bool,
    completed_new_onboarding: bool,
    has_zero_base_credits: bool,
    workspaces_fetched: bool,
) -> FreeAiRemovalModalDecision {
    if !is_warp_ai_enabled || has_byok_or_byoe || completed_new_onboarding {
        return FreeAiRemovalModalDecision::MarkSeenSilently;
    }
    // Restrict to a Free (or confirmed solo) user; anyone else is paid (silently
    // marked) or not-yet-known (deferred).
    match customer_type {
        Some(CustomerType::Free) => {}
        // A missing workspace usually means billing data hasn't loaded yet; only treat
        // it as a solo Free user once a server fetch has confirmed there is none, so a
        // paid user's modal decision never runs against absent data.
        None if workspaces_fetched => {}
        None | Some(CustomerType::Unknown) => return FreeAiRemovalModalDecision::Defer,
        Some(_) => return FreeAiRemovalModalDecision::MarkSeenSilently,
    }
    // Some ICPs still receive base AI credits on the Free plan; don't spook them with
    // the notice. Only show once the base allowance is gone, and defer (rather than
    // mark seen) otherwise so it re-evaluates if the allowance later drops to zero.
    if has_zero_base_credits {
        FreeAiRemovalModalDecision::Show
    } else {
        FreeAiRemovalModalDecision::Defer
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OneTimeModalEvent {
    VisibilityChanged { is_open: bool },
}

impl Entity for OneTimeModalModel {
    type Event = OneTimeModalEvent;
}

impl SingletonEntity for OneTimeModalModel {}

#[cfg(test)]
#[path = "one_time_modal_model_tests.rs"]
mod tests;
