import Foundation

public struct CloudInventoryBudget: Hashable, Sendable {
    public let maximumTotalObjects: Int
    public let maximumTotalResponseBytes: Int
    public let maximumElapsedTime: TimeInterval

    public init(
        maximumTotalObjects: Int = CloudInventoryLimits.maximumTotalObjects,
        maximumTotalResponseBytes: Int = CloudInventoryLimits.maximumTotalResponseBytes,
        maximumElapsedTime: TimeInterval = CloudInventoryLimits.maximumElapsedSeconds
    ) {
        self.maximumTotalObjects = Swift.min(
            Swift.max(0, maximumTotalObjects),
            CloudInventoryLimits.maximumTotalObjects
        )
        self.maximumTotalResponseBytes = Swift.min(
            Swift.max(0, maximumTotalResponseBytes),
            CloudInventoryLimits.maximumTotalResponseBytes
        )
        if maximumElapsedTime.isFinite {
            self.maximumElapsedTime = Swift.min(
                Swift.max(0, maximumElapsedTime),
                CloudInventoryLimits.maximumElapsedSeconds
            )
        } else {
            self.maximumElapsedTime = 0
        }
    }
}

public enum CloudInventoryCompletion: String, CaseIterable, Hashable, Sendable {
    case complete
    case truncated
    case unavailable
    case failed
    case cancelled
}

public enum CloudInventoryIssue: String, CaseIterable, Hashable, Sendable {
    case disconnected
    case degradedConnection
    case authorizationExpired
    case permissionDenied
    case missingReadMetadataCapability
    case objectLimit
    case responseByteLimit
    case elapsedTimeLimit
    case cursorCycle
    case conflictingStableID
    case providerReportedTruncation
    case malformedResponse
    case rateLimited
    case transportFailure
    case serverFailure
    case unknownProviderFailure
}

/// Runtime-only inventory output. Raw provider metadata is deliberately non-Codable.
public struct CloudInventoryReport: Sendable {
    public let provider: CloudProviderKind
    public let connection: CloudConnectionReference?
    public let objects: [CloudObjectReference]
    public let logicalBytes: Int64
    public let pageCount: Int
    public let responseByteCount: Int
    public let retryCount: Int
    public let completion: CloudInventoryCompletion
    public let issue: CloudInventoryIssue?
    public let nonClaims: [String]

    public var isComplete: Bool {
        completion == .complete && issue == nil
    }
}

public struct CloudInventoryBuilder: Sendable {
    private let adapter: any CloudProviderAdapter
    private let budget: CloudInventoryBudget
    private let rateLimiter: CloudRateLimiter
    private let monotonicTime: @Sendable () -> TimeInterval
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    public init(
        adapter: any CloudProviderAdapter,
        budget: CloudInventoryBudget = CloudInventoryBudget(),
        rateLimiter: CloudRateLimiter = CloudRateLimiter(),
        monotonicTime: @escaping @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { delay in
            guard delay > 0 else { return }
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    ) {
        self.adapter = adapter
        self.budget = budget
        self.rateLimiter = rateLimiter
        self.monotonicTime = monotonicTime
        self.sleep = sleep
    }

    public func build() async -> CloudInventoryReport {
        let startedAt = monotonicTime()
        let provider = adapter.kind
        let deadline = startedAt + budget.maximumElapsedTime
        guard startedAt.isFinite,
              deadline.isFinite,
              budget.maximumElapsedTime > 0 else {
            return report(provider: provider, completion: .truncated, issue: .elapsedTimeLimit)
        }
        let requestContext = CloudRequestContext(
            deadlineUptime: deadline,
            maximumResponseBytes: CloudInventoryLimits.maximumResponseBytes
        )
        let status: CloudConnectionStatus
        switch await callWithinDeadline(deadline: deadline, operation: {
            try await adapter.connectionStatus(context: requestContext)
        }) {
        case .success(let value):
            status = value
        case .providerFailure(let error):
            return report(provider: provider, completion: completion(for: error), issue: issue(for: error))
        case .unknownFailure:
            return report(provider: provider, completion: .failed, issue: .unknownProviderFailure)
        case .timedOut:
            return report(provider: provider, completion: .truncated, issue: .elapsedTimeLimit)
        case .cancelled:
            return report(provider: provider, completion: .cancelled)
        }
        switch status.state {
        case .disconnected:
            return report(provider: provider, completion: .unavailable, issue: .disconnected)
        case .degraded:
            return report(provider: provider, completion: .unavailable, issue: .degradedConnection)
        case .authorizationExpired:
            return report(provider: provider, completion: .unavailable, issue: .authorizationExpired)
        case .connected:
            break
        }

        guard !Task.isCancelled else {
            return report(provider: provider, completion: .cancelled)
        }
        guard !elapsedTimeExceeded(deadline: deadline) else {
            return report(provider: provider, completion: .truncated, issue: .elapsedTimeLimit)
        }

        let connectionFetch = await fetchConnection(deadline: deadline, context: requestContext)
        guard let connection = connectionFetch.connection else {
            return report(
                provider: provider,
                retryCount: connectionFetch.retryCount,
                completion: connectionFetch.completion,
                issue: connectionFetch.issue
            )
        }

        guard !elapsedTimeExceeded(deadline: deadline) else {
            return report(
                provider: provider,
                connection: connection,
                retryCount: connectionFetch.retryCount,
                completion: .truncated,
                issue: .elapsedTimeLimit
            )
        }

        guard connection.provider == provider else {
            return report(
                provider: provider,
                retryCount: connectionFetch.retryCount,
                completion: .failed,
                issue: .malformedResponse
            )
        }
        guard connection.grantedCapabilities.contains(.readMetadata) else {
            return report(
                provider: provider,
                connection: connection,
                retryCount: connectionFetch.retryCount,
                completion: .unavailable,
                issue: .missingReadMetadataCapability
            )
        }

        var objects = [CloudObjectReference]()
        var objectsByID = [String: CloudObjectReference]()
        var seenCursors = Set<String>()
        var cursor: String?
        var pageCount = 0
        var responseByteCount = 0
        var retryCount = connectionFetch.retryCount
        var logicalBytes: Int64 = 0
        var providerReportedTruncation = false

        while true {
            guard !Task.isCancelled else {
                return report(
                    provider: provider,
                    connection: connection,
                    objects: objects,
                    logicalBytes: logicalBytes,
                    pageCount: pageCount,
                    responseByteCount: responseByteCount,
                    retryCount: retryCount,
                    completion: .cancelled
                )
            }
            guard !elapsedTimeExceeded(deadline: deadline) else {
                return partialReport(
                    provider: provider,
                    connection: connection,
                    objects: objects,
                    logicalBytes: logicalBytes,
                    pageCount: pageCount,
                    responseByteCount: responseByteCount,
                    retryCount: retryCount,
                    issue: .elapsedTimeLimit
                )
            }
            guard objects.count < budget.maximumTotalObjects else {
                return partialReport(
                    provider: provider,
                    connection: connection,
                    objects: objects,
                    logicalBytes: logicalBytes,
                    pageCount: pageCount,
                    responseByteCount: responseByteCount,
                    retryCount: retryCount,
                    issue: .objectLimit
                )
            }

            let fetch = await fetchPage(cursor: cursor, deadline: deadline, context: requestContext)
            retryCount += fetch.retryCount
            guard let page = fetch.page else {
                return report(
                    provider: provider,
                    connection: connection,
                    objects: objects,
                    logicalBytes: logicalBytes,
                    pageCount: pageCount,
                    responseByteCount: responseByteCount,
                    retryCount: retryCount,
                    completion: fetch.completion,
                    issue: fetch.issue
                )
            }
            guard !elapsedTimeExceeded(deadline: deadline) else {
                return partialReport(
                    provider: provider,
                    connection: connection,
                    objects: objects,
                    logicalBytes: logicalBytes,
                    pageCount: pageCount,
                    responseByteCount: responseByteCount,
                    retryCount: retryCount,
                    issue: .elapsedTimeLimit
                )
            }

            guard page.responseByteCount <= budget.maximumTotalResponseBytes - responseByteCount else {
                return partialReport(
                    provider: provider,
                    connection: connection,
                    objects: objects,
                    logicalBytes: logicalBytes,
                    pageCount: pageCount,
                    responseByteCount: responseByteCount,
                    retryCount: retryCount,
                    issue: .responseByteLimit
                )
            }
            responseByteCount += page.responseByteCount
            pageCount += 1
            providerReportedTruncation = providerReportedTruncation || page.truncated

            for object in page.objects {
                guard object.provider == provider else {
                    return failedReport(
                        provider: provider,
                        connection: connection,
                        objects: objects,
                        logicalBytes: logicalBytes,
                        pageCount: pageCount,
                        responseByteCount: responseByteCount,
                        retryCount: retryCount,
                        issue: .malformedResponse
                    )
                }
                if let existing = objectsByID[object.id] {
                    guard existing == object else {
                        return failedReport(
                            provider: provider,
                            connection: connection,
                            objects: objects,
                            logicalBytes: logicalBytes,
                            pageCount: pageCount,
                            responseByteCount: responseByteCount,
                            retryCount: retryCount,
                            issue: .conflictingStableID
                        )
                    }
                    continue
                }
                guard objects.count < budget.maximumTotalObjects else {
                    return partialReport(
                        provider: provider,
                        connection: connection,
                        objects: objects,
                        logicalBytes: logicalBytes,
                        pageCount: pageCount,
                        responseByteCount: responseByteCount,
                        retryCount: retryCount,
                        issue: .objectLimit
                    )
                }
                if let byteCount = object.logicalBytes {
                    let addition = logicalBytes.addingReportingOverflow(byteCount)
                    guard !addition.overflow else {
                        return failedReport(
                            provider: provider,
                            connection: connection,
                            objects: objects,
                            logicalBytes: logicalBytes,
                            pageCount: pageCount,
                            responseByteCount: responseByteCount,
                            retryCount: retryCount,
                            issue: .malformedResponse
                        )
                    }
                    logicalBytes = addition.partialValue
                }
                objectsByID[object.id] = object
                objects.append(object)
            }

            guard let nextCursor = page.nextCursor else {
                if providerReportedTruncation {
                    return partialReport(
                        provider: provider,
                        connection: connection,
                        objects: objects,
                        logicalBytes: logicalBytes,
                        pageCount: pageCount,
                        responseByteCount: responseByteCount,
                        retryCount: retryCount,
                        issue: .providerReportedTruncation
                    )
                }
                return report(
                    provider: provider,
                    connection: connection,
                    objects: objects,
                    logicalBytes: logicalBytes,
                    pageCount: pageCount,
                    responseByteCount: responseByteCount,
                    retryCount: retryCount,
                    completion: .complete
                )
            }
            guard seenCursors.insert(nextCursor).inserted else {
                return partialReport(
                    provider: provider,
                    connection: connection,
                    objects: objects,
                    logicalBytes: logicalBytes,
                    pageCount: pageCount,
                    responseByteCount: responseByteCount,
                    retryCount: retryCount,
                    issue: .cursorCycle
                )
            }
            cursor = nextCursor
        }
    }

    private func fetchPage(
        cursor: String?,
        deadline: TimeInterval,
        context: CloudRequestContext
    ) async -> PageFetchResult {
        var retryCount = 0
        while true {
            switch await callWithinDeadline(deadline: deadline, operation: {
                try await adapter.listPage(parentID: nil, cursor: cursor, context: context)
            }) {
            case .success(let page):
                return PageFetchResult(page: page, retryCount: retryCount, completion: .complete, issue: nil)
            case .cancelled:
                return PageFetchResult(page: nil, retryCount: retryCount, completion: .cancelled, issue: nil)
            case .timedOut:
                return PageFetchResult(
                    page: nil,
                    retryCount: retryCount,
                    completion: .truncated,
                    issue: .elapsedTimeLimit
                )
            case .providerFailure(let error):
                let nextRetry = retryCount + 1
                guard let delay = rateLimiter.delay(for: error, retryNumber: nextRetry) else {
                    return PageFetchResult(
                        page: nil,
                        retryCount: retryCount,
                        completion: completion(for: error),
                        issue: issue(for: error)
                    )
                }
                guard let boundedDelay = boundedRetryDelay(delay, deadline: deadline) else {
                    return PageFetchResult(
                        page: nil,
                        retryCount: retryCount,
                        completion: .truncated,
                        issue: .elapsedTimeLimit
                    )
                }
                switch await callWithinDeadline(deadline: deadline, operation: {
                    try await sleep(boundedDelay)
                    return true
                }) {
                case .success:
                    break
                case .cancelled:
                    return PageFetchResult(page: nil, retryCount: retryCount, completion: .cancelled, issue: nil)
                case .timedOut:
                    return PageFetchResult(
                        page: nil,
                        retryCount: retryCount,
                        completion: .truncated,
                        issue: .elapsedTimeLimit
                    )
                case .providerFailure, .unknownFailure:
                    return PageFetchResult(page: nil, retryCount: retryCount, completion: .cancelled, issue: nil)
                }
                retryCount = nextRetry
                guard boundedDelay == delay else {
                    return PageFetchResult(
                        page: nil,
                        retryCount: retryCount,
                        completion: .truncated,
                        issue: .elapsedTimeLimit
                    )
                }
                guard !Task.isCancelled else {
                    return PageFetchResult(page: nil, retryCount: retryCount, completion: .cancelled, issue: nil)
                }
                guard !elapsedTimeExceeded(deadline: deadline) else {
                    return PageFetchResult(
                        page: nil,
                        retryCount: retryCount,
                        completion: .truncated,
                        issue: .elapsedTimeLimit
                    )
                }
            case .unknownFailure:
                return PageFetchResult(
                    page: nil,
                    retryCount: retryCount,
                    completion: .failed,
                    issue: .unknownProviderFailure
                )
            }
        }
    }

    private func fetchConnection(
        deadline: TimeInterval,
        context: CloudRequestContext
    ) async -> ConnectionFetchResult {
        var retryCount = 0
        while true {
            switch await callWithinDeadline(deadline: deadline, operation: {
                try await adapter.accountReference(context: context)
            }) {
            case .success(let connection):
                return ConnectionFetchResult(
                    connection: connection,
                    retryCount: retryCount,
                    completion: .complete,
                    issue: nil
                )
            case .cancelled:
                return ConnectionFetchResult(
                    connection: nil,
                    retryCount: retryCount,
                    completion: .cancelled,
                    issue: nil
                )
            case .timedOut:
                return ConnectionFetchResult(
                    connection: nil,
                    retryCount: retryCount,
                    completion: .truncated,
                    issue: .elapsedTimeLimit
                )
            case .providerFailure(let error):
                let nextRetry = retryCount + 1
                guard let delay = rateLimiter.delay(for: error, retryNumber: nextRetry) else {
                    return ConnectionFetchResult(
                        connection: nil,
                        retryCount: retryCount,
                        completion: completion(for: error),
                        issue: issue(for: error)
                    )
                }
                guard let boundedDelay = boundedRetryDelay(delay, deadline: deadline) else {
                    return ConnectionFetchResult(
                        connection: nil,
                        retryCount: retryCount,
                        completion: .truncated,
                        issue: .elapsedTimeLimit
                    )
                }
                switch await callWithinDeadline(deadline: deadline, operation: {
                    try await sleep(boundedDelay)
                    return true
                }) {
                case .success:
                    break
                case .cancelled:
                    return ConnectionFetchResult(
                        connection: nil,
                        retryCount: retryCount,
                        completion: .cancelled,
                        issue: nil
                    )
                case .timedOut:
                    return ConnectionFetchResult(
                        connection: nil,
                        retryCount: retryCount,
                        completion: .truncated,
                        issue: .elapsedTimeLimit
                    )
                case .providerFailure, .unknownFailure:
                    return ConnectionFetchResult(
                        connection: nil,
                        retryCount: retryCount,
                        completion: .cancelled,
                        issue: nil
                    )
                }
                retryCount = nextRetry
                guard boundedDelay == delay else {
                    return ConnectionFetchResult(
                        connection: nil,
                        retryCount: retryCount,
                        completion: .truncated,
                        issue: .elapsedTimeLimit
                    )
                }
                guard !Task.isCancelled else {
                    return ConnectionFetchResult(
                        connection: nil,
                        retryCount: retryCount,
                        completion: .cancelled,
                        issue: nil
                    )
                }
                guard !elapsedTimeExceeded(deadline: deadline) else {
                    return ConnectionFetchResult(
                        connection: nil,
                        retryCount: retryCount,
                        completion: .truncated,
                        issue: .elapsedTimeLimit
                    )
                }
            case .unknownFailure:
                return ConnectionFetchResult(
                    connection: nil,
                    retryCount: retryCount,
                    completion: .failed,
                    issue: .unknownProviderFailure
                )
            }
        }
    }

    private func elapsedTimeExceeded(deadline: TimeInterval) -> Bool {
        let now = monotonicTime()
        return !now.isFinite || now >= deadline
    }

    private func boundedRetryDelay(_ requested: TimeInterval, deadline: TimeInterval) -> TimeInterval? {
        let now = monotonicTime()
        let remaining = deadline - now
        guard requested.isFinite,
              requested >= 0,
              remaining.isFinite,
              remaining > 0 else {
            return nil
        }
        return Swift.min(requested, remaining)
    }

    private func callWithinDeadline<Value: Sendable>(
        deadline: TimeInterval,
        operation: @escaping @Sendable () async throws -> Value
    ) async -> AdapterCallOutcome<Value> {
        let remaining = deadline - monotonicTime()
        guard remaining.isFinite, remaining > 0 else {
            return .timedOut
        }

        let race = DeadlineRaceState<Value>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                race.install(continuation)

                let operationTask = Task {
                    let outcome: AdapterCallOutcome<Value>
                    do {
                        outcome = .success(try await operation())
                    } catch is CancellationError {
                        outcome = .cancelled
                    } catch let error as CloudProviderError {
                        outcome = .providerFailure(error)
                    } catch {
                        outcome = .unknownFailure
                    }
                    race.resolve(outcome, winner: .operation)
                }
                race.setOperationTask(operationTask)

                let timeoutTask = Task {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                    } catch {
                        return
                    }
                    race.resolve(.timedOut, winner: .timeout)
                }
                race.setTimeoutTask(timeoutTask)
            }
        } onCancel: {
            race.resolve(.cancelled, winner: .cancellation)
        }
    }

    private func completion(for error: CloudProviderError) -> CloudInventoryCompletion {
        switch error {
        case .unauthorized, .forbidden:
            .unavailable
        case .rateLimited, .serverFailure, .transportFailure, .malformedResponse:
            .failed
        }
    }

    private func issue(for error: CloudProviderError) -> CloudInventoryIssue {
        switch error {
        case .unauthorized:
            .authorizationExpired
        case .forbidden:
            .permissionDenied
        case .rateLimited:
            .rateLimited
        case .serverFailure:
            .serverFailure
        case .transportFailure:
            .transportFailure
        case .malformedResponse:
            .malformedResponse
        }
    }

    private func partialReport(
        provider: CloudProviderKind,
        connection: CloudConnectionReference,
        objects: [CloudObjectReference],
        logicalBytes: Int64,
        pageCount: Int,
        responseByteCount: Int,
        retryCount: Int,
        issue: CloudInventoryIssue
    ) -> CloudInventoryReport {
        report(
            provider: provider,
            connection: connection,
            objects: objects,
            logicalBytes: logicalBytes,
            pageCount: pageCount,
            responseByteCount: responseByteCount,
            retryCount: retryCount,
            completion: .truncated,
            issue: issue
        )
    }

    private func failedReport(
        provider: CloudProviderKind,
        connection: CloudConnectionReference,
        objects: [CloudObjectReference],
        logicalBytes: Int64,
        pageCount: Int,
        responseByteCount: Int,
        retryCount: Int,
        issue: CloudInventoryIssue
    ) -> CloudInventoryReport {
        report(
            provider: provider,
            connection: connection,
            objects: objects,
            logicalBytes: logicalBytes,
            pageCount: pageCount,
            responseByteCount: responseByteCount,
            retryCount: retryCount,
            completion: .failed,
            issue: issue
        )
    }

    private func report(
        provider: CloudProviderKind,
        connection: CloudConnectionReference? = nil,
        objects: [CloudObjectReference] = [],
        logicalBytes: Int64 = 0,
        pageCount: Int = 0,
        responseByteCount: Int = 0,
        retryCount: Int = 0,
        completion: CloudInventoryCompletion,
        issue: CloudInventoryIssue? = nil
    ) -> CloudInventoryReport {
        CloudInventoryReport(
            provider: provider,
            connection: connection,
            objects: objects,
            logicalBytes: logicalBytes,
            pageCount: pageCount,
            responseByteCount: responseByteCount,
            retryCount: retryCount,
            completion: completion,
            issue: issue,
            nonClaims: ProtectReadinessNonClaims.cloud
        )
    }

    private struct PageFetchResult: Sendable {
        let page: CloudInventoryPage?
        let retryCount: Int
        let completion: CloudInventoryCompletion
        let issue: CloudInventoryIssue?
    }

    private struct ConnectionFetchResult: Sendable {
        let connection: CloudConnectionReference?
        let retryCount: Int
        let completion: CloudInventoryCompletion
        let issue: CloudInventoryIssue?
    }
}

private enum AdapterCallOutcome<Value: Sendable>: Sendable {
    case success(Value)
    case providerFailure(CloudProviderError)
    case unknownFailure
    case timedOut
    case cancelled
}

private enum DeadlineRaceWinner {
    case operation
    case timeout
    case cancellation
}

private final class DeadlineRaceState<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<AdapterCallOutcome<Value>, Never>?
    private var pendingOutcome: AdapterCallOutcome<Value>?
    private var completed = false
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    func install(_ continuation: CheckedContinuation<AdapterCallOutcome<Value>, Never>) {
        let immediate: AdapterCallOutcome<Value>? = lock.withLock {
            if completed {
                return pendingOutcome
            }
            self.continuation = continuation
            return nil
        }
        if let immediate {
            continuation.resume(returning: immediate)
        }
    }

    func setOperationTask(_ task: Task<Void, Never>) {
        let shouldCancel = lock.withLock {
            if completed { return true }
            operationTask = task
            return false
        }
        if shouldCancel { task.cancel() }
    }

    func setTimeoutTask(_ task: Task<Void, Never>) {
        let shouldCancel = lock.withLock {
            if completed { return true }
            timeoutTask = task
            return false
        }
        if shouldCancel { task.cancel() }
    }

    func resolve(_ outcome: AdapterCallOutcome<Value>, winner: DeadlineRaceWinner) {
        let resolution: (
            CheckedContinuation<AdapterCallOutcome<Value>, Never>?,
            Task<Void, Never>?,
            Task<Void, Never>?
        )? = lock.withLock {
            guard !completed else { return nil }
            completed = true
            let capturedContinuation = continuation
            continuation = nil
            if capturedContinuation == nil {
                pendingOutcome = outcome
            }
            let operationToCancel = winner == .operation ? nil : operationTask
            let timeoutToCancel = winner == .timeout ? nil : timeoutTask
            operationTask = nil
            timeoutTask = nil
            return (capturedContinuation, operationToCancel, timeoutToCancel)
        }
        guard let resolution else { return }
        resolution.1?.cancel()
        resolution.2?.cancel()
        resolution.0?.resume(returning: outcome)
    }
}
