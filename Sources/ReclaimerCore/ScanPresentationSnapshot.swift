import Foundation

public struct ScanPresentationSnapshot: Hashable, Sendable {
    public let overview: ScanOverview
    public let reviewQueues: ReviewQueueReport
    public let topOffenders: TopOffenderTable
    public let largeOldReview: LargeOldReviewReport
    public let archiveReview: ArchiveReviewReport
    public let actionCenter: ActionCenterReport

    public init(
        overview: ScanOverview,
        reviewQueues: ReviewQueueReport,
        topOffenders: TopOffenderTable,
        largeOldReview: LargeOldReviewReport,
        archiveReview: ArchiveReviewReport,
        actionCenter: ActionCenterReport
    ) {
        self.overview = overview
        self.reviewQueues = reviewQueues
        self.topOffenders = topOffenders
        self.largeOldReview = largeOldReview
        self.archiveReview = archiveReview
        self.actionCenter = actionCenter
    }

    public static func build(
        findings: [Finding],
        scopes: [ScanScope],
        scanCoverage: ScanCoverage? = nil,
        permissionReport: PermissionAdvisorReport? = nil,
        latestScanSession: ScanSession? = nil,
        currentPlan: ReclaimPlan? = nil,
        latestExecutionReceipt: ExecutionReceipt? = nil,
        activeFileReviewReport: ActiveFileReviewReport? = nil,
        browserCacheReport: BrowserCacheReviewReport? = nil,
        packageCacheReport: PackageCacheReviewReport? = nil,
        latestNativeToolExecutionReceipt: NativeToolExecutionReceipt? = nil,
        sessionHistoryWarnings: [AuditStoreScanSessionWarning] = [],
        topOffenderSort: TopOffenderSort = .allocated,
        topOffenderGroup: TopOffenderGroup = .none,
        largeOldMode: LargeOldReviewMode = .all,
        largeOldSort: TopOffenderSort = .allocated,
        now: Date = Date(),
        fileManager: FileManager = .default,
        scopeAccessProbe: (any ScopeAccessProbing)? = nil
    ) -> ScanPresentationSnapshot {
        let reviewQueues = FindingAnalytics.reviewQueueReport(
            findings: findings,
            limitPerQueue: 40,
            now: now
        )
        var overview = FindingAnalytics.overview(
            findings: findings,
            scopes: scopes,
            topLimit: 20,
            now: now,
            fileManager: fileManager,
            scopeAccessSummaries: scanCoverage?.scopeAccessSummaries,
            scopeAccessProbe: scopeAccessProbe
        )
        if let scanCoverage {
            overview = overview.withScanCoverage(scanCoverage)
        }
        let resolvedPermissionReport = permissionReport ?? PermissionAdvisor.report(
            scopeSummaries: overview.scopeSummaries,
            now: now
        )
        let topOffenders = FindingAnalytics.topOffenderTable(
            findings: findings,
            sort: topOffenderSort,
            group: topOffenderGroup,
            limit: 80,
            now: now
        )
        let largeOldReview = FindingAnalytics.largeOldReviewReport(
            findings: findings,
            mode: largeOldMode,
            sort: largeOldSort,
            limit: 80,
            now: now
        )
        let archiveReview = deterministicArchiveReview(
            findings: findings,
            mode: largeOldMode,
            sort: largeOldSort,
            now: now
        )
        let actionCenter = ActionCenterBuilder.build(
            input: ActionCenterInput(
                permissionReport: resolvedPermissionReport,
                latestScanSession: latestScanSession,
                findings: findings,
                currentPlan: currentPlan,
                latestExecutionReceipt: latestExecutionReceipt,
                reviewQueueReport: reviewQueues,
                activeFileReviewReport: activeFileReviewReport,
                browserCacheReport: browserCacheReport,
                packageCacheReport: packageCacheReport,
                latestNativeToolExecutionReceipt: latestNativeToolExecutionReceipt,
                sessionHistoryWarnings: sessionHistoryWarnings,
                generatedAt: now
            )
        )
        return ScanPresentationSnapshot(
            overview: overview,
            reviewQueues: reviewQueues,
            topOffenders: topOffenders,
            largeOldReview: largeOldReview,
            archiveReview: archiveReview,
            actionCenter: actionCenter
        )
    }

    private static func deterministicArchiveReview(
        findings: [Finding],
        mode: LargeOldReviewMode,
        sort: TopOffenderSort,
        now: Date
    ) -> ArchiveReviewReport {
        ArchiveReviewBuilder.build(
            reportID: archiveIdentifier(findings: findings, mode: mode, sort: sort, now: now),
            findings: findings,
            mode: mode,
            sort: sort,
            limit: 40,
            now: now
        )
    }

    private static func archiveIdentifier(
        findings: [Finding],
        mode: LargeOldReviewMode,
        sort: TopOffenderSort,
        now: Date
    ) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        let parts = findings.map(\.id).sorted()
            + [mode.rawValue, sort.rawValue, String(now.timeIntervalSinceReferenceDate)]
        for byte in parts.joined(separator: "\u{1f}").utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "scan-presentation-%016llx", hash)
    }
}
