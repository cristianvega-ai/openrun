use warpui_core::color::ColorU;
use warpui_core::elements::{CacheOption, Image, Text};
use warpui_core::geometry::vector::vec2f;
use warpui_core::text_layout::ClipConfig;
use warpui_core::{Element, SizeConstraint};

use super::{RenderContext, RenderableBlock};
use crate::extract_block;
use crate::render::element::paint::{CursorData, CursorDisplayType};
use crate::render::layout::HYPERLINK_COLOR;
use crate::render::model::viewport::ViewportItem;
use crate::render::model::{BlockItem, RenderState};

pub struct RenderableImage {
    viewport_item: ViewportItem,
    // TODO: The AssetCache does not currently support automatic eviction of assets when they are
    // dropped. We should consider implementing a mechanism to unload images when they are no longer
    // visible or referenced.
    image_element: Option<Box<dyn Element>>,
}

impl RenderableImage {
    pub fn new(viewport_item: ViewportItem) -> Self {
        Self {
            viewport_item,
            image_element: None,
        }
    }
}

impl RenderableBlock for RenderableImage {
    fn viewport_item(&self) -> &ViewportItem {
        &self.viewport_item
    }

    fn layout(
        &mut self,
        model: &RenderState,
        ctx: &mut warpui_core::LayoutContext,
        app: &warpui_core::AppContext,
    ) {
        let content = model.content();
        let (asset_source, alt_text, source, config) = extract_block!(
            self.viewport_item,
            content,
            (_block, BlockItem::Image { asset_source, alt_text, source, config }) => (asset_source.clone(), alt_text.clone(), source.clone(), *config)
        );

        let size = vec2f(config.width.as_f32(), config.height.as_f32());
        let constraint = SizeConstraint::new(vec2f(0., 0.), size);

        let Some(asset_source) = asset_source else {
            // Blocked sources (remote URLs, network shares) are never loaded. Show the alt text as a link
            // the user can click.
            let base_text = &model.styles().base_text;
            let label = if alt_text.trim().is_empty() {
                source
            } else {
                alt_text
            };
            let mut link = Text::new(label, base_text.font_family, base_text.font_size)
                .with_color(ColorU::from_u32(HYPERLINK_COLOR))
                .with_line_height_ratio(base_text.line_height_ratio)
                .with_clip(ClipConfig::ellipsis())
                .soft_wrap(false);
            link.layout(constraint, ctx, app);
            self.image_element = Some(Box::new(link));
            return;
        };

        let mut image = Image::new(asset_source, CacheOption::BySize)
            .contain()
            .first_frame_preview();
        image.layout(constraint, ctx, app);

        self.image_element = Some(Box::new(image));
    }

    fn paint(
        &mut self,
        model: &RenderState,
        ctx: &mut RenderContext,
        app: &warpui_core::AppContext,
    ) {
        let content = model.content();
        let positioned_image = extract_block!(
            self.viewport_item,
            content,
            (block, BlockItem::Image { config, .. }) => block.image(config)
        );

        let selected = model.offset_in_active_selection(positioned_image.start_char_offset);
        let draw_cursor = model.is_selection_head(positioned_image.start_char_offset);

        let content_position = positioned_image.content_origin();
        let screen_position = ctx.content_to_screen(content_position);
        let size = vec2f(
            positioned_image.item.width.as_f32(),
            positioned_image.item.height.as_f32(),
        );

        if let Some(ref mut image_element) = self.image_element {
            image_element.paint(screen_position, ctx.paint, app);
        }

        if selected {
            let rect_bounds = warpui_core::geometry::rect::RectF::new(screen_position, size);
            ctx.paint
                .scene
                .draw_rect_with_hit_recording(rect_bounds)
                .with_background(model.styles().selection_fill);
        }

        if draw_cursor {
            let end_of_line_position = content_position + vec2f(size.x(), 0.);
            ctx.draw_and_save_cursor(
                CursorDisplayType::Bar,
                end_of_line_position,
                vec2f(model.styles().cursor_width, size.y()),
                CursorData::default(),
                model.styles(),
            );
        }
    }
}
