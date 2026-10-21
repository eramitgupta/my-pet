import CoreGraphics
import CPetCore
import Foundation

/// Recolours sprite frames with the gradient colour while keeping outlines, eyes and
/// shading intact: the tint is multiplied only into the mask's pixels, and the original
/// alpha is restored afterwards so transparency is untouched.
///
/// Results are cached by (pet, animation, frame, colour quantised to 7 bits per channel).
/// During a colour transition only the frames actually shown get rendered.
@MainActor
final class TintRenderer {
    static let shared = TintRenderer()

    private struct Key: Hashable {
        let pet: String
        let animation: PetAnimation
        let frame: Int
        let color: UInt32
    }

    private var cache: [Key: CGImage] = [:]
    private let capacity = 512

    static func quantize(_ c: PetColor) -> UInt32 {
        func q(_ v: Float) -> UInt32 { UInt32((min(max(v, 0), 1) * 127).rounded()) }
        return q(c.r) << 14 | q(c.g) << 7 | q(c.b)
    }

    static func dequantize(_ k: UInt32) -> PetColor {
        PetColor(r: Float((k >> 14) & 127) / 127, g: Float((k >> 7) & 127) / 127, b: Float(k & 127) / 127)
    }

    /// Returns the tinted frame (or the untouched frame when `tint` is nil).
    func image(_ pet: PetSprites, _ animation: PetAnimation, _ frame: Int, tint: PetColor?) -> CGImage {
        let original = pet.frame(animation, frame)
        guard let tint else { return original }
        let key = Key(pet: pet.id, animation: animation, frame: frame, color: Self.quantize(tint))
        if let hit = cache[key] { return hit }
        let color = Self.dequantize(key.color).cgColor
        let rendered = Self.render(original, mask: pet.mask(animation, frame), color: color) ?? original
        if cache.count >= capacity { cache.removeAll(keepingCapacity: true) }
        cache[key] = rendered
        return rendered
    }

    func purge() { cache.removeAll() }

    static func render(_ image: CGImage, mask: CGImage?, color: CGColor) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.interpolationQuality = .none
        ctx.draw(image, in: rect)
        ctx.saveGState()
        if let mask { ctx.clip(to: rect, mask: mask) }
        ctx.setBlendMode(.multiply)
        ctx.setFillColor(color)
        ctx.fill(rect)
        ctx.restoreGState()
        // Restore the sprite's own alpha (the fill painted transparent pixels too when unmasked).
        ctx.setBlendMode(.destinationIn)
        ctx.draw(image, in: rect)
        return ctx.makeImage()
    }
}
