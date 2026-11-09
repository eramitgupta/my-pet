import CPetCore
import XCTest
@testable import mypet

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
