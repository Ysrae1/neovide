//! Native raster previews. File I/O and decoding happen in the bridge worker.
use std::{
    collections::BTreeMap,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
};

use skia_safe::{
    AlphaType, Canvas, ColorType, Data, FilterMode, Image, ImageInfo, MipmapMode, Paint, Path,
    PathOp, Rect, SamplingOptions, canvas::SrcRectConstraint, images,
};

use crate::{
    image_preview::{DecodedImage, ImageView},
    units::{GridScale, PixelRect, to_skia_rect},
};

#[derive(Clone, Debug)]
pub struct PreparedImage {
    pub image: Image,
    pub live: Arc<AtomicBool>,
}

impl PartialEq for PreparedImage {
    fn eq(&self, other: &Self) -> bool {
        self.image.unique_id() == other.image.unique_id() && Arc::ptr_eq(&self.live, &other.live)
    }
}

impl PreparedImage {
    /// This also runs on the worker: the GUI never copies or lazily decodes encoded files.
    pub fn new(decoded: DecodedImage, live: Arc<AtomicBool>) -> Result<Self, String> {
        let info = ImageInfo::new(
            (decoded.width as i32, decoded.height as i32),
            ColorType::RGBA8888,
            AlphaType::Unpremul,
            skia_safe::ColorSpace::new_srgb(),
        );
        let image = images::raster_from_data(
            &info,
            Data::new_copy(&decoded.pixels),
            decoded.width as usize * 4,
        )
        .ok_or("Cannot allocate native image")?;
        Ok(Self { image, live })
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum ImageCommand {
    Begin(u64),
    Ready(u64, PreparedImage),
    Show(u64, ImageView),
    Hide(u64),
    Close(u64),
}

#[derive(Default)]
struct Preview {
    image: Option<PreparedImage>,
    view: Option<ImageView>,
    resolved: Option<ResolvedImageView>,
}

#[derive(Clone, Copy)]
struct ResolvedImageView {
    bounds: Rect,
    clip: Rect,
}

#[derive(Default)]
pub(crate) struct ImageRenderer {
    previews: BTreeMap<u64, Preview>,
    anchored_occlusions: Vec<Rect>,
}

impl ImageRenderer {
    pub fn prepare_anchored_views(
        &mut self,
        scale: GridScale,
        notebooks: &mut super::notebook::NotebookRenderer,
        windows: &[super::notebook::NotebookWindow],
        floating: &[PixelRect<f32>],
    ) {
        self.anchored_occlusions = floating.iter().map(to_skia_rect).collect();
        for preview in self.previews.values_mut() {
            preview.resolved = None;
            let Some(view) = preview.view else {
                continue;
            };
            let Some(anchor) = view.anchor else {
                continue;
            };
            let Some(owner) = notebooks.image_owner_transform(anchor, scale, windows) else {
                continue;
            };
            let bounds = view_bounds(&view, scale).with_offset(owner.offset);
            let mut clip = view
                .clip
                .map(|clip| {
                    Rect::from_xywh(
                        clip.col * scale.width(),
                        clip.row * scale.height(),
                        clip.width * scale.width(),
                        clip.height * scale.height(),
                    )
                    .with_offset(owner.origin)
                })
                .unwrap_or(owner.clip);
            if clip.intersect(owner.clip) && clip.intersect(bounds) {
                preview.resolved = Some(ResolvedImageView { bounds, clip });
            }
        }
    }
    /// Keep the editor's bloom, but do not grade the preview's pixels. Floating
    /// windows over a preview remain part of the normal editor light layer.
    pub fn bloom_exclusion(
        &self,
        scale: GridScale,
        floating: &[super::WindowDrawDetails],
    ) -> Option<Path> {
        let mut mask: Option<Path> = None;
        for preview in self.previews.values() {
            let (Some(image), Some(view)) = (&preview.image, &preview.view) else { continue };
            if !image.live.load(Ordering::Acquire) {
                continue;
            }
            let Some(resolved) = resolved_view(preview, scale) else {
                continue;
            };
            let mut region = Path::rect(resolved.clip, None);
            if !view.overlay {
                for window in floating {
                    region = region
                        .op(&Path::rect(to_skia_rect(&window.region), None), PathOp::Difference)?;
                }
            }
            mask = Some(match mask {
                Some(mask) => mask.op(&region, PathOp::Union)?,
                None => region,
            });
        }
        mask
    }

    pub fn clear(&mut self) {
        for preview in self.previews.values() {
            if let Some(image) = &preview.image {
                image.live.store(false, Ordering::Release);
            }
        }
        self.previews.clear();
        self.anchored_occlusions.clear();
    }

    pub fn handle(&mut self, command: ImageCommand) {
        match command {
            ImageCommand::Begin(id) => {
                self.previews.insert(id, Preview::default());
            }
            ImageCommand::Ready(id, image) => {
                if image.live.load(Ordering::Acquire)
                    && let Some(preview) = self.previews.get_mut(&id)
                {
                    preview.image = Some(image);
                }
            }
            ImageCommand::Show(id, view) => {
                if let Some(preview) = self.previews.get_mut(&id) {
                    preview.view = Some(view);
                    preview.resolved = None;
                }
            }
            ImageCommand::Hide(id) => {
                if let Some(preview) = self.previews.get_mut(&id) {
                    preview.view = None;
                    preview.resolved = None;
                }
            }
            ImageCommand::Close(id) => {
                self.previews.remove(&id);
            }
        }
    }

    pub fn draw(&self, canvas: &Canvas, scale: GridScale) {
        self.draw_layer(canvas, scale, false);
    }

    pub fn draw_overlay(&self, canvas: &Canvas, scale: GridScale) {
        self.draw_layer(canvas, scale, true);
    }

    fn draw_layer(&self, canvas: &Canvas, scale: GridScale, overlay: bool) {
        for preview in self.previews.values() {
            let (Some(image), Some(view)) = (&preview.image, &preview.view) else { continue };
            if !image.live.load(Ordering::Acquire) || view.overlay != overlay {
                continue;
            }
            let Some(resolved) = resolved_view(preview, scale) else {
                continue;
            };
            let bounds = resolved.bounds;
            let destination = image_destination(
                bounds,
                image.image.width() as f32,
                image.image.height() as f32,
                view,
            );
            canvas.save();
            canvas.clip_rect(resolved.clip, None, false);
            if view.anchor.is_some() && !view.overlay {
                for region in &self.anchored_occlusions {
                    canvas.clip_rect(region, skia_safe::ClipOp::Difference, false);
                }
            }
            canvas.draw_image_rect_with_sampling_options(
                &image.image,
                Some((
                    &Rect::from_wh(image.image.width() as f32, image.image.height() as f32),
                    SrcRectConstraint::Strict,
                )),
                destination,
                SamplingOptions::new(FilterMode::Linear, MipmapMode::None),
                &Paint::default(),
            );
            canvas.restore();
        }
    }
}

fn resolved_view(preview: &Preview, scale: GridScale) -> Option<ResolvedImageView> {
    let view = preview.view?;
    if view.anchor.is_some() {
        return preview.resolved;
    }
    let bounds = view_bounds(&view, scale);
    let mut clip = view
        .clip
        .map(|clip| {
            Rect::from_xywh(
                clip.col * scale.width(),
                clip.row * scale.height(),
                clip.width * scale.width(),
                clip.height * scale.height(),
            )
        })
        .unwrap_or(bounds);
    clip.intersect(bounds).then_some(ResolvedImageView { bounds, clip })
}

fn view_bounds(view: &ImageView, scale: GridScale) -> Rect {
    Rect::from_xywh(
        view.col * scale.width(),
        view.row * scale.height(),
        view.width * scale.width(),
        view.height * scale.height(),
    )
}

fn image_destination(bounds: Rect, width: f32, height: f32, view: &ImageView) -> Rect {
    let fit = (bounds.width() / width).min(bounds.height() / height);
    // Font zoom can reach the renderer before Lua's new cell metrics/padding.
    // Keep inline pixels at natural size during that interval too. Absolute
    // previews and existing image popups retain their original fit behavior.
    let fit = if view.anchor.is_some() && !view.overlay { fit.min(1.0) } else { fit };
    let scale = fit * view.zoom;
    let (w, h) = (width * scale, height * scale);
    Rect::from_xywh(
        bounds.center_x() - w / 2.0 - view.pan_x * scale,
        bounds.center_y() - h / 2.0 - view.pan_y * scale,
        w,
        h,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use skia_safe::{Color, surfaces};

    fn view() -> ImageView {
        ImageView {
            row: 2.0,
            col: 2.0,
            width: 6.0,
            height: 6.0,
            zoom: 1.0,
            pan_x: 0.0,
            pan_y: 0.0,
            overlay: false,
            anchor: None,
            clip: None,
        }
    }

    #[test]
    fn native_image_anchor_shares_notebook_scroll_and_clips_owner_floats_and_lifetime() {
        use crate::{
            editor::WindowType,
            image_preview::{ImageAnchor, ImageClip},
            renderer::{
                RenderedWindow, WindowDrawCommand,
                notebook::{FrameSnapshot, NotebookRenderer, NotebookWindow},
            },
            units::{GridPos, PixelPos, PixelSize},
        };
        use rmpv::Value;

        let scale = PixelSize::new(10.0, 10.0).into();
        let image = PreparedImage::new(
            DecodedImage { pixels: [255, 0, 0, 255].repeat(800), width: 40, height: 20 },
            Arc::new(AtomicBool::new(true)),
        )
        .unwrap();
        let mut renderer = ImageRenderer::default();
        renderer.handle(ImageCommand::Begin(1));
        renderer.handle(ImageCommand::Ready(1, image.clone()));
        let mut surface = surfaces::raster_n32_premul((150, 120)).unwrap();
        // Existing absolute and popup images need no owner or anchor preparation.
        renderer.handle(ImageCommand::Show(1, view()));
        surface.canvas().clear(Color::BLUE);
        renderer.draw(surface.canvas(), scale);
        assert_eq!(surface.peek_pixels().unwrap().get_color((50, 50)), Color::RED);
        let mut popup = view();
        popup.overlay = true;
        renderer.handle(ImageCommand::Show(1, popup));
        surface.canvas().clear(Color::BLUE);
        renderer.draw(surface.canvas(), scale);
        assert_eq!(surface.peek_pixels().unwrap().get_color((50, 50)), Color::BLUE);
        renderer.draw_overlay(surface.canvas(), scale);
        assert_eq!(surface.peek_pixels().unwrap().get_color((50, 50)), Color::RED);

        let anchor = ImageAnchor { window: 1000, epoch: 9, scroll: true };
        let mut owner = RenderedWindow::new(2);
        owner.handle_window_draw_command(WindowDrawCommand::Position {
            grid_position: (2.0, 1.0),
            grid_size: (10, 8),
            anchor_info: None,
            window_type: WindowType::Editor,
        });
        owner.handle_window_draw_command(WindowDrawCommand::HostSize { width: 10, height: 8 });
        owner.handle_window_draw_command(WindowDrawCommand::Viewport {
            window_id: 1000,
            scroll_delta: 10.0,
        });
        owner.handle_window_draw_command(WindowDrawCommand::ViewportMargins {
            top: 1,
            bottom: 0,
            left: 0,
            right: 0,
        });
        owner.grid_current_position = GridPos::new(2.0, 1.0);
        let mut notebooks = NotebookRenderer::default();
        let rect = |row: f64, col: f64, width: f64, height: f64| {
            Value::Map(vec![
                ("row".into(), row.into()),
                ("col".into(), col.into()),
                ("width".into(), width.into()),
                ("height".into(), height.into()),
            ])
        };
        notebooks.replace(
            FrameSnapshot::parse(&[Value::Array(vec![Value::Map(vec![
                ("kind".into(), "output".into()),
                ("rect".into(), rect(2.0, 1.0, 4.0, 2.0)),
                ("clip".into(), rect(1.0, 0.0, 10.0, 5.0)),
                (
                    "anchor".into(),
                    Value::Map(vec![
                        ("window".into(), 1000.into()),
                        ("epoch".into(), 9.into()),
                        ("scroll".into(), true.into()),
                    ]),
                ),
            ])])])
            .unwrap(),
        );
        let windows = vec![NotebookWindow::from_window(&owner, scale).unwrap()];
        assert_eq!(
            notebooks.output_bounds(scale, &windows)[0].1,
            Rect::from_xywh(30.0, 30.0, 40.0, 20.0)
        );
        let mut anchored = view();
        anchored.row = 2.0;
        anchored.col = 1.0;
        anchored.width = 4.0;
        anchored.height = 2.0;
        anchored.anchor = Some(anchor);
        anchored.clip = Some(ImageClip { row: 1.0, col: 0.0, width: 10.0, height: 5.0 });
        renderer.handle(ImageCommand::Show(1, anchored));
        // Bind the image after a viewport update: it must reuse the frame's
        // existing epoch baseline, rather than jump a whole row ahead.
        owner.viewport_scroll = 11.0;
        owner.scroll_animation.position = -0.65;
        let windows = vec![NotebookWindow::from_window(&owner, scale).unwrap()];
        let floating = [PixelRect::from_origin_and_size(
            PixelPos::new(40.0, 25.0),
            PixelSize::new(10.0, 30.0),
        )];
        renderer.prepare_anchored_views(scale, &mut notebooks, &windows, &floating);
        let resolved = renderer.previews[&1].resolved.unwrap();
        assert_eq!(resolved.bounds, notebooks.output_bounds(scale, &windows)[0].1);
        assert_eq!(resolved.bounds.top, 26.0, "same rounded spring transform as frame/text");
        surface.canvas().clear(Color::BLUE);
        renderer.draw(surface.canvas(), scale);
        let pixels = surface.peek_pixels().unwrap();
        assert_eq!(pixels.get_color((35, 30)), Color::RED);
        assert_eq!(pixels.get_color((45, 30)), Color::BLUE, "topmost float keeps its pixels");
        assert_eq!(
            pixels.get_color((35, 19)),
            Color::BLUE,
            "winbar is outside owner inner viewport"
        );
        owner.viewport_scroll = 13.0;
        owner.scroll_animation.position = 0.0;
        let windows = vec![NotebookWindow::from_window(&owner, scale).unwrap()];
        renderer.prepare_anchored_views(scale, &mut notebooks, &windows, &[]);
        assert!(renderer.previews[&1].resolved.is_none(), "offscreen output is fully clipped");
        owner.viewport_scroll = 10.0;
        owner.grid_current_position = GridPos::new(3.0, 2.0);
        owner.handle_window_draw_command(WindowDrawCommand::HostSize { width: 4, height: 8 });
        let windows = vec![NotebookWindow::from_window(&owner, scale).unwrap()];
        renderer.prepare_anchored_views(scale, &mut notebooks, &windows, &[]);
        surface.canvas().clear(Color::BLUE);
        renderer.draw(surface.canvas(), scale);
        let pixels = surface.peek_pixels().unwrap();
        assert_eq!(pixels.get_color((65, 45)), Color::RED, "owner movement follows the window");
        assert_eq!(
            pixels.get_color((75, 45)),
            Color::BLUE,
            "stale actual width cannot escape latest host"
        );
        owner.hidden = true;
        let windows = NotebookWindow::from_window(&owner, scale).into_iter().collect::<Vec<_>>();
        renderer.prepare_anchored_views(scale, &mut notebooks, &windows, &[]);
        assert!(renderer.previews[&1].resolved.is_none());
        assert!(
            renderer.bloom_exclusion(scale, &[]).is_none(),
            "hidden owner has no stale pixel mask"
        );
        renderer.handle(ImageCommand::Hide(1));
        assert!(renderer.previews[&1].view.is_none());
        renderer.handle(ImageCommand::Close(1));
        renderer.handle(ImageCommand::Ready(1, image));
        assert!(
            renderer.previews.is_empty(),
            "close releases the view and rejects late completion"
        );
    }

    #[test]
    fn fit_preserves_aspect_and_zoom_is_centered() {
        let mut v = view();
        let bounds = Rect::from_xywh(20.0, 20.0, 60.0, 60.0);
        assert_eq!(
            image_destination(bounds, 120.0, 60.0, &v),
            Rect::from_xywh(20.0, 35.0, 60.0, 30.0)
        );
        v.zoom = 2.0;
        assert_eq!(
            image_destination(bounds, 120.0, 60.0, &v),
            Rect::from_xywh(-10.0, 20.0, 120.0, 60.0)
        );
    }

    #[test]
    fn native_inline_intrinsic_size_never_upscales_during_metric_updates() {
        let mut inline = view();
        inline.anchor =
            Some(crate::image_preview::ImageAnchor { window: 1000, epoch: 1, scroll: true });
        let large = Rect::from_xywh(0.0, 0.0, 1400.0, 1100.0);
        let natural = image_destination(large, 547.0, 434.0, &inline);
        assert_eq!((natural.width(), natural.height()), (547.0, 434.0));
        let small = image_destination(Rect::from_wh(200.0, 100.0), 547.0, 434.0, &inline);
        assert!(small.width() < 547.0 && small.height() <= 100.0);
        inline.anchor = None;
        let popup = image_destination(large, 547.0, 434.0, &inline);
        assert!(popup.width() > 547.0 && popup.height() > 434.0, "existing popup fit is unchanged");
    }

    #[test]
    fn zoom_is_clipped_and_close_releases_pixels_and_rejects_late_completion() {
        for background in [Color::WHITE, Color::BLACK] {
            let mut renderer = ImageRenderer::default();
            let live = Arc::new(AtomicBool::new(true));
            let image = PreparedImage::new(
                DecodedImage { pixels: [255, 0, 0, 255].repeat(8), width: 4, height: 2 },
                live.clone(),
            )
            .unwrap();
            renderer.handle(ImageCommand::Begin(1));
            renderer.handle(ImageCommand::Ready(1, image.clone()));
            let mut v = view();
            v.zoom = 4.0;
            renderer.handle(ImageCommand::Show(1, v));
            let mut surface = surfaces::raster_n32_premul((100, 100)).unwrap();
            surface.canvas().clear(background);
            renderer.draw(surface.canvas(), crate::units::PixelSize::new(10.0, 10.0).into());
            let pix = surface.peek_pixels().unwrap();
            assert_eq!(pix.get_color((10, 50)), background);
            assert_eq!(pix.get_color((50, 50)), Color::RED);
            let before = pix.bytes().unwrap().to_vec();
            surface.canvas().save();
            surface.canvas().clip_path(
                &renderer
                    .bloom_exclusion(crate::units::PixelSize::new(10.0, 10.0).into(), &[])
                    .unwrap(),
                skia_safe::ClipOp::Difference,
                false,
            );
            super::super::bloom::BloomRenderer::default().draw(
                surface.canvas(),
                &super::super::RendererSettings::default(),
                background,
            );
            surface.canvas().restore();
            let after = surface.peek_pixels().unwrap();
            let center = (50 * 100 + 50) * 4;
            assert_eq!(
                &after.bytes().unwrap()[center..center + 4],
                &before[center..center + 4],
                "editor bloom must not change preview pixels"
            );
            renderer.handle(ImageCommand::Hide(1));
            assert!(renderer.previews[&1].view.is_none());
            live.store(false, Ordering::Release);
            renderer.handle(ImageCommand::Close(1));
            renderer.handle(ImageCommand::Ready(1, image));
            assert!(renderer.previews.is_empty());
            assert_eq!(Arc::strong_count(&live), 1);
        }
    }
    #[test]
    fn output_float_overlay_is_separate_and_excluded_from_bloom() {
        let mut renderer = ImageRenderer::default();
        let image = PreparedImage::new(
            DecodedImage { pixels: [255, 0, 0, 255].repeat(8), width: 4, height: 2 },
            Arc::new(AtomicBool::new(true)),
        )
        .unwrap();
        let mut v = view();
        v.overlay = true;
        renderer.handle(ImageCommand::Begin(1));
        renderer.handle(ImageCommand::Ready(1, image));
        renderer.handle(ImageCommand::Show(1, v));
        let scale = crate::units::PixelSize::new(10.0, 10.0).into();
        let mut surface = surfaces::raster_n32_premul((100, 100)).unwrap();
        surface.canvas().clear(Color::BLUE);
        renderer.draw(surface.canvas(), scale);
        assert_eq!(surface.peek_pixels().unwrap().get_color((50, 50)), Color::BLUE);
        renderer.draw_overlay(surface.canvas(), scale);
        assert_eq!(surface.peek_pixels().unwrap().get_color((50, 50)), Color::RED);
        let mask = renderer.bloom_exclusion(scale, &[]).unwrap();
        assert!(mask.contains((50.0, 50.0)));
        renderer.handle(ImageCommand::Close(1));
        assert!(renderer.bloom_exclusion(scale, &[]).is_none());
    }
}
