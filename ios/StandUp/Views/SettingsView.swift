import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("坐站分界距离")
                            Spacer()
                            Text(String(format: "%.1f cm", model.settings.thresholdMM / 10))
                                .font(.headline.monospacedDigit())
                        }
                        Slider(value: $model.settings.thresholdMM, in: 50...3950, step: 5)
                            .accessibilityLabel("坐站分界距离，毫米")
                        Stepper("每次调整 0.5 cm", value: $model.settings.thresholdMM, in: 50...3950, step: 5)
                            .font(.subheadline)
                    }.padding(.vertical, 6)
                    Toggle("距离较大时为站立高度", isOn: $model.settings.standingIsFarther)
                } header: { Text("识别距离") } footer: {
                    Text("默认适用于升降台与固定台面之间的测距：升高为站立，降低为坐姿。设置仅保存在这台 iPhone 上，修改后重新等待稳定识别。")
                }

                Section {
                    LabeledContent("当前间距", value: model.distanceMM.map { String(format: "%.1f cm", $0 / 10) } ?? "等待有效读数")
                    Button("记录坐姿高度") { model.calibrate(standing: false) }.disabled(model.distanceMM == nil)
                    Button("记录站姿高度") { model.calibrate(standing: true) }.disabled(model.distanceMM == nil)
                    LabeledContent("已记录坐姿", value: calibration(model.settings.seatedCalibrationMM))
                    LabeledContent("已记录站姿", value: calibration(model.settings.standingCalibrationMM))
                } header: { Text("两点校准") } footer: {
                    Text("分别将升降台调到坐姿与站姿高度，再记录间距。两点至少相差 4 cm；完成后自动取中点作为分界，并确定判断方向。演示中也可以测试此流程。")
                }

                Section {
                    Stepper(value: $model.settings.hysteresisMM, in: 0...model.settings.maximumHysteresisMM, step: 5) {
                        LabeledContent("滞回半宽", value: String(format: "± %.1f cm", model.settings.hysteresisMM / 10))
                    }
                    Stepper(value: $model.settings.stabilitySeconds, in: 0.5...5, step: 0.5) {
                        LabeledContent("稳定时间", value: String(format: "%.1f 秒", model.settings.stabilitySeconds))
                    }
                } header: { Text("减少抖动") } footer: {
                    Text("先对最近 5 次读数取中位数，再进行识别。切换姿态须跨过分界的滞回边缘，并持续达到稳定时间。超过 2 秒没有有效数据将停止识别。")
                }

                Section {
                    if model.isDemo { Button("结束手机演示") { model.stopDemo() } }
                    else { Button("开始手机演示") { model.startDemo() } }
                } header: { Text("无硬件测试") } footer: {
                    Text("手机演示不请求蓝牙权限。演示时可在监测页调节距离，并模拟传感器无效读数。")
                }

                Section {
                    LabeledContent("App 版本", value: "1.0.0")
                    LabeledContent("测距协议", value: "StandUp BLE v1")
                    Text("数据与设置保存在本机。此版本只做前台监测，不包含后台统计、云同步或离桌检测。")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                } header: { Text("关于") }
            }
            .scrollContentBackground(.hidden).background(Theme.paper)
            .navigationTitle("识别设置")
            .alert("高度校准", isPresented: Binding(get: { model.calibrationMessage != nil }, set: { if !$0 { model.calibrationMessage = nil } })) {
                Button("知道了", role: .cancel) { model.calibrationMessage = nil }
            } message: { Text(model.calibrationMessage ?? "") }
        }
    }

    private func calibration(_ mm: Double?) -> String { mm.map { String(format: "%.1f cm", $0 / 10) } ?? "未记录" }
}
