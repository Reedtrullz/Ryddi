import Foundation

public enum TrustReadinessSeverity: String, Codable, CaseIterable, Hashable, Sendable {
    case ready
    case info
    case warning
    case blocked

    public var label: String {
        switch self {
        case .ready: "Ready"
        case .info: "Info"
        case .warning: "Review"
        case .blocked: "Blocked"
        }
    }
}

public struct TrustReadinessAction: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let severity: TrustReadinessSeverity

    public init(id: String, title: String, detail: String, severity: TrustReadinessSeverity) {
        self.id = id
        self.title = title
        self.detail = detail
        self.severity = severity
    }
}

public struct LatestPlanSummary: Codable, Hashable, Sendable {
    public let id: String
    public let createdAt: Date
    public let mode: String
    public let itemCount: Int
    public let selectedCount: Int
    public let expectedImmediateReclaim: Int64

    public init(plan: ReclaimPlan) {
        self.id = plan.id
        self.createdAt = plan.createdAt
        self.mode = plan.mode
        self.itemCount = plan.items.count
        self.selectedCount = plan.items.filter(\.selected).count
        self.expectedImmediateReclaim = plan.expectedImmediateReclaim
    }
}

public struct LatestReceiptSummary: Codable, Hashable, Sendable {
    public let id: String
    public let createdAt: Date
    public let mode: String
    public let actionCount: Int
    public let dryRunCount: Int
    public let doneCount: Int
    public let skippedCount: Int
    public let errorCount: Int

    public init(receipt: ExecutionReceipt) {
        self.id = receipt.id
        self.createdAt = receipt.createdAt
        self.mode = receipt.mode
        self.actionCount = receipt.actions.count
        self.dryRunCount = receipt.actions.filter { $0.status == "dry-run" }.count
        self.doneCount = receipt.actions.filter { $0.status == "done" }.count
        self.skippedCount = receipt.actions.filter { $0.status == "skipped" }.count
        self.errorCount = receipt.errors.count + receipt.actions.filter { $0.status == "error" }.count
    }
}

public struct TrustReadinessReport: Codable, Hashable, Sendable {
    public let createdAt: Date
    public let diskStatus: DiskStatusSnapshot
    public let permissionSummary: PermissionAdvisorReport
    public let latestPlanSummary: LatestPlanSummary?
    public let latestReceiptSummary: LatestReceiptSummary?
    public let automationInstalled: Bool
    public let signingState: String
    public let runtimeReleaseTrustReport: RuntimeReleaseTrustReport?
    public let releaseTrustEvidence: ReleaseTrustEvidence
    public let nextActionCounts: [String: Int]
    public let scanCoverage: ScanCoverage?
    public let recommendedActions: [TrustReadinessAction]
    public let nonClaims: [String]

    public init(
        createdAt: Date = Date(),
        diskStatus: DiskStatusSnapshot,
        permissionSummary: PermissionAdvisorReport,
        latestPlanSummary: LatestPlanSummary?,
        latestReceiptSummary: LatestReceiptSummary?,
        automationInstalled: Bool,
        signingState: String,
        runtimeReleaseTrustReport: RuntimeReleaseTrustReport? = nil,
        releaseTrustEvidence: ReleaseTrustEvidence = .missingManifest(path: nil),
        nextActionCounts: [String: Int] = [:],
        scanCoverage: ScanCoverage? = nil,
        recommendedActions: [TrustReadinessAction],
        nonClaims: [String]
    ) {
        self.createdAt = createdAt
        self.diskStatus = diskStatus
        self.permissionSummary = permissionSummary
        self.latestPlanSummary = latestPlanSummary
        self.latestReceiptSummary = latestReceiptSummary
        self.automationInstalled = automationInstalled
        self.signingState = signingState
        self.runtimeReleaseTrustReport = runtimeReleaseTrustReport
        self.releaseTrustEvidence = releaseTrustEvidence
        self.nextActionCounts = nextActionCounts
        self.scanCoverage = scanCoverage
        self.recommendedActions = recommendedActions
        self.nonClaims = nonClaims
    }
}

public enum TrustReadinessBuilder {
    public static func build(
        diskStatus: DiskStatusSnapshot = DiskStatusReader().snapshot(),
        permissionSummary: PermissionAdvisorReport,
        findings: [Finding] = [],
        latestPlan: ReclaimPlan? = nil,
        latestReceipt: ExecutionReceipt? = nil,
        automationInstalled: Bool = false,
        signingState: String = "Unsigned local debug or source build",
        runtimeReleaseTrustReport: RuntimeReleaseTrustReport? = nil,
        releaseTrustEvidence: ReleaseTrustEvidence = .missingManifest(path: nil),
        scanCoverage: ScanCoverage? = nil,
        now: Date = Date()
    ) -> TrustReadinessReport {
        var actions: [TrustReadinessAction] = []

        switch diskStatus.pressure {
        case .healthy:
            actions.append(TrustReadinessAction(
                id: "disk.healthy",
                title: "Disk pressure looks acceptable",
                detail: diskStatus.statusLine,
                severity: .ready
            ))
        case .warning:
            actions.append(TrustReadinessAction(
                id: "disk.warning",
                title: "Review disk pressure",
                detail: "Free space is low; use report-first scans before reclaiming anything.",
                severity: .warning
            ))
        case .critical:
            actions.append(TrustReadinessAction(
                id: "disk.critical",
                title: "Stop long build loops",
                detail: "Free space is critically low. Review safe candidates before running more heavy work.",
                severity: .blocked
            ))
        case .unknown:
            actions.append(TrustReadinessAction(
                id: "disk.unknown",
                title: "Disk status unavailable",
                detail: "Ryddi could not read the target volume's free-space state.",
                severity: .warning
            ))
        }

        if permissionSummary.needsFullDiskAccessReview {
            actions.append(TrustReadinessAction(
                id: "permissions.review-full-disk-access",
                title: "Review Full Disk Access",
                detail: permissionSummary.coverageSummary,
                severity: permissionSummary.coverageLevel == .blocked ? .blocked : .warning
            ))
        }

        if let scanCoverage, scanCoverage.state != .complete {
            actions.append(TrustReadinessAction(
                id: "scan.coverage-\(scanCoverage.state.rawValue)",
                title: scanCoverage.state == .bounded ? "Targeted rescan recommended" : "Scan coverage is degraded",
                detail: scanCoverage.nonClaim,
                severity: scanCoverage.state == .degraded ? .warning : .info
            ))
        }

        if !findings.isEmpty, latestPlan == nil {
            actions.append(TrustReadinessAction(
                id: "plan.create-dry-run",
                title: "Create a dry-run plan",
                detail: "Findings exist, but no current plan summary was supplied.",
                severity: .warning
            ))
        }

        if let latestReceipt {
            if latestReceipt.mode == ExecutionMode.dryRun.rawValue {
                actions.append(TrustReadinessAction(
                    id: "receipt.dry-run-only",
                    title: "Dry-run receipt only",
                    detail: "The latest receipt proves a preview, not executed cleanup.",
                    severity: .info
                ))
            } else if !latestReceipt.errors.isEmpty {
                actions.append(TrustReadinessAction(
                    id: "receipt.errors",
                    title: "Review latest receipt errors",
                    detail: "\(latestReceipt.errors.count) error(s) were recorded.",
                    severity: .warning
                ))
            } else {
                actions.append(TrustReadinessAction(
                    id: "receipt.complete",
                    title: "Latest receipt has no errors",
                    detail: "\(latestReceipt.actions.count) action(s) recorded.",
                    severity: .ready
                ))
            }
        }

        actions.append(TrustReadinessAction(
            id: "automation.report-only",
            title: automationInstalled ? "Report-only automation installed" : "Automation not installed",
            detail: automationInstalled ? "Scheduled work is limited to report or plan commands." : "No LaunchAgent plist was detected.",
            severity: automationInstalled ? .ready : .info
        ))

        if let runtimeReleaseTrustReport {
            actions.append(TrustReadinessAction(
                id: "release.runtime-signature",
                title: "Runtime signature",
                detail: runtimeReleaseTrustReport.signatureSummary,
                severity: signatureSeverity(runtimeReleaseTrustReport.signature.state)
            ))
            actions.append(TrustReadinessAction(
                id: "release.runtime-gatekeeper",
                title: "Local Gatekeeper assessment",
                detail: runtimeReleaseTrustReport.gatekeeperSummary,
                severity: gatekeeperSeverity(runtimeReleaseTrustReport.gatekeeper.state)
            ))
        }

        let resolvedExternalEvidence = runtimeReleaseTrustReport?.externalManifest ?? releaseTrustEvidence
        actions.append(TrustReadinessAction(
            id: "release.external-manifest",
            title: "External release manifest",
            detail: runtimeReleaseTrustReport?.externalManifestSummary ?? resolvedExternalEvidence.summary,
            severity: resolvedExternalEvidence.state == .stapledAndAccepted ? .ready : .warning
        ))
        let resolvedSigningState = runtimeReleaseTrustReport?.signatureSummary
            ?? (resolvedExternalEvidence.state == .missingManifest ? signingState : resolvedExternalEvidence.summary)

        return TrustReadinessReport(
            createdAt: now,
            diskStatus: diskStatus,
            permissionSummary: permissionSummary,
            latestPlanSummary: latestPlan.map(LatestPlanSummary.init(plan:)),
            latestReceiptSummary: latestReceipt.map(LatestReceiptSummary.init(receipt:)),
            automationInstalled: automationInstalled,
            signingState: resolvedSigningState,
            runtimeReleaseTrustReport: runtimeReleaseTrustReport,
            releaseTrustEvidence: resolvedExternalEvidence,
            nextActionCounts: Dictionary(grouping: findings, by: { $0.reviewNextAction.rawValue })
                .mapValues(\.count),
            scanCoverage: scanCoverage,
            recommendedActions: actions,
            nonClaims: [
                "Trust readiness is a local summary of current evidence; it is not a cleanup action.",
                "Dry-run receipts prove proposed actions only; they do not prove bytes were reclaimed.",
                "Free-space and APFS accounting can differ from scan-time allocated byte estimates.",
                "Gatekeeper acceptance does not prove notarization or stapling.",
                "Release trust must be proven by the signed, notarized, stapled artifact and manifest for the distributed app."
            ]
        )
    }

    private static func signatureSeverity(_ state: RuntimeTrustState) -> TrustReadinessSeverity {
        switch state {
        case .developerIDSigned: .ready
        case .unsigned, .unavailable, .malformed: .warning
        case .gatekeeperAccepted: .ready
        case .gatekeeperRejectedUnnotarized, .rejected: .blocked
        }
    }

    private static func gatekeeperSeverity(_ state: RuntimeTrustState) -> TrustReadinessSeverity {
        switch state {
        case .gatekeeperAccepted: .ready
        case .unavailable, .malformed, .unsigned, .developerIDSigned: .warning
        case .gatekeeperRejectedUnnotarized, .rejected: .blocked
        }
    }
}
