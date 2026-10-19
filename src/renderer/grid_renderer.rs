use std::{ops::Range, sync::Arc};

use log::trace;
use skia_safe::{
    BlendMode, Canvas, Color, Color4f, HSV, Paint, PathBuilder, colors, dash_path_effect,
};

use crate::{
    editor::{Colors, LineFragment, Style, UnderlineStyle},
    profiling::tracy_zone,
    renderer::{
        CachingShaper, RendererSettings,
        box_drawing::{self},
    },
    settings::*,
    units::{
        GridPos, GridScale, GridSize, PixelPos, PixelRect, PixelVec, to_skia_point, to_skia_rect,
    },
    window::WindowSettings,
};

use super::{box_drawing::BoxDrawingSettings, fonts::font_options::FontOptions};

pub struct GridRenderer {
    pub shaper: CachingShaper,
    pub default_style: Arc<Style>,
    pub em_size: f32,
    pub grid_scale: GridScale,
    pub box_char_renderer: box_drawing::Renderer,
    pub is_ready: bool,

    settings: Arc<Settings>,
}

/// Struct with named fields to be returned from draw_background
pub struct BackgroundInfo {
    pub custom_color: bool,
    // This should probably be used
    #[allow(unused)]
    pub transparent: bool,
}

impl GridRenderer {
    pub fn new(scale_factor: f64, settings: Arc<Settings>) -> Self {
        let mut shaper = CachingShaper::new(scale_factor as f32);
        let default_style = Arc::new(Style::new(Colors::new(
            Some(colors::WHITE),
            Some(colors::BLACK),
            Some(colors::GREY),
        )));
        let em_size = shaper.current_size();
        let font_dimensions = shaper.font_base_dimensions();
        let grid_scale = GridScale::new(font_dimensions);
        let cell_size = GridSize::new(1, 1) * grid_scale;

        GridRenderer {
            shaper,
            default_style,
            em_size,
            grid_scale,
            box_char_renderer: box_drawing::Renderer::new(
                cell_size,
                em_size,
                BoxDrawingSettings::default(),
            ),
            is_ready: false,

            settings,
        }
    }

    pub fn font_names(&self) -> Vec<String> {
        self.shaper.font_names()
    }

    pub fn handle_scale_factor_update(&mut self, scale_factor: f64) {
        self.shaper.update_scale_factor(scale_factor as f32);
        self.update_font_dimensions();
    }

    pub fn update_font(&mut self, guifont_setting: &str) {
        self.shaper.update_font(guifont_setting);
        self.update_font_dimensions();
    }

    pub fn update_font_options(&mut self, options: FontOptions) {
        self.shaper.update_font_options(options);
        self.update_font_dimensions();
    }

    pub fn update_linespace(&mut self, linespace_setting: f32) {
        self.shaper.update_linespace(linespace_setting);
        self.update_font_dimensions();
    }

    pub fn handle_box_drawing_update(&mut self, settings: BoxDrawingSettings) {
        self.box_char_renderer.update_settings(settings);
    }

    fn update_font_dimensions(&mut self) {
        self.em_size = self.shaper.current_size();
        self.grid_scale = GridScale::new(self.shaper.font_base_dimensions());
        let new_cell_size = GridSize::new(1, 1) * self.grid_scale;
        self.box_char_renderer.update_dimensions(new_cell_size, self.em_size);
        self.is_ready = true;
        trace!("Updated font dimensions: {:?}", self.grid_scale);
    }

    fn compute_text_region(&self, cells: &Range<u32>) -> PixelRect<f32> {
        let grid_position = GridPos::new(cells.start, 0);
        let pos = grid_position * self.grid_scale;
        let size = GridSize::new(cells.len() as i32, 1) * self.grid_scale;
        PixelRect::from_origin_and_size(pos, size)
    }

    pub fn get_default_background_color(&self) -> Color {
        self.default_style.colors.background.unwrap().to_color()
    }

    pub fn get_default_background(&self, opacity: f32) -> Color {
        log::info!("blend {}", self.default_style.blend);
        let alpha = opacity * (100 - self.default_style.blend) as f32 / 100.0;
        self.get_default_background_color().with_a((alpha * 255.0) as u8)
    }

    pub fn background_paint_color(&self, style: &Option<Arc<Style>>, opacity: f32) -> Color4f {
        let style = style.as_ref().unwrap_or(&self.default_style);
        let style_background = style.background(&self.default_style.colors).to_color();

        let mut paint = Paint::default();
        paint.set_anti_alias(false);
        paint.set_blend_mode(BlendMode::Src);
        paint.set_color(style_background);

        paint.set_alpha_f(self.background_opacity(style_background, style.blend, opacity));
        paint.color4f()
    }

    fn background_opacity(&self, color: Color, blend: u8, opacity: f32) -> f32 {
        let normal_opacity = self.settings.get::<WindowSettings>().normal_opacity;
        if blend > 0 {
            // An explicit highlight blend also applies when CursorLine or a
            // remapped window background happens to share Normal's RGB color.
            ((100 - blend) as f32 / 100.0) * opacity
        } else if normal_opacity < 1.0 && color == self.get_default_background_color() {
            normal_opacity
        } else {
            opacity
        }
    }

    /// Draws a single background cell with the same style
    pub fn draw_background(
        &mut self,
        canvas: &Canvas,
        cells: &Range<u32>,
        style: &Option<Arc<Style>>,
        opacity: f32,
    ) -> BackgroundInfo {
        tracy_zone!("draw_background");
        let debug = self.settings.get::<RendererSettings>().debug_renderer;
        if style.is_none() && !debug {
            return BackgroundInfo {
                custom_color: false,
                transparent: self.default_style.blend > 0 || opacity < 1.0,
            };
        }
        let region = self.compute_text_region(cells);
        let style = style.as_ref().unwrap_or(&self.default_style);
        let style_background = style.background(&self.default_style.colors).to_color();

        let mut paint = Paint::default();
        paint.set_anti_alias(false);
        paint.set_blend_mode(BlendMode::Src);

        if debug {
            let random_hsv: HSV = (rand::random::<f32>() * 360.0, 0.3, 0.3).into();
            let random_color = random_hsv.to_color(255);
            paint.set_color(random_color);
        } else {
            paint.set_color(style_background);
        }

        let alpha = self.background_opacity(style_background, style.blend, opacity);
        paint.set_alpha_f(alpha);

        let custom_color = paint.color4f() != self.default_style.colors.background.unwrap();
        if custom_color {
            canvas.draw_rect(to_skia_rect(&region), &paint);
        }

        BackgroundInfo { custom_color, transparent: alpha < 1.0 }
    }

    /// A foreground decoration, independent of background blend and font size.
    /// Coordinates already use physical pixels; inset keeps the complete 1px
    /// stroke inside the highlighted cells and the line's vertical clip.
    pub fn draw_reference_outline(
        &self,
        canvas: &Canvas,
        cells: &Range<u32>,
        color: Color4f,
    ) -> bool {
        let mut region = to_skia_rect(&self.compute_text_region(cells));
        if region.width() <= 1.0 || region.height() <= 1.0 {
            return false;
        }
        region.inset((0.5, 0.5));
        let mut paint = Paint::default();
        paint
            .set_anti_alias(false)
            .set_style(skia_safe::paint::Style::Stroke)
            .set_stroke_width(1.0)
            .set_color(color.to_color());
        canvas.draw_rect(region, &paint);
        true
    }

    /// Draws some foreground text.
    /// Returns true if any text was actually drawn.
    pub fn draw_foreground(
        &mut self,
        text_canvas: &Canvas,
        boxchar_canvas: &Canvas,
        fragment: &LineFragment,
        window_position: PixelPos<f32>,
        opacity: f32,
    ) -> (bool, bool) {
        tracy_zone!("draw_foreground");

        let LineFragment { text, cells, style, .. } = fragment;

        let region = self.compute_text_region(cells);

        let style = style.as_ref().unwrap_or(&self.default_style);
        let mut text_drawn = false;

        if let Some(underline_style) = style.underline {
            let stroke_size = self.shaper.stroke_size();
            // Measure the underline offset from the baseline position snapped to a whole pixel
            let baseline_position = self.shaper.baseline_offset().round();
            // The underline should be at least 1 pixel below the baseline
            let underline_position =
                baseline_position - self.shaper.underline_offset().min(-1.).round();
            let p1 = PixelPos::new(region.min.x, underline_position);
            let p2 = PixelPos::new(region.max.x, underline_position);

            self.draw_underline(text_canvas, style, underline_style, stroke_size, p1, p2);
            text_drawn = true;
        }

        let foreground = style.foreground(&self.default_style.colors).to_color();
        let shape_opacity = self.background_opacity(foreground, style.blend, opacity);
        #[cfg(target_os = "macos")]
        let shape_opacity = if style.avante_solid_cap
            && style.blend > 0
            && self.settings.get::<WindowSettings>().liquid_glass
        {
            // These endcaps are solid title shapes over a translucent panel.
            // Their cell background still follows its explicit highlight blend.
            opacity
        } else {
            shape_opacity
        };
        if self.box_char_renderer.draw_glyph(
            text,
            boxchar_canvas,
            region,
            foreground,
            window_position,
            Some(shape_opacity),
        ) {
            return (text_drawn, true);
        } else if !text.is_empty() {
            text_canvas.save();

            // We don't want to clip text in the x position, only the y so we add a buffer of 1
            // character on either side of the region so that we clip vertically but not horizontally.
            let wider_cells = cells.start.saturating_sub(1)..cells.end + 1;
            let clip_region = self.compute_text_region(&wider_cells);
            text_canvas.clip_rect(to_skia_rect(&clip_region), None, Some(false));

            let mut paint = Paint::default();
            paint.set_anti_alias(false);
            paint.set_blend_mode(BlendMode::SrcOver);

            if self.settings.get::<RendererSettings>().debug_renderer {
                let random_hsv: HSV = (rand::random::<f32>() * 360.0, 1.0, 1.0).into();
                let random_color = random_hsv.to_color(255);
                paint.set_color(random_color);
            } else {
                paint.set_color(style.foreground(&self.default_style.colors).to_color());
            }
            if style.enlarged_icon {
                // The capsule's text has its own three-cell region. Enlarge
                // its icon around that center, preserving layout and baseline
                // for every other highlight, background and powerline cap.
                let center = region.center();
                text_canvas.save();
                text_canvas.translate((center.x, center.y));
                text_canvas.scale((1.2, 1.2));
                text_canvas.translate((-center.x, -center.y));
            }
            for word in fragment.words() {
                let adjustment = PixelVec::new(
                    word.cell as f32 * self.grid_scale.width(),
                    self.shaper.baseline_offset(),
                );

                for blob in self.shaper.shape_cached(word, style.into()).iter() {
                    tracy_zone!("draw_text_blob");
                    text_canvas.draw_text_blob(
                        blob,
                        to_skia_point(region.min + adjustment),
                        &paint,
                    );
                    text_drawn = true;
                }
            }
            if style.enlarged_icon {
                text_canvas.restore();
            }

            if style.strikethrough {
                let line_position = region.center().y;
                paint.set_color(style.special(&self.default_style.colors).to_color());
                text_canvas.draw_line(
                    (region.min.x, line_position),
                    (region.max.x, line_position),
                    &paint,
                );
                text_drawn = true;
            }
            text_canvas.restore();
        }
        (text_drawn, false)
    }

    fn draw_underline(
        &self,
        canvas: &Canvas,
        style: &Arc<Style>,
        underline_style: UnderlineStyle,
        stroke_size: f32,
        p1: PixelPos<f32>,
        p2: PixelPos<f32>,
    ) {
        tracy_zone!("draw_underline");
        canvas.save();

        let mut underline_paint = Paint::default();
        underline_paint.set_anti_alias(false);
        underline_paint.set_blend_mode(BlendMode::SrcOver);
        let underline_stroke_scale = self.settings.get::<RendererSettings>().underline_stroke_scale;
        // at least 1 and in whole pixels
        let stroke_width = (stroke_size * underline_stroke_scale).max(1.).round();

        // offset y by width / 2 to align the *top* of the underline with p1 and p2
        let offset = stroke_width / 2.;
        let p1 = (p1.x, p1.y + offset);
        let p2 = (p2.x, p2.y + offset);

        underline_paint
            .set_color(style.special(&self.default_style.colors).to_color())
            .set_stroke_width(stroke_width);

        match underline_style {
            UnderlineStyle::Underline => {
                underline_paint.set_path_effect(None);
                canvas.draw_line(p1, p2, &underline_paint);
            }
            UnderlineStyle::UnderDouble => {
                underline_paint.set_path_effect(None);
                canvas.draw_line(p1, p2, &underline_paint);
                let p1 = (p1.0, p1.1 + 2. * stroke_width);
                let p2 = (p2.0, p2.1 + 2. * stroke_width);
                canvas.draw_line(p1, p2, &underline_paint);
            }
            UnderlineStyle::UnderCurl => {
                let p1 = (p1.0, p1.1 + stroke_width);
                let p2 = (p2.0, p2.1 + stroke_width);
                underline_paint
                    .set_path_effect(None)
                    .set_anti_alias(true)
                    .set_style(skia_safe::paint::Style::Stroke);

                let mut builder = PathBuilder::new();
                builder.move_to(p1);
                let mut sin = -2. * stroke_width;
                let dx = self.grid_scale.width() / 2.;
                let count = ((p2.0 - p1.0) / dx).round();
                let dy = (p2.1 - p1.1) / count;
                for _ in 0..(count as i32) {
                    sin *= -1.;
                    builder.r_quad_to((dx / 2., sin), (dx, dy));
                }

                let path = builder.detach();
                canvas.draw_path(&path, &underline_paint);
            }
            UnderlineStyle::UnderDash => {
                underline_paint.set_path_effect(dash_path_effect::new(
                    &[6.0 * stroke_width, 2.0 * stroke_width],
                    0.0,
                ));
                canvas.draw_line(p1, p2, &underline_paint);
            }
            UnderlineStyle::UnderDot => {
                underline_paint.set_path_effect(dash_path_effect::new(
                    &[1.0 * stroke_width, 1.0 * stroke_width],
                    0.0,
                ));
                canvas.draw_line(p1, p2, &underline_paint);
            }
        }

        canvas.restore();
    }
}

#[cfg(test)]
mod tests {
    use skia_safe::{Data, Font, FontMgr, PictureRecorder, Rect, Surface, surfaces};

    use super::*;

    fn powerline_frame(
        renderer: &mut GridRenderer,
        font: &Font,
        cap: &str,
        color: Color,
        blend: u8,
        opacity: f32,
        draw_cap: bool,
    ) -> Surface {
        let bounds = Rect::from_wh(160.0, 32.0);
        let background = Some(Arc::new(Style {
            blend,
            ..Style::new(Colors::new(None, Some(color.into()), None))
        }));
        let body = if cap == "" { 0..2 } else { 3..5 };
        let mut recorder = PictureRecorder::new();
        renderer.draw_background(
            recorder.begin_recording(bounds, false),
            &body,
            &background,
            opacity,
        );
        let background_picture = recorder.finish_recording_as_picture(None).unwrap();

        let mut text_paint = Paint::default();
        text_paint.set_color(Color::from_rgb(240, 113, 120));
        recorder.begin_recording(bounds, false).draw_str("a", (104.0, 23.0), font, &text_paint);
        let foreground_picture = recorder.finish_recording_as_picture(None).unwrap();

        let canvas = recorder.begin_recording(bounds, false);
        let shape_opacity = renderer.background_opacity(color, blend, opacity);
        let cell = |column: f32| {
            PixelRect::from_origin_and_size(
                PixelPos::new(column * 16.0, 0.0),
                crate::units::PixelSize::new(16.0, 32.0),
            )
        };
        // Ordinary foreground box lines must remain opaque, and letters must
        // still fall through to the normal text renderer.
        let alpha = draw_cap.then_some(shape_opacity);
        assert!(renderer.box_char_renderer.draw_glyph(
            "│",
            canvas,
            cell(8.0),
            Color::WHITE,
            PixelPos::default(),
            alpha,
        ));
        assert!(!renderer.box_char_renderer.draw_glyph(
            "a",
            canvas,
            cell(6.0),
            Color::WHITE,
            PixelPos::default(),
            alpha,
        ));
        if draw_cap {
            assert!(renderer.box_char_renderer.draw_glyph(
                cap,
                canvas,
                cell(2.0),
                color,
                PixelPos::default(),
                Some(shape_opacity),
            ));
        }
        let boxchar_picture = recorder.finish_recording_as_picture(None).unwrap();

        // Replay the same separate background/text/boxchar pictures used by a
        // rendered window, over a translucent pre-existing window background.
        let mut surface = surfaces::raster_n32_premul((160, 32)).unwrap();
        surface.canvas().clear(Color::from_argb(64, 11, 14, 20));
        for picture in [&background_picture, &foreground_picture, &boxchar_picture] {
            surface.canvas().draw_picture(picture, None, None);
        }
        surface
    }

    #[test]
    fn powerline_caps_match_background_alpha_without_changing_text_or_outer_pixels() {
        let settings = Arc::new(Settings::new());
        let window_settings = WindowSettings { normal_opacity: 0.9, ..WindowSettings::default() };
        settings.set(&window_settings);
        settings.set(&RendererSettings::default());
        let mut renderer = GridRenderer::new(1.0, settings);
        renderer.grid_scale = GridScale::new(crate::units::PixelSize::new(16.0, 32.0));
        renderer
            .box_char_renderer
            .update_dimensions(crate::units::PixelSize::new(16.0, 32.0), 32.0);
        let typeface = FontMgr::new()
            .new_from_data(Data::new_copy(font_test_data::NOTO_SERIF_DISPLAY_TRIMMED), 0)
            .unwrap();
        let font = Font::from_typeface(typeface, 20.0);
        let normal = renderer.get_default_background_color();
        let capsule = Color::from_rgb(28, 31, 37);

        for opacity in [1.0, 0.95, 0.5] {
            for (color, blend) in [(capsule, 0), (normal, 0), (capsule, 35)] {
                for cap in ["", ""] {
                    let mut expected =
                        powerline_frame(&mut renderer, &font, cap, color, blend, opacity, false);
                    let mut actual =
                        powerline_frame(&mut renderer, &font, cap, color, blend, opacity, true);
                    let baseline = expected.peek_pixels().unwrap();
                    let pixels = actual.peek_pixels().unwrap();
                    let body_x = if cap == "" { 16 } else { 64 };
                    let inner_x = if cap == "" { 33 } else { 46 };
                    let body = pixels.get_color((body_x, 16));
                    assert_eq!(
                        pixels.get_color((inner_x, 16)),
                        body,
                        "{cap} must match its background at opacity {opacity}, blend {blend}",
                    );
                    let mut antialiased_edge = false;
                    let mut text_drawn = false;
                    for y in 0..32 {
                        for x in 0..160 {
                            let before = baseline.get_color((x, y));
                            let after = pixels.get_color((x, y));
                            if (32..48).contains(&x) {
                                antialiased_edge |= after != before && after != body;
                            } else {
                                assert_eq!(after, before, "{cap} changed an outside/text pixel");
                                text_drawn |= (100..128).contains(&x)
                                    && after != Color::from_argb(64, 11, 14, 20);
                            }
                        }
                    }
                    assert!(antialiased_edge, "{cap} must keep its smooth contour");
                    assert!(text_drawn, "the normal text sample must be rendered");
                }
            }
        }
    }

    #[test]
    fn explicit_tree_and_cursorline_blend_preserves_normal_selection_and_capsule_alpha() {
        let settings = Arc::new(Settings::new());
        settings.set(&WindowSettings { normal_opacity: 0.78, ..WindowSettings::default() });
        settings.set(&RendererSettings::default());
        let mut renderer = GridRenderer::new(1.0, settings);
        renderer.grid_scale = GridScale::new(crate::units::PixelSize::new(16.0, 24.0));
        let normal = Color::from_rgb(250, 250, 250);
        let foreground = Color::from_rgb(92, 97, 102);
        renderer.default_style =
            Arc::new(Style::new(Colors::new(Some(foreground.into()), Some(normal.into()), None)));
        let mut surface = surfaces::raster_n32_premul((80, 24)).unwrap();
        let base = renderer.get_default_background(0.78);
        surface.canvas().clear(base);
        for (index, (name, color, blend, expected_alpha)) in [
            ("NeoTreeNormal", Color::from_rgb(243, 243, 243), 40, 153),
            // The actual light-theme NeoTreeCursorLine is exactly Normal RGB.
            ("NeoTreeCursorLine", normal, 40, 153),
            ("CursorLine", Color::from_rgb(239, 239, 239), 40, 153),
            ("Visual", Color::from_rgb(238, 238, 238), 0, 255),
            ("GlowNotebookLanguage", Color::from_rgb(255, 214, 138), 0, 255),
        ]
        .into_iter()
        .enumerate()
        {
            let style = Style {
                blend,
                ..Style::new(Colors::new(Some(foreground.into()), Some(color.into()), None))
            }
            .with_roles(
                (name == "GlowNotebookLanguage")
                    .then_some(crate::editor::HighlightRole::EnlargedIcon),
            );
            assert_eq!(style.foreground(&renderer.default_style.colors).to_color(), foreground);
            renderer.draw_background(
                surface.canvas(),
                &(index as u32..index as u32 + 1),
                &Some(Arc::new(style)),
                1.0,
            );
            assert_eq!(
                surface.peek_pixels().unwrap().get_color((index as i32 * 16 + 8, 12)).a(),
                expected_alpha,
                "{name} must replace the base background alpha rather than stacking over it"
            );
        }
        assert_eq!(base.a(), 198, "ordinary editor background remains 78% opaque");
        assert!((renderer.background_opacity(normal, 0, 1.0) - 0.78).abs() < 0.001);
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn avante_solid_caps_keep_panel_corners_glass_and_match_title_body() {
        let settings = Arc::new(Settings::new());
        settings.set(&RendererSettings::default());
        let mut renderer = GridRenderer::new(1.0, settings.clone());
        let cell_size = crate::units::PixelSize::new(16.0, 32.0);
        renderer.grid_scale = GridScale::new(cell_size);
        renderer.box_char_renderer.update_dimensions(cell_size, 32.0);
        let bounds = Rect::from_wh(80.0, 32.0);
        let accent = Color::from_rgb(95, 175, 175);

        for panel in [Color::from_rgb(243, 243, 243), Color::from_rgb(32, 36, 43)] {
            for opacity in [1.0, 0.8] {
                for liquid_glass in [false, true] {
                    settings.set(&WindowSettings { liquid_glass, ..WindowSettings::default() });
                    for name in [
                        "AvanteReversedTitle",
                        "AvanteReversedSubtitle",
                        "AvanteReversedThirdTitle",
                        "StatusLine",
                    ] {
                        let cap = Some(Arc::new(
                            Style {
                                blend: 40,
                                ..Style::new(Colors::new(
                                    Some(accent.into()),
                                    Some(panel.into()),
                                    None,
                                ))
                            }
                            .with_roles(
                                (name != "StatusLine")
                                    .then_some(crate::editor::HighlightRole::SolidTitleCap),
                            ),
                        ));
                        let body = Some(Arc::new(Style::new(Colors::new(
                            Some(Color::WHITE.into()),
                            Some(accent.into()),
                            None,
                        ))));
                        let mut background = PictureRecorder::new();
                        let canvas = background.begin_recording(bounds, false);
                        renderer.draw_background(canvas, &(0..5), &cap, opacity);
                        renderer.draw_background(canvas, &(1..4), &body, opacity);
                        let background = background.finish_recording_as_picture(None).unwrap();

                        let mut text = PictureRecorder::new();
                        let mut boxes = PictureRecorder::new();
                        let text_canvas = text.begin_recording(bounds, false);
                        let box_canvas = boxes.begin_recording(bounds, false);
                        let line = crate::editor::Line::from_test_cells(&["", " ", " ", " ", ""]);
                        let mut drawn_caps = 0;
                        for mut fragment in line.fragments().filter(|f| matches!(f.text, "" | ""))
                        {
                            fragment.style = &cap;
                            assert_eq!(
                                renderer.draw_foreground(
                                    text_canvas,
                                    box_canvas,
                                    &fragment,
                                    PixelPos::ZERO,
                                    opacity,
                                ),
                                (false, true)
                            );
                            drawn_caps += 1;
                        }
                        assert_eq!(drawn_caps, 2);
                        let boxes = boxes.finish_recording_as_picture(None).unwrap();
                        let mut surface = surfaces::raster_n32_premul((80, 32)).unwrap();
                        surface.canvas().clear(Color::TRANSPARENT);
                        surface.canvas().draw_picture(&background, None, None);
                        surface.canvas().draw_picture(&boxes, None, None);
                        let pixels = surface.peek_pixels().unwrap();
                        let panel_pixel = pixels.get_color((0, 0));
                        assert_eq!(panel_pixel, pixels.get_color((79, 0)));
                        assert!(
                            (panel_pixel.a() as f32 - 153.0 * opacity).abs() <= 1.0,
                            "{name} exterior must retain the panel's glass alpha"
                        );
                        let left = pixels.get_color((15, 16));
                        let right = pixels.get_color((64, 16));
                        assert_eq!(left, right, "both ends must use the same material");
                        if liquid_glass && name.starts_with("AvanteReversed") {
                            assert_eq!(
                                left,
                                pixels.get_color((32, 16)),
                                "{name} shape must join its solid title body at opacity {opacity}"
                            );
                        } else {
                            assert!(
                                (left.a() as f32 - 153.0 * opacity).abs() <= 1.0,
                                "ordinary caps and non-Glass windows keep their original blend"
                            );
                        }
                    }
                }
            }
        }
    }
}
