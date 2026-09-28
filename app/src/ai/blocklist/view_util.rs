//! This module contains common utilities for rendering Blocklist AI UI.

use pathfinder_color::ColorU;
use thousands::Separable;
use warp_core::features::FeatureFlag;
use warp_core::ui::appearance::Appearance;
use warpui::elements::{ConstrainedBox, Container};
use warpui::{AppContext, Element, EntityId, SingletonEntity};

use crate::ai::AIRequestUsageModel;
use crate::ai::agent::RenderableAIError;
use crate::settings::UsageDisplayUnit;
use crate::themes::theme::{AnsiColorIdentifier, Fill, WarpTheme};
use crate::ui_components::icons::Icon;
use crate::workspaces::user_workspaces::UserWorkspaces;

const ERROR_APOLOGY_TEXT: &str = "I'm sorry, I couldn't complete that request.";
const INTERNAL_WARP_ERROR: &str = "Internal Warp error.";
pub const FAILED_OUTPUT_USAGE_NOTICE_TEXT: &str = "This response won't count towards your usage.";
pub const OUT_OF_CREDITS_SUBSCRIBE_LABEL: &str = "Subscribe";

/// Returns the color to be used for various AI signifiers
/// input with AI mode).
pub fn ai_brand_color(theme: &WarpTheme) -> ColorU {
    AnsiColorIdentifier::Magenta
        .to_ansi_color(&theme.terminal_colors().normal)
        .into()
}

/// Returns the color to be used for error UI throughout Agent Mode (like the "request limit
/// exceeded" chip).
pub fn error_color(theme: &WarpTheme) -> ColorU {
    AnsiColorIdentifier::Red
        .to_ansi_color(&theme.terminal_colors().normal)
        .into()
}
/// Renderer-neutral content for a failed Agent Mode request.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum FailedOutputPresentation {
    Message(String),
    OutOfCredits {
        message: String,
        can_use_own_api_keys: bool,
    },
    InvalidApiKey {
        title: &'static str,
        detail: String,
    },
    ContextWindowExceeded {
        message: String,
    },
    AwsBedrockCredentialsExpiredOrInvalid {
        fallback_message: String,
    },
    GeminiEnterpriseCredentialsExpiredOrInvalid {
        fallback_message: String,
    },
}

/// Returns the user-facing presentation for an Agent Mode request failure.
///
/// Recovery-pending failures are intentionally suppressed so callers cannot accidentally render
/// an alarming terminal error while an automatic resume is still in flight.
pub fn failed_output_presentation(
    error: &RenderableAIError,
    app: &AppContext,
) -> Option<FailedOutputPresentation> {
    if error.should_suppress_during_recovery() {
        return None;
    }

    Some(match error {
        RenderableAIError::QuotaLimit {
            user_display_message,
        } => {
            if let Some(message) = user_display_message {
                if should_show_subscribe_cta(app) {
                    FailedOutputPresentation::OutOfCredits {
                        message: format!("{ERROR_APOLOGY_TEXT}\n\n{message}"),
                        can_use_own_api_keys: UserWorkspaces::as_ref(app)
                            .is_byo_api_key_enabled(app),
                    }
                } else {
                    FailedOutputPresentation::Message(format!("{ERROR_APOLOGY_TEXT}\n\n{message}"))
                }
            } else {
                let formatted_next_refresh_time = AIRequestUsageModel::as_ref(app)
                    .next_refresh_time()
                    .format("%B %d")
                    .to_string();
                FailedOutputPresentation::Message(format!(
                    "{ERROR_APOLOGY_TEXT}\n\nYou've reached your credit limit. Your credit limit resets on {formatted_next_refresh_time}.",
                ))
            }
        }
        RenderableAIError::ServerOverloaded => FailedOutputPresentation::Message(
            "Warp is currently overloaded. Please try again later.".to_string(),
        ),
        RenderableAIError::InternalWarpError => FailedOutputPresentation::Message(format!(
            "{ERROR_APOLOGY_TEXT}\n\n{INTERNAL_WARP_ERROR}"
        )),
        RenderableAIError::ContextWindowExceeded(message) => {
            FailedOutputPresentation::ContextWindowExceeded {
                message: message.clone(),
            }
        }
        RenderableAIError::InvalidApiKey {
            provider,
            model_name,
        } => FailedOutputPresentation::InvalidApiKey {
            title: "Provided API key is not valid",
            detail: format!(
                "Failed to authenticate with {provider} when using {model_name}. \
                 Double-check that your API key is correct."
            ),
        },
        RenderableAIError::AwsBedrockCredentialsExpiredOrInvalid { model_name } => {
            FailedOutputPresentation::AwsBedrockCredentialsExpiredOrInvalid {
                fallback_message: format!(
                    "{ERROR_APOLOGY_TEXT}\n\nAWS credentials expired or missing for {model_name}. \
                     Please refresh your AWS credentials."
                ),
            }
        }
        RenderableAIError::GeminiEnterpriseCredentialsExpiredOrInvalid => {
            FailedOutputPresentation::GeminiEnterpriseCredentialsExpiredOrInvalid {
                fallback_message: format!(
                    "{ERROR_APOLOGY_TEXT}\n\nGemini Enterprise credentials expired or invalid.\n\n\
                     Warp couldn't authenticate with Google Cloud. Refresh your Gemini Enterprise credentials, then retry the request."
                ),
            }
        }
        RenderableAIError::TransientNetworkError { .. } => {
            FailedOutputPresentation::Message(error.to_string())
        }
        RenderableAIError::AgentStreamFailure { error_message }
        | RenderableAIError::Other { error_message, .. } => {
            FailedOutputPresentation::Message(format!("{ERROR_APOLOGY_TEXT}\n\n{error_message}"))
        }
        RenderableAIError::AgentExitedShell { .. } => {
            FailedOutputPresentation::Message(format!("{ERROR_APOLOGY_TEXT}\n\n{error}"))
        }
        // Cloud startup failures surface the raw server message directly, matching the
        // dedicated GUI error card which shows the message without an apology prefix.
        RenderableAIError::CloudStartupFailed(msg) => {
            FailedOutputPresentation::Message(msg.clone())
        }
    })
}

/// Whether a failed Agent Mode response should explain that it will not count towards usage.
pub fn should_show_failed_output_usage_notice(
    error: &RenderableAIError,
    is_latest_visible_exchange_in_root_task: bool,
    has_expanded_last_requested_command: bool,
    is_restored: bool,
) -> bool {
    !error.should_suppress_during_recovery()
        && is_latest_visible_exchange_in_root_task
        && !has_expanded_last_requested_command
        && !is_restored
        && !error.is_invalid_api_key()
}

/// Whether to show the out-of-credits CTA: only for non-paid users. Paid users and the enterprise
/// spend-limit variant of this message fall back to plain text.
fn should_show_subscribe_cta(app: &AppContext) -> bool {
    UserWorkspaces::as_ref(app)
        .current_workspace()
        .is_none_or(|workspace| !workspace.billing_metadata.is_user_on_paid_plan())
}

/// Returns the AI icon element to be rendered in AI output blocks and the terminal input when in
/// AI mode. Takes a color parameter as the solid fill for the icon. We use [ai_brand_color] in most
/// cases.
pub fn render_ai_agent_mode_icon(app: &AppContext, color: impl Into<Fill>) -> Box<dyn Element> {
    render_input_icon(Icon::AgentMode, color.into(), app)
}

fn render_input_icon(icon: Icon, color: Fill, app: &AppContext) -> Box<dyn Element> {
    // Since the icon is rendered next to monospace text content, its size should scale to
    // based on the current font size -- specifically, its height must match the editor text line
    // height.
    let icon_size = ai_indicator_height(app);
    ConstrainedBox::new(
        Container::new(icon.to_warpui_icon(color).finish())
            .with_uniform_padding(icon_size / 8.)
            .finish(),
    )
    .with_width(icon_size)
    .with_height(icon_size)
    .finish()
}

/// Returns the size to be used for the AI icon in AI output blocks and the terminal input when in
/// AI mode.
///
/// This size is computed based on the user's current font size and line height ratio, such that the
/// size of the icon matches the user's text line height.  This is necessary because the AI icon in
/// the input is rendered next to text in the editor.
pub fn ai_indicator_height(app: &AppContext) -> f32 {
    let appearance = Appearance::as_ref(app);
    app.font_cache().line_height(
        appearance.monospace_font_size(),
        appearance.line_height_ratio(),
    )
}

/// Returns the saved position ID of the attached blocks chip inside the [`AIBlock`] header.
pub fn get_attached_blocks_chip_element_position_id(view_id: EntityId) -> String {
    format!("aiblock:{view_id}.attached_block_chip_position")
}

/// Returns the saved position ID of the overflow menu inside the [`AIBlock`] header.
pub fn get_ai_block_overflow_menu_element_position_id(view_id: EntityId) -> String {
    format!("aiblock:{view_id}.overflow_menu_position")
}

/// Formats credit count to display as whole numbers when the value is effectively a whole number,
/// otherwise displays with one decimal place. A non-zero amount below the displayed precision is
/// shown as `<0.1 credits` rather than rounding to zero, which would read as no cost.
/// Returns a formatted string with proper pluralization ("credit" vs "credits").
pub fn format_credits(credits: f32) -> String {
    if credits > 0.0 && credits < 0.1 {
        return "<0.1 credits".to_string();
    }
    // If the first part of the decimal is 0, we just display the whole number.
    if credits.fract() < 0.1 {
        let whole = credits.trunc() as i32;
        if whole == 1 {
            format!("{whole} credit")
        } else {
            format!("{whole} credits")
        }
    } else {
        format!("{credits:.1} credits")
    }
}

/// Formats a US-cent amount as dollars without rounding a positive charge down to zero.
pub fn format_dollars(cost_in_cents: f32) -> String {
    // Accumulated costs can produce negative zero, which would otherwise render as `$-0.00`.
    let cost_in_cents = if cost_in_cents == 0.0 {
        0.0
    } else {
        cost_in_cents
    };
    let dollars = cost_in_cents / 100.0;
    if cost_in_cents > 0.0 && dollars < 0.01 {
        "<$0.01".to_string()
    } else {
        format!("${dollars:.2}")
    }
}

fn effective_usage_unit(unit: UsageDisplayUnit, cost_in_cents: Option<f32>) -> UsageDisplayUnit {
    if !FeatureFlag::PricingTransparency.is_enabled() {
        return UsageDisplayUnit::Credits;
    }
    match unit {
        UsageDisplayUnit::Credits => UsageDisplayUnit::Credits,
        UsageDisplayUnit::Dollars if cost_in_cents.is_some() => UsageDisplayUnit::Dollars,
        UsageDisplayUnit::Dollars => UsageDisplayUnit::Credits,
    }
}

fn format_usage_unit_value(
    credits: f32,
    cost_in_cents: Option<f32>,
    unit: UsageDisplayUnit,
) -> String {
    match unit {
        UsageDisplayUnit::Credits => format_credits(credits),
        UsageDisplayUnit::Dollars => cost_in_cents
            .map(format_dollars)
            .unwrap_or_else(|| format_credits(credits)),
    }
}

/// Formats tokens with the selected unit, falling back to credits when dollars are unavailable.
pub fn format_usage(
    credits: f32,
    tokens: Option<u32>,
    cost_in_cents: Option<f32>,
    unit: UsageDisplayUnit,
) -> String {
    let resolved_unit = effective_usage_unit(unit, cost_in_cents);
    if !FeatureFlag::PricingTransparency.is_enabled() || resolved_unit != unit {
        return format_credits(credits);
    }
    let unit_text = format_usage_unit_value(credits, cost_in_cents, resolved_unit);
    let Some(tokens) = tokens.filter(|&tokens| tokens > 0) else {
        return unit_text;
    };
    format!("{} tokens / {unit_text}", tokens.separate_with_commas())
}

#[derive(Clone, Copy)]
pub enum UsageLabelKind {
    LastResponse,
    Total,
    Plain,
    DetailsPanel,
}

/// Matches the label to the unit [`format_usage`] will render.
pub fn usage_label(
    kind: UsageLabelKind,
    cost_in_cents: Option<f32>,
    unit: UsageDisplayUnit,
) -> String {
    let unit = effective_usage_unit(unit, cost_in_cents);
    let base = match (kind, unit) {
        (UsageLabelKind::DetailsPanel, UsageDisplayUnit::Credits) => "Credits used",
        (UsageLabelKind::DetailsPanel, UsageDisplayUnit::Dollars) => "Usage",
        (
            UsageLabelKind::LastResponse | UsageLabelKind::Total | UsageLabelKind::Plain,
            UsageDisplayUnit::Credits,
        ) => "Credits spent",
        (
            UsageLabelKind::LastResponse | UsageLabelKind::Total | UsageLabelKind::Plain,
            UsageDisplayUnit::Dollars,
        ) => "Usage charged",
    };
    let suffix = match kind {
        UsageLabelKind::LastResponse => " (last response)",
        UsageLabelKind::Total => " (total)",
        UsageLabelKind::Plain | UsageLabelKind::DetailsPanel => "",
    };
    format!("{base}{suffix}")
}

#[cfg(test)]
#[path = "view_util_tests.rs"]
mod tests;
