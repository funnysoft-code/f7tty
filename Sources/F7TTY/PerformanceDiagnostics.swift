import Foundation

/// Opt-in counters. No timers or output are added to normal terminal sessions.
@MainActor
enum PerformanceDiagnostics {
    static let enabled = ProcessInfo.processInfo.environment["F7TTY_PROFILE"] == "1"
    static let benchmark = CommandLine.arguments.contains("--benchmark")
    private(set) static var counts: [String: Int] = [:]

    static func record(_ event: String) {
        guard enabled else { return }
        let count = counts[event, default: 0]
        if count < Int.max { counts[event] = count + 1 }
    }

    static func experiment(_ name: String) -> Bool {
        benchmark && ProcessInfo.processInfo.environment[name] == "1"
    }
}
