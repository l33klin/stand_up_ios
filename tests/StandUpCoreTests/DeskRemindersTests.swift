import XCTest
@testable import StandUpCore

final class DeskRemindersTests: XCTestCase {
    func testSettingsDefaultsValidationAndRoundTrip() throws {
        var settings = ReminderSettings()
        XCTAssertFalse(settings.sittingEnabled)
        XCTAssertFalse(settings.goalEnabled)
        XCTAssertEqual(settings.sittingMinutes, 45)
        settings.sittingEnabled = true
        settings.sittingMinutes = 1
        XCTAssertEqual(settings.validated().sittingMinutes, 15)
        settings.sittingMinutes = 999
        XCTAssertEqual(ReminderSettings.restore(from: try JSONEncoder().encode(settings)).sittingMinutes, 120)
        XCTAssertEqual(ReminderSettings.restore(from: Data("invalid".utf8)), ReminderSettings())
    }

    func testSittingThresholdRemindsOnceAndARealBreakAllowsNextReminder() {
        var tracker = DeskReminderTracker()
        var settings = ReminderSettings()
        settings.sittingEnabled = true
        settings.sittingMinutes = 15
        XCTAssertFalse(tracker.recordSitting(seconds: 899.75, settings: settings, canNotify: true))
        XCTAssertTrue(tracker.recordSitting(seconds: 0.25, settings: settings, canNotify: true))
        XCTAssertFalse(tracker.recordSitting(seconds: 900, settings: settings, canNotify: true))
        tracker.resetSitting()
        XCTAssertEqual(tracker.sittingSeconds, 0)
        XCTAssertTrue(tracker.recordSitting(seconds: 900, settings: settings, canNotify: true))
    }

    func testDisabledDeniedAndInvalidIntervalsNeverNotify() {
        var tracker = DeskReminderTracker()
        var settings = ReminderSettings()
        for seconds in [Double.nan, Double.infinity, -1, 0] {
            XCTAssertFalse(tracker.recordSitting(seconds: seconds, settings: settings, canNotify: true))
        }
        XCTAssertEqual(tracker.sittingSeconds, 0)
        XCTAssertFalse(tracker.recordSitting(seconds: 3600, settings: settings, canNotify: true))
        settings.sittingEnabled = true
        XCTAssertFalse(tracker.recordSitting(seconds: 3600, settings: settings, canNotify: false))
    }

    func testGoalLedgerPersistsOncePerDayAndPrunesToThirtyDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let today = ISO8601DateFormatter().date(from: "2026-10-29T12:00:00+08:00")!
        var ledger = GoalReminderLedger()
        for offset in -35...0 {
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            let key = StandingHistory.dayKey(for: date, calendar: calendar)
            XCTAssertTrue(ledger.reserve(day: key, on: date, calendar: calendar))
            XCTAssertFalse(ledger.reserve(day: key, on: date, calendar: calendar))
        }
        XCTAssertEqual(ledger.days.count, 30)
        let restored = GoalReminderLedger.restore(from: try JSONEncoder().encode(ledger), on: today, calendar: calendar)
        XCTAssertEqual(restored, ledger)
        XCTAssertEqual(GoalReminderLedger.restore(from: Data("invalid".utf8), on: today).days, [])
    }

    func testMilestonesUseExactProgressAndHandleEmptyInvalidAndExcessValues() {
        for (progress, stage) in [(0.0, GoalMilestone.starting), (0.249999, .starting), (0.25, .quarter),
                                  (0.5, .half), (0.74999, .half), (0.75, .threeQuarters), (1, .complete), (2, .complete)] {
            XCTAssertEqual(GoalMilestone.reached(progress: progress), stage)
        }
        XCTAssertEqual(GoalMilestone.reached(progress: .nan), .starting)
        XCTAssertEqual(DailyDeskRecord(day: "2026-10-29", goalMinutes: 60).milestone, .starting)
    }
}
