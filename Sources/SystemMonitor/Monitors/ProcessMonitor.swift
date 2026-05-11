import Foundation
import Darwin

struct ProcessInfo: Identifiable {
    let id = UUID()
    let pid: Int32
    let name: String
    let cpuUsage: Double
    let memoryUsage: Double
    let memoryBytes: UInt64
}

/// 临时用于解析 ps 输出的结构
private struct RawProcess {
    let pid: Int32
    let rssKB: Double
    let cpuUsage: Double
    let rawName: String
}

class ProcessMonitor: ObservableObject {
    @Published var topCPUProcesses: [ProcessInfo] = []
    @Published var topMemoryProcesses: [ProcessInfo] = []

    /// 总物理内存（字节）
    private let totalMemory: UInt64 = {
        return Foundation.ProcessInfo.processInfo.physicalMemory
    }()

    func update() {
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/ps")
            task.arguments = ["-axo", "pid=,rss=,pcpu=,comm="]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
            } catch {
                return
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            guard task.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8) else { return }

            let rawProcesses = self.parsePSOutput(output)

            // 为所有进程获取精确内存数据，构建 ProcessInfo
            let allProcesses = rawProcesses.map { raw -> ProcessInfo in
                let footprint = getPhysFootprint(pid: raw.pid)
                let memoryPercent: Double
                let memBytes: UInt64
                if footprint > 0 {
                    memoryPercent = Double(footprint) / Double(self.totalMemory) * 100.0
                    memBytes = footprint
                } else {
                    // fallback: 使用 rss
                    memoryPercent = raw.rssKB * 1024.0 / Double(self.totalMemory) * 100.0
                    memBytes = UInt64(raw.rssKB * 1024.0)
                }
                return ProcessInfo(pid: raw.pid, name: extractAppName(from: raw.rawName), cpuUsage: raw.cpuUsage, memoryUsage: memoryPercent, memoryBytes: memBytes)
            }

            // 按应用名分组聚合（同名进程 CPU/内存累加）
            var grouped: [String: (cpuUsage: Double, memoryUsage: Double, memoryBytes: UInt64, pid: Int32)] = [:]
            for process in allProcesses {
                if var existing = grouped[process.name] {
                    existing.cpuUsage += process.cpuUsage
                    existing.memoryUsage += process.memoryUsage
                    existing.memoryBytes += process.memoryBytes
                    grouped[process.name] = existing
                } else {
                    grouped[process.name] = (process.cpuUsage, process.memoryUsage, process.memoryBytes, process.pid)
                }
            }

            let aggregated = grouped.map { name, data in
                ProcessInfo(pid: data.pid, name: name, cpuUsage: data.cpuUsage, memoryUsage: data.memoryUsage, memoryBytes: data.memoryBytes)
            }

            // 按 CPU 排序取 Top 10
            let cpuSorted = aggregated.sorted { $0.cpuUsage > $1.cpuUsage }.prefix(10)
            // 按内存排序取 Top 10
            let memSorted = aggregated.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(10)

            DispatchQueue.main.async {
                self.topCPUProcesses = Array(cpuSorted)
                self.topMemoryProcesses = Array(memSorted)
            }
        }
    }

    private func parsePSOutput(_ output: String) -> [RawProcess] {
        var results: [RawProcess] = []
        let lines = output.split(separator: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)

            guard parts.count >= 4 else { continue }

            if let pid = Int32(parts[0]),
               let rssKB = Double(parts[1]),
               let cpu = Double(parts[2]) {
                let name = parts[3...].joined(separator: " ")
                results.append(RawProcess(pid: pid, rssKB: rssKB, cpuUsage: cpu, rawName: name))
            }
        }

        return results
    }
}

// MARK: - proc_pid_rusage 获取 phys_footprint

/// 使用 proc_pid_rusage 系统调用获取进程的物理内存占用（phys_footprint），
/// 这是活动监视器使用的内存指标，比 ps 的 rss 更准确（包含压缩内存页等）。
private func getPhysFootprint(pid: Int32) -> UInt64 {
    var info = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &info) { ptr in
        ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rustPtr in
            proc_pid_rusage(pid, RUSAGE_INFO_V4, rustPtr)
        }
    }
    if result == 0 {
        return info.ri_phys_footprint
    }
    return 0
}

// MARK: - 进程名提取

/// 从进程完整路径中提取应用名称：
/// 1. 如果路径包含 `.app/`，提取 `.app` 前面的名称部分（如 `IntelliJ IDEA.app` -> `IntelliJ IDEA`）
/// 2. 否则取路径最后一个 `/` 后面的文件名（如 `/usr/sbin/coreaudiod` -> `coreaudiod`）
private func extractAppName(from path: String) -> String {
    // 尝试从 .app 路径提取应用名
    if let range = path.range(of: ".app") {
        let beforeApp = path[..<range.lowerBound]
        if let lastSlash = beforeApp.lastIndex(of: "/") {
            return String(beforeApp[beforeApp.index(after: lastSlash)...])
        }
        return String(beforeApp)
    }
    // fallback: 取最后的文件名
    return (path as NSString).lastPathComponent
}
