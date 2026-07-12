import Foundation

public struct TrashConfirmationItem: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let originalPath: String
    public let displayPath: String
    public let allocatedBytes: Int64
    public let conditions: [String]
}

public struct TrashConfirmationModel: Codable, Hashable, Sendable {
    public let items: [TrashConfirmationItem]
    public let pathStyle: ReportPathStyle
    public let nonClaims: [String]

    public var itemCount: Int { items.count }
    public var totalAllocatedBytes: Int64 { items.reduce(0) { $0 + $1.allocatedBytes } }

    public static func build(
        plan: ReclaimPlan,
        pathStyle: ReportPathStyle = .full,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> TrashConfirmationModel {
        let privacy = ReportPrivacyOptions(
            pathStyle: pathStyle,
            redactUserText: false,
            homeDirectory: homeDirectory
        )
        let items = plan.items
            .filter { $0.selected && $0.proposedAction == .trash }
            .map { item in
                TrashConfirmationItem(
                    id: item.id,
                    name: item.finding.displayName,
                    originalPath: item.finding.path,
                    displayPath: privacy.displayPath(item.finding.path),
                    allocatedBytes: item.finding.allocatedSize,
                    conditions: item.conditions.map(\.message)
                )
            }
        return TrashConfirmationModel(
            items: items,
            pathStyle: pathStyle,
            nonClaims: [
                "Moving items to Trash does not immediately increase free disk space.",
                "Final checks revalidate identity, rules, policy, age, symlinks, and open handles for every item.",
                "The final pathname check reduces replacement risk but is not an atomic filesystem guarantee.",
                "Ryddi does not empty Trash or silently restore items."
            ]
        )
    }
}
