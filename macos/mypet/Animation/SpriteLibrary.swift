import CoreGraphics
import Foundation
import ImageIO
import os

private let log = Logger(subsystem: "com.erag.mypet", category: "sprites")

/// One pet's decoded frames. Sheets are decoded once at load; frames are crops that share
/// the decoded pixels, so nothing is decoded again while animating.
final class PetSprites {
    let manifest: PetManifest
    let frames: [PetAnimation: [CGImage]]
    let masks: [PetAnimation: [CGImage]]
    /// Union of opaque pixels across an animation's frames (top-left origin, pixels).
    let contentBounds: [PetAnimation: CGRect]
    let baseColor: RGB

    var id: String { manifest.id }
    var name: String { manifest.displayName }

    init(manifest: PetManifest, frames: [PetAnimation: [CGImage]], masks: [PetAnimation: [CGImage]],
         contentBounds: [PetAnimation: CGRect]) {
        self.manifest = manifest
        self.frames = frames
        self.masks = masks
        self.contentBounds = contentBounds
        baseColor = manifest.baseColor.flatMap(RGB.init(hex:)) ?? RGB(0.85, 0.85, 0.85)
    }

    func frame(_ a: PetAnimation, _ index: Int) -> CGImage {
        let list = frames[a]!
        return list[min(max(index, 0), list.count - 1)]
    }

    func mask(_ a: PetAnimation, _ index: Int) -> CGImage? {
        guard let list = masks[a], !list.isEmpty else { return nil }
        return list[min(max(index, 0), list.count - 1)]
    }
}

@MainActor
final class SpriteLibrary {
    static let shared = SpriteLibrary()

    private(set) var pets: [PetSprites] = []
    private var byID: [String: PetSprites] = [:]

    /// Display order for bundled pets; user pets follow alphabetically.
    private static let preferredOrder = ["cat", "dog", "fox", "rabbit", "dinosaur", "panda"]

    /// Bundled pets plus `~/Library/Application Support/mypet/Pets`, where developers can
    /// drop new pet folders without rebuilding. A user folder with a bundled id overrides it.
    static func searchDirectories() -> [URL] {
        var dirs: [URL] = []
        if let env = ProcessInfo.processInfo.environment["MYPET_PETS_DIR"] {
            dirs.append(URL(fileURLWithPath: env))
        }
        if let res = Bundle.main.resourceURL?.appendingPathComponent("Pets"),
           FileManager.default.fileExists(atPath: res.path) {
            dirs.append(res)
        } else {
            // `swift run` during development: use the source tree's assets.
            let source = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Assets/Pets")
            dirs.append(source)
        }
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            dirs.append(support.appendingPathComponent("MyPet/Pets"))
        }
        return dirs
    }

    func loadAll() {
        var found: [String: PetSprites] = [:]
        for dir in Self.searchDirectories() {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            else { continue }
            for folder in entries where (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                do {
                    let pet = try Self.load(folder: folder)
                    found[pet.id] = pet
                } catch {
                    log.error("Skipping pet at \(folder.path, privacy: .public): \(String(describing: error), privacy: .public)")
                }
            }
        }
        pets = found.values.sorted { a, b in
            let ia = Self.preferredOrder.firstIndex(of: a.id) ?? Int.max
            let ib = Self.preferredOrder.firstIndex(of: b.id) ?? Int.max
            return ia != ib ? ia < ib : a.name < b.name
        }
        byID = found
        log.info("Loaded \(self.pets.count) pets")
    }

    func pet(_ id: String) -> PetSprites? { byID[id] ?? pets.first }

    // MARK: Loading

    enum LoadError: Error, CustomStringConvertible {
        case noManifest, unreadableImage(String), wrongSheetSize(String)
        var description: String {
            switch self {
            case .noManifest: return "manifest.json missing or invalid"
            case .unreadableImage(let f): return "cannot read \(f)"
            case .wrongSheetSize(let f): return "\(f) is not frames × frameSize"
            }
        }
    }

    static func load(folder: URL) throws -> PetSprites {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(PetManifest.self, from: data)
        else { throw LoadError.noManifest }
        try manifest.validate()

        var frames: [PetAnimation: [CGImage]] = [:]
        var masks: [PetAnimation: [CGImage]] = [:]
        var bounds: [PetAnimation: CGRect] = [:]
        let fw = manifest.frameWidth, fh = manifest.frameHeight
        for a in PetAnimation.allCases {
            let count = manifest.animations[a.rawValue]!.frames
            let file = "\(a.rawValue).png"
            guard let sheet = decode(folder.appendingPathComponent(file)) else { throw LoadError.unreadableImage(file) }
            guard sheet.width >= fw * count, sheet.height >= fh else { throw LoadError.wrongSheetSize(file) }
            frames[a] = slice(sheet, count: count, width: fw, height: fh)
            bounds[a] = opaqueBounds(sheet, count: count, width: fw, height: fh)
            // Masks are optional: without one the whole sprite is tinted.
            if let m = decode(folder.appendingPathComponent("\(a.rawValue)_mask.png")),
               m.width >= fw * count, m.height >= fh {
                masks[a] = slice(m, count: count, width: fw, height: fh)
            }
        }
        return PetSprites(manifest: manifest, frames: frames, masks: masks, contentBounds: bounds)
    }

    /// Decodes a PNG into an in-memory bitmap. Crops of a bitmap-backed image share its
    /// pixels; crops of a file-backed image would re-run the PNG decoder when drawn.
    private static func decode(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let gray = image.colorSpace?.model == .monochrome && image.alphaInfo == .none
        let space = gray ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB)!
        let info = gray ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: info) else { return image }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage() ?? image
    }

    private static func slice(_ sheet: CGImage, count: Int, width: Int, height: Int) -> [CGImage] {
        (0..<count).compactMap { sheet.cropping(to: CGRect(x: $0 * width, y: 0, width: width, height: height)) }
    }

    /// Bounding box of non-transparent pixels over all frames, in frame coordinates.
    private static func opaqueBounds(_ sheet: CGImage, count: Int, width: Int, height: Int) -> CGRect {
        let w = width * count
        var pixels = [UInt8](repeating: 0, count: w * height * 4)
        let drew: Bool = pixels.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: height, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            // Draw the top `height` rows; CG's origin is bottom-left, so offset accordingly.
            ctx.draw(sheet, in: CGRect(x: 0, y: height - sheet.height, width: sheet.width, height: sheet.height))
            return true
        }
        guard drew else { return CGRect(x: 0, y: 0, width: width, height: height) }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 0 {
                let fx = x % width
                minX = min(minX, fx); maxX = max(maxX, fx)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX else { return CGRect(x: 0, y: 0, width: width, height: height) }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
