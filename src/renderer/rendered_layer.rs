use itertools::Itertools;
use skia_safe::{
    BlendMode, Canvas, ClipOp, Color, Paint, Path, PathOp, Point3, RRect, Rect,
    canvas::SaveLayerRec,
    image_filters::blur,
    utils::shadow_utils::{ShadowFlags, draw_shadow},
};
use std::collections::HashSet;

use glamour::Intersection;

use crate::{
    editor::WindowType,
    units::{GridScale, PixelRect, to_skia_rect},
};

use super::{RenderedWindow, RendererSettings, WindowDrawDetails, is_rightmost_window_edge};

struct LayerWindow<'w> {
    window: &'w mut RenderedWindow,
    group: usize,
}

pub struct FloatingLayer<'w> {
    pub windows: Vec<&'w mut RenderedWindow>,
}

impl FloatingLayer<'_> {
    fn build_draw_clip_and_bounds(
        &self,
        mut draw_clip: Path,
        mut draw_bound_rect: Rect,
        expanded_regions: &[PixelRect<f32>],
        grid_scale: GridScale,
    ) -> (Path, Rect) {
        for (window, region) in self.windows.iter().zip(expanded_regions.iter().copied()) {
            if let Some((path, bounds)) = window.edge_background_path_and_bounds(region, grid_scale)
            {
                include_path_bounds(&mut draw_clip, &mut draw_bound_rect, &path, bounds);
            }
        }

        (draw_clip, draw_bound_rect)
    }

    pub fn draw(
        &mut self,
        root_canvas: &Canvas,
        settings: &RendererSettings,
        default_background: Color,
        grid_scale: GridScale,
        content_region: Option<PixelRect<f32>>,
        shadow_exclusions: &HashSet<u64>,
    ) -> Vec<WindowDrawDetails> {
        let pixel_regions =
            self.windows.iter().map(|window| window.pixel_region(grid_scale)).collect::<Vec<_>>();
        let regions = self.expanded_regions(&pixel_regions, grid_scale, content_region);

        let (silhouette, bound_rect) = build_silhouette(&pixel_regions, settings, grid_scale);
        let (draw_clip, draw_bound_rect) =
            self.build_draw_clip_and_bounds(silhouette.clone(), bound_rect, &regions, grid_scale);
        let has_transparency = self.windows.iter().any(|window| window.has_transparency());

        if shadow_exclusions.is_empty() {
            self._draw_shadow(root_canvas, &silhouette, settings);
        } else {
            let shadow_regions = self
                .windows
                .iter()
                .zip(pixel_regions.iter())
                .filter(|(window, _)| {
                    !window.window_id.is_some_and(|id| shadow_exclusions.contains(&id))
                })
                .map(|(_, region)| *region)
                .collect_vec();
            if !shadow_regions.is_empty() {
                let (shadow_silhouette, _) =
                    build_silhouette(&shadow_regions, settings, grid_scale);
                self._draw_shadow(root_canvas, &shadow_silhouette, settings);
            }
        }

        root_canvas.save();
        root_canvas.clip_path(&draw_clip, None, Some(false));
        let need_blur = has_transparency || settings.floating_blur;
        if need_blur
            && let Some(blur) = blur(
                (settings.floating_blur_amount_x, settings.floating_blur_amount_y),
                None,
                None,
                None,
            )
        {
            let paint =
                Paint::default().set_anti_alias(false).set_blend_mode(BlendMode::Src).to_owned();
            let save_layer_rec =
                SaveLayerRec::default().backdrop(&blur).bounds(&draw_bound_rect).paint(&paint);
            root_canvas.save_layer(&save_layer_rec);
            root_canvas.restore();
        }

        // Float backgrounds carry absolute material alpha, just like editor
        // cells. Replace the clipped area instead of accumulating another
        // background over the editor (85% over 85% would become 97.75%).
        let paint =
            Paint::default().set_anti_alias(false).set_blend_mode(BlendMode::Src).to_owned();

        let save_layer_rec = SaveLayerRec::default().bounds(&draw_bound_rect).paint(&paint);

        root_canvas.save_layer(&save_layer_rec);
        let background_paint = Paint::default().set_color(default_background).to_owned();
        root_canvas.draw_path(&draw_clip, &background_paint);
        let mut ret = vec![];

        (0..self.windows.len()).for_each(|i| {
            let window = &mut self.windows[i];
            window.draw_background_surface(root_canvas, pixel_regions[i], grid_scale);
            window.draw_foreground_surface(root_canvas, pixel_regions[i], grid_scale);
            ret.push(WindowDrawDetails {
                id: window.id,
                region: regions[i],
                grid_size: window.grid_size,
                window_type: window.window_type,
            });
        });

        for (window, region) in self.windows.iter().zip(regions.iter().copied()) {
            window.draw_edge_background_surface(root_canvas, region, grid_scale);
        }

        root_canvas.restore();

        root_canvas.restore();

        ret
    }

    fn expanded_regions(
        &self,
        pixel_regions: &[PixelRect<f32>],
        grid_scale: GridScale,
        content_region: Option<PixelRect<f32>>,
    ) -> Vec<PixelRect<f32>> {
        let max_layer_x = max_region_max_x(pixel_regions);
        self.windows
            .iter()
            .zip(pixel_regions.iter().copied())
            .map(|(window, region)| {
                let rightmost_window = is_rightmost_window_edge(region.max.x, max_layer_x);
                window.expanded_pixel_region(region, content_region, grid_scale, rightmost_window)
            })
            .collect::<Vec<_>>()
    }

    fn _draw_shadow(&self, root_canvas: &Canvas, path: &Path, settings: &RendererSettings) {
        if !settings.floating_shadow {
            return;
        }
        // Assume that the message window is the only one in the layer
        if self
            .windows
            .first()
            .is_some_and(|w| matches!(w.window_type, WindowType::Message { scrolled: false }))
        {
            return;
        }

        root_canvas.save();
        // We clip using the Difference op to make sure that the shadow isn't rendered inside
        // the window itself.
        root_canvas.clip_path(path, Some(ClipOp::Difference), None);
        // The light angle is specified in degrees from the vertical, so we first convert them
        // to radians and then use sin/cos to get the y and z components of the light
        let light_angle_radians = settings.light_angle_degrees.to_radians();
        draw_shadow(
            root_canvas,
            path,
            // Specifies how far from the root canvas the shadow casting rect is. We just use
            // the z component here to set it a constant distance away.
            Point3::new(0., 0., settings.floating_z_height),
            // Because we use the DIRECTIONAL_LIGHT shadow flag, this specifies the angle that
            // the light is coming from.
            Point3::new(0., -light_angle_radians.sin(), light_angle_radians.cos()),
            // This is roughly equal to the apparent radius of the light .
            5.,
            Color::from_argb((0.03 * 255.) as u8, 0, 0, 0),
            Color::from_argb((0.35 * 255.) as u8, 0, 0, 0),
            // Directional Light flag is necessary to make the shadow render consistently
            // across various sizes of floating windows. It effects how the light direction is
            // processed.
            Some(ShadowFlags::DIRECTIONAL_LIGHT),
        );
        root_canvas.restore();
    }
}

fn get_window_group(windows: &mut Vec<LayerWindow>, index: usize) -> usize {
    if windows[index].group != index {
        windows[index].group = get_window_group(windows, windows[index].group);
    }
    windows[index].group
}

fn group_windows_with_regions(windows: &mut Vec<LayerWindow>, regions: &[PixelRect<f32>]) {
    // intersects does not consider touching regions as intersection, so extend the box by one
    // pixel before doing the test.
    let epsilon = 1.0;
    for i in 0..windows.len() {
        for j in i + 1..windows.len() {
            let group_i = get_window_group(windows, i);
            let group_j = get_window_group(windows, j);
            if group_i != group_j
                && regions[i].to_rect().inflate((epsilon, epsilon).into()).intersects(&regions[j])
            {
                let new_group = group_i.min(group_j);
                if group_i != group_j {
                    windows[group_i].group = new_group;
                    windows[group_j].group = new_group;
                }
            }
        }
    }
}

pub fn group_windows(
    windows: Vec<&mut RenderedWindow>,
    grid_scale: GridScale,
) -> Vec<Vec<&mut RenderedWindow>> {
    let mut windows = windows
        .into_iter()
        .enumerate()
        .map(|(index, window)| LayerWindow { window, group: index })
        .collect::<Vec<_>>();
    let regions =
        windows.iter().map(|window| window.window.pixel_region(grid_scale)).collect::<Vec<_>>();
    group_windows_with_regions(&mut windows, &regions);
    for i in 0..windows.len() {
        let _ = get_window_group(&mut windows, i);
    }
    windows.sort_by_key(|a| a.group);
    windows
        .into_iter()
        .chunk_by(|window| window.group)
        .into_iter()
        .map(|(_, v)| v.map(|w| w.window).collect::<Vec<_>>())
        .collect_vec()
}

fn include_path_bounds(
    draw_clip: &mut Path,
    draw_bound_rect: &mut Rect,
    path: &Path,
    bounds: Rect,
) {
    if let Some(unioned) = draw_clip.op(path, PathOp::Union) {
        *draw_clip = unioned;
    }

    *draw_bound_rect = Rect::join2(*draw_bound_rect, bounds);
}

fn build_silhouette(
    regions: &[PixelRect<f32>],
    settings: &RendererSettings,
    grid_scale: GridScale,
) -> (Path, Rect) {
    let silhouette = regions
        .iter()
        .map(|r| rect_to_round_rect_path(to_skia_rect(r), settings, grid_scale))
        .reduce(|a, b| a.op(&b, PathOp::Union).unwrap())
        .unwrap();

    let bounding_rect = regions.iter().map(to_skia_rect).reduce(Rect::join2).unwrap();

    (silhouette, bounding_rect)
}

fn max_region_max_x(regions: &[PixelRect<f32>]) -> f32 {
    regions.iter().fold(f32::NEG_INFINITY, |max_x, region| max_x.max(region.max.x))
}

fn rect_to_round_rect_path(rect: Rect, settings: &RendererSettings, grid_scale: GridScale) -> Path {
    let scaled_radius =
        if settings.floating_corner_radius > 0.0 && settings.floating_corner_radius <= 1.0 {
            settings.floating_corner_radius * grid_scale.height()
        } else {
            0.0
        };
    Path::rrect(RRect::new_rect_xy(rect, scaled_radius, scaled_radius), None)
}

#[cfg(test)]
mod tests {
    use std::{collections::HashMap, sync::Arc};

    use crate::{
        bridge::GridLineCell,
        editor::{Colors, DrawCommandBatcher, Style, Window, WindowType},
        renderer::{DrawCommand, GridRenderer, WindowDrawCommand},
        settings::Settings,
        units::{GridPos, GridScale, PixelPos, PixelRect, PixelSize},
        window::WindowSettings,
    };

    use super::*;

    fn grid_scale() -> GridScale {
        GridScale::new(PixelSize::new(8.0, 16.0))
    }

    fn positioned_window(id: u64, grid_top: f64, grid_left: f64) -> RenderedWindow {
        let mut window = RenderedWindow::new(id);
        window.handle_window_draw_command(WindowDrawCommand::Position {
            grid_position: (grid_left, grid_top),
            grid_size: (20, 1),
            anchor_info: None,
            window_type: WindowType::Editor,
        });
        window.grid_current_position = GridPos::new(grid_left as f32, grid_top as f32);
        window
    }

    fn material_renderer() -> GridRenderer {
        let settings = Arc::new(Settings::new());
        settings.set(&RendererSettings::default());
        settings.set(&WindowSettings { normal_opacity: 0.85, ..WindowSettings::default() });
        let mut renderer = GridRenderer::new(1.0, settings);
        renderer.grid_scale = grid_scale();
        renderer.default_style = Arc::new(Style::new(Colors::new(
            Some(Color::WHITE.into()),
            Some(Color::BLACK.into()),
            None,
        )));
        renderer
    }

    fn material_style(background: Color, blend: u8) -> Style {
        Style {
            blend,
            ..Style::new(Colors::new(Some(Color::WHITE.into()), Some(background.into()), None))
        }
    }

    fn material_window(
        renderer: &mut GridRenderer,
        id: u64,
        position: (f64, f64),
        size: (u64, u64),
        base: Style,
        accent: Option<Style>,
    ) -> RenderedWindow {
        let mut commands = DrawCommandBatcher::new();
        let mut editor = Window::new(id, WindowType::Editor, None, position, size, &mut commands);
        let mut styles = HashMap::from([(1, Arc::new(base))]);
        for row in 0..size.1 {
            editor.draw_grid_line(
                &mut commands,
                row,
                0,
                vec![GridLineCell {
                    text: " ".into(),
                    highlight_id: Some(1),
                    repeat: Some(size.0),
                }],
                &styles,
            );
        }
        if let Some(accent) = accent {
            styles.insert(2, Arc::new(accent));
            editor.draw_grid_line(
                &mut commands,
                1,
                1,
                vec![GridLineCell { text: " ".into(), highlight_id: Some(2), repeat: Some(1) }],
                &styles,
            );
        }
        let mut window = RenderedWindow::new(id);
        for command in commands.take_commands() {
            if let DrawCommand::Window { command, .. } = command {
                window.handle_window_draw_command(command);
            }
        }
        window.grid_current_position = GridPos::new(position.0 as f32, position.1 as f32);
        window.flush(&RendererSettings::default());
        window.prepare_lines(renderer, 1.0, true);
        window
    }

    #[test]
    fn floating_material_alpha_replaces_editor_and_parent_in_grouped_and_separate_layers() {
        use skia_safe::surfaces;

        let mut renderer = material_renderer();
        let settings = RendererSettings {
            floating_shadow: false,
            floating_blur: false,
            floating_blur_amount_x: 0.0,
            floating_blur_amount_y: 0.0,
            ..RendererSettings::default()
        };
        let default_background = renderer.get_default_background(0.85);
        for blend in [100, 60, 15, 0] {
            for (grouped, blur_amount) in [(true, 0.0), (false, 0.0), (true, 3.0), (false, 3.0)] {
                let settings = RendererSettings {
                    floating_blur: blur_amount > 0.0,
                    floating_blur_amount_x: blur_amount,
                    floating_blur_amount_y: blur_amount,
                    ..settings.clone()
                };
                let style = material_style(Color::BLUE, blend);
                let mut parent =
                    material_window(&mut renderer, 2, (1.0, 1.0), (14, 7), style.clone(), None);
                let mut child = material_window(&mut renderer, 3, (3.0, 3.0), (5, 2), style, None);
                let mut surface = surfaces::raster_n32_premul((160, 160)).unwrap();
                // A real editor already occupies the framebuffer when floats draw.
                // Its alpha must not accumulate with either popup material.
                surface.canvas().clear(Color::from_argb(216, 255, 0, 0));
                if grouped {
                    FloatingLayer { windows: vec![&mut parent, &mut child] }.draw(
                        surface.canvas(),
                        &settings,
                        default_background,
                        grid_scale(),
                        None,
                        &HashSet::new(),
                    );
                } else {
                    for window in [&mut parent, &mut child] {
                        FloatingLayer { windows: vec![window] }.draw(
                            surface.canvas(),
                            &settings,
                            default_background,
                            grid_scale(),
                            None,
                            &HashSet::new(),
                        );
                    }
                }
                let pixels = surface.peek_pixels().unwrap();
                let expected_alpha = ((100 - blend) as f32 * 2.55).round() as u8;
                for point in [(16, 40), (32, 56)] {
                    let actual = pixels.get_color(point);
                    assert!(
                        actual.a().abs_diff(expected_alpha) <= 1,
                        "absolute alpha: blend={blend}, grouped={grouped}, blur={blur_amount}, point={point:?}, actual={actual:?}",
                    );
                    if expected_alpha > 0 {
                        assert_eq!(actual.b(), 255, "editor red must not tint the blue popup");
                        assert_eq!(actual.r(), 0);
                    }
                }
            }
        }
    }

    #[test]
    fn floating_material_keeps_independent_child_selection_foreground_and_rounded_exterior() {
        use skia_safe::surfaces;

        let mut renderer = material_renderer();
        let settings = RendererSettings {
            floating_shadow: false,
            floating_blur: false,
            floating_blur_amount_x: 0.0,
            floating_blur_amount_y: 0.0,
            floating_corner_radius: 0.5,
            ..RendererSettings::default()
        };
        let default_background = renderer.get_default_background(0.85);
        for grouped in [true, false] {
            let mut parent = material_window(
                &mut renderer,
                2,
                (1.0, 1.0),
                (14, 7),
                material_style(Color::BLUE, 15),
                None,
            );
            let accent = Style {
                // Native reference outlines give a deterministic foreground pixel
                // without making this compositing regression depend on a font.
                reference_outline: true,
                ..Style::new(Colors::new(
                    Some(Color::GREEN.into()),
                    Some(Color::YELLOW.into()),
                    Some(Color::GREEN.into()),
                ))
            };
            let mut child = material_window(
                &mut renderer,
                3,
                (3.0, 3.0),
                (5, 2),
                material_style(Color::MAGENTA, 60),
                Some(accent),
            );
            let mut surface = surfaces::raster_n32_premul((160, 160)).unwrap();
            let backdrop = Color::from_argb(216, 255, 0, 0);
            surface.canvas().clear(backdrop);
            if grouped {
                FloatingLayer { windows: vec![&mut parent, &mut child] }.draw(
                    surface.canvas(),
                    &settings,
                    default_background,
                    grid_scale(),
                    None,
                    &HashSet::new(),
                );
            } else {
                for window in [&mut parent, &mut child] {
                    FloatingLayer { windows: vec![window] }.draw(
                        surface.canvas(),
                        &settings,
                        default_background,
                        grid_scale(),
                        None,
                        &HashSet::new(),
                    );
                }
            }
            let pixels = surface.peek_pixels().unwrap();
            let parent = pixels.get_color((16, 40));
            assert!(parent.a().abs_diff(217) <= 1);
            assert_eq!((parent.r(), parent.g(), parent.b()), (0, 0, 255));
            let child = pixels.get_color((36, 56));
            assert!(child.a().abs_diff(102) <= 1, "independent child retains 40% alpha");
            assert_eq!((child.r(), child.g(), child.b()), (255, 0, 255));
            assert_eq!(
                pixels.get_color((36, 72)),
                Color::YELLOW,
                "semantic selection stays opaque"
            );
            assert!(
                (64..80).any(|y| (32..40).any(|x| pixels.get_color((x, y)) == Color::GREEN)),
                "foreground decoration must survive the material replacement",
            );
            for point in [(8, 16), (7, 48), (120, 128), (150, 150)] {
                assert_eq!(
                    pixels.get_color(point),
                    backdrop,
                    "rounded clip/exterior must retain the editor at {point:?}, grouped={grouped}",
                );
            }
        }
    }

    #[test]
    fn floating_layer_only_expands_the_right_edge() {
        let grid_scale = grid_scale();
        let mut upper_window = positioned_window(2, 3.0, 0.0);
        let mut bottom_window = positioned_window(3, 4.0, 0.0);
        let layer = FloatingLayer { windows: vec![&mut upper_window, &mut bottom_window] };
        let pixel_regions =
            layer.windows.iter().map(|window| window.pixel_region(grid_scale)).collect::<Vec<_>>();
        let upper_region = pixel_regions[0];
        let bottom_region = pixel_regions[1];
        let content_region = PixelRect::new(
            PixelPos::new(0.0, 0.0),
            PixelPos::new(bottom_region.max.x + 3.0, bottom_region.max.y + 7.0),
        );

        let expanded_regions =
            layer.expanded_regions(&pixel_regions, grid_scale, Some(content_region));

        assert_eq!(expanded_regions[0].max.y, upper_region.max.y);
        assert_eq!(expanded_regions[1].max.y, bottom_region.max.y);
        assert_eq!(expanded_regions[0].max.x, content_region.max.x);
        assert_eq!(expanded_regions[1].max.x, content_region.max.x);
    }

    #[test]
    fn picker_shadow_scope_excludes_children_but_preserves_outer_box_and_ordinary_pixels() {
        use skia_safe::surfaces;
        let excluded = HashSet::from([1001, 1002, 1003, 1004]); // Input/list/preview/nested box.
        let render = |owner: u64, shadow: bool| {
            let mut window = positioned_window(2, 4.0, 6.0);
            window.handle_window_draw_command(WindowDrawCommand::Position {
                grid_position: (6.0, 4.0),
                grid_size: (8, 4),
                anchor_info: None,
                window_type: WindowType::Editor,
            });
            window.handle_window_draw_command(WindowDrawCommand::Viewport {
                window_id: owner,
                scroll_delta: 0.0,
            });
            let mut surface = surfaces::raster_n32_premul((180, 180)).unwrap();
            surface.canvas().clear(Color::WHITE);
            FloatingLayer { windows: vec![&mut window] }.draw(
                surface.canvas(),
                &RendererSettings {
                    floating_shadow: shadow,
                    floating_blur: false,
                    floating_corner_radius: 0.3,
                    ..RendererSettings::default()
                },
                Color::BLUE,
                grid_scale(),
                None,
                &excluded,
            );
            let pix = surface.peek_pixels().unwrap();
            assert_eq!(
                pix.get_color((70, 80)),
                Color::BLUE,
                "normal component background is unchanged"
            );
            pix.bytes().unwrap().to_vec()
        };
        for owner in [1001, 1002, 1003, 1004] {
            assert_eq!(
                render(owner, true),
                render(owner, false),
                "child {owner} adds no inner shadow"
            );
        }
        for owner in [1000, 2000] {
            // Outermost Box and an unrelated floating window.
            assert_ne!(
                render(owner, true),
                render(owner, false),
                "outer/default {owner} keeps its shadow"
            );
        }
        let valid = crate::bridge::parse_shadow_exclusions(&[rmpv::Value::Array(vec![
            1001.into(),
            1002.into(),
        ])])
        .unwrap();
        assert_eq!(valid, [1001, 1002]);
        assert!(
            crate::bridge::parse_shadow_exclusions(&[rmpv::Value::Array(vec![0.into()])]).is_err()
        );
    }
}
