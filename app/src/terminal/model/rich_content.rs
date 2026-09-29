#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
/// Because it's hard to identify the contents of rich content blocks,
/// we register unique identifiers to make it easier to identify them.
pub enum RichContentType {
    AIBlock,
    WarpifySuccessBlock,
}

impl RichContentType {
    pub fn is_ai_block(&self) -> bool {
        matches!(self, Self::AIBlock)
    }
}
