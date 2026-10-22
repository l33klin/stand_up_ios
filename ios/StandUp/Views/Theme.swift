// Hallmark · genre: modern-minimal · macrostructure: Stat-Led · theme: Coral
// Native iOS adaptation: system navigation, SF typography, Dynamic Type, no decorative imagery.
// Audience: personal desk user · use: distance monitoring · tone: quiet and precise.
// Pre-emit critique: Philosophy 4 · Hierarchy 5 · Execution 4 · Specificity 5 · Restraint 5 · Variety 4.
import SwiftUI

enum Theme {
    static let paper = Color(red: 0.97, green: 0.96, blue: 0.94)
    static let surface = Color(red: 0.995, green: 0.99, blue: 0.98)
    static let ink = Color(red: 0.16, green: 0.18, blue: 0.18)
    static let muted = Color(red: 0.39, green: 0.41, blue: 0.40)
    static let accent = Color(red: 0.72, green: 0.25, blue: 0.17)
    static let onAccent = Color(red: 0.995, green: 0.99, blue: 0.98)
    static let rule = Color(red: 0.84, green: 0.83, blue: 0.80)
    static let stand = Color(red: 0.20, green: 0.40, blue: 0.31)
}

struct Surface: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(20).background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}

extension View {
    func surface() -> some View { modifier(Surface()) }
}
