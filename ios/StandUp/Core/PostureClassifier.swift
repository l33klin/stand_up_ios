import Foundation

public enum DeskPosture: String, Codable {
    case unknown, sitting, standing
    public var title: String {
        switch self { case .unknown: return "等待识别"; case .sitting: return "坐姿高度"; case .standing: return "站立高度" }
    }
    public var symbol: String {
        switch self { case .unknown: return "sensor"; case .sitting: return "chair"; case .standing: return "figure.stand" }
    }
}

public struct DetectionSettings: Codable, Equatable {
    public var thresholdMM: Double = 300
    public var hysteresisMM: Double = 20
    public var stabilitySeconds: Double = 1.5
    public var standingIsFarther: Bool = true
    public var seatedCalibrationMM: Double?
    public var standingCalibrationMM: Double?
    public init() {}

    // Keep at least one valid millimeter beyond each strict switching edge.
    public var maximumHysteresisMM: Double { max(0, min(100, thresholdMM - 41, 3999 - thresholdMM)) }

    public func validated() -> Self {
        var value = self
        value.thresholdMM = thresholdMM.isFinite ? min(3950, max(50, thresholdMM)) : 300
        let maximumMargin = value.maximumHysteresisMM
        value.hysteresisMM = hysteresisMM.isFinite ? min(maximumMargin, max(0, hysteresisMM)) : min(20, maximumMargin)
        value.stabilitySeconds = stabilitySeconds.isFinite ? min(5, max(0.5, stabilitySeconds)) : 1.5
        return value
    }
}

/// Median filtering + Schmitt trigger + dwell time; all times are monotonic seconds.
public struct PostureClassifier {
    public static let staleAfter: TimeInterval = 2
    public private(set) var posture: DeskPosture = .unknown
    public private(set) var filteredMM: Double?
    public private(set) var lastSampleTime: TimeInterval?
    private var samples: [Double] = []
    private var candidate: DeskPosture = .unknown
    private var candidateSince: TimeInterval = 0
    public init() {}

    public mutating func reset() { self = Self() }

    public mutating func expire(at time: TimeInterval) {
        if let lastSampleTime, time - lastSampleTime > Self.staleAfter { reset() }
    }

    public mutating func ingest(mm: Double?, at time: TimeInterval, settings: DetectionSettings) {
        expire(at: time)
        guard let mm, mm.isFinite, (40...4000).contains(mm) else { reset(); return }
        lastSampleTime = time
        samples.append(mm)
        if samples.count > 5 { samples.removeFirst() }
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        filteredMM = median
        let s = settings.validated()
        // Invert the coordinate axis so standing always means positive distance.
        let signedDistance = (median - s.thresholdMM) * (s.standingIsFarther ? 1 : -1)
        let next: DeskPosture
        switch posture {
        case .unknown: next = signedDistance >= 0 ? .standing : .sitting
        case .standing: next = signedDistance < -s.hysteresisMM ? .sitting : .standing
        case .sitting: next = signedDistance > s.hysteresisMM ? .standing : .sitting
        }
        if next == posture { candidate = posture; candidateSince = time; return }
        if candidate != next { candidate = next; candidateSince = time }
        if time - candidateSince >= s.stabilitySeconds { posture = next }
    }
}
