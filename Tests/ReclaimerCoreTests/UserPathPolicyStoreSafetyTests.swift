import Darwin
import Foundation
import XCTest
@testable import ReclaimerCore

final class UserPathPolicyStoreSafetyTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiUserPathPolicyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
        try super.tearDownWithError()
    }

    func testMissingPolicyIsEmptyAndMutable() {
        let store = makeStore()

        let result = store.loadResult()

        XCTAssertEqual(result.state, .missing)
        XCTAssertEqual(result.policy, .empty)
        XCTAssertEqual(result.enforcementPolicy, .empty)
        XCTAssertTrue(result.canMutate)
        XCTAssertEqual(store.load(), .empty)
    }

    func testSaveUsesPrivatePermissionsAndExactReadback() throws {
        let store = makeStore()
        let policy = makePolicy(path: "/Users/example/Documents")

        try store.save(policy)

        let result = store.loadResult()
        XCTAssertEqual(result.state, .loaded)
        XCTAssertEqual(result.policy, policy)
        XCTAssertEqual(try mode(of: store.policyURL.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(try mode(of: store.policyURL), 0o600)
    }

    func testInsecurePermissionsLoadButAreRepairedByNextMutation() throws {
        let store = makeStore()
        try store.save(makePolicy(path: "/Users/example/Documents"))
        XCTAssertEqual(Darwin.chmod(store.policyURL.deletingLastPathComponent().path, 0o755), 0)
        XCTAssertEqual(Darwin.chmod(store.policyURL.path, 0o644), 0)

        XCTAssertEqual(store.loadResult().state, .loadedWithInsecurePermissions)
        _ = try store.add(path: "/Users/example/Pictures", kind: .protect, reason: "Keep photos")

        XCTAssertEqual(store.loadResult().state, .loaded)
        XCTAssertEqual(try mode(of: store.policyURL.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(try mode(of: store.policyURL), 0o600)
    }

    func testCorruptPolicyFailsClosedAndRefusesMutationOrExport() throws {
        let store = makeStore()
        try createPolicyRoot(for: store)
        let corrupt = Data("{ definitely-not-valid-json".utf8)
        try corrupt.write(to: store.policyURL)
        XCTAssertEqual(Darwin.chmod(store.policyURL.path, 0o600), 0)

        let result = store.loadResult()

        XCTAssertEqual(result.state, .corrupt)
        XCTAssertFalse(result.canMutate)
        assertProtectsEverything(store.load())
        XCTAssertThrowsError(try store.add(path: "/Users/example/Cache", kind: .exclude)) {
            XCTAssertEqual($0 as? UserPathPolicyStoreError, .currentPolicyUnavailable(.corrupt))
        }
        XCTAssertThrowsError(try store.exportDocument()) {
            XCTAssertEqual($0 as? UserPathPolicyStoreError, .currentPolicyUnavailable(.corrupt))
        }
        XCTAssertThrowsError(try store.save(makePolicy(path: "/Users/example/NewPolicy"))) {
            XCTAssertEqual($0 as? UserPathPolicyStoreError, .currentPolicyUnavailable(.corrupt))
        }
        XCTAssertEqual(try Data(contentsOf: store.policyURL), corrupt)
    }

    func testUnreadablePolicyFailsClosedAndRefusesMutation() throws {
        let store = makeStore()
        try store.save(makePolicy(path: "/Users/example/Documents"))
        XCTAssertEqual(Darwin.chmod(store.policyURL.path, 0o000), 0)
        defer { _ = Darwin.chmod(store.policyURL.path, 0o600) }

        let result = store.loadResult()

        XCTAssertEqual(result.state, .unreadable)
        assertProtectsEverything(store.load())
        XCTAssertThrowsError(try store.remove(path: "/Users/example/Documents")) {
            XCTAssertEqual($0 as? UserPathPolicyStoreError, .currentPolicyUnavailable(.unreadable))
        }
    }

    func testRootSymlinkIsUnsafeAndNeverFollowed() throws {
        let realRoot = temporaryRoot.appendingPathComponent("real-config", isDirectory: true)
        let linkedRoot = temporaryRoot.appendingPathComponent("linked-config", isDirectory: true)
        try FileManager.default.createDirectory(at: realRoot, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: realRoot)
        let store = UserPathPolicyStore(root: linkedRoot)

        XCTAssertEqual(store.loadResult().state, .unsafeStorage)
        assertProtectsEverything(store.load())
        XCTAssertThrowsError(try store.save(makePolicy(path: "/Users/example/Documents")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: realRoot.appendingPathComponent("user-path-policy.json").path))
    }

    func testFilesystemRootCannotBeUsedAsPolicyRoot() {
        let store = UserPathPolicyStore(root: URL(fileURLWithPath: "/", isDirectory: true))

        XCTAssertThrowsError(try store.save(makePolicy(path: "/Users/example/Documents"))) {
            guard case UserPathPolicyStoreError.unsafeStorage(let reason) = $0 else {
                return XCTFail("Expected unsafe storage, got \($0)")
            }
            XCTAssertTrue(reason.contains("protected directory"))
        }
    }

    func testPolicySymlinkIsUnsafeAndTargetRemainsUnchanged() throws {
        let store = makeStore()
        try createPolicyRoot(for: store)
        let target = temporaryRoot.appendingPathComponent("outside-policy.json")
        let original = Data("outside-data-must-not-change".utf8)
        try original.write(to: target)
        try FileManager.default.createSymbolicLink(at: store.policyURL, withDestinationURL: target)

        XCTAssertEqual(store.loadResult().state, .unsafeStorage)
        assertProtectsEverything(store.load())
        XCTAssertThrowsError(try store.add(path: "/Users/example/Documents", kind: .protect)) {
            XCTAssertEqual($0 as? UserPathPolicyStoreError, .currentPolicyUnavailable(.unsafeStorage))
        }
        XCTAssertThrowsError(try store.save(makePolicy(path: "/Users/example/Documents")))
        XCTAssertEqual(try Data(contentsOf: target), original)
    }

    func testMutationLockSymlinkIsUnsafeAndTargetRemainsUnchanged() throws {
        let store = makeStore()
        try createPolicyRoot(for: store)
        let target = temporaryRoot.appendingPathComponent("outside-lock")
        let original = Data("outside-lock-must-not-change".utf8)
        try original.write(to: target)
        let lockURL = store.policyURL.deletingLastPathComponent()
            .appendingPathComponent(".user-path-policy.lock")
        try FileManager.default.createSymbolicLink(at: lockURL, withDestinationURL: target)

        XCTAssertThrowsError(try store.add(path: "/Users/example/Documents", kind: .protect)) {
            guard case UserPathPolicyStoreError.unsafeStorage = $0 else {
                return XCTFail("Expected unsafe storage, got \($0)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: target), original)
        XCTAssertEqual(store.loadResult().state, .missing)
    }

    func testOversizedPolicyFailsClosedWithoutAllocatingUnboundedInput() throws {
        let store = makeStore()
        try createPolicyRoot(for: store)
        let oversized = Data(repeating: 0x20, count: Int(UserPathPolicyStore.maximumPolicyBytes) + 1)
        try oversized.write(to: store.policyURL)
        XCTAssertEqual(Darwin.chmod(store.policyURL.path, 0o600), 0)

        XCTAssertEqual(store.loadResult().state, .corrupt)
        assertProtectsEverything(store.load())
    }

    func testConcurrentMutationsRetainEveryProtection() async throws {
        let configRoot = temporaryRoot.appendingPathComponent("ConcurrentConfig", isDirectory: true)
        let expectedPaths = (0..<40).map { "/Users/example/concurrent-\($0)" }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for path in expectedPaths {
                group.addTask {
                    let store = UserPathPolicyStore(root: configRoot)
                    _ = try store.add(path: path, kind: .protect, reason: "Concurrent protection")
                }
            }
            try await group.waitForAll()
        }

        let result = UserPathPolicyStore(root: configRoot).loadResult()
        XCTAssertEqual(result.state, .loaded)
        XCTAssertEqual(Set(result.policy.rules.map(\.path)), Set(expectedPaths))
    }

    func testLockedLoadRejectsRootReplacementBeforeInvokingOperation() throws {
        let configRoot = temporaryRoot.appendingPathComponent("Config", isDirectory: true)
        let store = UserPathPolicyStore(root: configRoot)
        try store.save(makePolicy(path: "/Users/example/Documents"))
        let fixture = RootReplacementFixture(
            originalRoot: configRoot,
            displacedRoot: temporaryRoot.appendingPathComponent("DisplacedConfig", isDirectory: true)
        )
        let hookedStore = UserPathPolicyStore(
            root: configRoot,
            onMutationLockContention: {},
            onLockedRootReady: { fixture.replaceRoot() }
        )
        var operationCalled = false

        XCTAssertThrowsError(
            try hookedStore.withLockedLoadResult { _ in
                operationCalled = true
            }
        ) { error in
            guard case UserPathPolicyStoreError.unsafeStorage = error else {
                return XCTFail("Expected unsafe storage, got \(error)")
            }
        }
        XCTAssertFalse(operationCalled)
        XCTAssertNil(fixture.replacementError)
    }

    func testImportRejectsOversizedSourceBeforeDecoding() throws {
        let store = makeStore()
        let source = temporaryRoot.appendingPathComponent("oversized-import.json")
        try Data(repeating: 0x20, count: Int(UserPathPolicyStore.maximumPolicyBytes) + 1).write(to: source)

        XCTAssertThrowsError(try store.importDocument(from: source)) {
            guard case UserPathPolicyStoreError.unsafeStorage(let reason) = $0 else {
                return XCTFail("Expected unsafe storage, got \($0)")
            }
            XCTAssertTrue(reason.contains("size limit"))
        }
        XCTAssertEqual(store.loadResult().state, .missing)
    }

    func testImportRejectsSymbolicLinkSource() throws {
        let store = makeStore()
        let target = temporaryRoot.appendingPathComponent("import-target.json")
        let source = temporaryRoot.appendingPathComponent("import-link.json")
        let document = UserPathPolicyDocument(rules: makePolicy(path: "/Users/example/Imported").rules)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(document).write(to: target)
        try FileManager.default.createSymbolicLink(at: source, withDestinationURL: target)

        XCTAssertThrowsError(try store.importDocument(from: source)) {
            guard case UserPathPolicyStoreError.unsafeStorage = $0 else {
                return XCTFail("Expected unsafe storage, got \($0)")
            }
        }
        XCTAssertEqual(store.loadResult().state, .missing)
    }

    private func makeStore() -> UserPathPolicyStore {
        UserPathPolicyStore(root: temporaryRoot.appendingPathComponent("Config", isDirectory: true))
    }

    private func makePolicy(path: String) -> UserPathPolicy {
        UserPathPolicy(rules: [
            UserPathRule(
                id: "policy-rule",
                kind: .protect,
                path: path,
                reason: "User protection",
                createdAt: Date(timeIntervalSince1970: 100)
            )
        ])
    }

    private func createPolicyRoot(for store: UserPathPolicyStore) throws {
        try FileManager.default.createDirectory(
            at: store.policyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: UInt16(0o700))]
        )
        XCTAssertEqual(Darwin.chmod(store.policyURL.deletingLastPathComponent().path, 0o700), 0)
    }

    private func assertProtectsEverything(
        _ policy: UserPathPolicy,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let rule = policy.matchingRule(for: "/Users/example/anything", kind: .protect)
        XCTAssertEqual(rule?.path, "/", file: file, line: line)
        XCTAssertEqual(rule?.id, "ryddi.user-policy.fail-closed", file: file, line: line)
    }

    private func mode(of url: URL) throws -> UInt32 {
        var metadata = Darwin.stat()
        guard url.path.withCString({ Darwin.lstat($0, &metadata) }) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return UInt32(metadata.st_mode & mode_t(0o777))
    }
}

private final class RootReplacementFixture: @unchecked Sendable {
    private let originalRoot: URL
    private let displacedRoot: URL
    private let lock = NSLock()
    private var storedError: Error?

    init(originalRoot: URL, displacedRoot: URL) {
        self.originalRoot = originalRoot
        self.displacedRoot = displacedRoot
    }

    var replacementError: Error? {
        lock.withLock { storedError }
    }

    func replaceRoot() {
        do {
            try FileManager.default.moveItem(at: originalRoot, to: displacedRoot)
            try FileManager.default.createDirectory(
                at: originalRoot,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: NSNumber(value: UInt16(0o700))]
            )
            try Data("{}".utf8).write(
                to: originalRoot.appendingPathComponent("user-path-policy.json")
            )
        } catch {
            lock.withLock { storedError = error }
        }
    }
}
