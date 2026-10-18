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
    units::{GridScale, to_skia_rect},
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
}

#[derive(Default)]
pub(crate) struct ImageRenderer {
    previews: BTreeMap<u64, Preview>,
}

impl ImageRenderer {
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
            let mut region = Path::rect(view_bounds(view, scale), None);
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
                }
            }
            ImageCommand::Hide(id) => {
                if let Some(preview) = self.previews.get_mut(&id) {
                    preview.view = None;
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
            let bounds = view_bounds(view, scale);
            let destination = image_destination(
                bounds,
                image.image.width() as f32,
                image.image.height() as f32,
                view,
            );
            canvas.save();
            canvas.clip_rect(bounds, None, false);
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

fn view_bounds(view: &ImageView, scale: GridScale) -> Rect {
    Rect::from_xywh(
        view.col * scale.width(),
        view.row * scale.height(),
        view.width * scale.width(),
        view.height * scale.height(),
    )
}

fn image_destination(bounds: Rect, width: f32, height: f32, view: &ImageView) -> Rect {
    let scale = (bounds.width() / width).min(bounds.height() / height) * view.zoom;
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
        }
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
