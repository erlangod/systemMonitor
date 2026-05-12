import SwiftUI

@main
struct SystemMonitorApp: App {
    /// 是否显示进程 PID，通过启动参数 --show-pid 开启
    let showPid: Bool

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        showPid = CommandLine.arguments.contains("--show-pid")
    }

    var body: some Scene {
        MenuBarExtra("System Monitor", systemImage: "gauge.medium") {
            MenuBarView(showPid: showPid)
        }
        .menuBarExtraStyle(.window)
    }
}


