import XCTest
@testable import ReclaimerCore

final class ScanSessionTests: XCTestCase {
    private let versionedScanSessionPrefix = "scan-session-v1-"
    private let legacyScanSessionPrefix = "scan-session-"
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiScanSessionTests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot, FileManager.default.fileExists(atPath: tempRoot.path) {
            try FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testScanSessionTransitionsAdvanceThroughBaselineStages() {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let session = makeSession(createdAt: createdAt, updatedAt: createdAt)

        XCTAssertEqual(session.stage, .notStarted)
        XCTAssertNil(session.findingDigest)
        XCTAssertNil(session.planDigest)

        let scanned = session.recordScan(findingDigest: "finding-v1", updatedAt: Date(timeIntervalSince1970: 1_100))
        XCTAssertEqual(scanned.stage, .scanned)
        XCTAssertEqual(scanned.findingDigest, "finding-v1")
        XCTAssertEqual(scanned.policyDigest, "policy-v1")

        let reviewed = scanned.recordReviewSelection(findingDigest: "finding-v1", updatedAt: Date(timeIntervalSince1970: 1_200))
        XCTAssertEqual(reviewed.stage, .reviewed)
        XCTAssertEqual(reviewed.findingDigest, "finding-v1")

        let planned = reviewed.recordPlan(planDigest: "plan-v1", updatedAt: Date(timeIntervalSince1970: 1_300))
        XCTAssertEqual(planned.stage, .planReady)
        XCTAssertEqual(planned.planDigest, "plan-v1")

        let dryRunReceipt = makeReceipt(
            id: "dry-run-receipt",
            mode: ExecutionMode.dryRun.rawValue,
            action: .trash,
            status: "dry-run"
        )
        let dryRunReady = planned.recordDryRunReceipt(dryRunReceipt, updatedAt: Date(timeIntervalSince1970: 1_400))
        XCTAssertEqual(dryRunReady.stage, .dryRunReady)
        XCTAssertEqual(dryRunReady.dryRunReceiptID, "dry-run-receipt")

        let reclaimReady = dryRunReady.markReclaimReady(updatedAt: Date(timeIntervalSince1970: 1_500))
        XCTAssertEqual(reclaimReady.stage, .reclaimReady)

        let executionReceipt = makeReceipt(
            id: "execution-receipt",
            mode: ExecutionMode.perform.rawValue,
            action: .deleteCache,
            status: "done"
        )
        let executed = reclaimReady.recordExecutionReceipt(executionReceipt, updatedAt: Date(timeIntervalSince1970: 1_600))
        XCTAssertEqual(executed.stage, .executed)
        XCTAssertEqual(executed.executionReceiptID, "execution-receipt")
    }

    func testExecutionReceiptWithRecoverableActionMarksRecoveryAvailable() {
        let session = makeSession()
            .recordScan(findingDigest: "finding-v1", updatedAt: Date(timeIntervalSince1970: 1_100))
            .recordReviewSelection(findingDigest: "finding-v1", updatedAt: Date(timeIntervalSince1970: 1_200))
            .recordPlan(planDigest: "plan-v1", updatedAt: Date(timeIntervalSince1970: 1_300))
            .markReclaimReady(updatedAt: Date(timeIntervalSince1970: 1_400))

        let receipt = makeReceipt(
            id: "recoverable-receipt",
            mode: ExecutionMode.perform.rawValue,
            action: .trash,
            status: "done"
        )

        let recoveryAvailable = session.recordExecutionReceipt(receipt, updatedAt: Date(timeIntervalSince1970: 1_500))

        XCTAssertEqual(recoveryAvailable.stage, .recoveryAvailable)
        XCTAssertEqual(recoveryAvailable.executionReceiptID, "recoverable-receipt")
    }

    func testPlanSelectionChangeClearsDryRunEvidenceAndBlocksExecuteSafePlan() throws {
        let originalPlan = makePlan(id: "plan-v1", createdAt: Date(timeIntervalSince1970: 1_300))
        let changedPlan = makePlan(id: "plan-v2", createdAt: Date(timeIntervalSince1970: 1_500))
        let receipt = makeReceipt(
            id: "dry-run-receipt",
            mode: ExecutionMode.dryRun.rawValue,
            action: .trash,
            status: "dry-run"
        )
        let dryRunReady = makeSession()
            .recordScan(findingDigest: "finding-v1", updatedAt: Date(timeIntervalSince1970: 1_100))
            .recordReviewSelection(findingDigest: "finding-v1", updatedAt: Date(timeIntervalSince1970: 1_200))
            .recordPlan(planDigest: originalPlan.id, updatedAt: Date(timeIntervalSince1970: 1_300))
            .recordDryRunReceipt(receipt, updatedAt: Date(timeIntervalSince1970: 1_400))

        let planReady = dryRunReady.recordPlan(planDigest: changedPlan.id, updatedAt: Date(timeIntervalSince1970: 1_500))
        let report = ActionCenterBuilder.build(input: ActionCenterInput(
            permissionReport: makePermissionReport(),
            latestScanSession: planReady,
            findings: changedPlan.items.map(\.finding),
            currentPlan: changedPlan,
            latestExecutionReceipt: receipt
        ))

        XCTAssertEqual(planReady.stage, .planReady)
        XCTAssertEqual(planReady.planDigest, changedPlan.id)
        XCTAssertNil(planReady.dryRunReceiptID)
        XCTAssertNil(planReady.executionReceiptID)
        XCTAssertFalse(report.actions.contains { $0.kind == .executeSafePlan })
        XCTAssertEqual(report.primaryAction?.kind, .runDryRun)
    }

    func testReviewSelectionClearsPlanAndReceiptEvidence() {
        let receipt = makeReceipt(
            id: "dry-run-receipt",
            mode: ExecutionMode.dryRun.rawValue,
            action: .trash,
            status: "dry-run"
        )
        let dryRunReady = makeSession()
            .recordScan(findingDigest: "finding-v1", updatedAt: Date(timeIntervalSince1970: 1_100))
            .recordPlan(planDigest: "plan-v1", updatedAt: Date(timeIntervalSince1970: 1_200))
            .recordDryRunReceipt(receipt, updatedAt: Date(timeIntervalSince1970: 1_300))

        let reviewed = dryRunReady.recordReviewSelection(
            findingDigest: "finding-v1",
            updatedAt: Date(timeIntervalSince1970: 1_400)
        )

        XCTAssertEqual(reviewed.stage, .reviewed)
        XCTAssertEqual(reviewed.findingDigest, "finding-v1")
        XCTAssertNil(reviewed.planDigest)
        XCTAssertNil(reviewed.dryRunReceiptID)
        XCTAssertNil(reviewed.executionReceiptID)
    }

    func testSessionInvalidatesWhenBaselineDigestsChange() {
        let session = makeSession(policyDigest: "policy-v1")
            .recordScan(findingDigest: "finding-v1", updatedAt: Date(timeIntervalSince1970: 1_100))

        let invalidated = session.invalidatedIfBaselineChanged(
            scopeDigest: "scope-v2",
            ruleVersion: "rules-v2",
            policyDigest: "policy-v2",
            findingDigest: "finding-v2",
            updatedAt: Date(timeIntervalSince1970: 1_200)
        )

        XCTAssertEqual(invalidated.stage, .invalidated)
        XCTAssertEqual(
            Set(invalidated.invalidationReasons),
            Set<ScanSessionInvalidationReason>([.rootsChanged, .rulesChanged, .policyChanged, .findingsChanged])
        )
    }

    func testSessionRemainsValidWhenBaselineDigestsMatch() {
        let session = makeSession(policyDigest: "policy-v1")
            .recordScan(findingDigest: "finding-v1", updatedAt: Date(timeIntervalSince1970: 1_100))

        let result = session.invalidatedIfBaselineChanged(
            scopeDigest: "scope-v1",
            ruleVersion: "rules-v1",
            policyDigest: "policy-v1",
            findingDigest: "finding-v1",
            updatedAt: Date(timeIntervalSince1970: 1_200)
        )

        XCTAssertEqual(result, session)
    }

    func testAuditStoreSavesListsAndLoadsLatestScanSession() throws {
        let store = AuditStore(root: tempRoot)
        let oldest = makeSession(id: "session-oldest", updatedAt: Date(timeIntervalSince1970: 1_000))
        let newest = makeSession(id: "session-newest", updatedAt: Date(timeIntervalSince1970: 3_000))
        let middle = makeSession(id: "session-middle", updatedAt: Date(timeIntervalSince1970: 2_000))

        try store.saveScanSession(oldest)
        try store.saveScanSession(newest)
        try store.saveScanSession(middle)

        let listed = try store.listScanSessions(limit: 2)

        XCTAssertEqual(listed.map(\.id), ["session-newest", "session-middle"])
        XCTAssertEqual(try store.latestScanSession()?.id, "session-newest")

        let savedFiles = try FileManager.default.contentsOfDirectory(at: tempRoot, includingPropertiesForKeys: nil)
        XCTAssertEqual(savedFiles.filter { $0.lastPathComponent.hasPrefix(versionedScanSessionPrefix) }.count, 3)
    }

    func testAuditStoreReadsLegacyUnversionedAndNewVersionedScanSessionFiles() throws {
        let store = AuditStore(root: tempRoot)
        let legacy = makeSession(id: "session-legacy", updatedAt: Date(timeIntervalSince1970: 1_500))
        let current = makeSession(id: "session-current", updatedAt: Date(timeIntervalSince1970: 2_500))

        try write(session: legacy, named: "\(legacyScanSessionPrefix)\(legacy.id).json")
        try store.saveScanSession(current)

        let listed = try store.listScanSessions(limit: 10)

        XCTAssertEqual(listed.map(\.id), ["session-current", "session-legacy"])
        XCTAssertEqual(try store.latestScanSession()?.id, "session-current")
    }

    func testAuditStoreScanSessionReadsAreEmptyWhenAuditRootDoesNotExist() throws {
        let missingRoot = tempRoot.appendingPathComponent("missing-audit-root", isDirectory: true)
        let store = AuditStore(root: missingRoot)

        XCTAssertEqual(try store.listScanSessions(limit: 10), [])
        XCTAssertNil(try store.latestScanSession())
    }

    func testAuditStoreScanSessionResultIsEmptyWhenNoSessionFilesExist() throws {
        let store = AuditStore(root: tempRoot)

        let result = try store.listScanSessionsResult(limit: 10)

        XCTAssertEqual(result.sessions, [])
        XCTAssertEqual(result.warnings, [])
        XCTAssertEqual(try store.listScanSessions(limit: 10), [])
    }

    func testAuditStoreScanSessionResultReadsOneOldSessionFileWithoutWarnings() throws {
        let store = AuditStore(root: tempRoot)
        let legacy = makeSession(id: "session-legacy", updatedAt: Date(timeIntervalSince1970: 1_500))
        try write(session: legacy, named: "\(legacyScanSessionPrefix)\(legacy.id).json")

        let result = try store.listScanSessionsResult(limit: 10)

        XCTAssertEqual(result.sessions.map(\.id), ["session-legacy"])
        XCTAssertEqual(result.warnings, [])
    }

    func testAuditStoreScanSessionResultWarnsForOneCorruptSessionFile() throws {
        let store = AuditStore(root: tempRoot)
        let corruptURL = try writeCorruptScanSessionFile(named: "\(versionedScanSessionPrefix)corrupt.json")

        let result = try store.listScanSessionsResult(limit: 10)

        XCTAssertEqual(result.sessions, [])
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.warnings.first?.path, corruptURL.path)
        XCTAssertEqual(result.warnings.first?.kind, .unreadableScanSession)
        XCTAssertTrue(result.warnings.first?.message.localizedCaseInsensitiveContains("scan session") ?? false)
        XCTAssertEqual(try store.listScanSessions(limit: 10), [])
    }

    func testAuditStoreScanSessionResultReturnsLatestValidSessionAfterCorruptFile() throws {
        let store = AuditStore(root: tempRoot)
        let older = makeSession(id: "session-older", updatedAt: Date(timeIntervalSince1970: 1_000))
        let latest = makeSession(id: "session-latest", updatedAt: Date(timeIntervalSince1970: 3_000))
        try store.saveScanSession(older)
        _ = try writeCorruptScanSessionFile(named: "\(versionedScanSessionPrefix)corrupt.json")
        try store.saveScanSession(latest)

        let result = try store.listScanSessionsResult(limit: 1)

        XCTAssertEqual(result.sessions.map(\.id), ["session-latest"])
        XCTAssertEqual(result.warnings.map(\.kind), [.unreadableScanSession])
        XCTAssertEqual(try store.latestScanSession()?.id, "session-latest")
    }

    func testScanSessionEvidenceBuilderCreatesDeterministicScannedSession() throws {
        let scope = ScanScope(name: "Fixture", root: tempRoot)
        let finding = Finding(
            id: "volatile-finding-id",
            scopeName: "Fixture",
            path: tempRoot.appendingPathComponent("cache").path,
            displayName: "cache",
            logicalSize: 12,
            allocatedSize: 16,
            isDirectory: true,
            safetyClass: .autoSafe,
            actionKind: .trash,
            ruleMatches: [],
            evidence: []
        )

        let first = ScanSessionEvidenceBuilder.scannedSession(
            appVersion: "0.3.0",
            ruleVersion: "rules-v1",
            preset: .developer,
            scopes: [scope],
            userPathPolicy: .empty,
            findings: [finding],
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let second = ScanSessionEvidenceBuilder.scannedSession(
            appVersion: "0.3.0",
            ruleVersion: "rules-v1",
            preset: .developer,
            scopes: [scope],
            userPathPolicy: .empty,
            findings: [finding],
            createdAt: Date(timeIntervalSince1970: 30),
            updatedAt: Date(timeIntervalSince1970: 40)
        )

        XCTAssertEqual(first.stage, .scanned)
        XCTAssertEqual(first.scopeDigest, second.scopeDigest)
        XCTAssertEqual(first.policyDigest, second.policyDigest)
        XCTAssertEqual(first.findingDigest, second.findingDigest)
        XCTAssertNil(first.planDigest)
        XCTAssertNil(first.dryRunReceiptID)
    }

    private func makeSession(
        id: String = "session-1",
        createdAt: Date = Date(timeIntervalSince1970: 1_000),
        updatedAt: Date = Date(timeIntervalSince1970: 1_000),
        policyDigest: String? = "policy-v1"
    ) -> ScanSession {
        ScanSession(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            appVersion: "0.3.0",
            ruleVersion: "rules-v1",
            preset: .developer,
            scopeDigest: "scope-v1",
            policyDigest: policyDigest,
            findingDigest: nil,
            planDigest: nil,
            dryRunReceiptID: nil,
            executionReceiptID: nil,
            stage: .notStarted,
            invalidationReasons: []
        )
    }

    private func makeReceipt(id: String, mode: String, action: ActionKind, status: String) -> ExecutionReceipt {
        ExecutionReceipt(
            id: id,
            createdAt: Date(timeIntervalSince1970: 2_000),
            ruleVersion: "rules-v1",
            mode: mode,
            beforeFreeBytes: 10_000,
            afterFreeBytes: 20_000,
            actions: [
                ExecutionActionReceipt(path: "/tmp/\(id)", action: action, status: status, message: "fixture", reclaimedBytes: 512)
            ],
            userConfirmed: mode == ExecutionMode.perform.rawValue
        )
    }

    private func makePlan(id: String, createdAt: Date) -> ReclaimPlan {
        let finding = Finding(
            scopeName: "Fixture",
            path: "/Users/example/Library/Caches/Ryddi-\(id)",
            displayName: "Ryddi \(id)",
            logicalSize: 4_096,
            allocatedSize: 4_096,
            isDirectory: true,
            safetyClass: .autoSafe,
            actionKind: .trash,
            ruleMatches: [
                RuleMatch(
                    ruleID: "fixture.cache",
                    title: "Fixture cache",
                    category: "Cache",
                    safetyClass: .autoSafe,
                    actionKind: .trash,
                    evidence: ["Fixture cache evidence"]
                )
            ],
            evidence: [Evidence(kind: "fixture", message: "Fixture cache evidence")]
        )
        return ReclaimPlan(
            id: id,
            createdAt: createdAt,
            mode: PlanMode.autoSafeOnly.rawValue,
            items: [
                ReclaimPlanItem(
                    finding: finding,
                    selected: true,
                    proposedAction: .trash,
                    conditions: [],
                    estimatedImmediateReclaim: finding.allocatedSize
                )
            ],
            dryRunSummary: []
        )
    }

    private func makePermissionReport() -> PermissionAdvisorReport {
        PermissionAdvisorReport(
            coverageLevel: .complete,
            readableCount: 1,
            deniedCount: 0,
            missingCount: 0,
            unknownCount: 0,
            totalCount: 1,
            readableFraction: 1,
            scopeSummaries: [],
            recommendedActions: [],
            nonClaims: []
        )
    }

    private func write(session: ScanSession, named filename: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(session).write(to: tempRoot.appendingPathComponent(filename), options: .atomic)
    }

    private func writeCorruptScanSessionFile(named filename: String) throws -> URL {
        let url = tempRoot.appendingPathComponent(filename)
        try "{ this is not valid json".write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
