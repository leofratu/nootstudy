import os

/// Lightweight signposts for Instruments so future profiling can isolate hot paths.
nonisolated enum PerformanceSignposts {
    nonisolated static let subsystem = "com.nootstudy.ibvault"
    nonisolated static let category = "Performance"
    nonisolated static let signposter = OSSignposter(subsystem: subsystem, category: category)

    nonisolated static func formatterInterval(_ name: StaticString = "formatter.parse") -> OSSignpostIntervalState {
        signposter.beginInterval(name)
    }

    nonisolated static func queueRefreshInterval() -> OSSignpostIntervalState {
        signposter.beginInterval("reviewQueue.refresh")
    }

    nonisolated static func dashboardEvidenceInterval() -> OSSignpostIntervalState {
        signposter.beginInterval("dashboard.evidence")
    }
}
