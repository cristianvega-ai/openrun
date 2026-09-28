use super::*;

#[test]
fn duration_round_trip() {
    let d = Duration::from_secs(30);
    let file_val = d.to_file_value();
    assert_eq!(file_val, Value::Number(30.into()));
    let back = Duration::from_file_value(&file_val).unwrap();
    assert_eq!(back, d);
}

#[test]
fn vec_recursive() {
    let v = vec![10u32, 20u32];
    let file_val = v.to_file_value();
    assert_eq!(
        file_val,
        Value::Array(vec![Value::Number(10.into()), Value::Number(20.into())])
    );
    let back = Vec::<u32>::from_file_value(&file_val).unwrap();
    assert_eq!(back, v);
}

#[test]
fn option_some() {
    let v: Option<u32> = Some(5);
    let file_val = v.to_file_value();
    assert_eq!(file_val, Value::Number(5.into()));
    let back = Option::<u32>::from_file_value(&file_val).unwrap();
    assert_eq!(back, v);
}

#[test]
fn option_none() {
    let v: Option<u32> = None;
    let file_val = v.to_file_value();
    assert_eq!(file_val, Value::Null);
    let back = Option::<u32>::from_file_value(&file_val).unwrap();
    assert_eq!(back, v);
}

#[test]
fn bool_passthrough() {
    assert_eq!(true.to_file_value(), Value::Bool(true));
    assert_eq!(bool::from_file_value(&Value::Bool(false)), Some(false));
}

#[test]
fn string_passthrough() {
    let s = "hello".to_string();
    let file_val = s.to_file_value();
    assert_eq!(file_val, Value::String("hello".into()));
    assert_eq!(String::from_file_value(&file_val), Some(s));
}

#[test]
fn hashmap_round_trip() {
    let mut m = HashMap::new();
    m.insert("key".to_string(), 42u32);
    let file_val = m.to_file_value();
    let obj = file_val.as_object().unwrap();
    assert_eq!(obj.get("key"), Some(&Value::Number(42.into())));
    let back = HashMap::<String, u32>::from_file_value(&file_val).unwrap();
    assert_eq!(back, m);
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, serde::Deserialize)]
enum Kind {
    A,
    B,
}

impl SettingsValue for Kind {
    fn to_file_value(&self) -> Value {
        Value::String(format!("{self:?}").to_lowercase())
    }

    fn from_file_value(value: &Value) -> Option<Self> {
        match value.as_str()? {
            "a" => Some(Kind::A),
            "b" => Some(Kind::B),
            _ => None,
        }
    }
}

#[test]
fn lenient_vec_skips_unknown_entries_from_serde() {
    let parsed: LenientVec<Kind> = serde_json::from_str(r#"["A", "Removed", "B", 3]"#).unwrap();
    assert_eq!(parsed.0, vec![Kind::A, Kind::B]);
}

#[test]
fn lenient_vec_skips_unknown_entries_from_file_value() {
    let file_val = serde_json::json!(["a", "removed", "b"]);
    let parsed = LenientVec::<Kind>::from_file_value(&file_val).unwrap();
    assert_eq!(parsed.0, vec![Kind::A, Kind::B]);
    assert_eq!(parsed.to_file_value(), serde_json::json!(["a", "b"]));
}

#[test]
fn lenient_vec_rejects_non_lists() {
    assert!(serde_json::from_str::<LenientVec<Kind>>(r#"{"A": 1}"#).is_err());
    assert!(LenientVec::<Kind>::from_file_value(&serde_json::json!("a")).is_none());
}

#[test]
fn lenient_set_skips_unknown_entries() {
    let parsed: LenientSet<Kind> = serde_json::from_str(r#"["Removed", "B", "B"]"#).unwrap();
    assert_eq!(parsed.0, HashSet::from([Kind::B]));

    let file_val = serde_json::json!(["removed", "a"]);
    let parsed = LenientSet::<Kind>::from_file_value(&file_val).unwrap();
    assert_eq!(parsed.0, HashSet::from([Kind::A]));
}
