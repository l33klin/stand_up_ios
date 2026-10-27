import XCTest
@testable import StandUpCore

final class LunchBreakTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    func testDisabledAndInvalidSchedulePreserveExistingCounting() {
        let start = date("2026-10-26T12:15:00+08:00")
        let end = start.addingTimeInterval(30)
        for settings in [LunchBreakSettings(), LunchBreakSettings(isEnabled: true, startMinute: 720, endMinute: 720)] {
            XCTAssertFalse(settings.isActive(at: start, calendar: calendar))
            XCTAssertEqual(settings.countedSeconds(from: start, to: end, calendar: calendar), 30)
        }
    }

    func testBoundariesAndPartialIntervalsExcludeOnlyLunch() {
        let lunch = LunchBreakSettings(isEnabled: true)
        let start = date("2026-10-26T12:00:00+08:00")
        let end = date("2026-10-26T13:00:00+08:00")
        XCTAssertFalse(lunch.isActive(at: start.addingTimeInterval(-0.125), calendar: calendar))
        XCTAssertTrue(lunch.isActive(at: start, calendar: calendar))
        XCTAssertTrue(lunch.isActive(at: end.addingTimeInterval(-0.125), calendar: calendar))
        XCTAssertFalse(lunch.isActive(at: end, calendar: calendar))
        XCTAssertEqual(lunch.countedSeconds(from: start.addingTimeInterval(-0.125), to: start.addingTimeInterval(0.125), calendar: calendar), 0.125)
        XCTAssertEqual(lunch.countedSeconds(from: end.addingTimeInterval(-0.125), to: end.addingTimeInterval(0.125), calendar: calendar), 0.125)
        XCTAssertEqual(lunch.countedSeconds(from: start, to: end, calendar: calendar), 0)
        XCTAssertEqual(lunch.countedSeconds(from: start.addingTimeInterval(-600), to: end.addingTimeInterval(600), calendar: calendar), 1200)
    }

    func testHistoryExcludesBothPosturesAndPreservesPreviousRecords() {
        var history = StandingHistory(goalMinutes: 5)
        let lunch = LunchBreakSettings(isEnabled: true)
        let before = date("2026-10-26T11:59:00+08:00")
        history.credit(seconds: 300, endingAt: before, posture: .standing, connected: true, simulated: false, calendar: calendar)
        XCTAssertTrue(history.records["2026-10-26"]!.isComplete)
        let saved = history
        for posture in [DeskPosture.standing, .sitting] {
            XCTAssertFalse(history.credit(seconds: 600, endingAt: date("2026-10-26T12:30:00+08:00"), posture: posture,
                                          connected: true, simulated: false, lunchBreak: lunch, calendar: calendar))
        }
        XCTAssertEqual(history, saved)
        history.credit(seconds: 20, endingAt: date("2026-10-26T12:00:10+08:00"), posture: .sitting,
                       connected: true, simulated: false, lunchBreak: lunch, calendar: calendar)
        XCTAssertEqual(history.records["2026-10-26"]?.sittingSeconds, 10)
        history.credit(seconds: 20, endingAt: date("2026-10-26T13:00:10+08:00"), posture: .standing,
                       connected: true, simulated: false, lunchBreak: lunch, calendar: calendar)
        XCTAssertEqual(history.records["2026-10-26"]?.standingSeconds, 310)
    }

    func testOvernightBreakRecursAndHistoryStillSplitsAtMidnight() {
        let lunch = LunchBreakSettings(isEnabled: true, startMinute: 23 * 60 + 30, endMinute: 30)
        XCTAssertTrue(lunch.isActive(at: date("2026-10-27T00:15:00+08:00"), calendar: calendar))
        XCTAssertFalse(lunch.isActive(at: date("2026-10-27T00:30:00+08:00"), calendar: calendar))
        var history = StandingHistory()
        history.credit(seconds: 7200, endingAt: date("2026-10-27T01:00:00+08:00"), posture: .standing,
                       connected: true, simulated: false, lunchBreak: lunch, calendar: calendar)
        XCTAssertEqual(history.records["2026-10-26"]?.standingSeconds, 1800)
        XCTAssertEqual(history.records["2026-10-27"]?.standingSeconds, 1800)
        XCTAssertTrue(lunch.isActive(at: date("2026-10-28T00:00:00+08:00"), calendar: calendar))
    }

    func testLocalTimeAndDaylightSavingUseCalendarBoundaries() {
        var local = calendar
        local.timeZone = TimeZone(identifier: "America/New_York")!
        let lunch = LunchBreakSettings(isEnabled: true, startMinute: 23 * 60, endMinute: 3 * 60)
        // This overnight break lasts five real hours when the clocks fall back.
        XCTAssertEqual(lunch.countedSeconds(from: date("2026-10-31T22:30:00-04:00"),
                                            to: date("2026-11-01T03:30:00-05:00"), calendar: local), 3600)
        // And three real hours when the clocks spring forward.
        XCTAssertEqual(lunch.countedSeconds(from: date("2026-03-07T22:30:00-05:00"),
                                            to: date("2026-03-08T03:30:00-04:00"), calendar: local), 3600)
        let noon = LunchBreakSettings(isEnabled: true)
        let instant = date("2026-10-26T12:30:00+08:00")
        XCTAssertTrue(noon.isActive(at: instant, calendar: calendar))
        XCTAssertFalse(noon.isActive(at: instant, calendar: local))
    }

    func testPersistenceDefaultsAndValidation() throws {
        let lunch = LunchBreakSettings(isEnabled: true, startMinute: 750, endMinute: 810)
        XCTAssertEqual(LunchBreakSettings.restore(from: try JSONEncoder().encode(lunch)), lunch)
        XCTAssertEqual(LunchBreakSettings.restore(from: nil), LunchBreakSettings())
        XCTAssertEqual(LunchBreakSettings.restore(from: Data("invalid".utf8)), LunchBreakSettings())
        let bad = Data(#"{"isEnabled":true,"startMinute":-10,"endMinute":2000}"#.utf8)
        let restored = LunchBreakSettings.restore(from: bad)
        XCTAssertEqual(restored.startMinute, 0)
        XCTAssertEqual(restored.endMinute, 1439)
    }
}
