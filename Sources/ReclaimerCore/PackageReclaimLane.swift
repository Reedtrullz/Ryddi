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

public enum PackageReclaimCommandRole: String, Codable, Hashable, Sendable {
    case inspect
    case dryRun
    case cleanup
}

public enum PackageReclaimCommandReview: String, Codable, Hashable, Sendable {
    case automaticSafeAction
    case manualReview
}

public enum PackageReclaimDryRunSupport: String, Codable, Hashable, Sendable {
    case supported
    case unsupported
    case versionDependent
    case notNeeded
}

public struct PackageReclaimCommandCard: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let argv: [String]
    public let role: PackageReclaimCommandRole
    public let review: PackageReclaimCommandReview
    public let dryRunSupport: PackageReclaimDryRunSupport
    public let note: String

    public init(
        id: String,
        title: String,
        argv: [String],
        role: PackageReclaimCommandRole,
        review: PackageReclaimCommandReview,
        dryRunSupport: PackageReclaimDryRunSupport,
        note: String
    ) {
        self.id = id
        self.title = title
        self.argv = argv
        self.role = role
        self.review = review
        self.dryRunSupport = dryRunSupport
        self.note = note
    }
}

public struct PackageReclaimManagerReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let managerName: String
    public let cacheBytes: Int64
    public let previewCommand: [String]
    public let cleanupCommand: [String]
    public let commandCards: [PackageReclaimCommandCard]
    public let previewOnly: Bool
    public let explanation: String

    public init(
        id: String,
        managerName: String,
        cacheBytes: Int64,
        previewCommand: [String],
        cleanupCommand: [String],
        commandCards: [PackageReclaimCommandCard] = [],
        previewOnly: Bool = true,
        explanation: String
    ) {
        self.id = id
        self.managerName = managerName
        self.cacheBytes = cacheBytes
        self.previewCommand = previewCommand
        self.cleanupCommand = cleanupCommand
        self.commandCards = commandCards
        self.previewOnly = previewOnly
        self.explanation = explanation
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case managerName
        case cacheBytes
        case previewCommand
        case cleanupCommand
        case commandCards
        case previewOnly
        case explanation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.managerName = try container.decode(String.self, forKey: .managerName)
        self.cacheBytes = try container.decode(Int64.self, forKey: .cacheBytes)
        self.previewCommand = try container.decodeIfPresent([String].self, forKey: .previewCommand) ?? []
        self.cleanupCommand = try container.decodeIfPresent([String].self, forKey: .cleanupCommand) ?? []
        self.commandCards = try container.decodeIfPresent([PackageReclaimCommandCard].self, forKey: .commandCards) ?? []
        self.previewOnly = try container.decodeIfPresent(Bool.self, forKey: .previewOnly) ?? true
        self.explanation = try container.decodeIfPresent(String.self, forKey: .explanation) ?? ""
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
        let cards = commandCards(for: summary.name)
        return PackageReclaimManagerReport(
            id: managerID(summary.name),
            managerName: summary.name,
            cacheBytes: summary.allocatedSize,
            previewCommand: commands.preview,
            cleanupCommand: commands.cleanup,
            commandCards: cards,
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

    private static func commandCards(for manager: String) -> [PackageReclaimCommandCard] {
        switch normalizedManager(manager) {
        case "homebrew", "brew":
            return [
                card("homebrew.cleanup-dry-run", "Preview cleanup", ["brew", "cleanup", "--dry-run"], .dryRun, .automaticSafeAction, .supported, "Homebrew can produce a cleanup preview through Ryddi's native action lane."),
                card("homebrew.cleanup", "Cleanup after review", ["brew", "cleanup"], .cleanup, .automaticSafeAction, .supported, "Ryddi can run this only through the Homebrew native action receipt flow with explicit confirmation.")
            ]
        case "npm":
            return [
                card("npm.verify", "Verify cache", ["npm", "cache", "verify"], .inspect, .manualReview, .notNeeded, "Integrity check and cache accounting; no cleanup is executed by Ryddi."),
                card("npm.clean", "Clean cache manually", ["npm", "cache", "clean", "--force"], .cleanup, .manualReview, .unsupported, "npm cache clean has no safe dry-run lane here, so keep it manual-review.")
            ]
        case "pnpm":
            return [
                card("pnpm.status", "Inspect store", ["pnpm", "store", "status"], .inspect, .manualReview, .notNeeded, "Reports modified packages before any manual prune."),
                card("pnpm.prune", "Prune store manually", ["pnpm", "store", "prune"], .cleanup, .manualReview, .unsupported, "pnpm store prune does not provide a Ryddi-executed dry run in this release.")
            ]
        case "yarn":
            return [
                card("yarn.clean-dry-run", "Preview clean when supported", ["yarn", "cache", "clean", "--dry-run"], .dryRun, .manualReview, .versionDependent, "Some Yarn versions support a dry-run flag; confirm your installed Yarn behavior before cleanup."),
                card("yarn.clean", "Clean cache manually", ["yarn", "cache", "clean"], .cleanup, .manualReview, .unsupported, "Yarn cache cleanup remains manual-review unless a version-specific dry run is confirmed.")
            ]
        default:
            let commands = commands(for: manager)
            if commands.preview.isEmpty, commands.cleanup.isEmpty {
                return []
            }
            var cards: [PackageReclaimCommandCard] = []
            if !commands.preview.isEmpty {
                cards.append(card("\(managerID(manager)).inspect", "Inspect cache", commands.preview, .inspect, .manualReview, .notNeeded, "Review this package-manager evidence command manually."))
            }
            if !commands.cleanup.isEmpty {
                cards.append(card("\(managerID(manager)).cleanup", "Cleanup manually", commands.cleanup, .cleanup, .manualReview, .unsupported, "No Ryddi-executed dry-run lane is implemented for this cleanup command."))
            }
            return cards
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

    private static func card(
        _ id: String,
        _ title: String,
        _ argv: [String],
        _ role: PackageReclaimCommandRole,
        _ review: PackageReclaimCommandReview,
        _ dryRunSupport: PackageReclaimDryRunSupport,
        _ note: String
    ) -> PackageReclaimCommandCard {
        PackageReclaimCommandCard(
            id: id,
            title: title,
            argv: argv,
            role: role,
            review: review,
            dryRunSupport: dryRunSupport,
            note: note
        )
    }
}
