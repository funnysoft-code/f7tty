import AppKit
import CoreGraphics
import Darwin

var cpu = host_cpu_load_info()
var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
let status = withUnsafeMutablePointer(to: &cpu) { ptr in
    ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
    }
}
let mode = CGDisplayCopyDisplayMode(CGMainDisplayID())
let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
    .filter { ($0[kCGWindowLayer as String] as? Int) == 0 }
    .map { w in ["owner": w[kCGWindowOwnerName as String] ?? "", "pid": w[kCGWindowOwnerPID as String] ?? 0,
                 "bounds": w[kCGWindowBounds as String] ?? [:]] as [String: Any] }
let data = try JSONSerialization.data(withJSONObject: [
    "frontmostPID": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0,
    "frontmost": NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown",
    "windows": windows,
    "display": ["width": mode?.width ?? 0, "height": mode?.height ?? 0, "refreshHz": mode?.refreshRate ?? 0],
    "cpuStatus": status,
    "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
    "cpuTicks": [cpu.cpu_ticks.0, cpu.cpu_ticks.1, cpu.cpu_ticks.2, cpu.cpu_ticks.3]
], options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
