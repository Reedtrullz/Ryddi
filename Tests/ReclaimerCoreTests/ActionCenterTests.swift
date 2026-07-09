import XCTest
@testable import ReclaimerCore

final class ActionCenterTests: XCTestCase {
    func testDegradedPermissionsSelectGrantAccess() throws {
        let report = ActionCenterBuilder.build(input: .fixture(
            permissionReport: .fixture(coverage: .degraded, denied: 2),
            latestScanSession: .fixture(stage: .scanned)
        ))

        let primary = try XCTUnwrap(report.primaryAction)
        XCTAssertEqual(primary.kind, .grantAccess)
        XCTAssertFalse(primary.isDestructive)
        XCTAssertEqual(primary.count, 2)
        XCTAssertTrue(report.nonClaims.contains { $0.localizedCaseInsensitiveContains("does not perform cleanup") })
    }

    func testNoSessionSelectsRunScan() throws {
        let report = ActionCenterBuilder.build(input: .fixture(latestScanSession: nil))

        let primary = try XCTUnwrap(report.primaryAction)
        XCTAssertEqual(primary.kind, .runScan)
        XCTAssertFalse(primary.isDestructive)
    }

    func testFindingsWithoutPlanSelectReviewQueue() throws {
        let finding = Finding.fixture(
            path: "/Users/example/Downloads/old-installer.dmg",
            safetyClass: .reviewRequired,
            actionKind: .openGuidance,
            allocatedSize: 1_500
        )

        let report = ActionCenterBuilder.build(input: .fixture(
            latestScanSession: .fixture(stage: .scanned, findingDigest: "findings-v1"),
            findings: [finding],
            currentPlan: nil,
            latestExecutionReceipt: nil
        ))

        let primary = try XCTUnwrap(report.primaryAction)
        XCTAssertEqual(primary.kind, .reviewQueue)
        XCTAssertFalse(primary.isDestructive)
        XCTAssertEqual(primary.estimatedReclaimBytes, 1_500)
        XCTAssertEqual(primary.count, 1)
        XCTAssertTrue(primary.sourceIDs.contains(ReviewQueueID.unknown.rawValue))
    }

    func testPlanWithoutDryRunSelectsRunDryRun() throws {
        let plan = ReclaimPlan.fixture(expectedReclaim: 2_000)

        let report = ActionCenterBuilder.build(input: .fixture(
            latestScanSession: .fixture(stage: .planReady, findingDigest: "findings-v1", planDigest: "plan-v1"),
            currentPlan: plan,
            latestExecutionReceipt: nil
        ))

        let primary = try XCTUnwrap(report.primaryAction)
        XCTAssertEqual(primary.kind, .runDryRun)
        XCTAssertFalse(primary.isDestructive)
        XCTAssertEqual(primary.estimatedReclaimBytes, 2_000)
    }

    func testCleanDryRunWithSafeBytesSelectsExecuteSafePlan() throws {
        let plan = ReclaimPlan.fixture(expectedReclaim: 3_000)
        let receipt = ExecutionReceipt.fixture(mode: ExecutionMode.dryRun.rawValue, status: "dry-run", reclaimedBytes: 3_000)

        let report = ActionCenterBuilder.build(input: .fixture(
            latestScanSession: .fixture(stage: .dryRunReady, findingDigest: "findings-v1", planDigest: "plan-v1", dryRunReceiptID: receipt.id),
            currentPlan: plan,
            latestExecutionReceipt: receipt
        ))

        let primary = try XCTUnwrap(report.primaryAction)
        XCTAssertEqual(primary.kind, .executeSafePlan)
        XCTAssertTrue(primary.isDestructive)
        XCTAssertEqual(primary.estimatedReclaimBytes, 3_000)
        XCTAssertTrue(report.nonClaims.contains { $0.localizedCaseInsensitiveContains("apfs") })
    }

    func testActiveBrowserCacheSelectsQuitApp() throws {
        let browserReport = BrowserCacheReviewReport.fixture(
            browser: .chrome,
            runtimeState: .running,
            allocatedSize: 4_000,
            itemCount: 12
        )

        let report = ActionCenterBuilder.build(input: .fixture(
            latestScanSession: .fixture(stage: .scanned, findingDigest: "findings-v1"),
            browserCacheReport: browserReport
        ))

        let primary = try XCTUnwrap(report.primaryAction)
        XCTAssertEqual(primary.kind, .quitApp)
        XCTAssertFalse(primary.isDestructive)
        XCTAssertEqual(primary.estimatedReclaimBytes, 4_000)
        XCTAssertEqual(primary.count, 12)
        XCTAssertTrue(primary.sourceIDs.contains(BrowserCacheBrowser.chrome.rawValue))
    }

    func testPackageCacheSelectsUseNativeTool() throws {
        let packageReport = PackageCacheReviewReport.fixture(
            managerSummaries: [
                PackageCacheSummary(name: PackageCacheManager.homebrew.label, itemCount: 8, allocatedSize: 5_000)
            ]
        )

        let report = ActionCenterBuilder.build(input: .fixture(
            latestScanSession: .fixture(stage: .scanned, findingDigest: "findings-v1"),
            packageCacheReport: packageReport
        ))

        let primary = try XCTUnwrap(report.primaryAction)
        XCTAssertEqual(primary.kind, .useNativeTool)
        XCTAssertFalse(primary.isDestructive)
        XCTAssertEqual(primary.estimatedReclaimBytes, 5_000)
        XCTAssertEqual(primary.count, 8)
        XCTAssertTrue(primary.sourceIDs.contains(PackageCacheManager.homebrew.rawValue))
    }

    func testActionsSortByPriorityThenEstimatedBytesThenCount() throws {
        let packageReport = PackageCacheReviewReport.fixture(
            managerSummaries: [
                PackageCacheSummary(name: PackageCacheManager.homebrew.label, itemCount: 12, allocatedSize: 1_000),
                PackageCacheSummary(name: PackageCacheManager.npm.label, itemCount: 4, allocatedSize: 6_000),
                PackageCacheSummary(name: PackageCacheManager.pnpm.label, itemCount: 9, allocatedSize: 6_000)
            ]
        )

        let report = ActionCenterBuilder.build(input: .fixture(
            permissionReport: .fixture(coverage: .degraded, denied: 1),
            latestScanSession: .fixture(stage: .scanned, findingDigest: "findings-v1"),
            packageCacheReport: packageReport
        ))

        XCTAssertEqual(report.actions.map(\.kind).prefix(1), [.grantAccess])
        XCTAssertEqual(
            report.actions.filter { $0.kind == .useNativeTool }.map(\.sourceIDs.first),
            [PackageCacheManager.pnpm.rawValue, PackageCacheManager.npm.rawValue, PackageCacheManager.homebrew.rawValue]
        )
    }

    func testProtectedCodexSessionsDoNotCreateDestructiveAction() throws {
        let protectedFinding = Finding.fixture(
            path: "/Users/example/.codex/sessions/2026/07/09/session.jsonl",
            displayName: "Codex session transcript",
            category: "Codex sessions",
            safetyClass: .preserveByDefault,
            actionKind: .reportOnly,
            allocatedSize: 9_000
        )
        let plan = ReclaimPlan.fixture(finding: protectedFinding, selected: true, proposedAction: .trash, estimatedReclaim: 9_000)
        let receipt = ExecutionReceipt.fixture(mode: ExecutionMode.dryRun.rawValue, status: "dry-run", reclaimedBytes: 9_000)

        let report = ActionCenterBuilder.build(input: .fixture(
            latestScanSession: .fixture(stage: .dryRunReady, findingDigest: "findings-v1", planDigest: "plan-v1", dryRunReceiptID: receipt.id),
            findings: [protectedFinding],
            currentPlan: plan,
            latestExecutionReceipt: receipt
        ))

        XCTAssertFalse(report.actions.contains { $0.kind == .executeSafePlan })
        XCTAssertFalse(report.actions.contains { $0.isDestructive })
        XCTAssertTrue(report.nonClaims.contains { $0.localizedCaseInsensitiveContains("protected data remains review-only") })
    }
}

private extension ActionCenterInput {
    static func fixture(
        permissionReport: PermissionAdvisorReport = .fixture(coverage: .complete),
        latestScanSession: ScanSession? = .fixture(stage: .scanned, findingDigest: "findings-v1"),
        findings: [Finding] = [],
        currentPlan: ReclaimPlan? = nil,
        latestExecutionReceipt: ExecutionReceipt? = nil,
        reviewQueueReport: ReviewQueueReport? = nil,
        activeFileReviewReport: ActiveFileReviewReport? = nil,
        browserCacheReport: BrowserCacheReviewReport? = nil,
        packageCacheReport: PackageCacheReviewReport? = nil
    ) -> ActionCenterInput {
        ActionCenterInput(
            permissionReport: permissionReport,
            latestScanSession: latestScanSession,
            findings: findings,
            currentPlan: currentPlan,
            latestExecutionReceipt: latestExecutionReceipt,
            reviewQueueReport: reviewQueueReport,
            activeFileReviewReport: activeFileReviewReport,
            browserCacheReport: browserCacheReport,
            packageCacheReport: packageCacheReport,
            generatedAt: Date(timeIntervalSince1970: 10)
        )
    }
}

private extension PermissionAdvisorReport {
    static func fixture(
        coverage: PermissionCoverageLevel,
        denied: Int = 0,
        missing: Int = 0,
        unknown: Int = 0
    ) -> PermissionAdvisorReport {
        let readable = coverage == .complete ? 3 : 1
        let total = readable + denied + missing + unknown
        return PermissionAdvisorReport(
            coverageLevel: coverage,
            readableCount: readable,
            deniedCount: denied,
            missingCount: missing,
            unknownCount: unknown,
            totalCount: total,
            readableFraction: total == 0 ? 0 : Double(readable) / Double(total),
            scopeSummaries: [],
            recommendedActions: [],
            nonClaims: []
        )
    }
}

private extension ScanSession {
    static func fixture(
        stage: ScanSessionStage,
        findingDigest: String? = nil,
        planDigest: String? = nil,
        dryRunReceiptID: String? = nil
    ) -> ScanSession {
        ScanSession(
            id: "session-\(stage.rawValue)",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            appVersion: "0.3.0",
            ruleVersion: "rules-v1",
            preset: .developer,
            scopeDigest: "scope-v1",
            policyDigest: "policy-v1",
            findingDigest: findingDigest,
            planDigest: planDigest,
            dryRunReceiptID: dryRunReceiptID,
            executionReceiptID: nil,
            stage: stage
        )
    }
}

private extension Finding {
    static func fixture(
        path: String,
        displayName: String = "Fixture",
        category: String = "Downloads",
        safetyClass: SafetyClass,
        actionKind: ActionKind,
        allocatedSize: Int64,
        openFileStatus: OpenFileStatus? = nil
    ) -> Finding {
        let match = RuleMatch(
            ruleID: "fixture.\(category)",
            title: displayName,
            category: category,
            safetyClass: safetyClass,
            actionKind: actionKind,
            evidence: ["Fixture evidence"]
        )
        return Finding(
            scopeName: "Fixture",
            path: path,
            displayName: displayName,
            logicalSize: allocatedSize,
            allocatedSize: allocatedSize,
            isDirectory: true,
            safetyClass: safetyClass,
            actionKind: actionKind,
            ruleMatches: [match],
            evidence: [Evidence(kind: "fixture", message: "Fixture evidence")],
            openFileStatus: openFileStatus
        )
    }
}

private extension ReclaimPlan {
    static func fixture(expectedReclaim: Int64) -> ReclaimPlan {
        fixture(
            finding: .fixture(
                path: "/Users/example/Library/Caches/Ryddi-fixture",
                safetyClass: .autoSafe,
                actionKind: .trash,
                allocatedSize: expectedReclaim
            ),
            selected: true,
            proposedAction: .trash,
            estimatedReclaim: expectedReclaim
        )
    }

    static func fixture(
        finding: Finding,
        selected: Bool,
        proposedAction: ActionKind,
        estimatedReclaim: Int64
    ) -> ReclaimPlan {
        ReclaimPlan(
            id: "plan-v1",
            mode: PlanMode.autoSafeOnly.rawValue,
            items: [
                ReclaimPlanItem(
                    finding: finding,
                    selected: selected,
                    proposedAction: proposedAction,
                    conditions: [],
                    estimatedImmediateReclaim: estimatedReclaim
                )
            ],
            dryRunSummary: []
        )
    }
}

private extension ExecutionReceipt {
    static func fixture(mode: String, status: String, reclaimedBytes: Int64) -> ExecutionReceipt {
        ExecutionReceipt(
            id: "receipt-\(mode)",
            createdAt: Date(timeIntervalSince1970: 3),
            ruleVersion: "rules-v1",
            mode: mode,
            beforeFreeBytes: 100_000,
            afterFreeBytes: nil,
            actions: [
                ExecutionActionReceipt(
                    path: "/Users/example/Library/Caches/Ryddi-fixture",
                    action: .trash,
                    status: status,
                    message: "Fixture receipt",
                    reclaimedBytes: reclaimedBytes
                )
            ],
            userConfirmed: false
        )
    }
}

private extension BrowserCacheReviewReport {
    static func fixture(
        browser: BrowserCacheBrowser,
        runtimeState: BrowserCacheRuntimeState,
        allocatedSize: Int64,
        itemCount: Int
    ) -> BrowserCacheReviewReport {
        BrowserCacheReviewReport(
            totalLogicalSize: allocatedSize,
            totalAllocatedSize: allocatedSize,
            itemCount: itemCount,
            displayedItemCount: itemCount,
            candidateBytes: allocatedSize,
            rootSummaries: [],
            browserSummaries: [BrowserCacheSummary(name: browser.label, itemCount: itemCount, allocatedSize: allocatedSize)],
            kindSummaries: [],
            largestItems: [],
            protectedProfileRoots: [],
            runtimeSummaries: [
                BrowserCacheRuntimeSummary(
                    browser: browser,
                    state: runtimeState,
                    matchedProcessNames: [browser.label],
                    note: "Fixture runtime",
                    guidance: []
                )
            ],
            guidance: [],
            nonClaims: []
        )
    }
}

private extension PackageCacheReviewReport {
    static func fixture(managerSummaries: [PackageCacheSummary]) -> PackageCacheReviewReport {
        PackageCacheReviewReport(
            totalLogicalSize: managerSummaries.reduce(0) { $0 + $1.allocatedSize },
            totalAllocatedSize: managerSummaries.reduce(0) { $0 + $1.allocatedSize },
            itemCount: managerSummaries.reduce(0) { $0 + $1.itemCount },
            displayedItemCount: managerSummaries.reduce(0) { $0 + $1.itemCount },
            candidateBytes: managerSummaries.reduce(0) { $0 + $1.allocatedSize },
            rootSummaries: [],
            managerSummaries: managerSummaries,
            kindSummaries: [],
            largestItems: [],
            protectedConfigRoots: [],
            guidance: [],
            nonClaims: []
        )
    }
}
