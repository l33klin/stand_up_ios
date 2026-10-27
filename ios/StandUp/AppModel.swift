import Foundation
import Combine
import Darwin
#if SWIFT_PACKAGE
import StandUpCore
#endif

struct DistancePoint: Identifiable {
    let id = UUID()
    let time: TimeInterval
    let centimeters: Double
}

struct MonitoringInstant {
    let uptime: TimeInterval
    let date: Date
    // Unlike an awake-only clock, this advances through device sleep while locked.
    private static let secondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()
    static var now: Self { Self(uptime: Double(mach_continuous_time()) * secondsPerTick, date: Date()) }
}

protocol StandingHistoryStorage {
    func load() -> Data?
    func save(_ data: Data)
}

private struct LocalStandingHistoryStorage: StandingHistoryStorage {
    let defaults: UserDefaults?
    func load() -> Data? { defaults?.data(forKey: "standingHistory.v1") }
    func save(_ data: Data) { defaults?.set(data, forKey: "standingHistory.v1") }
}

final class AppModel: ObservableObject {
    let bluetooth: BluetoothManager
    @Published var settings: DetectionSettings {
        didSet {
            let validated = settings.validated()
            if settings != validated { settings = validated; return }
            if let data = try? JSONEncoder().encode(settings.validated()) { defaults?.set(data, forKey: "detection.v1") }
            classifier.reset()
            lastMeasurement = nil
            posture = .unknown
            distanceMM = nil
        }
    }
    @Published var lunchBreak: LunchBreakSettings {
        didSet {
            let validated = lunchBreak.validated()
            if lunchBreak != validated { lunchBreak = validated }
            if let data = try? JSONEncoder().encode(validated) { defaults?.set(data, forKey: "lunchBreak.v1") }
            // A setting change applies from now, without reinterpreting the previous sample interval.
            statisticsSettingsChangedAt = clock().uptime
        }
    }
    @Published private(set) var posture: DeskPosture = .unknown
    @Published private(set) var distanceMM: Double?
    @Published private(set) var history: [DistancePoint] = []
    @Published private(set) var isDemo = false
    @Published private(set) var simulatedFirmware = false
    @Published private(set) var sampleMessage = "连接开发板，开始测量升降台与台面的间距。"
    @Published private(set) var standingSeconds: TimeInterval = 0
    @Published private(set) var sittingSeconds: TimeInterval = 0
    @Published private(set) var dailyHistory: StandingHistory
    @Published private(set) var todayDate: Date
    @Published var demoCentimeters: Double = 40
    @Published var demoSensorValid = true
    @Published var calibrationMessage: String?

    private var classifier = PostureClassifier()
    private var sequence = FrameSequence()
    private var timer: Timer?
    private var subscription: AnyCancellable?
    private var lastMeasurement: (receivedAt: TimeInterval, deviceUptime: UInt32)?
    // This controls UI refresh and phone demo only. BLE events also run while locked.
    private var active = true
    private var demoSequence: UInt16 = 0
    private var demoStarted: TimeInterval = 0
    private var sawFrame = false
    private let defaults: UserDefaults?
    private let historyStorage: StandingHistoryStorage
    private let clock: () -> MonitoringInstant
    private let deviceIsReady: () -> Bool
    private let calendar: Calendar
    private let timerEnabled: Bool
    private var lastHistorySave: TimeInterval
    private var historyDirty = false
    private var lastFrameWasSimulated: Bool?
    private var statisticsSettingsChangedAt: TimeInterval

    var todayRecord: DailyDeskRecord {
        let key = StandingHistory.dayKey(for: todayDate, calendar: calendar)
        return dailyHistory.records[key] ?? DailyDeskRecord(day: key, goalMinutes: dailyHistory.goalMinutes)
    }

    var dailyGoalMinutes: Int {
        get { dailyHistory.goalMinutes }
        set {
            let instant = clock()
            refreshDay(at: instant)
            dailyHistory.setGoal(minutes: newValue, on: instant.date, calendar: calendar)
            historyDirty = true
            persistHistory(at: instant, force: true)
        }
    }

    var isCountingDailyStanding: Bool {
        !isOnLunchBreak && deviceIsReady() && !isDemo && lastFrameWasSimulated == false &&
            posture == .standing && classifier.lastSampleTime.map { clock().uptime - $0 <= PostureClassifier.staleAfter } == true
    }

    var isOnLunchBreak: Bool { lunchBreak.isActive(at: clock().date, calendar: calendar) }

    init(defaults: UserDefaults? = .standard, historyStorage: StandingHistoryStorage? = nil,
         clock: @escaping () -> MonitoringInstant = { .now }, deviceIsReady: (() -> Bool)? = nil,
         calendar: Calendar = .autoupdatingCurrent, startTimer: Bool = true) {
        self.defaults = defaults
        let transport = BluetoothManager(defaults: defaults)
        bluetooth = transport
        self.clock = clock
        self.calendar = calendar
        timerEnabled = startTimer
        let instant = clock()
        statisticsSettingsChangedAt = instant.uptime
        lastHistorySave = instant.uptime
        todayDate = instant.date
        let storage = historyStorage ?? LocalStandingHistoryStorage(defaults: defaults)
        self.historyStorage = storage
        dailyHistory = StandingHistory.restore(from: storage.load(), on: instant.date, calendar: calendar)
        self.deviceIsReady = deviceIsReady ?? { transport.isReady }
        if let data = defaults?.data(forKey: "detection.v1"),
           let saved = try? JSONDecoder().decode(DetectionSettings.self, from: data) { settings = saved.validated() }
        else { settings = DetectionSettings() }
        lunchBreak = LunchBreakSettings.restore(from: defaults?.data(forKey: "lunchBreak.v1"))
        bluetooth.onFrame = { [weak self] data in self?.receive(data) }
        bluetooth.onDisconnect = { [weak self] in self?.clearReading(message: "设备未连接，识别已暂停。") }
        subscription = bluetooth.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        dailyHistory.ensureDay(on: instant.date, calendar: calendar)
        historyDirty = true // Also persist pruning performed while restoring older data.
        persistHistory(at: instant, force: true)
        startUITimer()
    }

    deinit { timer?.invalidate() }

    private func startUITimer() {
        guard timerEnabled, active, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
    }

    func startDemo() {
        bluetooth.disconnect()
        isDemo = true
        simulatedFirmware = false
        demoSensorValid = true
        demoStarted = clock().uptime
        demoSequence = 0
        demoCentimeters = min(400, max(4, settings.thresholdMM / 10 + 10))
        resetSession()
        sampleMessage = "手机演示数据 · 拖动距离滑块测试识别。"
    }

    func prepareRealMode() {
        if isDemo { isDemo = false; resetSession() }
    }

    func stopDemo() {
        isDemo = false
        resetSession()
        sampleMessage = "演示已结束，请连接开发板。"
    }

    func connect(_ device: DiscoveredDevice) {
        prepareRealMode()
        resetSession()
        bluetooth.connect(device)
    }

    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        if value {
            startUITimer()
            if !isDemo { bluetooth.resumeMonitoring() }
        }
        else {
            timer?.invalidate()
            timer = nil
            bluetooth.stopScan()
        }
        if isDemo {
            clearReading(message: value ? "等待新的演示数据…" : "手机演示已暂停，返回 App 后继续。")
        } else {
            // Keep the subscription and fresh classification across lock/unlock.
            // Expire a gap on return, without crediting any time without new frames.
            let instant = clock()
            refreshDay(at: instant)
            expireReading(at: instant.uptime)
            persistHistory(at: instant, force: true)
        }
    }

    func resetSession() {
        clearReading(message: "等待测距数据…")
        standingSeconds = 0
        sittingSeconds = 0
        history = []
    }

    private func clearReading(message: String) {
        let instant = clock()
        refreshDay(at: instant)
        classifier.reset()
        lastMeasurement = nil
        sequence = FrameSequence()
        posture = .unknown
        distanceMM = nil
        simulatedFirmware = false
        lastFrameWasSimulated = nil
        sawFrame = false
        sampleMessage = message
        persistHistory(at: instant, force: true)
    }

    private func refreshDay(at instant: MonitoringInstant) {
        todayDate = instant.date
        if dailyHistory.ensureDay(on: instant.date, calendar: calendar) { historyDirty = true }
        persistHistory(at: instant)
    }

    private func persistHistory(at instant: MonitoringInstant, force: Bool = false) {
        guard historyDirty, force || instant.uptime - lastHistorySave >= 1,
              let data = try? JSONEncoder().encode(dailyHistory) else { return }
        historyStorage.save(data)
        lastHistorySave = instant.uptime
        historyDirty = false
    }

    func tick() {
        guard active else { return }
        let instant = clock()
        let now = instant.uptime
        refreshDay(at: instant)
        history.removeAll { now - $0.time > 60 }
        if isDemo {
            demoSequence &+= 1
            let ripple = sin(now * 2) * 1.5
            let mm = UInt16(min(4000, max(40, demoCentimeters * 10 + ripple)))
            receive(DistanceFrame.encode(sequence: demoSequence,
                                         uptime: UInt32(truncatingIfNeeded: Int((now - demoStarted) * 1000)),
                                         distance: demoSensorValid ? mm : nil, simulated: true))
        }
        expireReading(at: now)
    }

    private func expireReading(at now: TimeInterval) {
        classifier.expire(at: now)
        posture = classifier.posture
        distanceMM = classifier.filteredMM
        if distanceMM == nil, sawFrame, !isDemo {
            // Invalid packets already carry a more specific explanation.
            if sampleMessage.hasPrefix("实时") || sampleMessage.hasPrefix("开发板模拟") {
                sampleMessage = "超过 2 秒未收到有效测距，识别已暂停。"
            }
        }
    }

    private func receive(_ data: Data) {
        guard !isDemo || active else { return }
        guard isDemo || deviceIsReady() else {
            clearReading(message: "设备未连接，识别已暂停。")
            return
        }
        let instant = clock()
        let now = instant.uptime
        refreshDay(at: instant)
        do {
            let frame = try DistanceFrame(data: data)
            if let previous = lastMeasurement, now - previous.receivedAt > PostureClassifier.staleAfter {
                sequence = FrameSequence()
            }
            guard sequence.accept(frame.sequence) else { return }
            let sourceChanged = lastFrameWasSimulated != frame.isSimulated
            let previousPosture = classifier.posture
            let interval = lastMeasurement.flatMap {
                MeasurementContinuity.interval(previousUptime: $0.deviceUptime, uptime: frame.uptimeMilliseconds,
                                               previousReceipt: $0.receivedAt, receipt: now)
            }
            if sourceChanged || interval == nil { classifier.reset() }
            lastFrameWasSimulated = frame.isSimulated
            sawFrame = true
            simulatedFirmware = frame.isSimulated && !isDemo
            classifier.ingest(mm: frame.isValid ? Double(frame.distanceMillimeters) : nil, at: now, settings: settings)
            posture = classifier.posture
            distanceMM = classifier.filteredMM
            lastMeasurement = (now, frame.uptimeMilliseconds)
            // Credit only an interval confirmed by consecutive valid measurements.
            // Timers, lock/unlock, reconnects and relaunches never backfill time.
            if !sourceChanged, let interval, previousPosture == posture, posture != .unknown {
                let duration = min(interval, max(0, now - statisticsSettingsChangedAt))
                let counted = lunchBreak.countedSeconds(from: instant.date.addingTimeInterval(-duration),
                                                       to: instant.date, calendar: calendar)
                if posture == .standing { standingSeconds += counted }
                if posture == .sitting { sittingSeconds += counted }
                if dailyHistory.credit(seconds: duration, endingAt: instant.date, posture: posture,
                                       connected: deviceIsReady(), simulated: isDemo || frame.isSimulated,
                                       lunchBreak: lunchBreak,
                                       calendar: calendar) { historyDirty = true }
            }
            if frame.isValid {
                history.append(DistancePoint(time: now, centimeters: Double(frame.distanceMillimeters) / 10))
                history.removeAll { now - $0.time > 60 }
                if history.count > 240 { history.removeFirst(history.count - 240) }
                sampleMessage = isDemo ? "手机演示数据 · 未使用蓝牙或传感器。" :
                    (frame.isSimulated ? "开发板模拟数据 · 当前未使用真实传感器。" : "实时测距 · 根据升降台高度推断办公姿态。")
            } else {
                sampleMessage = "测距无效（状态 \(frame.sensorStatus)），请检查传感器、接线与反射面。"
            }
        } catch {
            classifier.reset()
            lastMeasurement = nil
            posture = .unknown
            distanceMM = nil
            sampleMessage = "测距协议不匹配或数据损坏，请检查开发板固件版本。"
        }
        // A BLE wake can be the last opportunity to save before iOS suspends us.
        persistHistory(at: instant, force: !active)
    }

    func calibrate(standing: Bool) {
        classifier.expire(at: clock().uptime)
        guard let mm = classifier.filteredMM else {
            calibrationMessage = "请先连接设备或开启演示，等待有效测距后再记录高度。"
            return
        }
        var next = settings
        if standing { next.standingCalibrationMM = mm } else { next.seatedCalibrationMM = mm }
        if let seated = next.seatedCalibrationMM, let upright = next.standingCalibrationMM {
            guard abs(upright - seated) >= 40 else {
                calibrationMessage = "两次高度至少需要相差 4 cm，请调整升降台后重新记录。"
                return
            }
            next.thresholdMM = (seated + upright) / 2
            next.standingIsFarther = upright > seated
            next.hysteresisMM = min(20, abs(upright - seated) / 4)
            calibrationMessage = String(format: "校准完成，分界距离为 %.1f cm。", next.thresholdMM / 10)
        } else {
            calibrationMessage = standing ? "已记录站姿高度，请再记录坐姿高度。" : "已记录坐姿高度，请再记录站姿高度。"
        }
        settings = next.validated()
    }
}
