use chrono::{Duration, Utc};
use serde_json::{Value, json};

use super::{
    AgentConfigSnapshot, AgentSource, AmbientAgentTask, AmbientAgentTaskState, ExecutionLocation,
    TaskStatusErrorCode, TaskStatusMessage,
};

fn make_task(snapshot_name: Option<&str>, title: &str) -> AmbientAgentTask {
    let now = Utc::now();
    let agent_config_snapshot = snapshot_name.map(|name| AgentConfigSnapshot {
        name: Some(name.to_string()),
        ..Default::default()
    });
    AmbientAgentTask {
        task_id: "11111111-1111-1111-1111-111111111111".parse().unwrap(),
        parent_run_id: None,
        title: title.to_string(),
        state: AmbientAgentTaskState::InProgress,
        prompt: String::new(),
        created_at: now,
        started_at: Some(now),
        updated_at: now,
        run_time: Some("PT1S".parse().unwrap()),
        status_message: None,
        source: None,
        execution_location: None,
        session_id: None,
        session_link: None,
        creator: None,
        executor: None,
        conversation_id: None,
        request_usage: None,
        is_sandbox_running: false,
        agent_config_snapshot,
        artifacts: vec![],
        last_event_sequence: None,
        children: vec![],
        debug_agent_available: false,
        scope: None,
    }
}

fn task_json_with_run_time(run_time_key: &str, run_time: Value) -> Value {
    let now = Utc::now().to_rfc3339();
    let mut task = json!({
        "task_id": "11111111-1111-1111-1111-111111111111",
        "title": "Task",
        "state": "SUCCEEDED",
        "prompt": "test",
        "created_at": now,
        "started_at": now,
        "updated_at": now,
        "status_message": null,
        "execution_location": "LOCAL",
        "session_id": null,
        "session_link": null,
        "creator": null,
        "conversation_id": null,
        "request_usage": null,
        "is_sandbox_running": false
    });
    task[run_time_key] = run_time;
    task
}

#[test]
fn task_status_error_code_deserializes_public_api_casing() {
    let message: TaskStatusMessage = serde_json::from_str(
        "{\"message\":\"setup failed\",\"error_code\":\"environment_setup_failed\"}",
    )
    .unwrap();

    assert_eq!(
        message.error_code,
        Some(TaskStatusErrorCode::EnvironmentSetupFailed)
    );
}

#[test]
fn task_status_error_code_deserializes_graphql_casing() {
    let message: TaskStatusMessage = serde_json::from_str(
        "{\"message\":\"setup failed\",\"errorCode\":\"ENVIRONMENT_SETUP_FAILED\"}",
    )
    .unwrap();

    assert_eq!(
        message.error_code,
        Some(TaskStatusErrorCode::EnvironmentSetupFailed)
    );
}

#[test]
fn task_status_error_code_deserializes_unknown_codes() {
    let message: TaskStatusMessage =
        serde_json::from_str("{\"message\":\"failed\",\"error_code\":\"new_error\"}").unwrap();

    assert_eq!(message.error_code, Some(TaskStatusErrorCode::Unknown));
}

#[test]
fn ambient_agent_task_deserializes_run_time_iso8601() {
    let task: AmbientAgentTask =
        serde_json::from_value(task_json_with_run_time("run_time", json!("PT2M30S"))).unwrap();

    assert_eq!(task.run_time(), Some(Duration::seconds(150)));
    assert_eq!(task.execution_location, Some(ExecutionLocation::Local));
}

#[test]
fn ambient_agent_task_deserializes_and_totals_request_usage() {
    let mut task = task_json_with_run_time("run_time", json!("PT1S"));
    task["request_usage"] = json!({
        "inference_cost": 10.0,
        "compute_cost": 2.0,
        "platform_cost": 3.0,
        "inference_cost_usd": 0.18,
        "compute_cost_usd": 0.036,
        "platform_cost_usd": 0.054
    });

    let task: AmbientAgentTask = serde_json::from_value(task).unwrap();

    assert_eq!(task.credits_used(), Some(15.0));
    assert_eq!(task.cost_in_cents(), Some(27.0));
}

#[test]
fn ambient_agent_task_totals_available_request_usage_dollar_components() {
    let mut task = task_json_with_run_time("run_time", json!("PT1S"));
    task["request_usage"] = json!({
        "inference_cost_usd": 0.18
    });

    let task: AmbientAgentTask = serde_json::from_value(task).unwrap();

    assert_eq!(task.cost_in_cents(), Some(18.0));
}

#[test]
fn ambient_agent_task_has_no_dollar_cost_when_usd_fields_are_missing() {
    let mut task = task_json_with_run_time("run_time", json!("PT1S"));
    task["request_usage"] = json!({
        "inference_cost": 10.0,
        "compute_cost": 2.0,
        "platform_cost": 3.0
    });

    let task: AmbientAgentTask = serde_json::from_value(task).unwrap();

    assert_eq!(task.credits_used(), Some(15.0));
    assert_eq!(task.cost_in_cents(), None);
}

#[test]
fn ambient_agent_task_deserializes_github_webhook_source() {
    let mut task = task_json_with_run_time("run_time", json!("PT1S"));
    task["source"] = json!("GITHUB_WEBHOOK");

    let task: AmbientAgentTask = serde_json::from_value(task).unwrap();

    assert_eq!(task.source, Some(AgentSource::GitHubWebhook));
}

#[test]
fn ambient_agent_task_deserializes_orchestration_source() {
    let mut task = task_json_with_run_time("run_time", json!("PT1S"));
    task["source"] = json!("ORCHESTRATION");

    let task: AmbientAgentTask = serde_json::from_value(task).unwrap();

    assert_eq!(task.source, Some(AgentSource::Orchestration));
}
