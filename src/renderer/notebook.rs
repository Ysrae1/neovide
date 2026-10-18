//! Decoration-only Notebook frames. Geometry arrives as asynchronous snapshots;
//! editor text, cursor, execution and document serialization remain in Neovim.
use rmpv::Value;
use skia_safe::{Canvas, Color, Paint, Rect, paint::Style};
use std::collections::{HashMap, HashSet};

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
}
impl NotebookWindow {
    pub fn from_window(window: &super::RenderedWindow, scale: GridScale) -> Option<Self> {
        if window.hidden {
            return None;
        }
        let region = window.pixel_region(scale);
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
pub struct NotebookFrame {
    rect: FrameRect,
    clip: FrameRect,
    output: bool,
    active: bool,
    overlay: bool,
    dark: bool,
    anchor: Option<FrameAnchor>,
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
        })
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct FrameSnapshot(pub Vec<NotebookFrame>);
impl FrameSnapshot {
    pub fn parse(arguments: &[Value]) -> Result<Self, String> {
        let [frames] = arguments else {
            return Err("Notebook frames expects one array".into());
        };
        let frames = frames
            .as_array()
            .filter(|f| f.len() <= MAX_FRAMES)
            .ok_or("Notebook frames must be an array with at most 512 entries")?;
        Ok(Self(frames.iter().map(NotebookFrame::parse).collect::<Result<_, _>>()?))
    }
}

#[derive(Default)]
pub(crate) struct NotebookRenderer {
    frames: Vec<NotebookFrame>,
    bindings: HashMap<(u64, u64), f64>,
}
impl NotebookRenderer {
    pub fn replace(&mut self, snapshot: FrameSnapshot) {
        let keys: HashSet<_> =
            snapshot.0.iter().filter_map(|f| f.anchor.map(|a| (a.window, a.epoch))).collect();
        self.bindings.retain(|key, _| keys.contains(key));
        self.frames = snapshot.0;
    }
    pub fn clear(&mut self) {
        self.frames.clear();
        self.bindings.clear();
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
            let mut bounds = frame.rect.pixels(scale);
            let mut clip = frame.clip.pixels(scale);
            let mut owner_grid = None;
            let mut owner_clip = None;
            if let Some(anchor) = frame.anchor {
                let Some(window) = windows.iter().find(|w| w.window == anchor.window) else {
                    continue;
                };
                let baseline =
                    *self.bindings.entry((anchor.window, anchor.epoch)).or_insert(window.scroll);
                let scroll = if anchor.scroll {
                    window.scroll_pixels(baseline, scale.height())
                } else {
                    0.0
                };
                bounds = bounds.with_offset((window.origin.0, window.origin.1 + scroll));
                clip = clip.with_offset(window.origin);
                owner_clip = Some(Rect::from_xywh(
                    window.origin.0,
                    window.origin.1,
                    window.size.0,
                    window.size.1,
                ));
                owner_grid = Some(window.grid);
            }
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
            paint.set_color(Color::from_argb(if frame.active { 235 } else { 155 }, r, g, b));
            paint.set_stroke_width(
                (scale.height() * if frame.active { 0.065 } else { 0.045 }).clamp(1.0, 3.5),
            );
            let radius =
                (scale.height() * 0.42).min(bounds.height() / 2.0).min(bounds.width() / 2.0);
            canvas.draw_round_rect(bounds, radius, radius, &paint);
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
            active: true,
            overlay: false,
            dark: false,
            anchor: Some(FrameAnchor { window: 1000, epoch: 1, scroll: true }),
        };
        let mut renderer = NotebookRenderer::default();
        renderer.replace(FrameSnapshot(vec![frame.clone()]));
        let mut surface = surfaces::raster_n32_premul((320, 640)).unwrap();
        let check = |renderer: &mut NotebookRenderer,
                     window: &RenderedWindow,
                     surface: &mut skia_safe::Surface| {
            let owner = NotebookWindow::from_window(window, scale).unwrap();
            surface.canvas().clear(Color::WHITE);
            renderer.draw(surface.canvas(), scale, false, &[], &[owner.clone()]);
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
                renderer.replace(FrameSnapshot(vec![frame.clone()]));
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
            active: true,
            overlay: true,
            dark: false,
            anchor: None,
        };
        let mut renderer = NotebookRenderer::default();
        renderer.replace(FrameSnapshot(vec![frame]));
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
