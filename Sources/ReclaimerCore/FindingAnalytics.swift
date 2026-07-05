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
    public let scopeSummaries: [ScopeAccessSummary]
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
        scopeSummaries: [ScopeAccessSummary],
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
        self.scopeSummaries = scopeSummaries
        self.topFindings = topFindings
        self.accountingNotes = accountingNotes
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
        let totalLogical = findings.reduce(0) { $0 + $1.logicalSize }
        let totalAllocated = findings.reduce(0) { $0 + $1.allocatedSize }
        let autoSafe = findings
            .filter { $0.safetyClass == .autoSafe }
            .reduce(0) { $0 + $1.allocatedSize }
        let review = findings
            .filter { [.safeAfterCondition, .reviewRequired].contains($0.safetyClass) }
            .reduce(0) { $0 + $1.allocatedSize }
        let protected = findings
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
            safetySummaries: bucket(findings, by: { $0.safetyClass.label }),
            categorySummaries: bucket(findings, by: { $0.primaryCategory }),
            scopeSummaries: scopeSummaries(scopes: scopes, fileManager: fileManager),
            topFindings: Array(findings.sorted(by: sortByAllocatedThenPath).prefix(topLimit)),
            accountingNotes: accountingNotes(logicalSize: totalLogical, allocatedSize: totalAllocated)
        )
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
}
