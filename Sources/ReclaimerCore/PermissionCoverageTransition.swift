import Foundation

public struct PermissionCoverageTransition: Hashable, Sendable {
    public let previous: PermissionAdvisorReport
    public let current: PermissionAdvisorReport

    public init(previous: PermissionAdvisorReport, current: PermissionAdvisorReport) {
        self.previous = previous
        self.current = current
    }

    public var coverageChanged: Bool {
        previous.coverageLevel != current.coverageLevel
            || previous.readableCount != current.readableCount
            || previous.deniedCount != current.deniedCount
            || previous.missingCount != current.missingCount
            || previous.unknownCount != current.unknownCount
    }

    public static func refresh(
        previous: PermissionAdvisorReport,
        scopes: [ScanScope],
        reporter: ([ScanScope]) -> PermissionAdvisorReport = { PermissionAdvisor.report(scopes: $0) }
    ) -> PermissionCoverageTransition {
        PermissionCoverageTransition(previous: previous, current: reporter(scopes))
    }
}
