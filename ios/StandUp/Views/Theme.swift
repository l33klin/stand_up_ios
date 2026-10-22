// Hallmark · pre-emit critique: P4 H5 E4 S5 R5 V4
// Modern-minimal · Workbench · Cobalt, adapted to native iOS controls and SF typography.
// Design tokens: design.md. Functional progress and measured data; no decorative imagery.
import SwiftUI

enum Theme {
    static let paper = Color(red: 0.985, green: 0.989, blue: 0.997)
    static let surface = Color(red: 1, green: 1, blue: 1)
    static let subtle = Color(red: 0.945, green: 0.958, blue: 0.980)
    static let ink = Color(red: 0.085, green: 0.115, blue: 0.175)
    static let muted = Color(red: 0.355, green: 0.400, blue: 0.480)
    static let accent = Color(red: 0.130, green: 0.330, blue: 0.870)
    static let pressedAccent = Color(red: 0.090, green: 0.250, blue: 0.700)
    static let onAccent = surface
    static let rule = Color(red: 0.865, green: 0.892, blue: 0.930)
    static let track = Color(red: 0.885, green: 0.910, blue: 0.950)
    static let stand = Color(red: 0.075, green: 0.430, blue: 0.315)
    static let warning = Color(red: 0.580, green: 0.300, blue: 0.080)
    static let destructive = Color(red: 0.710, green: 0.190, blue: 0.220)
    static let pageInset: CGFloat = 24
    static let sectionGap: CGFloat = 28
    static let radius: CGFloat = 16
}

struct Surface: ViewModifier {
    var padding: CGFloat = 20
    func body(content: Content) -> some View {
        content.padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay { RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.rule, lineWidth: 0.5) }
    }
}

extension View {
    func surface(padding: CGFloat = 20) -> some View { modifier(Surface(padding: padding)) }
    func appPage() -> some View { background(Theme.paper).foregroundStyle(Theme.ink) }
    func appForm() -> some View {
        scrollContentBackground(.hidden).background(Theme.paper).foregroundStyle(Theme.ink)
            .tint(Theme.accent)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .lineLimit(1).minimumScaleFactor(0.75)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(Theme.onAccent)
            .background(configuration.isPressed ? Theme.pressedAccent : Theme.accent, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 14).strokeBorder(isFocused ? Theme.ink : Theme.ink.opacity(0), lineWidth: 2)
                    .padding(-4)
            }
            .opacity(isEnabled ? 1 : 0.40)
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct GoalRing: View {
    let record: DailyDeskRecord
    var diameter: CGFloat = 196
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 60

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: 10)
            Circle().trim(from: 0, to: record.progress)
                .stroke(record.isComplete ? Theme.stand : Theme.accent,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(Int(record.standingSeconds) / 60)")
                    .font(.system(size: numberSize, weight: .medium, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.4)
                    .foregroundStyle(Theme.ink)
                Text("站立分钟").font(.subheadline).foregroundStyle(Theme.muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }.padding(24)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("已站立 \(StandingDuration.text(record.standingSeconds))，目标 \(record.goalMinutes) 分钟，完成 \(Int(record.progress * 100))%")
    }
}

struct SectionHeading: View {
    let title: String
    var detail: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Spacer(minLength: 12)
            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(Theme.muted) }
        }
    }
}

struct EmptyReading: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Theme.muted).padding(.bottom, 4)
            Text(title).font(.subheadline.weight(.medium))
            Text(detail).font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 24)
    }
}

struct SettingsRow: View {
    let title: String
    let symbol: String
    var value: String = ""
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 24)
            Text(title).foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            if !value.isEmpty { Text(value).font(.subheadline).foregroundStyle(Theme.muted) }
        }.padding(.vertical, 4)
    }
}

enum StandingDuration {
    static func text(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total >= 3600 { return "\(total / 3600)小时\(total % 3600 / 60)分" }
        return "\(total / 60)分\(total % 60)秒"
    }
}
