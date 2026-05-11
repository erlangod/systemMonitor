import Foundation
import SwiftUI

class DiskMonitor: ObservableObject {
    @Published var totalSpace: UInt64 = 0
    @Published var usedSpace: UInt64 = 0
    @Published var usagePercent: Double = 0.0
    @Published var pressureColor: Color = .green
    @Published var diskType: String = "HDD"

    init() {
        diskType = detectDiskType()
    }

    private func detectDiskType() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "/"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if output.contains("Solid State: Yes") || output.contains("SSD") {
            return "SSD"
        }
        return "HDD"
    }

    func update() {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: "/")

            guard let total = attrs[.systemSize] as? UInt64,
                  let free = attrs[.systemFreeSize] as? UInt64 else {
                return
            }

            let used = total - free
            let percent = total > 0 ? Double(used) / Double(total) * 100.0 : 0.0

            DispatchQueue.main.async {
                self.totalSpace = total
                self.usedSpace = used
                self.usagePercent = percent
                self.pressureColor = self.colorForUsage(percent)
            }
        } catch {
            // Silently fail; values remain at 0
        }
    }

    private func colorForUsage(_ percent: Double) -> Color {
        if percent > 80 {
            return .red
        } else if percent > 50 {
            return .yellow
        } else {
            return .green
        }
    }
}
