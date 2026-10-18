//! The local raster-image preview protocol and bounded decoder.
//!
//! `decode_image` performs blocking file I/O and decoding. Call it on a worker,
//! never on the editor or render thread. Each call owns its input and result;
//! dropping a stale result or closing a preview releases those resources.

use std::{
    fs::File,
    io::{Cursor, Read},
};

use image::{DynamicImage, ImageDecoder, ImageFormat, ImageReader, Limits};
use rmpv::Value;

const MAX_INPUT_BYTES: u64 = 64 * 1024 * 1024;
const MAX_DECODED_BYTES: u64 = 128 * 1024 * 1024;

/// Owned, non-premultiplied RGBA8 pixels, ready to upload on the render thread.
#[derive(Debug)]
pub struct DecodedImage {
    pub pixels: Vec<u8>,
    pub width: u32,
    pub height: u32,
}

/// Image viewport in editor grid coordinates, with pan measured in pixels.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ImageView {
    pub row: f32,
    pub col: f32,
    pub width: f32,
    pub height: f32,
    pub zoom: f32,
    pub pan_x: f32,
    pub pan_y: f32,
    /// Molten images inside an editor output float use the overlay pass.
    pub overlay: bool,
}

impl ImageView {
    pub fn parse(value: &Value) -> Result<Self, String> {
        let fields = value.as_map().ok_or_else(|| "Image viewport must be a map".to_owned())?;
        let number = |key: &str, default: Option<f32>| -> Result<f32, String> {
            let value =
                fields.iter().find(|(name, _)| name.as_str() == Some(key)).map(|(_, value)| value);
            let Some(value) = value else {
                return default.ok_or_else(|| format!("Image viewport is missing {key}"));
            };
            let number =
                value.as_f64().ok_or_else(|| format!("Image viewport {key} must be a number"))?
                    as f32;
            if !number.is_finite() {
                return Err(format!("Image viewport {key} must be finite"));
            }
            Ok(number)
        };
        let view = Self {
            row: number("row", None)?,
            col: number("col", None)?,
            width: number("width", None)?,
            height: number("height", None)?,
            zoom: number("zoom", Some(1.0))?,
            pan_x: number("pan_x", Some(0.0))?,
            pan_y: number("pan_y", Some(0.0))?,
            overlay: match fields.iter().find(|(name, _)| name.as_str() == Some("overlay")) {
                Some((_, value)) => value.as_bool().ok_or("Image overlay must be a boolean")?,
                None => false,
            },
        };
        if view.row < 0.0 || view.col < 0.0 {
            return Err("Image viewport row and col must be nonnegative".to_owned());
        }
        if view.width <= 0.0 || view.height <= 0.0 || view.zoom <= 0.0 {
            return Err("Image viewport width, height and zoom must be positive".to_owned());
        }
        if [view.row, view.col, view.width, view.height]
            .into_iter()
            .any(|value| value > 1_000_000.0)
            || view.pan_x.abs() > 1_000_000.0
            || view.pan_y.abs() > 1_000_000.0
        {
            return Err("Image viewport coordinates exceed the supported range".to_owned());
        }
        if !(0.05..=32.0).contains(&view.zoom) {
            return Err("Image preview zoom must be between 0.05 and 32".to_owned());
        }
        Ok(view)
    }
}

/// Decode the first frame of a local raster image, with bounded input/output.
///
/// Format detection uses the file contents, so an incorrect or missing extension
/// is harmless. SVG, URLs and other formats are deliberately unsupported.
pub fn decode_image(path: &str) -> Result<DecodedImage, String> {
    let file = File::open(path).map_err(|error| format!("Cannot open image: {error}"))?;
    let metadata = file.metadata().map_err(|error| format!("Cannot inspect image: {error}"))?;
    if !metadata.is_file() {
        return Err("Image preview requires a local regular file".to_owned());
    }
    if metadata.len() > MAX_INPUT_BYTES {
        return Err("Image file exceeds the 64 MiB preview limit".to_owned());
    }

    // The extra byte detects a file that grows after the metadata check. Reading
    // into an owned buffer also prevents later file changes affecting decoding.
    let mut bytes = Vec::new();
    file.take(MAX_INPUT_BYTES + 1)
        .read_to_end(&mut bytes)
        .map_err(|error| format!("Cannot read image: {error}"))?;
    if bytes.len() as u64 > MAX_INPUT_BYTES {
        return Err("Image file exceeds the 64 MiB preview limit".to_owned());
    }
    decode_bytes(bytes)
}

fn decode_bytes(bytes: Vec<u8>) -> Result<DecodedImage, String> {
    let mut reader = ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()
        .map_err(|error| format!("Cannot identify image: {error}"))?;
    if !matches!(
        reader.format(),
        Some(
            ImageFormat::Png
                | ImageFormat::Jpeg
                | ImageFormat::Gif
                | ImageFormat::WebP
                | ImageFormat::Bmp
                | ImageFormat::Tiff
                | ImageFormat::Ico
        )
    ) {
        return Err(
            "Unsupported image format (use PNG, JPEG, GIF, WebP, BMP, TIFF or ICO)".to_owned()
        );
    }
    let mut limits = Limits::default();
    // Width/height are strict decoder limits. The pixel-product checks below
    // enforce the actual decoded-buffer bound before allocation, including
    // decoders whose internal allocation limits are only best effort.
    limits.max_image_width = Some((MAX_DECODED_BYTES / 4) as u32);
    limits.max_image_height = Some((MAX_DECODED_BYTES / 4) as u32);
    limits.max_alloc = Some(MAX_DECODED_BYTES);
    reader.limits(limits);
    let decoder =
        reader.into_decoder().map_err(|error| format!("Cannot read image header: {error}"))?;
    let (width, height) = decoder.dimensions();
    let rgba_bytes = u64::from(width)
        .checked_mul(u64::from(height))
        .and_then(|pixels| pixels.checked_mul(4))
        .filter(|bytes| *bytes > 0 && *bytes <= MAX_DECODED_BYTES)
        .ok_or_else(|| "Image dimensions exceed the 128 MiB preview limit".to_owned())?;
    if decoder.total_bytes() > MAX_DECODED_BYTES {
        return Err("Decoded image exceeds the 128 MiB preview limit".to_owned());
    }
    let image = DynamicImage::from_decoder(decoder)
        .map_err(|error| format!("Cannot decode image: {error}"))?;
    let pixels = image.into_rgba8().into_raw();
    if pixels.len() as u64 != rgba_bytes {
        return Err("Decoded image has an invalid pixel buffer".to_owned());
    }
    Ok(DecodedImage { pixels, width, height })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        fs,
        path::PathBuf,
        sync::atomic::{AtomicU64, Ordering},
    };

    use image::{Frame, Rgba, RgbaImage, codecs::gif::GifEncoder};

    struct TestFile(PathBuf);

    impl TestFile {
        fn new() -> Self {
            static NEXT_ID: AtomicU64 = AtomicU64::new(0);
            Self(std::env::temp_dir().join(format!(
                "neovide-image-preview-{}-{}",
                std::process::id(),
                NEXT_ID.fetch_add(1, Ordering::Relaxed)
            )))
        }

        fn path(&self) -> &str {
            self.0.to_str().unwrap()
        }
    }

    impl Drop for TestFile {
        fn drop(&mut self) {
            let _ = fs::remove_file(&self.0);
        }
    }

    fn viewport() -> Value {
        Value::Map(
            [("row", 2), ("col", 3), ("width", 80), ("height", 24)]
                .into_iter()
                .map(|(key, value)| (Value::from(key), Value::from(value)))
                .collect(),
        )
    }

    #[test]
    fn parses_viewport_with_defaults_and_rejects_invalid_values() {
        let view = ImageView::parse(&viewport()).unwrap();
        assert_eq!((view.zoom, view.pan_x, view.pan_y), (1.0, 0.0, 0.0));
        for (key, value) in [
            ("zoom", Value::from(0)),
            ("zoom", Value::from(33)),
            ("zoom", Value::from(0.01)),
            ("height", Value::from(-1)),
            ("width", Value::from(1_000_001)),
            ("col", Value::from(-1)),
            ("pan_x", Value::from(-1_000_001)),
            ("pan_x", Value::F64(f64::NAN)),
            ("pan_y", Value::F64(f64::MAX)),
            ("width", Value::from("wide")),
        ] {
            let mut input = viewport();
            let Value::Map(fields) = &mut input else { unreachable!() };
            fields.retain(|(name, _)| name.as_str() != Some(key));
            fields.push((Value::from(key), value));
            assert!(ImageView::parse(&input).is_err(), "accepted {key}");
        }
        assert!(ImageView::parse(&Value::Nil).is_err());
        assert!(ImageView::parse(&Value::Map(Vec::new())).is_err());
    }

    #[test]
    fn decodes_supported_raster_formats_without_relying_on_extension() {
        for format in [
            ImageFormat::Png,
            ImageFormat::Jpeg,
            ImageFormat::Gif,
            ImageFormat::WebP,
            ImageFormat::Bmp,
            ImageFormat::Tiff,
            ImageFormat::Ico,
        ] {
            let file = TestFile::new();
            let image = DynamicImage::ImageRgb8(image::RgbImage::from_pixel(
                2,
                1,
                image::Rgb([30, 100, 210]),
            ));
            // ICO's embedded PNG representation requires RGBA pixels.
            if format == ImageFormat::Ico {
                image.into_rgba8().save_with_format(&file.0, format).unwrap();
            } else {
                image.save_with_format(&file.0, format).unwrap();
            }
            let result =
                decode_image(file.path()).unwrap_or_else(|error| panic!("{format:?}: {error}"));
            assert_eq!((result.width, result.height), (2, 1));
            assert_eq!(result.pixels.len(), 8);
            assert_eq!(result.pixels[3], 255);
        }
    }

    #[test]
    fn preserves_alpha_and_decodes_only_the_first_gif_frame() {
        let mut png = Cursor::new(Vec::new());
        DynamicImage::ImageRgba8(RgbaImage::from_pixel(1, 1, Rgba([20, 40, 60, 80])))
            .write_to(&mut png, ImageFormat::Png)
            .unwrap();
        assert_eq!(decode_bytes(png.into_inner()).unwrap().pixels, [20, 40, 60, 80]);

        let mut gif = Vec::new();
        {
            let mut encoder = GifEncoder::new(&mut gif);
            for color in [[255, 0, 0, 255], [0, 255, 0, 255]] {
                encoder.encode_frame(Frame::new(RgbaImage::from_pixel(1, 1, Rgba(color)))).unwrap();
            }
        }
        assert_eq!(decode_bytes(gif).unwrap().pixels, [255, 0, 0, 255]);
    }

    #[test]
    fn returns_actionable_errors_for_missing_damaged_and_unsupported_files() {
        let file = TestFile::new();
        assert!(decode_image(file.path()).unwrap_err().contains("Cannot open"));
        fs::write(&file.0, b"\x89PNG\r\n\x1a\ntruncated").unwrap();
        assert!(decode_image(file.path()).unwrap_err().contains("header"));
        fs::write(&file.0, b"<svg xmlns='http://www.w3.org/2000/svg'/>").unwrap();
        assert!(decode_image(file.path()).unwrap_err().contains("Unsupported"));
        assert!(decode_image(std::env::temp_dir().to_str().unwrap()).is_err());
    }

    #[test]
    fn rejects_oversized_input_without_reading_the_file() {
        let file = TestFile::new();
        File::create(&file.0).unwrap().set_len(MAX_INPUT_BYTES + 1).unwrap();
        assert!(decode_image(file.path()).unwrap_err().contains("64 MiB"));
    }

    #[test]
    fn rejects_oversized_dimensions_before_decoding_pixels() {
        // A valid uncompressed BMP header declaring 10000 x 10000 pixels, with
        // no pixel payload. The preview limit must fail before a pixel read.
        let mut bmp = vec![0u8; 54];
        bmp[..2].copy_from_slice(b"BM");
        bmp[10..14].copy_from_slice(&54u32.to_le_bytes());
        bmp[14..18].copy_from_slice(&40u32.to_le_bytes());
        bmp[18..22].copy_from_slice(&10000i32.to_le_bytes());
        bmp[22..26].copy_from_slice(&10000i32.to_le_bytes());
        bmp[26..28].copy_from_slice(&1u16.to_le_bytes());
        bmp[28..30].copy_from_slice(&24u16.to_le_bytes());
        assert!(decode_bytes(bmp).unwrap_err().contains("128 MiB"));
    }
}
