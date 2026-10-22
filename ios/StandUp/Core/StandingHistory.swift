import Foundation

public struct DailyDeskRecord: Codable, Equatable, Identifiable {
    public let day: String
    public fileprivate(set) var standingSeconds: TimeInterval = 0
    public fileprivate(set) var sittingSeconds: TimeInterval = 0
    public fileprivate(set) var goalMinutes: Int
    public var id: String { day }
    public var goalSeconds: TimeInterval { Double(goalMinutes * 60) }
    public var isComplete: Bool { standingSeconds >= goalSeconds }
    public var progress: Double { min(1, standingSeconds / goalSeconds) }
    public var remainingSeconds: TimeInterval { max(0, goalSeconds - standingSeconds) }

    public init(day: String, goalMinutes: Int) {
        self.day = day
        self.goalMinutes = StandingHistory.validGoal(goalMinutes)
    }
}

/// Daily totals contain only connected, non-simulated measurements, including BLE background wakes.
/// Goal snapshots belong to each day, so changing today's goal preserves past results.
public struct StandingHistory: Codable, Equatable {
    public static let goalRange = 5...480
    public static let retentionDays = 30
    private let version: Int
    public private(set) var goalMinutes: Int
    public private(set) var records: [String: DailyDeskRecord]

    public init(goalMinutes: Int = 60) {
        version = 1
        self.goalMinutes = Self.validGoal(goalMinutes)
        records = [:]
    }

    public static func validGoal(_ minutes: Int) -> Int { min(goalRange.upperBound, max(goalRange.lowerBound, minutes)) }

    public static func dayKey(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let components = dayCalendar(calendar).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }

    public static func date(for day: String, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard day.count == 10, parts.count == 3,
              let date = dayCalendar(calendar).date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              dayKey(for: date, calendar: calendar) == day else { return nil }
        return date
    }

    private static func dayCalendar(_ calendar: Calendar) -> Calendar {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian
    }

    @discardableResult
    public mutating func ensureDay(on date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        let removed = prune(on: date, calendar: calendar)
        let key = Self.dayKey(for: date, calendar: calendar)
        guard records[key] == nil else { return removed }
        records[key] = DailyDeskRecord(day: key, goalMinutes: goalMinutes)
        return true
    }

    @discardableResult
    public mutating func prune(on date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        let calendar = Self.dayCalendar(calendar)
        guard let cutoff = calendar.date(byAdding: .day, value: -(Self.retentionDays - 1),
                                         to: calendar.startOfDay(for: date)) else { return false }
        let firstDay = Self.dayKey(for: cutoff, calendar: calendar)
        let oldCount = records.count
        records = records.filter { $0.key >= firstDay }
        return records.count != oldCount
    }

    public mutating func setGoal(minutes: Int, on date: Date, calendar: Calendar = .autoupdatingCurrent) {
        goalMinutes = Self.validGoal(minutes)
        ensureDay(on: date, calendar: calendar)
        records[Self.dayKey(for: date, calendar: calendar)]?.goalMinutes = goalMinutes
    }

    /// The caller supplies a monotonic-clock duration; wall time only assigns it to local dates.
    /// Splitting at calendar boundaries also handles 23/25-hour daylight-saving days.
    @discardableResult
    public mutating func credit(seconds: TimeInterval, endingAt end: Date, posture: DeskPosture,
                                connected: Bool, simulated: Bool,
                                calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard connected, !simulated, posture != .unknown,
              seconds.isFinite, seconds > 0, seconds <= 90_000,
              end.timeIntervalSinceReferenceDate.isFinite else { return false }
        let calendar = Self.dayCalendar(calendar)
        var start = end.addingTimeInterval(-seconds)
        while start < end {
            let key = Self.dayKey(for: start, calendar: calendar)
            guard let boundary = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start)),
                  boundary > start else { return false }
            let stop = min(end, boundary)
            var record = records[key] ?? DailyDeskRecord(day: key, goalMinutes: goalMinutes)
            if posture == .standing { record.standingSeconds += stop.timeIntervalSince(start) }
            else { record.sittingSeconds += stop.timeIntervalSince(start) }
            records[key] = record
            start = stop
        }
        prune(on: end, calendar: calendar)
        return true
    }

    public static func restore(from data: Data?, on date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Self {
        guard let data, let saved = try? JSONDecoder().decode(Self.self, from: data), saved.version == 1 else { return Self() }
        var history = Self(goalMinutes: saved.goalMinutes)
        for (key, var record) in saved.records {
            guard key == record.day, Self.date(for: key, calendar: calendar) != nil,
                  record.standingSeconds.isFinite, record.standingSeconds >= 0,
                  record.sittingSeconds.isFinite, record.sittingSeconds >= 0,
                  record.standingSeconds + record.sittingSeconds <= 90_000 else { continue }
            record.goalMinutes = validGoal(record.goalMinutes)
            history.records[key] = record
        }
        history.prune(on: date, calendar: calendar)
        return history
    }
}
