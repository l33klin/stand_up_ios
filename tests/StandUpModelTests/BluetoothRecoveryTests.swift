import CoreBluetooth
import XCTest
@testable import StandUpModel

final class BluetoothRecoveryTests: XCTestCase {
    func testRapidPersistentFailuresStopSpinningButForegroundRetryCanResume() {
        var gate = BluetoothRetryGate()
        XCTAssertTrue(gate.retryAfterFailure(at: 100))
        XCTAssertTrue(gate.retryAfterFailure(at: 100.1))
        XCTAssertFalse(gate.retryAfterFailure(at: 100.2))
        gate.reset() // User/foreground recovery starts a fresh attempt.
        XCTAssertTrue(gate.retryAfterFailure(at: 100.3))
        XCTAssertTrue(gate.retryAfterFailure(at: 110))
    }

    func testSavedSelectionSurvivesRelaunchAndRequestsConnectionWithoutScanning() throws {
        let id = UUID()
        var selection = BluetoothMonitoringPreference()
        selection.select(id: id, name: "StandUp-test")
        let restored = BluetoothMonitoringPreference.restore(from: try JSONEncoder().encode(selection))
        XCTAssertEqual(restored.deviceID, id)
        XCTAssertEqual(restored.name, "StandUp-test")
        XCTAssertEqual(restored.recoveryAction(poweredOn: true, state: nil, systemIsReconnecting: false), .retrieve)
        XCTAssertEqual(restored.recoveryAction(poweredOn: true, state: .disconnected, systemIsReconnecting: false), .connect)
    }

    func testSystemReconnectRemainsPendingAndResubscribesAfterConnection() {
        var selection = BluetoothMonitoringPreference()
        selection.select(id: UUID(), name: "StandUp-test")
        // A disconnect callback may arrive before CBPeripheral.state changes.
        XCTAssertEqual(selection.recoveryAction(poweredOn: true, state: .disconnected, systemIsReconnecting: true), .wait)
        XCTAssertEqual(selection.recoveryAction(poweredOn: true, state: .connected, systemIsReconnecting: true), .wait)
        XCTAssertEqual(selection.recoveryAction(poweredOn: true, state: .connecting, systemIsReconnecting: false), .wait)
        XCTAssertEqual(selection.recoveryAction(poweredOn: true, state: .disconnecting, systemIsReconnecting: false), .wait)
        XCTAssertEqual(selection.recoveryAction(poweredOn: true, state: .connected, systemIsReconnecting: false), .subscribe)
    }

    func testBluetoothPowerCycleRetainsSelectionForNextPoweredOnEvent() {
        let id = UUID()
        var selection = BluetoothMonitoringPreference()
        selection.select(id: id, name: "StandUp-test")
        XCTAssertEqual(selection.recoveryAction(poweredOn: false, state: .disconnected, systemIsReconnecting: false), .none)
        XCTAssertEqual(selection.deviceID, id)
        XCTAssertEqual(selection.recoveryAction(poweredOn: true, state: .disconnected, systemIsReconnecting: false), .connect)
    }

    func testExplicitStopPersistsAndRejectsLateRestoration() throws {
        let id = UUID()
        var selection = BluetoothMonitoringPreference()
        selection.select(id: id, name: "StandUp-test")
        selection.stop()
        let restored = BluetoothMonitoringPreference.restore(from: try JSONEncoder().encode(selection))
        XCTAssertTrue(restored.userStopped)
        XCTAssertNil(restored.deviceID)
        XCTAssertFalse(restored.acceptsRestoredDevice(id))
        XCTAssertEqual(restored.recoveryAction(poweredOn: true, state: .disconnected, systemIsReconnecting: true), .none)
    }

    func testRestorationAdoptsLegacyDeviceButNeverSwitchesSelectedDevice() {
        let id = UUID()
        var selection = BluetoothMonitoringPreference.restore(from: nil)
        XCTAssertTrue(selection.acceptsRestoredDevice(id)) // Upgrade from the old restoration-only app.
        selection.select(id: id, name: "StandUp-test")
        XCTAssertTrue(selection.acceptsRestoredDevice(id))
        XCTAssertFalse(selection.acceptsRestoredDevice(UUID()))
        XCTAssertEqual(BluetoothMonitoringPreference.restore(from: Data("invalid".utf8)), BluetoothMonitoringPreference())
    }

    func testManagerLoadsSavedIntentAndExplicitStopClearsItWithoutCreatingBluetooth() throws {
        let suite = "StandUpBluetoothTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var selection = BluetoothMonitoringPreference()
        selection.select(id: UUID(), name: "StandUp-test")
        defaults.set(try JSONEncoder().encode(selection), forKey: "bluetooth.monitoring.v1")
        let manager = BluetoothManager(defaults: defaults)
        XCTAssertTrue(manager.hasConnection)
        XCTAssertTrue(manager.isConnecting)
        XCTAssertEqual(manager.connectedName, "StandUp-test")
        XCTAssertFalse(manager.isReady)
        var stopped = false
        manager.onDisconnect = { stopped = true }
        manager.disconnect()
        XCTAssertTrue(stopped)
        XCTAssertFalse(manager.hasConnection)
        XCTAssertFalse(manager.isConnecting)
        let restored = BluetoothMonitoringPreference.restore(from: defaults.data(forKey: "bluetooth.monitoring.v1"))
        XCTAssertTrue(restored.userStopped)
        XCTAssertNil(restored.deviceID)
        manager.resumeMonitoring() // A manual stop must not initialize CBCentralManager/request permission.
        let relaunched = BluetoothManager(defaults: defaults)
        XCTAssertFalse(relaunched.hasConnection)
        XCTAssertFalse(relaunched.isReady)
    }
}
