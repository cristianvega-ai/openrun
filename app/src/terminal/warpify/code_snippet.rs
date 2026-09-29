use warpui::elements::{
    Border, Container, CornerRadius, CrossAxisAlignment, Empty, Flex, MainAxisAlignment,
    MainAxisSize, MouseStateHandle, ParentElement, Radius, Text,
};
use warpui::ui_components::components::UiComponent;
use warpui::{AppContext, Element, EventContext, SingletonEntity};

use crate::appearance::Appearance;
use crate::terminal::shell::ShellType;
use crate::ui_components::blended_colors;
use crate::ui_components::buttons::icon_button;
use crate::ui_components::icons::Icon;

const CODE_BLOCK_CORNER_RADIUS: f32 = 8.0;
const CODE_BLOCK_HORIZONTAL_PADDING: f32 = 16.;
const CODE_BLOCK_VERTICAL_PADDING: f32 = 10.;
const CODE_BLOCK_FOOTER_PADDING_TOP: f32 = 6.;
const CODE_BLOCK_FOOTER_PADDING_BOTTOM: f32 = 12.;

#[derive(Default, Clone)]
pub struct CodeSnippetButtonHandles {
    pub copy_button: MouseStateHandle,
    pub run_button: MouseStateHandle,
}

pub type HandleCode = Box<dyn FnMut(String, &mut EventContext)>;

fn render_button<F>(
    appearance: &Appearance,
    icon: Icon,
    tooltip_text: &str,
    mouse_handle: MouseStateHandle,
    code: String,
    mut on_click: F,
) -> Container
where
    F: FnMut(String, &mut EventContext) + 'static,
{
    let ui_builder = appearance.ui_builder().clone();
    let tooltip_text = tooltip_text.to_owned();

    Container::new(
        icon_button(appearance, icon, false, mouse_handle)
            .with_tooltip(move || ui_builder.tool_tip(tooltip_text.clone()).build().finish())
            .build()
            .on_click(move |ctx, _, _| {
                on_click(code.clone(), ctx);
            })
            .finish(),
    )
}

/// Renders a code snippet in a bordered block with an optional shell label and copy and run
/// buttons.
pub fn render_runnable_code_snippet(
    code_snippet: &str,
    shell_type: Option<ShellType>,
    on_execute: Option<HandleCode>,
    on_copy: Option<HandleCode>,
    mouse_handles: Option<CodeSnippetButtonHandles>,
    app: &AppContext,
) -> Box<dyn Element> {
    let appearance = Appearance::as_ref(app);
    let theme = appearance.theme();

    let code_element = Text::new(
        code_snippet.to_owned(),
        appearance.monospace_font_family(),
        appearance.monospace_font_size(),
    )
    .with_color(blended_colors::text_main(theme, theme.surface_1()))
    .with_selectable(true)
    .finish();

    let shell_label = shell_type.map(|shell_type| {
        Text::new_inline(
            shell_type.name().to_owned(),
            appearance.monospace_font_family(),
            appearance.monospace_font_size(),
        )
        .with_color(blended_colors::text_sub(theme, theme.surface_3()))
        .finish()
    });

    let mut footer_row = Flex::row()
        .with_cross_axis_alignment(CrossAxisAlignment::Center)
        .with_main_axis_alignment(MainAxisAlignment::SpaceBetween)
        .with_main_axis_size(MainAxisSize::Max)
        .with_child(shell_label.unwrap_or_else(|| Empty::new().finish()));

    if let Some(mouse_handles) = mouse_handles {
        let mut action_row = Flex::row().with_cross_axis_alignment(CrossAxisAlignment::Center);
        let code = code_snippet.to_owned();

        if let Some(on_copy) = on_copy {
            action_row.add_child(
                render_button(
                    appearance,
                    Icon::Copy,
                    "Copy",
                    mouse_handles.copy_button,
                    code.clone(),
                    on_copy,
                )
                .finish(),
            );
        }

        if let Some(on_execute) = on_execute {
            action_row.add_child(
                render_button(
                    appearance,
                    Icon::TerminalInput,
                    "Run in terminal",
                    mouse_handles.run_button,
                    code,
                    on_execute,
                )
                .with_margin_left(8.)
                .finish(),
            );
        }

        footer_row.add_child(action_row.finish());
    }

    let content = Flex::column()
        .with_cross_axis_alignment(CrossAxisAlignment::Stretch)
        .with_child(
            Container::new(code_element)
                .with_background(theme.surface_2())
                .with_padding_top(CODE_BLOCK_VERTICAL_PADDING)
                .with_padding_bottom(CODE_BLOCK_VERTICAL_PADDING)
                .with_horizontal_padding(CODE_BLOCK_HORIZONTAL_PADDING)
                .with_corner_radius(CornerRadius::with_top(Radius::Pixels(
                    CODE_BLOCK_CORNER_RADIUS,
                )))
                .finish(),
        )
        .with_child(
            Container::new(footer_row.finish())
                .with_background(theme.surface_2())
                .with_padding_top(CODE_BLOCK_FOOTER_PADDING_TOP)
                .with_padding_bottom(CODE_BLOCK_FOOTER_PADDING_BOTTOM)
                .with_horizontal_padding(CODE_BLOCK_HORIZONTAL_PADDING)
                .with_corner_radius(CornerRadius::with_bottom(Radius::Pixels(
                    CODE_BLOCK_CORNER_RADIUS,
                )))
                .finish(),
        );

    Container::new(content.finish())
        .with_border(Border::all(1.).with_border_fill(theme.outline()))
        .with_corner_radius(CornerRadius::with_all(Radius::Pixels(
            CODE_BLOCK_CORNER_RADIUS,
        )))
        .finish()
}
