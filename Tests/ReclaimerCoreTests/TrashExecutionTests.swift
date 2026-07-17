import Foundation
import XCTest
@testable import ReclaimerCore

final class TrashExecutionTests: XCTestCase {
    private var tempRoot: URL!
    private var fakeTrashRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiTrashExecutionTests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        fakeTrashRoot = tempRoot.appendingPathComponent("FakeTrash", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeTrashRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot, FileManager.default.fileExists(atPath: tempRoot.path) {
            try FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testAuthorizedTrashMovesOnlySelectedItemAndRecordsResult() async throws {
        let selectedURL = try makeFile(named: "selected.cache", contents: "selected")
        let unselectedURL = try makeFile(named: "unselected.cache", contents: "preserve")
        let selected = makeItem(id: "selected", url: selectedURL)
        let unselected = makeItem(id: "unselected", url: unselectedURL, selected: false)
        let plan = makePlan(items: [selected, unselected])
        let context = try await authorizationContext(for: plan)
        let trasher = FakeTrasher(root: fakeTrashRoot)

        let receipt = await makeExecutor(trasher: trasher, currentScanSession: context.session).executeAuthorizedTrash(
            plan: plan,
            authorizationID: context.authorization.id,
            authorizationRegistry: context.registry,
            ruleVersion: "rules-v1",
            userConfirmed: true,
            now: context.now
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: selectedURL.path))
        XCTAssertEqual(try String(contentsOf: unselectedURL, encoding: .utf8), "preserve")
        XCTAssertEqual(receipt.actions.count, 1)
        XCTAssertEqual(receipt.actions[0].status, "done")
        XCTAssertEqual(receipt.actions[0].action, .trash)
        XCTAssertEqual(receipt.actions[0].resultingPath, fakeTrashRoot.appendingPathComponent("selected.cache").path)
        XCTAssertEqual(receipt.actions[0].fileIdentity, context.authorization.identities[selected.id])
        XCTAssertNil(receipt.actions[0].skipReason)
        XCTAssertEqual(receipt.actions[0].reclaimedBytes, 0, "Moving to Trash does not immediately reclaim disk space.")
        XCTAssertEqual(trasher.trashedPaths, [selectedURL.path])
    }

    func testCurrentSessionMustStillMatchAuthorization() async throws {
        let url = try makeFile(named: "stale-session.cache")
        let item = makeItem(url: url)
        let plan = makePlan(items: [item])
        let context = try await authorizationContext(for: plan)
        let staleSession = ScanSession(
            id: "different-session",
            appVersion: "0.3.0",
            ruleVersion: "rules-v1",
            preset: .developer,
            scopeDigest: "scope-v1",
            policyDigest: "policy-v1",
            findingDigest: "findings-v1",
            planDigest: plan.id,
            dryRunReceiptID: context.authorization.dryRunReceiptID,
            stage: .reclaimReady
        )

        let receipt = await makeExecutor(
            trasher: FakeTrasher(root: fakeTrashRoot),
            currentScanSession: staleSession
        ).executeAuthorizedTrash(
            plan: plan,
            authorizationID: context.authorization.id,
            authorizationRegistry: context.registry,
            ruleVersion: "rules-v1",
            userConfirmed: true,
            now: context.now
        )

        XCTAssertEqual(receipt.actions.first?.skipReason, .authorizationMismatch)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testMissingConfirmationDoesNotConsumeAuthorization() async throws {
        let url = try makeFile(named: "confirm.cache")
        let item = makeItem(url: url)
        let plan = makePlan(items: [item])
        let context = try await authorizationContext(for: plan)
        let trasher = FakeTrasher(root: fakeTrashRoot)
        let executor = makeExecutor(trasher: trasher, currentScanSession: context.session)

        let refused = await executor.executeAuthorizedTrash(
            plan: plan,
            authorizationID: context.authorization.id,
            authorizationRegistry: context.registry,
            ruleVersion: "rules-v1",
            userConfirmed: false,
            now: context.now
        )
        let confirmed = await executor.executeAuthorizedTrash(
            plan: plan,
            authorizationID: context.authorization.id,
            authorizationRegistry: context.registry,
            ruleVersion: "rules-v1",
            userConfirmed: true,
            now: context.now
        )

        XCTAssertEqual(refused.actions.first?.skipReason, .confirmationRequired)
        XCTAssertEqual(confirmed.actions.first?.status, "done")
        XCTAssertEqual(trasher.trashedPaths, [url.path])
    }

    func testReplacementInodeIsSkipped() async throws {
        let url = try makeFile(named: "replaced.cache")
        let item = makeItem(url: url)
        let plan = makePlan(items: [item])
        let context = try await authorizationContext(for: plan)
        try FileManager.default.removeItem(at: url)
        try Data("replacement".utf8).write(to: url)

        let receipt = await execute(plan: plan, context: context)

        XCTAssertEqual(receipt.actions.first?.skipReason, .identityMismatch)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "replacement")
    }

    func testFileToDirectoryChangeIsSkipped() async throws {
        let url = try makeFile(named: "changed-type.cache")
        let item = makeItem(url: url)
        let plan = makePlan(items: [item])
        let context = try await authorizationContext(for: plan)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)

        let receipt = await execute(plan: plan, context: context)

        XCTAssertEqual(receipt.actions.first?.skipReason, .typeChanged)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testSymlinkReplacementIsSkippedWithoutTouchingTarget() async throws {
        let url = try makeFile(named: "link.cache")
        let target = try makeFile(named: "valuable.txt", contents: "valuable")
        let item = makeItem(url: url)
        let plan = makePlan(items: [item])
        let context = try await authorizationContext(for: plan)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)

        let receipt = await execute(plan: plan, context: context)

        XCTAssertEqual(receipt.actions.first?.skipReason, .symbolicLink)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "valuable")
    }

    func testRecursiveOpenChildSkipsDirectory() async throws {
        let directory = tempRoot.appendingPathComponent("open-directory", isDirectory: true)
        let child = directory.appendingPathComponent("open-child.cache")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("open".utf8).write(to: child)
        let item = makeItem(url: directory, isDirectory: true)
        let plan = makePlan(items: [item])
        let context = try await authorizationContext(for: plan)
        let checker = RecordingOpenFileChecker(statuses: [
            directory.path: OpenFileStatus(
                isOpen: true,
                processSummary: ["fixture pid 42"],
                checkedRecursively: true,
                checkedPath: directory.path
            )
        ])

        let receipt = await execute(plan: plan, context: context, openFileChecker: checker)

        XCTAssertEqual(receipt.actions.first?.skipReason, .recursiveOpenFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: child.path))
        XCTAssertEqual(checker.checkedPaths, [directory.path])
    }

    func testProtectedReclassificationSkipsItem() async throws {
        let url = try makeFile(named: "reclassified.cache")
        let item = makeItem(url: url)
        let plan = makePlan(items: [item])
        let context = try await authorizationContext(for: plan)
        let protectedRule = rule(
            id: "fixture.protected",
            path: url.path,
            safetyClass: .neverTouch,
            action: .reportOnly
        )

        let receipt = await execute(
            plan: plan,
            context: context,
            ruleEngine: RuleEngine(version: "protected", rules: [protectedRule])
        )

        XCTAssertEqual(receipt.actions.first?.skipReason, .protectedClassification)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testNewUserProtectionPolicySkipsItem() async throws {
        let url = try makeFile(named: "policy.cache")
        let item = makeItem(url: url)
        let plan = makePlan(items: [item])
        let context = try await authorizationContext(for: plan)
        let policy = UserPathPolicy(rules: [UserPathRule(kind: .protect, path: url.path, reason: "keep")])

        let receipt = await execute(plan: plan, context: context, userPathPolicy: policy)

        XCTAssertEqual(receipt.actions.first?.skipReason, .userProtected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testProtectionAddedAfterAuthorizationSkipsItem() async throws {
        let url = try makeFile(named: "late-policy.cache")
        let item = makeItem(url: url)
        let plan = makePlan(items: [item])
        let context = try await authorizationContext(for: plan)
        let loader = MutableUserPathPolicyLoader(policy: .empty)
        let executor = makeExecutor(
            trasher: FakeTrasher(root: fakeTrashRoot),
            userPathPolicyLoader: loader,
            currentScanSession: context.session
        )
        loader.setPolicy(UserPathPolicy(rules: [
            UserPathRule(kind: .protect, path: url.path, reason: "Added after authorization")
        ]))

        let receipt = await executor.executeAuthorizedTrash(
            plan: plan,
            authorizationID: context.authorization.id,
            authorizationRegistry: context.registry,
            ruleVersion: "rules-v1",
            userConfirmed: true,
            now: context.now
        )

        XCTAssertEqual(receipt.actions.first?.skipReason, .userProtected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testUnrelatedPolicyChangeAfterAuthorizationInvalidatesTrash() async throws {
        let url = try makeFile(named: "policy-digest.cache")
        let item = makeItem(url: url)
        let plan = makePlan(items: [item])
        let context = try await authorizationContext(for: plan)
        let loader = MutableUserPathPolicyLoader(policy: .empty)
        let executor = makeExecutor(
            trasher: FakeTrasher(root: fakeTrashRoot),
            userPathPolicyLoader: loader,
            currentScanSession: context.session
        )
        loader.setPolicy(UserPathPolicy(rules: [
            UserPathRule(kind: .protect, path: "/Users/example/unrelated", reason: "Changed")
        ]))

        let receipt = await executor.executeAuthorizedTrash(
            plan: plan,
            authorizationID: context.authorization.id,
            authorizationRegistry: context.registry,
            ruleVersion: "rules-v1",
            userConfirmed: true,
            now: context.now
        )

        XCTAssertEqual(receipt.actions.first?.skipReason, .userPolicyChanged)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testUnavailableCurrentPolicyBlocksTrashFailClosed() async throws {
        let url = try makeFile(named: "unavailable-policy.cache")
        let item = makeItem(url: url)
        let plan = makePlan(items: [item])
        let context = try await authorizationContext(for: plan)
        let loader = MutableUserPathPolicyLoader(policy: .empty)
        let executor = makeExecutor(
            trasher: FakeTrasher(root: fakeTrashRoot),
            userPathPolicyLoader: loader,
            currentScanSession: context.session
        )
        loader.setResult(UserPathPolicyLoadResult(
            state: .corrupt,
            policy: .empty,
            detail: "Fixture corruption"
        ))

        let receipt = await executor.executeAuthorizedTrash(
            plan: plan,
            authorizationID: context.authorization.id,
            authorizationRegistry: context.registry,
            ruleVersion: "rules-v1",
            userConfirmed: true,
            now: context.now
        )

        XCTAssertEqual(receipt.actions.first?.skipReason, .userPolicyUnavailable)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testTypedMinimumAgeGateIsRechecked() async throws {
        let url = try makeFile(named: "age.cache")
        let oldDate = Date().addingTimeInterval(-10 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: url.path)
        let item = makeItem(url: url, minimumAgeDays: 7, modificationDate: oldDate)
        let plan = makePlan(items: [item])
        let context = try await authorizationContext(for: plan)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)

        let receipt = await execute(plan: plan, context: context)

        XCTAssertEqual(receipt.actions.first?.skipReason, .gateFailed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testExpiredAuthorizationSkipsWithoutTrashing() async throws {
        let url = try makeFile(named: "expired.cache")
        let item = makeItem(url: url)
        let plan = makePlan(items: [item])
        let context = try await authorizationContext(for: plan)

        let receipt = await execute(
            plan: plan,
            context: context,
            now: context.now.addingTimeInterval(TrashExecutionAuthorizationRegistry.validityDuration)
        )

        XCTAssertEqual(receipt.actions.first?.skipReason, .authorizationExpired)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testAuthorizationCannotBeUsedTwice() async throws {
        let url = try makeFile(named: "one-time.cache")
        let item = makeItem(url: url)
        let plan = makePlan(items: [item])
        let context = try await authorizationContext(for: plan)
        let trasher = FakeTrasher(root: fakeTrashRoot)
        let executor = makeExecutor(trasher: trasher, currentScanSession: context.session)

        let first = await executor.executeAuthorizedTrash(
            plan: plan,
            authorizationID: context.authorization.id,
            authorizationRegistry: context.registry,
            ruleVersion: "rules-v1",
            userConfirmed: true,
            now: context.now
        )
        let second = await executor.executeAuthorizedTrash(
            plan: plan,
            authorizationID: context.authorization.id,
            authorizationRegistry: context.registry,
            ruleVersion: "rules-v1",
            userConfirmed: true,
            now: context.now
        )

        XCTAssertEqual(first.actions.first?.status, "done")
        XCTAssertEqual(second.actions.first?.skipReason, .authorizationUnavailable)
        XCTAssertEqual(trasher.trashedPaths.count, 1)
    }

    func testBlockedItemDoesNotWeakenChecksForLaterItem() async throws {
        let blockedURL = try makeFile(named: "blocked.cache")
        let allowedURL = try makeFile(named: "allowed.cache")
        let blocked = makeItem(id: "blocked", url: blockedURL)
        let allowed = makeItem(id: "allowed", url: allowedURL)
        let plan = makePlan(items: [blocked, allowed])
        let context = try await authorizationContext(for: plan)
        let checker = RecordingOpenFileChecker(statuses: [
            blockedURL.path: OpenFileStatus(isOpen: true, checkedPath: blockedURL.path),
            allowedURL.path: OpenFileStatus(isOpen: false, checkedPath: allowedURL.path)
        ])
        let trasher = FakeTrasher(root: fakeTrashRoot)

        let receipt = await execute(
            plan: plan,
            context: context,
            openFileChecker: checker,
            trasher: trasher
        )

        XCTAssertEqual(receipt.actions.map(\.skipReason), [.openFile, nil])
        XCTAssertEqual(receipt.actions.map(\.status), ["skipped", "done"])
        XCTAssertEqual(checker.checkedPaths, [blockedURL.path, allowedURL.path])
        XCTAssertEqual(trasher.trashedPaths, [allowedURL.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: blockedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: allowedURL.path))
    }

    func testFilesystemRootFailsContainmentCheck() async throws {
        let item = makeItem(url: URL(fileURLWithPath: "/"), isDirectory: true)
        let plan = makePlan(items: [item])
        let context = try await authorizationContext(for: plan)

        let receipt = await execute(plan: plan, context: context)

        XCTAssertEqual(receipt.actions.first?.skipReason, .pathContainment)
    }

    func testLegacyExecutionActionReceiptDecodesWithoutTrashFields() throws {
        let data = Data(#"{"path":"/tmp/legacy","action":"trash","status":"skipped","message":"legacy","reclaimedBytes":0}"#.utf8)

        let receipt = try JSONDecoder().decode(ExecutionActionReceipt.self, from: data)

        XCTAssertNil(receipt.resultingPath)
        XCTAssertNil(receipt.fileIdentity)
        XCTAssertNil(receipt.skipReason)
    }

    private func execute(
        plan: ReclaimPlan,
        context: AuthorizationContext,
        now: Date? = nil,
        openFileChecker: OpenFileChecking = RecordingOpenFileChecker(),
        userPathPolicy: UserPathPolicy = .empty,
        userPathPolicyLoader: (any UserPathPolicyLoading)? = nil,
        ruleEngine: RuleEngine? = nil,
        trasher: FakeTrasher? = nil
    ) async -> ExecutionReceipt {
        let resolvedTrasher = trasher ?? FakeTrasher(root: fakeTrashRoot)
        return await makeExecutor(
            trasher: resolvedTrasher,
            openFileChecker: openFileChecker,
            userPathPolicy: userPathPolicy,
            userPathPolicyLoader: userPathPolicyLoader,
            ruleEngine: ruleEngine,
            currentScanSession: context.session
        ).executeAuthorizedTrash(
            plan: plan,
            authorizationID: context.authorization.id,
            authorizationRegistry: context.registry,
            ruleVersion: "rules-v1",
            userConfirmed: true,
            now: now ?? context.now
        )
    }

    private func makeExecutor(
        trasher: Trashing,
        openFileChecker: OpenFileChecking = RecordingOpenFileChecker(),
        userPathPolicy: UserPathPolicy = .empty,
        userPathPolicyLoader: (any UserPathPolicyLoading)? = nil,
        ruleEngine: RuleEngine? = nil,
        currentScanSession: ScanSession? = nil
    ) -> ReclaimerExecutor {
        ReclaimerExecutor(
            openFileChecker: openFileChecker,
            configuration: ExecutorConfiguration(
                userPathPolicy: userPathPolicy,
                userPathPolicyLoader: userPathPolicyLoader ?? MutableUserPathPolicyLoader(policy: userPathPolicy),
                currentScanSession: currentScanSession
            ),
            ruleEngine: ruleEngine ?? autoSafeRuleEngine(),
            trasher: trasher
        )
    }

    private func authorizationContext(for plan: ReclaimPlan) async throws -> AuthorizationContext {
        let receipt = ExecutionReceipt(
            id: "receipt-\(UUID().uuidString)",
            ruleVersion: "rules-v1",
            mode: ExecutionMode.dryRun.rawValue,
            beforeFreeBytes: nil,
            afterFreeBytes: nil,
            actions: plan.items.filter(\.selected).map {
                ExecutionActionReceipt(
                    path: $0.finding.path,
                    action: $0.proposedAction,
                    status: "dry-run",
                    message: "Would perform \($0.proposedAction.label).",
                    reclaimedBytes: $0.estimatedImmediateReclaim
                )
            },
            userConfirmed: false
        )
        let session = ScanSession(
            id: "session-\(UUID().uuidString)",
            appVersion: "0.3.0",
            ruleVersion: "rules-v1",
            preset: .developer,
            scopeDigest: "scope-v1",
            policyDigest: ScanSessionEvidenceBuilder.policyDigest(
                preset: .developer,
                userPathPolicy: .empty
            ),
            findingDigest: "findings-v1",
            planDigest: plan.id,
            dryRunReceiptID: receipt.id,
            stage: .reclaimReady
        )
        let registry = TrashExecutionAuthorizationRegistry()
        let now = Date(timeIntervalSince1970: 50_000)
        let authorization = try await registry.issue(
            session: session,
            plan: plan,
            dryRunReceipt: receipt,
            now: now
        )
        return AuthorizationContext(registry: registry, authorization: authorization, session: session, now: now)
    }

    private func makeFile(named name: String, contents: String = "fixture") throws -> URL {
        let url = tempRoot.appendingPathComponent(name).standardizedFileURL
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func makeItem(
        id: String = UUID().uuidString,
        url: URL,
        selected: Bool = true,
        isDirectory: Bool = false,
        minimumAgeDays: Int? = nil,
        modificationDate: Date? = nil
    ) -> ReclaimPlanItem {
        let gates: [PlanConditionKind] = isDirectory
            ? [.recursiveOpenFileClear, .finalClassificationRequired]
            : [.openFileClear, .finalClassificationRequired] + (minimumAgeDays == nil ? [] : [.minimumAgeRequired])
        let match = RuleMatch(
            ruleID: "fixture.auto-trash",
            title: "Fixture Trash",
            category: "Fixture",
            safetyClass: .autoSafe,
            actionKind: .trash,
            evidence: ["Disposable fixture"],
            conditionGates: gates,
            gateEvidence: RuleGateEvidence(minimumAgeDays: minimumAgeDays),
            recovery: "Restore from Trash."
        )
        let finding = Finding(
            id: id,
            scopeName: "Fixture",
            path: url.path,
            displayName: url.lastPathComponent,
            logicalSize: 7,
            allocatedSize: 7,
            isDirectory: isDirectory,
            modificationDate: modificationDate,
            safetyClass: .autoSafe,
            actionKind: .trash,
            ruleMatches: [match],
            evidence: [Evidence(kind: "fixture", message: "Disposable fixture")]
        )
        return ReclaimPlanItem(
            finding: finding,
            selected: selected,
            proposedAction: .trash,
            conditions: gates.map { PlanCondition(kind: $0, message: $0.label, isSatisfied: true) },
            estimatedImmediateReclaim: selected ? 7 : 0
        )
    }

    private func makePlan(items: [ReclaimPlanItem]) -> ReclaimPlan {
        ReclaimPlan(mode: PlanMode.autoSafeOnly.rawValue, items: items, dryRunSummary: [])
    }

    private func autoSafeRuleEngine() -> RuleEngine {
        RuleEngine(version: "rules-v1", rules: [
            rule(id: "fixture.auto-trash", path: tempRoot.path, safetyClass: .autoSafe, action: .trash)
        ])
    }

    private func rule(
        id: String,
        path: String,
        safetyClass: SafetyClass,
        action: ActionKind
    ) -> ReclaimerRule {
        ReclaimerRule(
            id: id,
            title: "Fixture rule",
            category: "Fixture",
            priority: 100,
            safetyClass: safetyClass,
            actionKind: action,
            match: RuleMatchSpec(containsAny: [path.lowercased()]),
            evidence: ["Disposable fixture"],
            conditionGates: [.openFileClear, .recursiveOpenFileClear, .finalClassificationRequired],
            recovery: "Restore from Trash."
        )
    }
}

private struct AuthorizationContext {
    let registry: TrashExecutionAuthorizationRegistry
    let authorization: TrashExecutionAuthorization
    let session: ScanSession
    let now: Date
}

private final class MutableUserPathPolicyLoader: UserPathPolicyLoading, @unchecked Sendable {
    private let lock = NSLock()
    private var result: UserPathPolicyLoadResult

    init(policy: UserPathPolicy) {
        self.result = UserPathPolicyLoadResult(
            state: policy == .empty ? .missing : .loaded,
            policy: policy,
            detail: "Fixture policy"
        )
    }

    func loadResult() -> UserPathPolicyLoadResult {
        lock.withLock { result }
    }

    func setPolicy(_ policy: UserPathPolicy) {
        setResult(UserPathPolicyLoadResult(state: .loaded, policy: policy, detail: "Fixture policy"))
    }

    func setResult(_ result: UserPathPolicyLoadResult) {
        lock.withLock { self.result = result }
    }
}

private final class FakeTrasher: Trashing, @unchecked Sendable {
    private let root: URL
    private let lock = NSLock()
    private var paths: [String] = []

    init(root: URL) {
        self.root = root
    }

    var trashedPaths: [String] {
        lock.withLock { paths }
    }

    func trashItem(at url: URL) throws -> URL {
        let destination = root.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
        lock.withLock { paths.append(url.path) }
        return destination
    }
}

private final class RecordingOpenFileChecker: OpenFileChecking, @unchecked Sendable {
    private let statuses: [String: OpenFileStatus]
    private let lock = NSLock()
    private var paths: [String] = []

    init(statuses: [String: OpenFileStatus] = [:]) {
        self.statuses = statuses
    }

    var checkedPaths: [String] {
        lock.withLock { paths }
    }

    func status(for url: URL) -> OpenFileStatus {
        lock.withLock { paths.append(url.path) }
        if let status = statuses[url.path] {
            return status
        }
        var isDirectory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return OpenFileStatus(
            isOpen: false,
            checkedRecursively: isDirectory.boolValue,
            checkedPath: url.path
        )
    }
}
