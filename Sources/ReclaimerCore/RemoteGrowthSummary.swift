import Foundation

public struct RemoteBucketGrowth: Codable, Hashable, Identifiable, Sendable {
    public var id: String { bucket }
    public let bucket: String
    public let previousBytes: Int64?
    public let currentBytes: Int64?
    public let deltaBytes: Int64?

    public init(bucket: String, previousBytes: Int64?, currentBytes: Int64?, deltaBytes: Int64?) {
        self.bucket = bucket
        self.previousBytes = previousBytes
        self.currentBytes = currentBytes
        self.deltaBytes = deltaBytes
    }
}

public struct RemoteGrowthSummary: Codable, Hashable, Sendable {
    public let targetID: String
    public let previousScanID: String?
    public let currentScanID: String
    public let changedBuckets: [RemoteBucketGrowth]
    public let unavailableReason: String?

    public init(
        targetID: String,
        previousScanID: String?,
        currentScanID: String,
        changedBuckets: [RemoteBucketGrowth],
        unavailableReason: String?
    ) {
        self.targetID = targetID
        self.previousScanID = previousScanID
        self.currentScanID = currentScanID
        self.changedBuckets = changedBuckets
        self.unavailableReason = unavailableReason
    }
}

public enum RemoteGrowthSummaryBuilder {
    public static func build(previous: RemoteScanReport?, current: RemoteScanReport) -> RemoteGrowthSummary {
        guard let previous else {
            return RemoteGrowthSummary(
                targetID: current.target.id,
                previousScanID: nil,
                currentScanID: current.id,
                changedBuckets: [],
                unavailableReason: "No previous remote scan is available for this target identity."
            )
        }

        if let reason = comparabilityFailure(previous: previous.target, current: current.target) {
            return RemoteGrowthSummary(
                targetID: current.target.id,
                previousScanID: previous.id,
                currentScanID: current.id,
                changedBuckets: [],
                unavailableReason: reason
            )
        }

        let previousBuckets = bucketTotals(for: previous)
        let currentBuckets = bucketTotals(for: current)
        let changedBuckets = Set(previousBuckets.keys).union(currentBuckets.keys)
            .compactMap { bucket -> RemoteBucketGrowth? in
                let previousBytes = previousBuckets[bucket] ?? nil
                let currentBytes = currentBuckets[bucket] ?? nil
                guard previousBytes != currentBytes else { return nil }
                let delta = if let previousBytes, let currentBytes {
                    currentBytes - previousBytes
                } else {
                    Optional<Int64>.none
                }
                return RemoteBucketGrowth(
                    bucket: bucket,
                    previousBytes: previousBytes,
                    currentBytes: currentBytes,
                    deltaBytes: delta
                )
            }
            .sorted {
                let lhsMagnitude = abs($0.deltaBytes ?? (($0.currentBytes ?? 0) - ($0.previousBytes ?? 0)))
                let rhsMagnitude = abs($1.deltaBytes ?? (($1.currentBytes ?? 0) - ($1.previousBytes ?? 0)))
                if lhsMagnitude == rhsMagnitude {
                    return $0.bucket < $1.bucket
                }
                return lhsMagnitude > rhsMagnitude
            }

        return RemoteGrowthSummary(
            targetID: current.target.id,
            previousScanID: previous.id,
            currentScanID: current.id,
            changedBuckets: changedBuckets,
            unavailableReason: nil
        )
    }

    private static func comparabilityFailure(previous: RemoteTargetReference, current: RemoteTargetReference) -> String? {
        let warnings = RemoteTargetContinuity.warnings(previous: previous, current: current)
        if !warnings.isEmpty {
            let fields = warnings.map(\.field).joined(separator: ", ")
            return "Target identity changed between scans (\(fields)); growth summary is unavailable."
        }

        if !hasConcreteIdentity(previous), !hasConcreteIdentity(current), previous.id != current.id {
            return "Remote target aliases are unresolved and differ; growth summary is unavailable."
        }

        return nil
    }

    private static func hasConcreteIdentity(_ target: RemoteTargetReference) -> Bool {
        target.resolvedHost != nil || target.fingerprint != nil
    }

    private static func bucketTotals(for report: RemoteScanReport) -> [String: Int64?] {
        var totals: [String: Int64?] = [
            "Disk filesystems": total(report.diskFilesystems.map(\.usedBytes)),
            "Inode filesystems": total(report.inodeFilesystems.map(\.usedBytes))
        ]

        let findingBuckets = Dictionary(grouping: report.findings, by: \.bucket)
        for (bucket, findings) in findingBuckets {
            totals[bucket] = total(findings.map(\.allocatedBytes))
        }

        return totals.filter { $0.value != nil }
    }

    private static func total(_ values: [Int64?]) -> Int64? {
        let present = values.compactMap { $0 }
        guard !present.isEmpty else { return nil }
        return present.reduce(0, +)
    }
}
