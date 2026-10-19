// Render the same Assets.car-backed icon shown by Finder and the running app.
// IconServices already supplies the final material, shape and system margins.
import AppKit
import ImageIO
import UniformTypeIdentifiers

struct Settings: Decodable {
    let version: Int
    let staticBrightnessGain: Double
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Native static icon: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 4 else {
    fail("Usage: swift export-static-icon.swift APP_BUNDLE OUTPUT.png COMPENSATION.json")
}
let bundleURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let settings: Settings
do {
    settings = try JSONDecoder().decode(Settings.self, from: Data(
        contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])
    ))
} catch { fail("Cannot read static brightness settings: \(error.localizedDescription)") }
guard settings.version == 1, settings.staticBrightnessGain.isFinite,
      (1...1.05).contains(settings.staticBrightnessGain) else {
    fail("Expected version 1 and a staticBrightnessGain between 1 and 1.05")
}
guard let bundle = Bundle(url: bundleURL),
      let name = bundle.object(forInfoDictionaryKey: "CFBundleIconName") as? String,
      !name.isEmpty,
      FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("Contents/Resources/Assets.car").path),
      let executable = bundle.executableURL,
      FileManager.default.isExecutableFile(atPath: executable.path) else {
    fail("Expected a complete temporary app with an executable and native Assets.car icon")
}

let size = 1024
func render(_ image: NSImage) -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fail("Cannot create the native icon bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    // Fix the ordinary appearance for reproducible installer/legacy artwork.
    NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
                   from: .zero, operation: .copy, fraction: 1)
    }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

let bitmap = render(NSWorkspace.shared.icon(forFile: bundleURL.path))
let generic = render(NSWorkspace.shared.icon(for: .applicationBundle))
guard let pixels = bitmap.bitmapData, let genericPixels = generic.bitmapData else {
    fail("Cannot inspect the rendered icon")
}
let byteCount = size * size * 4
guard memcmp(pixels, genericPixels, byteCount) != 0 else {
    fail("IconServices returned a generic application icon")
}
var left = size, top = size, right = -1, bottom = -1
var opaque = 0
for y in 0..<size {
    for x in 0..<size {
        let alpha = pixels[(y * size + x) * 4 + 3]
        if alpha > 0 {
            left = min(left, x); right = max(right, x)
            top = min(top, y); bottom = max(bottom, y)
        }
        if alpha >= 250 { opaque += 1 }
    }
}
// A native macOS plate must occupy most of the square, retain transparent
// margins on every side and contain an opaque center. Reject blank/partial
// results before replacing any active icon or installer image.
guard left > 0, top > 0, right < size - 1, bottom < size - 1,
      right - left >= 700, bottom - top >= 700,
      opaque > size * size / 2 else {
    fail("Unexpected native icon alpha bounds (\(left), \(top))–(\(right), \(bottom)), opaque pixels \(opaque)")
}
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fail("Cannot encode the native icon PNG")
}

func applyStaticBrightness(_ data: Data, gain: Double) -> Data {
    if gain == 1 { return data }
    // Normalize the native PNG to an explicit premultiplied sRGB buffer, the
    // same representation used for the approved static preview. The material
    // source and Assets.car never receive this white-background compensation.
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let context = CGContext(
              data: nil, width: size, height: size, bitsPerComponent: 8,
              bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
          ), let storage = context.data else {
        fail("Cannot prepare the static brightness buffer")
    }
    context.setBlendMode(.copy)
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    let rgba = storage.bindMemory(to: UInt8.self, capacity: byteCount)
    for offset in stride(from: 0, to: byteCount, by: 4) {
        let alpha = Double(rgba[offset + 3])
        for channel in 0..<3 {
            rgba[offset + channel] = UInt8(min(alpha, (Double(rgba[offset + channel]) * gain).rounded()))
        }
        // Alpha is unchanged, including antialiasing and the system shadow.
        // Premultiplied black shadow pixels remain black at any valid gain.
    }
    let output = NSMutableData()
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithData(
              output, UTType.png.identifier as CFString, 1, nil
          ) else { fail("Cannot encode the compensated static icon") }
    CGImageDestinationAddImage(destination, image, [
        kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGsRGBIntent: 0]
    ] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fail("Cannot finish the static PNG") }
    return output as Data
}
let staticPNG = applyStaticBrightness(png, gain: settings.staticBrightnessGain)
do {
    try staticPNG.write(to: outputURL, options: .atomic)
} catch { fail(error.localizedDescription) }
print("Native 1024 × 1024 icon: alpha bounds (\(left), \(top))–(\(right), \(bottom)); static brightness ×\(settings.staticBrightnessGain), no extra scale or shadow")
