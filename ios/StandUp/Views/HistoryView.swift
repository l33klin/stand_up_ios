import SwiftUI
import Charts

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsRules = false

    private var records: [DailyDeskRecord] {
        let today = StandingHistory.dayKey(for: model.todayDate)
        return model.dailyHistory.records.values.filter { $0.day <= today }.sorted { $0.day > $1.day }
    }

    private var week: [(day: String, label: String, record: DailyDeskRecord?)] {
        let calendar = Calendar.autoupdatingCurrent
        return (-6...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: model.todayDate) else { return nil }
            let day = StandingHistory.dayKey(for: date)
            return (day, String(day.suffix(5)).replacingOccurrences(of: "-", with: "/"), model.dailyHistory.records[day])
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionGap) {
                    weeklySummary
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeading(title: "每日记录", detail: "最近 30 天")
                        VStack(spacing: 0) {
                            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                                if index > 0 { Divider().padding(.leading, 16) }
                                NavigationLink { DailyRecordView(day: record.day) } label: { recordRow(record) }
                                    .buttonStyle(.plain)
                            }
                        }.surface(padding: 0)
                        Text("仅记录真实测距 · 数据保存在此设备")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.horizontal, Theme.pageInset).padding(.top, 16).padding(.bottom, 28)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .appPage().navigationTitle("历史")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsRules = true } label: { Image(systemName: "info.circle").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("了解统计规则")
                }
            }
            .sheet(isPresented: $showsRules) {
                NavigationStack {
                    MonitoringRulesView()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showsRules = false } } }
                }.tint(Theme.accent)
            }
        }
    }

    private var weeklySummary: some View {
        let seconds = week.reduce(0) { $0 + ($1.record?.standingSeconds ?? 0) }
        let completed = week.filter { $0.record?.isComplete == true }.count
        return VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("近 7 天站立").font(.subheadline).foregroundStyle(Theme.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(seconds) / 60)").font(.system(.largeTitle, design: .rounded).weight(.medium)).monospacedDigit()
                        Text("分钟").font(.subheadline).foregroundStyle(Theme.muted)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 8) {
                    Text("达标天数").font(.subheadline).foregroundStyle(Theme.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(completed)").font(.system(.largeTitle, design: .rounded).weight(.medium)).monospacedDigit()
                        Text("天").font(.subheadline).foregroundStyle(Theme.muted)
                    }
                }
            }
            if seconds > 0 {
                Chart(week, id: \.day) { item in
                    BarMark(x: .value("日期", item.label), y: .value("站立分钟", (item.record?.standingSeconds ?? 0) / 60), width: .ratio(0.42))
                        .cornerRadius(4)
                        .foregroundStyle(item.record?.isComplete == true ? Theme.stand : Theme.accent)
                        .accessibilityLabel("\(item.label)，站立 \(StandingDuration.text(item.record?.standingSeconds ?? 0))\(item.record?.isComplete == true ? "，已达标" : "")")
                }
                .chartYScale(domain: 0...max(5, (week.compactMap { $0.record?.standingSeconds }.max() ?? 0) / 60 * 1.15))
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Theme.muted) } }
                .frame(height: 164)
            } else {
                EmptyReading(symbol: "chart.bar", title: "还没有站立记录", detail: "连接设备后，每一次站立都会记在这里")
                    .frame(minHeight: 144)
            }
            Divider().overlay(Theme.rule)
        }
    }

    private func recordRow(_ record: DailyDeskRecord) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(record.day == StandingHistory.dayKey(for: model.todayDate) ? "今天" : String(record.day.suffix(5)).replacingOccurrences(of: "-", with: " / "))
                    .font(.subheadline.weight(.semibold))
                Text("目标 \(record.goalMinutes) 分钟").font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 4) {
                    if record.isComplete { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.stand) }
                    Text(StandingDuration.text(record.standingSeconds)).monospacedDigit()
                }.font(.subheadline.weight(.medium))
                ProgressView(value: record.progress).tint(record.isComplete ? Theme.stand : Theme.accent).frame(width: 72)
                    .accessibilityHidden(true)
            }
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted)
        }.foregroundStyle(Theme.ink).padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(record.day)，站立 \(StandingDuration.text(record.standingSeconds))，目标 \(record.goalMinutes) 分钟，\(record.isComplete ? "已达标" : "未达标")")
    }
}

private struct DailyRecordView: View {
    @EnvironmentObject private var model: AppModel
    let day: String

    var body: some View {
        ScrollView {
            if let record = model.dailyHistory.records[day] {
                VStack(spacing: 28) {
                    GoalRing(record: record).padding(.top, 24)
                    VStack(spacing: 8) {
                        Text(record.isComplete ? "已完成当天目标" : "当天目标未完成").font(.headline)
                        Text("站立目标 \(record.goalMinutes) 分钟").font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    VStack(spacing: 0) {
                        detailRow("站立时间", value: StandingDuration.text(record.standingSeconds), symbol: "figure.stand")
                        Divider()
                        detailRow("坐姿时间", value: StandingDuration.text(record.sittingSeconds), symbol: "chair")
                        Divider()
                        detailRow("有效监测", value: StandingDuration.text(record.standingSeconds + record.sittingSeconds), symbol: "clock")
                    }.surface()
                    Text("包含锁屏时接收的有效测距。按当时设置排除午休时段，数据空档与演示时段不计入。")
                        .font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                }.padding(.horizontal, Theme.pageInset).padding(.bottom, 28)
                    .frame(maxWidth: 640).frame(maxWidth: .infinity)
            } else {
                EmptyReading(symbol: "calendar", title: "记录已过期", detail: "仅保留最近 30 天的数据")
            }
        }.appPage().navigationTitle(day).navigationBarTitleDisplayMode(.inline)
    }

    private func detailRow(_ title: String, value: String, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).font(.subheadline.weight(.medium)).monospacedDigit()
        }.padding(.vertical, 16)
    }
}
