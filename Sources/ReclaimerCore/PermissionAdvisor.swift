import Foundation

public enum ScopeReadability: Hashable, Sendable {
    case readable
    case missing
    case permissionDenied
    case unknown

    public static func classify(error: Error) -> ScopeReadability {
        if let code = normalizedPOSIXCode(in: error) {
            switch Int32(code) {
            case ENOENT, ENOTDIR:
                return .missing
            case EACCES, EPERM:
                return .permissionDenied
            default:
                return .unknown
            }
        }
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain {
            switch CocoaError.Code(rawValue: error.code) {
            case .fileNoSuchFile:
                return .missing
            default:
                return .unknown
            }
        }
        return .unknown
    }

    static func normalizedPOSIXCode(in error: Error) -> Int? {
        var current: NSError? = error as NSError
        for _ in 0..<8 {
            guard let candidate = current else { return nil }
            if candidate.domain == NSPOSIXErrorDomain {
                return candidate.code
            }
            current = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return nil
    }
}

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

    public var blockingUnavailableScopes: [ScopeAccessSummary] {
        scopeSummaries.filter { [.denied, .unknown].contains($0.permissionState) }
    }

    public var optionalUnavailableScopes: [ScopeAccessSummary] {
        scopeSummaries.filter { $0.permissionState == .missing }
    }

    public var needsFullDiskAccessReview: Bool {
        deniedCount > 0
    }

    public var coverageSummary: String {
        guard totalCount > 0 else {
            return "No configured scopes"
        }
        if deniedCount > 0 || unknownCount > 0 {
            var parts = ["\(readableCount) of \(totalCount) configured scopes readable"]
            if deniedCount > 0 {
                parts.append("\(deniedCount) \(plural("scope", deniedCount)) need access review")
            }
            if unknownCount > 0 {
                parts.append("\(unknownCount) \(plural("scope", unknownCount)) need a fresh check")
            }
            if missingCount > 0 {
                parts.append("\(missingCount) optional \(plural("root", missingCount)) not present")
            }
            return parts.joined(separator: "; ")
        }
        if missingCount > 0 {
            return "\(readableCount) readable; \(missingCount) optional \(plural("root", missingCount)) not present"
        }
        return "All \(readableCount) configured \(plural("scope", readableCount)) readable"
    }
}

private func plural(_ singular: String, _ count: Int) -> String {
    count == 1 ? singular : singular + "s"
}

public enum PermissionAdvisor {
    public static let fullDiskAccessSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

    public static func report(
        scopes: [ScanScope],
        now: Date = Date(),
        fileManager: FileManager = .default,
        probe: (any ScopeAccessProbing)? = nil
    ) -> PermissionAdvisorReport {
        let resolvedProbe = probe ?? FileManagerScopeAccessProbe(fileManager: fileManager)
        return report(scopeSummaries: scopeSummaries(scopes: scopes, probe: resolvedProbe), now: now)
    }

    public static func scopeReadability(at root: URL, fileManager: FileManager = .default) -> ScopeReadability {
        FileManagerScopeAccessProbe(fileManager: fileManager).probe(root).state
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
            "This advisory reports only the configured operation result; it cannot prove macOS Full Disk Access is enabled and does not claim that it is enabled.",
            "Readable scope coverage does not mean any item is safe to remove.",
            "Missing roots can be normal when a developer tool is not installed or has not created cache data.",
            "Changing macOS privacy settings is a user-controlled system action; Ryddi does not grant permissions automatically."
        ]
    }

    static func scopeSummaries(
        scopes: [ScanScope],
        probe: any ScopeAccessProbing
    ) -> [ScopeAccessSummary] {
        scopes.map { scope in
            let root = scope.root.standardizedFileURL
            let result = probe.probe(root)
            return scopeSummary(scope: scope, result: result)
        }
    }

    static func scopeSummary(scope: ScanScope, result: ScopeAccessProbeResult) -> ScopeAccessSummary {
        let permissionState: PermissionState
        let message: String
        switch result.state {
        case .missing:
            permissionState = .missing
            message = "Unavailable on this Mac: the configured operation found no path."
        case .permissionDenied:
            permissionState = .denied
            message = "Permission required: the configured operation was denied."
        case .unknown:
            permissionState = .unknown
            message = "Check failed: the configured operation did not produce conclusive access evidence."
        case .readable:
            permissionState = .readable
            message = "Access verified: the configured operation succeeded."
        }
        return ScopeAccessSummary(
            name: scope.name,
            path: scope.root.standardizedFileURL.path,
            permissionState: permissionState,
            message: message,
            operation: result.operation,
            errorCode: result.errorCode,
            detail: result.detail
        )
    }
}
