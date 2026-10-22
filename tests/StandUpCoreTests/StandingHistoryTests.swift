import XCTest
@testable import StandUpCore

final class StandingHistoryTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    func testOnlyConnectedRealPosturesReceiveCredit() {
        let end = date("2026-10-22T12:00:00+08:00")
        var history = StandingHistory()
        for (connected, simulated, posture) in [
            (false, false, DeskPosture.standing),
            (true, true, .standing),
            (true, false, .unknown)
        ] {
            XCTAssertFalse(history.credit(seconds: 60, endingAt: end, posture: posture,
                                          connected: connected, simulated: simulated, calendar: calendar))
        }
        XCTAssertTrue(history.records.isEmpty)
        history.credit(seconds: 90, endingAt: end, posture: .standing, connected: true, simulated: false, calendar: calendar)
        history.credit(seconds: 30, endingAt: end, posture: .sitting, connected: true, simulated: false, calendar: calendar)
        XCTAssertEqual(history.records["2026-10-22"]?.standingSeconds, 90)
        XCTAssertEqual(history.records["2026-10-22"]?.sittingSeconds, 30)
    }

    func testMidnightSplitsOnlyTheMeasuredSecondsBetweenDates() {
        let end = date("2026-10-23T00:00:01+08:00")
        var history = StandingHistory()
        history.credit(seconds: 2, endingAt: end, posture: .standing, connected: true, simulated: false, calendar: calendar)
        XCTAssertEqual(history.records["2026-10-22"]?.standingSeconds, 1)
        XCTAssertEqual(history.records["2026-10-23"]?.standingSeconds, 1)
    }

    func testGoalCompletionAndPastGoalSnapshots() throws {
        let yesterday = date("2026-10-21T12:00:00+08:00")
        let today = date("2026-10-22T12:00:00+08:00")
        var history = StandingHistory(goalMinutes: 30)
        history.credit(seconds: 1801, endingAt: yesterday, posture: .standing, connected: true, simulated: false, calendar: calendar)
        history.setGoal(minutes: 60, on: today, calendar: calendar)
        let record = try XCTUnwrap(history.records["2026-10-21"])
        XCTAssertEqual(record.goalMinutes, 30)
        XCTAssertTrue(record.isComplete)
        XCTAssertEqual(record.progress, 1)
        XCTAssertEqual(record.standingSeconds, 1801)
        XCTAssertEqual(history.records["2026-10-22"]?.goalMinutes, 60)
        history.setGoal(minutes: 5000, on: today, calendar: calendar)
        XCTAssertEqual(history.goalMinutes, 480)
        history.setGoal(minutes: 0, on: today, calendar: calendar)
        XCTAssertEqual(history.goalMinutes, 5)
    }

    func testRoundTripPersistsLastThirtyDaysInclusive() throws {
        let today = date("2026-10-22T12:00:00+08:00")
        var history = StandingHistory(goalMinutes: 45)
        for offset in -35...0 {
            let end = calendar.date(byAdding: .day, value: offset, to: today)!
            history.credit(seconds: 60, endingAt: end, posture: .standing, connected: true, simulated: false, calendar: calendar)
        }
        XCTAssertEqual(history.records.count, 30)
        XCTAssertNotNil(history.records["2026-09-23"])
        XCTAssertNil(history.records["2026-09-22"])
        let restored = StandingHistory.restore(from: try JSONEncoder().encode(history), on: today, calendar: calendar)
        XCTAssertEqual(restored, history)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let older = StandingHistory.restore(from: try JSONEncoder().encode(history), on: tomorrow, calendar: calendar)
        XCTAssertNil(older.records["2026-09-23"])
        XCTAssertEqual(older.records.count, 29)
    }

    func testBadPersistenceAndInvalidDurationsCannotCreateProgress() {
        let today = date("2026-10-22T12:00:00+08:00")
        XCTAssertEqual(StandingHistory.restore(from: Data("invalid".utf8)).goalMinutes, 60)
        var history = StandingHistory()
        for duration in [Double.nan, -Double.infinity, -1, 0, 90_001] {
            XCTAssertFalse(history.credit(seconds: duration, endingAt: today, posture: .standing,
                                          connected: true, simulated: false, calendar: calendar))
        }
        XCTAssertTrue(history.records.isEmpty)
        XCTAssertNil(StandingHistory.date(for: "2026-02-30", calendar: calendar))
    }

    func testDaylightSavingBoundaryUsesCalendarDays() {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = TimeZone(identifier: "America/New_York")!
        let end = date("2026-11-02T00:00:01-05:00")
        var history = StandingHistory()
        history.credit(seconds: 2, endingAt: end, posture: .standing, connected: true, simulated: false, calendar: local)
        XCTAssertEqual(history.records["2026-11-01"]?.standingSeconds, 1)
        XCTAssertEqual(history.records["2026-11-02"]?.standingSeconds, 1)
    }
}
