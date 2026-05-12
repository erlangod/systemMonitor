import Foundation
import SwiftUI
import Darwin

class MemoryMonitor: ObservableObject {
    @Published var totalMemory: UInt64 = 0
    @Published var usedMemory: UInt64 = 0
    @Published var usagePercent: Double = 0.0
    @Published var swapUsed: UInt64 = 0
    @Published var pressureColor: Color = .green

    private var pageSize: vm_size_t {
        let pageSize = NSPageSize()
        return vm_size_t(pageSize)
    }

    init() {
        fetchTotalMemory()
    }

    private func fetchTotalMemory() {
        var size: UInt64 = 0
        var len = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &size, &len, nil, 0)
        totalMemory = size
    }

    func update() {
        // Fetch VM statistics
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            host_statistics64(mach_host_self(),
                              HOST_VM_INFO64,
                              host_info64_t(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: integer_t.self)),
                              &count)
        }

        guard result == KERN_SUCCESS else { return }

        let pageSizeValue = UInt64(pageSize)

        // Match macOS Activity Monitor's "Memory Used" calculation:
        // Used = Total - Free - Cached Files
        // Free = free_count * pageSize
        // Cached Files ≈ external_page_count (file-backed pages) * pageSize
        // Speculative pages are on the free list and also available
        let available = (UInt64(stats.free_count)
                         + UInt64(stats.external_page_count)
                         + UInt64(stats.speculative_count)) * pageSizeValue
        let used = totalMemory - available
        let percent = totalMemory > 0 ? Double(used) / Double(totalMemory) * 100.0 : 0.0

        // Fetch swap usage
        let swap = fetchSwapUsage()

        DispatchQueue.main.async {
            self.usedMemory = used
            self.usagePercent = percent
            self.swapUsed = swap
            self.pressureColor = colorForUsage(percent)
        }
    }

    private func fetchSwapUsage() -> UInt64 {
        var mib: [Int32] = [CTL_VM, VM_SWAPUSAGE]
        var swapUsage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size

        let result = sysctl(&mib, u_int(mib.count), &swapUsage, &size, nil, 0)
        guard result == 0 else { return 0 }

        return UInt64(swapUsage.xsu_used)
    }
}
