import Foundation
import XCTest
@testable import MacDiskReclaimerApp
import ReclaimerCore

@MainActor
final class DashboardScanOperationTests: XCTestCase {
    func testCancelScanStopsWorkAndNeverCommitsFindings() async {
        let fake = BlockingScanService()
        let model = DashboardModel(dependencies: .testing(scanService: fake))

        model.startScan()
        await fake.waitUntilStarted()
        model.cancelScan()
        await fake.waitUntilCancelled()
        await waitUntil { model.activity(for: .scan) == .idle }

        XCTAssertTrue(model.findings.isEmpty)
        XCTAssertEqual(model.activity(for: .scan), .idle)
        XCTAssertNil(model.activeScanRequest)
    }

    func testOldOperationCannotClearNewOperation() {
        var registry = DashboardActivityRegistry()
        let old = registry.begin(.review, message: "Old")
        let new = registry.begin(.review, message: "New")

        registry.finish(.review, id: old)

        XCTAssertEqual(registry.state(for: .review).id, new)
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
        await Task.yield()

        XCTAssertFalse(model.activity(for: .scan).message.contains("/Users/"))

        model.cancelScan()
        await fake.waitUntilCancelled()
        await waitUntil { model.activity(for: .scan) == .idle }
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
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
