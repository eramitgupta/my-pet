import CPetCore
import XCTest
@testable import mypet

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
