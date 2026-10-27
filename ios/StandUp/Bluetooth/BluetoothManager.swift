import CoreBluetooth
import Foundation
import Combine
import OSLog
#if SWIFT_PACKAGE
import StandUpCore
#endif

struct DiscoveredDevice: Identifiable {
    let peripheral: CBPeripheral
    var name: String
    var rssi: Int
    var isCompatible: Bool
    var id: UUID { peripheral.identifier }
}

/// CoreBluetooth delegates and observable state share the main queue.
final class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let restorationIdentifier = "com.l33klin.StandUp.central"
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var stateText = "尚未启用蓝牙"
    @Published private(set) var connectionText = "未连接设备"
    @Published private(set) var connectedName: String?
    @Published private(set) var isReady = false
    @Published private(set) var isConnecting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var firmwareInfo: String?
    @Published private(set) var lastMeasurementAt: Date?
    var onFrame: ((Data) -> Void)?
    var onDisconnect: (() -> Void)?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var pendingScan = false
    private var showAll = false
    private var scanTimeout: DispatchWorkItem?
    private var connectTimeout: DispatchWorkItem?
    private var restoringPeripheral = false
    private var systemIsReconnecting = false
    private var monitoring: BluetoothMonitoringPreference
    private var retryGate = BluetoothRetryGate()
    private let defaults: UserDefaults?
    private let logger = Logger(subsystem: "com.l33klin.StandUp", category: "Bluetooth")
    private let service = CBUUID(string: DistanceFrame.serviceUUID)
    private let measurement = CBUUID(string: DistanceFrame.measurementUUID)
    private let info = CBUUID(string: DistanceFrame.infoUUID)

    var canScan: Bool { central == nil || central?.state == .poweredOn }
    var hasConnection: Bool { peripheral != nil || monitoring.deviceID != nil }

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        monitoring = BluetoothMonitoringPreference.restore(from: defaults?.data(forKey: "bluetooth.monitoring.v1"))
        super.init()
        if monitoring.deviceID != nil {
            connectedName = monitoring.name
            isConnecting = true
            connectionText = "等待恢复设备监测…"
        }
    }

    private func saveMonitoring() {
        if let data = try? JSONEncoder().encode(monitoring) { defaults?.set(data, forKey: "bluetooth.monitoring.v1") }
    }

    /// Also called on a normal launch/foreground return when there is no restoration payload.
    func resumeMonitoring() {
        guard monitoring.deviceID != nil else { return }
        retryGate.reset()
        if central == nil { initializeCentral() }
        else { resumeMonitoredConnection() }
    }

    func restoreIfNeeded(identifiers: [String]) {
        guard identifiers.contains(Self.restorationIdentifier) else { return }
        initializeCentral()
    }

    private func initializeCentral() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restorationIdentifier])
    }

    func scan(allDevices: Bool) {
        guard !hasConnection else { return }
        errorMessage = nil
        showAll = allDevices
        pendingScan = true
        if central == nil { initializeCentral() }
        else if central?.state == .poweredOn { beginScan() }
        else { pendingScan = false; errorMessage = stateText }
    }

    private func beginScan() {
        guard let central, central.state == .poweredOn else { return }
        stopScan()
        pendingScan = false
        devices = []
        central.scanForPeripherals(withServices: showAll ? nil : [service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
        let timeout = DispatchWorkItem { [weak self] in self?.stopScan() }
        scanTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
    }

    func stopScan() {
        pendingScan = false
        scanTimeout?.cancel()
        scanTimeout = nil
        central?.stopScan()
        isScanning = false
    }

    func connect(_ device: DiscoveredDevice) {
        guard let central, central.state == .poweredOn, !hasConnection, device.isCompatible else { return }
        stopScan()
        errorMessage = nil
        firmwareInfo = nil
        lastMeasurementAt = nil
        peripheral = device.peripheral
        peripheral?.delegate = self
        connectedName = device.name
        monitoring.select(id: device.id, name: device.name)
        retryGate.reset()
        saveMonitoring()
        isConnecting = true
        connectionText = "正在连接…"
        requestConnection(device.peripheral)
        // Connection requests stay pending while out of range. Only an already
        // established link gets a deadline for discovery/subscription.
    }

    private func requestConnection(_ peripheral: CBPeripheral) {
        guard let central, central.state == .poweredOn else { return }
        logger.notice("Submitting pending connection with system auto-reconnect")
        if #available(iOS 17.0, macOS 14.0, *) {
            central.connect(peripheral, options: [CBConnectPeripheralOptionEnableAutoReconnect: true])
        } else { central.connect(peripheral, options: nil) }
    }

    private func startSubscriptionDeadline() {
        connectTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, !self.isReady, self.peripheral?.state == .connected else { return }
            self.recoverConnection("服务发现或订阅超时，正在重新连接。")
        }
        connectTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: timeout)
    }

    func disconnect() {
        monitoring.stop()
        saveMonitoring()
        logger.notice("Monitoring explicitly stopped; pending reconnect cancelled")
        stopScan()
        connectTimeout?.cancel()
        let old = peripheral
        clearConnection()
        if let old { central?.cancelPeripheralConnection(old) }
    }

    private func clearConnection() {
        restoringPeripheral = false
        systemIsReconnecting = false
        peripheral?.delegate = nil
        peripheral = nil
        connectTimeout?.cancel()
        connectTimeout = nil
        connectedName = nil
        isConnecting = false
        isReady = false
        firmwareInfo = nil
        connectionText = "未连接设备"
        onDisconnect?()
    }

    private func fail(_ message: String) { errorMessage = message; disconnect() }

    private func recoverConnection(_ message: String) {
        errorMessage = message
        isReady = false
        isConnecting = true
        firmwareInfo = nil
        connectTimeout?.cancel()
        connectTimeout = nil
        connectionText = "等待重新连接并恢复测距…"
        onDisconnect?()
        logger.notice("Recovering transport/subscription without clearing monitoring intent")
        guard let peripheral, let central, central.state == .poweredOn else { return }
        if peripheral.state == .connected { central.cancelPeripheralConnection(peripheral) }
        else { resumeMonitoredConnection() }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: stateText = "蓝牙已开启"
        case .poweredOff: stateText = "蓝牙已关闭，请在系统设置中开启。"
        case .unauthorized: stateText = "蓝牙权限未授权，请前往系统设置允许 StandUp 使用蓝牙。"
        case .unsupported: stateText = "当前设备不支持蓝牙，请在 iPhone 真机测试。"
        case .resetting: stateText = "蓝牙正在重置，请稍后重试。"
        case .unknown: stateText = "正在初始化蓝牙…"
        @unknown default: stateText = "蓝牙暂不可用"
        }
        if central.state == .poweredOn {
            if restoringPeripheral || monitoring.deviceID != nil { resumeMonitoredConnection() }
            else if pendingScan { beginScan() }
        } else if central.state == .poweredOff || central.state == .unauthorized || central.state == .unsupported {
            stopScan()
            clearConnection()
            if monitoring.deviceID != nil {
                connectedName = monitoring.name
                isConnecting = true
                connectionText = "蓝牙暂不可用 · 保留设备监测，等待恢复…"
            }
        } else if central.state == .resetting {
            stopScan()
            // Resetting invalidates CBPeripheral objects; retrieve a fresh object when powered on.
            clearConnection()
            restoringPeripheral = monitoring.deviceID != nil
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        // Scans are user initiated and foreground only. Restore the single monitored
        // peripheral, its delegate and notification subscription, never a broad scan.
        pendingScan = false
        restoringPeripheral = true
        let restoredPeripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        guard let restored = restoredPeripherals.first(where: { monitoring.acceptsRestoredDevice($0.identifier) }) else {
            for old in restoredPeripherals { central.cancelPeripheralConnection(old) }
            if central.state == .poweredOn { resumeMonitoredConnection() }
            return
        }
        monitoring.select(id: restored.identifier, name: restored.name ?? monitoring.name ?? "StandUp")
        saveMonitoring()
        peripheral = restored
        restored.delegate = self
        connectedName = restored.name ?? "StandUp"
        isConnecting = true
        isReady = false
        connectionText = "正在恢复设备监测…"
        logger.notice("Restored peripheral and delegate from CoreBluetooth")
        if central.state == .poweredOn { resumeMonitoredConnection() }
    }

    private func resumeMonitoredConnection() {
        guard let central, central.state == .poweredOn else { return }
        guard monitoring.deviceID != nil else { restoringPeripheral = false; return }
        stopScan()
        restoringPeripheral = false
        if peripheral == nil, let id = monitoring.deviceID {
            peripheral = central.retrievePeripherals(withIdentifiers: [id]).first
            peripheral?.delegate = self
        }
        guard let peripheral else {
            connectionText = "未能恢复设备信息，请断开后重新扫描。"
            return
        }
        switch monitoring.recoveryAction(poweredOn: true, state: peripheral.state, systemIsReconnecting: systemIsReconnecting) {
        case .subscribe:
            if !isReady { startSubscriptionDeadline(); resumeSubscription(peripheral) }
        case .connect:
            isConnecting = true
            connectedName = monitoring.name
            connectionText = "等待设备回到范围，自动恢复监测…"
            requestConnection(peripheral)
        case .wait: connectionText = "等待系统重新连接设备…"
        case .none, .retrieve: break
        }
    }

    private func resumeSubscription(_ peripheral: CBPeripheral) {
        if let found = peripheral.services?.first(where: { $0.uuid == service }) {
            if let characteristic = found.characteristics?.first(where: { $0.uuid == measurement }),
               characteristic.properties.contains(.notify) {
                if characteristic.isNotifying { markReady() }
                else { peripheral.setNotifyValue(true, for: characteristic) }
                readInfo(peripheral, service: found)
            } else {
                peripheral.discoverCharacteristics([measurement, info], for: found)
            }
        } else {
            peripheral.discoverServices([service])
        }
    }

    private func markReady() {
        connectTimeout?.cancel()
        connectTimeout = nil
        isReady = true
        isConnecting = false
        errorMessage = nil
        connectionText = "已连接 · 接收测距中"
        logger.notice("Measurement subscription ready; recording can resume on fresh data")
    }

    private func readInfo(_ peripheral: CBPeripheral, service: CBService) {
        if let characteristic = service.characteristics?.first(where: { $0.uuid == info }),
           characteristic.properties.contains(.read) { peripheral.readValue(for: characteristic) }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard isScanning else { return }
        let advertised = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            + (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? [])
        let compatible = advertised.contains(service)
        let device = DiscoveredDevice(peripheral: peripheral,
                                      name: advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "未命名 BLE 设备",
                                      rssi: RSSI.intValue, isCompatible: compatible)
        if let index = devices.firstIndex(where: { $0.id == device.id }) { devices[index] = device }
        else { devices.append(device) }
        devices.sort { lhs, rhs in
            lhs.isCompatible != rhs.isCompatible ? lhs.isCompatible : lhs.rssi > rhs.rssi
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        connectionText = "正在发现测距服务…"
        systemIsReconnecting = false
        retryGate.reset()
        isReady = false
        isConnecting = true
        peripheral.delegate = self
        logger.notice("Peripheral connected; rediscovering measurement service")
        startSubscriptionDeadline()
        peripheral.discoverServices([service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        logger.error("Connection attempt failed; retaining selected device")
        if let error = error as? CBError, [.invalidParameters, .uuidNotAllowed, .operationNotSupported, .unknownDevice].contains(error.code) {
            fail("设备无法连接：\(error.localizedDescription)。请重新扫描。")
            return
        }
        if let error = error as? CBError, [.connectionLimitReached, .tooManyLEPairedDevices].contains(error.code) {
            // A resource limit cannot be fixed by an immediate retry loop. Keep
            // the selection and retry when the app next comes to the foreground.
            systemIsReconnecting = false
            isReady = false
            isConnecting = false
            connectionText = "系统蓝牙连接受限 · 请返回 App 重试"
            errorMessage = error.localizedDescription
            onDisconnect?()
            return
        }
        systemIsReconnecting = false
        guard retryGate.retryAfterFailure(at: ProcessInfo.processInfo.systemUptime) else {
            isReady = false
            isConnecting = false
            connectionText = "连续连接失败 · 请在 App 中恢复监测"
            errorMessage = error?.localizedDescription
            onDisconnect?()
            return
        }
        recoverConnection("连接失败：\(error?.localizedDescription ?? "设备未响应")。正在等待重连。")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        handleDisconnection(central, peripheral: peripheral, isReconnecting: false, error: error)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        timestamp: CFAbsoluteTime, isReconnecting: Bool, error: Error?) {
        handleDisconnection(central, peripheral: peripheral, isReconnecting: isReconnecting, error: error)
    }

    private func handleDisconnection(_ central: CBCentralManager, peripheral: CBPeripheral, isReconnecting: Bool, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        systemIsReconnecting = isReconnecting
        isReady = false
        isConnecting = true
        firmwareInfo = nil
        connectTimeout?.cancel()
        connectTimeout = nil
        connectionText = "连接中断 · 等待设备重新连接…"
        errorMessage = error.map { "连接中断：\($0.localizedDescription)。正在等待重连。" }
        onDisconnect?()
        logger.notice("Link lost; system auto-reconnect pending: \(isReconnecting)")
        // Do not cancel/reissue a request that iOS already owns. The explicit-stop
        // path clears the peripheral and saved intent before a callback can arrive.
        if central.state == .poweredOn { resumeMonitoredConnection() }
        else { restoringPeripheral = true }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        guard peripheral.state == .connected else { return }
        if error != nil { recoverConnection("发现测距服务失败，正在重连。"); return }
        guard let found = peripheral.services?.first(where: { $0.uuid == service }) else {
            fail("未找到 StandUp 测距服务，请检查开发板固件。")
            return
        }
        peripheral.discoverCharacteristics([measurement, info], for: found)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier, service.uuid == self.service else { return }
        guard peripheral.state == .connected else { return }
        if error != nil { recoverConnection("发现测距特征失败，正在重连。"); return }
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == measurement }),
              characteristic.properties.contains(.notify) else {
            fail("测距特征不可用，请更新开发板固件。")
            return
        }
        peripheral.setNotifyValue(true, for: characteristic)
        readInfo(peripheral, service: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier, characteristic.uuid == measurement else { return }
        guard peripheral.state == .connected else { return }
        guard error == nil, characteristic.isNotifying else {
            recoverConnection("订阅测距数据失败，正在重连。")
            return
        }
        markReady()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        guard peripheral.state == .connected else { return }
        if characteristic.uuid == info, error == nil, let value = characteristic.value {
            firmwareInfo = String(data: value, encoding: .utf8)
        } else if characteristic.uuid == measurement, isReady {
            guard error == nil, let value = characteristic.value else {
                recoverConnection("读取测距数据失败，正在重连。")
                return
            }
            lastMeasurementAt = Date()
            onFrame?(value)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        if invalidatedServices.contains(where: { $0.uuid == service }) {
            isReady = false
            isConnecting = true
            connectionText = "设备服务更新 · 正在恢复订阅…"
            onDisconnect?()
            startSubscriptionDeadline()
            peripheral.discoverServices([self.service])
        }
    }
}
