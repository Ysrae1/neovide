use skia_safe::{
    BlendMode, Canvas, Color, Color4f, FilterMode, ImageFilter, Matrix, MipmapMode, Paint,
    RuntimeEffect, SamplingOptions, TileMode,
    canvas::{SaveLayerFlags, SaveLayerRec},
    image_filters,
    runtime_effect::RuntimeShaderBuilder,
};

use super::RendererSettings;

const EXTRACT_SOURCE: &str = include_str!("bloom_extract.sksl");
const GRADE_SOURCE: &str = include_str!("bloom_grade.sksl");
const BLOOM_SCALE: f32 = 0.5;

#[derive(Clone, Copy, PartialEq)]
struct FilterKey {
    background: Color,
    strength: f32,
    radius: f32,
    brightness: f32,
    saturation: f32,
}

/// Adds a filtered light layer over the already rendered, full-resolution frame.
///
/// The original canvas never enters the blur or downsampling passes. Skia owns
/// the GPU filter surfaces, so this path needs neither readback nor another
/// backend-specific rendering implementation.
pub struct BloomRenderer {
    effects: Option<(RuntimeEffect, RuntimeEffect)>,
    cached_key: Option<FilterKey>,
    cached_filter: Option<ImageFilter>,
}

impl Default for BloomRenderer {
    fn default() -> Self {
        let effects = (|| -> Result<_, String> {
            Ok((
                RuntimeEffect::make_for_shader(EXTRACT_SOURCE, None)?,
                RuntimeEffect::make_for_shader(GRADE_SOURCE, None)?,
            ))
        })();
        let effects = match effects {
            Ok(effects) => Some(effects),
            Err(error) => {
                log::warn!("Bloom disabled: could not compile the Skia effects: {error}");
                None
            }
        };

        Self { effects, cached_key: None, cached_filter: None }
    }
}

impl BloomRenderer {
    pub fn draw(&mut self, canvas: &Canvas, settings: &RendererSettings, background: Color) {
        let Some(filter) = self.filter_for(settings, background) else {
            return;
        };

        let mut paint = Paint::default();
        paint.set_blend_mode(BlendMode::Screen);

        // Blur coordinates are framebuffer pixels, independent of the editor's
        // font scale or any caller transform. The existing device clip remains.
        canvas.save();
        canvas.reset_matrix();
        // Retain faint linear-light values between blur/grade passes, rather
        // than quantizing the soft halo to 8-bit steps before gamma conversion.
        canvas.save_layer(
            &SaveLayerRec::default()
                .backdrop(&filter)
                .flags(SaveLayerFlags::F16_COLOR_TYPE)
                .paint(&paint),
        );
        canvas.restore();
        canvas.restore();
    }

    /// Returns the cached filter tree, rebuilding only when its inputs change.
    /// Kept separate from draw so the light layer can also be checked on a raster
    /// canvas without requiring a native window or GPU readback.
    pub(super) fn filter_for(
        &mut self,
        settings: &RendererSettings,
        background: Color,
    ) -> Option<ImageFilter> {
        if !settings.bloom || self.effects.is_none() {
            return None;
        }

        let key = FilterKey {
            background,
            strength: finite_clamp(settings.bloom_strength, 0.0, 1.0),
            radius: finite_clamp(settings.bloom_radius, 0.0, 32.0),
            brightness: finite_clamp(settings.bloom_brightness, 0.0, 8.0),
            saturation: finite_clamp(settings.bloom_saturation, 0.0, 3.0),
        };
        if key.strength <= 0.0 || key.radius <= 0.0 || key.brightness <= 0.0 {
            return None;
        }

        if self.cached_key != Some(key) {
            self.cached_filter = self.build_filter(key);
            self.cached_key = Some(key);
            if self.cached_filter.is_none() {
                log::warn!(
                    "Bloom unavailable for the current settings; keeping the original frame"
                );
            }
        }

        self.cached_filter.clone()
    }

    fn build_filter(&self, key: FilterKey) -> Option<ImageFilter> {
        let (extract_effect, grade_effect) = self.effects.as_ref()?;
        let background = Color4f::from(key.background);

        let mut extract = RuntimeShaderBuilder::new(extract_effect.clone());
        extract
            .set_uniform_float("background", &[background.r, background.g, background.b])
            .ok()?;
        let source = image_filters::runtime_shader(&extract, "source", None)?;

        // Extract before reducing resolution, so thin bright glyphs cannot fall
        // below the bright-pass threshold merely because they were averaged.
        let sampling = SamplingOptions::new(FilterMode::Linear, MipmapMode::None);
        let reduced = image_filters::matrix_transform(
            &Matrix::scale((BLOOM_SCALE, BLOOM_SCALE)),
            sampling,
            Some(source),
        )?;
        let sigma = (key.radius / 3.0).max(0.5) * BLOOM_SCALE;
        let blurred =
            image_filters::blur((sigma, sigma), Some(TileMode::Decal), Some(reduced), None)?;

        // Grade the linear light energy once per reduced pixel. Scaling the
        // Gaussian sigma alongside the image preserves its displayed radius.
        let mut grade = RuntimeShaderBuilder::new(grade_effect.clone());
        grade.set_uniform_float("strength", &[key.strength]).ok()?;
        grade.set_uniform_float("brightness", &[key.brightness]).ok()?;
        grade.set_uniform_float("saturation", &[key.saturation]).ok()?;
        let graded = image_filters::runtime_shader(&grade, "source", Some(blurred))?;

        image_filters::matrix_transform(
            &Matrix::scale((1.0 / BLOOM_SCALE, 1.0 / BLOOM_SCALE)),
            sampling,
            Some(graded),
        )
    }
}

fn finite_clamp(value: f32, minimum: f32, maximum: f32) -> f32 {
    if value.is_finite() { value.clamp(minimum, maximum) } else { minimum }
}
