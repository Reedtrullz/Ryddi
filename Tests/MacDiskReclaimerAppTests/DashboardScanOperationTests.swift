import Foundation
import XCTest
@testable import MacDiskReclaimerApp
import ReclaimerCore

@MainActor
final class DashboardScanOperationTests: XCTestCase {
    func testCancelScanStopsWorkAndNeverCommitsFindings() async {
        let fake = BlockingScanService()
        let model = DashboardModel(dependencies: .testing(scanService: fake))
        model.latestGuidedMap = nil

        model.startScan()
        await fake.waitUntilStarted()
        model.cancelScan()
        await fake.waitUntilCancelled()
        let becameIdle = await waitUntil { model.activity(for: .scan) == .idle }

        XCTAssertTrue(becameIdle)
        XCTAssertTrue(model.findings.isEmpty)
        XCTAssertEqual(model.activity(for: .scan), .idle)
        XCTAssertNil(model.activeScanRequest)
        XCTAssertEqual(
            model.scanResultFeedback?.detail,
            "Nothing was saved or changed. Start another scan whenever you are ready."
        )
    }

    func testOldOperationCannotClearNewOperation() {
        let model = DashboardModel(dependencies: .testing(scanService: BlockingScanService()))
        let old = model.activities.begin(.review, message: "Old")
        let new = model.activities.begin(.review, message: "New")

        model.activities.finish(.review, id: old)

        XCTAssertTrue(model.isWorking)
        XCTAssertEqual(model.activity(for: .review).id, new)

        model.activities.finish(.review, id: new)

        XCTAssertFalse(model.isWorking)
        XCTAssertEqual(model.activity(for: .review), .idle)
    }

    func testRemoteActivityTracksNewestInvocation() {
        let model = DashboardModel(dependencies: .testing(scanService: BlockingScanService()))
        let old = model.activities.begin(.remote, message: "Old remote operation")

        XCTAssertTrue(model.isRemoteActivityRunning)

        let new = model.activities.begin(.remote, message: "New remote operation")
        model.activities.finish(.remote, id: old)

        XCTAssertTrue(model.isRemoteActivityRunning)
        XCTAssertEqual(model.activity(for: .remote).id, new)

        model.activities.finish(.remote, id: new)

        XCTAssertFalse(model.isRemoteActivityRunning)
        XCTAssertEqual(model.activity(for: .remote), .idle)
    }

    func testWorkingStateHasNoMutableLegacyBridgeOrAssignments() throws {
        let modelSource = try source("Sources/MacDiskReclaimerApp/DashboardModel.swift")
        let isWorkingStart = try XCTUnwrap(modelSource.range(of: "var isWorking: Bool"))
        let isScanRunningStart = try XCTUnwrap(
            modelSource.range(of: "var isScanRunning: Bool", range: isWorkingStart.upperBound..<modelSource.endIndex)
        )
        let isWorkingDeclaration = modelSource[isWorkingStart.lowerBound..<isScanRunningStart.lowerBound]

        XCTAssertFalse(isWorkingDeclaration.contains("set"))
        XCTAssertFalse(modelSource.contains("legacyActivityID"))

        let appSourceRoot = repositoryRoot.appendingPathComponent("Sources/MacDiskReclaimerApp", isDirectory: true)
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: appSourceRoot,
            includingPropertiesForKeys: nil
        ))
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            XCTAssertNil(
                contents.range(of: #"isWorking\s*="# , options: .regularExpression),
                "Mutable isWorking assignment remains in \(fileURL.lastPathComponent)"
            )
        }
    }

    func testScanProgressMessageDoesNotExposePersonalPath() async {
        let fake = BlockingScanService(
            progress: ScanProgress(
                phase: .measuring,
                scopeName: "/Users/private/Documents",
                measuredItemCount: 100,
                requestedItemBudget: 1_000
            )
        )
        let model = DashboardModel(dependencies: .testing(scanService: fake))

        model.startScan()
        await fake.waitUntilStarted()
        let receivedSanitizedProgress = await waitUntil {
            model.activity(for: .scan).message == "Measured 100 items"
        }

        XCTAssertTrue(receivedSanitizedProgress)
        XCTAssertEqual(model.activity(for: .scan).message, "Measured 100 items")
        XCTAssertFalse(model.activity(for: .scan).message.contains("/Users/"))

        model.cancelScan()
        await fake.waitUntilCancelled()
        let becameIdle = await waitUntil { model.activity(for: .scan) == .idle }
        XCTAssertTrue(becameIdle)
    }

    func testFinishedFileWalkReportsResultPreparationInsteadOfFalseCompletion() async {
        let fake = BlockingScanService(
            progress: ScanProgress(
                phase: .finished,
                scopeName: nil,
                measuredItemCount: 600,
                requestedItemBudget: 25_000
            )
        )
        let model = DashboardModel(dependencies: .testing(scanService: fake))

        model.startScan()
        await fake.waitUntilStarted()
        let reportedPreparation = await waitUntil {
            model.activity(for: .scan).message == "Preparing your results"
        }

        XCTAssertTrue(reportedPreparation)
        XCTAssertEqual(model.activity(for: .scan).message, "Preparing your results")

        model.cancelScan()
        await fake.waitUntilCancelled()
        let becameIdle = await waitUntil { model.activity(for: .scan) == .idle }
        XCTAssertTrue(becameIdle)
    }

    func testAcceptedResultBecomesVisibleBeforeDurableMapWriteFinishes() async {
        let mapStore = BlockingGuidedMapStore()
        let model = DashboardModel(dependencies: .testing(
            scanService: ImmediateScanService(),
            guidedMapStore: mapStore
        ))

        model.startScan()
        await mapStore.waitUntilSaveStarted()

        XCTAssertEqual(model.activity(for: .scan), .idle)
        XCTAssertNotNil(model.latestGuidedMap)
        XCTAssertEqual(model.scanResultFeedback?.title, "Scan complete")
        XCTAssertNotNil(model.activeScanRequest, "Durable finalization may continue after the result is visible.")
        XCTAssertTrue(model.isScanFinalizing)
        XCTAssertFalse(model.isScanRunning)

        mapStore.releaseSave()
        let finalized = await waitUntil { model.scanTask == nil }
        XCTAssertTrue(finalized)
        XCTAssertFalse(model.isScanFinalizing)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            await Task.yield()
        }
        return condition()
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}

private struct ImmediateScanService: ScanServicing {
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
                measuredItemCount: 12,
                skippedItemCount: 0,
                rootsVisited: scopes.count,
                rootsDenied: 0,
                maximumMeasurementDepth: options.measurementDepth
            )
        )
    }
}

private final class BlockingGuidedMapStore: GuidedMapPersisting, @unchecked Sendable {
    private let condition = NSCondition()
    private var saveStarted = false
    private var saveReleased = false

    func loadLatest() -> GuidedMapSnapshot? { nil }

    func save(_ snapshot: GuidedMapSnapshot) throws {
        condition.lock()
        saveStarted = true
        condition.broadcast()
        while !saveReleased {
            _ = condition.wait(until: Date().addingTimeInterval(0.01))
        }
        condition.unlock()
    }

    func waitUntilSaveStarted() async {
        await waitUntil(\Self.saveStarted)
    }

    func releaseSave() {
        condition.withLock {
            saveReleased = true
            condition.broadcast()
        }
    }

    private func waitUntil(_ keyPath: KeyPath<BlockingGuidedMapStore, Bool>) async {
        while !condition.withLock({ self[keyPath: keyPath] }) {
            await Task.yield()
        }
    }
}

private final class BlockingScanService: ScanServicing, @unchecked Sendable {
    private let condition = NSCondition()
    private var started = false
    private var cancelled = false
    private let progress: ScanProgress?

    init(progress: ScanProgress? = nil) {
        self.progress = progress
    }

    func scanWithCoverage(
        scopes: [ScanScope],
        options: ScanOptions,
        control: ScanControl
    ) -> ScanResult {
        condition.withLock {
            started = true
            condition.broadcast()
        }
        if let progress {
            control.progress?(progress)
        }

        condition.lock()
        while !control.cancellation.isCancelled {
            _ = condition.wait(until: Date().addingTimeInterval(0.01))
        }
        cancelled = true
        condition.broadcast()
        condition.unlock()

        return ScanResult(
            findings: [],
            coverage: ScanCoverage(
                state: .bounded,
                requestedItemBudget: options.measurementItemBudget,
                measuredItemCount: 0,
                skippedItemCount: 1,
                rootsVisited: scopes.count,
                rootsDenied: 0,
                maximumMeasurementDepth: options.measurementDepth,
                evidence: ["Measurement was cancelled before completion."]
            )
        )
    }

    func waitUntilStarted() async {
        await waitUntil(\Self.started)
    }

    func waitUntilCancelled() async {
        await waitUntil(\Self.cancelled)
    }

    private func waitUntil(_ keyPath: KeyPath<BlockingScanService, Bool>) async {
        while !snapshot(keyPath) {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func snapshot(_ keyPath: KeyPath<BlockingScanService, Bool>) -> Bool {
        condition.withLock { self[keyPath: keyPath] }
    }
}
