import SwiftUI

@main
struct SystemMonitorApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("System Monitor", systemImage: "gauge.medium") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}


