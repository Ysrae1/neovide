use std::sync::Arc;

use skia_safe::{Color, Paint, Rect, surfaces};

use super::*;
use crate::{editor::Colors, units::PixelSize};

fn renderer_with_root(background: Color) -> Renderer {
    let settings = Arc::new(Settings::new());
    settings.register::<WindowSettings>();
    settings.register::<RendererSettings>();
    let mut renderer = Renderer::new(1.0, Config::default(), settings);
    renderer.grid_renderer.grid_scale = GridScale::new(PixelSize::new(8.0, 16.0));
    renderer.grid_renderer.default_style =
        Arc::new(Style::new(Colors::new(None, Some(background.into()), None)));
    let mut root = RenderedWindow::new(1);
    root.handle_window_draw_command(WindowDrawCommand::Position {
        grid_position: (1.0, 0.5),
        grid_size: (4, 2),
        anchor_info: None,
        window_type: WindowType::Editor,
    });
    root.grid_current_position = GridPos::new(1.0, 0.5);
    renderer.rendered_windows.insert(1, root);
    renderer
}

#[test]
fn bottom_margin_material_replaces_alpha_without_extending_statusline_or_padding() {
    let settings = WindowSettings {
        normal_opacity: 0.85,
        opacity: 0.75,
        bottom_margin_opacity: Some(0.20).into(),
        ..WindowSettings::default()
    };
    let content = PixelRect::from_min_max((8.0, 8.0), (43.0, 47.0));
    for normal in [Color::from_rgb(40, 80, 120), Color::from_rgb(240, 240, 240)] {
        let renderer = renderer_with_root(normal);
        let mut surface = surfaces::raster_n32_premul((55, 55)).unwrap();
        let ordinary = renderer.grid_renderer.get_default_background(settings.normal_opacity);
        surface.canvas().clear(ordinary);
        // Two differently colored segments represent the last complete status
        // line. Neither segment can leak into the independent material strip.
        let mut paint = Paint::default();
        paint.set_color(Color::RED);
        surface.canvas().draw_rect(Rect::new(8.0, 24.0, 24.0, 40.0), &paint);
        paint.set_color(Color::CYAN);
        surface.canvas().draw_rect(Rect::new(24.0, 24.0, 43.0, 40.0), &paint);
        renderer.draw_bottom_margin_background(surface.canvas(), Some(&content), &settings);

        let pixels = surface.peek_pixels().unwrap();
        assert_eq!(pixels.get_color((12, 39)), Color::RED);
        assert_eq!(pixels.get_color((42, 39)), Color::CYAN, "right remainder stays unchanged");
        for y in 40..47 {
            for x in 8..43 {
                let actual = pixels.get_color((x, y));
                assert!((actual.a() as f32 - 255.0 * 0.20 * 0.75).abs() <= 1.0);
                for (actual, expected) in
                    [(actual.r(), normal.r()), (actual.g(), normal.g()), (actual.b(), normal.b())]
                {
                    assert!((i16::from(actual) - i16::from(expected)).abs() <= 4);
                }
            }
        }
        let preserved = pixels.get_color((0, 0));
        for point in [(7, 42), (43, 42), (12, 47), (12, 8)] {
            assert_eq!(pixels.get_color(point), preserved, "padding and editor at {point:?}");
        }
        assert_eq!(preserved.a(), ordinary.a(), "normal_opacity remains independent");
    }
}

#[test]
fn bottom_margin_disabled_or_invalid_values_preserve_the_original_pixels() {
    let renderer = renderer_with_root(Color::WHITE);
    let content = PixelRect::from_min_max((8.0, 8.0), (43.0, 47.0));
    assert_eq!(WindowSettings::default().bottom_margin_opacity.0, None);
    for (bottom_margin_opacity, opacity) in
        [(None, 1.0), (Some(f32::NAN), 1.0), (Some(f32::INFINITY), 1.0), (Some(0.2), f32::NAN)]
    {
        let settings = WindowSettings {
            bottom_margin_opacity: bottom_margin_opacity.into(),
            opacity,
            ..WindowSettings::default()
        };
        let mut surface = surfaces::raster_n32_premul((55, 55)).unwrap();
        surface.canvas().clear(Color::MAGENTA);
        let before = surface.peek_pixels().unwrap().bytes().unwrap().to_vec();
        renderer.draw_bottom_margin_background(surface.canvas(), Some(&content), &settings);
        assert_eq!(surface.peek_pixels().unwrap().bytes().unwrap(), before);
    }

    for (value, alpha) in [(-1.0, 0), (2.0, 255)] {
        let settings = WindowSettings {
            bottom_margin_opacity: Some(value).into(),
            ..WindowSettings::default()
        };
        let mut surface = surfaces::raster_n32_premul((55, 55)).unwrap();
        surface.canvas().clear(Color::MAGENTA);
        renderer.draw_bottom_margin_background(surface.canvas(), Some(&content), &settings);
        assert_eq!(surface.peek_pixels().unwrap().get_color((12, 42)).a(), alpha);
    }
}

#[test]
fn bottom_margin_only_uses_the_visible_global_grid_and_a_fractional_gap() {
    let settings =
        WindowSettings { bottom_margin_opacity: Some(0.2).into(), ..WindowSettings::default() };
    let mut renderer = renderer_with_root(Color::WHITE);
    // A normal split reaching farther down is deliberately irrelevant. The
    // global grid, rather than the last rendered split or float, owns the gap.
    let mut split = RenderedWindow::new(2);
    split.grid_size = GridSize::new(4, 20);
    renderer.rendered_windows.insert(2, split);
    let mut surface = surfaces::raster_n32_premul((55, 80)).unwrap();
    let fractional = PixelRect::from_min_max((8.0, 8.0), (43.0, 47.0));
    surface.canvas().clear(Color::MAGENTA);
    renderer.draw_bottom_margin_background(surface.canvas(), Some(&fractional), &settings);
    assert_eq!(surface.peek_pixels().unwrap().get_color((12, 42)).a(), 51);

    for bottom in [32.0, 40.0, 56.0, 57.0, 80.0] {
        let content = PixelRect::from_min_max((8.0, 8.0), (43.0, bottom));
        surface.canvas().clear(Color::MAGENTA);
        renderer.draw_bottom_margin_background(surface.canvas(), Some(&content), &settings);
        assert_eq!(surface.peek_pixels().unwrap().get_color((12, 42)), Color::MAGENTA);
    }
    renderer.rendered_windows.get_mut(&1).unwrap().hidden = true;
    surface.canvas().clear(Color::MAGENTA);
    renderer.draw_bottom_margin_background(surface.canvas(), Some(&fractional), &settings);
    assert_eq!(surface.peek_pixels().unwrap().get_color((12, 42)), Color::MAGENTA);
    renderer.rendered_windows.remove(&1);
    renderer.draw_bottom_margin_background(surface.canvas(), Some(&fractional), &settings);
    assert_eq!(surface.peek_pixels().unwrap().get_color((12, 42)), Color::MAGENTA);

    // Canvas bounds, rather than a stale larger content region, bound the draw.
    let root = PixelRect::from_origin_and_size(PixelPos::new(8.0, 8.0), PixelSize::new(32.0, 64.0));
    let oversized = PixelRect::from_min_max((8.0, 8.0), (43.0, 87.0));
    assert_eq!(
        bottom_margin_rect(surface.canvas(), root, Some(&oversized), 16.0),
        Some(Rect::new(8.0, 72.0, 43.0, 80.0))
    );
}

#[test]
fn bottom_margin_setting_parses_clamps_and_clears() {
    use rmpv::Value;

    let mut setting = WindowSettings::default().bottom_margin_opacity;
    assert_eq!(Value::from(setting), Value::Nil);
    for (number, expected) in [(0.2, 0.2), (-2.0, 0.0), (4.0, 1.0)] {
        setting.parse_from_value(Value::from(number));
        assert_eq!(setting.0, Some(expected));
        assert_eq!(Value::from(setting), Value::from(expected));
    }
    setting.parse_from_value(Value::from(0));
    assert_eq!(setting.0, Some(0.0));
    setting.parse_from_value(Value::Nil);
    assert_eq!(setting.0, None, "removing the Lua override restores the default background");
    assert_eq!(Value::from(setting), Value::Nil);
}
