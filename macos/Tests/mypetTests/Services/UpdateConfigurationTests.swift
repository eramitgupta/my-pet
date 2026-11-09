import CPetCore
import XCTest
@testable import mypet

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
