import SwiftUI
import UIKit

struct DevicesView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View { DeviceList(model: model, bluetooth: model.bluetooth) }
}

private struct DeviceList: View {
    @ObservedObject var model: AppModel
    @ObservedObject var bluetooth: BluetoothManager
    @State private var showAll = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(bluetooth.stateText, systemImage: "antenna.radiowaves.left.and.right")
                    if model.isDemo { Label("当前正在演示，开始扫描将结束演示。", systemImage: "play.circle").font(.subheadline) }
                    Toggle("显示所有 BLE 设备", isOn: $showAll).disabled(bluetooth.hasConnection)
                        .onChange(of: showAll) { _, value in if bluetooth.isScanning { bluetooth.scan(allDevices: value) } }
                    Button {
                        model.prepareRealMode()
                        if bluetooth.isScanning { bluetooth.stopScan() } else { bluetooth.scan(allDevices: showAll) }
                    } label: {
                        HStack {
                            Text(bluetooth.isScanning ? "停止扫描" : "扫描蓝牙设备")
                            Spacer()
                            if bluetooth.isScanning { ProgressView() } else { Image(systemName: "magnifyingglass") }
                        }.frame(minHeight: 28)
                    }.disabled(bluetooth.hasConnection || (!bluetooth.canScan && !bluetooth.isScanning))
                } footer: {
                    Text("每次扫描持续 15 秒。默认只显示 StandUp 设备；开启全部设备可在开发板到货前测试蓝牙扫描。")
                }

                if bluetooth.hasConnection {
                    Section("当前设备") {
                        Label(bluetooth.connectedName ?? "StandUp", systemImage: "cpu")
                        HStack {
                            Text(bluetooth.connectionText).font(.subheadline)
                            if bluetooth.isConnecting { Spacer(); ProgressView() }
                        }
                        if let info = bluetooth.firmwareInfo { LabeledContent("固件", value: info).font(.caption) }
                        Button("断开连接", role: .destructive) { bluetooth.disconnect() }
                    }
                }

                if let error = bluetooth.errorMessage {
                    Section("连接提示") { Label(error, systemImage: "exclamationmark.triangle").font(.subheadline) }
                }

                Section("附近设备（\(bluetooth.devices.count)）") {
                    if bluetooth.devices.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(bluetooth.isScanning ? "正在寻找附近设备…" : "尚未发现设备").font(.headline)
                            Text("请让设备通电并保持广播。蓝牙设备不会全部持续广播，手机也可能不会出现在列表中。")
                                .font(.subheadline).foregroundStyle(Theme.muted)
                        }.padding(.vertical, 8)
                    }
                    ForEach(bluetooth.devices) { device in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                Label(device.name, systemImage: device.isCompatible ? "cpu" : "wave.3.right")
                                    .font(.headline)
                                Spacer()
                                Text(device.rssi == 127 ? "RSSI 未知" : "\(device.rssi) dBm")
                                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                            }
                            Text(device.id.uuidString).font(.caption2.monospaced()).foregroundStyle(Theme.muted)
                            if device.isCompatible {
                                Button("连接此设备") { model.connect(device) }
                                    .buttonStyle(.bordered).disabled(bluetooth.hasConnection)
                            } else {
                                Text("未广播 StandUp 服务，仅供扫描测试。")
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                        }.padding(.vertical, 6)
                    }
                }

                Section {
                    Button("打开 App 系统设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } footer: { Text("蓝牙权限被拒绝时，在系统设置中允许访问。连接应从此 App 发起。") }
            }
            .scrollContentBackground(.hidden).background(Theme.paper)
            .navigationTitle("蓝牙设备")
            .onDisappear { bluetooth.stopScan() }
        }
    }
}
