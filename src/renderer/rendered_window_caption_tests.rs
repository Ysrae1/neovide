use std::sync::Arc;

use skia_safe::surfaces;

use super::*;
use crate::{
    editor::{Colors, Style},
    window::WindowSettings,
};

fn caption_pixels(
    renderer: &mut GridRenderer,
    text: &str,
    centered: bool,
    light: bool,
) -> (Vec<Color>, usize, usize, f32, f32) {
    let mut strings = vec!["│".to_owned()];
    for ch in format!(" {text} ").chars() {
        strings.push(ch.to_string());
        if !ch.is_ascii() {
            strings.push(String::new());
        }
    }
    strings.push("│".into());
    let cells: Vec<&str> = strings.iter().map(String::as_str).collect();
    let line = Line::from_test_cells(&cells);
    let foreground = if light { Color::WHITE } else { Color::BLACK };
    let background =
        if light { Color::from_rgb(255, 82, 87) } else { Color::from_rgb(242, 143, 173) };
    let caption = Some(Arc::new(Style {
        centered_caption: centered,
        ..Style::new(Colors::new(Some(foreground.into()), Some(background.into()), None))
    }));
    let ordinary = Some(Arc::new(Style::new(Colors::new(
        Some(Color::BLUE.into()),
        Some(Color::GREEN.into()),
        None,
    ))));
    let width = (cells.len() as f32 * renderer.grid_scale.width()).ceil() as usize;
    let height = renderer.grid_scale.height().ceil() as usize;
    let mut surface = surfaces::raster_n32_premul((width as i32, height as i32)).unwrap();
    surface.canvas().clear(Color::TRANSPARENT);
    let fragments = || {
        line.fragments().map(|mut fragment| {
            fragment.style = if fragment.cells.start >= 1 && fragment.cells.end < cells.len() as u32
            {
                &caption
            } else {
                &ordinary
            };
            fragment
        })
    };
    for fragment in fragments() {
        renderer.draw_background(surface.canvas(), fragment.cells, fragment.style, 1.0);
    }
    // Native border shapes keep world-X alignment; captions use only the text canvas.
    let mut recorder = PictureRecorder::new();
    let boxes = recorder.begin_recording(Rect::from_wh(width as f32, height as f32), false);
    draw_line_foreground(renderer, surface.canvas(), boxes, fragments(), PixelPos::ZERO, 1.0);
    surface.canvas().draw_picture(&recorder.finish_recording_as_picture(None).unwrap(), None, None);
    let pixels = surface.peek_pixels().unwrap();
    let colors = (0..height)
        .flat_map(|y| (0..width).map(move |x| (x, y)))
        .map(|(x, y)| pixels.get_color((x as i32, y as i32)))
        .collect();
    (
        colors,
        width,
        height,
        renderer.grid_scale.width(),
        (cells.len() - 1) as f32 * renderer.grid_scale.width(),
    )
}

#[test]
fn centered_caption_raster_keeps_equal_ink_gaps_without_moving_background_or_borders() {
    let settings = Arc::new(Settings::new());
    settings.set(&RendererSettings::default());
    settings.set(&WindowSettings::default());
    let mut changed = false;
    for scale in [1.6, 2.0, 2.4] {
        let mut renderer = GridRenderer::new(scale, settings.clone());
        renderer.update_font("FiraCode Nerd Font Mono,PingFang SC:h16");
        for light in [true, false] {
            for text in ["文件", "buffer 列表", "Files", "ASCII title", "🔎 文件"] {
                let (old, width, height, left, right) =
                    caption_pixels(&mut renderer, text, false, light);
                let (actual, _, _, _, _) = caption_pixels(&mut renderer, text, true, light);
                let measurements = renderer.caption_raster_count;
                let (cached, _, _, _, _) = caption_pixels(&mut renderer, text, true, light);
                assert_eq!(cached, actual, "cached caption must preserve actual ink");
                assert_eq!(
                    renderer.caption_raster_count, measurements,
                    "unchanged title must not repeat CPU raster measurement"
                );
                changed |= actual != old;
                let background = if light {
                    Color::from_rgb(255, 82, 87)
                } else {
                    Color::from_rgb(242, 143, 173)
                };
                // Count pixels from the actual rasterized color boundary,
                // rather than a fractional grid edge between two pixels.
                let background_columns: Vec<_> = actual[..width]
                    .iter()
                    .enumerate()
                    .filter_map(|(x, color)| (*color == background).then_some(x))
                    .collect();
                let left_pixel = *background_columns.first().unwrap();
                let right_pixel = *background_columns.last().unwrap();
                let mut min = width;
                let mut max = 0;
                for y in 0..height {
                    for x in 0..width {
                        let color = actual[y * width + x];
                        let ink = (left_pixel..=right_pixel).contains(&x) && color != background;
                        if ink {
                            min = min.min(x);
                            max = max.max(x);
                        }
                        if (x as f32) < left || x as f32 >= right {
                            assert_eq!(
                                color,
                                old[y * width + x],
                                "outside caption changed: {text}, {scale}, {light}, {x},{y}"
                            );
                        }
                    }
                }
                assert!(min < max, "caption ink missing: {text}");
                let gaps = (min - left_pixel, right_pixel - max);
                eprintln!("caption raster {text:?} scale={scale} light={light} gaps={gaps:?}");
                assert!(
                    gaps.0.abs_diff(gaps.1) <= 1,
                    "unequal caption ink padding: {text}, {scale}, {light}, {gaps:?}"
                );
                assert!(gaps.0 > 0 && gaps.1 > 0, "caption ink clipped");
            }
        }
    }
    let before_scale = renderer_scale_cache_probe(&settings);
    assert!(before_scale, "font/scale changes invalidate measured ink");
    assert!(changed, "test must expose the original fallback/ink alignment");
}

fn renderer_scale_cache_probe(settings: &Arc<Settings>) -> bool {
    let mut renderer = GridRenderer::new(1.6, settings.clone());
    renderer.update_font("FiraCode Nerd Font Mono,PingFang SC:h16");
    caption_pixels(&mut renderer, "Files", true, true);
    let before_scale = renderer.caption_raster_count;
    renderer.handle_scale_factor_update(2.0);
    caption_pixels(&mut renderer, "Files", true, true);
    renderer.caption_raster_count > before_scale
}
