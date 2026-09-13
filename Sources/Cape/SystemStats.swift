import Foundation
import Darwin

/// Live CPU / RAM / storage usage, sampled a couple of times per second.
final class SystemStats: ObservableObject {
    @Published private(set) var cpu: Double = 0          // 0...1
    @Published private(set) var ramUsed: Double = 0      // bytes
    @Published private(set) var ramTotal: Double = 0
    @Published private(set) var diskUsed: Double = 0
    @Published private(set) var diskTotal: Double = 0

    private var previousCPU: host_cpu_load_info?
    private var timer: Timer?

    var ramFraction: Double { ramTotal > 0 ? ramUsed / ramTotal : 0 }
    var diskFraction: Double { diskTotal > 0 ? diskUsed / diskTotal : 0 }

    init() {
        ramTotal = Double(ProcessInfo.processInfo.physicalMemory)
        sample()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func sample() {
        cpu = sampleCPU()
        let ram = sampleRAM(); ramUsed = ram.used; ramTotal = ram.total
        let disk = sampleDisk(); diskUsed = disk.used; diskTotal = disk.total
    }

    private func sampleCPU() -> Double {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return cpu }
        defer { previousCPU = info }
        guard let prev = previousCPU else { return 0 }

        let user = Double(info.cpu_ticks.0 &- prev.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1 &- prev.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 &- prev.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 &- prev.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return cpu }
        return (user + system + nice) / total
    }

    private func sampleRAM() -> (used: Double, total: Double) {
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (ramUsed, total) }
        let page = Double(vm_page_size)
        // Resident "used" = active + wired, matching htop/btop. We deliberately
        // leave out the compressor's footprint and inactive/cached file pages, so
        // this reads lower than Activity Monitor's "Memory Used" (which adds the
        // compressed pages on top).
        let used = (Double(stats.active_count) + Double(stats.wire_count)) * page
        return (used, total)
    }

    private func sampleDisk() -> (used: Double, total: Double) {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/") else {
            return (diskUsed, diskTotal)
        }
        let total = (attrs[.systemSize] as? NSNumber)?.doubleValue ?? 0
        let free = (attrs[.systemFreeSize] as? NSNumber)?.doubleValue ?? 0
        return (max(0, total - free), total)
    }
}

/// Human-readable gigabytes.
func formatGB(_ bytes: Double) -> String {
    String(format: "%.1f GB", bytes / 1_073_741_824)
}
