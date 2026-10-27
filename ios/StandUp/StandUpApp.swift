import SwiftUI
import UIKit

// Own the model before scenes are created: a CoreBluetooth restoration launch may
// run entirely in the background without showing a SwiftUI window.
final class StandUpAppDelegate: NSObject, UIApplicationDelegate {
    let model = AppModel()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        model.setActive(application.applicationState == .active)
        let identifiers = launchOptions?[.bluetoothCentrals] as? [String] ?? []
        model.bluetooth.restoreIfNeeded(identifiers: identifiers)
        model.bluetooth.resumeMonitoring()
        return true
    }
}

@main
struct StandUpApp: App {
    @UIApplicationDelegateAdaptor(StandUpAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.model)
                .preferredColorScheme(.light)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // Permission sheets temporarily make the scene inactive; keep their scan alive.
                    if phase == .active { appDelegate.model.setActive(true) }
                    if phase == .background { appDelegate.model.setActive(false) }
                }
        }
    }
}
