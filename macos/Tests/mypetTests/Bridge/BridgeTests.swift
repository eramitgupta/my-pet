import CPetCore
import XCTest
@testable import mypet

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
