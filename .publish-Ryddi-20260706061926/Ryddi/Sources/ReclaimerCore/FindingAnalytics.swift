import Foundation

public struct BucketSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let count: Int
    public let logicalSize: Int64
    public let allocatedSize: Int64

    public init(name: String, count: Int, logicalSize: Int64, allocatedSize: Int64) {
        self.name = name
        self.count = count
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
    }
}

public struct ScopeAccessSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let permissionState: PermissionState
    public let message: String

    public init(name: String, path: String, permissionState: PermissionState, message: String) {
        self.name = name
        self.path = path
        self.permissionState = permissionState
        self.message = message
    }
}

public struct DiskMapNode: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(group):\(name)" }
    public let group: String
    public let name: String
    public let allocatedSize: Int64
    public let logicalSize: Int64
    public let count: Int
    public let safetyClass: SafetyClass?
    public let actionKind: ActionKind?
    public let isReclaimable: Bool

    public init(
        group: String,
        name: String,
        allocatedSize: Int64,
        logicalSize: Int64,
        count: Int,
        safetyClass: SafetyClass?,
        actionKind: ActionKind?,
        isReclaimable: Bool
    ) {
        self.group = group
        self.name = name
        self.allocatedSize = allocatedSize
        self.logicalSize = logicalSize
        self.count = count
        self.safetyClass = safetyClass
        self.actionKind = actionKind
        self.isReclaimable = isReclaimable
    }
}

public struct OwnerStorageSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String { ownerName }
    public let ownerName: String
    public let count: Int
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let expectedAutoSafeBytes: Int64
    public let reviewBytes: Int64
    public let protectedBytes: Int64
    public let dominantCategory: String
    public let safetyClass: SafetyClass?
    public let actionKind: ActionKind?
    public let isReclaimable: Bool
    public let topPaths: [String]

    public init(
        ownerName: String,
        count: Int,
        logicalSize: Int64,
        allocatedSize: Int64,
        expectedAutoSafeBytes: Int64,
        reviewBytes: Int64,
        protectedBytes: Int64,
        dominantCategory: String,
        safetyClass: SafetyClass?,
        actionKind: ActionKind?,
        isReclaimable: Bool,
        topPaths: [String]
    ) {
        self.ownerName = ownerName
        self.count = count
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.expectedAutoSafeBytes = expectedAutoSafeBytes
        self.reviewBytes = reviewBytes
        self.protectedBytes = protectedBytes
        self.dominantCategory = dominantCategory
        self.safetyClass = safetyClass
        self.actionKind = actionKind
        self.isReclaimable = isReclaimable
        self.topPaths = topPaths
    }
}

public struct ScanOverview: Codable, Hashable, Sendable {
    public let generatedAt: Date
    public let findingCount: Int
    public let totalLogicalSize: Int64
    public let totalAllocatedSize: Int64
    public let expectedAutoSafeBytes: Int64
    public let reviewBytes: Int64
    public let protectedBytes: Int64
    public let safetySummaries: [BucketSummary]
    public let categorySummaries: [BucketSummary]
    public let scopeSizeSummaries: [BucketSummary]
    public let scopeSummaries: [ScopeAccessSummary]
    public let mapNodes: [DiskMapNode]
    public let ownerSummaries: [OwnerStorageSummary]
    public let topFindings: [Finding]
    public let accountingNotes: [String]

    public init(
        generatedAt: Date,
        findingCount: Int,
        totalLogicalSize: Int64,
        totalAllocatedSize: Int64,
        expectedAutoSafeBytes: Int64,
        reviewBytes: Int64,
        protectedBytes: Int64,
        safetySummaries: [BucketSummary],
        categorySummaries: [BucketSummary],
        scopeSizeSummaries: [BucketSummary],
        scopeSummaries: [ScopeAccessSummary],
        mapNodes: [DiskMapNode],
        ownerSummaries: [OwnerStorageSummary],
        topFindings: [Finding],
        accountingNotes: [String]
    ) {
        self.generatedAt = generatedAt
        self.findingCount = findingCount
        self.totalLogicalSize = totalLogicalSize
        self.totalAllocatedSize = totalAllocatedSize
        self.expectedAutoSafeBytes = expectedAutoSafeBytes
        self.reviewBytes = reviewBytes
        self.protectedBytes = protectedBytes
        self.safetySummaries = safetySummaries
        self.categorySummaries = categorySummaries
        self.scopeSizeSummaries = scopeSizeSummaries
        self.scopeSummaries = scopeSummaries
        self.mapNodes = mapNodes
        self.ownerSummaries = ownerSummaries
        self.topFindings = topFindings
        self.accountingNotes = accountingNotes
    }
}

public enum GrowthGroup: String, Codable, CaseIterable, Hashable, Sendable {
    case category
    case scope
    case safety

    public var label: String {
        switch self {
        case .category: "Category"
        case .scope: "Scope"
        case .safety: "Safety"
        }
    }
}

public struct ScanSnapshot: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let findingCount: Int
    public let totalLogicalSize: Int64
    public let totalAllocatedSize: Int64
    public let expectedAutoSafeBytes: Int64
    public let reviewBytes: Int64
    public let protectedBytes: Int64
    public let categorySummaries: [BucketSummary]
    public let safetySummaries: [BucketSummary]
    public let scopeBuckets: [BucketSummary]
    public let scopeSummaries: [ScopeAccessSummary]
    public let topFindingPaths: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date,
        findingCount: Int,
        totalLogicalSize: Int64,
        totalAllocatedSize: Int64,
        expectedAutoSafeBytes: Int64,
        reviewBytes: Int64,
        protectedBytes: Int64,
        categorySummaries: [BucketSummary],
        safetySummaries: [BucketSummary],
        scopeBuckets: [BucketSummary],
        scopeSummaries: [ScopeAccessSummary],
        topFindingPaths: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.findingCount = findingCount
        self.totalLogicalSize = totalLogicalSize
        self.totalAllocatedSize = totalAllocatedSize
        self.expectedAutoSafeBytes = expectedAutoSafeBytes
        self.reviewBytes = reviewBytes
        self.protectedBytes = protectedBytes
        self.categorySummaries = categorySummaries
        self.safetySummaries = safetySummaries
        self.scopeBuckets = scopeBuckets
        self.scopeSummaries = scopeSummaries
        self.topFindingPaths = topFindingPaths
    }
}

public struct BucketGrowthDelta: Codable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let previousAllocatedSize: Int64
    public let currentAllocatedSize: Int64
    public let deltaAllocatedSize: Int64
    public let previousCount: Int
    public let currentCount: Int

    public init(
        name: String,
        previousAllocatedSize: Int64,
        currentAllocatedSize: Int64,
        previousCount: Int,
        currentCount: Int
    ) {
        self.name = name
        self.previousAllocatedSize = previousAllocatedSize
        self.currentAllocatedSize = currentAllocatedSize
        self.deltaAllocatedSize = currentAllocatedSize - previousAllocatedSize
        self.previousCount = previousCount
        self.currentCount = currentCount
    }
}

public enum FindingAnalytics {
    public static func overview(
        findings: [Finding],
        scopes: [ScanScope],
        topLimit: Int = 20,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> ScanOverview {
        let accountingFindings = nonOverlappingFindings(findings)
        let totalLogical = accountingFindings.reduce(0) { $0 + $1.logicalSize }
        let totalAllocated = accountingFindings.reduce(0) { $0 + $1.allocatedSize }
        let autoSafe = accountingFindings
            .filter { $0.safetyClass == .autoSafe }
            .reduce(0) { $0 + $1.allocatedSize }
        let review = accountingFindings
            .filter { [.safeAfterCondition, .reviewRequired].contains($0.safetyClass) }
            .reduce(0) { $0 + $1.allocatedSize }
        let protected = accountingFindings
            .filter { [.preserveByDefault, .neverTouch].contains($0.safetyClass) }
            .reduce(0) { $0 + $1.allocatedSize }

        return ScanOverview(
            generatedAt: now,
            findingCount: findings.count,
            totalLogicalSize: totalLogical,
            totalAllocatedSize: totalAllocated,
            expectedAutoSafeBytes: autoSafe,
            reviewBytes: review,
            protectedBytes: protected,
            safetySummaries: bucket(accountingFindings, by: { $0.safetyClass.label }),
            categorySummaries: bucket(accountingFindings, by: { $0.primaryCategory }),
            scopeSizeSummaries: bucket(accountingFindings, by: { $0.scopeName }),
            scopeSummaries: scopeSummaries(scopes: scopes, fileManager: fileManager),
            mapNodes: mapNodes(from: accountingFindings),
            ownerSummaries: ownerSummaries(from: ownerAttributionFindings(findings)),
            topFindings: Array(findings.sorted(by: sortByAllocatedThenPath).prefix(topLimit)),
            accountingNotes: accountingNotes(logicalSize: totalLogical, allocatedSize: totalAllocated)
        )
    }

    public static func ownerSummaries(from findings: [Finding], limit: Int = 18) -> [OwnerStorageSummary] {
        let grouped = Dictionary(grouping: findings) { finding in
            ownerName(for: finding)
        }
        return grouped.map { ownerName, items in
            let allocated = items.reduce(0) { $0 + $1.allocatedSize }
            let logical = items.reduce(0) { $0 + $1.logicalSize }
            let autoSafe = items
                .filter { $0.safetyClass == .autoSafe }
                .reduce(0) { $0 + $1.allocatedSize }
            let review = items
                .filter { [.safeAfterCondition, .reviewRequired].contains($0.safetyClass) }
                .reduce(0) { $0 + $1.allocatedSize }
            let protected = items
                .filter { [.preserveByDefault, .neverTouch].contains($0.safetyClass) }
                .reduce(0) { $0 + $1.allocatedSize }
            let dominant = dominantFinding(in: items)
            let reclaimable = items.contains {
                $0.safetyClass == .autoSafe && [.deleteCache, .trash].contains($0.actionKind)
            }
            return OwnerStorageSummary(
                ownerName: ownerName,
                count: items.count,
                logicalSize: logical,
                allocatedSize: allocated,
                expectedAutoSafeBytes: autoSafe,
                reviewBytes: review,
                protectedBytes: protected,
                dominantCategory: dominantCategory(in: items),
                safetyClass: dominant?.safetyClass,
                actionKind: dominant?.actionKind,
                isReclaimable: reclaimable,
                topPaths: items.sorted(by: sortByAllocatedThenPath).prefix(3).map(\.path)
            )
        }
        .sorted {
            if $0.allocatedSize == $1.allocatedSize {
                return $0.ownerName < $1.ownerName
            }
            return $0.allocatedSize > $1.allocatedSize
        }
        .prefix(limit)
        .map { $0 }
    }

    public static func mapNodes(from findings: [Finding], limit: Int = 18) -> [DiskMapNode] {
        let grouped = Dictionary(grouping: findings) { finding in
            finding.primaryCategory
        }
        return grouped.map { category, items in
            let allocated = items.reduce(0) { $0 + $1.allocatedSize }
            let logical = items.reduce(0) { $0 + $1.logicalSize }
            let dominant = dominantFinding(in: items)
            let reclaimable = items.contains {
                $0.safetyClass == .autoSafe && [.deleteCache, .trash].contains($0.actionKind)
            }
            return DiskMapNode(
                group: "category",
                name: category,
                allocatedSize: allocated,
                logicalSize: logical,
                count: items.count,
                safetyClass: dominant?.safetyClass,
                actionKind: dominant?.actionKind,
                isReclaimable: reclaimable
            )
        }
        .sorted {
            if $0.allocatedSize == $1.allocatedSize {
                return $0.name < $1.name
            }
            return $0.allocatedSize > $1.allocatedSize
        }
        .prefix(limit)
        .map { $0 }
    }

    public static func snapshot(from overview: ScanOverview, id: String = UUID().uuidString) -> ScanSnapshot {
        ScanSnapshot(
            id: id,
            createdAt: overview.generatedAt,
            findingCount: overview.findingCount,
            totalLogicalSize: overview.totalLogicalSize,
            totalAllocatedSize: overview.totalAllocatedSize,
            expectedAutoSafeBytes: overview.expectedAutoSafeBytes,
            reviewBytes: overview.reviewBytes,
            protectedBytes: overview.protectedBytes,
            categorySummaries: overview.categorySummaries,
            safetySummaries: overview.safetySummaries,
            scopeBuckets: overview.scopeSizeSummaries,
            scopeSummaries: overview.scopeSummaries,
            topFindingPaths: overview.topFindings.map(\.path)
        )
    }

    public static func growthDeltas(
        previous: ScanSnapshot,
        current: ScanSnapshot,
        group: GrowthGroup = .category
    ) -> [BucketGrowthDelta] {
        let previousBuckets = buckets(in: previous, group: group)
        let currentBuckets = buckets(in: current, group: group)
        let names = Set(previousBuckets.map(\.name)).union(currentBuckets.map(\.name))
        return names.map { name in
            let previousBucket = previousBuckets.first { $0.name == name }
            let currentBucket = currentBuckets.first { $0.name == name }
            return BucketGrowthDelta(
                name: name,
                previousAllocatedSize: previousBucket?.allocatedSize ?? 0,
                currentAllocatedSize: currentBucket?.allocatedSize ?? 0,
                previousCount: previousBucket?.count ?? 0,
                currentCount: currentBucket?.count ?? 0
            )
        }
        .sorted {
            let leftMagnitude = abs($0.deltaAllocatedSize)
            let rightMagnitude = abs($1.deltaAllocatedSize)
            if leftMagnitude == rightMagnitude {
                return $0.name < $1.name
            }
            return leftMagnitude > rightMagnitude
        }
    }

    private static func buckets(in snapshot: ScanSnapshot, group: GrowthGroup) -> [BucketSummary] {
        switch group {
        case .category: snapshot.categorySummaries
        case .scope: snapshot.scopeBuckets
        case .safety: snapshot.safetySummaries
        }
    }

    private static func bucket(_ findings: [Finding], by key: (Finding) -> String) -> [BucketSummary] {
        let grouped = Dictionary(grouping: findings, by: key)
        return grouped.map { name, items in
            BucketSummary(
                name: name,
                count: items.count,
                logicalSize: items.reduce(0) { $0 + $1.logicalSize },
                allocatedSize: items.reduce(0) { $0 + $1.allocatedSize }
            )
        }
        .sorted {
            if $0.allocatedSize == $1.allocatedSize {
                return $0.name < $1.name
            }
            return $0.allocatedSize > $1.allocatedSize
        }
    }

    private static func scopeSummaries(scopes: [ScanScope], fileManager: FileManager) -> [ScopeAccessSummary] {
        scopes.map { scope in
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: scope.root.path, isDirectory: &isDirectory)
            if !exists {
                return ScopeAccessSummary(
                    name: scope.name,
                    path: scope.root.path,
                    permissionState: .missing,
                    message: "Path is not present on this Mac."
                )
            }
            if !fileManager.isReadableFile(atPath: scope.root.path) {
                return ScopeAccessSummary(
                    name: scope.name,
                    path: scope.root.path,
                    permissionState: .denied,
                    message: "Path exists but is not readable with current permissions. Full Disk Access may be needed for broader scans."
                )
            }
            return ScopeAccessSummary(
                name: scope.name,
                path: scope.root.path,
                permissionState: .readable,
                message: isDirectory.boolValue ? "Directory is readable." : "File is readable."
            )
        }
    }

    private static func ownerName(for finding: Finding) -> String {
        if let ownerHint = finding.ownerHint?.trimmingCharacters(in: .whitespacesAndNewlines), !ownerHint.isEmpty {
            return ownerHint
        }
        let category = finding.primaryCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !category.isEmpty && category != "Unknown" {
            return category
        }
        let scopeName = finding.scopeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !scopeName.isEmpty {
            return scopeName
        }
        return "Unknown"
    }

    private static func dominantFinding(in findings: [Finding]) -> Finding? {
        findings.sorted(by: sortByAllocatedThenPath).first
    }

    private static func dominantCategory(in findings: [Finding]) -> String {
        let categories = bucket(findings, by: { $0.primaryCategory })
        return categories.first?.name ?? "Unknown"
    }

    private static func accountingNotes(logicalSize: Int64, allocatedSize: Int64) -> [String] {
        var notes = [
            "Ryddi reports allocated size for reclaim estimates because APFS physical usage is closer to what can be freed than Finder-style logical size."
        ]
        if allocatedSize != logicalSize {
            notes.append("Logical and allocated totals differ; APFS clones, hard links, compression, sparse files, local snapshots, and purgeable storage can make free-space gains differ from item size.")
        }
        notes.append("VM/container disks and native tool stores are reported for review; Ryddi does not raw-delete them automatically.")
        return notes
    }

    private static func sortByAllocatedThenPath(_ lhs: Finding, _ rhs: Finding) -> Bool {
        if lhs.allocatedSize == rhs.allocatedSize {
            return lhs.path < rhs.path
        }
        return lhs.allocatedSize > rhs.allocatedSize
    }

    private static func nonOverlappingFindings(_ findings: [Finding]) -> [Finding] {
        let nonRoot = findings.filter { finding in
            !finding.evidence.contains { $0.kind == "scope" }
        }
        let candidates = nonRoot.isEmpty ? findings : nonRoot
        let ordered = candidates.sorted { lhs, rhs in
            let lhsDepth = URL(fileURLWithPath: lhs.path).standardizedFileURL.pathComponents.count
            let rhsDepth = URL(fileURLWithPath: rhs.path).standardizedFileURL.pathComponents.count
            if lhsDepth == rhsDepth {
                return lhs.path < rhs.path
            }
            return lhsDepth < rhsDepth
        }
        var selected: [Finding] = []
        var selectedPaths: [String] = []
        for finding in ordered {
            let path = URL(fileURLWithPath: finding.path).standardizedFileURL.path
            guard !selectedPaths.contains(where: { isDescendant(path, of: $0) }) else { continue }
            selected.append(finding)
            selectedPaths.append(path)
        }
        return selected
    }

    private static func ownerAttributionFindings(_ findings: [Finding]) -> [Finding] {
        let nonRoot = findings.filter { finding in
            !finding.evidence.contains { $0.kind == "scope" }
        }
        let candidates = nonRoot.isEmpty ? findings : nonRoot
        let ordered = candidates.sorted { lhs, rhs in
            let lhsDepth = URL(fileURLWithPath: lhs.path).standardizedFileURL.pathComponents.count
            let rhsDepth = URL(fileURLWithPath: rhs.path).standardizedFileURL.pathComponents.count
            if lhsDepth == rhsDepth {
                return lhs.path < rhs.path
            }
            return lhsDepth < rhsDepth
        }
        var selected: [Finding] = []
        var selectedPaths: [String] = []
        for finding in ordered {
            let path = URL(fileURLWithPath: finding.path).standardizedFileURL.path
            guard !selectedPaths.contains(where: { isDescendant(path, of: $0) }) else { continue }
            if !isOwnerAttributable(finding) && hasOwnerAttributableDescendant(of: path, in: candidates) {
                continue
            }
            selected.append(finding)
            selectedPaths.append(path)
        }
        return selected
    }

    private static func isOwnerAttributable(_ finding: Finding) -> Bool {
        if let ownerHint = finding.ownerHint?.trimmingCharacters(in: .whitespacesAndNewlines), !ownerHint.isEmpty {
            return true
        }
        return !finding.ruleMatches.isEmpty
    }

    private static func hasOwnerAttributableDescendant(of path: String, in findings: [Finding]) -> Bool {
        findings.contains { other in
            let otherPath = URL(fileURLWithPath: other.path).standardizedFileURL.path
            return isDescendant(otherPath, of: path) && isOwnerAttributable(other)
        }
    }

    private static func isDescendant(_ path: String, of ancestor: String) -> Bool {
        guard path != ancestor else { return false }
        let ancestorWithSlash = ancestor.hasSuffix("/") ? ancestor : ancestor + "/"
        return path.hasPrefix(ancestorWithSlash)
    }
}
