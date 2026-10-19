// Generate the material before glass rendering, always from the untouched source.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct Settings: Decodable {
    let version: Int
    let saturationGain: Double
    let staticBrightnessGain: Double
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Icon color compensation: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard (2...3).contains(arguments.count), ["--check", "--prepare"].contains(arguments[1]) else {
    fail("Usage: swift compensate-icon.swift --check|--prepare [ASSETS_DIRECTORY]")
}
let assets = arguments.count == 3
    ? URL(fileURLWithPath: arguments[2], isDirectory: true)
    : URL(fileURLWithPath: arguments[0]).standardizedFileURL
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("assets")
let configURL = assets.appendingPathComponent("icon-color-compensation.json")
let iconURL = assets.appendingPathComponent("Neovide.icon")
let originalName = "original-material.png"
let generatedName = "original-material-compensated.png"
let inputURL = iconURL.appendingPathComponent("Assets/\(originalName)")
let outputURL = iconURL.appendingPathComponent("Assets/\(generatedName)")
let documentURL = iconURL.appendingPathComponent("icon.json")

do {
    let settings = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: configURL))
    guard settings.version == 1, settings.saturationGain.isFinite,
          (1...3).contains(settings.saturationGain) else {
        fail("Expected version 1 and a saturationGain between 1 and 3")
    }
    guard settings.staticBrightnessGain.isFinite,
          (1...1.05).contains(settings.staticBrightnessGain) else {
        fail("Expected a staticBrightnessGain between 1 and 1.05")
    }
    guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
          let original = CGImageSourceCreateImageAtIndex(source, 0, nil),
          original.width == 1024, original.height == 1024 else {
        fail("Expected the untouched 1024 × 1024 original-material.png")
    }
    let documentData = try Data(contentsOf: documentURL)
    guard let documentText = String(data: documentData, encoding: .utf8),
          let document = try JSONSerialization.jsonObject(with: documentData) as? [String: Any],
          let groups = document["groups"] as? [[String: Any]] else {
        fail("Cannot read Icon Composer layers")
    }
    let materialLayers = groups.flatMap { $0["layers"] as? [[String: Any]] ?? [] }
        .filter { [originalName, generatedName].contains($0["image-name"] as? String ?? "") }
    guard materialLayers.count == 1 else {
        fail("Expected exactly one original material layer; preserve its name and geometry")
    }
    if arguments[1] == "--check" {
        print("Original material, native saturation and static brightness settings are available.")
        exit(0)
    }

    let width = original.width, height = original.height
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: colorSpace, bitmapInfo: bitmapInfo),
          let storage = context.data else { fail("Cannot create sRGB material context") }
    context.setBlendMode(.copy)
    context.draw(original, in: CGRect(x: 0, y: 0, width: width, height: height))
    let pixels = storage.bindMemory(to: UInt8.self, capacity: width * height * 4)
    for offset in stride(from: 0, to: width * height * 4, by: 4) {
        let alpha = Double(pixels[offset + 3])
        if alpha == 0 { continue }
        let rgb = (0..<3).map { Double(pixels[offset + $0]) / alpha }
        let maximum = rgb.max()!, minimum = rgb.min()!
        let range = maximum - minimum
        // HSV saturation preserves hue and maximum brightness. Limit the gain
        // before a channel crosses zero instead of clipping individual channels.
        let gain = range > 0 ? min(settings.saturationGain, maximum / range) : 1
        for channel in 0..<3 {
            let value = maximum + gain * (rgb[channel] - maximum)
            pixels[offset + channel] = UInt8(max(0, min(alpha, (value * alpha).rounded())))
        }
        // Alpha is never changed: glass geometry, edge antialiasing and holes survive.
    }
    guard let generated = context.makeImage(),
          let data = CFDataCreateMutable(nil, 0),
          let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { fail("Cannot create compensated PNG") }
    CGImageDestinationAddImage(destination, generated, nil)
    guard CGImageDestinationFinalize(destination) else { fail("Cannot encode compensated PNG") }
    let result = data as Data
    if (try? Data(contentsOf: outputURL)) != result {
        try result.write(to: outputURL, options: .atomic)
    }
    // Change only the image name, preserving every user-edited glass property.
    let pattern = #"("image-name"\s*:\s*)"original-material\.png""#
    let expression = try NSRegularExpression(pattern: pattern)
    let range = NSRange(documentText.startIndex..., in: documentText)
    let updated = expression.stringByReplacingMatches(
        in: documentText, range: range,
        withTemplate: "$1\"\(generatedName)\""
    )
    if updated != documentText { try Data(updated.utf8).write(to: documentURL, options: .atomic) }
    print(String(format: "Generated glass material from the original with saturation ×%.3f.", settings.saturationGain))
} catch { fail(error.localizedDescription) }
