import XCTest
import StandUpCore
@testable import StandUpModel

@MainActor
final class AppModelTests: XCTestCase {
    private func waitForSamples(_ seconds: Double = 2.1) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    func testDemoCalibrationSensorFailureAndLifecycle() async throws {
        let model = AppModel(defaults: nil)
        model.settings = DetectionSettings()
        model.startDemo()
        model.demoCentimeters = 45
        try await waitForSamples()
        XCTAssertEqual(model.posture, .standing)
        XCTAssertNotNil(model.distanceMM)
        XCTAssertFalse(model.bluetooth.isReady)
        model.calibrate(standing: true)
        XCTAssertEqual(model.settings.standingCalibrationMM ?? 0, 450, accuracy: 3)
        XCTAssertNil(model.distanceMM)
        model.demoCentimeters = 10
        try await waitForSamples()
        model.calibrate(standing: false)
        XCTAssertEqual(model.settings.thresholdMM, 275, accuracy: 3)
        XCTAssertTrue(model.settings.standingIsFarther)
        try await waitForSamples()
        XCTAssertEqual(model.posture, .sitting)
        model.demoSensorValid = false
        try await waitForSamples(0.4)
        XCTAssertEqual(model.posture, .unknown)
        XCTAssertNil(model.distanceMM)
        model.demoSensorValid = true
        try await waitForSamples()
        model.setActive(false)
        let paused = model.sittingSeconds
        try await waitForSamples(0.4)
        XCTAssertEqual(model.posture, .unknown)
        XCTAssertEqual(model.sittingSeconds, paused)
        model.setActive(true)
        try await waitForSamples(0.4)
        XCTAssertEqual(model.posture, .unknown)
        model.resetSession()
        XCTAssertEqual(model.sittingSeconds, 0)
        XCTAssertEqual(model.standingSeconds, 0)
        model.stopDemo()
        XCTAssertFalse(model.isDemo)
        XCTAssertNil(model.distanceMM)
    }
}
