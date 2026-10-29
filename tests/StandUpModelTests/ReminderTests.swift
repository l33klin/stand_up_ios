import Foundation
import XCTest
import StandUpCore
@testable import StandUpModel

private final class ReminderClock {
    var uptime: TimeInterval = 100
    var date = ISO8601DateFormatter().date(from: "2026-10-29T11:00:00+08:00")!
    func read() -> MonitoringInstant { MonitoringInstant(uptime: uptime, date: date) }
    func advance(_ seconds: TimeInterval) { uptime += seconds; date.addTimeInterval(seconds) }
}

private final class FakeReminderDelivery: ReminderDelivering {
    var status: ReminderAuthorization = .allowed
    var requests = 0
    var notices: [DeskNotice] = []
    var acceptsDelivery = true
    func activate() {}
    func authorization(_ completion: @escaping (ReminderAuthorization) -> Void) { completion(status) }
    func requestAuthorization(_ completion: @escaping (ReminderAuthorization, String?) -> Void) {
        requests += 1
        if status == .notDetermined { status = .allowed }
        completion(status, nil)
    }
    func deliver(_ notice: DeskNotice, completion: @escaping (Bool) -> Void) {
        notices.append(notice); completion(acceptsDelivery)
    }
}

private final class ReminderStorage: StandingHistoryStorage {
    var data: Data?
    func load() -> Data? { data }
    func save(_ data: Data) { self.data = data }
}

@MainActor
private final class ReminderHarness {
    let clock: ReminderClock
    let delivery: FakeReminderDelivery
    let model: AppModel
    var sequence: UInt16 = 0
    var uptime: UInt32 = 0
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    init(defaults: UserDefaults? = nil, storage: ReminderStorage = ReminderStorage(),
         clock: ReminderClock = ReminderClock(), delivery: FakeReminderDelivery = FakeReminderDelivery()) {
        self.clock = clock
        self.delivery = delivery
        model = AppModel(defaults: defaults, historyStorage: storage, clock: clock.read,
                         deviceIsReady: { true }, calendar: Self.calendar, startTimer: false, reminderDelivery: delivery)
        model.reminderSettings.sittingMinutes = 15
        model.reminderSettings.sittingEnabled = true
        model.reminderSettings.goalEnabled = true
        model.refreshReminderAuthorization()
    }

    func send(_ count: Int = 1, distance: UInt16? = 100, simulated: Bool = false, after: Double = 1) {
        for _ in 0..<count {
            clock.advance(after); sequence &+= 1; uptime &+= UInt32(after * 1000)
            model.bluetooth.onFrame?(DistanceFrame.encode(sequence: sequence, uptime: uptime, distance: distance, simulated: simulated))
        }
    }
}

@MainActor
final class ReminderTests: XCTestCase {
    func testLockedSittingRemindsAtThresholdOnceAndStandingResetsTheBout() {
        let h = ReminderHarness()
        h.model.setActive(false)
        h.send(902)
        XCTAssertEqual(h.model.continuousSittingSeconds, 899)
        XCTAssertTrue(h.delivery.notices.isEmpty)
        h.send()
        XCTAssertEqual(h.delivery.notices.count, 1)
        h.send(100)
        XCTAssertEqual(h.delivery.notices.count, 1)
        h.send(8, distance: 450)
        XCTAssertEqual(h.model.continuousSittingSeconds, 0)
        h.send(910)
        XCTAssertEqual(h.delivery.notices.filter { if case .sitting = $0 { return true }; return false }.count, 2)
    }

    func testInvalidDataGapDisconnectAndSessionResetCannotBackfillSitting() {
        let h = ReminderHarness()
        h.model.setActive(false)
        h.send(902)
        h.send(distance: nil)
        XCTAssertEqual(h.model.continuousSittingSeconds, 0)
        h.send(902)
        h.send(after: 60)
        XCTAssertEqual(h.model.continuousSittingSeconds, 0)
        XCTAssertTrue(h.delivery.notices.isEmpty)
        h.send(50)
        h.model.bluetooth.onDisconnect?()
        XCTAssertEqual(h.model.continuousSittingSeconds, 0)
        h.send(50)
        h.model.resetSession()
        XCTAssertEqual(h.model.continuousSittingSeconds, 0)
        XCTAssertTrue(h.delivery.notices.isEmpty)
    }

    func testLunchMockAndPhoneDemoDoNotTriggerReminders() {
        let h = ReminderHarness()
        h.model.lunchBreak = LunchBreakSettings(isEnabled: true, startMinute: 11 * 60, endMinute: 12 * 60)
        h.model.setActive(false)
        h.send(910)
        XCTAssertEqual(h.model.continuousSittingSeconds, 0)
        h.model.lunchBreak.isEnabled = false
        h.send(910, simulated: true)
        XCTAssertEqual(h.model.continuousSittingSeconds, 0)
        XCTAssertTrue(h.delivery.notices.isEmpty)
        h.model.setActive(true)
        h.model.startDemo()
        h.model.demoCentimeters = 10
        for _ in 0..<910 { h.clock.advance(1); h.model.tick() }
        XCTAssertTrue(h.delivery.notices.isEmpty)
        XCTAssertEqual(h.model.continuousSittingSeconds, 0)
        XCTAssertEqual(h.model.goalMilestoneEvent, 0)
    }

    func testGoalNotificationIsOncePerDayAcrossHigherGoalsAndRelaunch() throws {
        let suite = "StandUpGoalReminderTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = ReminderStorage()
        let clock = ReminderClock()
        var history = StandingHistory(goalMinutes: 5)
        history.credit(seconds: 299, endingAt: clock.date, posture: .standing, connected: true, simulated: false, calendar: ReminderHarness.calendar)
        storage.data = try JSONEncoder().encode(history)
        let first = ReminderHarness(defaults: defaults, storage: storage, clock: clock)
        XCTAssertEqual(first.model.goalMilestoneEvent, 0)
        first.model.setActive(false)
        first.send(4, distance: 450)
        XCTAssertEqual(first.delivery.notices, [.goal(day: "2026-10-29", minutes: 5)])
        XCTAssertEqual(first.model.goalMilestoneEvent, 1)
        let restored = ReminderHarness(defaults: defaults, storage: storage, clock: clock)
        restored.model.dailyGoalMinutes = 10
        restored.model.setActive(false)
        restored.send(304, distance: 450)
        XCTAssertTrue(restored.model.todayRecord.isComplete)
        XCTAssertTrue(restored.delivery.notices.isEmpty) // Saved day ledger, even after another actual crossing.
        clock.date = ISO8601DateFormatter().date(from: "2026-10-30T11:00:00+08:00")!
        restored.send(605, distance: 450, after: 1)
        XCTAssertEqual(restored.delivery.notices, [.goal(day: "2026-10-30", minutes: 10)])
    }

    func testOldAchievementGoalEditsAndDeniedPermissionDoNotSendRetroactiveAlerts() throws {
        let h = ReminderHarness()
        h.model.dailyGoalMinutes = 5
        h.delivery.status = .denied
        h.model.refreshReminderAuthorization()
        h.send(305, distance: 450)
        XCTAssertTrue(h.model.todayRecord.isComplete)
        XCTAssertTrue(h.delivery.notices.isEmpty)
        h.delivery.status = .allowed
        h.model.refreshReminderAuthorization()
        h.model.dailyGoalMinutes = 5
        let oldEvents = h.model.goalMilestoneEvent
        h.send(10, distance: 450)
        XCTAssertTrue(h.delivery.notices.isEmpty)
        XCTAssertEqual(h.model.goalMilestoneEvent, oldEvents)
    }

    func testPermissionIsRequestedOnlyByUserAndSettingsPersist() throws {
        let suite = "StandUpReminderSettingsTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let delivery = FakeReminderDelivery()
        delivery.status = .notDetermined
        let model = AppModel(defaults: defaults, startTimer: false, reminderDelivery: delivery)
        model.refreshReminderAuthorization()
        XCTAssertEqual(delivery.requests, 0)
        model.setSittingReminderEnabled(true)
        XCTAssertEqual(delivery.requests, 1)
        XCTAssertEqual(model.reminderAuthorization, .allowed)
        model.setGoalReminderEnabled(true)
        XCTAssertEqual(delivery.requests, 1)
        model.reminderSettings.sittingMinutes = 30
        let restored = AppModel(defaults: defaults, startTimer: false, reminderDelivery: delivery)
        XCTAssertEqual(restored.reminderSettings, model.reminderSettings)
        delivery.status = .denied
        model.refreshReminderAuthorization()
        model.setGoalReminderEnabled(true)
        XCTAssertEqual(delivery.requests, 1)
        XCTAssertEqual(model.reminderAuthorization, .denied)
    }

    func testShorteningSittingThresholdStartsFreshAndNotificationFailureIsNotRepeated() {
        let h = ReminderHarness()
        h.model.reminderSettings.sittingMinutes = 30
        h.send(905)
        XCTAssertGreaterThan(h.model.continuousSittingSeconds, 900)
        XCTAssertTrue(h.delivery.notices.isEmpty)
        h.model.reminderSettings.sittingMinutes = 15
        XCTAssertEqual(h.model.continuousSittingSeconds, 0)
        h.delivery.acceptsDelivery = false
        h.send(900)
        XCTAssertEqual(h.delivery.notices.count, 1)
        XCTAssertNotNil(h.model.reminderError)
        h.send(10)
        XCTAssertEqual(h.delivery.notices.count, 1)
    }

    func testMidnightIntervalCanCompleteYesterdaysGoalWithoutNotifyingToday() throws {
        let clock = ReminderClock()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        clock.date = formatter.date(from: "2026-10-29T23:59:56.500+08:00")!
        let storage = ReminderStorage()
        var history = StandingHistory(goalMinutes: 5)
        history.credit(seconds: 299.75, endingAt: clock.date, posture: .standing,
                       connected: true, simulated: false, calendar: ReminderHarness.calendar)
        storage.data = try JSONEncoder().encode(history)
        let h = ReminderHarness(storage: storage, clock: clock)
        h.model.setActive(false)
        h.send(4, distance: 450)
        XCTAssertEqual(h.model.todayRecord.day, "2026-10-30")
        XCTAssertEqual(h.model.todayRecord.standingSeconds, 0.5, accuracy: 0.001)
        XCTAssertEqual(h.delivery.notices, [.goal(day: "2026-10-29", minutes: 5)])
        XCTAssertEqual(h.model.goalMilestoneEvent, 0) // Yesterday's completion does not celebrate a new empty day.
    }

    func testManualTestNoticeRequiresPermissionAndNeverChangesProgress() {
        let h = ReminderHarness()
        let before = h.model.dailyHistory
        h.model.sendTestReminder()
        XCTAssertEqual(h.delivery.notices.count, 1)
        guard case .test = h.delivery.notices[0] else { return XCTFail("Expected a clearly labeled test notice") }
        XCTAssertEqual(h.model.dailyHistory, before)
        XCTAssertEqual(h.model.goalMilestoneEvent, 0)
        h.delivery.status = .denied
        h.model.refreshReminderAuthorization()
        h.model.sendTestReminder()
        XCTAssertEqual(h.delivery.notices.count, 1)
    }
}
