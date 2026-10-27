import CoreBluetooth
import Foundation

/// User intent survives a lost radio link and a process relaunch.
/// An explicit stop is saved too, so a late restoration cannot restart monitoring.
struct BluetoothMonitoringPreference: Codable, Equatable {
    private(set) var deviceID: UUID?
    private(set) var name: String?
    private(set) var userStopped = false

    enum RecoveryAction: Equatable { case none, retrieve, connect, wait, subscribe }

    mutating func select(id: UUID, name: String) {
        deviceID = id
        self.name = name
        userStopped = false
    }

    mutating func stop() {
        deviceID = nil
        name = nil
        userStopped = true
    }

    func acceptsRestoredDevice(_ id: UUID) -> Bool {
        !userStopped && (deviceID == nil || deviceID == id)
    }

    func recoveryAction(poweredOn: Bool, state: CBPeripheralState?, systemIsReconnecting: Bool) -> RecoveryAction {
        guard deviceID != nil, !userStopped, poweredOn else { return .none }
        guard let state else { return .retrieve }
        if systemIsReconnecting { return .wait }
        switch state {
        case .disconnected: return .connect
        case .connecting, .disconnecting: return .wait
        case .connected: return .subscribe
        @unknown default: return .wait
        }
    }

    static func restore(from data: Data?) -> Self {
        guard let data, let saved = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        // A stop always takes precedence, including malformed saved combinations.
        if saved.userStopped { var stopped = Self(); stopped.stop(); return stopped }
        return saved
    }
}

/// Prevent a persistent stack error from creating a rapid connect/fail callback loop.
/// Ordinary out-of-range requests stay pending in CoreBluetooth and never hit this gate.
struct BluetoothRetryGate {
    private var lastFailure: TimeInterval?
    private var rapidFailures = 0

    mutating func retryAfterFailure(at uptime: TimeInterval) -> Bool {
        if let lastFailure, uptime - lastFailure < 5 { rapidFailures += 1 }
        else { rapidFailures = 1 }
        lastFailure = uptime
        return rapidFailures <= 2
    }

    mutating func reset() { lastFailure = nil; rapidFailures = 0 }
}
