import Foundation

/// Resident footprint, for confirming on device what the cache budget and
/// the thumbnail tier actually bought. Jetsam measures `phys_footprint`,
/// not `resident_size` — reporting anything else would flatter the numbers.
///
/// Debug-only by construction: `log(_:)` compiles to nothing in release.
enum MemoryProbe {

    /// Megabytes of physical footprint, or nil if the kernel call fails.
    static var footprintMB: Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.phys_footprint) / 1_048_576
    }

    static func log(_ label: String) {
        #if DEBUG
        guard let mb = footprintMB else { return }
        print(String(format: "[mem] %-22@ %7.1f MB", label as NSString, mb))
        #endif
    }
}
