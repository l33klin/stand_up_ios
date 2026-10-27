import Foundation

/// A recurring break in the phone's local time. Endpoints are minute-of-day values.
public struct LunchBreakSettings: Codable, Equatable {
    public var isEnabled: Bool
    public var startMinute: Int
    public var endMinute: Int

    public init(isEnabled: Bool = false, startMinute: Int = 12 * 60, endMinute: Int = 13 * 60) {
        self.isEnabled = isEnabled
        self.startMinute = min(1439, max(0, startMinute))
        self.endMinute = min(1439, max(0, endMinute))
    }

    public var hasValidTimes: Bool { (0..<1440).contains(startMinute) && (0..<1440).contains(endMinute) && startMinute != endMinute }
    public var crossesMidnight: Bool { endMinute < startMinute }

    public func validated() -> Self {
        Self(isEnabled: isEnabled, startMinute: startMinute, endMinute: endMinute)
    }

    public static func restore(from data: Data?) -> Self {
        guard let data, let saved = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return saved.validated()
    }

    public func isActive(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard isEnabled, hasValidTimes, date.timeIntervalSinceReferenceDate.isFinite else { return false }
        let day = calendar.startOfDay(for: date)
        if let interval = interval(startingOn: day, calendar: calendar), date >= interval.start, date < interval.end { return true }
        if crossesMidnight, let yesterday = calendar.date(byAdding: .day, value: -1, to: day),
           let interval = interval(startingOn: yesterday, calendar: calendar) {
            return date >= interval.start && date < interval.end
        }
        return false
    }

    /// Subtract only overlapping break time, including partial samples and overnight breaks.
    public func countedSeconds(from start: Date, to end: Date, calendar: Calendar = .autoupdatingCurrent) -> TimeInterval {
        guard start.timeIntervalSinceReferenceDate.isFinite, end.timeIntervalSinceReferenceDate.isFinite,
              end > start else { return 0 }
        let duration = end.timeIntervalSince(start)
        guard isEnabled, hasValidTimes else { return duration }
        var day = calendar.startOfDay(for: start)
        if crossesMidnight, let previous = calendar.date(byAdding: .day, value: -1, to: day) { day = previous }
        var excluded: TimeInterval = 0
        while day < end {
            if let interval = interval(startingOn: day, calendar: calendar) {
                excluded += max(0, min(end, interval.end).timeIntervalSince(max(start, interval.start)))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return max(0, duration - excluded)
    }

    private func interval(startingOn day: Date, calendar: Calendar) -> DateInterval? {
        let endDay: Date
        if crossesMidnight {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            endDay = next
        } else { endDay = day }
        // Resolve local clock times with Calendar rather than adding fixed seconds across DST.
        guard let start = calendar.date(bySettingHour: startMinute / 60, minute: startMinute % 60, second: 0,
                                        of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first),
              let end = calendar.date(bySettingHour: endMinute / 60, minute: endMinute % 60, second: 0,
                                      of: endDay, matchingPolicy: .nextTime, repeatedTimePolicy: .first),
              end > start else { return nil }
        return DateInterval(start: start, end: end)
    }
}
