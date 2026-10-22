import SwiftUI

@main
struct StandUpApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(.light)
                .onChange(of: scenePhase) { _, phase in
                    // Permission sheets temporarily make the scene inactive; keep their scan alive.
                    if phase == .active { model.setActive(true) }
                    if phase == .background { model.setActive(false) }
                }
        }
    }
}
