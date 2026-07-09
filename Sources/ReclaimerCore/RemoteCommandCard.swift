import Foundation

public enum RemoteCommandCardKind: String, Codable, Hashable, Sendable {
    case inspect
    case dryRun
    case manualCleanup
    case preserveReview

    public var label: String {
        switch self {
        case .inspect:
            "Inspect"
        case .dryRun:
            "Dry run"
        case .manualCleanup:
            "Manual cleanup"
        case .preserveReview:
            "Preserve/review"
        }
    }
}

public struct RemoteManualCommandCard: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let kind: RemoteCommandCardKind
    public let displayCommand: String
    public let risk: SafetyClass
    public let explanation: String
    public let prerequisites: [String]
    public let nonClaims: [String]

    public init(
        id: String,
        title: String,
        kind: RemoteCommandCardKind,
        displayCommand: String,
        risk: SafetyClass,
        explanation: String,
        prerequisites: [String],
        nonClaims: [String]
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.displayCommand = displayCommand
        self.risk = risk
        self.explanation = explanation
        self.prerequisites = prerequisites
        self.nonClaims = nonClaims
    }
}

public enum RemoteCommandCardBuilder {
    public static let defaultNonClaims = [
        "Ryddi does not execute this command on remote targets.",
        "Some commands may require sudo; Ryddi does not collect or manage sudo passwords.",
        "Inspect service impact before changing logs, packages, containers, or deploy releases."
    ]

    public static func build(for findings: [RemoteStorageFinding]) -> [RemoteManualCommandCard] {
        var cards: [RemoteManualCommandCard] = []
        if containsBucket("journald", in: findings) {
            cards.append(card(
                id: "journald.disk-usage.inspect",
                title: "Inspect journal usage",
                kind: .inspect,
                command: "journalctl --disk-usage",
                risk: .reviewRequired,
                explanation: "Shows current systemd journal usage before choosing a retention policy.",
                prerequisites: ["Confirm the host uses systemd-journald."]
            ))
            cards.append(card(
                id: "journald.vacuum-time.manual",
                title: "Vacuum old journals manually",
                kind: .manualCleanup,
                command: "sudo journalctl --rotate && sudo journalctl --vacuum-time=14d",
                risk: .safeAfterCondition,
                explanation: "Rotates journals and removes archived entries older than the selected retention window.",
                prerequisites: ["Confirm log retention requirements.", "Review whether sudo is available for the operator."]
            ))
        }

        if containsBucket("apt cache", in: findings) {
            cards.append(card(
                id: "apt.autoremove.dry-run",
                title: "Preview package autoremove",
                kind: .dryRun,
                command: "sudo apt-get autoremove --dry-run",
                risk: .reviewRequired,
                explanation: "Lists packages apt would remove without changing the server.",
                prerequisites: ["Review the package list for service dependencies."]
            ))
            cards.append(card(
                id: "apt.clean.manual",
                title: "Clean downloaded package archives",
                kind: .manualCleanup,
                command: "sudo apt-get clean",
                risk: .safeAfterCondition,
                explanation: "Clears downloaded package archives from the apt cache.",
                prerequisites: ["Confirm package downloads are disposable.", "Review whether sudo is available for the operator."]
            ))
        }

        if findings.contains(where: { normalized($0.bucket).hasPrefix("docker") && !normalized($0.bucket).contains("volumes") }) {
            cards.append(card(
                id: "docker.system-df.inspect",
                title: "Inspect Docker storage",
                kind: .inspect,
                command: "docker system df -v",
                risk: .reviewRequired,
                explanation: "Shows Docker image, container, volume, and build-cache accounting before any prune decision.",
                prerequisites: ["Confirm the operator can read Docker inventory."]
            ))
            cards.append(card(
                id: "docker.system-prune.manual-review",
                title: "Review Docker system prune manually",
                kind: .manualCleanup,
                command: "docker system prune",
                risk: .safeAfterCondition,
                explanation: "Starts Docker's interactive prune flow for stopped containers, unused networks, dangling images, and build cache.",
                prerequisites: ["Inspect running services.", "Inspect images and containers to preserve.", "Do not include volumes unless separately reviewed."]
            ))
        }

        if findings.contains(where: { normalized($0.bucket).contains("docker volumes") }) {
            cards.append(card(
                id: "docker.volumes.inspect",
                title: "Inspect Docker volumes",
                kind: .preserveReview,
                command: "docker volume ls",
                risk: .preserveByDefault,
                explanation: "Lists volumes for manual ownership review; volumes can contain databases, uploads, and durable app state.",
                prerequisites: ["Map each volume to an application before considering any change."]
            ))
        }

        if containsBucket("old deploy releases", in: findings) {
            cards.append(card(
                id: "deploy.releases.inspect",
                title: "Inspect deploy release directories",
                kind: .inspect,
                command: "find /opt /srv /var/www -maxdepth 4 -type d -name releases -print 2>/dev/null",
                risk: .reviewRequired,
                explanation: "Finds release directories for manual rollback-policy review without deleting anything.",
                prerequisites: ["Confirm the deploy tool and rollback policy before archiving old releases."]
            ))
        }

        return deduplicate(cards)
    }

    private static func card(
        id: String,
        title: String,
        kind: RemoteCommandCardKind,
        command: String,
        risk: SafetyClass,
        explanation: String,
        prerequisites: [String]
    ) -> RemoteManualCommandCard {
        RemoteManualCommandCard(
            id: id,
            title: title,
            kind: kind,
            displayCommand: command,
            risk: risk,
            explanation: explanation,
            prerequisites: prerequisites,
            nonClaims: defaultNonClaims
        )
    }

    private static func containsBucket(_ needle: String, in findings: [RemoteStorageFinding]) -> Bool {
        let target = normalized(needle)
        return findings.contains { normalized($0.bucket).contains(target) }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func deduplicate(_ cards: [RemoteManualCommandCard]) -> [RemoteManualCommandCard] {
        var seen = Set<String>()
        return cards.filter { seen.insert($0.id).inserted }
    }
}
