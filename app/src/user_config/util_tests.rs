use super::*;

#[test]
fn title_case_test() {
    assert_eq!("Test", title_case("test"));
    assert_eq!("Test", title_case("TEST"));
    assert_eq!("Test", title_case("Test"));
    assert_eq!("Zażółć", title_case("Zażółć"));
    assert_eq!("Zażółć", title_case("ZAŻÓŁĆ"));
}

#[test]
fn file_name_to_human_readable_name_test() {
    assert_eq!(
        "Solarized Dark",
        file_name_to_human_readable_name("solarized_dark")
    );
    assert_eq!(
        "Solarized Dark",
        file_name_to_human_readable_name("solarized_dark.yaml")
    );
    assert_eq!(
        "Solarized Dark",
        file_name_to_human_readable_name("SOLARIZED_DARK.yaml")
    );
    assert_eq!(
        "Solarizeddark",
        file_name_to_human_readable_name("solarizeddark.yaml")
    );
}

fn workflows_in_file(contents: &str) -> Option<Vec<Workflow>> {
    let dir = tempfile::tempdir().expect("tempdir should be created");
    fs::write(dir.path().join("workflows.yaml"), contents).expect("file should be written");
    let entry = WalkDir::new(dir.path())
        .into_iter()
        .filter_map(Result::ok)
        .find(|entry| entry.file_type().is_file())
        .expect("the workflow file should be listed");
    parse_multi_workflow_dir_entry(&entry)
}

#[test]
fn workflow_file_keeps_supported_workflows_next_to_a_removed_workflow_type() {
    let workflows = workflows_in_file(
        r#"---
name: List files
command: ls -la
---
type: agent_mode
name: Explain the diff
query: Explain the staged changes
---
name: Show status
command: git status
"#,
    )
    .expect("the file should be read");

    let names = workflows.iter().map(Workflow::name).collect_vec();
    assert_eq!(names, vec!["List files", "Show status"]);
}

#[test]
fn workflow_file_with_only_a_removed_workflow_type_yields_nothing() {
    let workflows = workflows_in_file(
        r#"type: agent_mode
name: Explain the diff
query: Explain the staged changes
"#,
    )
    .expect("the file should be read");

    assert!(workflows.is_empty());
}
