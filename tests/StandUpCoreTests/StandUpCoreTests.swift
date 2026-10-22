import XCTest
@testable import StandUpCore

final class StandUpCoreTests: XCTestCase {
    func testGoldenFrameAndLittleEndian() throws {
        // Shared with firmware/tests/protocol_test.c and docs/ble-protocol.md.
        let golden = Data([1, 1, 0x34, 0x12, 0x78, 0x56, 0x34, 0x12, 0xC2, 1, 0, 0])
        let frame = try DistanceFrame(data: golden)
        XCTAssertEqual(frame.sequence, 0x1234)
        XCTAssertEqual(frame.uptimeMilliseconds, 0x12345678)
        XCTAssertEqual(frame.distanceMillimeters, 450)
        XCTAssertTrue(frame.isValid)
        XCTAssertFalse(frame.isSimulated)
        XCTAssertEqual(DistanceFrame.encode(sequence: 0x1234, uptime: 0x12345678, distance: 450, simulated: false), golden)
    }

    func testRejectMalformedOrFutureFrames() {
        let valid = Array(DistanceFrame.encode(sequence: 1, uptime: 0, distance: 300, simulated: false))
        XCTAssertThrowsError(try DistanceFrame(data: Data(valid.dropLast())))
        for (index, value): (Int, UInt8) in [(0, 2), (1, 4), (11, 1), (10, 1)] {
            var mutated = valid
            mutated[index] = value
            XCTAssertThrowsError(try DistanceFrame(data: Data(mutated)))
        }
    }

    func testInvalidAndSimulatedFrames() throws {
        let frame = try DistanceFrame(data: DistanceFrame.encode(sequence: 0, uptime: 1, distance: nil, simulated: true, status: 2))
        XCTAssertFalse(frame.isValid)
        XCTAssertTrue(frame.isSimulated)
        XCTAssertEqual(frame.distanceMillimeters, .max)
        XCTAssertEqual(frame.sensorStatus, 2)
    }

    func testSequenceWrapDuplicatesAndReorder() {
        var sequence = FrameSequence()
        XCTAssertTrue(sequence.accept(65534))
        XCTAssertTrue(sequence.accept(65535))
        XCTAssertTrue(sequence.accept(0))
        XCTAssertFalse(sequence.accept(0))
        XCTAssertFalse(sequence.accept(65535))
        XCTAssertTrue(sequence.accept(3))
    }

    func testMeasuredIntervalHandlesUptimeWrapAndUsesShorterClock() throws {
        XCTAssertEqual(try XCTUnwrap(MeasurementContinuity.interval(previousUptime: UInt32.max - 124, uptime: 125,
                                                                   previousReceipt: 10, receipt: 10.25)), 0.25)
        XCTAssertEqual(try XCTUnwrap(MeasurementContinuity.interval(previousUptime: 1000, uptime: 1250,
                                                                   previousReceipt: 10, receipt: 10.5)), 0.25)
        XCTAssertEqual(try XCTUnwrap(MeasurementContinuity.interval(previousUptime: 1000, uptime: 1500,
                                                                   previousReceipt: 10, receipt: 10.25)), 0.25)
    }

    func testMeasuredIntervalRejectsGapsRebootStalledOrBufferedData() {
        for (before, after, received): (UInt32, UInt32, Double) in [
            (1000, 1250, 60), (1000, 5000, 0.25), (1000, 1000, 0.25),
            (10_000, 0, 0.25), (1000, 1250, 0), (1000, 1250, -1), (1000, 1250, .infinity)
        ] {
            XCTAssertNil(MeasurementContinuity.interval(previousUptime: before, uptime: after,
                                                        previousReceipt: 10, receipt: 10 + received))
        }
    }

    func testDeskHeightAndDwell() {
        var classifier = PostureClassifier()
        let settings = DetectionSettings()
        classifier.ingest(mm: 450, at: 0, settings: settings)
        classifier.ingest(mm: 450, at: 1, settings: settings)
        XCTAssertEqual(classifier.posture, .unknown)
        classifier.ingest(mm: 450, at: 1.5, settings: settings)
        XCTAssertEqual(classifier.posture, .standing)
        for i in 1...16 { classifier.ingest(mm: 100, at: 1.5 + Double(i) * 0.25, settings: settings) }
        XCTAssertEqual(classifier.posture, .sitting)
    }

    func testHysteresisAndMedianIgnoreJitter() {
        var classifier = PostureClassifier()
        let settings = DetectionSettings()
        for i in 0...8 { classifier.ingest(mm: 450, at: Double(i) * 0.25, settings: settings) }
        classifier.ingest(mm: 40, at: 2.25, settings: settings)
        XCTAssertEqual(classifier.filteredMM, 450)
        for i in 10...30 { classifier.ingest(mm: 290, at: Double(i) * 0.25, settings: settings) }
        XCTAssertEqual(classifier.posture, .standing)
    }

    func testInvalidAndStaleBecomeUnknownAndRequireFreshDwell() {
        var classifier = PostureClassifier()
        let settings = DetectionSettings()
        for i in 0...8 { classifier.ingest(mm: 450, at: Double(i) * 0.25, settings: settings) }
        classifier.expire(at: 4.01)
        XCTAssertEqual(classifier.posture, .unknown)
        XCTAssertNil(classifier.filteredMM)
        classifier.ingest(mm: 450, at: 5, settings: settings)
        XCTAssertEqual(classifier.posture, .unknown)
        classifier.ingest(mm: nil, at: 5.25, settings: settings)
        XCTAssertNil(classifier.filteredMM)
        classifier.ingest(mm: .nan, at: 5.5, settings: settings)
        XCTAssertEqual(classifier.posture, .unknown)
    }

    func testDirectionCanBeReversed() {
        var classifier = PostureClassifier()
        var settings = DetectionSettings()
        settings.standingIsFarther = false
        for i in 0...8 { classifier.ingest(mm: 100, at: Double(i) * 0.25, settings: settings) }
        XCTAssertEqual(classifier.posture, .standing)
    }

    func testGapDoesNotCountAsStableTime() {
        var classifier = PostureClassifier()
        let settings = DetectionSettings()
        classifier.ingest(mm: 450, at: 0, settings: settings)
        classifier.ingest(mm: 450, at: 10, settings: settings)
        XCTAssertEqual(classifier.posture, .unknown)
    }

    func testSettingsAndPhysicalRangeBounds() throws {
        var settings = DetectionSettings()
        settings.thresholdMM = 50
        settings.hysteresisMM = 100
        XCTAssertEqual(settings.validated().hysteresisMM, 9)
        var classifier = PostureClassifier()
        for i in 0...8 { classifier.ingest(mm: 100, at: Double(i) * 0.25, settings: settings) }
        XCTAssertEqual(classifier.posture, .standing)
        for i in 9...24 { classifier.ingest(mm: 40, at: Double(i) * 0.25, settings: settings) }
        XCTAssertEqual(classifier.posture, .sitting)
        settings.thresholdMM = .infinity
        settings.stabilitySeconds = -.infinity
        XCTAssertEqual(settings.validated().thresholdMM, 300)
        XCTAssertEqual(settings.validated().stabilitySeconds, 1.5)
        for distance: UInt16 in [39, 4001] {
            XCTAssertFalse(try DistanceFrame(data: DistanceFrame.encode(sequence: 0, uptime: 0, distance: distance, simulated: false)).isValid)
        }
        for distance: UInt16 in [40, 4000] {
            XCTAssertTrue(try DistanceFrame(data: DistanceFrame.encode(sequence: 0, uptime: 0, distance: distance, simulated: false)).isValid)
        }
    }
}
