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

        _ = try store.save(plan: plan)
        _ = try store.save(receipt: receipt)

        XCTAssertEqual(store.recentPlans().first?.id, plan.id)
        XCTAssertEqual(store.recentReceipts().first?.id, receipt.id)
    }

    private func finding(
        path: String,
        safety: SafetyClass,
        action: ActionKind,
        open: Bool,
        conditions: [String] = [],
        allocatedSize: Int64 = 128,
        isDirectory: Bool = false
    ) -> Finding {
        let matches = conditions.isEmpty ? [] : [
            RuleMatch(
                ruleID: "fixture.rule",
                title: "Fixture rule",
                category: "Fixture",
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
}
