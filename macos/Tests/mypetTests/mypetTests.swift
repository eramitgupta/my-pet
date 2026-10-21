import CPetCore
import XCTest
@testable import mypet

// Swift-side tests. Core logic (gradient, thresholds, memory scoring, movement bounds) is
// tested in Rust; these cover the Swift layer: persistence, manifests, assets, tinting and
// the FFI wrappers. Run with Xcode (⌘U) or `swift test` on a machine with full Xcode.

final class SettingsTests: XCTestCase {
    func testRoundTripThroughUserDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "mypet.tests.\(UUID())"))
        var s = PetSettings()
        s.menuBar.petID = "fox"
        s.menuBar.cpuDrivenSpeed = false
        s.menuBar.manualSpeed = 2
        s.gradientColors[2] = RGB(0.1, 0.2, 0.3)
        s.memoryMode = .pressure
        s.lowCPUMenuBar = false
        s.facing = .turnAround
        let data = try JSONEncoder().encode(s)
        defaults.set(data, forKey: SettingsStore.storageKey)
        XCTAssertEqual(SettingsStore.load(from: defaults), s)
    }

    func testMissingKeysFallBackToDefaults() throws {
        // Includes keys from older versions (desktop pet) that must simply be ignored.
        let partial = #"{"memoryMode":"pressure","displayMode":"desktop","desktopSize":80}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(PetSettings.self, from: partial)
        XCTAssertEqual(s.memoryMode, .pressure)
        XCTAssertEqual(s.menuBar.petID, PetSettings().menuBar.petID)
        XCTAssertEqual(s.thresholds, PetSettings.defaultThresholds)
    }

    func testUnknownEnumValueFallsBack() throws {
        let json = #"{"memoryMode":"hologram"}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(PetSettings.self, from: json).memoryMode, .usage)
    }

    func testSanitizeClampsValues() {
        var s = PetSettings()
        s.menuBar.manualSpeed = 99
        s.samplingInterval = 0
        s.gradientColors = [.red]
        let clean = s.sanitized
        XCTAssertEqual(clean.menuBar.manualSpeed, PetSettings.speedRange.upperBound)
        XCTAssertEqual(clean.samplingInterval, PetSettings.intervalRange.lowerBound)
        XCTAssertEqual(clean.gradientColors.count, 4)
    }

    func testThresholdsStayOrdered() {
        XCTAssertEqual(PetSettings.sanitizeThresholds([70, 20, 10]), [70, 75, 80])
        let t = PetSettings.sanitizeThresholds([99, 99, 99])
        XCTAssertTrue(t[0] < t[1] && t[1] < t[2] && t[2] < 100)
        XCTAssertEqual(PetSettings.sanitizeThresholds([1, 2]), PetSettings.defaultThresholds)
    }

    func testLegacySettingsMigrateOnce() throws {
        let fresh = try XCTUnwrap(UserDefaults(suiteName: "mypet.tests.\(UUID())"))
        let legacy = try XCTUnwrap(UserDefaults(suiteName: "mypet.tests.legacy.\(UUID())"))
        var old = PetSettings()
        old.menuBar.petID = "panda"
        legacy.set(try JSONEncoder().encode(old), forKey: SettingsStore.storageKey)
        SettingsStore.migrateLegacySettings(into: fresh, legacy: legacy)
        XCTAssertEqual(SettingsStore.load(from: fresh).menuBar.petID, "panda")
        // Existing settings are never overwritten.
        old.menuBar.petID = "fox"
        legacy.set(try JSONEncoder().encode(old), forKey: SettingsStore.storageKey)
        SettingsStore.migrateLegacySettings(into: fresh, legacy: legacy)
        XCTAssertEqual(SettingsStore.load(from: fresh).menuBar.petID, "panda")
    }

    @MainActor
    func testStoreDebouncesAndFlushes() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "mypet.tests.\(UUID())"))
        let store = SettingsStore(defaults: defaults)
        store.update { $0.paused = true }
        XCTAssertNil(defaults.data(forKey: SettingsStore.storageKey))
        store.flush()
        XCTAssertEqual(SettingsStore.load(from: defaults).paused, true)
    }
}

final class FacingTests: XCTestCase {
    func testFixedDirections() {
        var f = FacingController(mode: .left)
        XCTAssertTrue(f.facingLeft)
        XCTAssertFalse(f.advance(100))
        f.setMode(.right)
        XCTAssertFalse(f.facingLeft)
        XCTAssertFalse(f.advance(100))
    }

    func testTurnAroundFlipsWithinInterval() {
        var f = FacingController(mode: .turnAround, random: { 0.5 }) // next turn at 10 s
        XCTAssertFalse(f.facingLeft)
        XCTAssertFalse(f.advance(9.9))
        XCTAssertTrue(f.advance(0.2))
        XCTAssertTrue(f.facingLeft)
        XCTAssertFalse(f.advance(5))
        XCTAssertTrue(f.advance(5.1))
        XCTAssertFalse(f.facingLeft)
    }

    func testTurnAroundKeepsCurrentDirectionWhenEnabled() {
        var f = FacingController(mode: .left)
        f.setMode(.turnAround)
        XCTAssertTrue(f.facingLeft)
    }

    func testIgnoresBadTime() {
        var f = FacingController(mode: .turnAround, random: { 0 })
        XCTAssertFalse(f.advance(-1))
        XCTAssertFalse(f.advance(.nan))
        XCTAssertFalse(f.facingLeft)
    }

    func testFlipButtonToggles() {
        XCTAssertEqual(PetFacing.right.flipped, .left)
        XCTAssertEqual(PetFacing.left.flipped, .right)
        XCTAssertEqual(PetFacing.turnAround.flipped, .left)
    }
}

final class EnergyPolicyTests: XCTestCase {
    typealias I = EnergyPolicy.Inputs

    func testNormalAnimatesAtFullRate() {
        let p = EnergyPolicy(I())
        XCTAssertTrue(p.animate)
        XCTAssertNil(p.maxFPS)
        XCTAssertEqual(p.samplingInterval, 1.5)
    }

    func testHiddenMenuBarStopsAnimationAndSlowsSampling() {
        let p = EnergyPolicy(I(menuBarVisible: false))
        XCTAssertFalse(p.animate)
        XCTAssertEqual(p.samplingInterval, EnergyPolicy.idleSamplingInterval)
    }

    func testPausedSamplesSlowlyUnlessUIIsOpen() {
        XCTAssertEqual(EnergyPolicy(I(paused: true)).samplingInterval, EnergyPolicy.idleSamplingInterval)
        XCTAssertEqual(EnergyPolicy(I(paused: true, uiOpen: true)).samplingInterval, 1.5)
    }

    func testSuspendedStopsEverything() {
        let p = EnergyPolicy(I(suspended: true, uiOpen: true))
        XCTAssertFalse(p.animate)
        XCTAssertNil(p.samplingInterval)
    }

    func testBatteryTiers() {
        let battery = EnergyPolicy(I(onBattery: true))
        XCTAssertEqual(battery.maxFPS, 8)
        XCTAssertEqual(battery.samplingInterval, 3)
        XCTAssertNil(EnergyPolicy(I(onBattery: true, batterySaver: false)).maxFPS)
        // Low Power Mode applies even with Battery saver off.
        let low = EnergyPolicy(I(onBattery: true, lowPowerMode: true, batterySaver: false))
        XCTAssertEqual(low.maxFPS, 5)
        XCTAssertEqual(low.samplingInterval, 5)
    }

    func testUserIntervalIsNeverShortened() {
        XCTAssertEqual(EnergyPolicy(I(onBattery: true, samplingInterval: 4.5)).samplingInterval, 4.5)
        XCTAssertEqual(EnergyPolicy(I(paused: true, samplingInterval: 20)).samplingInterval, 20)
    }
}

final class UpdateConfigurationTests: XCTestCase {
    /// The security-relevant Sparkle settings must never silently disappear from Info.plist.
    func testSparkleSecurityKeysArePresent() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertEqual(info["SURequireSignedFeed"] as? Bool, true)
        XCTAssertEqual(info["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
        XCTAssertEqual(info["SUAutomaticallyUpdate"] as? Bool, false)
        let feed = try XCTUnwrap(info["SUFeedURL"] as? String)
        XCTAssertTrue(feed.hasPrefix("https://"), feed)
    }

    func testVersionIsComparable() throws {
        // Sparkle compares CFBundleVersion; it must equal the marketing version.
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertEqual(info["CFBundleVersion"] as? String, info["CFBundleShortVersionString"] as? String)
    }
}

final class ManifestTests: XCTestCase {
    private func manifest(_ json: String) throws -> PetManifest {
        try JSONDecoder().decode(PetManifest.self, from: json.data(using: .utf8)!)
    }

    private let valid = """
    {"id":"x","displayName":"X","frameSize":[32,32],"animations":{
      "idle":{"frames":4,"fps":4,"loop":true},"walk":{"frames":6,"fps":8,"loop":true},
      "run":{"frames":6,"fps":12,"loop":true},"jump":{"frames":6,"fps":10,"loop":false},
      "sleep":{"frames":4,"fps":2,"loop":true}}}
    """

    func testValidManifest() throws {
        let m = try manifest(valid)
        XCTAssertNoThrow(try m.validate())
        XCTAssertEqual(m.animSpecs.count, 5)
        XCTAssertEqual(m.animSpecs[2].frames, 6)
        XCTAssertEqual(m.menuBar, .run)
    }

    func testMissingAnimationRejected() throws {
        var m = try manifest(valid)
        m.animations["sleep"] = nil
        XCTAssertThrowsError(try m.validate())
    }

    func testBadFrameCountRejected() throws {
        var m = try manifest(valid)
        m.animations["run"]?.frames = 0
        XCTAssertThrowsError(try m.validate())
        m = try manifest(valid)
        m.frameSize = [32]
        XCTAssertThrowsError(try m.validate())
    }
}

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

final class BridgeTests: XCTestCase {
    func testABIMatches() {
        XCTAssertTrue(RustBridge.isCompatible)
    }

    func testEngineSamples() throws {
        let engine = try XCTUnwrap(MetricsEngine())
        _ = engine.sample()
        let m = try XCTUnwrap(engine.sample())
        XCTAssertGreaterThan(m.ram_total_bytes, 0)
        XCTAssertTrue((0...100).contains(m.ram_used_percent))
    }

    func testGradientSampleMatchesDefaults() throws {
        let colors = PetSettings.defaultColors.map(PetColor.init)
        let t = PetSettings.defaultThresholds.map(Float.init)
        let low = try XCTUnwrap(RustBridge.sampleBands(colors: colors, thresholds: t, value: 5))
        XCTAssertEqual(low.g, Float(RGB.green.g), accuracy: 0.01)
        XCTAssertNil(RustBridge.sampleBands(colors: colors, thresholds: [60, 30, 80], value: 5))
    }

    func testActorShowsEveryRunFrame() throws {
        let actor = try XCTUnwrap(PetActorHandle())
        var o = ActorOptions()
        o.cpuDrivenSpeed = false
        let specs = (0..<5).map { _ in PetAnimSpec(frames: 6, fps: 12, looping: 1) }
        XCTAssertTrue(actor.configure(o, animations: specs))
        var seen = Set<UInt32>()
        for _ in 0..<24 {
            let f = actor.tick(dt: 1.0 / 12)
            XCTAssertEqual(f.state, PetStateKind.run.rawValue)
            seen.insert(f.frame_index)
        }
        XCTAssertEqual(seen.count, 6)
    }
}
