import CoreBluetooth
import Foundation
import Combine
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
    var onFrame: ((Data) -> Void)?
    var onDisconnect: (() -> Void)?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var pendingScan = false
    private var showAll = false
    private var scanTimeout: DispatchWorkItem?
    private var connectTimeout: DispatchWorkItem?
    private var restoringPeripheral = false
    private let service = CBUUID(string: DistanceFrame.serviceUUID)
    private let measurement = CBUUID(string: DistanceFrame.measurementUUID)
    private let info = CBUUID(string: DistanceFrame.infoUUID)

    var canScan: Bool { central == nil || central?.state == .poweredOn }
    var hasConnection: Bool { peripheral != nil }

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
        guard peripheral == nil else { return }
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
        guard let central, central.state == .poweredOn, peripheral == nil, device.isCompatible else { return }
        stopScan()
        errorMessage = nil
        firmwareInfo = nil
        peripheral = device.peripheral
        peripheral?.delegate = self
        connectedName = device.name
        isConnecting = true
        connectionText = "正在连接…"
        central.connect(device.peripheral, options: nil)
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, !self.isReady else { return }
            self.fail("连接或订阅超时，请靠近设备后重试。")
        }
        connectTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: timeout)
    }

    func disconnect() {
        stopScan()
        connectTimeout?.cancel()
        let old = peripheral
        clearConnection()
        if let old { central?.cancelPeripheralConnection(old) }
    }

    private func clearConnection() {
        restoringPeripheral = false
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
            if restoringPeripheral { resumeRestoredConnection() }
            else if pendingScan { beginScan() }
        } else if central.state == .poweredOff || central.state == .unauthorized || central.state == .unsupported {
            stopScan()
            clearConnection()
        } else if central.state == .resetting {
            stopScan()
            isReady = false
            onDisconnect?()
            restoringPeripheral = peripheral != nil
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        // Scans are user initiated and foreground only. Restore the single monitored
        // peripheral, its delegate and notification subscription, never a broad scan.
        pendingScan = false
        restoringPeripheral = true
        guard let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first else {
            if central.state == .poweredOn { resumeRestoredConnection() }
            return
        }
        peripheral = restored
        restored.delegate = self
        connectedName = restored.name ?? "StandUp"
        isConnecting = true
        isReady = false
        connectionText = "正在恢复设备监测…"
        if central.state == .poweredOn { resumeRestoredConnection() }
    }

    private func resumeRestoredConnection() {
        guard let central, central.state == .poweredOn else { return }
        stopScan()
        restoringPeripheral = false
        guard let peripheral else { return }
        switch peripheral.state {
        case .connected: resumeSubscription(peripheral)
        case .connecting: connectionText = "等待设备重新连接…"
        case .disconnected: central.connect(peripheral, options: nil)
        case .disconnecting: break // didDisconnect will issue the pending reconnect.
        @unknown default: break
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
        peripheral.delegate = self
        peripheral.discoverServices([service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        fail("连接失败：\(error?.localizedDescription ?? "设备未响应")。请重试。")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        isReady = false
        isConnecting = true
        firmwareInfo = nil
        connectTimeout?.cancel()
        connectTimeout = nil
        connectionText = "连接中断 · 等待设备重新连接…"
        errorMessage = error.map { "连接中断：\($0.localizedDescription)。正在等待重连。" }
        onDisconnect?()
        // CoreBluetooth keeps a pending connection without a polling timer. An
        // explicit disconnect clears `peripheral` first and never reaches here.
        if central.state == .poweredOn { central.connect(peripheral, options: nil) }
        else { restoringPeripheral = true }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        guard error == nil, let found = peripheral.services?.first(where: { $0.uuid == service }) else {
            fail("未找到 StandUp 测距服务，请检查开发板固件。")
            return
        }
        peripheral.discoverCharacteristics([measurement, info], for: found)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier, service.uuid == self.service else { return }
        guard error == nil, let characteristic = service.characteristics?.first(where: { $0.uuid == measurement }),
              characteristic.properties.contains(.notify) else {
            fail("测距特征不可用，请更新开发板固件。")
            return
        }
        peripheral.setNotifyValue(true, for: characteristic)
        readInfo(peripheral, service: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier, characteristic.uuid == measurement else { return }
        guard error == nil, characteristic.isNotifying else {
            fail("订阅测距数据失败，请重新连接。")
            return
        }
        markReady()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        if characteristic.uuid == info, error == nil, let value = characteristic.value {
            firmwareInfo = String(data: value, encoding: .utf8)
        } else if characteristic.uuid == measurement, isReady {
            guard error == nil, let value = characteristic.value else {
                fail("读取测距数据失败，请重新连接。")
                return
            }
            onFrame?(value)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        if invalidatedServices.contains(where: { $0.uuid == service }) {
            fail("设备服务已更新，请重新连接。")
        }
    }
}
