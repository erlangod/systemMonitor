import SwiftUI

struct CPUView: View {
    @ObservedObject var monitor: CPUMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.callout)
                    .foregroundStyle(monitor.pressureColor)
                Text("CPU")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(monitor.pressureColor)
                    .frame(width: 8, height: 8)
            }
            Text("\(monitor.coreCount) cores")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(String(format: "%.1f%%", monitor.usage))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(monitor.pressureColor)
                Spacer()
            }
            CapsuleProgressBar(value: monitor.usage / 100.0, color: monitor.pressureColor)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(NSColor.quaternarySystemFill)))
    }
}
