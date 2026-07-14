import Foundation
import XCTest
@testable import MacDiskReclaimerApp
import ReclaimerCore

@MainActor
final class DashboardAuditLoadingTests: XCTestCase {
    func testAuditLoadRunsOffMainAndAppliesOneCompleteSnapshotAfterReturn() async {
        let snapshot = makeSnapshot(id: "loaded")
        let loader = BlockingAuditSnapshotLoader(snapshot: snapshot)
        let model = DashboardModel(dependencies: .testing(
            scanService: NoopAuditScanService(),
            auditSnapshotLoader: loader
        ))
        var sidebarSelection = DashboardSection.summary

        let task = Task { await model.loadAudit() }
        await loader.waitUntilStarted()

        sidebarSelection = .audit
        XCTAssertEqual(sidebarSelection, .audit)
        XCTAssertFalse(loader.loadedOnMainThread)
        XCTAssertNil(model.auditStoreSummary)
        XCTAssertTrue(model.recentReceipts.isEmpty)

        loader.release()
        await task.value

        XCTAssertEqual(model.auditStoreSummary?.rootPath, "/audit/loaded")
        XCTAssertEqual(model.recentReceipts.map(\.id), ["loaded"])
        XCTAssertEqual(model.auditHistoryState.sessions.map(\.id), ["session-loaded"])
        XCTAssertEqual(model.recoveryReport.items.compactMap(\.receiptID), ["loaded"])
        XCTAssertEqual(model.activity(for: .auditLoad), .idle)
    }

    func testOlderAuditLoaderCannotCommitOverNewerLoader() async {
        let loader = SequencedAuditSnapshotLoader(snapshots: [
            makeSnapshot(id: "old"),
            makeSnapshot(id: "new")
        ])
        let model = DashboardModel(dependencies: .testing(
            scanService: NoopAuditScanService(),
            auditSnapshotLoader: loader
        ))

        let oldTask = Task { await model.loadAudit() }
        await loader.waitForCallCount(1)
        let newTask = Task { await model.loadAudit() }
        await loader.waitForCallCount(2)

        loader.release(call: 1)
        await newTask.value
        XCTAssertEqual(model.recentReceipts.map(\.id), ["new"])

        loader.release(call: 0)
        await oldTask.value
        XCTAssertEqual(model.recentReceipts.map(\.id), ["new"])
        XCTAssertEqual(model.auditStoreSummary?.rootPath, "/audit/new")
    }

    private func makeSnapshot(id: String) -> AuditStoreSnapshot {
        let receipt = ExecutionReceipt(
            id: id,
            ruleVersion: "test",
            mode: ExecutionMode.perform.rawValue,
            beforeFreeBytes: nil,
            afterFreeBytes: nil,
            actions: [
                ExecutionActionReceipt(
                    path: "/tmp/\(id)",
                    action: .trash,
                    status: "done",
                    message: "Moved to Trash.",
                    reclaimedBytes: 1
                )
            ],
            userConfirmed: true
        )
        let session = ScanSession(
            id: "session-\(id)",
            appVersion: "test",
            ruleVersion: "test",
            preset: .developer,
            scopeDigest: "scope",
            policyDigest: "policy"
        )
        return AuditStoreSnapshot(
            summary: AuditStoreSummary(
                rootPath: "/audit/\(id)",
                totalKnownFileCount: 1,
                totalKnownBytes: 1,
                unknownFileCount: 0,
                symlinkCount: 0,
                items: []
            ),
            scanSessions: AuditStoreScanSessionListResult(sessions: [session], warnings: []),
            plans: [],
            receipts: [receipt],
            nativeToolReports: [],
            nativeToolExecutionReceipts: [],
            containerInventoryReports: [],
            remoteProbeReports: [],
            remoteScanReports: [],
            remoteDogfoodReports: [],
            activeFileReviewReports: [],
            trashReviewReports: [],
            downloadsReviewReports: [],
            browserCacheReviewReports: [],
            packageCacheReviewReports: [],
            projectDependencyReviewReports: [],
            deviceBackupReviewReports: [],
            xcodeReviewReports: [],
            appUninstallReceipts: []
        )
    }
}

private final class BlockingAuditSnapshotLoader: AuditSnapshotLoading, @unchecked Sendable {
    private let condition = NSCondition()
    private let snapshot: AuditStoreSnapshot
    private var started = false
    private var released = false
    private var wasLoadedOnMainThread = false

    init(snapshot: AuditStoreSnapshot) {
        self.snapshot = snapshot
    }

    var loadedOnMainThread: Bool {
        condition.withLock { wasLoadedOnMainThread }
    }

    func load(limitPerKind: Int) -> AuditStoreSnapshot {
        condition.lock()
        wasLoadedOnMainThread = Thread.isMainThread
        started = true
        condition.broadcast()
        if !wasLoadedOnMainThread {
            while !released {
                condition.wait()
            }
        }
        condition.unlock()
        return snapshot
    }

    func waitUntilStarted() async {
        while !condition.withLock({ started }) {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func release() {
        condition.withLock {
            released = true
            condition.broadcast()
        }
    }
}

private final class SequencedAuditSnapshotLoader: AuditSnapshotLoading, @unchecked Sendable {
    private let condition = NSCondition()
    private let snapshots: [AuditStoreSnapshot]
    private var callCount = 0
    private var releasedCalls = Set<Int>()

    init(snapshots: [AuditStoreSnapshot]) {
        self.snapshots = snapshots
    }

    func load(limitPerKind: Int) -> AuditStoreSnapshot {
        condition.lock()
        let call = callCount
        callCount += 1
        condition.broadcast()
        while !releasedCalls.contains(call) {
            condition.wait()
        }
        condition.unlock()
        return snapshots[call]
    }

    func waitForCallCount(_ expected: Int) async {
        while condition.withLock({ callCount < expected }) {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func release(call: Int) {
        condition.withLock {
            releasedCalls.insert(call)
            condition.broadcast()
        }
    }
}

private struct NoopAuditScanService: ScanServicing {
    func scanWithCoverage(
        scopes: [ScanScope],
        options: ScanOptions,
        control: ScanControl
    ) -> ScanResult {
        ScanResult(
            findings: [],
            coverage: ScanCoverage(
                state: .complete,
                requestedItemBudget: options.measurementItemBudget,
                measuredItemCount: 0,
                skippedItemCount: 0,
                rootsVisited: scopes.count,
                rootsDenied: 0,
                maximumMeasurementDepth: options.measurementDepth,
                evidence: []
            )
        )
    }
}
