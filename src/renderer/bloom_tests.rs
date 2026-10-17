use skia_safe::{Canvas, Color, EncodedImageFormat, Paint, PathBuilder, Rect, Surface, surfaces};

use super::{RendererSettings, bloom::BloomRenderer};

const BACKGROUND: Color = Color::from_rgb(11, 14, 20);

fn fixture(canvas: &Canvas) {
    canvas.clear(BACKGROUND);
    let mut paint = Paint::default();
    paint.set_anti_alias(true);
    paint.set_style(skia_safe::paint::Style::Stroke).set_stroke_width(2.0);
    // Glyph-like strokes exercise antialiased edges without requiring system fonts.
    for (y, color) in [
        (46.0, Color::WHITE),
        (92.0, Color::from_rgb(0, 194, 245)),
        (138.0, Color::from_rgb(255, 190, 40)),
        (184.0, Color::from_rgb(170, 240, 60)),
    ] {
        paint.set_color(color);
        for column in 0..28 {
            let x = 24.25 + column as f32 * 21.0;
            let mut strokes = PathBuilder::new();
            strokes.move_to((x, y)).line_to((x, y - 24.0));
            strokes.line_to((x + 12.0, y - 24.0)).line_to((x + 12.0, y));
            if column % 2 == 0 {
                strokes.move_to((x, y - 12.0)).line_to((x + 12.0, y - 12.0));
            }
            if column % 3 == 0 {
                strokes.move_to((x, y)).line_to((x + 12.0, y - 24.0));
            }
            canvas.draw_path(&strokes.detach(), &paint);
        }
    }
    paint.set_style(skia_safe::paint::Style::Fill);
    paint.set_color(Color::from_rgb(21, 27, 36));
    canvas.draw_round_rect(Rect::from_xywh(30.0, 222.0, 180.0, 64.0), 28.0, 28.0, &paint);
    canvas.draw_round_rect(Rect::from_xywh(260.0, 222.0, 180.0, 64.0), 28.0, 28.0, &paint);
    paint.set_color(Color::from_rgb(150, 245, 60));
    paint.set_style(skia_safe::paint::Style::Stroke).set_stroke_width(5.0);
    let mut check = PathBuilder::new();
    check.move_to((320.0, 252.0)).line_to((332.0, 265.0)).line_to((357.0, 240.0));
    canvas.draw_path(&check.detach(), &paint);
}

fn pixels(surface: &mut Surface) -> Vec<u8> {
    surface.peek_pixels().unwrap().bytes().unwrap().to_vec()
}

#[test]
fn bloom_preserves_base_and_dark_fills() {
    let mut bloom = BloomRenderer::default();
    let mut settings = RendererSettings::default();
    assert!(bloom.filter_for(&settings, BACKGROUND).is_some(), "SkSL must compile");

    for background in [Color::TRANSPARENT, BACKGROUND, Color::from_rgb(21, 27, 36)] {
        let mut surface = surfaces::raster_n32_premul((240, 80)).unwrap();
        surface.canvas().clear(background);
        let original = pixels(&mut surface);
        bloom.draw(surface.canvas(), &settings, BACKGROUND);
        assert_eq!(pixels(&mut surface), original, "dark/empty pixels must not emit light");
    }

    let mut surface = surfaces::raster_n32_premul((800, 320)).unwrap();
    fixture(surface.canvas());
    let original = pixels(&mut surface);
    settings.bloom = false;
    bloom.draw(surface.canvas(), &settings, BACKGROUND);
    assert_eq!(pixels(&mut surface), original, "disabled bloom is an exact bypass");
    settings.bloom = true;
    settings.bloom_strength = 0.0;
    bloom.draw(surface.canvas(), &settings, BACKGROUND);
    assert_eq!(pixels(&mut surface), original, "zero strength is an exact bypass");
    settings.bloom_strength = 0.2;
    bloom.draw(surface.canvas(), &settings, BACKGROUND);
    let glowing = pixels(&mut surface);
    let mut changed = 0;
    for (base, output) in original.chunks_exact(4).zip(glowing.chunks_exact(4)) {
        for channel in 0..3 {
            assert!(output[channel] >= base[channel], "screen blend must not erode native edges");
            assert!(output[channel] <= output[3], "output must stay premultiplied");
        }
        changed += usize::from(base != output);
    }
    assert!(changed > 1500, "the halo must be present, not silently bypassed");
    let dark_badge_center = (250 * 800 + 120) * 4;
    assert_eq!(
        &glowing[dark_badge_center..dark_badge_center + 4],
        &original[dark_badge_center..dark_badge_center + 4],
        "isolated dark badge must not gain an outline or light"
    );

    if let Some(directory) = std::env::var_os("NEOVIDE_BLOOM_TEST_OUTPUT") {
        let directory = std::path::PathBuf::from(directory);
        std::fs::create_dir_all(&directory).unwrap();
        let png = surface.image_snapshot().encode(None, EncodedImageFormat::PNG, None).unwrap();
        std::fs::write(directory.join("bloom-on.png"), png.as_bytes()).unwrap();
        let mut baseline = surfaces::raster_n32_premul((800, 320)).unwrap();
        fixture(baseline.canvas());
        let png = baseline.image_snapshot().encode(None, EncodedImageFormat::PNG, None).unwrap();
        std::fs::write(directory.join("bloom-off.png"), png.as_bytes()).unwrap();
    }

    for value in [f32::NAN, f32::INFINITY, -1.0] {
        settings.bloom_radius = value;
        assert!(bloom.filter_for(&settings, BACKGROUND).is_none());
    }
}

#[cfg(target_os = "macos")]
#[test]
#[ignore = "requires an available Metal GPU; run explicitly with --ignored"]
fn metal_bloom_renders() {
    use objc2::{rc::Retained, runtime::ProtocolObject};
    use objc2_metal::{MTLCreateSystemDefaultDevice, MTLDevice};
    use skia_safe::{AlphaType, ColorSpace, ColorType, ImageInfo, gpu};

    let device = MTLCreateSystemDefaultDevice().expect("Metal device");
    let queue = device.newCommandQueue().expect("Metal queue");
    let backend = unsafe {
        gpu::mtl::BackendContext::new(
            Retained::as_ptr(&device).cast(),
            Retained::<ProtocolObject<dyn objc2_metal::MTLCommandQueue>>::as_ptr(&queue).cast(),
        )
    };
    let mut context = gpu::direct_contexts::make_metal(&backend, None).expect("Skia Metal context");
    let info = ImageInfo::new(
        (1920, 1080),
        ColorType::BGRA8888,
        AlphaType::Premul,
        ColorSpace::new_srgb(),
    );
    let mut surface = gpu::surfaces::render_target(
        &mut context,
        gpu::Budgeted::Yes,
        &info,
        None,
        Some(gpu::SurfaceOrigin::TopLeft),
        None,
        None,
        None,
    )
    .expect("Metal surface");
    let mut bloom = BloomRenderer::default();
    let settings = RendererSettings::default();
    for row in 0..3 {
        surface.canvas().save();
        surface.canvas().translate((0.0, row as f32 * 340.0));
        surface.canvas().clip_rect(Rect::from_xywh(0.0, 0.0, 1920.0, 340.0), None, false);
        fixture(surface.canvas());
        surface.canvas().restore();
    }
    let mut cursor = Paint::default();
    cursor.set_color(Color::from_rgb(255, 170, 51));
    surface.canvas().draw_rect(Rect::from_xywh(820.0, 96.0, 12.0, 28.0), &cursor);
    context.flush_submit_and_sync_cpu();

    // GPU readbacks are used only by this test, never by the rendering path.
    let mut original = vec![0u8; 1920 * 1080 * 4];
    assert!(surface.read_pixels(&info, &mut original, 1920 * 4, (0, 0)));
    bloom.draw(surface.canvas(), &settings, BACKGROUND);
    context.flush_submit_and_sync_cpu();
    let mut bytes = vec![0u8; 1920 * 1080 * 4];
    assert!(surface.read_pixels(&info, &mut bytes, 1920 * 4, (0, 0)));
    let mut changed = 0;
    for (base, output) in original.chunks_exact(4).zip(bytes.chunks_exact(4)) {
        for channel in 0..3 {
            assert!(output[channel] >= base[channel], "GPU bloom must not erode native edges");
            assert!(output[channel] <= output[3], "GPU output must stay premultiplied");
        }
        changed += usize::from(base != output);
    }
    assert!(changed > 1500, "the GPU halo must not silently bypass rendering");
}
