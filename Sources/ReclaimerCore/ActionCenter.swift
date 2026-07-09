import Foundation

public enum ActionCenterActionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case grantAccess
    case runScan
    case reviewQueue
    case runDryRun
    case executeSafePlan
    case quitApp
    case useNativeTool
}

public struct ActionCenterAction: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let kind: ActionCenterActionKind
    public let title: String
    public let reason: String
    public let priority: Int
    public let estimatedReclaimBytes: Int64
    public let count: Int
    public let isDestructive: Bool
    public let sourceIDs: [String]

    public init(
        id: String,
        kind: ActionCenterActionKind,
        title: String,
        reason: String,
        priority: Int,
        estimatedReclaimBytes: Int64 = 0,
        count: Int = 0,
        isDestructive: Bool = false,
        sourceIDs: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.reason = reason
        self.priority = priority
        self.estimatedReclaimBytes = max(0, estimatedReclaimBytes)
        self.count = max(0, count)
        self.isDestructive = isDestructive
        self.sourceIDs = sourceIDs
    }
}

public struct ActionCenterReport: Codable, Hashable, Sendable {
    public let generatedAt: Date
    public let primaryAction: ActionCenterAction?
    public let actions: [ActionCenterAction]
    public let nonClaims: [String]

    public init(
        generatedAt: Date,
        actions: [ActionCenterAction],
        nonClaims: [String] = ActionCenterBuilder.defaultNonClaims
    ) {
        let sortedActions = ActionCenterBuilder.sorted(actions)
        self.generatedAt = generatedAt
        self.primaryAction = sortedActions.first
        self.actions = sortedActions
        self.nonClaims = nonClaims
    }
}

public struct ActionCenterInput: Sendable {
    public let permissionReport: PermissionAdvisorReport
    public let latestScanSession: ScanSession?
    public let findings: [Finding]
    public let currentPlan: ReclaimPlan?
    public let latestExecutionReceipt: ExecutionReceipt?
    public let reviewQueueReport: ReviewQueueReport?
    public let activeFileReviewReport: ActiveFileReviewReport?
    public let browserCacheReport: BrowserCacheReviewReport?
    public let packageCacheReport: PackageCacheReviewReport?
    public let latestNativeToolExecutionReceipt: NativeToolExecutionReceipt?
    public let sessionHistoryWarnings: [AuditStoreScanSessionWarning]
    public let generatedAt: Date

    public init(
        permissionReport: PermissionAdvisorReport,
        latestScanSession: ScanSession?,
        findings: [Finding] = [],
        currentPlan: ReclaimPlan? = nil,
        latestExecutionReceipt: ExecutionReceipt? = nil,
        reviewQueueReport: ReviewQueueReport? = nil,
        activeFileReviewReport: ActiveFileReviewReport? = nil,
        browserCacheReport: BrowserCacheReviewReport? = nil,
        packageCacheReport: PackageCacheReviewReport? = nil,
        latestNativeToolExecutionReceipt: NativeToolExecutionReceipt? = nil,
        sessionHistoryWarnings: [AuditStoreScanSessionWarning] = [],
        generatedAt: Date = Date()
    ) {
        self.permissionReport = permissionReport
        self.latestScanSession = latestScanSession
        self.findings = findings
        self.currentPlan = currentPlan
        self.latestExecutionReceipt = latestExecutionReceipt
        self.reviewQueueReport = reviewQueueReport
        self.activeFileReviewReport = activeFileReviewReport
        self.browserCacheReport = browserCacheReport
        self.packageCacheReport = packageCacheReport
        self.latestNativeToolExecutionReceipt = latestNativeToolExecutionReceipt
        self.sessionHistoryWarnings = sessionHistoryWarnings
        self.generatedAt = generatedAt
    }
}

public enum ActionCenterBuilder {
    public static let defaultNonClaims = [
        "Building the action center does not perform cleanup or modify files.",
        "Estimated bytes are not a promise of exact APFS free-space gain.",
        "Protected data remains review-only."
    ]

    public static func build(input: ActionCenterInput) -> ActionCenterReport {
        var actions: [ActionCenterAction] = []

        if let action = permissionAction(from: input.permissionReport) {
            actions.append(action)
        }
        if let action = scanAction(from: input.latestScanSession) {
            actions.append(action)
        }
        actions.append(contentsOf: quitActions(
            activeFileReport: input.activeFileReviewReport,
            browserCacheReport: input.browserCacheReport
        ))
        if let action = nativeToolReceiptAction(from: input.latestNativeToolExecutionReceipt) {
            actions.append(action)
        }
        actions.append(contentsOf: nativeToolActions(from: input.packageCacheReport))
        if let action = planAction(
            plan: input.currentPlan,
            receipt: input.latestExecutionReceipt,
            session: input.latestScanSession
        ) {
            actions.append(action)
        }
        if let action = reviewAction(input: input) {
            actions.append(action)
        }

        return ActionCenterReport(
            generatedAt: input.generatedAt,
            actions: actions,
            nonClaims: nonClaims(sessionHistoryWarnings: input.sessionHistoryWarnings)
        )
    }

    public static func sorted(_ actions: [ActionCenterAction]) -> [ActionCenterAction] {
        actions.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            if lhs.estimatedReclaimBytes != rhs.estimatedReclaimBytes {
                return lhs.estimatedReclaimBytes > rhs.estimatedReclaimBytes
            }
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs.title < rhs.title
        }
    }

    private static func permissionAction(from report: PermissionAdvisorReport) -> ActionCenterAction? {
        guard report.coverageLevel != .complete else {
            return nil
        }
        let blockedCount = report.deniedCount + report.missingCount + report.unknownCount
        let unavailableCount = max(blockedCount, report.unavailableScopes.count)
        return ActionCenterAction(
            id: "permissions.grant-access",
            kind: .grantAccess,
            title: "Grant Access",
            reason: "\(report.readableCount) of \(report.totalCount) configured scopes are readable.",
            priority: 1_000,
            count: unavailableCount,
            sourceIDs: ["permission-advisor"]
        )
    }

    private static func scanAction(from session: ScanSession?) -> ActionCenterAction? {
        guard shouldRunScan(session) else {
            return nil
        }
        let reason: String
        let sourceIDs: [String]
        if let session {
            reason = "The latest scan session is \(session.stage.rawValue), so fresh scan evidence is needed."
            sourceIDs = [session.id]
        } else {
            reason = "No scan session evidence is available."
            sourceIDs = []
        }
        return ActionCenterAction(
            id: "scan.run",
            kind: .runScan,
            title: "Run Scan",
            reason: reason,
            priority: 900,
            sourceIDs: sourceIDs
        )
    }

    private static func shouldRunScan(_ session: ScanSession?) -> Bool {
        guard let session else {
            return true
        }
        if [.notStarted, .invalidated].contains(session.stage) {
            return true
        }
        return session.findingDigest == nil
    }

    private static func quitActions(
        activeFileReport: ActiveFileReviewReport?,
        browserCacheReport: BrowserCacheReviewReport?
    ) -> [ActionCenterAction] {
        var actions: [ActionCenterAction] = []
        if let activeFileReport, activeFileReport.openCount > 0 {
            actions.append(ActionCenterAction(
                id: "active-files.quit-app",
                kind: .quitApp,
                title: "Quit Blocking Apps",
                reason: "Open file handles are blocking cleanup candidates.",
                priority: 850,
                estimatedReclaimBytes: activeFileReport.totalBlockedBytes,
                count: activeFileReport.openCount,
                sourceIDs: [activeFileReport.id]
            ))
        }

        guard let browserCacheReport else {
            return actions
        }
        for runtime in browserCacheReport.runtimeSummaries where runtime.state == .running {
            let summary = browserCacheReport.browserSummaries.first { $0.name == runtime.browser.label }
            let bytes = summary?.allocatedSize ?? browserCacheReport.candidateBytes
            let count = summary?.itemCount ?? browserCacheReport.itemCount
            guard bytes > 0 || count > 0 else {
                continue
            }
            actions.append(ActionCenterAction(
                id: "browser-cache.\(runtime.browser.rawValue).quit-app",
                kind: .quitApp,
                title: "Quit \(runtime.browser.label)",
                reason: "The browser is running while cache candidates are present.",
                priority: 850,
                estimatedReclaimBytes: bytes,
                count: count,
                sourceIDs: [runtime.browser.rawValue]
            ))
        }
        return actions
    }

    private static func nativeToolReceiptAction(from receipt: NativeToolExecutionReceipt?) -> ActionCenterAction? {
        guard let receipt else {
            return nil
        }
        let title: String
        let reason: String
        let priority: Int
        switch receipt.status {
        case "dry-run":
            title = "Review Native Preview"
            reason = "Saved preview for \(receipt.command.id); review the receipt before running any native cleanup."
            priority = 790
        case "blocked":
            title = "Review Blocked Native Command"
            reason = receipt.message
            priority = 785
        case "failed":
            title = "Review Failed Native Command"
            reason = receipt.message
            priority = 785
        case "done":
            title = "Review Native Result"
            reason = "Native command completed; review the receipt and APFS free-space notes before treating reclaim as exact."
            priority = 500
        default:
            title = "Review Native Receipt"
            reason = receipt.message
            priority = 700
        }
        return ActionCenterAction(
            id: "native-tool-receipt.\(receipt.id)",
            kind: .useNativeTool,
            title: title,
            reason: reason,
            priority: priority,
            count: 1,
            isDestructive: false,
            sourceIDs: [receipt.id, receipt.command.id]
        )
    }

    private static func nativeToolActions(from report: PackageCacheReviewReport?) -> [ActionCenterAction] {
        guard let report else {
            return []
        }
        return report.managerSummaries.compactMap { summary in
            guard summary.allocatedSize > 0 || summary.itemCount > 0 else {
                return nil
            }
            let manager = packageManager(named: summary.name)
            let sourceID = manager?.rawValue ?? summary.name
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
            let toolName = manager?.label ?? summary.name
            let hint = manager?.nativeCleanupHint ?? "Use the owning tool's cleanup command where available."
            return ActionCenterAction(
                id: "package-cache.\(sourceID).native-tool",
                kind: .useNativeTool,
                title: "Use \(toolName)",
                reason: hint,
                priority: 750,
                estimatedReclaimBytes: summary.allocatedSize,
                count: summary.itemCount,
                sourceIDs: [sourceID]
            )
        }
    }

    private static func packageManager(named name: String) -> PackageCacheManager? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return PackageCacheManager.allCases.first { manager in
            manager.rawValue.lowercased() == normalized || manager.label.lowercased() == normalized
        }
    }

    private static func planAction(
        plan: ReclaimPlan?,
        receipt: ExecutionReceipt?,
        session: ScanSession?
    ) -> ActionCenterAction? {
        guard let plan else {
            return nil
        }
        guard let receipt else {
            return dryRunAction(for: plan, reason: "Preview the current plan before cleanup.")
        }

        guard receipt.mode == ExecutionMode.dryRun.rawValue else {
            return nil
        }
        guard receipt.errors.isEmpty else {
            return dryRunAction(for: plan, reason: "The last dry run had errors, so the current plan needs a clean dry run.")
        }
        guard dryRunReceiptIsCurrent(plan: plan, receipt: receipt, session: session) else {
            return dryRunAction(for: plan, reason: "The current plan selection needs a fresh dry-run receipt.")
        }

        let selectedItems = plan.items.filter(\.selected)
        guard !selectedItems.isEmpty, selectedItems.allSatisfy(isSafeExecutablePlanItem) else {
            return nil
        }
        let safeBytes = selectedItems.reduce(Int64(0)) { $0 + $1.estimatedImmediateReclaim }
        guard safeBytes > 0 else {
            return nil
        }
        let dryRunBytes = receipt.actions
            .filter { $0.status == "dry-run" }
            .reduce(Int64(0)) { $0 + $1.reclaimedBytes }
        guard dryRunBytes > 0 else {
            return nil
        }

        return ActionCenterAction(
            id: "plan.\(plan.id).execute-safe",
            kind: .executeSafePlan,
            title: "Execute Safe Plan",
            reason: "A clean dry-run receipt exists for selected auto-safe trash/cache items.",
            priority: 600,
            estimatedReclaimBytes: min(safeBytes, dryRunBytes),
            count: selectedItems.count,
            isDestructive: true,
            sourceIDs: [plan.id, receipt.id]
        )
    }

    private static func dryRunAction(for plan: ReclaimPlan, reason: String) -> ActionCenterAction {
        ActionCenterAction(
            id: "plan.\(plan.id).dry-run",
            kind: .runDryRun,
            title: "Run Dry Run",
            reason: reason,
            priority: 650,
            estimatedReclaimBytes: plan.expectedImmediateReclaim,
            count: plan.items.filter(\.selected).count,
            sourceIDs: [plan.id]
        )
    }

    private static func dryRunReceiptIsCurrent(
        plan: ReclaimPlan,
        receipt: ExecutionReceipt,
        session: ScanSession?
    ) -> Bool {
        guard let session else {
            return false
        }
        guard [.dryRunReady, .reclaimReady].contains(session.stage) else {
            return false
        }
        guard session.dryRunReceiptID == receipt.id else {
            return false
        }
        guard session.planDigest == plan.id else {
            return false
        }
        return true
    }

    private static func isSafeExecutablePlanItem(_ item: ReclaimPlanItem) -> Bool {
        guard item.selected else {
            return false
        }
        guard item.finding.safetyClass == .autoSafe else {
            return false
        }
        guard [.deleteCache, .trash].contains(item.proposedAction) else {
            return false
        }
        guard !hasProtectedRuleEvidence(item.finding) else {
            return false
        }
        guard !hasProtectedPathGuardrail(item.finding) else {
            return false
        }
        return item.conditions.allSatisfy(\.isSatisfied)
    }

    private static func hasProtectedRuleEvidence(_ finding: Finding) -> Bool {
        finding.ruleMatches.contains { match in
            [.preserveByDefault, .neverTouch].contains(match.safetyClass)
        }
    }

    private static func hasProtectedPathGuardrail(_ finding: Finding) -> Bool {
        let path = URL(fileURLWithPath: finding.path).standardizedFileURL.path.lowercased()
        return path.contains("/.codex/sessions/")
            || path.hasSuffix("/.codex/sessions")
            || path.contains("/.codex/memories/")
            || path.hasSuffix("/.codex/memories")
    }

    private static func reviewAction(input: ActionCenterInput) -> ActionCenterAction? {
        let queueReport = input.reviewQueueReport ?? FindingAnalytics.reviewQueueReport(
            findings: input.findings,
            now: input.generatedAt
        )
        guard let queue = queueReport.queues
            .filter({ $0.count > 0 })
            .sorted(by: compareReviewQueues)
            .first
        else {
            return nil
        }
        return ActionCenterAction(
            id: "review-queue.\(queue.queueID.rawValue)",
            kind: .reviewQueue,
            title: "Review \(queue.title)",
            reason: queue.guidance,
            priority: 500,
            estimatedReclaimBytes: queue.allocatedSize,
            count: queue.count,
            sourceIDs: [queue.queueID.rawValue]
        )
    }

    private static func compareReviewQueues(_ lhs: ReviewQueueSummary, _ rhs: ReviewQueueSummary) -> Bool {
        if lhs.allocatedSize != rhs.allocatedSize {
            return lhs.allocatedSize > rhs.allocatedSize
        }
        if lhs.count != rhs.count {
            return lhs.count > rhs.count
        }
        return lhs.title < rhs.title
    }

    private static func nonClaims(sessionHistoryWarnings: [AuditStoreScanSessionWarning]) -> [String] {
        guard !sessionHistoryWarnings.isEmpty else {
            return defaultNonClaims
        }
        var nonClaims = defaultNonClaims
        let filenames = sessionHistoryWarnings
            .map { URL(fileURLWithPath: $0.path).lastPathComponent }
            .sorted()
        let shown = filenames.prefix(3).joined(separator: ", ")
        let extraCount = max(0, filenames.count - 3)
        let suffix = extraCount > 0 ? "\(shown), and \(extraCount) more" : shown
        nonClaims.append(
            "Scan session history is partially unreadable; unreadable audit files were excluded from action selection (\(suffix))."
        )
        return nonClaims
    }
}
