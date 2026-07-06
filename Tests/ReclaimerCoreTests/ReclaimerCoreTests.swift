import XCTest
@testable import ReclaimerCore

final class ReclaimerCoreTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacDiskReclaimerTests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot, FileManager.default.fileExists(atPath: tempRoot.path) {
            try FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testRuleEngineClassifiesCodexPolicy() throws {
        let engine = try RuleEngine.bundled()

        let config = engine.classify(
            path: "/Users/test/.codex/auth.json",
            isDirectory: false,
            isSymbolicLink: false
        )
        XCTAssertEqual(config.safetyClass, .neverTouch)

        let session = engine.classify(
            path: "/Users/test/.codex/sessions/2026/06/rollout.jsonl",
            isDirectory: false,
            isSymbolicLink: false
        )
        XCTAssertEqual(session.safetyClass, .preserveByDefault)
        XCTAssertEqual(session.actionKind, .compress)

        let cache = engine.classify(
            path: "/Users/test/Library/Caches/Codex/Cache_Data/blob",
            isDirectory: false,
            isSymbolicLink: false
        )
        XCTAssertEqual(cache.safetyClass, .autoSafe)
        XCTAssertEqual(cache.actionKind, .deleteCache)
    }

    func testScannerProducesStableFindingsAndDoesNotFollowSymlink() throws {
        let cache = tempRoot.appendingPathComponent("Library/Caches/Codex", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4096).write(to: cache.appendingPathComponent("cache.bin"))

        let target = tempRoot.appendingPathComponent("target.txt")
        try "target".write(to: target, atomically: true, encoding: .utf8)
        let link = tempRoot.appendingPathComponent("Library/Caches/Codex/link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let scanner = try FileScanner(openFileChecker: NoOpenFilesChecker())
        let findings = scanner.scan(
            scopes: [ScanScope(name: "fixture", root: tempRoot)],
            options: ScanOptions(minimumFindingSize: 0, maximumFindingDepth: 4, includeOpenFileStatus: false)
        )

        XCTAssertTrue(findings.contains { $0.path.hasSuffix("/Library/Caches/Codex") && $0.safetyClass == .autoSafe })
        XCTAssertTrue(findings.contains { $0.path.hasSuffix("/Library/Caches/Codex/link") && $0.isSymbolicLink && $0.safetyClass == .reviewRequired })
    }

    func testScannerAddsLargeAndOldReviewSignalsWithoutSelectingForCleanup() throws {
        let reviewFile = tempRoot.appendingPathComponent("Downloads/old-large.bin")
        try FileManager.default.createDirectory(at: reviewFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 6, count: 256).write(to: reviewFile)
        let oldDate = Date().addingTimeInterval(-90 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: reviewFile.path)

        let scanner = try FileScanner(openFileChecker: NoOpenFilesChecker())
        let findings = scanner.scan(
            scopes: [ScanScope(name: "fixture", root: tempRoot)],
            options: ScanOptions(
                minimumFindingSize: 0,
                maximumFindingDepth: 3,
                includeOpenFileStatus: false,
                largeFileThreshold: 100,
                oldFileAgeDays: 30
            )
        )

        let finding = try XCTUnwrap(findings.first { $0.path.hasSuffix("/Downloads/old-large.bin") })
        XCTAssertEqual(finding.safetyClass, .reviewRequired)
        XCTAssertEqual(finding.actionKind, .openGuidance)
        XCTAssertTrue(finding.ruleMatches.contains { $0.ruleID == "dynamic.large-item.review" })
        XCTAssertTrue(finding.ruleMatches.contains { $0.ruleID == "dynamic.old-item.review" })

        let plan = PlanBuilder(openFileChecker: NoOpenFilesChecker()).buildPlan(from: [finding], mode: .autoSafeOnly)
        XCTAssertFalse(plan.items.first?.selected ?? true)
    }

    func testScanOverviewReportsScopeCoverageAndBuckets() throws {
        let cache = tempRoot.appendingPathComponent("Library/Caches/Codex/cache.bin")
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 128).write(to: cache)

        let scopes = [
            ScanScope(name: "fixture", root: tempRoot),
            ScanScope(name: "missing", root: tempRoot.appendingPathComponent("missing"))
        ]
        let scanner = try FileScanner(openFileChecker: NoOpenFilesChecker())
        let findings = scanner.scan(
            scopes: scopes,
            options: ScanOptions(minimumFindingSize: 0, maximumFindingDepth: 4, includeOpenFileStatus: false)
        )
        let overview = FindingAnalytics.overview(findings: findings, scopes: scopes, topLimit: 3)

        XCTAssertEqual(overview.scopeSummaries.first { $0.name == "missing" }?.permissionState, .missing)
        XCTAssertGreaterThan(overview.totalAllocatedSize, 0)
        XCTAssertFalse(overview.categorySummaries.isEmpty)
        XCTAssertFalse(overview.mapNodes.isEmpty)
        XCTAssertLessThanOrEqual(overview.topFindings.count, 3)
        XCTAssertFalse(overview.accountingNotes.isEmpty)
    }

    func testEvidenceReportIncludesSafetyPolicyAndNonClaims() throws {
        let protectedPath = tempRoot.appendingPathComponent("Projects/KeepMe", isDirectory: true)
        let excludedPath = tempRoot.appendingPathComponent("Downloads/Noisy", isDirectory: true)
        let cache = finding(
            path: tempRoot.appendingPathComponent("Library/Caches/Codex").path,
            safety: .autoSafe,
            action: .deleteCache,
            open: false,
            allocatedSize: 1_000,
            isDirectory: true,
            category: "Codex Cache"
        )
        let history = finding(
            path: tempRoot.appendingPathComponent(".codex/sessions/rollout.jsonl").path,
            safety: .preserveByDefault,
            action: .compress,
            open: false,
            allocatedSize: 2_000,
            category: "Codex History"
        )
        let scopes = [ScanScope(name: "fixture", root: tempRoot)]
        let overview = FindingAnalytics.overview(
            findings: [cache, history],
            scopes: scopes,
            topLimit: 2,
            now: Date(timeIntervalSince1970: 0)
        )
        let policy = UserPathPolicy(rules: [
            UserPathRule(kind: .protect, path: protectedPath.path, reason: "active work", createdAt: Date(timeIntervalSince1970: 0)),
            UserPathRule(kind: .exclude, path: excludedPath.path, reason: "too noisy", createdAt: Date(timeIntervalSince1970: 0))
        ])
        let disk = DiskStatusSnapshot(
            createdAt: Date(timeIntervalSince1970: 0),
            path: "/fixture",
            totalBytes: 10_000,
            freeBytes: 2_000,
            importantFreeBytes: nil,
            availableBytes: nil,
            pressure: .warning,
            notes: ["Fixture disk note."]
        )

        let report = EvidenceReportBuilder.build(
            overview: overview,
            findings: [cache, history],
            scopes: scopes,
            diskStatus: disk,
            userPathPolicy: policy,
            topLimit: 2,
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(report.markdown.contains("# Ryddi Evidence Report"))
        XCTAssertTrue(report.markdown.contains("## Top Findings"))
        XCTAssertTrue(report.markdown.contains("Codex Cache"))
        XCTAssertTrue(report.markdown.contains("Protect from cleanup"))
        XCTAssertTrue(report.markdown.contains("Exclude from scans"))
        XCTAssertTrue(report.markdown.contains("No cleanup was executed by this report."))
        XCTAssertTrue(report.markdown.contains("Fixture disk note."))
        XCTAssertEqual(report.findingCount, 2)
        XCTAssertEqual(report.protectedBytes, 2_000)
    }

    func testReportStoreSavesMarkdown() throws {
        let report = EvidenceReport(
            id: "fixture",
            createdAt: Date(timeIntervalSince1970: 0),
            title: "Fixture Report",
            markdown: "# Fixture Report\n\nEvidence.",
            findingCount: 1,
            expectedAutoSafeBytes: 10,
            reviewBytes: 20,
            protectedBytes: 30,
            nonClaims: ["fixture non-claim"]
        )
        let store = ReportStore(root: tempRoot.appendingPathComponent("Reports", isDirectory: true))

        let url = try store.save(report: report)

        XCTAssertEqual(url.lastPathComponent, "report-fixture.md")
        XCTAssertEqual(try String(contentsOf: url), report.markdown)
    }

    func testExecutionReceiptReportIncludesCountsDeltasAndNonClaims() {
        let receipt = ExecutionReceipt(
            id: "receipt-fixture",
            createdAt: Date(timeIntervalSince1970: 0),
            ruleVersion: "test-rules",
            mode: ExecutionMode.dryRun.rawValue,
            beforeFreeBytes: 1_000,
            afterFreeBytes: 1_200,
            actions: [
                ExecutionActionReceipt(path: "/tmp/cache", action: .deleteCache, status: "dry-run", message: "Would delete.", reclaimedBytes: 200),
                ExecutionActionReceipt(path: "/tmp/open", action: .deleteCache, status: "skipped", message: "Open-file check blocked action."),
                ExecutionActionReceipt(path: "/tmp/error", action: .trash, status: "error", message: "Fixture error.")
            ],
            userConfirmed: false,
            errors: ["fixture top-level error"]
        )

        let report = ExecutionReceiptReportBuilder.build(
            receipt: receipt,
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(report.receiptID, "receipt-fixture")
        XCTAssertEqual(report.actionCount, 3)
        XCTAssertEqual(report.dryRunCount, 1)
        XCTAssertEqual(report.skippedCount, 1)
        XCTAssertEqual(report.errorCount, 2)
        XCTAssertEqual(report.totalReclaimedBytes, 200)
        XCTAssertEqual(report.freeSpaceDeltaBytes, 200)
        XCTAssertTrue(report.markdown.contains("# Ryddi Receipt Report"))
        XCTAssertTrue(report.markdown.contains("receipt-fixture"))
        XCTAssertTrue(report.markdown.contains("Open-file check blocked action."))
        XCTAssertTrue(report.markdown.contains("fixture top-level error"))
        XCTAssertTrue(report.markdown.contains("This report summarizes a saved receipt; it does not execute cleanup."))
    }

    func testReportStoreSavesExecutionReceiptReport() throws {
        let receiptReport = ExecutionReceiptReport(
            id: "report-fixture",
            createdAt: Date(timeIntervalSince1970: 0),
            title: "Receipt Report",
            markdown: "# Receipt Report\n",
            receiptID: "receipt-fixture",
            actionCount: 0,
            dryRunCount: 0,
            doneCount: 0,
            skippedCount: 0,
            errorCount: 0,
            totalReclaimedBytes: 0,
            freeSpaceDeltaBytes: nil,
            nonClaims: []
        )
        let store = ReportStore(root: tempRoot.appendingPathComponent("Reports", isDirectory: true))

        let url = try store.save(executionReceiptReport: receiptReport)

        XCTAssertEqual(url.lastPathComponent, "receipt-report-receipt-fixture-report-fixture.md")
        XCTAssertEqual(try String(contentsOf: url), receiptReport.markdown)
    }

    func testVisualMapUsesNonOverlappingAllocatedSizes() throws {
        let root = Finding(
            scopeName: "fixture",
            path: tempRoot.path,
            displayName: tempRoot.lastPathComponent,
            logicalSize: 200,
            allocatedSize: 200,
            isDirectory: true,
            safetyClass: .reviewRequired,
            actionKind: .reportOnly,
            ruleMatches: [],
            evidence: [Evidence(kind: "scope", message: "Scan root: fixture.")]
        )
        let parent = finding(
            path: tempRoot.appendingPathComponent("Library/Caches/Codex").path,
            safety: .autoSafe,
            action: .deleteCache,
            open: false,
            allocatedSize: 100,
            isDirectory: true,
            category: "Codex Cache"
        )
        let child = finding(
            path: tempRoot.appendingPathComponent("Library/Caches/Codex/blob").path,
            safety: .autoSafe,
            action: .deleteCache,
            open: false,
            allocatedSize: 40,
            category: "Codex Cache"
        )

        let overview = FindingAnalytics.overview(
            findings: [root, child, parent],
            scopes: [ScanScope(name: "fixture", root: tempRoot)]
        )

        XCTAssertEqual(overview.totalAllocatedSize, 100)
        XCTAssertEqual(overview.mapNodes.reduce(0) { $0 + $1.allocatedSize }, 100)
        XCTAssertEqual(overview.mapNodes.first?.name, "Codex Cache")
        XCTAssertEqual(overview.mapNodes.first?.isReclaimable, true)
    }

    func testVisualMapKeepsProtectedNodesInformationalOnly() throws {
        let protected = finding(
            path: tempRoot.appendingPathComponent(".codex/sessions/rollout.jsonl").path,
            safety: .preserveByDefault,
            action: .compress,
            open: false,
            allocatedSize: 800,
            category: "Codex History"
        )
        let cache = finding(
            path: tempRoot.appendingPathComponent("Library/Caches/Codex").path,
            safety: .autoSafe,
            action: .deleteCache,
            open: false,
            allocatedSize: 200,
            isDirectory: true,
            category: "Codex Cache"
        )

        let nodes = FindingAnalytics.overview(
            findings: [protected, cache],
            scopes: [ScanScope(name: "fixture", root: tempRoot)]
        ).mapNodes

        let protectedNode = try XCTUnwrap(nodes.first { $0.allocatedSize == 800 })
        XCTAssertEqual(protectedNode.safetyClass, .preserveByDefault)
        XCTAssertFalse(protectedNode.isReclaimable)
        XCTAssertTrue(nodes.contains { $0.isReclaimable })
    }

    func testGrowthDeltasCoverCategoryScopeAndSafety() throws {
        let previous = snapshot(
            category: [
                BucketSummary(name: "Codex", count: 1, logicalSize: 100, allocatedSize: 100),
                BucketSummary(name: "Xcode", count: 1, logicalSize: 80, allocatedSize: 80)
            ],
            scope: [
                BucketSummary(name: "Codex state", count: 1, logicalSize: 100, allocatedSize: 100)
            ],
            safety: [
                BucketSummary(name: SafetyClass.autoSafe.label, count: 1, logicalSize: 100, allocatedSize: 100)
            ]
        )
        let current = snapshot(
            category: [
                BucketSummary(name: "Codex", count: 2, logicalSize: 150, allocatedSize: 150),
                BucketSummary(name: "Browser", count: 1, logicalSize: 20, allocatedSize: 20)
            ],
            scope: [
                BucketSummary(name: "Codex state", count: 2, logicalSize: 150, allocatedSize: 150)
            ],
            safety: [
                BucketSummary(name: SafetyClass.autoSafe.label, count: 2, logicalSize: 150, allocatedSize: 150)
            ]
        )

        let categoryDeltas = FindingAnalytics.growthDeltas(previous: previous, current: current, group: .category)
        XCTAssertEqual(categoryDeltas.first { $0.name == "Codex" }?.deltaAllocatedSize, 50)
        XCTAssertEqual(categoryDeltas.first { $0.name == "Xcode" }?.deltaAllocatedSize, -80)
        XCTAssertEqual(categoryDeltas.first { $0.name == "Browser" }?.deltaAllocatedSize, 20)

        let scopeDeltas = FindingAnalytics.growthDeltas(previous: previous, current: current, group: .scope)
        XCTAssertEqual(scopeDeltas.first { $0.name == "Codex state" }?.deltaAllocatedSize, 50)

        let safetyDeltas = FindingAnalytics.growthDeltas(previous: previous, current: current, group: .safety)
        XCTAssertEqual(safetyDeltas.first { $0.name == SafetyClass.autoSafe.label }?.deltaAllocatedSize, 50)
    }

    func testScanHistoryStoreSavesRecentSnapshotsAndDeltas() throws {
        let historyRoot = tempRoot.appendingPathComponent("History", isDirectory: true)
        let store = ScanHistoryStore(root: historyRoot)
        let older = snapshot(
            id: "older",
            createdAt: Date(timeIntervalSince1970: 10),
            category: [BucketSummary(name: "Codex", count: 1, logicalSize: 100, allocatedSize: 100)]
        )
        let newer = snapshot(
            id: "newer",
            createdAt: Date(timeIntervalSince1970: 20),
            category: [BucketSummary(name: "Codex", count: 1, logicalSize: 140, allocatedSize: 140)]
        )

        try store.save(snapshot: older, keepLimit: 5)
        try store.save(snapshot: newer, keepLimit: 5)

        XCTAssertEqual(store.recent(limit: 2).map(\.id), ["newer", "older"])
        XCTAssertEqual(store.latestGrowthDeltas().first { $0.name == "Codex" }?.deltaAllocatedSize, 40)
    }

    func testDiskStatusPressureThresholdsAndFormatting() {
        let thresholds = DiskStatusThresholds(
            warningFreeBytes: 50,
            criticalFreeBytes: 20,
            warningFreeFraction: 0.20,
            criticalFreeFraction: 0.05
        )

        XCTAssertEqual(DiskStatusReader.pressure(freeBytes: nil, totalBytes: 100, thresholds: thresholds), .unknown)
        XCTAssertEqual(DiskStatusReader.pressure(freeBytes: 10, totalBytes: 1_000, thresholds: thresholds), .critical)
        XCTAssertEqual(DiskStatusReader.pressure(freeBytes: 100, totalBytes: 1_000, thresholds: thresholds), .warning)
        XCTAssertEqual(DiskStatusReader.pressure(freeBytes: 400, totalBytes: 1_000, thresholds: thresholds), .healthy)

        let snapshot = DiskStatusSnapshot(
            path: "/fixture",
            totalBytes: 1_000,
            freeBytes: 100,
            importantFreeBytes: nil,
            availableBytes: nil,
            pressure: .warning,
            notes: []
        )
        XCTAssertEqual(snapshot.freeFraction, 0.1)
        XCTAssertTrue(snapshot.statusLine.contains("free"))
    }

    func testPermissionAdvisorReportsCompleteCoverage() {
        let report = PermissionAdvisor.report(
            scopeSummaries: [
                ScopeAccessSummary(name: "Codex", path: "/fixture/.codex", permissionState: .readable, message: "Directory is readable."),
                ScopeAccessSummary(name: "Caches", path: "/fixture/Library/Caches", permissionState: .readable, message: "Directory is readable.")
            ],
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(report.coverageLevel, .complete)
        XCTAssertEqual(report.readableCount, 2)
        XCTAssertEqual(report.readableFraction, 1)
        XCTAssertFalse(report.needsFullDiskAccessReview)
        XCTAssertTrue(report.recommendedActions.contains { $0.contains("Coverage is complete") })
        XCTAssertTrue(report.nonClaims.contains { $0.contains("does not mean any item is safe") })
    }

    func testPermissionAdvisorSeparatesDeniedAndMissingScopes() {
        let report = PermissionAdvisor.report(
            scopeSummaries: [
                ScopeAccessSummary(name: "Codex", path: "/fixture/.codex", permissionState: .readable, message: "Directory is readable."),
                ScopeAccessSummary(name: "Mail", path: "/fixture/Library/Mail", permissionState: .denied, message: "Path exists but is not readable."),
                ScopeAccessSummary(name: "Colima", path: "/fixture/.colima", permissionState: .missing, message: "Path is not present.")
            ],
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(report.coverageLevel, .degraded)
        XCTAssertEqual(report.deniedCount, 1)
        XCTAssertEqual(report.missingCount, 1)
        XCTAssertTrue(report.needsFullDiskAccessReview)
        XCTAssertEqual(report.unavailableScopes.map(\.name), ["Mail", "Colima"])
        XCTAssertTrue(report.recommendedActions.contains { $0.contains("Grant Full Disk Access") })
        XCTAssertTrue(report.recommendedActions.contains { $0.contains("missing roots") })
        XCTAssertTrue(report.nonClaims.contains { $0.contains("cannot prove macOS Full Disk Access") })
    }

    func testDuplicateReviewGroupsOnlySameContent() throws {
        let duplicatesRoot = tempRoot.appendingPathComponent("Duplicates", isDirectory: true)
        try FileManager.default.createDirectory(at: duplicatesRoot, withIntermediateDirectories: true)
        let duplicateBytes = Data([1, 2, 3, 4, 5, 6])
        try duplicateBytes.write(to: duplicatesRoot.appendingPathComponent("a.bin"))
        try duplicateBytes.write(to: duplicatesRoot.appendingPathComponent("b.bin"))
        try Data([6, 5, 4, 3, 2, 1]).write(to: duplicatesRoot.appendingPathComponent("same-size-different.bin"))

        let report = try DuplicateReviewScanner().scan(
            scopes: [ScanScope(name: "fixture", root: duplicatesRoot)],
            options: DuplicateReviewOptions(minimumFileSize: 1, maximumDepth: 2)
        )

        XCTAssertEqual(report.groups.count, 1)
        let group = try XCTUnwrap(report.groups.first)
        XCTAssertEqual(group.files.map(\.displayName).sorted(), ["a.bin", "b.bin"])
        XCTAssertEqual(group.logicalSize, Int64(duplicateBytes.count))
        XCTAssertEqual(group.apparentDuplicateBytes, try XCTUnwrap(group.files.map(\.allocatedSize).min()))
        XCTAssertTrue(group.files.allSatisfy { $0.safetyClass == .reviewRequired })
        XCTAssertTrue(group.files.allSatisfy { $0.actionKind == .openGuidance })
    }

    func testDuplicateReviewSkipsNeverTouchAndSymlinkFiles() throws {
        let root = tempRoot.appendingPathComponent("Protected", isDirectory: true)
        let codex = root.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        let bytes = Data("secret-ish".utf8)
        let regular = root.appendingPathComponent("copy.txt")
        let auth = codex.appendingPathComponent("auth.json")
        try bytes.write(to: regular)
        try bytes.write(to: auth)

        let target = root.appendingPathComponent("target.bin")
        try Data("symlink target only".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("target-link.bin"),
            withDestinationURL: target
        )

        let report = try DuplicateReviewScanner().scan(
            scopes: [ScanScope(name: "fixture", root: root)],
            options: DuplicateReviewOptions(minimumFileSize: 1, maximumDepth: 4)
        )

        XCTAssertTrue(report.groups.isEmpty)
        XCTAssertTrue(report.skipped.contains { $0.contains("auth.json") })
        XCTAssertFalse(report.groups.flatMap(\.files).contains { $0.path.hasSuffix("target-link.bin") })
    }

    func testDuplicateReviewExcludesPreserveByDefaultUnlessRequested() throws {
        let documents = tempRoot.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let bytes = Data("valuable duplicate draft".utf8)
        try bytes.write(to: documents.appendingPathComponent("draft-a.txt"))
        try bytes.write(to: documents.appendingPathComponent("draft-b.txt"))

        let scanner = try DuplicateReviewScanner()
        let defaultReport = scanner.scan(
            scopes: [ScanScope(name: "documents", root: documents)],
            options: DuplicateReviewOptions(minimumFileSize: 1, maximumDepth: 2)
        )
        XCTAssertTrue(defaultReport.groups.isEmpty)
        XCTAssertTrue(defaultReport.skipped.contains { $0.contains("preserve-by-default") })

        let includedReport = scanner.scan(
            scopes: [ScanScope(name: "documents", root: documents)],
            options: DuplicateReviewOptions(minimumFileSize: 1, maximumDepth: 2, includePreserveByDefault: true)
        )
        let group = try XCTUnwrap(includedReport.groups.first)
        XCTAssertEqual(group.files.count, 2)
        XCTAssertTrue(group.files.allSatisfy { $0.safetyClass == .preserveByDefault })
    }

    func testAppReviewFindsInstalledAppRelatedFiles() throws {
        let appRoot = tempRoot.appendingPathComponent("Applications", isDirectory: true)
        let home = tempRoot.appendingPathComponent("Home", isDirectory: true)
        try createAppBundle(
            at: appRoot.appendingPathComponent("Fixture.app", isDirectory: true),
            bundleIdentifier: "com.example.fixture",
            displayName: "Fixture"
        )
        let cache = home.appendingPathComponent("Library/Caches/com.example.fixture/cache.bin")
        let preferences = home.appendingPathComponent("Library/Preferences/com.example.fixture.plist")
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: preferences.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 512).write(to: cache)
        try Data(repeating: 2, count: 512).write(to: preferences)

        let report = try AppReviewScanner().scan(
            options: AppReviewOptions(
                appRoots: [appRoot],
                home: home,
                minimumRelatedSize: 1,
                measurementDepth: 2
            )
        )

        XCTAssertEqual(report.installedApps.map(\.bundleIdentifier), ["com.example.fixture"])
        let group = try XCTUnwrap(report.installedAppGroups.first)
        XCTAssertEqual(group.ownerName, "Fixture")
        XCTAssertTrue(group.isInstalled)
        XCTAssertTrue(group.items.contains { $0.category == "App cache" && $0.safetyClass == .safeAfterCondition && $0.actionKind == .openGuidance })
        XCTAssertTrue(group.items.contains { $0.category == "App preferences" && $0.safetyClass == .preserveByDefault && $0.actionKind == .reportOnly })
    }

    func testAppReviewSurfacesOrphanCandidatesAsReviewOnly() throws {
        let appRoot = tempRoot.appendingPathComponent("Applications", isDirectory: true)
        let home = tempRoot.appendingPathComponent("Home", isDirectory: true)
        try FileManager.default.createDirectory(at: appRoot, withIntermediateDirectories: true)
        let orphanCache = home.appendingPathComponent("Library/Caches/com.example.removed/blob")
        try FileManager.default.createDirectory(at: orphanCache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 3, count: 512).write(to: orphanCache)

        let report = try AppReviewScanner().scan(
            options: AppReviewOptions(
                appRoots: [appRoot],
                home: home,
                includeOrphanCandidates: true,
                minimumRelatedSize: 1,
                measurementDepth: 2
            )
        )

        XCTAssertTrue(report.installedApps.isEmpty)
        let orphan = try XCTUnwrap(report.orphanGroups.first)
        XCTAssertFalse(orphan.isInstalled)
        XCTAssertEqual(orphan.bundleIdentifier, "com.example.removed")
        XCTAssertEqual(orphan.items.first?.safetyClass, .reviewRequired)
        XCTAssertEqual(orphan.items.first?.actionKind, .openGuidance)

        let finding = finding(
            path: orphan.items[0].path,
            safety: orphan.items[0].safetyClass,
            action: orphan.items[0].actionKind,
            open: false,
            allocatedSize: orphan.items[0].allocatedSize,
            isDirectory: orphan.items[0].isDirectory,
            category: orphan.items[0].category
        )
        let plan = PlanBuilder(openFileChecker: NoOpenFilesChecker()).buildPlan(from: [finding], mode: .autoSafeOnly)
        XCTAssertFalse(plan.items.first?.selected ?? true)
    }

    func testExpandedDeveloperRulesStayConservative() throws {
        let engine = try RuleEngine.bundled()

        let nodeModules = engine.classify(
            path: "/Users/test/Project/node_modules",
            isDirectory: true,
            isSymbolicLink: false
        )
        XCTAssertEqual(nodeModules.safetyClass, .reviewRequired)
        XCTAssertEqual(nodeModules.actionKind, .openGuidance)

        let playwright = engine.classify(
            path: "/Users/test/Library/Caches/ms-playwright/chromium-123",
            isDirectory: true,
            isSymbolicLink: false
        )
        XCTAssertEqual(playwright.safetyClass, .safeAfterCondition)
        XCTAssertEqual(playwright.actionKind, .deleteCache)

        let androidSDK = engine.classify(
            path: "/Users/test/Library/Android/sdk/platforms/android-35",
            isDirectory: true,
            isSymbolicLink: false
        )
        XCTAssertEqual(androidSDK.safetyClass, .reviewRequired)
        XCTAssertEqual(androidSDK.actionKind, .openGuidance)
    }

    func testNativeToolGuidanceBuildsPreviewReceipts() throws {
        let docker = finding(
            path: "/Users/test/.colima/default/disk.img",
            safety: .reviewRequired,
            action: .nativeToolCommand,
            open: false,
            allocatedSize: 2_000,
            isDirectory: false,
            category: "Containers"
        )
        let homebrew = finding(
            path: "/Users/test/Library/Caches/Homebrew",
            safety: .safeAfterCondition,
            action: .nativeToolCommand,
            open: false,
            allocatedSize: 1_000,
            isDirectory: true,
            category: "Developer cache"
        )

        let report = NativeToolGuidance.report(for: [docker, homebrew], ruleVersion: "test")

        XCTAssertEqual(report.receipts.count, 2)
        XCTAssertEqual(report.totalBytesUnderNativeReview, 3_000)
        XCTAssertTrue(report.nonClaims.contains { $0.contains("No native cleanup command was executed") })
        XCTAssertTrue(report.receipts.flatMap(\.commands).contains { $0.command == "colima list" && $0.risk == .inspect })
        XCTAssertTrue(report.receipts.flatMap(\.commands).contains { $0.command == "colima delete <profile>" && $0.risk == .destructive && $0.requiresReview })
        XCTAssertTrue(report.receipts.flatMap(\.commands).contains { $0.command == "brew cleanup -n" && $0.risk == .inspect })
        XCTAssertTrue(report.receipts.allSatisfy { $0.status == "preview-only" })
    }

    func testNativeToolReportDeduplicatesNestedReceipts() throws {
        let rootPath = "/Users/test/Library/Caches/Homebrew"
        let root = finding(
            path: rootPath,
            safety: .safeAfterCondition,
            action: .nativeToolCommand,
            open: false,
            allocatedSize: 1_000,
            isDirectory: true,
            category: "Developer cache"
        )
        let child = finding(
            path: "\(rootPath)/downloads/bottle.tar.gz",
            safety: .safeAfterCondition,
            action: .nativeToolCommand,
            open: false,
            allocatedSize: 200,
            category: "Developer cache"
        )

        let report = NativeToolGuidance.report(for: [child, root], ruleVersion: "test")

        XCTAssertEqual(report.receipts.map(\.findingPath), [rootPath])
        XCTAssertEqual(report.totalBytesUnderNativeReview, 1_000)
    }

    func testNativeToolFindingsStayOutOfExecutionPlans() throws {
        let docker = finding(
            path: "/Users/test/.docker",
            safety: .reviewRequired,
            action: .nativeToolCommand,
            open: false,
            category: "Containers"
        )

        let plan = PlanBuilder(openFileChecker: NoOpenFilesChecker()).buildPlan(from: [docker], mode: .reviewAll)
        let receipt = ReclaimerExecutor(openFileChecker: NoOpenFilesChecker())
            .execute(plan: plan, mode: .perform, ruleVersion: "test", userConfirmed: true)

        XCTAssertFalse(plan.items.first?.selected ?? true)
        XCTAssertTrue(receipt.actions.isEmpty)
    }

    func testContainerInventoryParsesDockerAndColimaReadOnlyOutput() throws {
        let runner = FakeToolRunner(outputs: [
            fakeOutput(
                "docker",
                ["system", "df"],
                stdout: """
                TYPE            TOTAL     ACTIVE    SIZE      RECLAIMABLE
                Images          7         2         5.694GB   5.151GB (90%)
                Containers      5         0         257.6MB   257.6MB (100%)
                Local Volumes   4         1         455MB     123MB (27%)
                Build Cache     140       0         11.55GB   11.55GB
                """
            ),
            fakeOutput(
                "docker",
                ["context", "ls"],
                stdout: """
                NAME        DESCRIPTION                               DOCKER ENDPOINT
                default *   Current DOCKER_HOST based configuration   unix:///var/run/docker.sock
                """
            ),
            fakeOutput(
                "docker",
                ["ps", "-a", "--size", "--format", "{{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Size}}"],
                stdout: "abc123\tpostgres\tExited (0) 2 days ago\t12.3MB (virtual 400MB)\n"
            ),
            fakeOutput(
                "docker",
                ["images", "--format", "{{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}"],
                stdout: "postgres\t16\timg123\t432MB\n"
            ),
            fakeOutput(
                "docker",
                ["volume", "ls", "--format", "{{.Name}}\t{{.Driver}}\t{{.Scope}}"],
                stdout: "db-data\tlocal\tlocal\n"
            ),
            fakeOutput(
                "colima",
                ["list", "--json"],
                stdout: """
                [
                  {"name":"default","status":"Running","runtime":"docker","arch":"aarch64","cpus":4,"memory":"8GiB","disk":"100GiB"}
                ]
                """
            )
        ])

        let report = ContainerInventoryScanner(runner: runner, timeout: 1).inspect()

        XCTAssertEqual(report.docker.status.state, .available)
        XCTAssertEqual(report.docker.storage.first { $0.type == "Images" }?.reclaimableBytes, 5_151_000_000)
        XCTAssertEqual(report.docker.containers.first?.name, "postgres")
        XCTAssertEqual(report.docker.images.first?.repository, "postgres")
        XCTAssertEqual(report.docker.volumes.first?.name, "db-data")
        XCTAssertEqual(report.colima.status.state, .available)
        XCTAssertEqual(report.colima.profiles.first?.name, "default")
        XCTAssertEqual(report.colima.profiles.first?.cpu, "4")
        XCTAssertTrue(report.nonClaims.contains { $0.contains("No prune") })
        XCTAssertTrue(runner.commands.allSatisfy { command in
            !command.contains("prune") && !command.contains("delete") && !command.contains("stop") && !command.contains("reset")
        })
    }

    func testContainerInventoryHandlesMissingToolsWithoutExtraFanout() throws {
        let runner = FakeToolRunner(outputs: [
            fakeOutput(
                "docker",
                ["system", "df"],
                exitCode: 127,
                stderr: "/usr/bin/env: docker: No such file or directory\n"
            ),
            fakeOutput(
                "colima",
                ["list", "--json"],
                exitCode: 127,
                stderr: "/usr/bin/env: colima: No such file or directory\n"
            )
        ])

        let report = ContainerInventoryScanner(runner: runner, timeout: 1).inspect()

        XCTAssertEqual(report.docker.status.state, .missing)
        XCTAssertEqual(report.colima.status.state, .missing)
        XCTAssertEqual(runner.commands, ["docker system df", "colima list --json"])
        XCTAssertTrue(report.docker.commands.allSatisfy { $0.command == "docker system df" })
        XCTAssertTrue(report.colima.commands.allSatisfy { $0.command == "colima list --json" })
    }

    func testContainerInventoryClassifiesDockerSocketFailureAsNotRunning() throws {
        let runner = FakeToolRunner(outputs: [
            fakeOutput(
                "docker",
                ["system", "df"],
                exitCode: 1,
                stderr: "failed to connect to the docker API at unix:///var/run/docker.sock: dial unix /var/run/docker.sock: connect: no such file or directory\n"
            ),
            fakeOutput(
                "colima",
                ["list", "--json"],
                stdout: "[]"
            )
        ])

        let report = ContainerInventoryScanner(runner: runner, timeout: 1).inspect()

        XCTAssertEqual(report.docker.status.state, .notRunning)
        XCTAssertEqual(report.colima.status.state, .available)
        XCTAssertEqual(runner.commands, ["docker system df", "colima list --json"])
    }

    func testUserPathPolicyStoreRoundTripsRules() throws {
        let store = UserPathPolicyStore(root: tempRoot.appendingPathComponent("Config", isDirectory: true))
        let protected = tempRoot.appendingPathComponent("Projects/valuable", isDirectory: true)
        let excluded = tempRoot.appendingPathComponent("Caches/noisy", isDirectory: true)

        _ = try store.add(path: protected.path, kind: .protect, reason: "fixture value")
        _ = try store.add(path: excluded.path, kind: .exclude, reason: "too noisy")

        let loaded = store.load()
        XCTAssertEqual(loaded.rules(kind: .protect).first?.path, protected.standardizedFileURL.path)
        XCTAssertEqual(loaded.rules(kind: .protect).first?.reason, "fixture value")
        XCTAssertEqual(loaded.rules(kind: .exclude).first?.path, excluded.standardizedFileURL.path)

        _ = try store.remove(path: excluded.path, kind: .exclude)
        XCTAssertTrue(store.load().rules(kind: .exclude).isEmpty)
    }

    func testScannerAppliesUserExclusionsAndDoesNotMeasureExcludedDescendants() throws {
        let include = tempRoot.appendingPathComponent("Root/include.bin")
        let excluded = tempRoot.appendingPathComponent("Root/Excluded/excluded.bin")
        try FileManager.default.createDirectory(at: include.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: excluded.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100).write(to: include)
        try Data(repeating: 2, count: 1_000).write(to: excluded)

        let policy = UserPathPolicy(rules: [
            UserPathRule(kind: .exclude, path: excluded.deletingLastPathComponent().path, reason: "fixture")
        ])
        let scanner = try FileScanner(openFileChecker: NoOpenFilesChecker())
        let findings = scanner.scan(
            scopes: [ScanScope(name: "fixture", root: tempRoot.appendingPathComponent("Root"))],
            options: ScanOptions(minimumFindingSize: 0, maximumFindingDepth: 3, includeOpenFileStatus: false, userPathPolicy: policy)
        )

        XCTAssertFalse(findings.contains { $0.path.contains("/Excluded") })
        let root = try XCTUnwrap(findings.first { $0.path.hasSuffix("/Root") })
        XCTAssertEqual(root.logicalSize, 100)
    }

    func testScannerAppliesUserProtectionBeforePlanning() throws {
        let cache = tempRoot.appendingPathComponent("Library/Caches/Codex/cache.bin")
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 3, count: 128).write(to: cache)
        let policy = UserPathPolicy(rules: [
            UserPathRule(kind: .protect, path: cache.deletingLastPathComponent().path, reason: "keep this cache")
        ])

        let findings = try FileScanner(openFileChecker: NoOpenFilesChecker()).scan(
            scopes: [ScanScope(name: "fixture", root: tempRoot.appendingPathComponent("Library/Caches/Codex"))],
            options: ScanOptions(minimumFindingSize: 0, maximumFindingDepth: 1, includeOpenFileStatus: false, userPathPolicy: policy)
        )

        let protected = try XCTUnwrap(findings.first { $0.path.hasSuffix("/Library/Caches/Codex") })
        XCTAssertEqual(protected.safetyClass, .preserveByDefault)
        XCTAssertEqual(protected.actionKind, .reportOnly)
        XCTAssertEqual(protected.ruleMatches.first?.ruleID, "user.path.protected")
        XCTAssertTrue(protected.evidence.contains { $0.message.contains("keep this cache") })

        let plan = PlanBuilder(openFileChecker: NoOpenFilesChecker()).buildPlan(from: findings, mode: .reviewAll)
        XCTAssertFalse(plan.items.contains { $0.selected })
    }

    func testExecutorBlocksStalePlanWhenUserProtectsPath() throws {
        let cache = tempRoot.appendingPathComponent("Library/Caches/Codex/cache.bin")
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 4, count: 128).write(to: cache)
        let plannedFinding = finding(path: cache.path, safety: .autoSafe, action: .deleteCache, open: false)
        let plan = ReclaimPlan(
            mode: "test",
            items: [
                ReclaimPlanItem(
                    finding: plannedFinding,
                    selected: true,
                    proposedAction: .deleteCache,
                    conditions: [PlanCondition(message: "fixture", isSatisfied: true)],
                    estimatedImmediateReclaim: 128
                )
            ],
            dryRunSummary: []
        )
        let policy = UserPathPolicy(rules: [
            UserPathRule(kind: .protect, path: cache.path, reason: "late protection")
        ])

        let receipt = ReclaimerExecutor(
            openFileChecker: NoOpenFilesChecker(),
            configuration: ExecutorConfiguration(userPathPolicy: policy)
        )
        .execute(plan: plan, mode: .perform, ruleVersion: "test", userConfirmed: true)

        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertEqual(receipt.actions.first?.status, "skipped")
        XCTAssertTrue(receipt.actions.first?.message.contains("user protection") ?? false)
    }

    func testPlanBuilderSelectsOnlyAutoSafeClosedFindings() throws {
        let open = finding(path: tempRoot.appendingPathComponent("Library/Caches/Codex/open").path, safety: .autoSafe, action: .deleteCache, open: true)
        let closed = finding(path: tempRoot.appendingPathComponent("Library/Caches/Codex/closed").path, safety: .autoSafe, action: .deleteCache, open: false)
        let preserve = finding(path: tempRoot.appendingPathComponent(".codex/sessions/rollout.jsonl").path, safety: .preserveByDefault, action: .compress, open: false)

        let plan = PlanBuilder(openFileChecker: NoOpenFilesChecker()).buildPlan(from: [open, closed, preserve], mode: .autoSafeOnly)

        XCTAssertEqual(plan.items.filter(\.selected).map(\.finding.path), [closed.path])
        XCTAssertGreaterThan(plan.expectedImmediateReclaim, 0)
    }

    func testPlanBuilderFailsClosedForUnverifiedRuleConditions() throws {
        let staleCondition = finding(
            path: tempRoot.appendingPathComponent("private/tmp/vifty-old").path,
            safety: .autoSafe,
            action: .deleteCache,
            open: false,
            conditions: ["Only delete stale paths with no open handles."]
        )
        let openOnlyCondition = finding(
            path: tempRoot.appendingPathComponent("Library/Caches/Codex/cache").path,
            safety: .autoSafe,
            action: .deleteCache,
            open: false,
            conditions: ["Skip files open by Codex."]
        )

        let plan = PlanBuilder(openFileChecker: NoOpenFilesChecker()).buildPlan(from: [staleCondition, openOnlyCondition], mode: .autoSafeOnly)

        XCTAssertFalse(plan.items.first { $0.finding.path == staleCondition.path }?.selected ?? true)
        XCTAssertTrue(plan.items.first { $0.finding.path == openOnlyCondition.path }?.selected ?? false)
        XCTAssertTrue(plan.items.first { $0.finding.path == staleCondition.path }?.conditions.contains { $0.message.contains("stale") && !$0.isSatisfied } ?? false)
    }

    func testPlanBuilderDeduplicatesNestedSelectedFindings() throws {
        let parentPath = tempRoot.appendingPathComponent("Library/Caches/Codex").path
        let childPath = tempRoot.appendingPathComponent("Library/Caches/Codex/blob").path
        let parent = finding(path: parentPath, safety: .autoSafe, action: .deleteCache, open: false, allocatedSize: 1_000, isDirectory: true)
        let child = finding(path: childPath, safety: .autoSafe, action: .deleteCache, open: false, allocatedSize: 400)

        let plan = PlanBuilder(openFileChecker: NoOpenFilesChecker()).buildPlan(from: [child, parent], mode: .autoSafeOnly)

        XCTAssertTrue(plan.items.first { $0.finding.path == parentPath }?.selected ?? false)
        XCTAssertFalse(plan.items.first { $0.finding.path == childPath }?.selected ?? true)
        XCTAssertEqual(plan.expectedImmediateReclaim, 1_000)
    }

    func testExecutorDryRunNeverMutatesFiles() throws {
        let cache = tempRoot.appendingPathComponent("Library/Caches/Codex/cache.bin")
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 2, count: 128).write(to: cache)

        let scan = try FileScanner(openFileChecker: NoOpenFilesChecker()).scan(
            scopes: [ScanScope(name: "cache", root: cache.deletingLastPathComponent())],
            options: ScanOptions(minimumFindingSize: 0, maximumFindingDepth: 1, includeOpenFileStatus: true)
        )
        let plan = PlanBuilder(openFileChecker: NoOpenFilesChecker()).buildPlan(from: scan, mode: .autoSafeOnly)
        let receipt = ReclaimerExecutor(openFileChecker: NoOpenFilesChecker())
            .execute(plan: plan, mode: .dryRun, ruleVersion: "test", userConfirmed: false)

        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertTrue(receipt.actions.allSatisfy { $0.status == "dry-run" })
    }

    func testExecutorPerformsDirectDeleteForAutoSafeCacheFixture() throws {
        let cacheRoot = tempRoot.appendingPathComponent("Library/Caches/Codex", isDirectory: true)
        let cacheFile = cacheRoot.appendingPathComponent("cache.bin")
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 128).write(to: cacheFile)

        let scan = try FileScanner(openFileChecker: NoOpenFilesChecker()).scan(
            scopes: [ScanScope(name: "cache", root: cacheRoot)],
            options: ScanOptions(minimumFindingSize: 0, maximumFindingDepth: 1, includeOpenFileStatus: false)
        )
        let plan = PlanBuilder(openFileChecker: NoOpenFilesChecker()).buildPlan(from: scan, mode: .autoSafeOnly)
        let receipt = ReclaimerExecutor(openFileChecker: NoOpenFilesChecker())
            .execute(plan: plan, mode: .perform, ruleVersion: "test", userConfirmed: true)

        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheRoot.path))
        XCTAssertTrue(receipt.actions.contains { $0.status == "done" && $0.action == .deleteCache })
        XCTAssertTrue(receipt.errors.isEmpty)
    }

    func testExecutorDirectDeleteRefusesPreserveByDefault() throws {
        let file = tempRoot.appendingPathComponent("rollout.jsonl")
        try Data(repeating: 3, count: 128).write(to: file)
        let protected = finding(path: file.path, safety: .preserveByDefault, action: .deleteCache, open: false)
        let plan = ReclaimPlan(
            mode: "test",
            items: [
                ReclaimPlanItem(
                    finding: protected,
                    selected: true,
                    proposedAction: .deleteCache,
                    conditions: [PlanCondition(message: "fixture", isSatisfied: true)],
                    estimatedImmediateReclaim: 128
                )
            ],
            dryRunSummary: []
        )

        let receipt = ReclaimerExecutor(openFileChecker: NoOpenFilesChecker())
            .execute(plan: plan, mode: .perform, ruleVersion: "test", userConfirmed: true)

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(receipt.actions.first?.status, "skipped")
    }

    func testExecutorSkipsPathThatChangedIntoSymlinkAfterPlanning() throws {
        let cache = tempRoot.appendingPathComponent("Library/Caches/Codex", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(repeating: 9, count: 128).write(to: cache.appendingPathComponent("cache.bin"))
        let plannedFinding = finding(path: cache.path, safety: .autoSafe, action: .deleteCache, open: false, allocatedSize: 128, isDirectory: true)
        let plan = ReclaimPlan(
            mode: "test",
            items: [
                ReclaimPlanItem(
                    finding: plannedFinding,
                    selected: true,
                    proposedAction: .deleteCache,
                    conditions: [PlanCondition(message: "fixture", isSatisfied: true)],
                    estimatedImmediateReclaim: 128
                )
            ],
            dryRunSummary: []
        )

        let target = tempRoot.appendingPathComponent("do-not-delete", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data(repeating: 8, count: 128).write(to: target.appendingPathComponent("valuable.bin"))
        try FileManager.default.removeItem(at: cache)
        try FileManager.default.createSymbolicLink(at: cache, withDestinationURL: target)

        let receipt = ReclaimerExecutor(openFileChecker: NoOpenFilesChecker())
            .execute(plan: plan, mode: .perform, ruleVersion: "test", userConfirmed: true)

        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("valuable.bin").path))
        XCTAssertTrue(receipt.actions.contains { $0.status == "skipped" && $0.message.contains("symbolic link") })
    }

    func testQuarantineHoldCanMoveFixture() throws {
        let file = tempRoot.appendingPathComponent("cache.bin")
        try Data(repeating: 4, count: 128).write(to: file)
        let holdRoot = tempRoot.appendingPathComponent("Holding", isDirectory: true)
        let candidate = finding(path: file.path, safety: .safeAfterCondition, action: .quarantineHold, open: false)
        let engine = RuleEngine(
            version: "test",
            rules: [
                ReclaimerRule(
                    id: "fixture.hold",
                    title: "Fixture hold",
                    category: "Fixture",
                    priority: 1,
                    safetyClass: .safeAfterCondition,
                    actionKind: .quarantineHold,
                    match: RuleMatchSpec(containsAny: [file.path.lowercased()]),
                    evidence: ["Fixture rule."]
                )
            ]
        )
        let plan = ReclaimPlan(
            mode: "test",
            items: [
                ReclaimPlanItem(
                    finding: candidate,
                    selected: true,
                    proposedAction: .quarantineHold,
                    conditions: [PlanCondition(message: "fixture", isSatisfied: true)],
                    estimatedImmediateReclaim: 0
                )
            ],
            dryRunSummary: []
        )

        let receipt = ReclaimerExecutor(
            openFileChecker: NoOpenFilesChecker(),
            configuration: ExecutorConfiguration(holdingRoot: holdRoot),
            ruleEngine: engine
        )
        .execute(plan: plan, mode: .perform, ruleVersion: "test", userConfirmed: true)

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(receipt.actions.first?.status, "done")
        XCTAssertTrue((try FileManager.default.subpathsOfDirectory(atPath: holdRoot.path)).contains("cache.bin") == false)
        XCTAssertTrue((try FileManager.default.subpathsOfDirectory(atPath: holdRoot.path)).contains { $0.hasSuffix("cache.bin") })

        let store = HoldingStore(root: holdRoot)
        let held = store.list()
        XCTAssertEqual(held.count, 1)
        XCTAssertEqual(held.first?.originalPath, file.path)

        let restored = try store.restore(id: try XCTUnwrap(held.first?.id))
        XCTAssertEqual(restored.path, file.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(store.list().isEmpty)
    }

    func testHoldingStoreExpireDryRunAndConfirmedRemoval() throws {
        let heldRoot = tempRoot.appendingPathComponent("Holding", isDirectory: true)
        let source = tempRoot.appendingPathComponent("source.bin")
        try Data(repeating: 5, count: 128).write(to: source)
        let heldDirectory = heldRoot.appendingPathComponent("2026-07-05T22-00-00Z", isDirectory: true)
        let heldFile = heldDirectory.appendingPathComponent("source.bin")
        try FileManager.default.createDirectory(at: heldDirectory, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: source, to: heldFile)
        try HoldingStore(root: heldRoot).recordHold(
            source: source,
            target: heldFile,
            finding: finding(path: source.path, safety: .safeAfterCondition, action: .quarantineHold, open: false)
        )

        let store = HoldingStore(root: heldRoot)
        let dryRunExpired = try store.expire(olderThan: Date().addingTimeInterval(1), dryRun: true)
        XCTAssertEqual(dryRunExpired.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: heldFile.path))

        let removed = try store.expire(olderThan: Date().addingTimeInterval(1), dryRun: false)
        XCTAssertEqual(removed.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: heldDirectory.path))
    }

    func testLaunchAgentPlistContainsReportOnlyScan() {
        let plist = LaunchAgentManager().plist(cliPath: "/tmp/reclaimer", logPath: "/tmp/reclaimer.log")
        XCTAssertTrue(plist.contains("<string>plan</string>"))
        XCTAssertTrue(plist.contains("<string>--json</string>"))
        XCTAssertTrue(plist.contains("<string>--save-audit</string>"))
        XCTAssertTrue(plist.contains("com.reidar.ryddi.agent"))
    }

    func testAuditStoreRoundTripsPlansAndReceipts() throws {
        let auditRoot = tempRoot.appendingPathComponent("Audit", isDirectory: true)
        let store = AuditStore(root: auditRoot)
        let candidate = finding(path: tempRoot.appendingPathComponent("Library/Caches/Codex/cache").path, safety: .autoSafe, action: .deleteCache, open: false)
        let plan = ReclaimPlan(
            mode: "test",
            items: [
                ReclaimPlanItem(
                    finding: candidate,
                    selected: true,
                    proposedAction: .deleteCache,
                    conditions: [PlanCondition(message: "fixture", isSatisfied: true)],
                    estimatedImmediateReclaim: 128
                )
            ],
            dryRunSummary: ["fixture"]
        )
        let receipt = ExecutionReceipt(
            ruleVersion: "test",
            mode: "dryRun",
            beforeFreeBytes: nil,
            afterFreeBytes: nil,
            actions: [
                ExecutionActionReceipt(path: candidate.path, action: .deleteCache, status: "dry-run", message: "fixture")
            ],
            userConfirmed: false
        )
        let nativeReport = NativeToolGuidance.report(
            for: [
                finding(
                    path: "/Users/test/Library/Caches/Homebrew",
                    safety: .safeAfterCondition,
                    action: .nativeToolCommand,
                    open: false,
                    category: "Developer cache"
                )
            ],
            ruleVersion: "test"
        )
        let containerReport = ContainerInventoryScanner(
            runner: FakeToolRunner(
                outputs: [
                    fakeOutput("docker", ["system", "df"], exitCode: 127, stderr: "docker: not found"),
                    fakeOutput("colima", ["list", "--json"], exitCode: 127, stderr: "colima: not found")
                ]
            ),
            timeout: 1
        ).inspect()

        _ = try store.save(plan: plan)
        _ = try store.save(receipt: receipt)
        _ = try store.save(nativeToolReport: nativeReport)
        _ = try store.save(containerInventoryReport: containerReport)

        XCTAssertEqual(store.recentPlans().first?.id, plan.id)
        XCTAssertEqual(store.recentReceipts().first?.id, receipt.id)
        XCTAssertEqual(store.receipt(id: String(receipt.id.prefix(8)))?.id, receipt.id)
        XCTAssertEqual(store.recentNativeToolReports().first?.id, nativeReport.id)
        XCTAssertEqual(store.recentContainerInventoryReports().first?.id, containerReport.id)
    }

    private final class FakeToolRunner: ToolCommandRunning, @unchecked Sendable {
        private let lock = NSLock()
        private let outputs: [String: ToolCommandOutput]
        private var recordedCommands: [String] = []

        init(outputs: [ToolCommandOutput]) {
            self.outputs = Dictionary(uniqueKeysWithValues: outputs.map { ($0.invocation.displayCommand, $0) })
        }

        var commands: [String] {
            lock.lock()
            defer { lock.unlock() }
            return recordedCommands
        }

        func run(_ invocation: ToolCommandInvocation, timeout: TimeInterval) -> ToolCommandOutput {
            lock.lock()
            recordedCommands.append(invocation.displayCommand)
            lock.unlock()
            return outputs[invocation.displayCommand] ?? ToolCommandOutput(
                invocation: invocation,
                exitCode: 1,
                stderr: "unexpected fake command: \(invocation.displayCommand)"
            )
        }
    }

    private func fakeOutput(
        _ executable: String,
        _ arguments: [String],
        exitCode: Int32 = 0,
        stdout: String = "",
        stderr: String = ""
    ) -> ToolCommandOutput {
        ToolCommandOutput(
            invocation: ToolCommandInvocation(executable: executable, arguments: arguments),
            exitCode: exitCode,
            stdout: stdout,
            stderr: stderr
        )
    }

    private func finding(
        path: String,
        safety: SafetyClass,
        action: ActionKind,
        open: Bool,
        conditions: [String] = [],
        allocatedSize: Int64 = 128,
        isDirectory: Bool = false,
        category: String = "Fixture"
    ) -> Finding {
        let matches = [
            RuleMatch(
                ruleID: "fixture.rule",
                title: "Fixture rule",
                category: category,
                safetyClass: safety,
                actionKind: action,
                evidence: ["Fixture evidence."],
                conditions: conditions
            )
        ]
        return Finding(
            scopeName: "fixture",
            path: path,
            displayName: URL(fileURLWithPath: path).lastPathComponent,
            logicalSize: allocatedSize,
            allocatedSize: allocatedSize,
            isDirectory: isDirectory,
            safetyClass: safety,
            actionKind: action,
            ruleMatches: matches,
            evidence: matches.flatMap { $0.evidence.map { Evidence(kind: "fixture", message: $0) } },
            openFileStatus: OpenFileStatus(isOpen: open, processSummary: open ? ["fixture"] : [])
        )
    }

    private func createAppBundle(at url: URL, bundleIdentifier: String, displayName: String) throws {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleDisplayName": displayName,
            "CFBundleName": displayName,
            "CFBundleShortVersionString": "1.0",
            "CFBundleExecutable": displayName
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    private func snapshot(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        category: [BucketSummary],
        scope: [BucketSummary] = [],
        safety: [BucketSummary] = []
    ) -> ScanSnapshot {
        ScanSnapshot(
            id: id,
            createdAt: createdAt,
            findingCount: category.reduce(0) { $0 + $1.count },
            totalLogicalSize: category.reduce(0) { $0 + $1.logicalSize },
            totalAllocatedSize: category.reduce(0) { $0 + $1.allocatedSize },
            expectedAutoSafeBytes: 0,
            reviewBytes: 0,
            protectedBytes: 0,
            categorySummaries: category,
            safetySummaries: safety,
            scopeBuckets: scope,
            scopeSummaries: [],
            topFindingPaths: []
        )
    }
}
