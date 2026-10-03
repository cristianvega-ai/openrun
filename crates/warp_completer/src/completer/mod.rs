mod coalesce;
mod context;
mod describe;
mod engine;
mod matchers;
mod suggest;
pub use suggest::alias::*;

#[cfg(feature = "test-util")]
pub mod testing;

pub use context::{
    CommandExitStatus, CommandOutput, CompletionContext, Containment, GIT_VERSION_COMMAND,
    GeneratorContext, GitVersion, MAIN_PATH_SEPARATOR, MINIMUM_GIT_VERSION, PATH_SEPARATORS,
    PathCompletionContext,
};
pub use describe::{Description, TopLevelCommandCaseSensitivity, describe, describe_given_token};
pub use engine::{EngineDirEntry, EngineFileType, LocationType};
pub use matchers::{Match, MatchStrategy, MatchType};
pub use suggest::{
    CompleterOptions, CompletionsFallbackStrategy, ExplicitTabCompletion, MatchedSuggestion,
    PreparedSuggestion, Priority, Suggestion, SuggestionResults, SuggestionType,
    SuggestionTypeName, suggestions,
};
