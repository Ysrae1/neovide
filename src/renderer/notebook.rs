//! Decoration-only Notebook frames. Geometry arrives as asynchronous snapshots;
//! editor text, cursor, execution and document serialization remain in Neovim.
use rmpv::Value;
use skia_safe::{Canvas, Color, Paint, PathBuilder, Rect, paint::Style};
use std::collections::{HashMap, HashSet};

use crate::image_preview::ImageAnchor;
use crate::units::{GridScale, to_skia_rect};

const MAX_FRAMES: usize = 512;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FrameRect {
    pub row: f32,
    pub col: f32,
    pub width: f32,
    pub height: f32,
}
impl FrameRect {
    fn parse(value: &Value) -> Result<Self, String> {
        let fields = value.as_map().ok_or("Notebook frame rectangle must be a map")?;
        let number = |key| {
            fields
                .iter()
                .find(|(k, _)| k.as_str() == Some(key))
                .and_then(|(_, v)| v.as_f64())
                .map(|v| v as f32)
                .filter(|v| v.is_finite() && v.abs() <= 1_000_000.0)
                .ok_or_else(|| format!("Notebook frame {key} must be a bounded finite number"))
        };
        let rect = Self {
            row: number("row")?,
            col: number("col")?,
            width: number("width")?,
            height: number("height")?,
        };
        if rect.width <= 0.0 || rect.height <= 0.0 {
            return Err("Notebook frame size must be positive".into());
        }
        Ok(rect)
    }
    fn pixels(self, scale: GridScale) -> Rect {
        Rect::from_xywh(
            self.col * scale.width(),
            self.row * scale.height(),
            self.width * scale.width(),
            self.height * scale.height(),
        )
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct FrameAnchor {
    window: u64,
    epoch: u64,
    scroll: bool,
}

#[derive(Clone, Debug)]
pub(crate) struct NotebookWindow {
    grid: u64,
    window: u64,
    origin: (f32, f32),
    size: (f32, f32),
    scroll: f64,
    animation: f32,
    floating: bool,
    host_width: f32,
    host_height: f32,
    content_clip: Rect,
}
impl NotebookWindow {
    pub fn from_window(window: &super::RenderedWindow, scale: GridScale) -> Option<Self> {
        if window.hidden {
            return None;
        }
        let region = window.pixel_region(scale);
        let mut content_clip = window.inner_region(region, scale);
        if !content_clip.intersect(to_skia_rect(&window.background_region(scale))) {
            return None;
        }
        Some(Self {
            grid: window.id,
            window: window.window_id?,
            origin: (region.min.x, region.min.y),
            size: (
                window.grid_size.width as f32 * scale.width(),
                window.grid_size.height as f32 * scale.height(),
            ),
            scroll: window.viewport_scroll,
            animation: window.scroll_animation.position,
            floating: window.anchor_info.is_some(),
            host_width: window.host_grid_size.unwrap_or(window.grid_size).width as f32
                * scale.width(),
            host_height: window.host_grid_size.unwrap_or(window.grid_size).height as f32
                * scale.height(),
            content_clip,
        })
    }
    fn scroll_pixels(&self, baseline: f64, height: f32) -> f32 {
        let integer = self.animation.floor();
        // Exact same row selection and rounded fractional transform as the
        // owner's iter_scrollable_lines_with_transform, including reverse scroll.
        -((self.scroll - baseline) as f32 + integer) * height
            + ((integer - self.animation) * height).round()
    }
}

#[derive(Clone, Debug, PartialEq)]
struct LabelGap {
    col: f32,
    width: f32,
}
impl LabelGap {
    fn parse_many(value: Option<&Value>, name: &str) -> Result<Vec<Self>, String> {
        let Some(value) = value else { return Ok(Vec::new()) };
        let gaps = value.as_array().filter(|v| v.len() <= 8).ok_or_else(|| {
            format!("Notebook {name} must be an array with at most eight entries")
        })?;
        gaps.iter()
            .map(|value| {
                let fields =
                    value.as_map().ok_or_else(|| format!("Notebook {name} entry must be a map"))?;
                let number = |name| {
                    fields
                        .iter()
                        .find(|(key, _)| key.as_str() == Some(name))
                        .and_then(|(_, value)| value.as_f64())
                        .map(|value| value as f32)
                        .filter(|value| value.is_finite() && *value >= 0.0 && *value <= 1_000_000.0)
                        .ok_or_else(|| format!("Notebook gap {name} must be bounded"))
                };
                let gap = Self { col: number("col")?, width: number("width")? };
                if gap.width <= 0.0 {
                    return Err("Notebook gap width must be positive".into());
                }
                Ok(gap)
            })
            .collect()
    }
}

#[derive(Clone, Debug, PartialEq)]
enum FrameJoin {
    Top,
    Bottom,
}

#[derive(Clone, Debug, PartialEq)]
pub struct NotebookFrame {
    rect: FrameRect,
    clip: FrameRect,
    output: bool,
    join: Option<FrameJoin>,
    active: bool,
    overlay: bool,
    dark: bool,
    anchor: Option<FrameAnchor>,
    color: Option<u32>,
    label_gaps: Vec<LabelGap>,
    footer_gaps: Vec<LabelGap>,
}
impl NotebookFrame {
    fn parse(value: &Value) -> Result<Self, String> {
        let fields = value.as_map().ok_or("Notebook frame must be a map")?;
        let field = |key| fields.iter().find(|(k, _)| k.as_str() == Some(key)).map(|(_, v)| v);
        let flag = |key| match field(key) {
            None => Ok(false),
            Some(value) => {
                value.as_bool().ok_or_else(|| format!("Notebook frame {key} must be a boolean"))
            }
        };
        Ok(Self {
            rect: FrameRect::parse(field("rect").ok_or("Notebook frame needs rect")?)?,
            clip: FrameRect::parse(field("clip").ok_or("Notebook frame needs clip")?)?,
            output: match field("kind").and_then(Value::as_str) {
                Some("input") => false,
                Some("output") => true,
                _ => return Err("Notebook frame kind must be input or output".into()),
            },
            join: match field("join") {
                None => None,
                Some(value) => Some(match value.as_str() {
                    Some("top") => FrameJoin::Top,
                    Some("bottom") => FrameJoin::Bottom,
                    _ => return Err("Notebook join must be top or bottom".into()),
                }),
            },
            anchor: field("anchor")
                .map(|value| {
                    let values = value.as_map().ok_or("Notebook anchor must be a map")?;
                    let positive = |name| {
                        values
                            .iter()
                            .find(|(key, _)| key.as_str() == Some(name))
                            .and_then(|(_, value)| value.as_u64())
                            .filter(|value| *value > 0)
                            .ok_or_else(|| format!("Notebook anchor {name} must be positive"))
                    };
                    let scroll = values
                        .iter()
                        .find(|(key, _)| key.as_str() == Some("scroll"))
                        .and_then(|(_, value)| value.as_bool())
                        .unwrap_or(false);
                    Ok::<_, String>(FrameAnchor {
                        window: positive("window")?,
                        epoch: positive("epoch")?,
                        scroll,
                    })
                })
                .transpose()?,
            active: flag("active")?,
            overlay: flag("overlay")?,
            dark: flag("dark")?,
            color: field("color")
                .map(|value| {
                    value
                        .as_u64()
                        .filter(|v| *v <= 0xff_ffff)
                        .map(|v| v as u32)
                        .ok_or_else(|| "Notebook color must be RGB".to_string())
                })
                .transpose()?,
            label_gaps: LabelGap::parse_many(field("label_gaps"), "label_gaps")?,
            footer_gaps: LabelGap::parse_many(field("footer_gaps"), "footer_gaps")?,
        })
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NotebookViewport {
    pub window: u64,
    pub width: u64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct FrameSnapshot {
    pub frames: Vec<NotebookFrame>,
    pub viewports: Vec<NotebookViewport>,
}
impl FrameSnapshot {
    pub fn parse(arguments: &[Value]) -> Result<Self, String> {
        let (frames, viewports) = match arguments {
            [frames] => (frames, None),
            [frames, viewports] => (frames, Some(viewports)),
            _ => return Err("Notebook frames expects frames and optional viewports".into()),
        };
        let frames = frames
            .as_array()
            .filter(|f| f.len() <= MAX_FRAMES)
            .ok_or("Notebook frames must be an array with at most 512 entries")?;
        let viewports =
            viewports
                .map(|value| {
                    let values = value
                        .as_array()
                        .filter(|v| v.len() <= 64)
                        .ok_or("Notebook viewports must be an array with at most 64 entries")?;
                    values
                        .iter()
                        .map(|value| {
                            let fields = value.as_map().ok_or("Notebook viewport must be a map")?;
                            let positive =
                                |name| {
                                    fields.iter().find(|(k, _)| k.as_str() == Some(name))
                    .and_then(|(_, v)| v.as_u64()).filter(|v| *v > 0 && *v <= 1_000_000)
                    .ok_or_else(|| format!("Notebook viewport {name} must be positive and bounded"))
                                };
                            Ok::<_, String>(NotebookViewport {
                                window: positive("window")?,
                                width: positive("width")?,
                            })
                        })
                        .collect::<Result<Vec<_>, _>>()
                })
                .transpose()?
                .unwrap_or_default();
        Ok(Self {
            frames: frames.iter().map(NotebookFrame::parse).collect::<Result<_, _>>()?,
            viewports,
        })
    }
}

struct ResolvedFrame {
    bounds: Rect,
    clip: Rect,
    owner_clip: Option<Rect>,
    owner_grid: Option<u64>,
}

pub(super) struct ImageOwnerTransform {
    pub origin: (f32, f32),
    pub offset: (f32, f32),
    pub clip: Rect,
}

fn resolve_frame(
    frame: &NotebookFrame,
    scale: GridScale,
    windows: &[NotebookWindow],
    bindings: &mut HashMap<(u64, u64), f64>,
    host_widths: &HashMap<u64, u64>,
) -> Option<ResolvedFrame> {
    let mut bounds = frame.rect.pixels(scale);
    let mut clip = frame.clip.pixels(scale);
    let mut owner_grid = None;
    let mut owner_clip = None;
    if let Some(anchor) = frame.anchor {
        let window = windows.iter().find(|w| w.window == anchor.window)?;
        let baseline = *bindings.entry((anchor.window, anchor.epoch)).or_insert(window.scroll);
        let scroll =
            if anchor.scroll { window.scroll_pixels(baseline, scale.height()) } else { 0.0 };
        bounds = bounds.with_offset((window.origin.0, window.origin.1 + scroll));
        clip = clip.with_offset(window.origin);
        owner_clip = Some(Rect::from_xywh(
            window.origin.0,
            window.origin.1,
            if !window.floating && !frame.overlay {
                host_widths
                    .get(&anchor.window)
                    .map(|w| (*w as f32 * scale.width()).min(window.host_width))
                    .unwrap_or(window.size.0)
            } else {
                window.size.0
            },
            if window.floating { window.size.1 } else { window.size.1.min(window.host_height) },
        ));
        owner_grid = Some(window.grid);
    }
    Some(ResolvedFrame { bounds, clip, owner_clip, owner_grid })
}

#[derive(Default)]
pub(crate) struct NotebookRenderer {
    frames: Vec<NotebookFrame>,
    bindings: HashMap<(u64, u64), f64>,
    host_widths: HashMap<u64, u64>,
}
impl NotebookRenderer {
    pub(super) fn image_owner_transform(
        &mut self,
        anchor: ImageAnchor,
        scale: GridScale,
        windows: &[NotebookWindow],
    ) -> Option<ImageOwnerTransform> {
        let window = windows.iter().find(|window| window.window == anchor.window)?;
        let baseline = *self.bindings.entry((anchor.window, anchor.epoch)).or_insert(window.scroll);
        let scroll =
            if anchor.scroll { window.scroll_pixels(baseline, scale.height()) } else { 0.0 };
        Some(ImageOwnerTransform {
            origin: window.origin,
            offset: (window.origin.0, window.origin.1 + scroll),
            clip: window.content_clip,
        })
    }
    pub fn replace(&mut self, snapshot: FrameSnapshot) {
        let keys: HashSet<_> =
            snapshot.frames.iter().filter_map(|f| f.anchor.map(|a| (a.window, a.epoch))).collect();
        self.bindings.retain(|key, _| keys.contains(key));
        self.host_widths = snapshot.viewports.into_iter().map(|v| (v.window, v.width)).collect();
        self.frames = snapshot.frames;
    }
    pub fn clear(&mut self) {
        self.frames.clear();
        self.bindings.clear();
        self.host_widths.clear();
    }
    /// Hit regions use precisely the same owner binding and scroll transform
    /// as the visible frames. Only inline outputs take over native selection.
    pub fn output_bounds(
        &mut self,
        scale: GridScale,
        windows: &[NotebookWindow],
    ) -> Vec<(u64, Rect)> {
        self.frames
            .iter()
            .filter(|frame| frame.output && !frame.overlay)
            .filter_map(|frame| {
                let resolved =
                    resolve_frame(frame, scale, windows, &mut self.bindings, &self.host_widths)?;
                let mut bounds = resolved.bounds;
                if !bounds.intersect(resolved.clip) || !bounds.intersect(resolved.owner_clip?) {
                    return None;
                }
                Some((resolved.owner_grid?, bounds))
            })
            .collect()
    }
    pub fn draw(
        &mut self,
        canvas: &Canvas,
        scale: GridScale,
        overlay: bool,
        floating: &[super::WindowDrawDetails],
        windows: &[NotebookWindow],
    ) {
        for frame in self.frames.iter().filter(|f| f.overlay == overlay) {
            let Some(ResolvedFrame { bounds, clip, owner_clip, owner_grid }) =
                resolve_frame(frame, scale, windows, &mut self.bindings, &self.host_widths)
            else {
                continue;
            };
            canvas.save();
            canvas.clip_rect(clip, None, false);
            if let Some(owner_clip) = owner_clip {
                canvas.clip_rect(owner_clip, None, false);
            }
            if overlay {
                // The popup frame is allowed only inside its actual owner grid.
                // Never let an asynchronous stale snapshot decorate another menu.
                let owner = owner_grid
                    .and_then(|grid| floating.iter().position(|w| w.id == grid))
                    .or_else(|| {
                        if frame.anchor.is_some() {
                            None
                        } else {
                            floating.iter().position(|w| {
                                let r = to_skia_rect(&w.region);
                                // region includes the fractional gap filled at the window's
                                // right/bottom edge. Ownership uses the actual grid size;
                                // occlusion below still uses the complete painted region.
                                let width = w.grid_size.width as f32 * scale.width();
                                let height = w.grid_size.height as f32 * scale.height();
                                (r.left - clip.left).abs() < scale.width() * 0.55
                                    && (r.top - clip.top).abs() < scale.height() * 0.55
                                    && (width - clip.width()).abs() < scale.width() * 0.55
                                    && (height - clip.height()).abs() < scale.height() * 0.55
                            })
                        }
                    });
                let Some(owner) = owner else {
                    canvas.restore();
                    continue;
                };
                for (index, window) in floating.iter().enumerate() {
                    if index != owner {
                        canvas.clip_rect(
                            to_skia_rect(&window.region),
                            skia_safe::ClipOp::Difference,
                            false,
                        );
                    }
                }
            }
            let (r, g, b) = match (frame.output, frame.dark) {
                (false, false) => (173, 115, 42),
                (false, true) => (223, 169, 91),
                (true, false) => (44, 124, 150),
                (true, true) => (97, 181, 202),
            };
            let mut paint = Paint::default();
            paint.set_anti_alias(true);
            paint.set_style(Style::Stroke);
            let color = frame
                .color
                .map(|rgb| Color::from_rgb((rgb >> 16) as u8, (rgb >> 8) as u8, rgb as u8))
                .unwrap_or_else(|| Color::from_rgb(r, g, b));
            paint.set_color(color);
            // Same physical-pixel units as box_drawing's default thin=2.
            let stroke = if frame.active { 2.5 } else { 2.0 };
            paint.set_stroke_width(stroke);
            for gap in &frame.label_gaps {
                // The text-grid capsule owns this segment of the top edge.
                // Bounds already carry the owner's scroll/window animation.
                canvas.clip_rect(
                    Rect::from_xywh(
                        bounds.left + gap.col * scale.width(),
                        bounds.top - stroke,
                        gap.width * scale.width(),
                        stroke * 2.0,
                    ),
                    skia_safe::ClipOp::Difference,
                    false,
                );
            }
            for gap in &frame.footer_gaps {
                // A footer capsule is centered on the outer bottom stroke.
                // Keep the input/output seam and both vertical sides untouched.
                canvas.clip_rect(
                    Rect::from_xywh(
                        bounds.left + gap.col * scale.width(),
                        bounds.bottom - stroke,
                        gap.width * scale.width(),
                        stroke * 2.0,
                    ),
                    skia_safe::ClipOp::Difference,
                    false,
                );
            }
            let radius =
                (scale.height() * 0.42).min(bounds.height() / 2.0).min(bounds.width() / 2.0);
            match frame.join {
                None => {
                    canvas.draw_round_rect(bounds, radius, radius, &paint);
                }
                Some(ref join) => {
                    let (l, t, r, b) = (bounds.left, bounds.top, bounds.right, bounds.bottom);
                    let mut path = PathBuilder::new();
                    let weight = std::f32::consts::FRAC_1_SQRT_2;
                    match join {
                        FrameJoin::Top => {
                            // Open bottom: this section never paints a second
                            // horizontal seam underneath the output's green one.
                            path.move_to((l, b))
                                .line_to((l, t + radius))
                                .conic_to((l, t), (l + radius, t), weight)
                                .line_to((r - radius, t))
                                .conic_to((r, t), (r, t + radius), weight)
                                .line_to((r, b));
                        }
                        FrameJoin::Bottom => {
                            // Square top corners and one shared green seam;
                            // only the external bottom corners remain round.
                            path.move_to((l, t))
                                .line_to((l, b - radius))
                                .conic_to((l, b), (l + radius, b), weight)
                                .line_to((r - radius, b))
                                .conic_to((r, b), (r, b - radius), weight)
                                .line_to((r, t))
                                .close();
                        }
                    }
                    canvas.draw_path(&path.detach(), &paint);
                }
            }
            canvas.restore();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        editor::WindowType,
        units::{GridSize, PixelPos, PixelRect, PixelSize},
    };
    use skia_safe::surfaces;
    fn rect(row: f64, col: f64, width: f64, height: f64) -> Value {
        Value::Map(
            [("row", row), ("col", col), ("width", width), ("height", height)]
                .map(|(k, v)| (k.into(), v.into()))
                .to_vec(),
        )
    }
    fn packet() -> Value {
        Value::Map(vec![
            ("rect".into(), rect(-1.0, 1.0, 6.0, 5.0)),
            ("clip".into(), rect(0.0, 0.0, 10.0, 10.0)),
            ("kind".into(), "input".into()),
        ])
    }
    #[test]
    fn protocol_accepts_partial_offscreen_frames_and_rejects_invalid_geometry() {
        assert!(FrameSnapshot::parse(&[Value::Array(vec![packet()])]).is_ok());
        for bad in
            [rect(f64::NAN, 0.0, 1.0, 1.0), rect(0.0, 0.0, 0.0, 1.0), rect(0.0, 0.0, 1e9, 1.0)]
        {
            let Value::Map(mut fields) = packet() else { unreachable!() };
            fields[0].1 = bad;
            assert!(FrameSnapshot::parse(&[Value::Array(vec![Value::Map(fields)])]).is_err());
        }
        assert!(FrameSnapshot::parse(&[Value::Array(vec![packet(); 513])]).is_err());
        assert!(FrameSnapshot::parse(&[]).is_err());
    }
    #[test]
    fn notebook_viewport_preserves_host_border_but_clips_stale_snapshots_after_split_resize() {
        use super::super::{RenderedWindow, WindowDrawCommand};
        let scale: GridScale = PixelSize::new(10.0, 20.0).into();
        let mut window = RenderedWindow::new(2);
        window.handle_window_draw_command(WindowDrawCommand::Position {
            grid_position: (0.0, 0.0),
            grid_size: (8, 10),
            anchor_info: None,
            window_type: WindowType::Editor,
        });
        window.handle_window_draw_command(WindowDrawCommand::HostSize { width: 10, height: 10 });
        window.handle_window_draw_command(WindowDrawCommand::Viewport {
            window_id: 1000,
            scroll_delta: 0.0,
        });
        let Value::Map(mut fields) = packet() else { unreachable!() };
        fields[0].1 = rect(1.0, 1.0, 8.0, 4.0);
        fields.push((
            "anchor".into(),
            Value::Map(vec![("window".into(), 1000.into()), ("epoch".into(), 1.into())]),
        ));
        let viewport =
            Value::Map(vec![("window".into(), 1000.into()), ("width".into(), 10.into())]);
        let snapshot = FrameSnapshot::parse(&[
            Value::Array(vec![Value::Map(fields)]),
            Value::Array(vec![viewport]),
        ])
        .unwrap();
        assert_eq!(snapshot.viewports, [NotebookViewport { window: 1000, width: 10 }]);
        let mut renderer = NotebookRenderer::default();
        renderer.replace(snapshot);
        let mut surface = surfaces::raster_n32_premul((110, 210)).unwrap();
        let draw = |renderer: &mut NotebookRenderer,
                    window: &RenderedWindow,
                    surface: &mut skia_safe::Surface| {
            surface.canvas().clear(Color::WHITE);
            renderer.draw(
                surface.canvas(),
                scale,
                false,
                &[],
                &[NotebookWindow::from_window(window, scale).unwrap()],
            );
        };
        draw(&mut renderer, &window, &mut surface);
        assert_ne!(
            surface.peek_pixels().unwrap().get_color((90, 60)),
            Color::WHITE,
            "host frame survives beyond the eight-column text grid"
        );
        window.handle_window_draw_command(WindowDrawCommand::HostSize { width: 8, height: 10 });
        draw(&mut renderer, &window, &mut surface);
        assert_eq!(
            surface.peek_pixels().unwrap().get_color((90, 60)),
            Color::WHITE,
            "old ten-column snapshot cannot paint into the neighboring split"
        );
    }
    #[test]
    fn joined_cell_keeps_blue_top_green_bottom_and_one_straight_shared_seam() {
        let item = |kind: &str, join: &str, row: f64, height: f64, color: u32| {
            Value::Map(vec![
                ("rect".into(), rect(row, 1.0, 6.0, height)),
                ("clip".into(), rect(0.0, 0.0, 10.0, 10.0)),
                ("kind".into(), kind.into()),
                ("join".into(), join.into()),
                ("color".into(), color.into()),
            ])
        };
        let mut renderer = NotebookRenderer::default();
        renderer.replace(
            FrameSnapshot::parse(&[Value::Array(vec![
                item("input", "top", 1.0, 2.0, 0x5588cc),
                item("output", "bottom", 3.0, 4.0, 0x22cc77),
            ])])
            .unwrap(),
        );
        let mut surface = surfaces::raster_n32_premul((110, 160)).unwrap();
        surface.canvas().clear(Color::WHITE);
        renderer.draw(surface.canvas(), PixelSize::new(10.0, 20.0).into(), false, &[], &[]);
        let pixels = surface.peek_pixels().unwrap();
        assert_eq!(pixels.get_color((40, 59)), Color::from_rgb(0x22, 0xcc, 0x77));
        assert_eq!(pixels.get_color((40, 60)), Color::from_rgb(0x22, 0xcc, 0x77));
        assert_eq!(pixels.get_color((40, 61)), Color::WHITE, "seam has no second edge or fill");
        assert_eq!(pixels.get_color((10, 20)), Color::WHITE, "external top remains rounded");
        assert_eq!(
            pixels.get_color((10, 50)),
            Color::from_rgb(0x55, 0x88, 0xcc),
            "upper side is blue"
        );
        assert_eq!(
            pixels.get_color((10, 60)),
            Color::from_rgb(0x22, 0xcc, 0x77),
            "junction is straight, with no rounded gap"
        );
        assert_eq!(
            pixels.get_color((10, 90)),
            Color::from_rgb(0x22, 0xcc, 0x77),
            "lower vertical sides are green"
        );
        assert_eq!(
            pixels.get_color((40, 139)),
            Color::from_rgb(0x22, 0xcc, 0x77),
            "lower external edge is green"
        );
        assert_eq!(pixels.get_color((10, 140)), Color::WHITE, "external bottom remains rounded");
    }
    #[test]
    fn capsule_gaps_preserve_connecting_line_and_opaque_two_pixel_theme_stroke() {
        let Value::Map(mut fields) = packet() else { unreachable!() };
        fields[0].1 = rect(1.0, 1.0, 8.0, 4.0);
        fields.push(("color".into(), 0xaa5533_u32.into()));
        let gap = |col: f64, width: f64| {
            Value::Map(vec![("col".into(), col.into()), ("width".into(), width.into())])
        };
        fields.push(("label_gaps".into(), Value::Array(vec![gap(2.0, 1.0), gap(5.0, 1.0)])));
        let mut renderer = NotebookRenderer::default();
        renderer.replace(FrameSnapshot::parse(&[Value::Array(vec![Value::Map(fields)])]).unwrap());
        let mut surface = surfaces::raster_n32_premul((110, 130)).unwrap();
        surface.canvas().clear(Color::WHITE);
        renderer.draw(surface.canvas(), PixelSize::new(10.0, 20.0).into(), false, &[], &[]);
        let pixels = surface.peek_pixels().unwrap();
        assert_eq!(pixels.get_color((35, 20)), Color::WHITE, "type capsule has its own gap");
        assert_eq!(pixels.get_color((65, 20)), Color::WHITE, "run capsule has its own gap");
        let accent = Color::from_rgb(0xaa, 0x55, 0x33);
        assert_eq!(pixels.get_color((50, 19)), accent, "line connects both capsules");
        assert_eq!(pixels.get_color((50, 20)), accent, "inactive stroke is two opaque pixels");
        assert_eq!(pixels.get_color((35, 99)), accent, "gap only clips top, never bottom");
    }
    #[test]
    fn notebook_footer_gaps_are_optional_bounded_and_finite() {
        let parsed = NotebookFrame::parse(&packet()).unwrap();
        assert!(parsed.footer_gaps.is_empty(), "legacy packets keep the complete bottom edge");
        let gap = |col: f64, width: f64| {
            Value::Map(vec![("col".into(), col.into()), ("width".into(), width.into())])
        };
        for bad in [
            Value::Array(vec![gap(1.0, 1.0); 9]),
            Value::Array(vec![gap(f64::NAN, 1.0)]),
            Value::Array(vec![gap(-1.0, 1.0)]),
            Value::Array(vec![gap(1.0, f64::INFINITY)]),
            Value::Array(vec![gap(1.0, 0.0)]),
            Value::Array(vec![gap(1_000_001.0, 1.0)]),
            Value::Array(vec![Value::from("invalid")]),
        ] {
            let Value::Map(mut fields) = packet() else { unreachable!() };
            fields.push(("footer_gaps".into(), bad));
            assert!(NotebookFrame::parse(&Value::Map(fields)).is_err());
        }
        let Value::Map(mut fields) = packet() else { unreachable!() };
        fields.push(("footer_gaps".into(), Value::Array(vec![gap(2.25, 3.5)])));
        let parsed = NotebookFrame::parse(&Value::Map(fields)).unwrap();
        assert_eq!(parsed.footer_gaps, vec![LabelGap { col: 2.25, width: 3.5 }]);
    }
    #[test]
    fn notebook_footer_capsule_cuts_only_bottom_stroke_and_keeps_output_seam() {
        let Value::Map(mut fields) = packet() else { unreachable!() };
        fields[0].1 = rect(1.0, 1.0, 8.0, 4.0);
        fields[2].1 = "output".into();
        fields.push(("join".into(), "bottom".into()));
        fields.push(("color".into(), 0x22cc77_u32.into()));
        fields.push((
            "footer_gaps".into(),
            Value::Array(vec![Value::Map(vec![
                ("col".into(), 2.0.into()),
                ("width".into(), 2.0.into()),
            ])]),
        ));
        let mut renderer = NotebookRenderer::default();
        renderer.replace(FrameSnapshot::parse(&[Value::Array(vec![Value::Map(fields)])]).unwrap());
        let mut surface = surfaces::raster_n32_premul((110, 130)).unwrap();
        surface.canvas().clear(Color::WHITE);
        renderer.draw(surface.canvas(), PixelSize::new(10.0, 20.0).into(), false, &[], &[]);
        let pixels = surface.peek_pixels().unwrap();
        let accent = Color::from_rgb(0x22, 0xcc, 0x77);
        assert_eq!(pixels.get_color((35, 99)), Color::WHITE, "footer cuts both stroke pixels");
        assert_eq!(pixels.get_color((35, 100)), Color::WHITE, "footer cuts both stroke pixels");
        assert_eq!(pixels.get_color((60, 99)), accent, "remaining bottom edge stays opaque");
        assert_eq!(pixels.get_color((35, 20)), accent, "input/output seam remains complete");
        assert_eq!(pixels.get_color((10, 60)), accent, "left edge remains complete");
    }
    #[test]
    fn notebook_frames_follow_owner_scroll_and_mid_animation_reversal() {
        use super::super::{RenderedWindow, RendererSettings, WindowDrawCommand};
        use crate::units::{GridPos, GridRect};
        let scale: GridScale = PixelSize::new(10.0, 20.0).into();
        let settings = RendererSettings::default();
        let mut window = RenderedWindow::new(2);
        window.handle_window_draw_command(WindowDrawCommand::Position {
            grid_position: (1.0, 2.0),
            grid_size: (10, 20),
            anchor_info: None,
            window_type: WindowType::Editor,
        });
        window.handle_window_draw_command(WindowDrawCommand::Viewport {
            window_id: 1000,
            scroll_delta: 0.0,
        });
        window.flush(&settings);
        let viewport = GridRect::from_min_max(GridPos::new(0.0, 0.0), GridPos::new(30.0, 30.0));
        window.animate(&settings, &viewport, 0.016);
        let mut frame = NotebookFrame {
            rect: FrameRect { row: 10.0, col: 1.0, width: 6.0, height: 2.0 },
            clip: FrameRect { row: 0.0, col: 0.0, width: 10.0, height: 20.0 },
            output: false,
            join: None,
            active: true,
            overlay: false,
            dark: false,
            anchor: Some(FrameAnchor { window: 1000, epoch: 1, scroll: true }),
            color: None,
            label_gaps: vec![],
            footer_gaps: vec![],
        };
        let mut renderer = NotebookRenderer::default();
        renderer.replace(FrameSnapshot { frames: vec![frame.clone()], viewports: vec![] });
        let mut surface = surfaces::raster_n32_premul((320, 640)).unwrap();
        let check = |renderer: &mut NotebookRenderer,
                     window: &RenderedWindow,
                     surface: &mut skia_safe::Surface| {
            let owner = NotebookWindow::from_window(window, scale).unwrap();
            surface.canvas().clear(Color::WHITE);
            renderer.draw(surface.canvas(), scale, false, &[], std::slice::from_ref(&owner));
            // Follow the same real source line through the owner's scrollback:
            // grid_row_rect supplies its foreground transform; snap as the
            // actual text picture pass does for fractional scroll pixels.
            let row =
                10.0 - window.viewport_scroll as f32 - window.scroll_animation.position.floor();
            let expected =
                window.grid_row_rect(row as u32, 0, 0, scale).unwrap().top.round() as i32;
            let x = (owner.origin.0 + 40.0).round() as i32;
            assert_ne!(
                surface.peek_pixels().unwrap().get_color((x, expected)),
                Color::WHITE,
                "frame must match foreground row each animation frame, scroll={}, spring={}",
                window.viewport_scroll,
                window.scroll_animation.position
            );
        };
        check(&mut renderer, &window, &mut surface);
        for (turn, (delta, steps)) in
            [(3.0, 6), (2.0, 3), (-4.0, 4), (1.0, 4), (-2.0, 8)].into_iter().enumerate()
        {
            window.handle_window_draw_command(WindowDrawCommand::Viewport {
                window_id: 1000,
                scroll_delta: delta,
            });
            window.flush(&settings);
            for _ in 0..steps {
                window.animate(&settings, &viewport, 0.016);
                check(&mut renderer, &window, &mut surface);
            }
            if turn == 1 {
                // A real layout epoch is measured in the current logical
                // viewport. Rebinding during scroll must not apply delta twice.
                frame.rect.row = 10.0 - window.viewport_scroll as f32;
                frame.anchor.as_mut().unwrap().epoch = 2;
                renderer.replace(FrameSnapshot { frames: vec![frame.clone()], viewports: vec![] });
                check(&mut renderer, &window, &mut surface);
                window.handle_window_draw_command(WindowDrawCommand::Position {
                    grid_position: (4.0, 3.0),
                    grid_size: (10, 20),
                    anchor_info: None,
                    window_type: WindowType::Editor,
                });
            }
        }
    }

    #[test]
    fn native_round_stroke_clips_at_viewport_and_respects_other_float_grids() {
        let scale: GridScale = PixelSize::new(10.0, 20.0).into();
        let frame = NotebookFrame {
            rect: FrameRect { row: 1.0, col: 1.0, width: 6.0, height: 4.0 },
            clip: FrameRect { row: 0.0, col: 0.0, width: 9.0, height: 6.0 },
            output: true,
            join: None,
            active: true,
            overlay: true,
            dark: false,
            anchor: None,
            color: None,
            label_gaps: vec![],
            footer_gaps: vec![],
        };
        let mut renderer = NotebookRenderer::default();
        renderer.replace(FrameSnapshot { frames: vec![frame], viewports: vec![] });
        let region = |id, x, y, w, h| super::super::WindowDrawDetails {
            id,
            region: PixelRect::from_origin_and_size(PixelPos::new(x, y), PixelSize::new(w, h)),
            grid_size: GridSize::new(9, 6),
            window_type: WindowType::Editor,
        };
        let mut floating = vec![region(2, 0.0, 0.0, 90.0, 120.0), region(3, 0.0, 40.0, 30.0, 40.0)];
        let mut surface = surfaces::raster_n32_premul((100, 140)).unwrap();
        surface.canvas().clear(Color::WHITE);
        renderer.draw(surface.canvas(), scale, true, &floating, &[]);
        let pixels = surface.peek_pixels().unwrap();
        assert_eq!(pixels.get_color((10, 20)), Color::WHITE, "rounded corner is transparent");
        assert_ne!(pixels.get_color((70, 90)), Color::WHITE, "right stroke is visible");
        assert_eq!(pixels.get_color((10, 60)), Color::WHITE, "other popup masks frame stroke");
        assert_eq!(
            pixels.get_color((40, 60)),
            Color::WHITE,
            "frame never fills over editable content"
        );
        // The renderer fills a subcell remainder at the rightmost edge. That
        // expansion must not make this real output grid lose its frame owner.
        floating[0].region.max.x += 8.0; // 0.8 columns; owner grid remains 9x6.
        surface.canvas().clear(Color::WHITE);
        renderer.draw(surface.canvas(), scale, true, &floating, &[]);
        assert_ne!(
            surface.peek_pixels().unwrap().get_color((70, 90)),
            Color::WHITE,
            "right-edge subcell expansion preserves the output frame owner"
        );
        assert_eq!(
            surface.peek_pixels().unwrap().get_color((10, 60)),
            Color::WHITE,
            "other popup occlusion still uses the complete painted region"
        );
        renderer.clear();
        surface.canvas().clear(Color::WHITE);
        renderer.draw(surface.canvas(), scale, true, &floating, &[]);
        assert_eq!(surface.peek_pixels().unwrap().get_color((70, 90)), Color::WHITE);
    }
}
