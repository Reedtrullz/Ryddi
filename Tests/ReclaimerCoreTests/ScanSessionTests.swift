import XCTest
@testable import ReclaimerCore

final class ScanSessionTests: XCTestCase {
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
        XCTAssertEqual(savedFiles.filter { $0.lastPathComponent.hasPrefix("scan-session-") }.count, 3)
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
}
