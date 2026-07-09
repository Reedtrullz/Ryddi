import Foundation

public enum PermissionCoverageLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case complete
    case degraded
    case blocked

    public var label: String {
        switch self {
        case .complete: "Complete"
        case .degraded: "Degraded"
        case .blocked: "Blocked"
        }
    }
}

public struct PermissionAdvisorReport: Codable, Hashable, Sendable {
    public let createdAt: Date
    public let coverageLevel: PermissionCoverageLevel
    public let readableCount: Int
    public let deniedCount: Int
    public let missingCount: Int
    public let unknownCount: Int
    public let totalCount: Int
    public let readableFraction: Double
    public let scopeSummaries: [ScopeAccessSummary]
    public let recommendedActions: [String]
    public let nonClaims: [String]
    public let fullDiskAccessSettingsURL: String

    public init(
        createdAt: Date = Date(),
        coverageLevel: PermissionCoverageLevel,
        readableCount: Int,
        deniedCount: Int,
        missingCount: Int,
        unknownCount: Int,
        totalCount: Int,
        readableFraction: Double,
        scopeSummaries: [ScopeAccessSummary],
        recommendedActions: [String],
        nonClaims: [String],
        fullDiskAccessSettingsURL: String = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    ) {
        self.createdAt = createdAt
        self.coverageLevel = coverageLevel
        self.readableCount = readableCount
        self.deniedCount = deniedCount
        self.missingCount = missingCount
        self.unknownCount = unknownCount
        self.totalCount = totalCount
        self.readableFraction = readableFraction
        self.scopeSummaries = scopeSummaries
        self.recommendedActions = recommendedActions
        self.nonClaims = nonClaims
        self.fullDiskAccessSettingsURL = fullDiskAccessSettingsURL
    }

    public var unavailableScopes: [ScopeAccessSummary] {
        scopeSummaries.filter { [.denied, .missing, .unknown].contains($0.permissionState) }
    }

    public var needsFullDiskAccessReview: Bool {
        deniedCount > 0
    }
}

public enum PermissionAdvisor {
    public static let fullDiskAccessSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

    public static func report(
        scopes: [ScanScope],
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> PermissionAdvisorReport {
        report(scopeSummaries: scopeSummaries(scopes: scopes, fileManager: fileManager), now: now)
    }

    public static func report(
        scopeSummaries: [ScopeAccessSummary],
        now: Date = Date()
    ) -> PermissionAdvisorReport {
        let readable = scopeSummaries.filter { $0.permissionState == .readable }.count
        let denied = scopeSummaries.filter { $0.permissionState == .denied }.count
        let missing = scopeSummaries.filter { $0.permissionState == .missing }.count
        let unknown = scopeSummaries.filter { $0.permissionState == .unknown }.count
        let total = scopeSummaries.count
        let fraction = total == 0 ? 0 : Double(readable) / Double(total)
        let level = coverageLevel(readable: readable, denied: denied, missing: missing, unknown: unknown, total: total)
        return PermissionAdvisorReport(
            createdAt: now,
            coverageLevel: level,
            readableCount: readable,
            deniedCount: denied,
            missingCount: missing,
            unknownCount: unknown,
            totalCount: total,
            readableFraction: fraction,
            scopeSummaries: scopeSummaries,
            recommendedActions: recommendedActions(level: level, denied: denied, missing: missing, unknown: unknown),
            nonClaims: nonClaims()
        )
    }

    private static func coverageLevel(
        readable: Int,
        denied: Int,
        missing: Int,
        unknown: Int,
        total: Int
    ) -> PermissionCoverageLevel {
        guard total > 0 else { return .blocked }
        if readable == total {
            return .complete
        }
        if readable == 0, denied > 0 {
            return .blocked
        }
        if readable == 0, missing + unknown == total {
            return .blocked
        }
        if denied == 0, unknown == 0, readable > 0 {
            return .complete
        }
        return .degraded
    }

    private static func recommendedActions(
        level: PermissionCoverageLevel,
        denied: Int,
        missing: Int,
        unknown: Int
    ) -> [String] {
        var actions: [String] = []
        if denied > 0 {
            actions.append("Grant Full Disk Access to Ryddi, then run a fresh scan to re-check restricted scopes.")
        }
        if missing > 0 {
            actions.append("Review missing roots as optional tool state; missing caches often mean that tool is not installed or has not created data yet.")
        }
        if unknown > 0 {
            actions.append("Run a scan to replace unknown scope states with current readable, denied, or missing evidence.")
        }
        if actions.isEmpty, level == .complete {
            actions.append("Coverage is complete for configured scopes. Continue with scan, review, dry run, and receipts before cleanup.")
        }
        if level == .blocked {
            actions.append("Do not treat this scan as complete until at least one intended scope is readable.")
        }
        return actions
    }

    private static func nonClaims() -> [String] {
        [
            "This advisory observes current path readability; it cannot prove macOS Full Disk Access is globally enabled.",
            "Readable scope coverage does not mean any item is safe to remove.",
            "Missing roots can be normal when a developer tool is not installed or has not created cache data.",
            "Changing macOS privacy settings is a user-controlled system action; Ryddi does not grant permissions automatically."
        ]
    }

    private static func scopeSummaries(scopes: [ScanScope], fileManager: FileManager) -> [ScopeAccessSummary] {
        scopes.map { scope in
            var isDirectory: ObjCBool = false
            let root = scope.root.standardizedFileURL
            let exists = fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory)
            if !exists {
                return ScopeAccessSummary(
                    name: scope.name,
                    path: root.path,
                    permissionState: .missing,
                    message: "Path is not present on this Mac."
                )
            }
            if !fileManager.isReadableFile(atPath: root.path) {
                return ScopeAccessSummary(
                    name: scope.name,
                    path: root.path,
                    permissionState: .denied,
                    message: "Path exists but is not readable with current permissions."
                )
            }
            return ScopeAccessSummary(
                name: scope.name,
                path: root.path,
                permissionState: .readable,
                message: isDirectory.boolValue ? "Directory is readable." : "File is readable."
            )
        }
    }
}
