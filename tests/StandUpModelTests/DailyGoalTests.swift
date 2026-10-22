import XCTest
import StandUpCore
@testable import StandUpModel

private final class MemoryHistoryStorage: StandingHistoryStorage {
    var data: Data?
    func load() -> Data? { data }
    func save(_ data: Data) { self.data = data }
}

private final class TestMonitoringClock {
    var uptime: TimeInterval = 100
    var date = ISO8601DateFormatter().date(from: "2026-10-22T12:00:00+08:00")!
    func read() -> MonitoringInstant { MonitoringInstant(uptime: uptime, date: date) }
    func advance(_ seconds: TimeInterval) { uptime += seconds; date.addTimeInterval(seconds) }
}

@MainActor
final class DailyGoalTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    func testRealDeviceCreditsPersistAndSessionResetKeepsToday() throws {
        let storage = MemoryHistoryStorage()
        let clock = TestMonitoringClock()
        var connected = true
        let model = AppModel(defaults: nil, historyStorage: storage, clock: clock.read,
                             deviceIsReady: { connected }, calendar: calendar, startTimer: false)
        model.dailyGoalMinutes = 45
        var sequence: UInt16 = 0
        func send() {
            clock.advance(0.25)
            sequence &+= 1
            model.bluetooth.onFrame?(DistanceFrame.encode(sequence: sequence, uptime: UInt32(sequence) * 250, distance: 450, simulated: false))
        }
        for _ in 0..<9 { send() }
        XCTAssertEqual(model.posture, .standing)
        XCTAssertEqual(model.todayRecord.standingSeconds, 0.5, accuracy: 0.001)
        XCTAssertTrue(model.isCountingDailyStanding)
        for _ in 0..<4 { send() }
        model.dailyGoalMinutes = 30
        XCTAssertEqual(model.posture, .standing) // Editing the goal does not restart distance detection.
        let total = model.todayRecord.standingSeconds
        model.resetSession()
        XCTAssertEqual(model.standingSeconds, 0)
        XCTAssertEqual(model.todayRecord.standingSeconds, total)
        let restored = AppModel(defaults: nil, historyStorage: storage, clock: clock.read,
                                deviceIsReady: { connected }, calendar: calendar, startTimer: false)
        XCTAssertEqual(restored.todayRecord.standingSeconds, total)
        XCTAssertEqual(restored.dailyGoalMinutes, 30)
        clock.advance(3600)
        restored.tick()
        XCTAssertEqual(restored.todayRecord.standingSeconds, total) // No backfill on relaunch.
        connected = false
        for _ in 0..<20 { send() }
        XCTAssertEqual(model.todayRecord.standingSeconds, total)
    }

    func testDemoMockInvalidAndDisconnectNeverAddGoalTime() {
        let clock = TestMonitoringClock()
        var connected = true
        let model = AppModel(defaults: nil, clock: clock.read, deviceIsReady: { connected }, calendar: calendar, startTimer: false)
        var sequence: UInt16 = 0
        func send(simulated: Bool = false, valid: Bool = true) {
            clock.advance(0.25)
            sequence &+= 1
            model.bluetooth.onFrame?(DistanceFrame.encode(sequence: sequence, uptime: UInt32(sequence) * 250, distance: valid ? 450 : nil, simulated: simulated))
        }
        for _ in 0..<20 { send(simulated: true) }
        XCTAssertEqual(model.todayRecord.standingSeconds, 0)
        send() // Switching away from mock must require a fresh real-data dwell.
        XCTAssertEqual(model.posture, .unknown)
        XCTAssertEqual(model.todayRecord.standingSeconds, 0)
        for _ in 0..<8 { send() }
        let real = model.todayRecord.standingSeconds
        XCTAssertGreaterThan(real, 0)
        send(valid: false)
        let invalidTotal = model.todayRecord.standingSeconds
        clock.advance(10)
        model.tick()
        XCTAssertEqual(model.todayRecord.standingSeconds, invalidTotal)
        connected = false
        for _ in 0..<20 { send() }
        XCTAssertEqual(model.todayRecord.standingSeconds, invalidTotal)
        connected = true
        model.setActive(false)
        let paused = model.todayRecord.standingSeconds
        clock.advance(3600)
        model.tick()
        send()
        model.setActive(true)
        XCTAssertEqual(model.todayRecord.standingSeconds, paused)
        XCTAssertEqual(model.posture, .unknown)
        model.startDemo()
        for _ in 0..<30 { clock.advance(0.25); model.tick() }
        model.stopDemo()
        XCTAssertEqual(model.todayRecord.standingSeconds, paused)
    }

    func testUnobservedTimeIsNeverCredited() {
        let clock = TestMonitoringClock()
        clock.date = ISO8601DateFormatter().date(from: "2026-10-22T23:59:57+08:00")!
        let model = AppModel(defaults: nil, clock: clock.read, deviceIsReady: { true }, calendar: calendar, startTimer: false)
        for i in 1...8 {
            clock.advance(0.25)
            model.bluetooth.onFrame?(DistanceFrame.encode(sequence: UInt16(i), uptime: UInt32(i) * 250, distance: 450, simulated: false))
        }
        XCTAssertEqual(model.posture, .standing)
        let before = model.todayRecord.standingSeconds
        clock.advance(100)
        model.tick()
        XCTAssertEqual(model.posture, .unknown)
        XCTAssertEqual(model.dailyHistory.records["2026-10-22"]?.standingSeconds ?? 0, before, accuracy: 0.001)
        XCTAssertEqual(model.todayRecord.day, "2026-10-23")
        XCTAssertEqual(model.todayRecord.standingSeconds, 0)
    }

    func testLockedRealNotificationsCountWithoutTimerAndPersistEachEvent() throws {
        let storage = MemoryHistoryStorage()
        let clock = TestMonitoringClock()
        let model = AppModel(defaults: nil, historyStorage: storage, clock: clock.read,
                             deviceIsReady: { true }, calendar: calendar, startTimer: false)
        model.setActive(false) // Includes a background restoration launch with no scene.
        for i in 1...20 {
            clock.advance(0.25)
            model.bluetooth.onFrame?(DistanceFrame.encode(sequence: UInt16(i), uptime: UInt32(i) * 250,
                                                          distance: 450, simulated: false))
        }
        XCTAssertEqual(model.posture, .standing)
        XCTAssertTrue(model.isCountingDailyStanding)
        XCTAssertEqual(model.todayRecord.standingSeconds, 3.25, accuracy: 0.001)
        let saved = try JSONDecoder().decode(StandingHistory.self, from: XCTUnwrap(storage.data))
        XCTAssertEqual(saved.records[model.todayRecord.day]?.standingSeconds, model.todayRecord.standingSeconds)
        let beforeUnlock = model.todayRecord.standingSeconds
        model.setActive(true)
        model.tick()
        XCTAssertEqual(model.todayRecord.standingSeconds, beforeUnlock) // No duplicate credit on unlock.
        XCTAssertEqual(model.posture, .standing) // Lock/unlock alone does not reset fresh detection.
        model.setActive(false)
        clock.advance(0.25)
        model.bluetooth.onFrame?(DistanceFrame.encode(sequence: 21, uptime: 5250, distance: 450, simulated: false))
        XCTAssertEqual(model.todayRecord.standingSeconds, beforeUnlock + 0.25, accuracy: 0.001)
    }

    func testBackgroundGapDisconnectReconnectionAndRelaunchRequireFreshData() {
        let storage = MemoryHistoryStorage()
        let clock = TestMonitoringClock()
        var connected = true
        let model = AppModel(defaults: nil, historyStorage: storage, clock: clock.read,
                             deviceIsReady: { connected }, calendar: calendar, startTimer: false)
        model.setActive(false)
        var sequence: UInt16 = 0
        var uptime: UInt32 = 0
        func send() {
            clock.advance(0.25); uptime &+= 250; sequence &+= 1
            model.bluetooth.onFrame?(DistanceFrame.encode(sequence: sequence, uptime: uptime, distance: 450, simulated: false))
        }
        for _ in 0..<20 { send() }
        let beforeGap = model.todayRecord.standingSeconds
        clock.advance(3600)
        uptime &+= 3_600_000
        sequence &+= 40_000 // More than half a sequence cycle during suspension.
        send()
        XCTAssertEqual(model.todayRecord.standingSeconds, beforeGap)
        XCTAssertEqual(model.posture, .unknown)
        for _ in 0..<8 { send() }
        XCTAssertEqual(model.todayRecord.standingSeconds, beforeGap + 0.5, accuracy: 0.001)
        connected = false
        model.bluetooth.onDisconnect?()
        let beforeReconnect = model.todayRecord.standingSeconds
        clock.advance(600)
        connected = true
        sequence = 0; uptime = 0 // Rebooted board; disconnect reset the protocol state.
        send()
        XCTAssertEqual(model.posture, .unknown)
        XCTAssertEqual(model.todayRecord.standingSeconds, beforeReconnect)
        for _ in 0..<8 { send() }
        XCTAssertEqual(model.todayRecord.standingSeconds, beforeReconnect + 0.5, accuracy: 0.001)
        let relaunched = AppModel(defaults: nil, historyStorage: storage, clock: clock.read,
                                 deviceIsReady: { true }, calendar: calendar, startTimer: false)
        relaunched.setActive(false)
        let persisted = relaunched.todayRecord.standingSeconds
        clock.advance(600)
        relaunched.bluetooth.onFrame?(DistanceFrame.encode(sequence: 1000, uptime: 600_000, distance: 450, simulated: false))
        XCTAssertEqual(relaunched.todayRecord.standingSeconds, persisted)
        XCTAssertEqual(relaunched.posture, .unknown)
    }

    func testBackgroundMidnightSplitsMeasuredIntervalAndRetainsGoals() {
        let clock = TestMonitoringClock()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        clock.date = formatter.date(from: "2026-10-22T23:59:57.875+08:00")!
        let model = AppModel(defaults: nil, clock: clock.read, deviceIsReady: { true }, calendar: calendar, startTimer: false)
        model.dailyGoalMinutes = 45
        model.setActive(false)
        for i in 1...9 {
            clock.advance(0.25)
            model.bluetooth.onFrame?(DistanceFrame.encode(sequence: UInt16(i), uptime: UInt32(i) * 250, distance: 450, simulated: false))
        }
        XCTAssertEqual(model.dailyHistory.records["2026-10-22"]?.standingSeconds ?? 0, 0.375, accuracy: 0.001)
        XCTAssertEqual(model.todayRecord.day, "2026-10-23")
        XCTAssertEqual(model.todayRecord.standingSeconds, 0.125, accuracy: 0.001)
        XCTAssertEqual(model.todayRecord.goalMinutes, 45)
    }

    func testDuplicateMalformedStalledAndBufferedFramesCannotCreateCredit() {
        let clock = TestMonitoringClock()
        let model = AppModel(defaults: nil, clock: clock.read, deviceIsReady: { true }, calendar: calendar, startTimer: false)
        model.setActive(false)
        for i in 1...10 {
            clock.advance(0.25)
            model.bluetooth.onFrame?(DistanceFrame.encode(sequence: UInt16(i), uptime: UInt32(i) * 250, distance: 450, simulated: false))
        }
        let total = model.todayRecord.standingSeconds
        clock.advance(0.25)
        model.bluetooth.onFrame?(DistanceFrame.encode(sequence: 10, uptime: 2500, distance: 450, simulated: false))
        model.bluetooth.onFrame?(DistanceFrame.encode(sequence: 9, uptime: 2250, distance: 450, simulated: false))
        XCTAssertEqual(model.todayRecord.standingSeconds, total)
        model.bluetooth.onFrame?(Data([0]))
        XCTAssertEqual(model.posture, .unknown)
        for i in 11...30 { // A burst delivered at the same host time is not 5 seconds of standing.
            model.bluetooth.onFrame?(DistanceFrame.encode(sequence: UInt16(i), uptime: UInt32(i) * 250, distance: 450, simulated: false))
        }
        XCTAssertEqual(model.todayRecord.standingSeconds, total)
        XCTAssertEqual(model.posture, .unknown)
        for i in 31...50 { // Increasing sequence with stalled sensor-clock snapshots is also excluded.
            clock.advance(0.25)
            model.bluetooth.onFrame?(DistanceFrame.encode(sequence: UInt16(i), uptime: 7500, distance: 450, simulated: false))
        }
        XCTAssertEqual(model.todayRecord.standingSeconds, total)
        XCTAssertEqual(model.posture, .unknown)
    }

    func testMockNotificationsAndPhoneDemoNeverCreditWhileLocked() {
        let clock = TestMonitoringClock()
        let model = AppModel(defaults: nil, clock: clock.read, deviceIsReady: { true }, calendar: calendar, startTimer: false)
        model.setActive(false)
        for i in 1...20 {
            clock.advance(0.25)
            model.bluetooth.onFrame?(DistanceFrame.encode(sequence: UInt16(i), uptime: UInt32(i) * 250, distance: 450, simulated: true))
        }
        XCTAssertEqual(model.posture, .standing)
        XCTAssertEqual(model.todayRecord.standingSeconds, 0)
        model.setActive(true)
        model.startDemo()
        for _ in 0..<20 { clock.advance(0.25); model.tick() }
        XCTAssertEqual(model.posture, .standing)
        model.setActive(false)
        let session = model.standingSeconds
        for _ in 0..<20 { clock.advance(0.25); model.tick() }
        XCTAssertEqual(model.standingSeconds, session)
        XCTAssertEqual(model.posture, .unknown)
        XCTAssertEqual(model.todayRecord.standingSeconds, 0)
    }

    func testExpiredRecordsAreRemovedFromStorageEvenWithoutADevice() throws {
        let storage = MemoryHistoryStorage()
        let clock = TestMonitoringClock()
        var old = StandingHistory(goalMinutes: 45)
        let expired = calendar.date(byAdding: .day, value: -30, to: clock.date)!
        old.credit(seconds: 600, endingAt: expired, posture: .standing,
                   connected: true, simulated: false, calendar: calendar)
        storage.data = try JSONEncoder().encode(old)
        let model = AppModel(defaults: nil, historyStorage: storage, clock: clock.read,
                             deviceIsReady: { false }, calendar: calendar, startTimer: false)
        XCTAssertEqual(model.dailyHistory.records.count, 1)
        XCTAssertEqual(model.todayRecord.standingSeconds, 0)
        let stored = try JSONDecoder().decode(StandingHistory.self, from: XCTUnwrap(storage.data))
        XCTAssertEqual(stored.records.count, 1)
        XCTAssertEqual(stored.records.keys.first, "2026-10-22")
    }
}
