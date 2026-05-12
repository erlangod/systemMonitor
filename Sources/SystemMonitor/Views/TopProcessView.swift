import SwiftUI

struct ProcessListView: View {
    let processes: [ProcessInfo]
    let valueKey: KeyPath<ProcessInfo, Double>
    let unit: String
    var showMemoryBytes: Bool = false
    var showPid: Bool = false

    var body: some View {
        if processes.isEmpty {
            Text("加载中...")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(NSColor.quaternarySystemFill)))
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(processes.enumerated()), id: \.element.id) { index, process in
                        let value = process[keyPath: valueKey]
                        HStack(spacing: 6) {
                            Text("\(index + 1)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .frame(width: 16, alignment: .trailing)
                            Text(showPid ? "\(process.name) (\(process.pid))" : process.name)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            if showMemoryBytes {
                                Text(formatMemoryBytes(process.memoryBytes))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(String(format: "%.1f%@", value, unit))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(colorForValue(value))
                        }
                    }
                }
                .padding(12)
            }
            .frame(height: 130)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(NSColor.quaternarySystemFill)))
        }
    }

    private func formatMemoryBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        if gb >= 1.0 {
            return String(format: "%.2f GB", gb)
        } else {
            let mb = Double(bytes) / 1_048_576.0
            return String(format: "%.1f MB", mb)
        }
    }

    private func colorForValue(_ value: Double) -> Color {
        if value > 80 {
            return .red
        } else if value > 50 {
            return .yellow
        } else {
            return .green
        }
    }
}
