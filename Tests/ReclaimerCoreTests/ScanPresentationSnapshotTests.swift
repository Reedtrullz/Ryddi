import XCTest
@testable import ReclaimerCore

final class ScanPresentationSnapshotTests: XCTestCase {
    func testArchiveReviewBuilderUsesExplicitReportIDInReportAndMarkdown() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let report = ArchiveReviewBuilder.build(
            reportID: "stable-archive-report",
            findings: fixtureFindings(count: 3, now: now),
            now: now
        )

        XCTAssertEqual(report.id, "stable-archive-report")
        XCTAssertTrue(report.markdown.contains("Report id: `stable-archive-report`"))
    }

    func testSnapshotIsDeterministicForSameFindingsAndClock() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let findings = fixtureFindings(count: 24, now: now)
        let scopes = [
            ScanScope(
                name: "Fixture",
                root: URL(fileURLWithPath: "/fixture"),
                permissionState: .readable
            )
        ]
        let permissionReport = PermissionAdvisor.report(
            scopeSummaries: [
                ScopeAccessSummary(
                    name: "Fixture",
                    path: "/fixture",
                    permissionState: .readable,
                    message: "Fixture scope is readable."
                )
            ],
            now: now
        )

        let first = ScanPresentationSnapshot.build(
            findings: findings,
            scopes: scopes,
            permissionReport: permissionReport,
            now: now
        )
        let second = ScanPresentationSnapshot.build(
            findings: findings,
            scopes: scopes,
            permissionReport: permissionReport,
            now: now
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.overview.generatedAt, now)
        XCTAssertEqual(first.reviewQueues.generatedAt, now)
        XCTAssertEqual(first.topOffenders.generatedAt, now)
        XCTAssertEqual(first.largeOldReview.generatedAt, now)
        XCTAssertEqual(first.archiveReview.createdAt, now)
        XCTAssertEqual(first.archiveReview.id, second.archiveReview.id)
        XCTAssertEqual(first.archiveReview.markdown, second.archiveReview.markdown)
        XCTAssertEqual(first.actionCenter.generatedAt, now)
        XCTAssertEqual(first.overview.findingCount, findings.count)
        XCTAssertEqual(first.reviewQueues.queues.reduce(0) { $0 + $1.count }, findings.count)
    }

    func testScanCoverageEvidencePreventsPresentationReprobe() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiSingleProbe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = ScanScope(name: "Single probe", root: root)
        let probe = CountingStateChangingScopeAccessProbe()
        let scanner = try FileScanner(
            openFileChecker: NoOpenFilesChecker(),
            scopeAccessProbe: probe
        )

        let result = scanner.scanWithCoverage(
            scopes: [scope],
            options: ScanOptions(minimumFindingSize: 0, measurementItemBudget: 10)
        )
        let snapshot = ScanPresentationSnapshot.build(
            findings: result.findings,
            scopes: [scope],
            scanCoverage: result.coverage,
            scopeAccessProbe: probe
        )

        XCTAssertEqual(probe.callCount, 1)
        let scopeAccessSummaries = try XCTUnwrap(result.coverage.scopeAccessSummaries)
        XCTAssertEqual(scopeAccessSummaries.count, 1)
        XCTAssertEqual(snapshot.overview.scopeSummaries, scopeAccessSummaries)
        XCTAssertEqual(snapshot.overview.scopeSummaries.first?.permissionState, .readable)
    }

    // Release-only guard: 5,000 findings must build within a generous five-second ceiling.
    func testBuild5000FindingsCompletesWithinFiveSecondsInRelease() throws {
        #if DEBUG
        throw XCTSkip("Performance ceiling is release-only; debug builds are intentionally unbounded.")
        #else
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let findings = fixtureFindings(count: 5_000, now: now)
        let scope = ScanScope(
            name: "Fixture",
            root: URL(fileURLWithPath: "/fixture"),
            permissionState: .readable
        )
        let permissionReport = PermissionAdvisor.report(
            scopeSummaries: [
                ScopeAccessSummary(
                    name: scope.name,
                    path: scope.root.path,
                    permissionState: .readable,
                    message: "Fixture scope is readable."
                )
            ],
            now: now
        )

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = ScanPresentationSnapshot.build(
                findings: findings,
                scopes: [scope],
                permissionReport: permissionReport,
                now: now
            )
        }

        XCTAssertLessThan(elapsed, .seconds(5))
        #endif
    }

    private func fixtureFindings(count: Int, now: Date) -> [Finding] {
        (0..<count).map { index in
            let safetyClass: SafetyClass = switch index % 5 {
            case 0: .autoSafe
            case 1: .safeAfterCondition
            case 2: .reviewRequired
            case 3: .preserveByDefault
            default: .neverTouch
            }
            let actionKind: ActionKind = safetyClass == .autoSafe ? .deleteCache : .openGuidance
            let size = Int64((index + 1) * 4_096)
            return Finding(
                id: "fixture-\(index)",
                scopeName: "Fixture",
                path: "/fixture/item-\(index).zip",
                displayName: "item-\(index).zip",
                logicalSize: size,
                allocatedSize: size,
                isDirectory: false,
                modificationDate: now.addingTimeInterval(TimeInterval(-index * 86_400)),
                safetyClass: safetyClass,
                actionKind: actionKind,
                ruleMatches: [
                    RuleMatch(
                        ruleID: "fixture.rule.\(index)",
                        title: "Fixture rule",
                        category: index.isMultiple(of: 2) ? "Archive" : "Cache",
                        safetyClass: safetyClass,
                        actionKind: actionKind,
                        evidence: ["Fixture evidence"]
                    )
                ],
                evidence: [Evidence(kind: "fixture", message: "Fixture evidence")]
            )
        }
    }
}

private final class CountingStateChangingScopeAccessProbe: ScopeAccessProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var callCount: Int {
        lock.withLock { calls }
    }

    func probe(_ url: URL) -> ScopeAccessProbeResult {
        let currentCall = lock.withLock {
            calls += 1
            return calls
        }
        if currentCall == 1 {
            return ScopeAccessProbeResult(
                state: .readable,
                operation: .listDirectory,
                detail: "First operation succeeded."
            )
        }
        return ScopeAccessProbeResult(
            state: .permissionDenied,
            operation: .listDirectory,
            errorCode: Int(EACCES),
            detail: "A later probe would disagree."
        )
    }
}
