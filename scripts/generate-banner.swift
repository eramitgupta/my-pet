#!/usr/bin/env swift
// Renders the README banner from the bundled pet sprites.
//   swift scripts/generate-banner.swift            → docs/banner.png (2560×960, shown at 1280×480)

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    .appendingPathComponent("..").standardizedFileURL
let pets = root.appendingPathComponent("macos/mypet/Assets/Pets")
let out = root.appendingPathComponent("docs/banner.png")

let scale: CGFloat = 2
let W: CGFloat = 1280, H: CGFloat = 480

func load(_ url: URL) -> CGImage {
    let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: a)
}

/// One 32×32 frame of a pet's strip, tinted the way the app tints it (multiply through the mask).
func pet(_ id: String, _ anim: String, frame: Int, tint: CGColor) -> CGImage {
    let sheet = load(pets.appendingPathComponent("\(id)/\(anim).png"))
    let mask = load(pets.appendingPathComponent("\(id)/\(anim)_mask.png"))
    let r = CGRect(x: frame * 32, y: 0, width: 32, height: 32)
    let f = sheet.cropping(to: r)!, m = mask.cropping(to: r)!
    let ctx = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let full = CGRect(x: 0, y: 0, width: 32, height: 32)
    ctx.draw(f, in: full)
    ctx.saveGState(); ctx.clip(to: full, mask: m); ctx.setBlendMode(.multiply)
    ctx.setFillColor(tint); ctx.fill(full); ctx.restoreGState()
    ctx.setBlendMode(.destinationIn); ctx.draw(f, in: full)
    return ctx.makeImage()!
}

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
}

func text(_ s: String, _ font: NSFont, _ c: CGColor, at p: CGPoint, kern: CGFloat = 0) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(cgColor: c)!, .kern: kern]
    NSAttributedString(string: s, attributes: attrs).draw(at: p)
}

let ctx = CGContext(data: nil, width: Int(W * scale), height: Int(H * scale), bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: scale, y: scale)
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

// Night-sky background with a soft glow behind the title.
let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                    colors: [color(0x1D2640), color(0x0E1220)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                      colors: [color(0x5B7CFF, 0.22), color(0x5B7CFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 330, y: 300), startRadius: 0,
                       endCenter: CGPoint(x: 330, y: 300), endRadius: 420, options: [])

// Pixel stars.
var seed: UInt32 = 7
for _ in 0..<70 {
    seed = seed &* 1_664_525 &+ 1_013_904_223
    let x = CGFloat(seed % 1280); seed = seed &* 1_664_525 &+ 1_013_904_223
    let y = 150 + CGFloat(seed % 330); seed = seed &* 1_664_525 &+ 1_013_904_223
    let a = 0.15 + CGFloat(seed % 50) / 100
    // Keep stars out of the menu-bar mock-up, the text block and the pets.
    let keepOut = [CGRect(x: 740, y: 380, width: 500, height: 70), CGRect(x: 60, y: 130, width: 760, height: 260),
                   CGRect(x: 600, y: 60, width: 680, height: 150)]
    if keepOut.contains(where: { $0.contains(CGPoint(x: x, y: y)) }) { continue }
    ctx.setFillColor(color(0xFFFFFF, a))
    ctx.fill(CGRect(x: x.rounded(), y: y.rounded(), width: seed % 5 == 0 ? 3 : 2, height: seed % 5 == 0 ? 3 : 2))
}

// Title block.
text("MyPet", roundedFont(112, .heavy), color(0xFFFFFF), at: CGPoint(x: 72, y: 255), kern: -2)
text("Your Mac’s Little Companion.", roundedFont(34, .semibold), color(0xC9D3FF), at: CGPoint(x: 78, y: 210))
text("A pixel-art pet in your menu bar. It changes colour with memory", roundedFont(20, .regular),
     color(0x9AA6CC), at: CGPoint(x: 80, y: 168))
text("and runs faster when your CPU is busy.", roundedFont(20, .regular), color(0x9AA6CC), at: CGPoint(x: 80, y: 142))

// A tiny menu bar mock-up (top right) with the pet in it.
let bar = CGRect(x: 760, y: 392, width: 460, height: 44)
ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 12, cornerHeight: 12, transform: nil))
ctx.setFillColor(color(0xFFFFFF, 0.10)); ctx.fillPath()
ctx.addPath(CGPath(roundedRect: bar.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 12, cornerHeight: 12, transform: nil))
ctx.setStrokeColor(color(0xFFFFFF, 0.18)); ctx.setLineWidth(1); ctx.strokePath()
ctx.interpolationQuality = .none
ctx.draw(pet("cat", "run", frame: 2, tint: color(0x34C759)), in: CGRect(x: bar.minX + 14, y: bar.minY + 4, width: 36, height: 36))
text("CPU 23%  ·  Memory 41%", roundedFont(17, .medium), color(0xE6EBFF), at: CGPoint(x: bar.minX + 62, y: bar.minY + 12))
text("Wed 11:11", roundedFont(17, .medium), color(0xE6EBFF, 0.75), at: CGPoint(x: bar.maxX - 98, y: bar.minY + 12))

// Memory gradient "ground" with the six pets running along it, coloured from calm to busy.
let ground = CGRect(x: 0, y: 0, width: W, height: 64)
let ramp = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                      colors: [color(0x34C759), color(0xFFD60A), color(0xFF9F0A), color(0xFF453A)] as CFArray,
                      locations: [0, 0.4, 0.7, 1])!
ctx.saveGState(); ctx.clip(to: ground)
ctx.drawLinearGradient(ramp, start: CGPoint(x: 0, y: 0), end: CGPoint(x: W, y: 0), options: [])
ctx.restoreGState()
ctx.setFillColor(color(0x000000, 0.18)); ctx.fill(CGRect(x: 0, y: 60, width: W, height: 4))

let lineup: [(String, String, Int, UInt32)] = [
    ("panda", "idle", 1, 0x34C759), ("rabbit", "run", 2, 0x7DD35A), ("cat", "run", 4, 0xC9D43A),
    ("fox", "run", 1, 0xFFD60A), ("dog", "run", 3, 0xFF9F0A), ("dinosaur", "run", 2, 0xFF453A),
]
for (i, (id, anim, frame, tint)) in lineup.enumerated() {
    let size: CGFloat = 112
    let x = 572 + CGFloat(i) * 114
    ctx.draw(pet(id, anim, frame: frame, tint: color(tint)), in: CGRect(x: x, y: 62 - size * 0.06, width: size, height: size))
}

// Ground labels.
text("calm", roundedFont(15, .bold), color(0x0E1220, 0.65), at: CGPoint(x: 24, y: 22))
text("busy", roundedFont(15, .bold), color(0x0E1220, 0.65), at: CGPoint(x: W - 62, y: 22))

let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
precondition(CGImageDestinationFinalize(dest))
print("✓ \(out.path)")
