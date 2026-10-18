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
) -> (Picture, Picture) {
    let cap = Some(Arc::new(Style::new(Colors::new(Some(Color::BLUE.into()), None, None))));
    let icon = Some(Arc::new(Style {
        enlarged_icon: true,
        ..Style::new(Colors::new(Some(Color::WHITE.into()), None, None))
    }));
    let ordinary = Some(Arc::new(Style::new(Colors::new(Some(Color::RED.into()), None, None))));
    let line = Line::from_test_cells(&["", "", "", " ", "x", " ", "│", " "]);
    let fragments = line.fragments().map(|mut fragment| {
        fragment.style = match fragment.text {
            "" => &icon,
            "" | "" | "│" => &cap,
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
        let (text, boxes) = record(&mut renderer, position, false);
        let old_order = raster(&text, &boxes, position, false);
        // Independent painter-order reference: the original enlarged glyph
        // picture over the original cap picture, at the original local X.
        let expected = raster(&text, &boxes, position, true);
        let (text, boxes) = record(&mut renderer, position, true);
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
                    ordinary_box |= actual[index].b() > 0;
                }
            }
        }
        assert!(recovered_edge, "test must expose the cap-over-icon clipping regression");
        assert!(ordinary_text && ordinary_box, "ordinary text and native box layer remain present");
    }
}
