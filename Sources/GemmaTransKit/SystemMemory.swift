import Foundation
import Darwin

public enum SystemMemory {
    public static func physical() -> UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    /// 可回收给新分配的内存（free + inactive 页）。读取失败返回 nil。
    public static func available() -> UInt64? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pageSize = UInt64(sysconf(_SC_PAGESIZE))  // vm_kernel_page_size 是全局 var，Swift 6 并发检查不允许
        return (UInt64(info.free_count) + UInt64(info.inactive_count)) * pageSize
    }
}
