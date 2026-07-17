import Foundation
import XCTest
@testable import RyddiProtectCore

final class CloudProviderConformanceTests: XCTestCase {
    func testAdapterConformanceHarnessExercisesEveryReadRequestWithOneDeadline() async throws {
        let adapter = try ConformanceFixtureAdapter()

        let report = await CloudProviderAdapterConformanceHarness.inventory(adapter: adapter)
        let contexts = await adapter.recordedContexts()

        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.objects.map(\.id), ["fixture-one", "fixture-two"])
        XCTAssertEqual(contexts.count, 4, "status, account, and both page requests must be covered")
        XCTAssertEqual(Set(contexts.map(\.deadlineUptime)).count, 1)
        XCTAssertTrue(contexts.allSatisfy {
            $0.deadlineUptime.isFinite
                && $0.maximumResponseBytes == CloudInventoryLimits.maximumResponseBytes
        })
    }

    func testInventoryBudgetClampsEveryCallerControlledLimit() {
        let budget = CloudInventoryBudget(
            maximumTotalObjects: Int.max,
            maximumTotalResponseBytes: Int.max,
            maximumElapsedTime: .infinity
        )

        XCTAssertEqual(budget.maximumTotalObjects, CloudInventoryLimits.maximumTotalObjects)
        XCTAssertEqual(budget.maximumTotalResponseBytes, CloudInventoryLimits.maximumTotalResponseBytes)
        XCTAssertEqual(budget.maximumElapsedTime, 0)
    }

    func testRateLimiterRetriesOnlyTypedTransientFailures() {
        let limiter = CloudRateLimiter(maximumRetryCount: 99, jitter: { 0.5 })

        XCTAssertEqual(limiter.maximumRetryCount, CloudInventoryLimits.maximumRetryCount)
        XCTAssertNil(limiter.delay(for: .unauthorized, retryNumber: 1))
        XCTAssertNil(limiter.delay(for: .forbidden, retryNumber: 1))
        XCTAssertNil(limiter.delay(for: .malformedResponse, retryNumber: 1))
        XCTAssertNil(limiter.delay(for: .serverFailure(statusCode: 400), retryNumber: 1))
        XCTAssertEqual(limiter.delay(for: .serverFailure(statusCode: 503), retryNumber: 1), 0.25)
        XCTAssertEqual(limiter.delay(for: .transportFailure, retryNumber: 2), 0.5)
        XCTAssertEqual(
            limiter.delay(for: .rateLimited(retryAfter: 1000), retryNumber: 1),
            CloudRateLimiter.maximumRetryDelay
        )
        XCTAssertNil(limiter.delay(for: .transportFailure, retryNumber: 4))

        let nonFiniteJitter = CloudRateLimiter(jitter: { .nan })
        XCTAssertEqual(nonFiniteJitter.delay(for: .transportFailure, retryNumber: 1), 0.25)
    }
}

private enum CloudProviderAdapterConformanceHarness {
    static func inventory(adapter: any CloudProviderAdapter) async -> CloudInventoryReport {
        await CloudInventoryBuilder(
            adapter: adapter,
            budget: CloudInventoryBudget(maximumElapsedTime: 1),
            rateLimiter: CloudRateLimiter(jitter: { 0.5 })
        ).build()
    }
}

private actor ConformanceFixtureAdapter: CloudProviderAdapter {
    nonisolated let kind = CloudProviderKind.dropbox
    private let connection: CloudConnectionReference
    private let pages: [CloudInventoryPage]
    private var pageIndex = 0
    private var contexts = [CloudRequestContext]()

    init() throws {
        self.connection = try CloudConnectionReference(
            provider: .dropbox,
            ordinal: 1,
            grantedCapabilities: [.readMetadata]
        )
        let first = try CloudObjectReference(
            id: "fixture-one",
            provider: .dropbox,
            displayName: "fixture-one",
            objectKind: .file
        )
        let second = try CloudObjectReference(
            id: "fixture-two",
            provider: .dropbox,
            displayName: "fixture-two",
            objectKind: .file
        )
        self.pages = [
            try CloudInventoryPage(
                objects: [first],
                nextCursor: "next",
                truncated: false,
                responseByteCount: 100
            ),
            try CloudInventoryPage(
                objects: [second],
                nextCursor: nil,
                truncated: false,
                responseByteCount: 100
            )
        ]
    }

    func connectionStatus(context: CloudRequestContext) async throws -> CloudConnectionStatus {
        contexts.append(context)
        return CloudConnectionStatus(state: .connected, detail: "fixture")
    }

    func accountReference(context: CloudRequestContext) async throws -> CloudConnectionReference {
        contexts.append(context)
        return connection
    }

    func listPage(
        parentID: String?,
        cursor: String?,
        context: CloudRequestContext
    ) async throws -> CloudInventoryPage {
        contexts.append(context)
        guard pageIndex < pages.count else { throw CloudProviderError.malformedResponse }
        defer { pageIndex += 1 }
        return pages[pageIndex]
    }

    func metadata(for objectID: String, context: CloudRequestContext) async throws -> CloudObjectReference {
        throw CloudProviderError.malformedResponse
    }

    func disconnect(context: CloudRequestContext) async throws {}

    func recordedContexts() -> [CloudRequestContext] {
        contexts
    }
}
