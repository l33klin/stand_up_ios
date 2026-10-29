import Foundation

public struct ReminderSettings: Codable, Equatable {
    public static let sittingRange = 15...120
    public var sittingEnabled = false
    public var goalEnabled = false
    public var sittingMinutes = 45
    public init() {}
    public func validated() -> Self {
        var value = self
        value.sittingMinutes = min(Self.sittingRange.upperBound, max(Self.sittingRange.lowerBound, sittingMinutes))
        return value
    }
    public static func restore(from data: Data?) -> Self {
        guard let data, let saved = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return saved.validated()
    }
}

public struct GoalReminderLedger: Codable, Equatable {
    public private(set) var days: Set<String> = []
    public init() {}

    public mutating func reserve(day: String, on date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        prune(on: date, calendar: calendar)
        guard StandingHistory.date(for: day, calendar: calendar) != nil else { return false }
        return days.insert(day).inserted
    }

    private mutating func prune(on date: Date, calendar: Calendar) {
        let cutoff = calendar.date(byAdding: .day, value: -29, to: date) ?? date
        let first = StandingHistory.dayKey(for: cutoff, calendar: calendar)
        let today = StandingHistory.dayKey(for: date, calendar: calendar)
        days = days.filter { $0 >= first && $0 <= today && StandingHistory.date(for: $0, calendar: calendar) != nil }
    }

    public static func restore(from data: Data?, on date: Date, calendar: Calendar = .autoupdatingCurrent) -> Self {
        var ledger = data.flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self()
        ledger.prune(on: date, calendar: calendar)
        return ledger
    }
}

/// Sitting continuity is deliberately not persisted: relaunches and radio gaps start a new bout.
public struct DeskReminderTracker {
    public private(set) var sittingSeconds: TimeInterval = 0
    private var remindedSitting = false
    public init() {}

    public mutating func resetSitting() { sittingSeconds = 0; remindedSitting = false }

    /// The caller supplies only the confirmed, real, non-lunch sitting interval.
    public mutating func recordSitting(seconds: TimeInterval, settings: ReminderSettings, canNotify: Bool) -> Bool {
        guard seconds.isFinite, seconds > 0 else { return false }
        sittingSeconds += seconds
        guard settings.sittingEnabled, canNotify, !remindedSitting,
              sittingSeconds >= Double(settings.validated().sittingMinutes * 60) else { return false }
        remindedSitting = true
        return true
    }
}

public enum GoalMilestone: Int, CaseIterable, Comparable {
    case starting = 0, quarter = 25, half = 50, threeQuarters = 75, complete = 100
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    public static func reached(progress: Double) -> Self {
        guard progress.isFinite else { return .starting }
        return allCases.reversed().first { progress >= Double($0.rawValue) / 100 } ?? .starting
    }
}

public extension DailyDeskRecord {
    var milestone: GoalMilestone { GoalMilestone.reached(progress: progress) }
}
