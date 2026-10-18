// Native static fallback compositor. The shadow must use the same alpha shape
// as the Icon Composer export, never a mask or shadow from the old Sketch icon.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: swift export-static-icon.swift COMPOSER_EXPORT.png OUTPUT.png")
}
let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let icon = CGImageSourceCreateImageAtIndex(source, 0, nil),
      icon.width == 1024, icon.height == 1024 else {
    fatalError("Expected a 1024 × 1024 Icon Composer export")
}
guard let context = CGContext(
    data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("Cannot create native icon context") }

context.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))
context.interpolationQuality = .high
// Retain the existing macOS fallback's 832-point plate and 96-point margins.
// Core Graphics derives the soft outside shadow directly from this image's
// alpha. One draw produces both the plate and its matching shadow.
context.setShadow(offset: CGSize(width: 0, height: -8), blur: 32,
                  color: CGColor(gray: 0, alpha: 0.32941177))
context.draw(icon, in: CGRect(x: 96, y: 96, width: 832, height: 832))

guard let output = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          outputURL as CFURL, UTType.png.identifier as CFString, 1, nil
      ) else { fatalError("Cannot create static icon output") }
CGImageDestinationAddImage(destination, output, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write static icon") }
