import Foundation
import SwiftUI
import Darwin

class CPUMonitor: ObservableObject {
    @Published var coreCount: Int = 0
    @Published var usage: Double = 0.0
    @Published var pressureColor: Color = .green

    private var previousTicks: [processor_cpu_load_info]?
    private var previousTime: Date?

    init() {
        fetchCoreCount()
    }

    private func fetchCoreCount() {
        var count: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.ncpu", &count, &size, nil, 0)
        coreCount = Int(count)
    }

    func update() {
        var cpuCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(),
                                          PROCESSOR_CPU_LOAD_INFO,
                                          &cpuCount,
                                          &cpuInfo,
                                          &cpuInfoCount)

        guard result == KERN_SUCCESS,
              let info = cpuInfo else {
            return
        }

        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(bitPattern: info),
                          vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }

        let currentTime = Date()

        var totalUsage: Double = 0.0

        let loadInfo = info.withMemoryRebound(to: processor_cpu_load_info.self, capacity: Int(cpuCount)) {
            Array(UnsafeBufferPointer(start: $0, count: Int(cpuCount)))
        }

        if let prevTicks = previousTicks,
           let prevTime = previousTime,
           prevTicks.count == Int(cpuCount) {
            let timeDelta = currentTime.timeIntervalSince(prevTime)
            guard timeDelta > 0 else { return }

            for i in 0..<Int(cpuCount) {
                let current = loadInfo[i]
                let prev = prevTicks[i]

                let user = Int32(current.cpu_ticks.0) - Int32(prev.cpu_ticks.0)
                let system = Int32(current.cpu_ticks.1) - Int32(prev.cpu_ticks.1)
                let idle = Int32(current.cpu_ticks.2) - Int32(prev.cpu_ticks.2)
                let nice = Int32(current.cpu_ticks.3) - Int32(prev.cpu_ticks.3)

                let total = user + system + idle + nice
                if total > 0 {
                    let usage = Double(user + system + nice) / Double(total) * 100.0
                    totalUsage += usage
                }
            }

            let avgUsage = totalUsage / Double(cpuCount)
            DispatchQueue.main.async {
                self.usage = min(max(avgUsage, 0.0), 100.0)
                self.pressureColor = self.colorForUsage(self.usage)
            }
        }

        previousTicks = loadInfo
        previousTime = currentTime
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
