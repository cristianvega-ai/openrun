//! Images and files staged in the input for the next CLI agent rich input submission.

use std::path::PathBuf;

use warpui::{Entity, ModelContext};

use crate::util::image::ImageContext;

/// A non-image file picked via the "attach file" button.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PendingFile {
    pub file_name: String,
    pub file_path: PathBuf,
    pub mime_type: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AttachmentType {
    Image,
    File,
}

/// A pending attachment: either an image (base64 in memory) or a file (path reference).
#[derive(Clone, Debug)]
pub enum PendingAttachment {
    Image(ImageContext),
    File(PendingFile),
}

impl PendingAttachment {
    pub fn file_name(&self) -> &str {
        match self {
            PendingAttachment::Image(img) => &img.file_name,
            PendingAttachment::File(file) => &file.file_name,
        }
    }

    pub fn attachment_type(&self) -> AttachmentType {
        match self {
            PendingAttachment::Image(_) => AttachmentType::Image,
            PendingAttachment::File(_) => AttachmentType::File,
        }
    }
}

#[derive(Default)]
pub struct PendingAttachmentsModel {
    attachments: Vec<PendingAttachment>,
}

impl PendingAttachmentsModel {
    pub fn attachments(&self) -> &[PendingAttachment] {
        &self.attachments
    }

    pub fn images(&self) -> Vec<&ImageContext> {
        self.attachments
            .iter()
            .filter_map(|attachment| match attachment {
                PendingAttachment::Image(image) => Some(image),
                PendingAttachment::File(_) => None,
            })
            .collect()
    }

    pub fn append(&mut self, attachments: Vec<PendingAttachment>, ctx: &mut ModelContext<Self>) {
        if !attachments.is_empty() {
            self.attachments.extend(attachments);
            ctx.emit(PendingAttachmentsEvent::Updated);
        }
    }

    pub fn append_images(&mut self, images: Vec<ImageContext>, ctx: &mut ModelContext<Self>) {
        self.append(
            images.into_iter().map(PendingAttachment::Image).collect(),
            ctx,
        );
    }

    pub fn remove(&mut self, index: usize, ctx: &mut ModelContext<Self>) {
        if index < self.attachments.len() {
            self.attachments.remove(index);
            ctx.emit(PendingAttachmentsEvent::Updated);
        }
    }

    pub fn clear_images(&mut self, ctx: &mut ModelContext<Self>) {
        let original_count = self.attachments.len();
        self.attachments
            .retain(|attachment| !matches!(attachment, PendingAttachment::Image(_)));
        if self.attachments.len() < original_count {
            ctx.emit(PendingAttachmentsEvent::Updated);
        }
    }
}

pub enum PendingAttachmentsEvent {
    Updated,
}

impl Entity for PendingAttachmentsModel {
    type Event = PendingAttachmentsEvent;
}
