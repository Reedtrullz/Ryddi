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

    func testAgentStorageReviewSeparatesCacheHistoryAndProtectedState() throws {
        let codexCache = tempRoot.appendingPathComponent(".codex/cache/blob.bin")
        let codexSession = tempRoot.appendingPathComponent(".codex/sessions/2026/07/session.jsonl")
        let codexAuth = tempRoot.appendingPathComponent(".codex/auth.json")
        let claudeProject = tempRoot.appendingPathComponent(".claude/projects/project.jsonl")
        let cursorCache = tempRoot.appendingPathComponent("Library/Application Support/Cursor/Cache/cache.bin")
        let ollamaModel = tempRoot.appendingPathComponent(".ollama/models/blobs/model.bin")

        for url in [codexCache, codexSession, codexAuth, claudeProject, cursorCache, ollamaModel] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: UInt8(url.path.count % 255), count: 256).write(to: url)
        }

        let scopes = DefaultScopes.aiAgentStorage(home: tempRoot, includeUnavailable: false)
        let findings = try FileScanner(openFileChecker: NoOpenFilesChecker()).scan(
            scopes: scopes,
            options: ScanOptions(
                minimumFindingSize: 1,
                maximumFindingDepth: 4,
                measurementDepth: 8,
                includeOpenFileStatus: false
            )
        )
        let report = AgentStorageReviewBuilder.build(
            findings: findings,
            scopes: scopes,
            limit: 30,
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertGreaterThan(report.itemCount, 0)
        XCTAssertGreaterThan(report.reclaimableBytes, 0)
        XCTAssertTrue(report.bucketSummaries.contains { $0.bucket == .reclaimableCache && $0.bytes > 0 })
        XCTAssertTrue(report.bucketSummaries.contains { $0.bucket == .valuableHistory && $0.bytes > 0 })
        XCTAssertTrue(report.bucketSummaries.contains { $0.bucket == .protectedState && $0.bytes > 0 })
        XCTAssertTrue(report.bucketSummaries.contains { $0.bucket == .quitFirst && $0.bytes > 0 })
        XCTAssertTrue(report.ownerSummaries.contains { $0.owner == "Codex" })
        XCTAssertTrue(report.ownerSummaries.contains { $0.owner == "Claude" })
        XCTAssertTrue(report.ownerSummaries.contains { $0.owner == "Cursor" })
        XCTAssertTrue(report.ownerSummaries.contains { $0.owner == "Ollama" })
        XCTAssertTrue(report.items.contains { $0.path.hasSuffix("/.codex/auth.json") && $0.bucket == .protectedState })
        XCTAssertTrue(report.items.contains { $0.path.contains("/.codex/sessions/") && $0.bucket == .valuableHistory })
        XCTAssertTrue(report.items.contains { $0.path.contains("/.claude/projects/") && $0.bucket == .valuableHistory })
        XCTAssertTrue(report.nonClaims.contains { $0.contains("does not delete agent sessions") })
    }

    func testRuleCatalogExplainsSafetyBucketsAndNeverTouchRules() throws {
        let catalog = try RuleEngine.bundled().catalog(generatedAt: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(catalog.ruleVersion, "2026.07.05-mvp1")
        XCTAssertGreaterThan(catalog.ruleCount, 10)
        XCTAssertEqual(catalog.userRuleCount, 0)
        XCTAssertTrue(catalog.safetySummaries.contains { $0.name == SafetyClass.neverTouch.label && $0.count > 0 })
        XCTAssertTrue(catalog.actionSummaries.contains { $0.name == ActionKind.deleteCache.label && $0.count > 0 })
        XCTAssertTrue(catalog.categorySummaries.contains { $0.name == "Codex" && $0.count > 0 })

        let neverTouch = try XCTUnwrap(catalog.sections.first { $0.safetyClass == .neverTouch })
        XCTAssertTrue(neverTouch.title.contains("Never Touch"))
        let credentials = try XCTUnwrap(neverTouch.rules.first { $0.id == "codex.credentials.never" })
        XCTAssertEqual(credentials.actionKind, .reportOnly)
        XCTAssertFalse(credentials.matchHints.isEmpty)
        XCTAssertFalse(credentials.evidence.isEmpty)
        XCTAssertFalse(catalog.nonClaims.isEmpty)
    }

    func testUserRulePackRejectsCleanupPermissions() throws {
        let store = UserRulePackStore(root: tempRoot.appendingPathComponent("config", isDirectory: true))
        let destructiveRule = ReclaimerRule(
            id: "user.bad.cache-cleanup",
            title: "Unsafe custom cleanup",
            category: "User",
            priority: 5000,
            safetyClass: .autoSafe,
            actionKind: .deleteCache,
            match: RuleMatchSpec(containsAny: ["/Library/Caches/UnsafeCustomThing/"]),
            evidence: ["This rule tries to grant itself cleanup permission."]
        )
        let document = UserRulePackDocument(rules: [destructiveRule])

        let issues = store.validate(document)
        XCTAssertTrue(issues.contains { $0.severity == .error && $0.ruleID == destructiveRule.id && $0.message.contains("cannot use") })
        XCTAssertTrue(issues.contains { $0.severity == .error && $0.ruleID == destructiveRule.id && $0.message.contains("cannot request") })
        XCTAssertThrowsError(try store.save(document)) { error in
            guard case UserRulePackError.validationFailed = error else {
                return XCTFail("Expected validation failure, got \(error)")
            }
        }
    }

    func testUserRulePackImportIsExplicitAndCannotDowngradeNeverTouch() throws {
        let configRoot = tempRoot.appendingPathComponent("config", isDirectory: true)
        let store = UserRulePackStore(root: configRoot)
        let reviewRule = ReclaimerRule(
            id: "user.review.vacuum-app-cache",
            title: "Vacuum app cache review",
            category: "General App Review",
            priority: 5000,
            safetyClass: .preserveByDefault,
            actionKind: .reportOnly,
            match: RuleMatchSpec(containsAny: ["/VacuumApp/"]),
            evidence: ["Local rule pack marks this app family for manual review."],
            conditions: ["Review in Ryddi before cleanup."]
        )
        let downgradeAttempt = ReclaimerRule(
            id: "user.review.codex-auth",
            title: "Codex auth review only",
            category: "User",
            priority: 6000,
            safetyClass: .reviewRequired,
            actionKind: .openGuidance,
            match: RuleMatchSpec(containsAny: ["/.codex/auth.json"]),
            evidence: ["This should not reduce the bundled credential guard."]
        )
        let source = tempRoot.appendingPathComponent("user-rules.json")
        let document = UserRulePackDocument(rules: [reviewRule, downgradeAttempt])
        try store.writeExport(document, to: source)

        let preview = try store.preview(from: source)
        XCTAssertTrue(preview.isImportable)
        XCTAssertEqual(preview.acceptedRuleCount, 2)
        let result = try store.importDocument(from: source)
        XCTAssertEqual(result.importedRuleCount, 2)
        XCTAssertFalse(result.includedByDefault)

        let bundled = try RuleEngine.bundled()
        let customPath = tempRoot.appendingPathComponent("VacuumApp/blob.cache").path
        XCTAssertFalse(bundled.classify(path: customPath, isDirectory: false, isSymbolicLink: false).matches.contains { $0.ruleID == reviewRule.id })

        let withUserRules = try RuleEngine.bundled(includingUserRules: true, userRuleStore: store)
        let customClassification = withUserRules.classify(path: customPath, isDirectory: false, isSymbolicLink: false)
        XCTAssertTrue(customClassification.matches.contains { $0.ruleID == reviewRule.id })
        XCTAssertEqual(customClassification.safetyClass, .preserveByDefault)

        let credentialClassification = withUserRules.classify(
            path: "/Users/test/.codex/auth.json",
            isDirectory: false,
            isSymbolicLink: false
        )
        XCTAssertTrue(credentialClassification.matches.contains { $0.ruleID == downgradeAttempt.id })
        XCTAssertEqual(credentialClassification.safetyClass, .neverTouch)
        XCTAssertEqual(credentialClassification.actionKind, .reportOnly)
    }

    func testUserRulePackMergeAndReplace() throws {
        let store = UserRulePackStore(root: tempRoot.appendingPathComponent("config", isDirectory: true))
        let first = ReclaimerRule(
            id: "user.review.first",
            title: "First review rule",
            category: "User",
            priority: 5000,
            safetyClass: .reviewRequired,
            actionKind: .openGuidance,
            match: RuleMatchSpec(containsAny: ["/FirstReviewTarget/"]),
            evidence: ["First rule."]
        )
        let second = ReclaimerRule(
            id: "user.review.second",
            title: "Second review rule",
            category: "User",
            priority: 5000,
            safetyClass: .reviewRequired,
            actionKind: .openGuidance,
            match: RuleMatchSpec(containsAny: ["/SecondReviewTarget/"]),
            evidence: ["Second rule."]
        )
        let firstSource = tempRoot.appendingPathComponent("first-user-rules.json")
        let secondSource = tempRoot.appendingPathComponent("second-user-rules.json")
        try store.writeExport(UserRulePackDocument(rules: [first]), to: firstSource)
        try store.writeExport(UserRulePackDocument(rules: [second]), to: secondSource)

        _ = try store.importDocument(from: firstSource, merge: true)
        XCTAssertEqual(try store.loadDocument().rules.map(\.id), [first.id])
        _ = try store.importDocument(from: secondSource, merge: true)
        XCTAssertEqual(Set(try store.loadDocument().rules.map(\.id)), Set([first.id, second.id]))
        _ = try store.importDocument(from: secondSource, merge: false)
        XCTAssertEqual(try store.loadDocument().rules.map(\.id), [second.id])
    }

    func testDefaultScopePresetsSeparateGeneralAndDeveloperRoots() throws {
        let general = DefaultScopes.plan(for: .general, home: tempRoot, includeUnavailable: true)
        let developer = DefaultScopes.plan(for: .developer, home: tempRoot, includeUnavailable: true)

        XCTAssertEqual(general.preset, .general)
        XCTAssertTrue(general.scopes.contains { $0.name == "Downloads review" && $0.root.path.hasSuffix("/Downloads") })
        XCTAssertTrue(general.scopes.contains { $0.name == "User caches" && $0.root.path.hasSuffix("/Library/Caches") })
        XCTAssertFalse(general.scopes.contains { $0.name == "Device backups review" })
        XCTAssertFalse(general.scopes.contains { $0.name == "Codex state" })

        XCTAssertEqual(developer.preset, .developer)
        XCTAssertTrue(developer.scopes.contains { $0.name == "Codex state" && $0.root.path.hasSuffix("/.codex") })
        XCTAssertTrue(developer.scopes.contains { $0.name == "Xcode Developer" && $0.root.path.hasSuffix("/Library/Developer") })
        XCTAssertFalse(developer.scopes.contains { $0.name == "Downloads review" })
        XCTAssertFalse(general.nonClaims.isEmpty)
    }

    func testAllScopePresetCollapsesNestedChildRoots() throws {
        let plan = DefaultScopes.plan(for: .all, home: tempRoot, includeUnavailable: true)
        let paths = plan.scopes.map { $0.root.path }

        XCTAssertEqual(Set(paths).count, paths.count)
        XCTAssertTrue(plan.scopes.contains { $0.name == "User caches" && $0.root.path.hasSuffix("/Library/Caches") })
        XCTAssertFalse(plan.scopes.contains { $0.name == "Homebrew cache" })
        XCTAssertFalse(plan.scopes.contains { $0.name == "VS Code caches" })
        XCTAssertTrue(plan.scopes.contains { $0.name == "Codex state" })
        XCTAssertTrue(plan.nonClaims.contains { $0.contains("Overlapping child scopes") })
    }

    func testCustomScopePlanOverridesPresetSemantics() throws {
        let custom = [
            ScanScope(name: "one", root: tempRoot.appendingPathComponent("One")),
            ScanScope(name: "duplicate", root: tempRoot.appendingPathComponent("One"))
        ]
        let plan = DefaultScopes.customPlan(scopes: custom)

        XCTAssertNil(plan.preset)
        XCTAssertEqual(plan.label, "Custom paths")
        XCTAssertEqual(plan.scopes.count, 1)
        XCTAssertTrue(plan.nonClaims.contains { $0.contains("Custom paths do not change") })
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
        XCTAssertFalse(overview.ownerSummaries.isEmpty)
        XCTAssertTrue(overview.ownerSummaries.contains { $0.ownerName == "Codex" })
        XCTAssertLessThanOrEqual(overview.topFindings.count, 3)
        XCTAssertFalse(overview.accountingNotes.isEmpty)
    }

    func testDiskDrillDownBuildsHierarchyAndOmittedChildSummary() throws {
        let cache = tempRoot.appendingPathComponent("Library/Caches/Codex/cache.bin")
        let logs = tempRoot.appendingPathComponent("Library/Logs/com.openai.codex/old.log")
        let download = tempRoot.appendingPathComponent("Downloads/installer.dmg")
        for (index, url) in [cache, logs, download].enumerated() {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: UInt8(index + 1), count: 256 + index).write(to: url)
        }

        let scopes = [ScanScope(name: "fixture", root: tempRoot)]
        let findings = try FileScanner(openFileChecker: NoOpenFilesChecker()).scan(
            scopes: scopes,
            options: ScanOptions(minimumFindingSize: 1, maximumFindingDepth: 4, measurementDepth: 8)
        )
        let report = DiskDrillDownBuilder.build(
            findings: findings,
            scopes: scopes,
            maxDepth: 4,
            childLimit: 1,
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        let root = try XCTUnwrap(report.rootNodes.first { $0.path == tempRoot.path })
        XCTAssertGreaterThan(report.nodeCount, 3)
        XCTAssertGreaterThan(report.totalAllocatedSize, 0)
        XCTAssertEqual(root.childCount, 2)
        XCTAssertEqual(root.children.count, 1)
        XCTAssertEqual(root.omittedChildCount, 1)
        XCTAssertGreaterThan(root.omittedAllocatedSize, 0)
        XCTAssertTrue(report.nonClaims.contains { $0.contains("Parent rows include measured descendant bytes") })
        XCTAssertTrue(report.nonClaims.contains { $0.contains("Map nodes are informational only") })
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

    func testEvidenceReportPrivacyCanRedactPathsAndUserText() throws {
        let cache = finding(
            path: tempRoot.appendingPathComponent("Library/Caches/Codex").path,
            safety: .autoSafe,
            action: .deleteCache,
            open: false,
            allocatedSize: 1_000,
            isDirectory: true,
            category: "Codex Cache"
        )
        let scopes = [ScanScope(name: "fixture", root: tempRoot)]
        let overview = FindingAnalytics.overview(findings: [cache], scopes: scopes, topLimit: 1)
        let policy = UserPathPolicy(rules: [
            UserPathRule(kind: .protect, path: cache.path, reason: "private client project", createdAt: Date(timeIntervalSince1970: 0))
        ])

        let report = EvidenceReportBuilder.build(
            overview: overview,
            findings: [cache],
            scopes: scopes,
            userPathPolicy: policy,
            topLimit: 1,
            privacy: ReportPrivacyOptions(pathStyle: .redacted, redactUserText: true, homeDirectory: tempRoot)
        )

        XCTAssertTrue(report.markdown.contains("<path redacted>"))
        XCTAssertTrue(report.markdown.contains("<redacted>"))
        XCTAssertTrue(report.markdown.contains("Report privacy was applied"))
        XCTAssertFalse(report.markdown.contains(tempRoot.path))
        XCTAssertFalse(report.markdown.contains("private client project"))
    }

    func testReportPrivacyCanRenderHomeRelativePaths() {
        let privacy = ReportPrivacyOptions(pathStyle: .homeRelative, homeDirectory: tempRoot)
        let cache = tempRoot.appendingPathComponent("Library/Caches/Codex").path

        XCTAssertEqual(ReportPathStyle(rawValue: "home-relative"), .homeRelative)
        XCTAssertEqual(privacy.displayPath(cache), "~/Library/Caches/Codex")
        XCTAssertEqual(privacy.displayText("Path: \(cache)", knownPaths: [cache]), "Path: ~/Library/Caches/Codex")
    }

    func testReclaimPlanReportIncludesSelectedBlockedAndNonClaims() {
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
        let plan = PlanBuilder(openFileChecker: NoOpenFilesChecker()).buildPlan(from: [cache, history])

        let report = ReclaimPlanReportBuilder.build(
            plan: plan,
            itemLimit: 10,
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(report.planID, plan.id)
        XCTAssertEqual(report.itemCount, 2)
        XCTAssertEqual(report.selectedCount, 1)
        XCTAssertEqual(report.blockedCount, 1)
        XCTAssertEqual(report.expectedImmediateReclaim, 1_000)
        XCTAssertTrue(report.markdown.contains("# Ryddi Plan Report"))
        XCTAssertTrue(report.markdown.contains("## Selected Actions"))
        XCTAssertTrue(report.markdown.contains("## Review And Blocked Items"))
        XCTAssertTrue(report.markdown.contains("Path is protected by policy"))
        XCTAssertTrue(report.markdown.contains("This report summarizes a proposed reclaim plan; it does not execute cleanup."))
        XCTAssertTrue(report.markdown.contains("A plan report is not a dry-run receipt"))
    }

    func testReclaimPlanReportPrivacyRedactsPaths() {
        let cache = finding(
            path: tempRoot.appendingPathComponent("Library/Caches/Codex").path,
            safety: .autoSafe,
            action: .deleteCache,
            open: false,
            allocatedSize: 1_000,
            isDirectory: true,
            category: "Codex Cache"
        )
        let plan = PlanBuilder(openFileChecker: NoOpenFilesChecker()).buildPlan(from: [cache])

        let report = ReclaimPlanReportBuilder.build(
            plan: plan,
            privacy: ReportPrivacyOptions(pathStyle: .redacted, homeDirectory: tempRoot),
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(report.markdown.contains("<path redacted>"))
        XCTAssertTrue(report.markdown.contains("Report privacy was applied"))
        XCTAssertFalse(report.markdown.contains(tempRoot.path))
        XCTAssertFalse(report.markdown.contains(cache.path))
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

    func testReportStoreSavesUserRulePackExport() throws {
        let rule = ReclaimerRule(
            id: "user.review.fixture",
            title: "Fixture review rule",
            category: "User",
            priority: 5000,
            safetyClass: .reviewRequired,
            actionKind: .openGuidance,
            match: RuleMatchSpec(containsAny: ["/FixtureReviewTarget/"]),
            evidence: ["Fixture rule."]
        )
        let document = UserRulePackDocument(id: "fixture-rules", exportedAt: Date(timeIntervalSince1970: 0), rules: [rule])
        let store = ReportStore(root: tempRoot.appendingPathComponent("Reports", isDirectory: true))

        let url = try store.save(userRulePackDocument: document)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(UserRulePackDocument.self, from: Data(contentsOf: url))

        XCTAssertEqual(url.lastPathComponent, "user-rules-fixture-rules.json")
        XCTAssertEqual(decoded.rules.map(\.id), [rule.id])
        XCTAssertTrue(decoded.nonClaims.contains { $0.contains("local review data") })
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

    func testExecutionReceiptReportPrivacyRedactsPathsAndMessages() {
        let cache = tempRoot.appendingPathComponent("Library/Caches/Codex/cache.bin").path
        let receipt = ExecutionReceipt(
            id: "receipt-fixture",
            createdAt: Date(timeIntervalSince1970: 0),
            ruleVersion: "test-rules",
            mode: ExecutionMode.perform.rawValue,
            beforeFreeBytes: nil,
            afterFreeBytes: nil,
            actions: [
                ExecutionActionReceipt(path: cache, action: .trash, status: "done", message: "Moved to app holding area: \(cache).")
            ],
            userConfirmed: true,
            errors: ["\(cache): fixture error"]
        )

        let report = ExecutionReceiptReportBuilder.build(
            receipt: receipt,
            privacy: ReportPrivacyOptions(pathStyle: .redacted, homeDirectory: tempRoot),
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(report.markdown.contains("<path redacted>"))
        XCTAssertTrue(report.markdown.contains("Report privacy was applied"))
        XCTAssertFalse(report.markdown.contains(tempRoot.path))
        XCTAssertFalse(report.markdown.contains(cache))
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

    func testReportStoreSavesReclaimPlanReport() throws {
        let planReport = ReclaimPlanReport(
            id: "report-fixture",
            createdAt: Date(timeIntervalSince1970: 0),
            title: "Plan Report",
            markdown: "# Plan Report\n",
            planID: "plan-fixture",
            itemCount: 1,
            selectedCount: 1,
            blockedCount: 0,
            expectedImmediateReclaim: 10,
            nonClaims: []
        )
        let store = ReportStore(root: tempRoot.appendingPathComponent("Reports", isDirectory: true))

        let url = try store.save(planReport: planReport)

        XCTAssertEqual(url.lastPathComponent, "plan-report-plan-fixture-report-fixture.md")
        XCTAssertEqual(try String(contentsOf: url), planReport.markdown)
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

    func testOwnerSummariesPreferOwnerHintsAndAvoidNestedDoubleCounting() throws {
        let parent = finding(
            path: tempRoot.appendingPathComponent("Library/Caches/Codex").path,
            safety: .autoSafe,
            action: .deleteCache,
            open: false,
            allocatedSize: 100,
            isDirectory: true,
            category: "Codex Cache",
            ownerHint: "Codex"
        )
        let child = finding(
            path: tempRoot.appendingPathComponent("Library/Caches/Codex/blob").path,
            safety: .autoSafe,
            action: .deleteCache,
            open: false,
            allocatedSize: 40,
            category: "Codex Cache",
            ownerHint: "Codex"
        )
        let fallback = finding(
            path: tempRoot.appendingPathComponent("Projects/App/node_modules").path,
            safety: .reviewRequired,
            action: .openGuidance,
            open: false,
            allocatedSize: 75,
            isDirectory: true,
            category: "Node Modules"
        )

        let overview = FindingAnalytics.overview(
            findings: [child, fallback, parent],
            scopes: [ScanScope(name: "fixture", root: tempRoot)]
        )

        XCTAssertEqual(overview.ownerSummaries.reduce(0) { $0 + $1.allocatedSize }, 175)
        let codex = try XCTUnwrap(overview.ownerSummaries.first { $0.ownerName == "Codex" })
        XCTAssertEqual(codex.allocatedSize, 100)
        XCTAssertEqual(codex.expectedAutoSafeBytes, 100)
        XCTAssertEqual(codex.dominantCategory, "Codex Cache")
        XCTAssertTrue(codex.isReclaimable)
        XCTAssertEqual(codex.topPaths, [parent.path])

        let fallbackOwner = try XCTUnwrap(overview.ownerSummaries.first { $0.ownerName == "Node Modules" })
        XCTAssertEqual(fallbackOwner.reviewBytes, 75)
        XCTAssertEqual(fallbackOwner.safetyClass, .reviewRequired)
        XCTAssertFalse(fallbackOwner.isReclaimable)
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
        XCTAssertEqual(store.snapshot(id: "older")?.id, "older")
    }

    func testGrowthReportIncludesDeltasNonClaimsAndRedactedPaths() {
        let previous = ScanSnapshot(
            id: "previous",
            createdAt: Date(timeIntervalSince1970: 10),
            findingCount: 1,
            totalLogicalSize: 100,
            totalAllocatedSize: 100,
            expectedAutoSafeBytes: 20,
            reviewBytes: 30,
            protectedBytes: 50,
            categorySummaries: [BucketSummary(name: "Codex", count: 1, logicalSize: 100, allocatedSize: 100)],
            safetySummaries: [BucketSummary(name: SafetyClass.autoSafe.label, count: 1, logicalSize: 100, allocatedSize: 100)],
            scopeBuckets: [BucketSummary(name: "Codex", count: 1, logicalSize: 100, allocatedSize: 100)],
            scopeSummaries: [
                ScopeAccessSummary(name: "Codex", path: "/Users/reidar/.codex", permissionState: .readable, message: "Directory is readable.")
            ],
            topFindingPaths: ["/Users/reidar/.codex/cache-old"]
        )
        let current = ScanSnapshot(
            id: "current",
            createdAt: Date(timeIntervalSince1970: 20),
            findingCount: 2,
            totalLogicalSize: 180,
            totalAllocatedSize: 190,
            expectedAutoSafeBytes: 90,
            reviewBytes: 40,
            protectedBytes: 60,
            categorySummaries: [BucketSummary(name: "Codex", count: 2, logicalSize: 180, allocatedSize: 190)],
            safetySummaries: [BucketSummary(name: SafetyClass.autoSafe.label, count: 2, logicalSize: 180, allocatedSize: 190)],
            scopeBuckets: [BucketSummary(name: "Codex", count: 2, logicalSize: 180, allocatedSize: 190)],
            scopeSummaries: [
                ScopeAccessSummary(name: "Codex", path: "/Users/reidar/.codex", permissionState: .readable, message: "Directory is readable.")
            ],
            topFindingPaths: ["/Users/reidar/.codex/cache-new"]
        )

        let report = GrowthReportBuilder.build(
            previous: previous,
            current: current,
            privacy: ReportPrivacyOptions(pathStyle: .redacted)
        )

        XCTAssertEqual(report.previousSnapshotID, "previous")
        XCTAssertEqual(report.currentSnapshotID, "current")
        XCTAssertEqual(report.deltaAllocatedSize, 90)
        XCTAssertEqual(report.deltaFindingCount, 1)
        XCTAssertEqual(report.deltas.first?.name, "Codex")
        XCTAssertEqual(report.deltas.first?.deltaAllocatedSize, 90)
        XCTAssertTrue(report.markdown.contains("# Ryddi Growth Report"))
        XCTAssertTrue(report.markdown.contains("Largest Category Deltas"))
        XCTAssertTrue(report.markdown.contains("Explicit Non-Claims"))
        XCTAssertTrue(report.markdown.contains("<path redacted>"))
        XCTAssertFalse(report.markdown.contains("/Users/reidar"))
        XCTAssertTrue(report.nonClaims.contains { $0.contains("No cleanup was executed") })
        XCTAssertTrue(report.nonClaims.contains { $0.contains("Report privacy was applied") })
    }

    func testReportStoreSavesGrowthReport() throws {
        let previous = snapshot(
            id: "previous",
            createdAt: Date(timeIntervalSince1970: 10),
            category: [BucketSummary(name: "Codex", count: 1, logicalSize: 100, allocatedSize: 100)]
        )
        let current = snapshot(
            id: "current",
            createdAt: Date(timeIntervalSince1970: 20),
            category: [BucketSummary(name: "Codex", count: 2, logicalSize: 180, allocatedSize: 190)]
        )
        let report = GrowthReportBuilder.build(previous: previous, current: current)
        let url = try ReportStore(root: tempRoot.appendingPathComponent("Reports", isDirectory: true))
            .save(growthReport: report)

        let markdown = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(url.lastPathComponent.hasPrefix("growth-report-current-"))
        XCTAssertTrue(markdown.contains("# Ryddi Growth Report"))
        XCTAssertTrue(markdown.contains("Codex"))
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

    func testPermissionWalkthroughGuidesDegradedCoverageWithoutGrantingPermission() {
        let report = PermissionAdvisor.report(
            scopeSummaries: [
                ScopeAccessSummary(name: "Codex", path: "/fixture/.codex", permissionState: .readable, message: "Directory is readable."),
                ScopeAccessSummary(name: "Mail", path: "/fixture/Library/Mail", permissionState: .denied, message: "Path exists but is not readable."),
                ScopeAccessSummary(name: "Colima", path: "/fixture/.colima", permissionState: .missing, message: "Path is not present.")
            ],
            now: Date(timeIntervalSince1970: 10)
        )

        let walkthrough = PermissionWalkthroughBuilder.build(report: report, now: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(walkthrough.coverageLevel, .degraded)
        XCTAssertEqual(walkthrough.readableCount, 1)
        XCTAssertEqual(walkthrough.totalCount, 3)
        XCTAssertEqual(walkthrough.steps.first { $0.id == "open-full-disk-access" }?.status, .recommended)
        XCTAssertEqual(walkthrough.steps.first { $0.id == "open-full-disk-access" }?.affectedScopes, ["Mail"])
        XCTAssertEqual(walkthrough.steps.first { $0.id == "keep-degraded-mode-visible" }?.status, .recommended)
        XCTAssertTrue(walkthrough.steps.contains { $0.command == "reclaimer permissions guide --output ryddi-permissions-guide.md" })
        XCTAssertTrue(walkthrough.nonClaims.contains("This walkthrough does not grant macOS permissions."))
        XCTAssertTrue(walkthrough.nonClaims.contains("Opening System Settings does not prove Full Disk Access is enabled."))
        XCTAssertTrue(walkthrough.markdown.contains("# Ryddi Permission Walkthrough"))
        XCTAssertTrue(walkthrough.markdown.contains("Explicit Non-Claims"))
        XCTAssertTrue(walkthrough.markdown.contains("does not grant macOS permissions"))
    }

    func testPermissionWalkthroughKeepsFullDiskAccessOptionalForCompleteCoverage() {
        let report = PermissionAdvisor.report(
            scopeSummaries: [
                ScopeAccessSummary(name: "Codex", path: "/fixture/.codex", permissionState: .readable, message: "Directory is readable."),
                ScopeAccessSummary(name: "Caches", path: "/fixture/Library/Caches", permissionState: .readable, message: "Directory is readable.")
            ],
            now: Date(timeIntervalSince1970: 20)
        )

        let walkthrough = PermissionWalkthroughBuilder.build(report: report, now: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(walkthrough.coverageLevel, .complete)
        XCTAssertEqual(walkthrough.steps.first { $0.id == "open-full-disk-access" }?.status, .optional)
        XCTAssertEqual(walkthrough.steps.first { $0.id == "keep-degraded-mode-visible" }?.status, .done)
        XCTAssertTrue(walkthrough.markdown.contains("Coverage: Complete"))
        XCTAssertTrue(walkthrough.markdown.contains("Readable scopes: 2/2"))
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

    func testAppUninstallPreviewKeepsRelatedFilesReviewOnly() throws {
        let appRoot = tempRoot.appendingPathComponent("Applications", isDirectory: true)
        let home = tempRoot.appendingPathComponent("Home", isDirectory: true)
        let app = appRoot.appendingPathComponent("Fixture.app", isDirectory: true)
        try createAppBundle(
            at: app,
            bundleIdentifier: "com.example.fixture",
            displayName: "Fixture"
        )
        let executable = app.appendingPathComponent("Contents/MacOS/Fixture")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 4, count: 512).write(to: executable)
        let cache = home.appendingPathComponent("Library/Caches/com.example.fixture/cache.bin")
        let preferences = home.appendingPathComponent("Library/Preferences/com.example.fixture.plist")
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: preferences.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 512).write(to: cache)
        try Data(repeating: 2, count: 512).write(to: preferences)

        let appReview = try AppReviewScanner().scan(
            options: AppReviewOptions(
                appRoots: [appRoot],
                home: home,
                minimumRelatedSize: 1,
                measurementDepth: 2
            )
        )
        let preview = try AppUninstallPreviewBuilder.build(
            report: appReview,
            selector: AppUninstallSelector(appPath: app.path),
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(preview.bundleCandidate.disposition, .trashPreview)
        XCTAssertEqual(preview.bundleCandidate.actionKind, .trash)
        XCTAssertGreaterThan(preview.explicitTrashPreviewBytes, 0)
        XCTAssertEqual(preview.relatedItems.count, 2)
        XCTAssertTrue(preview.relatedItems.allSatisfy { $0.actionKind != .trash && $0.actionKind != .deleteCache })
        XCTAssertTrue(preview.nonClaims.contains { $0.contains("related files remain review-only") })

        let markdown = AppUninstallPreviewMarkdownBuilder.build(
            preview: preview,
            privacy: ReportPrivacyOptions(pathStyle: .redacted, homeDirectory: tempRoot)
        )
        XCTAssertTrue(markdown.contains("# Ryddi App Uninstall Preview"))
        XCTAssertTrue(markdown.contains("<path redacted>"))
        XCTAssertTrue(markdown.contains("Only the selected app bundle"))
    }

    func testAppUninstallPreviewBlocksProtectedAppleApps() throws {
        let appRoot = tempRoot.appendingPathComponent("Applications", isDirectory: true)
        let home = tempRoot.appendingPathComponent("Home", isDirectory: true)
        let app = appRoot.appendingPathComponent("Logic Pro.app", isDirectory: true)
        try createAppBundle(
            at: app,
            bundleIdentifier: "com.apple.logic10",
            displayName: "Logic Pro"
        )

        let appReview = try AppReviewScanner().scan(
            options: AppReviewOptions(
                appRoots: [appRoot],
                home: home,
                minimumRelatedSize: 1,
                measurementDepth: 2
            )
        )
        let preview = try AppUninstallPreviewBuilder.build(
            report: appReview,
            selector: AppUninstallSelector(bundleIdentifier: "com.apple.logic10"),
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(preview.bundleCandidate.disposition, .protectedAppBlocked)
        XCTAssertEqual(preview.bundleCandidate.safetyClass, .preserveByDefault)
        XCTAssertEqual(preview.bundleCandidate.actionKind, .reportOnly)
        XCTAssertEqual(preview.explicitTrashPreviewBytes, 0)
        XCTAssertTrue(preview.bundleCandidate.evidence.contains { $0.message.contains("Apple app bundle") || $0.message.contains("GarageBand and Logic") })
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

    func testUserPathPolicyExportDocumentContainsRulesAndNonClaims() throws {
        let store = UserPathPolicyStore(root: tempRoot.appendingPathComponent("Config", isDirectory: true))
        let protected = tempRoot.appendingPathComponent("Projects/valuable", isDirectory: true)
        _ = try store.add(path: protected.path, kind: .protect, reason: "client data")

        let document = store.exportDocument(exportedAt: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(document.schemaVersion, UserPathPolicyDocument.currentSchemaVersion)
        XCTAssertEqual(document.rules.count, 1)
        XCTAssertEqual(document.rules.first?.path, protected.standardizedFileURL.path)
        XCTAssertTrue(document.nonClaims.contains { $0.contains("does not delete files") })
        XCTAssertTrue(document.nonClaims.contains { $0.contains("private local paths") })

        let exportURL = tempRoot.appendingPathComponent("policy-export.json")
        try store.writeExport(document, to: exportURL)
        let imported = try store.importDocument(from: exportURL)
        XCTAssertEqual(imported.importedRuleCount, 1)
        XCTAssertEqual(imported.finalRuleCount, 1)
    }

    func testUserPathPolicyImportMergesAndUpdatesMatchingRules() throws {
        let sourceStore = UserPathPolicyStore(root: tempRoot.appendingPathComponent("SourceConfig", isDirectory: true))
        let targetStore = UserPathPolicyStore(root: tempRoot.appendingPathComponent("TargetConfig", isDirectory: true))
        let shared = tempRoot.appendingPathComponent("Projects/shared", isDirectory: true)
        let retained = tempRoot.appendingPathComponent("Projects/local-only", isDirectory: true)
        let importedExclude = tempRoot.appendingPathComponent("Caches/noisy", isDirectory: true)

        _ = try targetStore.add(path: shared.path, kind: .protect, reason: "old reason")
        _ = try targetStore.add(path: retained.path, kind: .protect, reason: "keep local")
        _ = try sourceStore.add(path: shared.path, kind: .protect, reason: "new reason")
        _ = try sourceStore.add(path: importedExclude.path, kind: .exclude, reason: "ignore churn")
        let exportURL = tempRoot.appendingPathComponent("policy-export.json")
        try sourceStore.writeExport(to: exportURL)

        let result = try targetStore.importDocument(from: exportURL)
        let policy = result.policy

        XCTAssertEqual(result.mode, "merge")
        XCTAssertEqual(policy.rules.count, 3)
        XCTAssertEqual(policy.matchingRule(for: shared.path, kind: .protect)?.reason, "new reason")
        XCTAssertEqual(policy.matchingRule(for: retained.path, kind: .protect)?.reason, "keep local")
        XCTAssertEqual(policy.matchingRule(for: importedExclude.path, kind: .exclude)?.reason, "ignore churn")
    }

    func testUserPathPolicyImportCanReplaceExistingRules() throws {
        let sourceStore = UserPathPolicyStore(root: tempRoot.appendingPathComponent("ReplaceSource", isDirectory: true))
        let targetStore = UserPathPolicyStore(root: tempRoot.appendingPathComponent("ReplaceTarget", isDirectory: true))
        let oldLocal = tempRoot.appendingPathComponent("Projects/local-only", isDirectory: true)
        let imported = tempRoot.appendingPathComponent("Projects/imported", isDirectory: true)

        _ = try targetStore.add(path: oldLocal.path, kind: .protect, reason: "drop on replace")
        _ = try sourceStore.add(path: imported.path, kind: .protect, reason: "portable")
        let exportURL = tempRoot.appendingPathComponent("replace-policy-export.json")
        try sourceStore.writeExport(to: exportURL)

        let result = try targetStore.importDocument(from: exportURL, merge: false)

        XCTAssertEqual(result.mode, "replace")
        XCTAssertEqual(result.policy.rules.count, 1)
        XCTAssertNil(result.policy.matchingRule(for: oldLocal.path, kind: .protect))
        XCTAssertEqual(result.policy.matchingRule(for: imported.path, kind: .protect)?.reason, "portable")
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

    func testActiveFileReviewReportsOpenCleanupCandidatesWithProcesses() throws {
        let openCache = finding(
            path: tempRoot.appendingPathComponent("Library/Caches/Codex/open-cache").path,
            safety: .autoSafe,
            action: .deleteCache,
            open: false,
            allocatedSize: 1_000,
            isDirectory: true,
            category: "Codex"
        )
        let protectedHistory = finding(
            path: tempRoot.appendingPathComponent(".codex/sessions/history.jsonl").path,
            safety: .preserveByDefault,
            action: .compress,
            open: true,
            allocatedSize: 2_000,
            category: "Codex"
        )

        let report = ActiveFileReviewScanner(
            openFileChecker: StaticOpenFileChecker(
                openStatuses: [
                    openCache.path: OpenFileStatus(isOpen: true, processSummary: ["Codex pid 42"])
                ]
            )
        ).review(findings: [protectedHistory, openCache], options: ActiveFileReviewOptions(limit: 10))

        XCTAssertEqual(report.candidateCount, 1)
        XCTAssertEqual(report.checkedCount, 1)
        XCTAssertEqual(report.openCount, 1)
        XCTAssertEqual(report.failedCheckCount, 0)
        XCTAssertEqual(report.totalBlockedBytes, 1_000)
        XCTAssertEqual(report.items.first?.finding.path, openCache.path)
        XCTAssertEqual(report.items.first?.processSummary, ["Codex pid 42"])
        XCTAssertTrue(report.items.first?.guidance.contains { $0.contains("rerun Plan or Dry Run") } ?? false)
        XCTAssertTrue(report.nonClaims.contains { $0.contains("did not quit processes") })
    }

    func testActiveFileReviewReportsCheckFailuresAndLimit() throws {
        let first = finding(path: "/tmp/a", safety: .autoSafe, action: .deleteCache, open: false, allocatedSize: 1_000)
        let second = finding(path: "/tmp/b", safety: .safeAfterCondition, action: .trash, open: false, allocatedSize: 900)
        let report = ActiveFileReviewScanner(
            openFileChecker: StaticOpenFileChecker(
                openStatuses: [
                    first.path: OpenFileStatus(isOpen: false, checkFailed: "permission denied")
                ]
            )
        ).review(findings: [second, first], options: ActiveFileReviewOptions(limit: 1))

        XCTAssertEqual(report.candidateCount, 2)
        XCTAssertEqual(report.checkedCount, 1)
        XCTAssertTrue(report.truncated)
        XCTAssertEqual(report.openCount, 0)
        XCTAssertEqual(report.failedCheckCount, 1)
        XCTAssertEqual(report.items.first?.state, .checkFailed)
        XCTAssertEqual(report.items.first?.checkFailed, "permission denied")
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

    func testRecoveryCenterSeparatesRestorableItemsFromReceiptGuidance() throws {
        let heldRoot = tempRoot.appendingPathComponent("Holding", isDirectory: true)
        let source = tempRoot.appendingPathComponent("Library/Caches/Ryddi/held-cache.bin")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: 128).write(to: source)
        let heldDirectory = heldRoot.appendingPathComponent("2026-07-06T12-00-00Z", isDirectory: true)
        let heldFile = heldDirectory.appendingPathComponent("held-cache.bin")
        try FileManager.default.createDirectory(at: heldDirectory, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: source, to: heldFile)

        let store = HoldingStore(root: heldRoot)
        try store.recordHold(
            source: source,
            target: heldFile,
            finding: finding(path: source.path, safety: .safeAfterCondition, action: .quarantineHold, open: false)
        )
        let heldItems = store.list()
        let heldID = try XCTUnwrap(heldItems.first?.id)
        let receipt = ExecutionReceipt(
            id: "performed-fixture",
            createdAt: Date(timeIntervalSince1970: 10),
            ruleVersion: "test",
            mode: ExecutionMode.perform.rawValue,
            beforeFreeBytes: nil,
            afterFreeBytes: nil,
            actions: [
                ExecutionActionReceipt(path: "/tmp/trashed-cache", action: .trash, status: "done", message: "Moved to Trash.", reclaimedBytes: 20),
                ExecutionActionReceipt(path: "/tmp/deleted-cache", action: .deleteCache, status: "done", message: "Deleted cache.", reclaimedBytes: 30),
                ExecutionActionReceipt(path: "/tmp/native-cache", action: .nativeToolCommand, status: "done", message: "Use native cleanup.", reclaimedBytes: 40),
                ExecutionActionReceipt(path: "/tmp/skipped-cache", action: .deleteCache, status: "skipped", message: "Open file.", reclaimedBytes: 0)
            ],
            userConfirmed: true
        )
        let dryRunReceipt = ExecutionReceipt(
            id: "dry-run-fixture",
            createdAt: Date(timeIntervalSince1970: 20),
            ruleVersion: "test",
            mode: ExecutionMode.dryRun.rawValue,
            beforeFreeBytes: nil,
            afterFreeBytes: nil,
            actions: [
                ExecutionActionReceipt(path: "/tmp/planned-cache", action: .deleteCache, status: "dry-run", message: "Would delete.", reclaimedBytes: 50)
            ],
            userConfirmed: false
        )

        let report = RecoveryCenter.build(
            heldItems: heldItems,
            receipts: [dryRunReceipt, receipt],
            limit: 20,
            generatedAt: Date(timeIntervalSince1970: 30)
        )

        XCTAssertEqual(report.restorableCount, 1)
        XCTAssertEqual(report.restorableBytes, 128)
        XCTAssertTrue(report.nonClaims.contains { $0.contains("Ryddi can restore only items currently held") })
        XCTAssertEqual(report.items.first?.state, .restorableFromHolding)
        XCTAssertEqual(report.items.first?.holdingID, heldID)
        XCTAssertEqual(Set(report.items.map(\.state)), [
            .restorableFromHolding,
            .trashReview,
            .notRecoverableByRyddi,
            .guidanceOnly,
            .skippedNoChange,
            .dryRunOnly
        ])
        XCTAssertTrue(report.items.contains { $0.state == .trashReview && $0.guidance.contains { $0.contains("Finder Trash") } })
        XCTAssertTrue(report.items.contains { $0.state == .notRecoverableByRyddi && $0.guidance.contains { $0.contains("rebuild the cache") } })

        let restored = try store.restore(id: heldID)
        XCTAssertEqual(restored.path, source.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))

        let refreshed = RecoveryCenter.build(heldItems: store.list(), receipts: [], limit: 20)
        XCTAssertEqual(refreshed.restorableCount, 0)
        XCTAssertTrue(refreshed.items.isEmpty)
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
        let activeReport = ActiveFileReviewScanner(
            openFileChecker: StaticOpenFileChecker(openPaths: [candidate.path])
        ).review(findings: [candidate], options: ActiveFileReviewOptions(limit: 10))

        _ = try store.save(plan: plan)
        _ = try store.save(receipt: receipt)
        _ = try store.save(nativeToolReport: nativeReport)
        _ = try store.save(containerInventoryReport: containerReport)
        _ = try store.save(activeFileReviewReport: activeReport)

        XCTAssertEqual(store.recentPlans().first?.id, plan.id)
        XCTAssertEqual(store.plan(id: String(plan.id.prefix(8)))?.id, plan.id)
        XCTAssertEqual(store.recentReceipts().first?.id, receipt.id)
        XCTAssertEqual(store.receipt(id: String(receipt.id.prefix(8)))?.id, receipt.id)
        XCTAssertEqual(store.recentNativeToolReports().first?.id, nativeReport.id)
        XCTAssertEqual(store.recentContainerInventoryReports().first?.id, containerReport.id)
        XCTAssertEqual(store.recentActiveFileReviewReports().first?.id, activeReport.id)
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
        category: String = "Fixture",
        ownerHint: String? = nil
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
            ownerHint: ownerHint,
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
