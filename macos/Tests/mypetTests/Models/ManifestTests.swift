import CPetCore
import XCTest
@testable import mypet

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
