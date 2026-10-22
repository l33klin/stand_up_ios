import Foundation
import Combine
#if SWIFT_PACKAGE
import StandUpCore
#endif

struct DistancePoint: Identifiable {
    let id = UUID()
    let time: TimeInterval
    let centimeters: Double
}

final class AppModel: ObservableObject {
    let bluetooth = BluetoothManager()
    @Published var settings: DetectionSettings {
        didSet {
            let validated = settings.validated()
            if settings != validated { settings = validated; return }
            if let data = try? JSONEncoder().encode(settings.validated()) { defaults?.set(data, forKey: "detection.v1") }
            classifier.reset()
            posture = .unknown
            distanceMM = nil
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
    @Published var demoCentimeters: Double = 40
    @Published var demoSensorValid = true
    @Published var calibrationMessage: String?

    private var classifier = PostureClassifier()
    private var sequence = FrameSequence()
    private var timer: Timer?
    private var subscription: AnyCancellable?
    private var lastAccounting = ProcessInfo.processInfo.systemUptime
    private var active = true
    private var demoSequence: UInt16 = 0
    private var demoStarted: TimeInterval = 0
    private var sawFrame = false
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: "detection.v1"),
           let saved = try? JSONDecoder().decode(DetectionSettings.self, from: data) { settings = saved.validated() }
        else { settings = DetectionSettings() }
        bluetooth.onFrame = { [weak self] data in self?.receive(data) }
        bluetooth.onDisconnect = { [weak self] in self?.clearReading(message: "设备未连接，识别已暂停。") }
        subscription = bluetooth.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
    }

    deinit { timer?.invalidate() }

    func startDemo() {
        bluetooth.disconnect()
        isDemo = true
        simulatedFirmware = false
        demoSensorValid = true
        demoStarted = ProcessInfo.processInfo.systemUptime
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
        account(at: ProcessInfo.processInfo.systemUptime)
        active = value
        if !value { bluetooth.stopScan() }
        clearReading(message: value ? "等待新的测距数据…" : "App 不在前台，识别与计时已暂停。")
    }

    func resetSession() {
        clearReading(message: "等待测距数据…")
        standingSeconds = 0
        sittingSeconds = 0
        history = []
    }

    private func clearReading(message: String) {
        account(at: ProcessInfo.processInfo.systemUptime)
        classifier.reset()
        sequence = FrameSequence()
        posture = .unknown
        distanceMM = nil
        simulatedFirmware = false
        sawFrame = false
        sampleMessage = message
    }

    private func account(at time: TimeInterval) {
        defer { lastAccounting = time }
        guard active, let sampleTime = classifier.lastSampleTime else { return }
        let duration = max(0, min(time, sampleTime + PostureClassifier.staleAfter) - lastAccounting)
        if classifier.posture == .standing { standingSeconds += duration }
        if classifier.posture == .sitting { sittingSeconds += duration }
    }

    private func tick() {
        guard active else { return }
        let now = ProcessInfo.processInfo.systemUptime
        account(at: now)
        history.removeAll { now - $0.time > 60 }
        if isDemo {
            demoSequence &+= 1
            let ripple = sin(now * 2) * 1.5
            let mm = UInt16(min(4000, max(40, demoCentimeters * 10 + ripple)))
            receive(DistanceFrame.encode(sequence: demoSequence,
                                         uptime: UInt32(truncatingIfNeeded: Int((now - demoStarted) * 1000)),
                                         distance: demoSensorValid ? mm : nil, simulated: true))
        }
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
        guard active else { return }
        let now = ProcessInfo.processInfo.systemUptime
        account(at: now)
        do {
            let frame = try DistanceFrame(data: data)
            guard sequence.accept(frame.sequence) else { return }
            sawFrame = true
            simulatedFirmware = frame.isSimulated && !isDemo
            classifier.ingest(mm: frame.isValid ? Double(frame.distanceMillimeters) : nil, at: now, settings: settings)
            posture = classifier.posture
            distanceMM = classifier.filteredMM
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
            posture = .unknown
            distanceMM = nil
            sampleMessage = "测距协议不匹配或数据损坏，请检查开发板固件版本。"
        }
    }

    func calibrate(standing: Bool) {
        classifier.expire(at: ProcessInfo.processInfo.systemUptime)
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
