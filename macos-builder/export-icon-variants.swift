// Export the active icon family from the final, compensated native macOS icon.
// Usage: swift macos-builder/export-icon-variants.swift [ASSETS_DIR]
// ASSETS_DIR may also be set in the environment; by default use this repo's assets.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct ExportError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func pngData(from image: CGImage, size: Int) throws -> Data {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil, width: size, height: size, bitsPerComponent: 8,
              bytesPerRow: size * 4, space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else { throw ExportError("Cannot create the \(size)-pixel sRGB context") }
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let resized = context.makeImage() else {
        throw ExportError("Cannot resize the icon to \(size) pixels")
    }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil
    ) else { throw ExportError("Cannot create the \(size)-pixel PNG") }
    CGImageDestinationAddImage(destination, resized, [
        kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGsRGBIntent: 0]
    ] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw ExportError("Cannot encode the \(size)-pixel PNG")
    }
    return data as Data
}

func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
}

func icoData(sizes: [Int], pngs: [Int: Data]) throws -> Data {
    // Modern Windows icons support PNG-compressed entries, retaining exact alpha.
    var data = Data()
    appendLE(UInt16(0), to: &data)
    appendLE(UInt16(1), to: &data)
    appendLE(UInt16(sizes.count), to: &data)
    var offset = 6 + 16 * sizes.count
    for size in sizes {
        guard let png = pngs[size], png.count <= Int(UInt32.max),
              offset <= Int(UInt32.max) else {
            throw ExportError("Invalid ICO entry for \(size) pixels")
        }
        data.append(UInt8(size == 256 ? 0 : size))
        data.append(UInt8(size == 256 ? 0 : size))
        data.append(0) // Color count: true color.
        data.append(0) // Reserved.
        appendLE(UInt16(1), to: &data) // Color planes.
        appendLE(UInt16(32), to: &data)
        appendLE(UInt32(png.count), to: &data)
        appendLE(UInt32(offset), to: &data)
        offset += png.count
    }
    for size in sizes { data.append(pngs[size]!) }
    return data
}

func exportVariants() throws {
    guard CommandLine.arguments.count <= 2 else {
        throw ExportError("Usage: swift export-icon-variants.swift [ASSETS_DIR]")
    }
    let defaultDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("assets", isDirectory: true)
    let directory: URL
    if let path = CommandLine.arguments.dropFirst().first
        ?? ProcessInfo.processInfo.environment["ASSETS_DIR"] {
        directory = URL(fileURLWithPath: path, isDirectory: true)
    } else {
        directory = defaultDirectory
    }
    let inputURL = directory.appendingPathComponent("neovide-1024.png")
    let originalPNG = try Data(contentsOf: inputURL)
    guard let source = CGImageSourceCreateWithData(originalPNG as CFData, nil),
          let icon = CGImageSourceCreateImageAtIndex(source, 0, nil),
          icon.width == 1024, icon.height == 1024 else {
        throw ExportError("Expected a 1024 × 1024 icon at \(inputURL.path)")
    }

    let icoSizes = [16, 24, 32, 48, 64, 128, 256]
    var pngs = [Int: Data]()
    for size in icoSizes { pngs[size] = try pngData(from: icon, size: size) }
    var outputs = [String: Data]()
    for size in [16, 32, 48, 256] {
        outputs["neovide-\(size)x\(size).png"] = pngs[size]!
    }
    outputs["neovide.ico"] = try icoData(sizes: icoSizes, pngs: pngs)

    // This is an SVG-compatible image container, not editable vector artwork.
    // Embedding the complete native PNG preserves the glass material exactly.
    let svg = """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
      <title>Neovide Glow — Liquid Glass icon</title>
      <desc>Raster-backed SVG generated from neovide-1024.png. The embedded PNG preserves the native glass material and transparency; this file is not editable vector artwork.</desc>
      <image width="1024" height="1024" href="data:image/png;base64,\(originalPNG.base64EncodedString())"/>
    </svg>

    """
    outputs["neovide.svg"] = Data(svg.utf8)

    // Prepare every format before replacing any active output.
    for name in outputs.keys.sorted() {
        try outputs[name]!.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
    print("Exported PNG (16, 32, 48, 256), seven-size ICO and raster-backed SVG in \(directory.path)")
}

do {
    try exportVariants()
} catch {
    FileHandle.standardError.write(Data("Icon variant export failed: \(error)\n".utf8))
    exit(1)
}
