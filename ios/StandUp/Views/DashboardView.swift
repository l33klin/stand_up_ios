import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let openDevices: () -> Void
    let openSettings: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.sectionGap) {
                    dailyGoal
                    heightReading
                    if model.isDemo { demoControls }
                    distanceTrend
                    session
                }
                .padding(.horizontal, Theme.pageInset).padding(.top, 8).padding(.bottom, 28)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .appPage()
            .navigationTitle("今天")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if model.isDemo { model.stopDemo() } else { openDevices() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: model.isDemo ? "stop.circle" : "antenna.radiowaves.left.and.right")
                            Text(model.isDemo ? "结束演示" : model.bluetooth.isReady ? "已连接" : model.bluetooth.isConnecting ? "连接中" : "连接设备")
                        }.font(.caption.weight(.medium))
                            .padding(.horizontal, 12).frame(minHeight: 36)
                            .background(Theme.subtle, in: Capsule())
                            .foregroundStyle(model.isDemo || model.bluetooth.isReady ? Theme.accent : Theme.muted)
                    }.frame(minHeight: 44)
                }
            }
        }
    }

    private var dailyGoal: some View {
        let today = model.todayRecord
        return VStack(spacing: 16) {
            HStack {
                Text("今日站立").font(.subheadline).foregroundStyle(Theme.muted)
                Spacer()
                Button(action: openSettings) {
                    HStack(spacing: 4) {
                        Text("目标 \(today.goalMinutes) 分钟").lineLimit(1).minimumScaleFactor(0.6)
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                    }.font(.subheadline).frame(minHeight: 44)
                }.foregroundStyle(Theme.muted)
            }
            GoalRing(record: today).padding(.vertical, 8)
            VStack(spacing: 6) {
                Text(today.isComplete ? "今日目标已完成" : "还差 \(Int(ceil(today.remainingSeconds / 60))) 分钟")
                    .font(.headline).foregroundStyle(today.isComplete ? Theme.stand : Theme.ink)
                Text(goalStatus).font(.caption).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            if !model.isDemo, !model.bluetooth.isReady, !model.bluetooth.hasConnection {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 8) { connectButton; demoButton }.padding(.top, 4)
                } else {
                    HStack(spacing: 16) { connectButton; demoButton }.padding(.top, 4)
                }
            }
        }
    }

    private var heightReading: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("台面间距").font(.caption).foregroundStyle(Theme.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(model.distanceMM.map { String(format: "%.1f", $0 / 10) } ?? "—")
                            .font(.system(.largeTitle, design: .rounded).weight(.medium)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text("cm").font(.subheadline).foregroundStyle(Theme.muted)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Label(model.posture.title, systemImage: model.posture.symbol)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(model.posture == .standing ? Theme.stand : Theme.ink)
                    Button(action: openSettings) {
                        Text(String(format: "分界 %.1f cm", model.settings.thresholdMM / 10)).lineLimit(1).minimumScaleFactor(0.6)
                            .font(.caption).frame(minHeight: 44)
                    }.foregroundStyle(Theme.muted)
                }
            }
            if model.distanceMM == nil, model.bluetooth.isReady {
                Text(model.sampleMessage).font(.caption).foregroundStyle(Theme.warning)
            }
        }.surface()
    }

    private var distanceTrend: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "距离趋势", detail: "最近 60 秒 · cm")
            if model.history.isEmpty {
                EmptyReading(symbol: "chart.xyaxis.line", title: "等待测距数据", detail: "连接后显示桌台高度的变化")
            } else {
                Chart {
                    ForEach(model.history) { point in
                        LineMark(x: .value("时间", point.time), y: .value("距离", point.centimeters))
                            .foregroundStyle(Theme.accent).lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
                    }
                    RuleMark(y: .value("分界", model.settings.thresholdMM / 10))
                        .foregroundStyle(Theme.muted).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }
                .chartXAxis(.hidden).chartXScale(domain: chartTimeRange)
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                .chartYScale(domain: chartRange).frame(height: 112)
                .accessibilityLabel("最近六十秒的台面间距，虚线为坐站分界")
                HStack { Text("60 秒前"); Spacer(); Text("现在") }
                    .font(.caption2).foregroundStyle(Theme.muted)
            }
        }
    }

    private var session: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider().overlay(Theme.rule)
            HStack {
                Text(model.isDemo || model.simulatedFirmware ? "本次演示" : "本次监测").font(.headline)
                Spacer()
                Button { model.resetSession() } label: {
                    Image(systemName: "arrow.counterclockwise").frame(minWidth: 44, minHeight: 44)
                }.foregroundStyle(Theme.muted)
                    .accessibilityLabel("清零本次监测").accessibilityHint("保留每日累计与历史记录")
            }
            HStack(spacing: 20) {
                duration("站立", seconds: model.standingSeconds, symbol: "figure.stand")
                Rectangle().fill(Theme.rule).frame(width: 1, height: 36).accessibilityHidden(true)
                duration("坐姿", seconds: model.sittingSeconds, symbol: "chair")
            }
            Label(model.bluetooth.isReady && !model.simulatedFirmware ? "锁屏后继续记录" : "仅真实设备数据计入每日目标", systemImage: "lock")
                .font(.caption).foregroundStyle(Theme.muted).padding(.top, 4)
        }
    }

    private var goalStatus: String {
        if model.isDemo || model.simulatedFirmware { return "演示数据不计入目标与历史" }
        if !model.bluetooth.isReady { return model.bluetooth.isConnecting ? "等待设备连接，连接期间不计时" : "连接你的升降台，开始记录" }
        if model.isCountingDailyStanding { return "正在记录站立时间" }
        if model.posture == .sitting { return "当前为坐姿高度" }
        return "等待稳定、有效的测距"
    }

    private var connectButton: some View {
        Button("连接设备", action: openDevices).buttonStyle(PrimaryButtonStyle())
    }

    private var demoButton: some View {
        Button("体验演示") { model.startDemo() }
            .font(.subheadline.weight(.medium)).foregroundStyle(Theme.accent)
            .lineLimit(1).frame(minWidth: 88, minHeight: 48)
    }

    private var demoControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "演示距离", detail: String(format: "%.1f cm", model.demoCentimeters))
            Slider(value: $model.demoCentimeters, in: 4...400, step: 0.5).accessibilityLabel("演示距离，厘米")
            HStack(spacing: 12) {
                Button("坐姿高度") { model.demoCentimeters = min(400, max(4, model.settings.thresholdMM / 10 + (model.settings.standingIsFarther ? -10 : 10))) }
                Spacer()
                Button("站立高度") { model.demoCentimeters = min(400, max(4, model.settings.thresholdMM / 10 + (model.settings.standingIsFarther ? 10 : -10))) }
            }.buttonStyle(.bordered).font(.subheadline)
            Toggle("读数有效", isOn: $model.demoSensorValid).font(.subheadline)
        }.surface()
    }

    private var chartRange: ClosedRange<Double> {
        let values = model.history.map(\.centimeters) + [model.settings.thresholdMM / 10]
        let lo = values.min() ?? 0
        let hi = values.max() ?? 100
        return max(0, lo - 5)...max(lo + 10, hi + 5)
    }

    private var chartTimeRange: ClosedRange<Double> {
        let now = MonitoringInstant.now.uptime
        return (now - 60)...now
    }

    private func duration(_ title: String, seconds: TimeInterval, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(Theme.muted)
            Text(StandingDuration.text(seconds)).font(.title3.weight(.medium)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
