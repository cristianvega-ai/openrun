use super::*;

#[test]
fn stored_billing_metadata_with_removed_plan_fields_still_loads() {
    let stored = r#"{
        "tier": {
            "name": "Build",
            "description": "Build plan",
            "usage_based_pricing_policy": {"toggleable": true},
            "purchase_add_on_credits_policy": {"enabled": true, "premium_enabled": false, "price_premium_bps": 0},
            "enterprise_pay_as_you_go_policy": {"enabled": false},
            "enterprise_credits_auto_reload_policy": {"enabled": false},
            "shared_notebooks_policy": {"is_unlimited": false, "limit": 3},
            "shared_workflows_policy": {"is_unlimited": true, "limit": 0},
            "usage_visibility_policy": {"admin_granularity": "TeamAggregate", "max_prior_cycles": {"Limited": 2}},
            "byo_api_key_policy": {"enabled": true}
        },
        "customer_type": "Build",
        "delinquency_status": "PastDue"
    }"#;

    let billing: BillingMetadata =
        serde_json::from_str(stored).expect("removed fields must not break loading");

    assert_eq!(billing.tier.name, "Build");
    assert_eq!(billing.customer_type, CustomerType::Build);
    assert!(billing.is_byo_api_key_enabled());
}
