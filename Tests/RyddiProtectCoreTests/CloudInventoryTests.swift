import Foundation
import XCTest
@testable import RyddiProtectCore

final class CloudInventoryTests: XCTestCase {
    func testBuildsCompleteBoundedMultiPageInventory() async throws {
        let first = try makeObject(id: "one", bytes: 10)
        let second = try makeObject(id: "two", bytes: 20)
        let third = try makeObject(id: "three", bytes: nil)
        let adapter = try ScriptedCloudAdapter(steps: [
            .page(makePage([first, second], cursor: "cursor-1", responseBytes: 200)),
            .page(makePage([third], responseBytes: 100))
        ])

        let report = await makeBuilder(adapter: adapter).build()

        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.objects.map(\.id), ["one", "two", "three"])
        XCTAssertEqual(report.logicalBytes, 30)
        XCTAssertEqual(report.pageCount, 2)
        XCTAssertEqual(report.responseByteCount, 300)
        XCTAssertEqual(report.retryCount, 0)
        XCTAssertEqual(report.connection?.displayLabel, "Dropbox 1")
        XCTAssertTrue(report.nonClaims.contains("No file was uploaded, moved, renamed, shared, or overwritten."))
        let listCallCount = await adapter.listCallCount()
        XCTAssertEqual(listCallCount, 2)
    }

    func testExactDuplicateStableIDIsCountedOnce() async throws {
        let item = try makeObject(id: "same", bytes: 25)
        let adapter = try ScriptedCloudAdapter(steps: [
            .page(makePage([item], cursor: "cursor-1")),
            .page(makePage([item]))
        ])

        let report = await makeBuilder(adapter: adapter).build()

        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.objects.count, 1)
        XCTAssertEqual(report.logicalBytes, 25)
    }

    func testConflictingStableIDFailsWithoutReplacingFirstObject() async throws {
        let first = try makeObject(id: "same", name: "first", bytes: 25)
        let conflicting = try makeObject(id: "same", name: "changed", bytes: 25)
        let adapter = try ScriptedCloudAdapter(steps: [
            .page(makePage([first], cursor: "cursor-1")),
            .page(makePage([conflicting]))
        ])

        let report = await makeBuilder(adapter: adapter).build()

        XCTAssertEqual(report.completion, .failed)
        XCTAssertEqual(report.issue, .conflictingStableID)
        XCTAssertEqual(report.objects, [first])
        XCTAssertFalse(report.isComplete)
    }

    func testProviderMismatchFailsAsMalformedResponse() async throws {
        let wrongProvider = try makeObject(id: "wrong", provider: .mega)
        let adapter = try ScriptedCloudAdapter(steps: [.page(makePage([wrongProvider]))])

        let report = await makeBuilder(adapter: adapter).build()

        XCTAssertEqual(report.completion, .failed)
        XCTAssertEqual(report.issue, .malformedResponse)
        XCTAssertTrue(report.objects.isEmpty)
    }

    func testObjectLimitProducesExplicitPartialReport() async throws {
        let adapter = try ScriptedCloudAdapter(steps: [
            .page(makePage([
                makeObject(id: "one"),
                makeObject(id: "two"),
                makeObject(id: "three")
            ]))
        ])
        let budget = CloudInventoryBudget(maximumTotalObjects: 2)

        let report = await makeBuilder(adapter: adapter, budget: budget).build()

        XCTAssertEqual(report.completion, .truncated)
        XCTAssertEqual(report.issue, .objectLimit)
        XCTAssertEqual(report.objects.map(\.id), ["one", "two"])
        XCTAssertFalse(report.isComplete)
    }

    func testResponseByteLimitRejectsWholePageBeforeAcceptingObjects() async throws {
        let adapter = try ScriptedCloudAdapter(steps: [
            .page(makePage([makeObject(id: "one")], responseBytes: 101))
        ])
        let budget = CloudInventoryBudget(maximumTotalResponseBytes: 100)

        let report = await makeBuilder(adapter: adapter, budget: budget).build()

        XCTAssertEqual(report.completion, .truncated)
        XCTAssertEqual(report.issue, .responseByteLimit)
        XCTAssertTrue(report.objects.isEmpty)
        XCTAssertEqual(report.pageCount, 0)
        XCTAssertEqual(report.responseByteCount, 0)
    }

    func testCursorCycleProducesExplicitPartialReport() async throws {
        let adapter = try ScriptedCloudAdapter(steps: [
            .page(makePage([makeObject(id: "one")], cursor: "cursor-1")),
            .page(makePage([makeObject(id: "two")], cursor: "cursor-1"))
        ])

        let report = await makeBuilder(adapter: adapter).build()

        XCTAssertEqual(report.completion, .truncated)
        XCTAssertEqual(report.issue, .cursorCycle)
        XCTAssertEqual(report.objects.count, 2)
    }

    func testProviderDeclaredTruncationNeverLooksComplete() async throws {
        let adapter = try ScriptedCloudAdapter(steps: [
            .page(makePage([makeObject(id: "one")], truncated: true))
        ])

        let report = await makeBuilder(adapter: adapter).build()

        XCTAssertEqual(report.completion, .truncated)
        XCTAssertEqual(report.issue, .providerReportedTruncation)
        XCTAssertFalse(report.isComplete)
    }

    func testCancellationFailureProducesCancelledReport() async throws {
        let adapter = try ScriptedCloudAdapter(steps: [.cancellation])

        let report = await makeBuilder(adapter: adapter).build()

        XCTAssertEqual(report.completion, .cancelled)
        XCTAssertNil(report.issue)
        XCTAssertFalse(report.isComplete)
    }

    func testRateLimitRetriesOnceUsingBoundedProviderDelay() async throws {
        let adapter = try ScriptedCloudAdapter(steps: [
            .failure(.rateLimited(retryAfter: 2)),
            .page(makePage([makeObject(id: "one")]))
        ])
        let clock = LockedTestClock()
        let delays = DelayRecorder()

        let report = await makeBuilder(
            adapter: adapter,
            clock: clock,
            delays: delays
        ).build()

        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.retryCount, 1)
        let recordedDelays = await delays.snapshot()
        let listCallCount = await adapter.listCallCount()
        XCTAssertEqual(recordedDelays, [2])
        XCTAssertEqual(listCallCount, 2)
    }

    func testConnectionResolutionUsesSameBoundedRetryPolicy() async throws {
        let adapter = try ScriptedCloudAdapter(
            accountFailures: [.rateLimited(retryAfter: 1.5)],
            steps: [.page(makePage([makeObject(id: "one")]))]
        )
        let clock = LockedTestClock()
        let delays = DelayRecorder()

        let report = await makeBuilder(
            adapter: adapter,
            clock: clock,
            delays: delays
        ).build()

        let recordedDelays = await delays.snapshot()
        let accountCallCount = await adapter.accountCallCount()
        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.retryCount, 1)
        XCTAssertEqual(recordedDelays, [1.5])
        XCTAssertEqual(accountCallCount, 2)
    }

    func testServerFailuresStopAfterHardRetryLimit() async throws {
        let adapter = try ScriptedCloudAdapter(steps: Array(
            repeating: .failure(.serverFailure(statusCode: 503)),
            count: 4
        ))
        let clock = LockedTestClock()
        let delays = DelayRecorder()

        let report = await makeBuilder(
            adapter: adapter,
            clock: clock,
            delays: delays
        ).build()

        XCTAssertEqual(report.completion, .failed)
        XCTAssertEqual(report.issue, .serverFailure)
        XCTAssertEqual(report.retryCount, CloudInventoryLimits.maximumRetryCount)
        let recordedDelays = await delays.snapshot()
        let listCallCount = await adapter.listCallCount()
        XCTAssertEqual(recordedDelays, [0.25, 0.5, 1.0])
        XCTAssertEqual(listCallCount, 4)
    }

    func testAuthorizationExpiredAndMissingCapabilityDoNoInventoryWork() async throws {
        let expired = try ScriptedCloudAdapter(
            status: CloudConnectionStatus(state: .authorizationExpired, detail: "expired"),
            steps: []
        )
        let missingCapability = try ScriptedCloudAdapter(
            capabilities: [.userSelectedFiles],
            steps: []
        )

        let expiredReport = await makeBuilder(adapter: expired).build()
        let capabilityReport = await makeBuilder(adapter: missingCapability).build()

        XCTAssertEqual(expiredReport.completion, .unavailable)
        XCTAssertEqual(expiredReport.issue, .authorizationExpired)
        XCTAssertEqual(capabilityReport.completion, .unavailable)
        XCTAssertEqual(capabilityReport.issue, .missingReadMetadataCapability)
        let expiredListCallCount = await expired.listCallCount()
        let capabilityListCallCount = await missingCapability.listCallCount()
        XCTAssertEqual(expiredListCallCount, 0)
        XCTAssertEqual(capabilityListCallCount, 0)
    }

    func testZeroElapsedBudgetStopsBeforeFirstPage() async throws {
        let adapter = try ScriptedCloudAdapter(steps: [
            .page(makePage([makeObject(id: "never-read")]))
        ])
        let budget = CloudInventoryBudget(maximumElapsedTime: 0)

        let report = await makeBuilder(adapter: adapter, budget: budget).build()

        XCTAssertEqual(report.completion, .truncated)
        XCTAssertEqual(report.issue, .elapsedTimeLimit)
        let listCallCount = await adapter.listCallCount()
        XCTAssertEqual(listCallCount, 0)
    }

    func testElapsedBudgetIsRecheckedAfterPageReturns() async throws {
        let clock = LockedTestClock()
        let adapter = try ScriptedCloudAdapter(
            beforePageReturn: { clock.advance(by: 10) },
            steps: [.page(makePage([makeObject(id: "too-late")]))]
        )
        let budget = CloudInventoryBudget(maximumElapsedTime: 5)

        let report = await makeBuilder(
            adapter: adapter,
            budget: budget,
            clock: clock
        ).build()

        XCTAssertEqual(report.completion, .truncated)
        XCTAssertEqual(report.issue, .elapsedTimeLimit)
        XCTAssertTrue(report.objects.isEmpty)
        XCTAssertEqual(report.pageCount, 0)
    }

    func testNonCooperativeConnectionStatusCannotExceedHardDeadline() async {
        let startedAt = Date()
        let report = await CloudInventoryBuilder(
            adapter: HangingStatusCloudAdapter(),
            budget: CloudInventoryBudget(maximumElapsedTime: 0.05)
        ).build()

        XCTAssertEqual(report.completion, .truncated)
        XCTAssertEqual(report.issue, .elapsedTimeLimit)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.5)
    }

    func testRetryDelayIsClampedToRemainingDeadline() async throws {
        let adapter = try ScriptedCloudAdapter(steps: [
            .failure(.rateLimited(retryAfter: 30)),
            .page(makePage([makeObject(id: "must-not-run")]))
        ])
        let clock = LockedTestClock()
        let delays = DelayRecorder()
        let report = await makeBuilder(
            adapter: adapter,
            budget: CloudInventoryBudget(maximumElapsedTime: 1),
            clock: clock,
            delays: delays
        ).build()

        XCTAssertEqual(report.completion, .truncated)
        XCTAssertEqual(report.issue, .elapsedTimeLimit)
        let recordedDelays = await delays.snapshot()
        let listCallCount = await adapter.listCallCount()
        XCTAssertEqual(recordedDelays, [1])
        XCTAssertEqual(listCallCount, 1)
    }

    private func makeBuilder(
        adapter: ScriptedCloudAdapter,
        budget: CloudInventoryBudget = CloudInventoryBudget(),
        clock: LockedTestClock = LockedTestClock(),
        delays: DelayRecorder = DelayRecorder()
    ) -> CloudInventoryBuilder {
        CloudInventoryBuilder(
            adapter: adapter,
            budget: budget,
            rateLimiter: CloudRateLimiter(jitter: { 0.5 }),
            monotonicTime: { clock.now() },
            sleep: { delay in
                await delays.record(delay)
                clock.advance(by: delay)
            }
        )
    }

    private func makeObject(
        id: String,
        name: String? = nil,
        provider: CloudProviderKind = .dropbox,
        bytes: Int64? = 1
    ) throws -> CloudObjectReference {
        try CloudObjectReference(
            id: id,
            provider: provider,
            displayName: name ?? id,
            objectKind: .file,
            logicalBytes: bytes,
            revision: "revision-\(id)",
            providerHash: "hash-\(id)"
        )
    }

    private func makePage(
        _ objects: [CloudObjectReference],
        cursor: String? = nil,
        truncated: Bool = false,
        responseBytes: Int = 100
    ) throws -> CloudInventoryPage {
        try CloudInventoryPage(
            objects: objects,
            nextCursor: cursor,
            truncated: truncated,
            responseByteCount: responseBytes
        )
    }
}

private struct HangingStatusCloudAdapter: CloudProviderAdapter {
    let kind = CloudProviderKind.dropbox

    func connectionStatus(context: CloudRequestContext) async throws -> CloudConnectionStatus {
        try await withUnsafeThrowingContinuation { (_: UnsafeContinuation<CloudConnectionStatus, Error>) in }
    }

    func accountReference(context: CloudRequestContext) async throws -> CloudConnectionReference {
        throw CloudProviderError.malformedResponse
    }

    func listPage(
        parentID: String?,
        cursor: String?,
        context: CloudRequestContext
    ) async throws -> CloudInventoryPage {
        throw CloudProviderError.malformedResponse
    }

    func metadata(for objectID: String, context: CloudRequestContext) async throws -> CloudObjectReference {
        throw CloudProviderError.malformedResponse
    }

    func disconnect(context: CloudRequestContext) async throws {}
}

private actor ScriptedCloudAdapter: CloudProviderAdapter {
    enum Step: Sendable {
        case page(CloudInventoryPage)
        case failure(CloudProviderError)
        case cancellation
    }

    nonisolated let kind: CloudProviderKind
    private let status: CloudConnectionStatus
    private let connection: CloudConnectionReference
    private let beforePageReturn: @Sendable () -> Void
    private var accountFailures: [CloudProviderError]
    private var steps: [Step]
    private var referenceCallCount = 0
    private var pageCallCount = 0

    init(
        kind: CloudProviderKind = .dropbox,
        status: CloudConnectionStatus = CloudConnectionStatus(state: .connected, detail: "connected"),
        capabilities: Set<CloudCapability> = [.readMetadata],
        accountFailures: [CloudProviderError] = [],
        beforePageReturn: @escaping @Sendable () -> Void = {},
        steps: [Step]
    ) throws {
        self.kind = kind
        self.status = status
        self.beforePageReturn = beforePageReturn
        self.accountFailures = accountFailures
        self.connection = try CloudConnectionReference(
            provider: kind,
            ordinal: 1,
            connectedAt: Date(timeIntervalSince1970: 100),
            grantedCapabilities: capabilities
        )
        self.steps = steps
    }

    func connectionStatus(context: CloudRequestContext) async throws -> CloudConnectionStatus {
        status
    }

    func accountReference(context: CloudRequestContext) async throws -> CloudConnectionReference {
        referenceCallCount += 1
        if !accountFailures.isEmpty {
            throw accountFailures.removeFirst()
        }
        return connection
    }

    func listPage(
        parentID: String?,
        cursor: String?,
        context: CloudRequestContext
    ) async throws -> CloudInventoryPage {
        pageCallCount += 1
        guard !steps.isEmpty else {
            throw CloudProviderError.malformedResponse
        }
        switch steps.removeFirst() {
        case .page(let page):
            beforePageReturn()
            return page
        case .failure(let error):
            throw error
        case .cancellation:
            throw CancellationError()
        }
    }

    func metadata(for objectID: String, context: CloudRequestContext) async throws -> CloudObjectReference {
        throw CloudProviderError.malformedResponse
    }

    func disconnect(context: CloudRequestContext) async throws {}

    func listCallCount() -> Int {
        pageCallCount
    }

    func accountCallCount() -> Int {
        referenceCallCount
    }
}

private final class LockedTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 0

    func now() -> TimeInterval {
        lock.withLock { value }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { value += interval }
    }
}

private actor DelayRecorder {
    private var values = [TimeInterval]()

    func record(_ value: TimeInterval) {
        values.append(value)
    }

    func snapshot() -> [TimeInterval] {
        values
    }
}
