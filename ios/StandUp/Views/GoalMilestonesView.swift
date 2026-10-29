import SwiftUI

struct GoalMilestonesView: View {
    let record: DailyDeskRecord
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var stage: GoalMilestone { record.milestone }

    var body: some View {
        Label(stage.encouragement, systemImage: stage.symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(record.isComplete ? Theme.stand : Theme.accent)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: stage)
    }
}

private extension GoalMilestone {
    var symbol: String {
        switch self {
        case .starting: return "figure.stand"
        case .quarter: return "leaf.fill"
        case .half: return "flag.fill"
        case .threeQuarters: return "sparkles"
        case .complete: return "trophy.fill"
        }
    }
    var encouragement: String {
        switch self {
        case .starting: return "每次站立，都在向目标靠近"
        case .quarter: return "第一步完成，继续保持"
        case .half: return "已过半程，节奏不错"
        case .threeQuarters: return "再坚持一小步，就能达标"
        case .complete: return "今天的坚持，值得一个赞"
        }
    }
}
