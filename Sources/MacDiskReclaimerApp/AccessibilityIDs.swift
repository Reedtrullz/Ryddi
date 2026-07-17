import ReclaimerCore

enum AccessibilityID {
    static let sidebar = "dashboard-sidebar"
    static let scan = "scan-button"
    static let scanProgress = "scan-progress"
    static let cancelScan = "cancel-scan-button"
    static let scanMode = "scan-mode-picker"
    static let savedScope = "saved-scope-picker"
    static let cleanupFlow = "cleanup-flow"
    static let flowStatus = "cleanup-flow-status"
    static let summaryPrimaryAction = "summary.primary-action"
    static let summaryScan = "summary.scan-button"
    static let summaryVerifyCleanup = "summary.verify-cleanup-button"
    static let summaryPlan = "summary.plan-button"
    static let summaryDryRun = "summary.dry-run-button"
    static let summaryManualReview = "summary.manual-review-button"
    static let summaryReclaim = "summary.reclaim-button"
    static let trashReviewed = "trash-confirmation.reviewed"
    static let trashConfirm = "trash-confirmation.confirm"
    static let trashCancel = "trash-confirmation.cancel"
    static let trashResult = "trash-execution.result"

    static func sidebarSection(_ section: DashboardSection) -> String {
        "sidebar.\(section.rawValue)"
    }

    static func sidebarDestination(_ destination: DashboardPrimaryDestination) -> String {
        "sidebar.\(destination.rawValue)"
    }

    static func queue(_ id: ReviewQueueID) -> String {
        "queue.\(id.rawValue)"
    }
}
