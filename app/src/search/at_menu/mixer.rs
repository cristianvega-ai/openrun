use crate::search::mixer::SearchMixer;

pub type AtMenuMixer = SearchMixer<AtMenuSearchableAction>;

#[derive(Debug, Clone, PartialEq)]
pub enum AtMenuSearchableAction {
    InsertFilePath {
        /// This is the file path relative to the root of the current git
        /// repository. If this changes, this could break how we resolve
        /// the file path, so just note the downstream dependencies.
        file_path: String,
    },
    InsertText {
        /// Text to insert into the input buffer.
        text: String,
    },
}
