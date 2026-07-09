import Foundation

public enum GuidedWorkflowStep: String, Codable, CaseIterable, Hashable, Sendable {
    case reviewPermissions
    case scan
    case reviewFindings
    case createPlan
    case dryRun
    case reclaimOrExport
    case recovery
}

public enum GuidedWorkflowActionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case openPermissions
    case runScan
    case openReviewQueues
    case createSafePlan
    case runDryRun
    case reclaimSafely
    case exportReport
    case openRecovery
}

public struct GuidedWorkflowAction: Codable, Hashable, Sendable {
    public let kind: GuidedWorkflowActionKind
    public let title: String
    public let reason: String
    public let estimatedBytes: Int64
    public let isDestructive: Bool

    public init(
        kind: GuidedWorkflowActionKind,
        title: String,
        reason: String,
        estimatedBytes: Int64 = 0,
        isDestructive: Bool = false
    ) {
        self.kind = kind
        self.title = title
        self.reason = reason
        self.estimatedBytes = estimatedBytes
        self.isDestructive = isDestructive
    }
}

public struct GuidedWorkflowReport: Codable, Hashable, Sendable {
    public let currentStep: GuidedWorkflowStep
    public let primaryAction: GuidedWorkflowAction
    public let secondaryActions: [GuidedWorkflowAction]
    public let safetyTotals: [ReviewNextAction: Int64]
    public let explanation: String

    public init(
        currentStep: GuidedWorkflowStep,
        primaryAction: GuidedWorkflowAction,
        secondaryActions: [GuidedWorkflowAction],
        safetyTotals: [ReviewNextAction: Int64],
        explanation: String
    ) {
        self.currentStep = currentStep
        self.primaryAction = primaryAction
        self.secondaryActions = secondaryActions
        self.safetyTotals = safetyTotals
        self.explanation = explanation
    }
}

public struct GuidedWorkflowInput: Sendable {
    public let diskStatus: DiskStatusSnapshot
    public let permissionSummary: PermissionAdvisorReport
    public let findings: [Finding]
    public let latestPlan: ReclaimPlan?
    public let latestReceipt: ExecutionReceipt?
    public let trustReadiness: TrustReadinessReport?

    public init(
        diskStatus: DiskStatusSnapshot,
        permissionSummary: PermissionAdvisorReport,
        findings: [Finding],
        latestPlan: ReclaimPlan?,
        latestReceipt: ExecutionReceipt?,
        trustReadiness: TrustReadinessReport?
    ) {
        self.diskStatus = diskStatus
        self.permissionSummary = permissionSummary
        self.findings = findings
        self.latestPlan = latestPlan
        self.latestReceipt = latestReceipt
        self.trustReadiness = trustReadiness
    }
}

public enum GuidedWorkflowBuilder {
    public static func build(input: GuidedWorkflowInput) -> GuidedWorkflowReport {
        let safetyTotals = safetyTotals(for: input.findings)

        if input.permissionSummary.coverageLevel != .complete {
            return GuidedWorkflowReport(
                currentStep: .reviewPermissions,
                primaryAction: GuidedWorkflowAction(
                    kind: .openPermissions,
                    title: "Review Access",
                    reason: "\(input.permissionSummary.readableCount) of \(input.permissionSummary.totalCount) configured scopes are readable."
                ),
                secondaryActions: [
                    GuidedWorkflowAction(
                        kind: .runScan,
                        title: "Scan Anyway",
                        reason: "Use currently readable locations without treating missing coverage as clean."
                    )
                ],
                safetyTotals: safetyTotals,
                explanation: "Scan coverage is degraded, so Ryddi should review access before promising cleanup results."
            )
        }

        if input.findings.isEmpty {
            return GuidedWorkflowReport(
                currentStep: .scan,
                primaryAction: GuidedWorkflowAction(
                    kind: .runScan,
                    title: "Scan",
                    reason: "No current scan evidence is available."
                ),
                secondaryActions: [],
                safetyTotals: safetyTotals,
                explanation: "Run a scan to build current local evidence before making cleanup decisions."
            )
        }

        guard let latestPlan = input.latestPlan else {
            return planningReport(findings: input.findings, safetyTotals: safetyTotals)
        }

        guard let latestReceipt = input.latestReceipt else {
            return GuidedWorkflowReport(
                currentStep: .dryRun,
                primaryAction: GuidedWorkflowAction(
                    kind: .runDryRun,
                    title: "Dry Run",
                    reason: "Preview the current plan before cleanup.",
                    estimatedBytes: latestPlan.expectedImmediateReclaim
                ),
                secondaryActions: [
                    GuidedWorkflowAction(
                        kind: .exportReport,
                        title: "Export Report",
                        reason: "Share evidence without changing files."
                    )
                ],
                safetyTotals: safetyTotals,
                explanation: "A plan exists. Dry-run it before any reclaim action."
            )
        }

        if latestReceipt.mode == ExecutionMode.dryRun.rawValue {
            return postDryRunReport(plan: latestPlan, receipt: latestReceipt, safetyTotals: safetyTotals)
        }

        return GuidedWorkflowReport(
            currentStep: .recovery,
            primaryAction: GuidedWorkflowAction(
                kind: .openRecovery,
                title: "Review Recovery",
                reason: "The latest receipt records performed cleanup; review recovery and audit history."
            ),
            secondaryActions: [
                GuidedWorkflowAction(
                    kind: .exportReport,
                    title: "Export Receipt",
                    reason: "Save local evidence of the completed action."
                )
            ],
            safetyTotals: safetyTotals,
            explanation: "Cleanup has been executed. Recovery and audit review are the safest next step."
        )
    }

    private static func planningReport(
        findings: [Finding],
        safetyTotals: [ReviewNextAction: Int64]
    ) -> GuidedWorkflowReport {
        let safeBytes = safetyTotals[.safeMaintenance, default: 0]
        if safeBytes > 0 {
            return GuidedWorkflowReport(
                currentStep: .createPlan,
                primaryAction: GuidedWorkflowAction(
                    kind: .createSafePlan,
                    title: "Create Safe Plan",
                    reason: "Auto-safe evidence is available for a dry-run plan.",
                    estimatedBytes: safeBytes
                ),
                secondaryActions: [
                    GuidedWorkflowAction(
                        kind: .openReviewQueues,
                        title: "Review Queues",
                        reason: "Inspect protected and conditional items before widening scope."
                    )
                ],
                safetyTotals: safetyTotals,
                explanation: "Ryddi can build a dry-run plan from safe maintenance findings while keeping review-heavy storage protected."
            )
        }

        return GuidedWorkflowReport(
            currentStep: .reviewFindings,
            primaryAction: GuidedWorkflowAction(
                kind: .openReviewQueues,
                title: "Review Findings",
                reason: "Findings need human review before planning.",
                estimatedBytes: totalBytes(findings)
            ),
            secondaryActions: [
                GuidedWorkflowAction(
                    kind: .exportReport,
                    title: "Export Report",
                    reason: "Preserve evidence without changing files."
                )
            ],
            safetyTotals: safetyTotals,
            explanation: "Ryddi found storage, but none of it is ready for an automatic safe-maintenance plan."
        )
    }

    private static func postDryRunReport(
        plan: ReclaimPlan,
        receipt: ExecutionReceipt,
        safetyTotals: [ReviewNextAction: Int64]
    ) -> GuidedWorkflowReport {
        if receipt.errors.isEmpty, plan.expectedImmediateReclaim > 0, plan.items.contains(where: \.selected) {
            return GuidedWorkflowReport(
                currentStep: .reclaimOrExport,
                primaryAction: GuidedWorkflowAction(
                    kind: .reclaimSafely,
                    title: "Reclaim Safely",
                    reason: "A dry-run receipt exists for the selected safe-maintenance plan.",
                    estimatedBytes: plan.expectedImmediateReclaim,
                    isDestructive: true
                ),
                secondaryActions: [
                    GuidedWorkflowAction(
                        kind: .exportReport,
                        title: "Export Dry Run",
                        reason: "Keep evidence instead of reclaiming now."
                    ),
                    GuidedWorkflowAction(
                        kind: .openReviewQueues,
                        title: "Review Queues",
                        reason: "Inspect skipped, protected, and conditional items."
                    )
                ],
                safetyTotals: safetyTotals,
                explanation: "Dry-run evidence exists. Ryddi can reclaim only the selected local plan after final safety revalidation."
            )
        }

        return GuidedWorkflowReport(
            currentStep: .reclaimOrExport,
            primaryAction: GuidedWorkflowAction(
                kind: .exportReport,
                title: "Export Report",
                reason: "The dry-run does not prove a clean reclaim path."
            ),
            secondaryActions: [
                GuidedWorkflowAction(
                    kind: .openReviewQueues,
                    title: "Review Queues",
                    reason: "Resolve skipped or blocked items before cleanup."
                )
            ],
            safetyTotals: safetyTotals,
            explanation: "The latest dry-run should be reviewed before any cleanup action."
        )
    }

    private static func safetyTotals(for findings: [Finding]) -> [ReviewNextAction: Int64] {
        findings.reduce(into: [:]) { totals, finding in
            totals[finding.reviewNextAction, default: 0] += finding.allocatedSize
        }
    }

    private static func totalBytes(_ findings: [Finding]) -> Int64 {
        findings.reduce(0) { $0 + $1.allocatedSize }
    }
}
