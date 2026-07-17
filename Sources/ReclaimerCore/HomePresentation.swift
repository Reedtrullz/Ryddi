import Foundation

public enum HomePrimaryAction: String, Codable, Hashable, Sendable {
    case scanMac
    case cancelScan
    case reviewSuggestions
    case reviewAccess
    case exploreLargestFiles
    case scanAgain
    case verifyCleanup
    case viewHistory
}

public enum HomeSuggestionKind: String, Codable, Hashable, Sendable {
    case safeMaintenance
    case quitAndCheckAgain
    case nativeMaintenance
    case reviewPersonalFiles
    case keepByDefault
    case protected
    case insufficientEvidence
}

public struct HomeSuggestion: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let kind: HomeSuggestionKind
    public let findingIDs: Set<String>
    public let title: String
    public let explanation: String
    public let consequence: String
    public let allocatedBytes: Int64
    public let estimatedReclaimBytes: Int64?
    public let requiresCurrentScan: Bool
}

public struct HomeSnapshot: Codable, Hashable, Sendable {
    public let primaryAction: HomePrimaryAction
    public let suggestions: [HomeSuggestion]
    public let hiddenSuggestionCount: Int
    public let map: GuidedMapSnapshot?
}

public struct HomePresentationInput: Sendable {
    public let isScanning: Bool
    public let map: GuidedMapSnapshot?
    public let findings: [Finding]
    public let hasPendingVerification: Bool
    public let accessIsLimited: Bool
    public let evidenceIsCurrent: Bool

    public init(
        isScanning: Bool,
        map: GuidedMapSnapshot?,
        findings: [Finding],
        hasPendingVerification: Bool,
        accessIsLimited: Bool,
        evidenceIsCurrent: Bool
    ) {
        self.isScanning = isScanning
        self.map = map
        self.findings = findings
        self.hasPendingVerification = hasPendingVerification
        self.accessIsLimited = accessIsLimited
        self.evidenceIsCurrent = evidenceIsCurrent
    }
}

public enum HomePresentationBuilder {
    public static func build(input: HomePresentationInput) -> HomeSnapshot {
        let allSuggestions = input.evidenceIsCurrent
            ? suggestions(from: input.findings)
            : []
        let visible = Array(allSuggestions.prefix(3))
        let action: HomePrimaryAction
        if input.isScanning {
            action = .cancelScan
        } else if input.hasPendingVerification {
            action = .verifyCleanup
        } else if input.map == nil {
            action = .scanMac
        } else if input.accessIsLimited && visible.isEmpty {
            action = .reviewAccess
        } else if !visible.isEmpty {
            action = .reviewSuggestions
        } else if input.evidenceIsCurrent {
            action = .exploreLargestFiles
        } else {
            action = .scanAgain
        }
        return HomeSnapshot(
            primaryAction: action,
            suggestions: visible,
            hiddenSuggestionCount: max(0, allSuggestions.count - visible.count),
            map: input.map
        )
    }

    private static func suggestions(from findings: [Finding]) -> [HomeSuggestion] {
        let grouped = Dictionary(grouping: findings, by: kind(for:))
        return grouped.compactMap { kind, values in
            guard let kind else { return nil }
            let ordered = values.sorted {
                if $0.allocatedSize == $1.allocatedSize { return $0.id < $1.id }
                return $0.allocatedSize > $1.allocatedSize
            }
            let bytes = ordered.reduce(Int64(0)) { partial, finding in
                let (sum, overflow) = partial.addingReportingOverflow(max(0, finding.allocatedSize))
                return overflow ? Int64.max : sum
            }
            return HomeSuggestion(
                id: "home-suggestion:\(kind.rawValue)",
                kind: kind,
                findingIDs: Set(ordered.map(\.id)),
                title: title(for: kind),
                explanation: explanation(for: kind),
                consequence: consequence(for: kind),
                allocatedBytes: bytes,
                estimatedReclaimBytes: kind == .safeMaintenance ? bytes : nil,
                requiresCurrentScan: true
            )
        }
        .sorted { lhs, rhs in
            let leftRank = rank(lhs.kind)
            let rightRank = rank(rhs.kind)
            if leftRank == rightRank {
                if lhs.estimatedReclaimBytes == rhs.estimatedReclaimBytes { return lhs.id < rhs.id }
                return (lhs.estimatedReclaimBytes ?? 0) > (rhs.estimatedReclaimBytes ?? 0)
            }
            return leftRank < rightRank
        }
    }

    private static func kind(for finding: Finding) -> HomeSuggestionKind? {
        if finding.safetyClass == .autoSafe,
           [.deleteCache, .trash].contains(finding.actionKind) {
            return .safeMaintenance
        }
        if finding.actionKind == .nativeToolCommand { return .nativeMaintenance }
        if finding.safetyClass == .safeAfterCondition { return .quitAndCheckAgain }
        if finding.safetyClass == .reviewRequired { return .reviewPersonalFiles }
        if finding.safetyClass == .preserveByDefault { return .keepByDefault }
        if finding.safetyClass == .neverTouch { return .protected }
        return nil
    }

    private static func rank(_ kind: HomeSuggestionKind) -> Int {
        switch kind {
        case .safeMaintenance: 0
        case .quitAndCheckAgain: 1
        case .nativeMaintenance: 2
        case .reviewPersonalFiles: 3
        case .keepByDefault: 4
        case .protected: 5
        case .insufficientEvidence: 6
        }
    }

    private static func title(for kind: HomeSuggestionKind) -> String {
        switch kind {
        case .safeMaintenance: "Safe maintenance"
        case .quitAndCheckAgain: "Quit app and check again"
        case .nativeMaintenance: "Use the app's maintenance tool"
        case .reviewPersonalFiles: "Review personal files"
        case .keepByDefault: "Keep by default"
        case .protected: "Protected"
        case .insufficientEvidence: "Not enough evidence"
        }
    }

    private static func explanation(for kind: HomeSuggestionKind) -> String {
        switch kind {
        case .safeMaintenance: "Recreatable items accepted by Ryddi's current safety rules."
        case .quitAndCheckAgain: "Current evidence requires a condition to change before cleanup."
        case .nativeMaintenance: "The owning app provides the safer maintenance path."
        case .reviewPersonalFiles: "Personal files need an item-by-item decision."
        case .keepByDefault: "Ryddi recommends keeping these items unless you understand their role."
        case .protected: "Ryddi will not include these items in cleanup."
        case .insufficientEvidence: "Ryddi cannot make a trustworthy recommendation yet."
        }
    }

    private static func consequence(for kind: HomeSuggestionKind) -> String {
        switch kind {
        case .safeMaintenance: "Review the exact items before Ryddi checks them safely."
        case .quitAndCheckAgain: "Quit the related app, then scan again."
        case .nativeMaintenance: "Ryddi will guide you to the native tool."
        case .reviewPersonalFiles: "Nothing happens until you choose individual files."
        case .keepByDefault, .protected: "No cleanup action is available."
        case .insufficientEvidence: "Review access or scan again."
        }
    }
}
