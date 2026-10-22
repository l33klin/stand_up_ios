import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    let openDevices: () -> Void
    let openSettings: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Label(model.isDemo ? "手机演示" : model.bluetooth.isReady ? "设备已连接" : "设备未连接",
                              systemImage: model.isDemo ? "play.circle" : "antenna.radiowaves.left.and.right")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Button(model.isDemo ? "结束演示" : "管理设备") {
                            if model.isDemo { model.stopDemo() } else { openDevices() }
                        }.font(.subheadline).foregroundStyle(Theme.accent).frame(minHeight: 44)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("升降台与台面间距").font(.headline).foregroundStyle(Theme.muted)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(model.distanceMM.map { String(format: "%.1f", $0 / 10) } ?? "—")
                                .font(.system(size: 84, weight: .light, design: .rounded))
                                .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                            Text("cm").font(.title2).foregroundStyle(Theme.muted)
                        }
                        Label(model.posture.title, systemImage: model.posture.symbol)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(model.posture == .standing ? Theme.stand : Theme.ink)
                        Text(model.sampleMessage).font(.subheadline).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)

                    if model.isDemo { demoControls }
                    else if !model.bluetooth.isReady {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("开发板还没到，也可以先试试。").font(.headline)
                            Text("演示会生成测距数据，可测试坐站切换、校准和异常状态。")
                                .font(.subheadline).foregroundStyle(Theme.muted)
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 16) { connectButton; demoButton }
                                VStack(alignment: .leading, spacing: 8) { connectButton; demoButton }
                            }
                        }.surface()
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack { Text("最近 60 秒").font(.headline); Spacer(); Text("原始距离 · cm").font(.caption).foregroundStyle(Theme.muted) }
                        if model.history.isEmpty {
                            Text("收到测距数据后，这里会显示距离变化。")
                                .font(.subheadline).foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, minHeight: 130)
                        } else {
                            Chart {
                                ForEach(model.history) { point in
                                    LineMark(x: .value("时间", point.time), y: .value("距离", point.centimeters))
                                        .foregroundStyle(Theme.ink).lineStyle(StrokeStyle(lineWidth: 2))
                                }
                                RuleMark(y: .value("分界", model.settings.thresholdMM / 10))
                                    .foregroundStyle(Theme.accent).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            }
                            .chartXAxis(.hidden)
                            .chartXScale(domain: chartTimeRange)
                            .chartYAxis { AxisMarks(position: .leading) }
                            .chartYScale(domain: chartRange)
                            .frame(height: 140)
                            .accessibilityLabel("最近六十秒的台面间距，虚线为坐站分界距离")
                        }
                        Button(action: openSettings) {
                            HStack {
                                Text(String(format: "分界距离 %.1f cm", model.settings.thresholdMM / 10))
                                Spacer()
                                Image(systemName: "chevron.right")
                            }.font(.subheadline).frame(minHeight: 32)
                        }.foregroundStyle(Theme.accent)
                    }.surface()

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(model.isDemo || model.simulatedFirmware ? "本次演示时长" : "本次前台监测").font(.headline)
                            Spacer()
                            Button("清零") { model.resetSession() }.font(.subheadline).foregroundStyle(Theme.accent).frame(minHeight: 44)
                        }
                        HStack(spacing: 32) {
                            duration("站立高度", seconds: model.standingSeconds, symbol: "figure.stand")
                            duration("坐姿高度", seconds: model.sittingSeconds, symbol: "chair")
                        }
                        Text("仅统计 App 在前台且识别稳定的时段。桌台高度不能确认人是否在桌前。")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    .padding(.bottom, 16)
                }.padding(.horizontal, 24).padding(.top, 8)
            }
            .background(Theme.paper)
            .foregroundStyle(Theme.ink)
            .navigationTitle("StandUp")
        }
    }

    private var connectButton: some View {
        Button("连接开发板", action: openDevices).buttonStyle(.borderedProminent).foregroundStyle(Theme.onAccent).controlSize(.large)
    }
    private var demoButton: some View {
        Button("开始演示") { model.startDemo() }.buttonStyle(.bordered).foregroundStyle(Theme.accent).controlSize(.large)
    }
    private var demoControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("演示距离").font(.headline); Spacer(); Text(String(format: "%.1f cm", model.demoCentimeters)).monospacedDigit() }
            Slider(value: $model.demoCentimeters, in: 4...400, step: 0.5)
                .accessibilityLabel("演示距离，厘米")
            HStack {
                Button("坐姿高度") { model.demoCentimeters = min(400, max(4, model.settings.thresholdMM / 10 + (model.settings.standingIsFarther ? -10 : 10))) }
                Spacer()
                Button("站立高度") { model.demoCentimeters = min(400, max(4, model.settings.thresholdMM / 10 + (model.settings.standingIsFarther ? 10 : -10))) }
            }.buttonStyle(.bordered).foregroundStyle(Theme.accent)
            Toggle("模拟传感器读数有效", isOn: $model.demoSensorValid).font(.subheadline)
        }.surface()
    }

    private var chartRange: ClosedRange<Double> {
        let values = model.history.map(\.centimeters) + [model.settings.thresholdMM / 10]
        let lo = values.min() ?? 0
        let hi = values.max() ?? 100
        return max(0, lo - 5)...max(lo + 10, hi + 5)
    }

    private var chartTimeRange: ClosedRange<Double> {
        let now = ProcessInfo.processInfo.systemUptime
        return (now - 60)...now
    }

    private func duration(_ title: String, seconds: TimeInterval, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(Theme.muted)
            Text("\(Int(seconds) / 60)分\(Int(seconds) % 60)秒")
                .font(.title3.weight(.medium)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
