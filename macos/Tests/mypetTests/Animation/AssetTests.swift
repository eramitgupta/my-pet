import CPetCore
import XCTest
@testable import mypet

@MainActor
final class AssetTests: XCTestCase {
    func testAllBundledPetsLoad() {
        let library = SpriteLibrary.shared
        library.loadAll()
        let ids = Set(library.pets.map(\.id))
        for id in ["cat", "dog", "fox", "rabbit", "dinosaur", "panda"] {
            XCTAssertTrue(ids.contains(id), "missing \(id)")
        }
        for pet in library.pets {
            for a in PetAnimation.allCases {
                XCTAssertEqual(pet.frames[a]?.count, pet.manifest.animations[a.rawValue]?.frames, "\(pet.id) \(a)")
                XCTAssertEqual(pet.masks[a]?.count, pet.frames[a]?.count, "\(pet.id) \(a) mask")
            }
        }
    }

    func testTintPreservesTransparencyAndOutline() throws {
        let library = SpriteLibrary.shared
        library.loadAll()
        let pet = try XCTUnwrap(library.pet("cat"))
        let original = pet.frame(.idle, 0)
        let tinted = try XCTUnwrap(TintRenderer.render(original, mask: pet.mask(.idle, 0),
                                                       color: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)))
        let a = rgba(original), b = rgba(tinted)
        var tintedPixels = 0
        for i in stride(from: 0, to: a.count, by: 4) {
            XCTAssertEqual(a[i + 3], b[i + 3], "alpha changed at \(i / 4)")
            if a[i + 3] > 0, a[i] == a[i + 1], a[i + 1] == a[i + 2], a[i] > 0x90, b[i + 1] < 0x20 { tintedPixels += 1 }
            if a[i] == 0x2A, a[i + 1] == 0x22 { XCTAssertEqual(b[i], 0x2A, "outline recoloured") }
        }
        XCTAssertGreaterThan(tintedPixels, 20)
    }

    private func rgba(_ img: CGImage) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: img.width * img.height * 4)
        px.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: img.width, height: img.height, bitsPerComponent: 8,
                                bytesPerRow: img.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        }
        return px
    }
}
