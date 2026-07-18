import Foundation

public struct CloudOrganizationPolicy: Hashable, Sendable {
    public let largeFileBytes: Int64
    public let staleAge: TimeInterval

    public init(
        largeFileBytes: Int64 = 1_000_000_000,
        staleAge: TimeInterval = 365 * 24 * 60 * 60
    ) {
        self.largeFileBytes = max(1, largeFileBytes)
        self.staleAge = max(1, staleAge)
    }
}

public struct CloudDuplicateGroup: Identifiable, Sendable {
    public let id: String
    public let provider: CloudProviderKind
    public let logicalBytesPerObject: Int64
    public let objects: [CloudObjectReference]

    public var potentialDuplicateBytes: Int64 {
        logicalBytesPerObject * Int64(max(0, objects.count - 1))
    }
}

public struct CloudOrganizationReport: Sendable {
    public let provider: CloudProviderKind
    public let inventoryCompletion: CloudInventoryCompletion
    public let duplicateGroups: [CloudDuplicateGroup]
    public let largeObjects: [CloudObjectReference]
    public let staleObjects: [CloudObjectReference]
    public let unknownDateCount: Int
    public let nonClaims: [String]
}

public enum CloudOrganizationBuilder {
    public static func build(
        inventory: CloudInventoryReport,
        policy: CloudOrganizationPolicy = CloudOrganizationPolicy(),
        now: Date = Date()
    ) -> CloudOrganizationReport {
        let files = inventory.objects.filter {
            $0.provider == inventory.provider && $0.objectKind == .file
        }
        let large = files
            .filter { ($0.logicalBytes ?? 0) >= policy.largeFileBytes }
            .sorted(by: objectSort)
        let cutoff = now.addingTimeInterval(-policy.staleAge)
        let stale = files
            .filter { object in
                guard let modifiedAt = object.modifiedAt else { return false }
                return modifiedAt <= cutoff
            }
            .sorted(by: objectSort)

        var duplicateBuckets: [String: [CloudObjectReference]] = [:]
        for object in files {
            guard let hash = object.providerHash?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !hash.isEmpty,
                  let hashKind = object.providerHashKind,
                  hashKind.provesDuplicateContent,
                  let bytes = object.logicalBytes,
                  bytes > 0 else { continue }
            duplicateBuckets["\(inventory.provider.rawValue):\(hashKind.rawValue):\(bytes):\(hash)", default: []].append(object)
        }
        let duplicates = duplicateBuckets.compactMap { key, objects -> CloudDuplicateGroup? in
            let uniqueObjects = Dictionary(grouping: objects, by: \.id).compactMap(\.value.first)
            guard uniqueObjects.count > 1, let bytes = uniqueObjects.first?.logicalBytes else { return nil }
            return CloudDuplicateGroup(
                id: key,
                provider: inventory.provider,
                logicalBytesPerObject: bytes,
                objects: uniqueObjects.sorted(by: objectSort)
            )
        }
        .sorted {
            if $0.potentialDuplicateBytes != $1.potentialDuplicateBytes {
                return $0.potentialDuplicateBytes > $1.potentialDuplicateBytes
            }
            return $0.id < $1.id
        }

        var nonClaims = [
            "Organization findings are review queues, not move or deletion instructions.",
            "Duplicate groups require a provider hash and exact byte size; matching names or sizes alone are never duplicate proof.",
            "Cloud logical bytes are not an estimate of local disk space that will be reclaimed.",
            "Ryddi does not move, rename, overwrite, deduplicate, or delete provider objects from this report."
        ]
        if !inventory.isComplete {
            nonClaims.append("The provider inventory is incomplete; rankings and duplicate groups may omit objects.")
        }
        return CloudOrganizationReport(
            provider: inventory.provider,
            inventoryCompletion: inventory.completion,
            duplicateGroups: duplicates,
            largeObjects: large,
            staleObjects: stale,
            unknownDateCount: files.filter { $0.modifiedAt == nil }.count,
            nonClaims: nonClaims
        )
    }

    private static func objectSort(_ lhs: CloudObjectReference, _ rhs: CloudObjectReference) -> Bool {
        if (lhs.logicalBytes ?? 0) != (rhs.logicalBytes ?? 0) {
            return (lhs.logicalBytes ?? 0) > (rhs.logicalBytes ?? 0)
        }
        return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }
}
