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
            // 避免 ps 在管道中截断长 comm 字段
            task.environment = Foundation.ProcessInfo.processInfo.environment.merging(["COLUMNS": "1000"], uniquingKeysWith: { current, _ in current })

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
                return ProcessInfo(pid: raw.pid, name: extractAppName(pid: raw.pid, from: raw.rawName), cpuUsage: raw.cpuUsage, memoryUsage: memoryPercent, memoryBytes: memBytes)
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
        var i = 0

        while i < lines.count {
            var line = String(lines[i])

            // 处理 ps 的续行：下一行不以空格开头且字段数不足4时，拼接回来
            while i + 1 < lines.count {
                let next = String(lines[i + 1])
                let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                let nextParts = nextTrimmed.split(separator: " ", omittingEmptySubsequences: true)
                if nextParts.count < 4 && !nextTrimmed.hasPrefix(" ") {
                    line += next
                    i += 1
                } else {
                    break
                }
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)

            guard parts.count >= 4 else { i += 1; continue }

            if let pid = Int32(parts[0]),
               let rssKB = Double(parts[1]),
               let cpu = Double(parts[2]) {
                let name = parts[3...].joined(separator: " ")
                results.append(RawProcess(pid: pid, rssKB: rssKB, cpuUsage: cpu, rawName: name))
            }
            i += 1
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

/// 常见无意义目录名，在拼接短进程名时跳过
private let skipDirs: Set<String> = [
    "bin", "sbin", "MacOS", "Contents", "Helpers", "Versions",
    "Frameworks", "Resources", "Support", "usr", "System", "Library",
    "Applications", "PrivateFrameworks", "CoreServices", "PlugIns",
    "SharedFrameworks", "libexec", "include", "lib", "local", "opt",
    "Cellar", "Homebrew", "node_modules", "Caches", "Logs",
]

/// 从进程信息中提取应用名称：
/// 1. 先用 proc_pidpath 获取进程完整可执行路径
/// 2. 如果路径包含 `.app/`，提取 `.app` 前面的应用名
/// 3. 如果提取后的名称过短（≤3 字符），沿路径向上找第一个有意义的目录拼接
/// 4. 若仍无意义，尝试 proc_name 作为备选
/// 5. 否则取路径最后一个 `/` 后面的文件名
private func extractAppName(pid: Int32, from comm: String) -> String {
    // 通过 proc_pidpath 获取进程真实可执行路径
    var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(MAXPATHLEN))
    let executablePath = pathLen > 0 ? String(cString: pathBuffer) : ""

    // 尝试从 .app 路径提取应用名（严格匹配 .app/ 或末尾的 .app，避免误匹配 .apple 等）
    if let range = executablePath.range(of: ".app/") {
        let beforeApp = executablePath[..<range.lowerBound]
        if let lastSlash = beforeApp.lastIndex(of: "/") {
            return String(beforeApp[beforeApp.index(after: lastSlash)...])
        }
        return String(beforeApp)
    } else if executablePath.hasSuffix(".app") {
        let beforeApp = executablePath.dropLast(4)
        if let lastSlash = beforeApp.lastIndex(of: "/") {
            return String(beforeApp[beforeApp.index(after: lastSlash)...])
        }
        return String(beforeApp)
    }

    // 取最后的文件名
    let name = executablePath.isEmpty ? comm : (executablePath as NSString).lastPathComponent

    // 若名称过短（≤3 字符），沿路径向上找有意义的目录拼接
    if name.count <= 3 {
        let components = executablePath.split(separator: "/")
        // 从倒数第二个开始往前遍历，跳过无意义目录
        for i in (0..<(components.count - 1)).reversed() {
            let dir = String(components[i])
            if !skipDirs.contains(dir) && dir.count > 2 {
                return "\(dir)/\(name)"
            }
        }

        // 路径中全是目录壳，尝试 proc_name API 作为备选
        var nameBuf = [CChar](repeating: 0, count: 256)
        let nameLen = proc_name(pid, &nameBuf, 256)
        if nameLen > 0 {
            let procName = String(cString: nameBuf)
            if procName.count > 3 && procName != comm {
                return procName
            }
        }
    }

    // 对 com.apple.xxx.yyy 格式的系统进程名，提取最后一段服务名
    if name.hasPrefix("com.apple.") {
        let suffix = String(name.dropFirst("com.apple.".count))
        if let lastDot = suffix.lastIndex(of: ".") {
            let serviceName = String(suffix[suffix.index(after: lastDot)...])
            if serviceName.count > 2 {
                return serviceName
            }
        }
        return suffix
    }

    return name
}
