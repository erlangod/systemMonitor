import Foundation
import SwiftUI

class DiskMonitor: ObservableObject {
    @Published var totalSpace: UInt64 = 0
    @Published var usedSpace: UInt64 = 0
    @Published var usagePercent: Double = 0.0
    @Published var pressureColor: Color = .green
    @Published var diskType: String = "HDD"

    init() {
        diskType = "SSD"
        DispatchQueue.global(qos: .utility).async {
            let type = self.detectDiskType()
            DispatchQueue.main.async { self.diskType = type }
        }
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
        let isSSD = output.components(separatedBy: .newlines)
            .first { $0.contains("Solid State") }?
            .contains("Yes") ?? false
        return (isSSD || output.contains("SSD")) ? "SSD" : "HDD"
    }

    func update() {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return
        }

        let totalBytes = UInt64(total)
        let availBytes = UInt64(max(0, available))
        let used = totalBytes > availBytes ? totalBytes - availBytes : 0
        let percent = totalBytes > 0 ? Double(used) / Double(totalBytes) * 100.0 : 0.0

        DispatchQueue.main.async {
            self.totalSpace = totalBytes
            self.usedSpace = used
            self.usagePercent = percent
            self.pressureColor = colorForUsage(percent)
        }
    }
}
