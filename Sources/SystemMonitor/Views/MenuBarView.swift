import SwiftUI

func formatBytes(_ bytes: UInt64) -> String {
    let gb = Double(bytes) / 1_073_741_824.0
    if gb >= 1.0 {
        return String(format: "%.1f GB", gb)
    } else {
        let mb = Double(bytes) / 1_048_576.0
        return String(format: "%.1f MB", mb)
    }
}

struct CapsuleProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(geometry.size.width, geometry.size.width * CGFloat(value))))
            }
        }
        .frame(height: 8)
    }
}

struct TabButton: View {
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct MenuBarView: View {
    let showPid: Bool
    @StateObject private var cpuMonitor = CPUMonitor()
    @StateObject private var memoryMonitor = MemoryMonitor()
    @StateObject private var diskMonitor = DiskMonitor()
    @StateObject private var processMonitor = ProcessMonitor()
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Tab 切换栏
            HStack(spacing: 0) {
                TabButton(systemImage: "cpu", isSelected: selectedTab == 0) { selectedTab = 0 }
                TabButton(systemImage: "memorychip", isSelected: selectedTab == 1) { selectedTab = 1 }
                TabButton(systemImage: "internaldrive", isSelected: selectedTab == 2) { selectedTab = 2 }
            }
            .padding(3)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Tab 内容区
            Group {
                switch selectedTab {
                case 0:
                    cpuTab
                case 1:
                    memoryTab
                case 2:
                    diskTab
                default:
                    EmptyView()
                }
            }

            Divider()
                .padding(.top, 4)

            // 退出按钮
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                HStack {
                    Image(systemName: "power")
                        .font(.caption2)
                    Text("退出")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 320)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onAppear {
            updateAll()
        }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            updateAll()
        }
    }

    // MARK: - CPU Tab

    private var cpuTab: some View {
        VStack(spacing: 10) {
            CPUView(monitor: cpuMonitor)
            ProcessListView(
                processes: processMonitor.topCPUProcesses,
                valueKey: \.cpuUsage,
                unit: "%",
                showPid: showPid
            )
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 内存 Tab

    private var memoryTab: some View {
        VStack(spacing: 10) {
            MemoryView(monitor: memoryMonitor)
            ProcessListView(
                processes: processMonitor.topMemoryProcesses,
                valueKey: \.memoryUsage,
                unit: "%",
                showMemoryBytes: true,
                showPid: showPid
            )
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 硬盘 Tab

    private var diskTab: some View {
        VStack(spacing: 10) {
            DiskView(monitor: diskMonitor)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Update

    private func updateAll() {
        cpuMonitor.update()
        memoryMonitor.update()
        diskMonitor.update()
        processMonitor.update()
    }
}
