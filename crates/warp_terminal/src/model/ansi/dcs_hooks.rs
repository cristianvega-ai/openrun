//! This module defines the schema for DCS hooks sent from the shell to the Rust
//! app -- for example, the payloads sent from shell precmd and preexec.
use std::collections::HashSet;
use std::path::PathBuf;

use ordered_float::OrderedFloat;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Deserializer, Serialize};
use warp_core::command::ExitCode;

use crate::model::block::BlockId;
use crate::model::session::SessionId;

/// Indicates that the following JSON-encoded message is hex-encoded for Warp's lifecycle hooks.
/// In DCS, it is used as the final char in the DCS start sequence.
/// In OSC, it is used as the first parameter.
pub(super) const HEX_ENCODED_JSON_MARKER: char = 'd';

/// Indicates that the following JSON-encoded message is unencoded for Warp's lifecycle hooks.
/// In DCS, it is used as the final char in the DCS start sequence.
/// In OSC, it is used as the first parameter.
pub(super) const UNENCODED_JSON_MARKER: char = 'f';

/// Session IDs decoded from shell hook payloads.
///
/// These are optional at the schema layer because several hook structs implement
/// `Default`; `None` means the hook omitted the field, while `Some(0)` means the
/// hook explicitly carried the legacy/default session ID. The ANSI processor
/// rejects missing or unregistered IDs for hooks that require a registered session.
pub type HookSessionId = Option<u64>;

/// Enum representing all possible JSON payloads for Warp's DCS's.
///
/// Serialization derives the internally tagged form
/// (`{"hook": "...", "value": {...}}`). Deserialization is hand-written
/// below and must accept exactly that form; it avoids the generic buffering
/// machinery that serde generates for internally tagged enums.
#[derive(Serialize, Debug)]
#[allow(clippy::upper_case_acronyms)]
#[serde(tag = "hook")]
pub(super) enum DProtoHook {
    CommandFinished {
        value: CommandFinishedValue,
    },
    Precmd {
        value: PrecmdHookValue,
    },
    Preexec {
        value: PreexecValue,
    },
    Bootstrapped {
        // This is wrapped in an `Box` to suppress clippy's large-enum-variant warning, not because it
        // functionally needs to be wrapped in an `Box`.
        value: Box<BootstrappedValue>,
    },
    PreInteractiveSSHSession {
        value: PreInteractiveSSHSessionValue,
    },
    SSH {
        value: SSHValue,
    },
    InitShell {
        value: InitShellValue,
    },
    InputBuffer {
        value: InputBufferValue,
    },
    ExternalShellWidgetSelection {
        value: ExternalShellWidgetSelectionValue,
    },
    Clear {
        value: ClearValue,
    },
    InitSubshell {
        value: InitSubshellValue,
    },
    SourcedRcFileForWarp {
        value: SourcedRcFileForWarpValue,
    },
}

/// The variant names of [`DProtoHook`], used for unknown-variant errors.
const DPROTO_HOOK_VARIANTS: &[&str] = &[
    "CommandFinished",
    "Precmd",
    "Preexec",
    "Bootstrapped",
    "PreInteractiveSSHSession",
    "SSH",
    "InitShell",
    "InputBuffer",
    "ExternalShellWidgetSelection",
    "Clear",
    "InitSubshell",
    "SourcedRcFileForWarp",
];

/// The envelope shape of a serialized hook: the `hook` tag plus the `value`
/// payload, which is parsed once the tag is known.
#[derive(Deserialize)]
struct RawDProtoHook {
    hook: String,
    value: serde_json::Value,
}

/// Parses a buffered JSON value into a hook payload type.
fn parse_hook_value<T: DeserializeOwned, E: serde::de::Error>(
    value: serde_json::Value,
) -> Result<T, E> {
    serde_json::from_value(value).map_err(E::custom)
}

impl<'de> Deserialize<'de> for DProtoHook {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let raw = RawDProtoHook::deserialize(deserializer)?;
        Ok(match raw.hook.as_str() {
            "CommandFinished" => DProtoHook::CommandFinished {
                value: parse_hook_value::<_, D::Error>(raw.value)?,
            },
            "Precmd" => DProtoHook::Precmd {
                value: parse_hook_value::<_, D::Error>(raw.value)?,
            },
            "Preexec" => DProtoHook::Preexec {
                value: parse_hook_value::<_, D::Error>(raw.value)?,
            },
            "Bootstrapped" => DProtoHook::Bootstrapped {
                value: parse_hook_value::<_, D::Error>(raw.value)?,
            },
            "PreInteractiveSSHSession" => DProtoHook::PreInteractiveSSHSession {
                value: parse_hook_value::<_, D::Error>(raw.value)?,
            },
            "SSH" => DProtoHook::SSH {
                value: parse_hook_value::<_, D::Error>(raw.value)?,
            },
            "InitShell" => DProtoHook::InitShell {
                value: parse_hook_value::<_, D::Error>(raw.value)?,
            },
            "InputBuffer" => DProtoHook::InputBuffer {
                value: parse_hook_value::<_, D::Error>(raw.value)?,
            },
            "ExternalShellWidgetSelection" => DProtoHook::ExternalShellWidgetSelection {
                value: parse_hook_value::<_, D::Error>(raw.value)?,
            },
            "Clear" => DProtoHook::Clear {
                value: parse_hook_value::<_, D::Error>(raw.value)?,
            },
            "InitSubshell" => DProtoHook::InitSubshell {
                value: parse_hook_value::<_, D::Error>(raw.value)?,
            },
            "SourcedRcFileForWarp" => DProtoHook::SourcedRcFileForWarp {
                value: parse_hook_value::<_, D::Error>(raw.value)?,
            },
            unknown => {
                return Err(serde::de::Error::unknown_variant(
                    unknown,
                    DPROTO_HOOK_VARIANTS,
                ));
            }
        })
    }
}

impl DProtoHook {
    pub fn name(&self) -> &'static str {
        match self {
            DProtoHook::CommandFinished { .. } => "CommandFinished",
            DProtoHook::Precmd { .. } => "Precmd",
            DProtoHook::Preexec { .. } => "Preexec",
            DProtoHook::Bootstrapped { .. } => "Bootstrapped",
            DProtoHook::PreInteractiveSSHSession { .. } => "PreInteractiveSSHSession",
            DProtoHook::SSH { .. } => "SSH",
            DProtoHook::InitShell { .. } => "InitShell",
            DProtoHook::InputBuffer { .. } => "InputBuffer",
            DProtoHook::ExternalShellWidgetSelection { .. } => "ExternalShellWidgetSelection",
            DProtoHook::Clear { .. } => "Clear",
            DProtoHook::InitSubshell { .. } => "InitSubshell",
            DProtoHook::SourcedRcFileForWarp { .. } => "SourcedRcFileForWarp",
        }
    }

    /// Extracts the session_id from whichever variant carries it. Returns `None`
    /// for hook types that don't (yet) include a session_id field.
    pub fn session_id(&self) -> Option<SessionId> {
        match self {
            DProtoHook::InitShell { value } => Some(value.session_id),
            DProtoHook::Precmd { value } => value.session_id().map(SessionId::from),
            DProtoHook::Preexec { value } => value.session_id.map(SessionId::from),
            DProtoHook::CommandFinished { value } => value.session_id.map(SessionId::from),
            DProtoHook::Bootstrapped { value } => value.session_id.map(SessionId::from),
            DProtoHook::InputBuffer { value } => value.session_id.map(SessionId::from),
            DProtoHook::ExternalShellWidgetSelection { value } => {
                value.session_id.map(SessionId::from)
            }
            DProtoHook::Clear { value } => value.session_id.map(SessionId::from),
            DProtoHook::PreInteractiveSSHSession { value } => value.session_id.map(SessionId::from),
            DProtoHook::SSH { value } => value.session_id.map(SessionId::from),
            DProtoHook::InitSubshell { value } => value.session_id.map(SessionId::from),
            DProtoHook::SourcedRcFileForWarp { .. } => None,
        }
    }

    /// Returns whether this hook mutates terminal/session state enough to require a recognized
    /// session_id before dispatch.
    pub fn requires_registered_session(&self) -> bool {
        match self {
            DProtoHook::CommandFinished { .. }
            | DProtoHook::Precmd { .. }
            | DProtoHook::Preexec { .. }
            | DProtoHook::Bootstrapped { .. }
            | DProtoHook::PreInteractiveSSHSession { .. }
            | DProtoHook::SSH { .. }
            | DProtoHook::InitShell { .. }
            | DProtoHook::InputBuffer { .. }
            | DProtoHook::ExternalShellWidgetSelection { .. }
            | DProtoHook::Clear { .. }
            | DProtoHook::InitSubshell { .. } => true,
            DProtoHook::SourcedRcFileForWarp { .. } => false,
        }
    }
}

/// Payload with completion metadata received from the PTY at precmd.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct PrecmdValue {
    #[serde(flatten)]
    pub completion_metadata: CompletionMetadata,
    #[serde(flatten)]
    pub prompt_metadata: PromptMetadata,
}

/// A decoded precmd payload, classified according to its completion evidence.
#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
#[serde(untagged)]
pub(super) enum PrecmdHookValue {
    WithCompletionMetadata(PrecmdValue),
    PromptOnly(PromptMetadata),
}

impl PrecmdHookValue {
    fn session_id(&self) -> HookSessionId {
        match self {
            Self::WithCompletionMetadata(value) => value.prompt_metadata.session_id,
            Self::PromptOnly(value) => value.session_id,
        }
    }
}

#[derive(Debug, Default, Deserialize)]
struct RawPrecmdValue {
    #[serde(flatten)]
    prompt_metadata: PromptMetadata,
    #[serde(default)]
    exit_code: RawPrecmdField<ExitCode>,
    #[serde(default)]
    next_block_id: RawPrecmdField<BlockId>,
}

#[derive(Debug, Default)]
enum RawPrecmdField<T> {
    #[default]
    Missing,
    Present(Option<T>),
}

impl<'de, T> Deserialize<'de> for RawPrecmdField<T>
where
    T: Deserialize<'de>,
{
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        Option::<T>::deserialize(deserializer).map(Self::Present)
    }
}

impl RawPrecmdValue {
    fn classify(self) -> Result<PrecmdHookValue, &'static str> {
        match (self.exit_code, self.next_block_id) {
            (
                RawPrecmdField::Present(Some(exit_code)),
                RawPrecmdField::Present(Some(next_block_id)),
            ) => Ok(PrecmdHookValue::WithCompletionMetadata(PrecmdValue {
                completion_metadata: CompletionMetadata {
                    exit_code,
                    next_block_id,
                },
                prompt_metadata: self.prompt_metadata,
            })),
            (RawPrecmdField::Missing, RawPrecmdField::Missing) => {
                Ok(PrecmdHookValue::PromptOnly(self.prompt_metadata))
            }
            _ => Err("Precmd payload must contain both exit_code and next_block_id"),
        }
    }
}

impl<'de> Deserialize<'de> for PrecmdHookValue {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        RawPrecmdValue::deserialize(deserializer)?
            .classify()
            .map_err(serde::de::Error::custom)
    }
}

/// Received from the pty when a command has finished executing.
#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
pub struct CompletionMetadata {
    pub exit_code: ExitCode,
    pub next_block_id: BlockId,
}

/// Received from the pty when a command has finished executing.
#[derive(Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
pub struct CommandFinishedValue {
    #[serde(flatten)]
    pub completion_metadata: CompletionMetadata,
    #[serde(default)]
    pub session_id: HookSessionId,
}
/// Prompt and shell context received from the pty at precmd.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct PromptMetadata {
    #[serde(deserialize_with = "empty_string_is_none", default)]
    pub pwd: Option<String>,

    #[serde(deserialize_with = "empty_string_is_none", default)]
    pub ps1: Option<String>,

    pub ps1_is_encoded: Option<bool>,

    pub honor_ps1: Option<bool>,

    #[serde(deserialize_with = "empty_string_is_none", default)]
    pub rprompt: Option<String>,

    #[serde(deserialize_with = "empty_string_is_none", default)]
    pub git_head: Option<String>,

    #[serde(deserialize_with = "empty_string_is_none", default)]
    pub git_branch: Option<String>,

    #[serde(deserialize_with = "empty_string_is_none", default)]
    pub virtual_env: Option<String>,

    #[serde(deserialize_with = "empty_string_is_none", default)]
    pub conda_env: Option<String>,

    #[serde(deserialize_with = "empty_string_is_none", default)]
    pub node_version: Option<String>,

    #[serde(deserialize_with = "empty_string_is_none", default)]
    pub kube_config: Option<String>,

    pub session_id: HookSessionId,

    /// Whether this prompt metadata was emitted after the completion of an in-band command.
    #[serde(default)]
    pub is_after_in_band_command: bool,
}

impl PromptMetadata {
    /// Returns `true` if this prompt metadata was emitted after the completion of an in-band command.
    ///
    /// This relies on the assumption that the warp_precmd shell function (responsible for writing
    /// this to the PTY from the shell) does not populate `pwd` or `ps1` when the previous command
    /// was an in-band command; for all other cases these fields should always be populated.
    pub fn was_sent_after_in_band_command(&self) -> bool {
        self.is_after_in_band_command || (self.pwd.is_none() && self.ps1.is_none())
    }
}

impl Default for PromptMetadata {
    fn default() -> Self {
        Self {
            pwd: Default::default(),
            ps1: Default::default(),
            // By default, we assume that we are using hex-encoding.
            ps1_is_encoded: Some(true),
            honor_ps1: Default::default(),
            rprompt: Default::default(),
            git_head: Default::default(),
            git_branch: Default::default(),
            virtual_env: Default::default(),
            conda_env: Default::default(),
            node_version: Default::default(),
            kube_config: Default::default(),
            session_id: Default::default(),
            is_after_in_band_command: Default::default(),
        }
    }
}

/// Received from the pty at preexec.
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct PreexecValue {
    /// The command for which this preexec hook is emitted.
    ///
    /// For Bash specifically, this command may not be the entire command string (it will only
    /// include up to the first job control indicator, e.g. '|', '&&'). This is due to a
    /// shortcoming of the bash_preexec library we use to simulate preexec hooks in bash.
    pub command: String,
    #[serde(default)]
    pub session_id: HookSessionId,
}

/// Received from the pty after the shell has finished executing Warp's
/// bootstrap script.
///
/// Deserialization is hand-written through [`RawBootstrappedValue`] below,
/// which applies the per-field string conversions in one place instead of
/// through per-field `deserialize_with` wrappers.
#[derive(Clone, Debug, Default, Serialize, PartialEq, Eq)]
pub struct BootstrappedValue {
    pub session_id: HookSessionId,

    pub histfile: Option<String>,

    pub shell: String,

    pub home_dir: Option<String>,

    pub path: Option<String>,

    /// `CDPATH` from the shell, colon-separated.
    pub cdpath: Option<String>,

    pub editor: Option<String>,

    pub aliases: Option<String>,

    pub abbreviations: Option<String>,

    pub function_names: Option<String>,

    pub env_var_names: Option<String>,

    pub builtins: Option<String>,

    pub keywords: Option<String>,

    pub shell_version: Option<String>,

    /// A list of options enabled for the shell by the end of bootstrap.  Will
    /// be None if the shell doesn't support listing options via builtin.
    pub shell_options: Option<HashSet<String>>,

    /// The time at which we started sourcing the user rcfiles, measured in
    /// seconds since epoch.
    pub rcfiles_start_time: Option<OrderedFloat<f64>>,

    /// The time at which we finished sourcing the user rcfiles, measured in
    /// seconds since epoch.
    pub rcfiles_end_time: Option<OrderedFloat<f64>>,

    /// Tags for known shell configurations/plugins, especially ones that are
    /// incompatible with Warp.
    pub shell_plugins: Option<HashSet<String>>,

    /// Whether the shell's native vi mode implementation is on.
    pub vi_mode_enabled: Option<String>,

    /// The operating system category (e.g. MacOS, Linux, Windows).
    pub os_category: Option<String>,

    pub linux_distribution: Option<String>,

    /// The full path to the running shell binary (e.g. "/usr/bin/zsh").
    pub shell_path: Option<String>,
}

/// An optional string field of [`RawBootstrappedValue`]. It distinguishes a
/// missing field from a present string, so the conversions below can mirror
/// the `#[serde(default)]` behavior of the former derived deserializer.
#[derive(Debug, Default)]
enum RawBootstrappedField {
    #[default]
    Missing,
    Present(String),
}

impl<'de> Deserialize<'de> for RawBootstrappedField {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        String::deserialize(deserializer).map(Self::Present)
    }
}

impl RawBootstrappedField {
    /// Mirrors the `empty_string_is_none` field deserializer, with a missing
    /// field mapping to `None`.
    fn empty_string_to_none(self) -> Option<String> {
        match self {
            Self::Missing => None,
            Self::Present(s) => empty_string_to_none(s),
        }
    }

    /// Mirrors the `trim_null_byte_deserializer` field deserializer, with a
    /// missing field mapping to an empty string.
    fn trimmed(self) -> String {
        match self {
            Self::Missing => String::new(),
            Self::Present(s) => trim_null_byte(s),
        }
    }

    /// Mirrors the former `parse_shell_options_list_deserializer` field
    /// deserializer, with a missing field mapping to `None`.
    fn shell_options(self) -> Option<HashSet<String>> {
        match self {
            Self::Missing => None,
            Self::Present(s) => Some(parse_shell_options_list(s)),
        }
    }

    /// Mirrors the former `parse_float_from_string_deserializer` field
    /// deserializer, with a missing field mapping to `None`. A non-empty
    /// string that does not parse as a float is an error, exactly as in the
    /// former field deserializer.
    fn float_from_string<E: serde::de::Error>(self) -> Result<Option<OrderedFloat<f64>>, E> {
        match self {
            Self::Missing => Ok(None),
            Self::Present(s) => {
                if s.is_empty() {
                    return Ok(None);
                }
                Ok(Some(s.parse::<f64>().map_err(E::custom)?.into()))
            }
        }
    }
}

/// The raw wire shape of [`BootstrappedValue`]. Fields without a
/// `#[serde(default)]` attribute are required, exactly as in the former
/// derived deserializer.
#[derive(Deserialize)]
struct RawBootstrappedValue {
    #[serde(default)]
    session_id: HookSessionId,
    histfile: String,
    #[serde(default)]
    shell: RawBootstrappedField,
    home_dir: String,
    path: String,
    #[serde(default)]
    cdpath: RawBootstrappedField,
    #[serde(default)]
    editor: RawBootstrappedField,
    aliases: String,
    abbreviations: String,
    function_names: String,
    env_var_names: String,
    builtins: String,
    keywords: String,
    shell_version: String,
    #[serde(default)]
    shell_options: RawBootstrappedField,
    #[serde(default)]
    rcfiles_start_time: RawBootstrappedField,
    #[serde(default)]
    rcfiles_end_time: RawBootstrappedField,
    #[serde(default)]
    shell_plugins: RawBootstrappedField,
    #[serde(default)]
    vi_mode_enabled: RawBootstrappedField,
    #[serde(default)]
    os_category: RawBootstrappedField,
    #[serde(default)]
    linux_distribution: RawBootstrappedField,
    #[serde(default)]
    shell_path: RawBootstrappedField,
}

impl<'de> Deserialize<'de> for BootstrappedValue {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let raw = RawBootstrappedValue::deserialize(deserializer)?;
        Ok(Self {
            session_id: raw.session_id,
            histfile: empty_string_to_none(raw.histfile),
            shell: raw.shell.trimmed(),
            home_dir: empty_string_to_none(raw.home_dir),
            path: empty_string_to_none(raw.path),
            cdpath: raw.cdpath.empty_string_to_none(),
            editor: raw.editor.empty_string_to_none(),
            aliases: empty_string_to_none(raw.aliases),
            abbreviations: empty_string_to_none(raw.abbreviations),
            function_names: empty_string_to_none(raw.function_names),
            env_var_names: empty_string_to_none(raw.env_var_names),
            builtins: empty_string_to_none(raw.builtins),
            keywords: empty_string_to_none(raw.keywords),
            shell_version: empty_string_to_none(raw.shell_version),
            shell_options: raw.shell_options.shell_options(),
            rcfiles_start_time: raw.rcfiles_start_time.float_from_string()?,
            rcfiles_end_time: raw.rcfiles_end_time.float_from_string()?,
            shell_plugins: raw.shell_plugins.shell_options(),
            vi_mode_enabled: raw.vi_mode_enabled.empty_string_to_none(),
            os_category: raw.os_category.empty_string_to_none(),
            linux_distribution: raw.linux_distribution.empty_string_to_none(),
            shell_path: raw.shell_path.empty_string_to_none(),
        })
    }
}

/// Received from the pty when Warp's SSH wrapper is executed, prior to
/// bootstrapping the SSH session.
#[derive(Debug, Default, PartialEq, Eq, Deserialize, Serialize, Clone)]
pub struct PreInteractiveSSHSessionValue {
    #[serde(default)]
    pub session_id: HookSessionId,
}

/// Received from the pty after establishing an SSH connection, prior to
/// bootstrapping the session.
#[derive(Debug, Default, PartialEq, Eq, Deserialize, Serialize, Clone)]
pub struct SSHValue {
    pub socket_path: PathBuf,
    pub remote_shell: String,
    #[serde(default)]
    pub session_id: HookSessionId,
    #[serde(default)]
    pub remote_session_id: HookSessionId,
    /// `true` when `socket_path` points at a ControlMaster the user already
    /// had running (the wrapper attached to it instead of creating its own).
    /// Warp must not tear down such a master on session exit. Defaults to
    /// `false` for hooks emitted by older bootstrap scripts.
    #[serde(default)]
    pub external_control_master: bool,
}

/// Received from the pty after the shell session has been initialized, marking
/// the shell ready to execute the bootstrap script.
#[derive(Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
pub struct InitShellValue {
    pub session_id: SessionId,

    pub shell: String,

    #[serde(default)]
    pub is_subshell: bool,

    #[serde(deserialize_with = "trim_null_byte_deserializer", default)]
    pub user: String,

    #[serde(deserialize_with = "trim_null_byte_deserializer", default)]
    pub hostname: String,
}

/// Emitted as part of the subshell bootstrapping process, before the shell type is known
/// to the client.
#[derive(Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
pub struct InitSubshellValue {
    pub shell: String,
    pub uname: Option<String>,
    #[serde(default)]
    pub session_id: HookSessionId,
}

/// Emitted by a snippet included in the user's RC file, which signals a new session is being
/// created; if the session is for a subshell, this triggers Warp's bootstrap process.
/// Otherwise, it's ignored.
///
/// NOTE: snippets installed by older Warp versions may also include a `tmux` field; serde
/// ignores unknown fields, so it is simply dropped now that the tmux SSH flow is removed.
#[derive(Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
pub struct SourcedRcFileForWarpValue {
    pub shell: String,
    pub uname: Option<String>,
}

/// Received from the pty via a shell line editor hook, whether readline (bash),
/// ZLE, or the fish [command line editor](https://fishshell.com/docs/current/interactive.html#command-line-editor).
/// The binding is triggered when Warp writes the `ESC-i` escape sequence to the pty.
/// Warp usually does this after a block completes, to collect any typeahead
/// that the user entered while the block was running (see
/// [`TerminalView::request_input_buffer`]).
#[derive(Debug, Default, PartialEq, Eq, Clone, Deserialize, Serialize)]
pub struct InputBufferValue {
    pub buffer: String,
    #[serde(default)]
    pub session_id: HookSessionId,
}

/// Selection reported by an external shell widget (ctrl-r history or ctrl-t file search).
/// Empty `buffer` means the user cancelled.
#[derive(Default, Clone, PartialEq, Eq, Deserialize, Serialize)]
pub struct ExternalShellWidgetSelectionValue {
    pub buffer: String,
    #[serde(default)]
    pub session_id: HookSessionId,
}

impl std::fmt::Debug for ExternalShellWidgetSelectionValue {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ExternalShellWidgetSelectionValue")
            .field("buffer", &"<redacted>")
            .field("session_id", &self.session_id)
            .finish()
    }
}

/// Received from the pty when the terminal screen should be cleared (e.g. via
/// the `clear` command or ctrl-l).
#[derive(Debug, Default, Deserialize, Serialize)]
pub struct ClearValue {
    #[serde(default)]
    pub session_id: HookSessionId,
}

/// Custom serde deserializer that trims trailing null bytes.
fn trim_null_byte_deserializer<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    let trimmed = trim_null_byte(s);
    Ok(trimmed)
}

fn trim_null_byte(s: String) -> String {
    s.trim().trim_end_matches(char::from(0)).to_owned()
}

/// Custom serde deserializer that maps empty strings to none.
fn empty_string_is_none<'de, D>(deserializer: D) -> Result<Option<String>, D::Error>
where
    D: Deserializer<'de>,
{
    Ok(empty_string_to_none(String::deserialize(deserializer)?))
}

/// Trims the string and maps an empty result to `None`.
fn empty_string_to_none(s: String) -> Option<String> {
    let trimmed = trim_null_byte(s);
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed)
    }
}

fn parse_shell_options_list(s: String) -> HashSet<String> {
    s.split_whitespace()
        .filter(|s| !s.is_empty())
        .map(Into::into)
        .collect()
}

#[cfg(test)]
#[path = "dcs_hooks_tests.rs"]
mod tests;
