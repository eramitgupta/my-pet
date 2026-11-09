import CPetCore
import XCTest
@testable import mypet

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
