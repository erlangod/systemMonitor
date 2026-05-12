import SwiftUI

struct DiskView: View {
    @ObservedObject var monitor: DiskMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive")
                    .font(.callout)
                    .foregroundStyle(monitor.pressureColor)
                Text(monitor.diskType)
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(monitor.pressureColor)
                    .frame(width: 8, height: 8)
            }
            Text("\(formatBytes(monitor.usedSpace, binary: false)) / \(formatBytes(monitor.totalSpace, binary: false))")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(String(format: "%.1f%%", monitor.usagePercent))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(monitor.pressureColor)
                Spacer()
            }
            CapsuleProgressBar(value: monitor.usagePercent / 100.0, color: monitor.pressureColor)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(NSColor.quaternarySystemFill)))
    }
}
