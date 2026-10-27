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
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionGap) {
                    if bluetooth.hasConnection { connectedDevice }
                    else { discovery }
                    if let error = bluetooth.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.subheadline).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true)
                    }
                    if !bluetooth.hasConnection {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeading(title: "附近设备", detail: "\(bluetooth.devices.count) 台")
                            if bluetooth.devices.isEmpty {
                                EmptyReading(symbol: "dot.radiowaves.left.and.right",
                                             title: bluetooth.isScanning ? "正在搜索附近设备" : "暂未发现设备",
                                             detail: bluetooth.isScanning ? "请保持开发板通电并靠近手机" : "开始扫描，查找 StandUp 开发板")
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(Array(bluetooth.devices.enumerated()), id: \.element.id) { index, device in
                                        if index > 0 { Divider().padding(.leading, 16) }
                                        if device.isCompatible {
                                            Button { model.connect(device) } label: { deviceRow(device) }
                                                .buttonStyle(.plain)
                                        } else {
                                            deviceRow(device)
                                        }
                                    }
                                }.surface(padding: 0)
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text(bluetooth.stateText).fixedSize(horizontal: false, vertical: true)
                    }.font(.caption).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, Theme.pageInset).padding(.top, 16).padding(.bottom, 28)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .appPage().navigationTitle("设备")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: { Image(systemName: "gearshape").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("打开 App 系统设置")
                }
            }
            .onDisappear { bluetooth.stopScan() }
        }
    }

    private var discovery: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "sensor.tag.radiowaves.forward")
                .font(.system(size: 32, weight: .regular)).foregroundStyle(Theme.accent)
                .frame(width: 64, height: 64)
                .background(Theme.subtle, in: RoundedRectangle(cornerRadius: Theme.radius))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("连接你的升降台").font(.title2.weight(.semibold))
                Text("开发板通电后，扫描并选择设备。")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                if model.isDemo {
                    Label("扫描将结束手机演示", systemImage: "play.circle").font(.caption).foregroundStyle(Theme.accent)
                }
            }
            Button {
                model.prepareRealMode()
                if bluetooth.isScanning { bluetooth.stopScan() } else { bluetooth.scan(allDevices: showAll) }
            } label: {
                HStack(spacing: 8) {
                    if bluetooth.isScanning { ProgressView().tint(Theme.onAccent) }
                    Text(bluetooth.isScanning ? "停止扫描" : "扫描附近设备")
                }
            }.buttonStyle(PrimaryButtonStyle()).disabled(!bluetooth.canScan && !bluetooth.isScanning)
            Toggle("包括其他蓝牙设备", isOn: $showAll)
                .font(.subheadline)
                .onChange(of: showAll) { _, value in if bluetooth.isScanning { bluetooth.scan(allDevices: value) } }
            Text("扫描持续 15 秒，仅 StandUp 设备支持连接。")
                .font(.caption).foregroundStyle(Theme.muted)
        }
    }

    private var connectedDevice: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Image(systemName: "cpu").font(.title).foregroundStyle(Theme.accent)
                    .frame(width: 56, height: 56).background(Theme.subtle, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 6) {
                    Text(bluetooth.connectedName ?? "StandUp").font(.headline)
                    Text(bluetooth.connectionText).font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                if bluetooth.isConnecting { ProgressView() }
                else if bluetooth.isReady { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.stand) }
                else { Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.warning) }
            }
            Label(bluetooth.isReady ? "锁屏后继续监测" : "等待设备回到范围，数据中断期间不计时", systemImage: "lock.iphone")
                .font(.subheadline).foregroundStyle(Theme.muted)
            if let received = bluetooth.lastMeasurementAt {
                LabeledContent("最近收到数据") { Text(received, style: .time).monospacedDigit() }
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            if !bluetooth.isReady {
                Button("恢复监测") { bluetooth.resumeMonitoring() }
                    .font(.subheadline).frame(minHeight: 44).disabled(!bluetooth.canScan)
            }
            if let info = bluetooth.firmwareInfo {
                DisclosureGroup("设备信息") { Text(info).font(.caption.monospaced()).foregroundStyle(Theme.muted).padding(.top, 8) }
                    .font(.subheadline)
            }
            Divider()
            Button("断开连接", role: .destructive) { bluetooth.disconnect() }
                .font(.subheadline.weight(.medium)).foregroundStyle(Theme.destructive)
                .frame(maxWidth: .infinity, minHeight: 44)
            Text("断开后停止监测与自动重连。")
                .font(.caption).foregroundStyle(Theme.muted)
        }.surface()
    }

    private func deviceRow(_ device: DiscoveredDevice) -> some View {
        HStack(spacing: 12) {
            Image(systemName: device.isCompatible ? "cpu" : "wave.3.right")
                .font(.title3).foregroundStyle(device.isCompatible ? Theme.accent : Theme.muted)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text(device.name).font(.subheadline.weight(.medium)).lineLimit(2)
                Text(device.isCompatible ? "StandUp · 轻点连接" : "其他蓝牙设备")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Image(systemName: device.isCompatible ? "plus.circle" : "wave.3.right")
                    .foregroundStyle(device.isCompatible ? Theme.accent : Theme.muted)
                Text(device.rssi == 127 ? "信号未知" : "\(device.rssi) dBm").font(.caption2.monospacedDigit()).foregroundStyle(Theme.muted)
            }
        }.padding(16).foregroundStyle(Theme.ink)
            .accessibilityElement(children: .combine)
    }
}
