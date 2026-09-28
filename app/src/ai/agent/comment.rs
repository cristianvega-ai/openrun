use warp_multi_agent_api as api;

use super::{
    current_head_to_api_ref, current_head_to_diff_hunk_api, diff_base_to_api_ref,
    diff_base_to_diff_hunk_api,
};
use crate::code::buffer_location::LocalOrRemotePath;
use crate::code_review::comments::{AttachedReviewComment, AttachedReviewCommentTarget, CommentId};

/// The current state of a code review.
#[derive(Debug, Clone, Default)]
pub struct CodeReview {
    /// Comments that are currently pending (have yet to be addressed).
    pub pending_comments: Vec<ReviewComment>,
    /// Comments that have been addressed.
    pub addressed_comments: Vec<ReviewComment>,
}

impl CodeReview {
    pub fn new_with_pending_comments(pending_comments: Vec<ReviewComment>) -> Self {
        Self {
            pending_comments,
            ..Self::default()
        }
    }
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub struct ReviewComment {
    pub id: CommentId,
    pub content: String,
    pub diff: ReviewDiff,
    pub head_title: Option<String>,
}

impl ReviewComment {
    pub fn title(&self) -> String {
        match (&self.diff.file_path, self.diff.line_number) {
            (Some(file_path), Some(line_number)) => {
                let path_component = file_path.path_component();
                let file_name = path_component.file_name().unwrap_or("Invalid File Name");
                let display_line = line_number + 1;
                format!("{file_name}:{display_line}")
            }
            (Some(file_path), None) => {
                let path_component = file_path.path_component();
                let file_name = path_component.file_name().unwrap_or("Invalid File Name");
                file_name.to_string()
            }
            (None, _) => self
                .head_title
                .as_ref()
                .cloned()
                .unwrap_or_else(|| "Review Comment".to_string()),
        }
    }
}

impl From<crate::code_review::comments::AttachedReviewComment> for ReviewComment {
    fn from(comment: crate::code_review::comments::AttachedReviewComment) -> Self {
        let head_title = comment.head().map(|head| head.title());

        ReviewComment {
            id: comment.id,
            content: comment.content,
            diff: comment.target.into(),
            head_title,
        }
    }
}

/// Converts a code review comment into the multi-agent API representation.
pub fn attached_review_comment_to_api(val: AttachedReviewComment) -> api::ReviewComment {
    let head = val.head;
    let base = val.base;
    let comment_target = match val.target {
        AttachedReviewCommentTarget::Line {
            absolute_file_path,
            content,
            line,
        } => {
            // For now, comments are only attached to a single line.
            let line_range = line.line_number().map(|lc| {
                let line_number = lc.as_usize() as u32;
                api::FileContentLineRange {
                    start: line_number,
                    end: line_number + 1,
                }
            });

            api::review_comment::CommentTarget::CommentedLine(api::DiffHunk {
                // For the agent/GitHub API we send the path bytes only;
                // the comment's owning batch is already host-scoped.
                file_path: absolute_file_path.display_path(),
                line_range,
                diff_content: content.content,
                lines_added: content.lines_added.as_u32(),
                lines_removed: content.lines_removed.as_u32(),
                current: head.map(current_head_to_diff_hunk_api),
                base: base.map(diff_base_to_diff_hunk_api),
            })
        }
        AttachedReviewCommentTarget::File { absolute_file_path } => {
            api::review_comment::CommentTarget::CommentedFile(api::review_comment::CommentedFile {
                file_path: absolute_file_path.display_path(),
                current: head.map(current_head_to_api_ref),
                base: base.map(diff_base_to_api_ref),
            })
        }
        AttachedReviewCommentTarget::General => {
            api::review_comment::CommentTarget::CommentedDiffset(
                api::review_comment::CommentedDiffset {
                    current: head.map(current_head_to_api_ref),
                    base: base.map(diff_base_to_api_ref),
                },
            )
        }
    };

    api::ReviewComment {
        id: val.id.to_string(),
        comment: val.content,
        comment_target: Some(comment_target),
    }
}

impl From<crate::code_review::comments::AttachedReviewCommentTarget> for ReviewDiff {
    fn from(val: crate::code_review::comments::AttachedReviewCommentTarget) -> Self {
        // Convert from the server format of a line number (which is zero indexed)
        // to one that is one-indexed to display within the blocklist.
        match val {
            crate::code_review::comments::AttachedReviewCommentTarget::Line {
                absolute_file_path,
                line,
                content: _,
            } => {
                let line_number = line
                    .line_number()
                    .map(|line_number| line_number.as_usize() + 1);
                Self {
                    file_path: Some(absolute_file_path),
                    line_number,
                }
            }
            crate::code_review::comments::AttachedReviewCommentTarget::File {
                absolute_file_path,
            } => Self {
                file_path: Some(absolute_file_path),
                line_number: None,
            },
            crate::code_review::comments::AttachedReviewCommentTarget::General => Self {
                file_path: None,
                line_number: None,
            },
        }
    }
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub struct ReviewDiff {
    pub file_path: Option<LocalOrRemotePath>,
    pub line_number: Option<usize>,
}
