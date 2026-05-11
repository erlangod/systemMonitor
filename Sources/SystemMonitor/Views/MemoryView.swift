import SwiftUI

struct MemoryView: View {
    @ObservedObject var monitor: MemoryMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "memorychip")
                    .font(.callout)
                    .foregroundStyle(monitor.pressureColor)
                Text("RAM")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(monitor.pressureColor)
                    .frame(width: 8, height: 8)
            }
            Text("\(formatBytes(monitor.usedMemory)) / \(formatBytes(monitor.totalMemory))")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(String(format: "%.1f%%", monitor.usagePercent))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(monitor.pressureColor)
                Spacer()
            }
            CapsuleProgressBar(value: monitor.usagePercent / 100.0, color: monitor.pressureColor)
            HStack {
                Text("Swap: \(formatBytes(monitor.swapUsed))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(NSColor.quaternarySystemFill)))
    }
}
