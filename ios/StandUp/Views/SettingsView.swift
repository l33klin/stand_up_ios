import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $model.dailyGoalMinutes, in: 5...480, step: 5) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("每天站立").font(.subheadline).foregroundStyle(Theme.muted)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(model.dailyGoalMinutes)").font(.system(.largeTitle, design: .rounded).weight(.medium)).monospacedDigit()
                                Text("分钟").font(.subheadline).foregroundStyle(Theme.muted)
                            }
                        }.padding(.vertical, 8)
                    }
                    LabeledContent("今日已记录", value: StandingDuration.text(model.todayRecord.standingSeconds))
                        .font(.subheadline)
                } header: { Text("每日目标") } footer: { Text("分次累计，养成每天站立办公的习惯。") }

                Section("桌台高度") {
                    NavigationLink { DetectionSettingsView() } label: {
                        SettingsRow(title: "识别距离", symbol: "ruler", value: String(format: "%.1f cm", model.settings.thresholdMM / 10))
                    }
                    NavigationLink { CalibrationView() } label: {
                        SettingsRow(title: "高度校准", symbol: "slider.horizontal.3", value: model.settings.seatedCalibrationMM != nil && model.settings.standingCalibrationMM != nil ? "已校准" : "两点校准")
                    }
                    NavigationLink { StabilitySettingsView() } label: {
                        SettingsRow(title: "识别稳定性", symbol: "waveform.path")
                    }
                }

                Section {
                    NavigationLink { MonitoringRulesView() } label: {
                        SettingsRow(title: "统计与锁屏", symbol: "lock.iphone", value: "支持后台")
                    }
                    Toggle(isOn: Binding(get: { model.isDemo }, set: { if $0 { model.startDemo() } else { model.stopDemo() } })) {
                        SettingsRow(title: "手机演示", symbol: "play.circle")
                    }
                } header: { Text("监测") } footer: { Text("演示无需开发板，不计入目标与历史。") }

                Section {
                    LabeledContent("版本", value: "1.0.0").font(.subheadline)
                    LabeledContent("数据保存", value: "本机 · 最近 30 天").font(.subheadline)
                } header: { Text("StandUp") } footer: {
                    Text("根据桌台高度推断坐站状态，不检测是否在桌前。")
                }
            }
            .appForm().navigationTitle("设置")
        }
    }
}

private struct DetectionSettingsView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("坐站分界").font(.subheadline).foregroundStyle(Theme.muted)
                    Text(String(format: "%.1f cm", model.settings.thresholdMM / 10))
                        .font(.system(.largeTitle, design: .rounded).weight(.medium)).monospacedDigit()
                    Slider(value: $model.settings.thresholdMM, in: 50...3950, step: 5)
                        .accessibilityLabel("坐站分界距离，毫米")
                    Stepper("调整 0.5 cm", value: $model.settings.thresholdMM, in: 50...3950, step: 5)
                        .font(.subheadline)
                }.padding(.vertical, 12)
            } footer: { Text("测量升降台与固定台面的间距，默认距离大为站立高度。") }
            Section {
                Toggle("距离较大时为站立", isOn: $model.settings.standingIsFarther)
            } footer: { Text("修改后重新等待稳定识别。也可以通过两点校准自动设置。") }
        }.appForm().navigationTitle("识别距离").navigationBarTitleDisplayMode(.inline)
    }
}

private struct CalibrationView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Form {
            Section {
                LabeledContent("当前间距", value: calibration(model.distanceMM))
                    .font(.headline).padding(.vertical, 8)
            } footer: { Text("将升降台调到对应高度，再记录一次。") }
            Section("坐姿高度") {
                LabeledContent("已记录", value: calibration(model.settings.seatedCalibrationMM))
                Button("记录坐姿高度") { model.calibrate(standing: false) }.disabled(model.distanceMM == nil)
            }
            Section("站立高度") {
                LabeledContent("已记录", value: calibration(model.settings.standingCalibrationMM))
                Button("记录站姿高度") { model.calibrate(standing: true) }.disabled(model.distanceMM == nil)
            }
            Section {
                Text("两次高度至少相差 4 cm。完成后自动取中点作为分界，并确定判断方向。")
                    .font(.subheadline).foregroundStyle(Theme.muted)
            }
        }.appForm().navigationTitle("高度校准").navigationBarTitleDisplayMode(.inline)
            .alert("高度校准", isPresented: Binding(get: { model.calibrationMessage != nil }, set: { if !$0 { model.calibrationMessage = nil } })) {
                Button("知道了", role: .cancel) { model.calibrationMessage = nil }
            } message: { Text(model.calibrationMessage ?? "") }
    }
    private func calibration(_ mm: Double?) -> String { mm.map { String(format: "%.1f cm", $0 / 10) } ?? "未记录" }
}

private struct StabilitySettingsView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Form {
            Section {
                Stepper(value: $model.settings.hysteresisMM, in: 0...model.settings.maximumHysteresisMM, step: 5) {
                    LabeledContent("滞回半宽", value: String(format: "± %.1f cm", model.settings.hysteresisMM / 10))
                }
            } footer: { Text("切换姿态需要跨过分界边缘，避免在分界附近反复跳动。") }
            Section {
                Stepper(value: $model.settings.stabilitySeconds, in: 0.5...5, step: 0.5) {
                    LabeledContent("稳定时间", value: String(format: "%.1f 秒", model.settings.stabilitySeconds))
                }
            } footer: { Text("先对最近 5 次读数取中位数，持续稳定后切换。超过 2 秒无有效数据时停止识别。") }
        }.appForm().navigationTitle("识别稳定性").navigationBarTitleDisplayMode(.inline)
    }
}

struct MonitoringRulesView: View {
    var body: some View {
        List {
            Section("有效统计") {
                Text("只有连接真实设备、收到连续有效测距且稳定识别后的时段才会累计。站立计入目标，坐姿单独保存。")
                Text("手机演示与开发板模拟数据不会增加每日目标或历史时长。")
            }
            Section("锁屏使用") {
                Text("连接后可以锁屏或切换 App，由蓝牙通知继续记录。后台接收受 iOS 调度影响。")
                Text("断连、无效读数或超过 2 秒的数据空档不补算；恢复后重新等待稳定识别。意外断连会尝试重连同一设备。")
                Text("设备页的“断开连接”会停止监测与重连。手动划掉 App 后需重新打开并检查连接。")
            }
            Section("数据与目标") {
                Text("最近 30 个本地日历日（含今天）的记录保存在此设备，过期自动清理，没有监测的时间不补记。")
                Text("修改目标影响今天及之后。历史日期保留当时的目标；清零本次监测不会删除每日记录。")
            }
        }.font(.subheadline).appForm().navigationTitle("统计与锁屏").navigationBarTitleDisplayMode(.inline)
    }
}
