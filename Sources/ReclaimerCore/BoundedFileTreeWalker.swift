import Foundation

struct BoundedFileTree {
    struct Node {
        let parentIndex: Int?
        let scopeIndex: Int
        let url: URL
        let absoluteDepth: Int
        let resource: ResourceMetadata
        var measurements: [FileMeasurement]

        var boundedMeasurement: FileMeasurement {
            measurements.reduce(.zero, +)
        }
    }

    struct ResourceMetadata {
        let isDirectory: Bool
        let isSymbolicLink: Bool
        let isPackage: Bool
        let isRegularFile: Bool
        let logicalSize: Int64
        let allocatedSize: Int64
        let modificationDate: Date?
    }

    struct ScopeIssue {
        let scopeIndex: Int
        let state: PermissionState
        let message: String
    }

    let nodes: [Node]
    let coverage: ScanCoverage
    let scopeIssues: [ScopeIssue]
}

struct BoundedFileTreeWalker {
    private let scopeAccessProbe: (any ScopeAccessProbing)?
    private let compatibilityReadabilityProvider: ((URL, FileManager) -> ScopeReadability)?

    init(
        scopeAccessProbe: any ScopeAccessProbing = FileManagerScopeAccessProbe()
    ) {
        self.scopeAccessProbe = scopeAccessProbe
        self.compatibilityReadabilityProvider = nil
    }

    init(scopeReadabilityProvider: @escaping (URL, FileManager) -> ScopeReadability) {
        self.scopeAccessProbe = nil
        self.compatibilityReadabilityProvider = scopeReadabilityProvider
    }

    func walk(
        scopes: [ScanScope],
        options: ScanOptions,
        fileManager: FileManager,
        userPathPolicy: UserPathPolicy,
        control: ScanControl
    ) -> BoundedFileTree {
        let measurementDepth = max(0, options.measurementDepth)
        let traversalDepth = max(0, options.maximumFindingDepth) + measurementDepth
        var frontiers = scopes.map { _ in FIFOFrontier() }
        var metrics = scopes.map { ScopeMetrics(scope: $0) }
        var scopeIssues = [BoundedFileTree.ScopeIssue]()
        var cancelled = false

        control.progress?(ScanProgress(
            phase: .measuring,
            scopeName: nil,
            measuredItemCount: 0,
            requestedItemBudget: options.measurementItemBudget
        ))

        for (scopeIndex, scope) in scopes.enumerated() {
            guard !control.cancellation.isCancelled else {
                cancelled = true
                metrics[scopeIndex].wasCancelled = true
                continue
            }
            let root = scope.root
            guard userPathPolicy.matchingRule(for: root.path, kind: .exclude) == nil else {
                continue
            }

            let probeResult = accessResult(for: root, fileManager: fileManager)
            metrics[scopeIndex].accessResult = probeResult
            switch probeResult.state {
            case .missing:
                metrics[scopeIndex].isMissing = true
                metrics[scopeIndex].evidence.append("This optional scan root was not present on this Mac.")
                scopeIssues.append(.init(scopeIndex: scopeIndex, state: .missing, message: "Path does not exist."))
            case .permissionDenied:
                metrics[scopeIndex].isPermissionDenied = true
                metrics[scopeIndex].evidence.append("This scan root could not be read because permission was denied.")
                scopeIssues.append(.init(
                    scopeIndex: scopeIndex,
                    state: .denied,
                    message: probeEvidenceMessage(prefix: "Permission required", result: probeResult)
                ))
            case .unknown:
                metrics[scopeIndex].isUnknown = true
                metrics[scopeIndex].evidence.append("This scan root access check failed without permission-denied evidence.")
                scopeIssues.append(.init(
                    scopeIndex: scopeIndex,
                    state: .unknown,
                    message: probeEvidenceMessage(prefix: "Access check failed", result: probeResult)
                ))
            case .readable:
                frontiers[scopeIndex].append(.init(url: root, parentIndex: nil, depth: 0))
            }
        }

        var nodes = [BoundedFileTree.Node]()
        var hardLinkIdentityKeys = Set<String>()
        var measuredItemCount = 0

        traversal: while frontiers.contains(where: { !$0.isEmpty }) {
            var visitedInRound = false

            for scopeIndex in scopes.indices {
                if control.cancellation.isCancelled {
                    cancelled = true
                    metrics[scopeIndex].wasCancelled = true
                    break traversal
                }
                guard measuredItemCount < options.measurementItemBudget else {
                    break traversal
                }
                guard let entry = frontiers[scopeIndex].popFirst() else { continue }
                visitedInRound = true

                guard userPathPolicy.matchingRule(for: entry.url.path, kind: .exclude) == nil else {
                    continue
                }

                measuredItemCount += 1
                metrics[scopeIndex].measuredItemCount += 1
                metrics[scopeIndex].deepestMeasuredLevel = max(
                    metrics[scopeIndex].deepestMeasuredLevel,
                    entry.depth
                )
                control.progress?(ScanProgress(
                    phase: .measuring,
                    scopeName: scopes[scopeIndex].name,
                    measuredItemCount: measuredItemCount,
                    requestedItemBudget: options.measurementItemBudget
                ))
                guard !control.cancellation.isCancelled else {
                    cancelled = true
                    metrics[scopeIndex].wasCancelled = true
                    break traversal
                }

                let values: URLResourceValues
                do {
                    values = try entry.url.resourceValues(forKeys: Set(boundedResourceKeys))
                } catch {
                    recordTraversalFailure(
                        error,
                        operation: .metadata,
                        entryDepth: entry.depth,
                        scopeIndex: scopeIndex,
                        metrics: &metrics,
                        scopeIssues: &scopeIssues
                    )
                    continue
                }

                let resource = resourceMetadata(
                    values: values,
                    url: entry.url,
                    deduplicateHardLinks: options.deduplicateHardLinks,
                    hardLinkIdentityKeys: &hardLinkIdentityKeys
                )
                var layers = Array(repeating: FileMeasurement.zero, count: measurementDepth + 1)
                layers[0] = FileMeasurement(
                    logicalSize: resource.logicalSize,
                    allocatedSize: resource.allocatedSize,
                    itemCount: 1
                )
                let nodeIndex = nodes.count
                nodes.append(.init(
                    parentIndex: entry.parentIndex,
                    scopeIndex: scopeIndex,
                    url: entry.url,
                    absoluteDepth: entry.depth,
                    resource: resource,
                    measurements: layers
                ))

                guard resource.isDirectory,
                      !resource.isSymbolicLink,
                      !resource.isPackage,
                      entry.depth < traversalDepth
                else {
                    continue
                }
                guard measuredItemCount < options.measurementItemBudget else {
                    metrics[scopeIndex].skippedItemCount += 1
                    continue
                }
                guard !control.cancellation.isCancelled else {
                    cancelled = true
                    metrics[scopeIndex].wasCancelled = true
                    break traversal
                }

                do {
                    let children = try fileManager.contentsOfDirectory(
                        at: entry.url,
                        includingPropertiesForKeys: boundedResourceKeys,
                        options: [.skipsPackageDescendants]
                    )
                    for child in children.sorted(by: { $0.path < $1.path }) {
                        guard !control.cancellation.isCancelled else {
                            cancelled = true
                            metrics[scopeIndex].wasCancelled = true
                            break traversal
                        }
                        guard userPathPolicy.matchingRule(for: child.path, kind: .exclude) == nil else {
                            continue
                        }
                        frontiers[scopeIndex].append(.init(
                            url: child,
                            parentIndex: nodeIndex,
                            depth: entry.depth + 1
                        ))
                    }
                } catch {
                    recordTraversalFailure(
                        error,
                        operation: .listDirectory,
                        entryDepth: entry.depth,
                        scopeIndex: scopeIndex,
                        metrics: &metrics,
                        scopeIssues: &scopeIssues
                    )
                }
            }

            if !visitedInRound { break }
        }

        for scopeIndex in scopes.indices {
            metrics[scopeIndex].skippedItemCount += frontiers[scopeIndex].remainingCount
        }

        for nodeIndex in nodes.indices.reversed() {
            guard let parentIndex = nodes[nodeIndex].parentIndex else { continue }
            for layerIndex in 0..<measurementDepth {
                nodes[parentIndex].measurements[layerIndex + 1] =
                    nodes[parentIndex].measurements[layerIndex + 1]
                    + nodes[nodeIndex].measurements[layerIndex]
            }
        }

        if cancelled {
            for scopeIndex in scopes.indices where
                metrics[scopeIndex].wasCancelled || !frontiers[scopeIndex].isEmpty
            {
                metrics[scopeIndex].wasCancelled = true
                metrics[scopeIndex].evidence.append("Measurement was cancelled before this scope completed.")
            }
        }

        let coverage = makeCoverage(
            metrics: metrics,
            requestedBudget: options.measurementItemBudget,
            measuredItemCount: measuredItemCount,
            measurementDepth: options.measurementDepth,
            cancelled: cancelled
        )
        return BoundedFileTree(nodes: nodes, coverage: coverage, scopeIssues: scopeIssues)
    }

    private func resourceMetadata(
        values: URLResourceValues,
        url: URL,
        deduplicateHardLinks: Bool,
        hardLinkIdentityKeys: inout Set<String>
    ) -> BoundedFileTree.ResourceMetadata {
        let isDirectory = values.isDirectory ?? false
        let isSymbolicLink = values.isSymbolicLink ?? false
        let isRegularFile = values.isRegularFile ?? false
        var logicalSize: Int64 = 0
        var allocatedSize: Int64 = 0

        if !isDirectory, !isSymbolicLink {
            var isDuplicateHardLink = false
            if deduplicateHardLinks,
               isRegularFile,
               let identity = try? FilesystemIdentity.capture(at: url),
               let key = identity.fileIdentityKey,
               (identity.hardLinkCount ?? 1) > 1
            {
                isDuplicateHardLink = hardLinkIdentityKeys.contains(key)
                hardLinkIdentityKeys.insert(key)
            }
            if !isDuplicateHardLink {
                logicalSize = Int64(values.fileSize ?? 0)
                allocatedSize = Int64(
                    values.totalFileAllocatedSize
                    ?? values.fileAllocatedSize
                    ?? values.fileSize
                    ?? 0
                )
            }
        }

        return .init(
            isDirectory: isDirectory,
            isSymbolicLink: isSymbolicLink,
            isPackage: values.isPackage ?? false,
            isRegularFile: isRegularFile,
            logicalSize: logicalSize,
            allocatedSize: allocatedSize,
            modificationDate: values.contentModificationDate
        )
    }

    private func makeCoverage(
        metrics: [ScopeMetrics],
        requestedBudget: Int,
        measuredItemCount: Int,
        measurementDepth: Int,
        cancelled: Bool
    ) -> ScanCoverage {
        let skippedItemCount = metrics.reduce(0) { $0 + $1.skippedItemCount }
        let rootsMissing = metrics.filter(\.isMissing).count
        let rootsPermissionDenied = metrics.filter(\.isPermissionDenied).count
        let rootsUnknown = metrics.filter(\.isUnknown).count
        let hasUnreadableDescendant = metrics.contains(where: \.hasUnreadableDescendant)
        let state: ScanCoverageState
        if rootsPermissionDenied > 0 || rootsUnknown > 0 || hasUnreadableDescendant {
            state = .degraded
        } else if skippedItemCount > 0 || measuredItemCount >= requestedBudget || cancelled {
            state = .bounded
        } else {
            state = .complete
        }

        var evidence = [String]()
        if rootsMissing > 0 {
            evidence.append("\(rootsMissing) optional scan root(s) were not present on this Mac.")
        }
        if rootsPermissionDenied > 0 {
            evidence.append("\(rootsPermissionDenied) scan root(s) could not be read because permission was denied.")
        }
        if rootsUnknown > 0 {
            evidence.append(
                rootsUnknown == 1
                    ? "1 scan root access check failed without permission-denied evidence."
                    : "\(rootsUnknown) scan root access checks failed without permission-denied evidence."
            )
        }
        if hasUnreadableDescendant {
            evidence.append("One or more descendants could not be read and were not measured.")
        }
        if skippedItemCount > 0 || measuredItemCount >= requestedBudget {
            evidence.append("Measurement stopped at \(requestedBudget) item(s); run a targeted rescan for exact local evidence.")
        }
        if cancelled {
            evidence.append("Measurement was cancelled before all queued items were visited.")
        }

        let scopeCoverage = metrics.map { metric in
            let scopeState: ScanCoverageState
            if metric.isPermissionDenied || metric.isUnknown || metric.hasUnreadableDescendant {
                scopeState = .degraded
            } else if metric.skippedItemCount > 0 || metric.wasCancelled {
                scopeState = .bounded
            } else {
                scopeState = .complete
            }
            var scopeEvidence = metric.evidence
            if metric.skippedItemCount > 0 {
                scopeEvidence.append("\(metric.skippedItemCount) queued or unreadable item(s) were not measured.")
            }
            return ScanScopeCoverage(
                scopeName: metric.scope.name,
                rootPath: metric.scope.root.path,
                state: scopeState,
                measuredItemCount: metric.measuredItemCount,
                skippedItemCount: metric.skippedItemCount,
                deepestMeasuredLevel: metric.deepestMeasuredLevel,
                evidence: scopeEvidence
            )
        }

        return ScanCoverage(
            state: state,
            requestedItemBudget: requestedBudget,
            measuredItemCount: measuredItemCount,
            skippedItemCount: skippedItemCount,
            rootsVisited: metrics.count,
            rootsDenied: rootsPermissionDenied,
            maximumMeasurementDepth: measurementDepth,
            rootsMissing: rootsMissing,
            rootsPermissionDenied: rootsPermissionDenied,
            rootsUnknown: rootsUnknown,
            evidence: evidence,
            scopeCoverage: scopeCoverage,
            scopeAccessSummaries: metrics.compactMap { metric in
                metric.accessResult.map { result in
                    PermissionAdvisor.scopeSummary(scope: metric.scope, result: result)
                }
            }
        )
    }

    private func recordTraversalFailure(
        _ error: Error,
        operation: ScopeAccessOperation,
        entryDepth: Int,
        scopeIndex: Int,
        metrics: inout [ScopeMetrics],
        scopeIssues: inout [BoundedFileTree.ScopeIssue]
    ) {
        let result = ScopeAccessProbeResult.failure(error, operation: operation)
        if entryDepth == 0 {
            metrics[scopeIndex].isMissing = false
            metrics[scopeIndex].isPermissionDenied = false
            metrics[scopeIndex].isUnknown = false
            metrics[scopeIndex].accessResult = result
            let state: PermissionState
            let prefix: String
            switch result.state {
            case .missing:
                metrics[scopeIndex].isMissing = true
                metrics[scopeIndex].evidence.append("This optional scan root disappeared during measurement.")
                state = .missing
                prefix = "Path disappeared"
            case .permissionDenied:
                metrics[scopeIndex].skippedItemCount += 1
                metrics[scopeIndex].isPermissionDenied = true
                state = .denied
                prefix = "Permission required"
            case .unknown:
                metrics[scopeIndex].skippedItemCount += 1
                metrics[scopeIndex].isUnknown = true
                state = .unknown
                prefix = "Access check failed"
            case .readable:
                return
            }
            scopeIssues.append(.init(
                scopeIndex: scopeIndex,
                state: state,
                message: probeEvidenceMessage(prefix: prefix, result: result)
            ))
            return
        }

        metrics[scopeIndex].skippedItemCount += 1
        switch result.state {
        case .missing:
            metrics[scopeIndex].evidence.append("A queued descendant disappeared before it could be measured.")
        case .permissionDenied:
            metrics[scopeIndex].hasUnreadableDescendant = true
            metrics[scopeIndex].evidence.append("A descendant operation was denied and was not measured.")
        case .unknown:
            metrics[scopeIndex].hasUnreadableDescendant = true
            metrics[scopeIndex].evidence.append("A descendant operation failed without permission-denied evidence.")
        case .readable:
            break
        }
    }

    private func accessResult(for root: URL, fileManager: FileManager) -> ScopeAccessProbeResult {
        if let compatibilityReadabilityProvider {
            let state = compatibilityReadabilityProvider(root, fileManager)
            let detail = switch state {
            case .readable: "Compatibility access check succeeded."
            case .missing: "Compatibility access check reported a missing path."
            case .permissionDenied: "Compatibility access check reported permission denied."
            case .unknown: "Compatibility access check failed with an unknown result."
            }
            return ScopeAccessProbeResult(state: state, operation: .metadata, detail: detail)
        }
        return scopeAccessProbe?.probe(root) ?? ScopeAccessProbeResult(
            state: .unknown,
            operation: .metadata,
            detail: "Access check failed because no probe was configured."
        )
    }

    private func probeEvidenceMessage(prefix: String, result: ScopeAccessProbeResult) -> String {
        var components = ["\(prefix) during \(result.operation.rawValue)."]
        if let errorCode = result.errorCode {
            components.append("POSIX code \(errorCode).")
        }
        components.append(result.detail)
        return components.joined(separator: " ")
    }
}

private struct FrontierEntry {
    let url: URL
    let parentIndex: Int?
    let depth: Int
}

private struct FIFOFrontier {
    private var entries = [FrontierEntry]()
    private var nextIndex = 0

    var isEmpty: Bool { nextIndex >= entries.count }
    var remainingCount: Int { entries.count - nextIndex }

    mutating func append(_ entry: FrontierEntry) {
        entries.append(entry)
    }

    mutating func popFirst() -> FrontierEntry? {
        guard !isEmpty else { return nil }
        defer { nextIndex += 1 }
        return entries[nextIndex]
    }
}

private struct ScopeMetrics {
    let scope: ScanScope
    var measuredItemCount = 0
    var skippedItemCount = 0
    var deepestMeasuredLevel = 0
    var isMissing = false
    var isPermissionDenied = false
    var isUnknown = false
    var hasUnreadableDescendant = false
    var wasCancelled = false
    var evidence = [String]()
    var accessResult: ScopeAccessProbeResult?
}

private extension FileMeasurement {
    static let zero = FileMeasurement(logicalSize: 0, allocatedSize: 0, itemCount: 0)

    static func + (lhs: FileMeasurement, rhs: FileMeasurement) -> FileMeasurement {
        FileMeasurement(
            logicalSize: lhs.logicalSize + rhs.logicalSize,
            allocatedSize: lhs.allocatedSize + rhs.allocatedSize,
            itemCount: lhs.itemCount + rhs.itemCount
        )
    }
}

private let boundedResourceKeys: [URLResourceKey] = [
    .isDirectoryKey,
    .isSymbolicLinkKey,
    .isPackageKey,
    .fileSizeKey,
    .fileAllocatedSizeKey,
    .totalFileAllocatedSizeKey,
    .contentModificationDateKey,
    .isRegularFileKey
]
