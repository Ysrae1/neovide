use std::sync::Arc;

use skia_safe::surfaces;

use super::*;
use crate::{
    editor::{Colors, Style},
    units::PixelSize,
    window::WindowSettings,
};

fn record(
    renderer: &mut GridRenderer,
    position: PixelPos<f32>,
    deferred: bool,
    title_caps: bool,
) -> (Picture, Picture) {
    let cap = Some(Arc::new(Style {
        avante_solid_cap: title_caps,
        ..Style::new(Colors::new(Some(Color::BLUE.into()), None, None))
    }));
    let icon = Some(Arc::new(Style {
        enlarged_icon: !title_caps,
        ..Style::new(Colors::new(Some(Color::WHITE.into()), None, None))
    }));
    let ordinary = Some(Arc::new(Style::new(Colors::new(Some(Color::RED.into()), None, None))));
    let line = Line::from_test_cells(&["", "", "", " ", "x", " ", "│", " "]);
    let fragments = line.fragments().map(|mut fragment| {
        fragment.style = match fragment.text {
            "" => &icon,
            "" | "" => &cap,
            "│" => &ordinary,
            _ => &ordinary,
        };
        fragment
    });
    let bounds = Rect::from_wh(renderer.grid_scale.width() * 8.0, renderer.grid_scale.height());
    let (mut text, mut boxes) = (PictureRecorder::new(), PictureRecorder::new());
    let text_canvas = text.begin_recording(bounds, false);
    let box_canvas = boxes.begin_recording(bounds.with_offset((position.x, 0.0)), false);
    if deferred {
        let drawn =
            draw_line_foreground(renderer, text_canvas, box_canvas, fragments, position, 1.0);
        assert_eq!(drawn, (true, true));
    } else {
        for fragment in fragments {
            renderer.draw_foreground(text_canvas, box_canvas, &fragment, position, 1.0);
        }
    }
    (
        text.finish_recording_as_picture(None).unwrap(),
        boxes.finish_recording_as_picture(None).unwrap(),
    )
}

fn raster(
    text: &Picture,
    boxes: &Picture,
    position: PixelPos<f32>,
    boxes_first: bool,
) -> Vec<Color> {
    let mut surface = surfaces::raster_n32_premul((144, 64)).unwrap();
    let canvas = surface.canvas();
    canvas.clear(Color::TRANSPARENT);
    let mut matrix = Matrix::new_identity();
    matrix.set_translate((-position.x, 0.0));
    if boxes_first {
        canvas.draw_picture(boxes, Some(&matrix), None);
        canvas.draw_picture(text, None, None);
    } else {
        canvas.draw_picture(text, None, None);
        canvas.draw_picture(boxes, Some(&matrix), None);
    }
    let pixels = surface.peek_pixels().unwrap();
    (0..64)
        .flat_map(|y| (0..144).map(move |x| (x, y)))
        .map(|point| pixels.get_color(point))
        .collect()
}

#[test]
fn enlarged_icon_overlays_caps_without_moving_ordinary_foreground() {
    let settings = Arc::new(Settings::new());
    settings.set(&RendererSettings::default());
    settings.set(&WindowSettings::default());
    // Use the bundled Nerd Font, independent of installed desktop families.
    let mut renderer = GridRenderer::new(3.0, settings);
    let cell = PixelSize::new(18.0, 64.0);
    renderer.grid_scale = GridScale::new(cell);
    renderer.box_char_renderer.update_dimensions(cell, renderer.shaper.current_size());
    for position in [PixelPos::ZERO, PixelPos::new(83.5, 47.0)] {
        let (text, boxes) = record(&mut renderer, position, false, false);
        let old_order = raster(&text, &boxes, position, false);
        // Independent painter-order reference: the original enlarged glyph
        // picture over the original cap picture, at the original local X.
        let expected = raster(&text, &boxes, position, true);
        let (text, boxes) = record(&mut renderer, position, true, false);
        let actual = raster(&text, &boxes, position, false);
        assert_eq!(actual, expected, "icon overlay or world/local X mismatch at {position:?}");
        let mut recovered_edge = false;
        let mut ordinary_text = false;
        let mut ordinary_box = false;
        for y in 0..64 {
            for x in 0..144 {
                let index = y * 144 + x;
                if x < 18 || (36..54).contains(&x) {
                    recovered_edge |= actual[index] != old_order[index];
                }
                if x >= 54 {
                    assert_eq!(
                        actual[index], old_order[index],
                        "ordinary foreground changed at ({x},{y})"
                    );
                    ordinary_text |= actual[index].r() > 0;
                    ordinary_box |= actual[index].r() > 0 && (108..126).contains(&x);
                }
            }
        }
        assert!(recovered_edge, "test must expose the cap-over-icon clipping regression");
        assert!(ordinary_text && ordinary_box, "ordinary text and native box layer remain present");
    }
}

#[test]
fn solid_title_caps_render_below_ordinary_logos_without_reordering_box_lines() {
    let settings = Arc::new(Settings::new());
    settings.set(&RendererSettings::default());
    settings.set(&WindowSettings::default());
    let mut renderer = GridRenderer::new(3.0, settings);
    let cell = PixelSize::new(18.0, 64.0);
    renderer.grid_scale = GridScale::new(cell);
    renderer.box_char_renderer.update_dimensions(cell, renderer.shaper.current_size());
    for position in [PixelPos::ZERO, PixelPos::new(83.5, 47.0)] {
        let (text, boxes) = record(&mut renderer, position, false, true);
        let old_order = raster(&text, &boxes, position, false);
        let expected = raster(&text, &boxes, position, true);
        let (text, boxes) = record(&mut renderer, position, true, true);
        let actual = raster(&text, &boxes, position, false);
        assert_eq!(actual, expected, "ordinary logo overlay mismatch at {position:?}");
        assert!(
            actual[..54 * 64] != old_order[..54 * 64],
            "test must expose a cap overlapping the ordinary logo"
        );
        for y in 0..64 {
            for x in 54..144 {
                let index = y * 144 + x;
                assert_eq!(
                    actual[index], old_order[index],
                    "unrelated text or box line changed at ({x},{y})"
                );
            }
        }
    }
}

fn reference_outline_pixels(
    renderer: &mut GridRenderer,
    styles: &[Option<Arc<Style>>; 8],
    position: PixelPos<f32>,
) -> Vec<Color> {
    // Alternating native shapes create separate cell fragments. Empty their
    // text afterwards so this measures only the decoration, without fonts.
    let line = Line::from_test_cells(&["│", "─", "│", "─", "│", "─", "│", "─"]);
    let fragments = line.fragments().enumerate().map(|(column, mut fragment)| {
        fragment.style = &styles[column];
        fragment.text = "";
        fragment
    });
    let bounds = Rect::from_wh(144.0, 64.0);
    let (mut text, mut boxes) = (PictureRecorder::new(), PictureRecorder::new());
    let text_canvas = text.begin_recording(bounds, false);
    let box_canvas = boxes.begin_recording(bounds.with_offset((position.x, 0.0)), false);
    draw_line_foreground(renderer, text_canvas, box_canvas, fragments, position, 0.2);
    raster(
        &text.finish_recording_as_picture(None).unwrap(),
        &boxes.finish_recording_as_picture(None).unwrap(),
        position,
        false,
    )
}

fn outlined_style(color: Color, alternate: bool) -> Option<Arc<Style>> {
    Some(Arc::new(
        Style {
            // Different syntax foregrounds and CursorLine backgrounds must
            // not add interior edges to one continuous reference range.
            blend: if alternate { 80 } else { 0 },
            ..Style::new(Colors::new(
                Some(if alternate { Color::RED.into() } else { Color::BLUE.into() }),
                alternate.then_some(Color::GRAY.into()),
                Some(color.into()),
            ))
        }
        .with_roles([crate::editor::HighlightRole::ReferenceOutline]),
    ))
}

#[test]
fn reference_outline_merges_style_fragments_and_stays_inside_grid_edges() {
    let settings = Arc::new(Settings::new());
    settings.set(&RendererSettings::default());
    settings.set(&WindowSettings::default());
    let mut renderer = GridRenderer::new(1.0, settings);
    renderer.grid_scale = GridScale::new(PixelSize::new(18.0, 64.0));
    let styles = std::array::from_fn(|column| match column {
        0..=3 => outlined_style(Color::GREEN, column % 2 == 0),
        4 => None,
        _ => outlined_style(Color::CYAN, column % 2 == 0),
    });
    for position in [PixelPos::ZERO, PixelPos::new(83.5, 47.0)] {
        let actual = reference_outline_pixels(&mut renderer, &styles, position);
        for y in 0..64 {
            for x in 0..144 {
                let expected = if x < 72 && (x == 0 || x == 71 || y == 0 || y == 63) {
                    Color::GREEN
                } else if x >= 90 && (x == 90 || x == 143 || y == 0 || y == 63) {
                    Color::CYAN
                } else {
                    Color::TRANSPARENT
                };
                assert_eq!(
                    actual[y * 144 + x],
                    expected,
                    "reference outline pixel ({x},{y}) at {position:?}"
                );
            }
        }
        let cleared = styles
            .clone()
            .map(|style| style.map(|style| Arc::new((*style).clone().with_roles([]))));
        assert!(
            reference_outline_pixels(&mut renderer, &cleared, position)
                .iter()
                .all(|color| *color == Color::TRANSPARENT),
            "removing the role must remove the whole outline"
        );
    }
}

#[test]
fn reference_outline_color_changes_start_a_separate_box() {
    let settings = Arc::new(Settings::new());
    settings.set(&RendererSettings::default());
    settings.set(&WindowSettings::default());
    let mut renderer = GridRenderer::new(1.0, settings);
    renderer.grid_scale = GridScale::new(PixelSize::new(18.0, 64.0));
    let styles = std::array::from_fn(|column| {
        outlined_style(if column < 4 { Color::GREEN } else { Color::CYAN }, false)
    });
    let actual = reference_outline_pixels(&mut renderer, &styles, PixelPos::ZERO);
    for y in 0..64 {
        assert_eq!(actual[y * 144 + 71], Color::GREEN);
        assert_eq!(actual[y * 144 + 72], Color::CYAN);
    }
}
