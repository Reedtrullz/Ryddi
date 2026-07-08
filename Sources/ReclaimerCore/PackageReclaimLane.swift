import Foundation

public struct PackageReclaimLaneReport: Codable, Hashable, Sendable {
    public let generatedAt: Date
    public let managerReports: [PackageReclaimManagerReport]
    public let totalPreviewBytes: Int64
    public let nonClaims: [String]

    public init(
        generatedAt: Date = Date(),
        managerReports: [PackageReclaimManagerReport],
        totalPreviewBytes: Int64,
        nonClaims: [String]
    ) {
        self.generatedAt = generatedAt
        self.managerReports = managerReports
        self.totalPreviewBytes = totalPreviewBytes
        self.nonClaims = nonClaims
    }
}

public struct PackageReclaimManagerReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let managerName: String
    public let cacheBytes: Int64
    public let previewCommand: [String]
    public let cleanupCommand: [String]
    public let previewOnly: Bool
    public let explanation: String

    public init(
        id: String,
        managerName: String,
        cacheBytes: Int64,
        previewCommand: [String],
        cleanupCommand: [String],
        previewOnly: Bool = true,
        explanation: String
    ) {
        self.id = id
        self.managerName = managerName
        self.cacheBytes = cacheBytes
        self.previewCommand = previewCommand
        self.cleanupCommand = cleanupCommand
        self.previewOnly = previewOnly
        self.explanation = explanation
    }
}

public enum PackageReclaimLaneBuilder {
    public static func build(from report: PackageCacheReviewReport, generatedAt: Date = Date()) -> PackageReclaimLaneReport {
        let managers = report.managerSummaries
            .sorted { lhs, rhs in
                if lhs.allocatedSize == rhs.allocatedSize {
                    return lhs.name < rhs.name
                }
                return lhs.allocatedSize > rhs.allocatedSize
            }
            .map(managerReport)

        return PackageReclaimLaneReport(
            generatedAt: generatedAt,
            managerReports: managers,
            totalPreviewBytes: managers
                .filter { !$0.previewCommand.isEmpty }
                .reduce(Int64(0)) { $0 + $1.cacheBytes },
            nonClaims: [
                "No package cache cleanup was executed.",
                "Native tools may report different reclaim after their own accounting.",
                "Preview and cleanup commands must be reviewed before use.",
                "Protected package-manager config, auth, registry, token, and project behavior files remain out of scope."
            ]
        )
    }

    private static func managerReport(for summary: PackageCacheSummary) -> PackageReclaimManagerReport {
        let commands = commands(for: summary.name)
        return PackageReclaimManagerReport(
            id: managerID(summary.name),
            managerName: summary.name,
            cacheBytes: summary.allocatedSize,
            previewCommand: commands.preview,
            cleanupCommand: commands.cleanup,
            explanation: explanation(managerName: summary.name, commands: commands)
        )
    }

    private static func commands(for manager: String) -> (preview: [String], cleanup: [String]) {
        switch normalizedManager(manager) {
        case "homebrew", "brew":
            return (["brew", "cleanup", "--dry-run"], ["brew", "cleanup"])
        case "npm":
            return (["npm", "cache", "verify"], ["npm", "cache", "clean", "--force"])
        case "pnpm":
            return (["pnpm", "store", "status"], ["pnpm", "store", "prune"])
        case "yarn":
            return (["yarn", "cache", "dir"], ["yarn", "cache", "clean"])
        case "pip":
            return (["pip", "cache", "info"], ["pip", "cache", "purge"])
        case "go":
            return (["go", "env", "GOMODCACHE"], ["go", "clean", "-modcache"])
        case "cocoapods":
            return (["pod", "cache", "list"], ["pod", "cache", "clean", "--all"])
        default:
            return ([], [])
        }
    }

    private static func explanation(managerName: String, commands: (preview: [String], cleanup: [String])) -> String {
        if commands.preview.isEmpty {
            return "\(managerName) does not have an allowlisted preview lane yet; review the package cache report manually."
        }
        if commands.cleanup.isEmpty {
            return "\(managerName) has allowlisted evidence commands, but no cleanup command is suggested by this lane."
        }
        return "\(managerName) has an allowlisted native preview path. Ryddi reports the command but does not execute cleanup."
    }

    private static func managerID(_ manager: String) -> String {
        normalizedManager(manager)
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "_", with: "-")
    }

    private static func normalizedManager(_ manager: String) -> String {
        manager
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
    }
}
