import Foundation
import XCTest
@testable import MacDiskReclaimerApp
import ReclaimerCore

@MainActor
final class PermissionRefreshTests: XCTestCase {
    func testRefreshRunsOffMainAndAppliesAfterProbeReturns() async throws {
        let fresh = permissionReport(name: "fresh", state: .readable)
        let loader = BlockingPermissionReportLoader(report: fresh)
        let model = DashboardModel(dependencies: .testing(
            scanService: NoopPermissionScanService(),
            permissionReportLoader: loader
        ))
        let previous = model.permissionReport

        model.refreshPermissions()
        let task = try XCTUnwrap(model.permissionRefreshTask)
        await loader.waitUntilStarted()

        model.includeUserRulesInScans = true
        XCTAssertTrue(model.includeUserRulesInScans)
        XCTAssertFalse(loader.loadedOnMainThread)
        XCTAssertEqual(model.permissionReport, previous)

        loader.release()
        await task.value

        XCTAssertEqual(model.permissionReport.scopeSummaries.first?.name, "fresh")
    }

    func testRepeatedRefreshRejectsOlderCompletion() async throws {
        let loader = SequencedPermissionReportLoader(reports: [
            permissionReport(name: "old", state: .denied),
            permissionReport(name: "new", state: .readable)
        ])
        let model = DashboardModel(dependencies: .testing(
            scanService: NoopPermissionScanService(),
            permissionReportLoader: loader
        ))

        model.refreshPermissions()
        let oldTask = try XCTUnwrap(model.permissionRefreshTask)
        await loader.waitForCallCount(1)

        model.refreshPermissions()
        let newTask = try XCTUnwrap(model.permissionRefreshTask)
        await loader.waitForCallCount(2)

        loader.release(call: 0)
        await oldTask.value
        XCTAssertNotEqual(model.permissionReport.scopeSummaries.first?.name, "old")

        loader.release(call: 1)
        await newTask.value
        XCTAssertEqual(model.permissionReport.scopeSummaries.first?.name, "new")
    }

    func testPresetChangeRejectsOldScopesAndAppliesNewRefresh() async throws {
        let loader = SequencedPermissionReportLoader(reports: [
            permissionReport(name: "developer-old", state: .denied),
            permissionReport(name: "general-new", state: .readable)
        ])
        let model = DashboardModel(dependencies: .testing(
            scanService: NoopPermissionScanService(),
            permissionReportLoader: loader
        ))

        model.refreshPermissions()
        let oldTask = try XCTUnwrap(model.permissionRefreshTask)
        await loader.waitForCallCount(1)

        model.setScanPreset(.general)
        let newTask = try XCTUnwrap(model.permissionRefreshTask)
        await loader.waitForCallCount(2)

        let requestedScopes = loader.scopes(forCall: 1)
        XCTAssertEqual(requestedScopes, model.currentScopes(includeUnavailable: true))
        XCTAssertTrue(requestedScopes.contains { $0.name == "Downloads review" })

        loader.release(call: 0)
        await oldTask.value
        XCTAssertNotEqual(model.permissionReport.scopeSummaries.first?.name, "developer-old")

        loader.release(call: 1)
        await newTask.value
        XCTAssertEqual(model.permissionReport.scopeSummaries.first?.name, "general-new")
    }

    private func permissionReport(name: String, state: PermissionState) -> PermissionAdvisorReport {
        let summary = ScopeAccessSummary(
            name: name,
            path: "/fixture/\(name)",
            permissionState: state,
            message: name,
            operation: .listDirectory,
            errorCode: state == .denied ? Int(EACCES) : nil,
            detail: name
        )
        return PermissionAdvisor.report(scopeSummaries: [summary])
    }
}

private final class BlockingPermissionReportLoader: PermissionReportLoading, @unchecked Sendable {
    private let condition = NSCondition()
    private let report: PermissionAdvisorReport
    private var started = false
    private var released = false
    private var wasLoadedOnMainThread = false

    init(report: PermissionAdvisorReport) {
        self.report = report
    }

    var loadedOnMainThread: Bool {
        condition.withLock { wasLoadedOnMainThread }
    }

    func load(scopes: [ScanScope]) -> PermissionAdvisorReport {
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
        return report
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

private final class SequencedPermissionReportLoader: PermissionReportLoading, @unchecked Sendable {
    private let condition = NSCondition()
    private let reports: [PermissionAdvisorReport]
    private var requestedScopes = [[ScanScope]]()
    private var releasedCalls = Set<Int>()

    init(reports: [PermissionAdvisorReport]) {
        self.reports = reports
    }

    func load(scopes: [ScanScope]) -> PermissionAdvisorReport {
        condition.lock()
        let call = requestedScopes.count
        requestedScopes.append(scopes)
        condition.broadcast()
        while !releasedCalls.contains(call) {
            condition.wait()
        }
        condition.unlock()
        return reports[call]
    }

    func waitForCallCount(_ expected: Int) async {
        while condition.withLock({ requestedScopes.count < expected }) {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func scopes(forCall call: Int) -> [ScanScope] {
        condition.withLock { requestedScopes[call] }
    }

    func release(call: Int) {
        condition.withLock {
            releasedCalls.insert(call)
            condition.broadcast()
        }
    }
}

private struct NoopPermissionScanService: ScanServicing {
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
                maximumMeasurementDepth: options.measurementDepth
            )
        )
    }
}
