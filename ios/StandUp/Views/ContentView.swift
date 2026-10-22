import SwiftUI

struct ContentView: View {
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            DashboardView(openDevices: { tab = 1 }, openSettings: { tab = 2 })
                .tabItem { Label("监测", systemImage: "ruler") }.tag(0)
            DevicesView().tabItem { Label("设备", systemImage: "antenna.radiowaves.left.and.right") }.tag(1)
            SettingsView().tabItem { Label("设置", systemImage: "slider.horizontal.3") }.tag(2)
        }
        .tint(Theme.accent)
    }
}
