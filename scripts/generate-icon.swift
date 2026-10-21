#!/usr/bin/env swift
// Renders the app icon from the bundled cat sprite.
//   swift scripts/generate-icon.swift
// Writes macos/mypet/Assets/AppIcon.icns and the Xcode asset catalog icon set.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    .appendingPathComponent("..").standardizedFileURL
let assets = root.appendingPathComponent("macos/mypet/Assets")
let pets = assets.appendingPathComponent("Pets")

func load(_ url: URL) -> CGImage {
    let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}

func writePNG(_ image: CGImage, _ url: URL) {
    let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, image, nil)
    precondition(CGImageDestinationFinalize(d))
}

let sheet = load(pets.appendingPathComponent("cat/run.png"))
let maskSheet = load(pets.appendingPathComponent("cat/run_mask.png"))
let frame = sheet.cropping(to: CGRect(x: 64, y: 0, width: 32, height: 32))!
let mask = maskSheet.cropping(to: CGRect(x: 64, y: 0, width: 32, height: 32))!

func render(size: Int) -> CGImage {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // macOS icon grid: 824/1024 body with ~22% corner radius.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = CGPath(roundedRect: body, cornerWidth: body.width * 0.225, cornerHeight: body.width * 0.225, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.02,
                  color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(path)
    ctx.setFillColor(CGColor(srgbRed: 0.12, green: 0.15, blue: 0.22, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                        colors: [CGColor(srgbRed: 0.17, green: 0.22, blue: 0.33, alpha: 1),
                                 CGColor(srgbRed: 0.08, green: 0.10, blue: 0.16, alpha: 1)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])

    // Memory gradient strip as the "floor".
    let strip = CGRect(x: body.minX, y: body.minY, width: body.width, height: body.height * 0.2)
    let ramp = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [CGColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1),
                                   CGColor(srgbRed: 1.0, green: 0.84, blue: 0.04, alpha: 1),
                                   CGColor(srgbRed: 1.0, green: 0.62, blue: 0.04, alpha: 1),
                                   CGColor(srgbRed: 1.0, green: 0.27, blue: 0.23, alpha: 1)] as CFArray,
                          locations: [0, 0.4, 0.7, 1])!
    ctx.saveGState()
    ctx.clip(to: strip)
    ctx.drawLinearGradient(ramp, start: CGPoint(x: strip.minX, y: 0), end: CGPoint(x: strip.maxX, y: 0), options: [])
    ctx.restoreGState()

    // The pet, tinted green, pixel-perfect.
    let petSize = body.width * 0.78
    let petRect = CGRect(x: body.midX - petSize / 2, y: strip.maxY - petSize * 0.1, width: petSize, height: petSize)
    let tinted = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let r32 = CGRect(x: 0, y: 0, width: 32, height: 32)
    tinted.draw(frame, in: r32)
    tinted.saveGState()
    tinted.clip(to: r32, mask: mask)
    tinted.setBlendMode(.multiply)
    tinted.setFillColor(CGColor(srgbRed: 0.45, green: 0.86, blue: 0.5, alpha: 1))
    tinted.fill(r32)
    tinted.restoreGState()
    tinted.setBlendMode(.destinationIn)
    tinted.draw(frame, in: r32)
    ctx.interpolationQuality = .none
    ctx.draw(tinted.makeImage()!, in: petRect)
    ctx.restoreGState()
    return ctx.makeImage()!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID()).iconset")
let catalog = assets.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)

var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let img = render(size: px)
        writePNG(img, iconset.appendingPathComponent(name))
        writePNG(img, catalog.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(base)x\(base)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: catalog.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": ["version": 1, "author": "xcode"]], options: .prettyPrinted)
    .write(to: assets.appendingPathComponent("Assets.xcassets/Contents.json"))

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", assets.appendingPathComponent("AppIcon.icns").path]
try p.run()
p.waitUntilExit()
precondition(p.terminationStatus == 0, "iconutil failed")
try? FileManager.default.removeItem(at: iconset)
print("✓ AppIcon.icns and asset catalog written")
