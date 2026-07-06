import Foundation

public struct ReclaimerRuleFile: Codable, Sendable {
    public let version: String
    public let rules: [ReclaimerRule]
}

public struct ReclaimerRule: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let category: String
    public let priority: Int
    public let safetyClass: SafetyClass
    public let actionKind: ActionKind
    public let match: RuleMatchSpec
    public let evidence: [String]
    public let conditions: [String]
    public let recovery: String?

    public init(
        id: String,
        title: String,
        category: String,
        priority: Int,
        safetyClass: SafetyClass,
        actionKind: ActionKind,
        match: RuleMatchSpec,
        evidence: [String],
        conditions: [String] = [],
        recovery: String? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.priority = priority
        self.safetyClass = safetyClass
        self.actionKind = actionKind
        self.match = match
        self.evidence = evidence
        self.conditions = conditions
        self.recovery = recovery
    }
}

public struct RuleMatchSpec: Codable, Hashable, Sendable {
    public let containsAny: [String]
    public let suffixAny: [String]
    public let basenameAny: [String]
    public let pathExtensionAny: [String]

    public init(
        containsAny: [String] = [],
        suffixAny: [String] = [],
        basenameAny: [String] = [],
        pathExtensionAny: [String] = []
    ) {
        self.containsAny = containsAny
        self.suffixAny = suffixAny
        self.basenameAny = basenameAny
        self.pathExtensionAny = pathExtensionAny
    }
}

public struct Classification: Hashable, Sendable {
    public let safetyClass: SafetyClass
    public let actionKind: ActionKind
    public let matches: [RuleMatch]
    public let evidence: [Evidence]
}

public final class RuleEngine: @unchecked Sendable {
    public let version: String
    public let rules: [ReclaimerRule]
    public let userRuleIDs: Set<String>

    public init(version: String, rules: [ReclaimerRule], userRuleIDs: Set<String> = []) {
        self.version = version
        self.userRuleIDs = userRuleIDs
        self.rules = rules.sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.id < rhs.id
            }
            return lhs.priority > rhs.priority
        }
    }

    public static func bundled() throws -> RuleEngine {
        let url = Bundle.module.url(forResource: "rules", withExtension: "json")
        guard let url else {
            return RuleEngine(version: "fallback-1", rules: BuiltInRules.fallback)
        }
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(ReclaimerRuleFile.self, from: data)
        return RuleEngine(version: file.version, rules: file.rules)
    }

    public static func bundled(includingUserRules: Bool, userRuleStore: UserRulePackStore = UserRulePackStore()) throws -> RuleEngine {
        let engine = try bundled()
        guard includingUserRules else {
            return engine
        }
        return try engine.includingUserRules(from: userRuleStore)
    }

    public func includingUserRules(from store: UserRulePackStore = UserRulePackStore()) throws -> RuleEngine {
        try includingUserRules(store.loadValidatedRules())
    }

    public func includingUserRules(_ userRules: [ReclaimerRule]) -> RuleEngine {
        let userIDs = Set(userRules.map(\.id))
        return RuleEngine(
            version: userRules.isEmpty ? version : "\(version)+user-rules",
            rules: rules + userRules,
            userRuleIDs: userRuleIDs.union(userIDs)
        )
    }

    public func classify(path: String, isDirectory: Bool, isSymbolicLink: Bool) -> Classification {
        var matches: [RuleMatch] = []
        for rule in rules where rule.matches(path: path) {
            matches.append(
                RuleMatch(
                    ruleID: rule.id,
                    title: rule.title,
                    category: rule.category,
                    safetyClass: rule.safetyClass,
                    actionKind: rule.actionKind,
                    evidence: rule.evidence,
                    conditions: rule.conditions,
                    recovery: rule.recovery
                )
            )
        }

        if isSymbolicLink {
            matches.insert(
                RuleMatch(
                    ruleID: "core.symlink-review",
                    title: "Symbolic link",
                    category: "Safety",
                    safetyClass: .reviewRequired,
                    actionKind: .reportOnly,
                    evidence: ["Symbolic links are not followed or removed automatically to avoid deleting an unexpected target."],
                    conditions: ["Review the link target manually before any action."]
                ),
                at: 0
            )
        }

        guard let primary = matches.first else {
            return Classification(
                safetyClass: .reviewRequired,
                actionKind: .reportOnly,
                matches: [],
                evidence: [Evidence(kind: "unmatched", message: "No cleanup rule matched this path; review required.")]
            )
        }
        let effectivePrimary = conservativePrimary(from: matches, initialPrimary: primary)

        let evidence = matches.flatMap { match in
            match.evidence.map { Evidence(kind: match.ruleID, message: $0) }
        }
        return Classification(
            safetyClass: effectivePrimary.safetyClass,
            actionKind: effectivePrimary.actionKind,
            matches: matches,
            evidence: evidence
        )
    }

    private func conservativePrimary(from matches: [RuleMatch], initialPrimary: RuleMatch) -> RuleMatch {
        guard !userRuleIDs.isEmpty else {
            return initialPrimary
        }

        let primaryIsUserRule = userRuleIDs.contains(initialPrimary.ruleID)
        if primaryIsUserRule {
            return matches
                .filter { !userRuleIDs.contains($0.ruleID) && $0.safetyClass.riskRank > initialPrimary.safetyClass.riskRank }
                .sorted(by: conservativeSort)
                .first ?? initialPrimary
        }

        return matches
            .filter { userRuleIDs.contains($0.ruleID) && $0.safetyClass.riskRank > initialPrimary.safetyClass.riskRank }
            .sorted(by: conservativeSort)
            .first ?? initialPrimary
    }

    private func conservativeSort(_ lhs: RuleMatch, _ rhs: RuleMatch) -> Bool {
        if lhs.safetyClass.riskRank == rhs.safetyClass.riskRank {
            return lhs.ruleID < rhs.ruleID
        }
        return lhs.safetyClass.riskRank > rhs.safetyClass.riskRank
    }
}

private extension ReclaimerRule {
    func matches(path: String) -> Bool {
        let normalized = (path as NSString).standardizingPath.lowercased()
        let basename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()

        if !match.containsAny.isEmpty, match.containsAny.contains(where: { normalized.contains($0.lowercased()) }) {
            return true
        }
        if !match.suffixAny.isEmpty, match.suffixAny.contains(where: { normalized.hasSuffix($0.lowercased()) }) {
            return true
        }
        if !match.basenameAny.isEmpty, match.basenameAny.contains(where: { basename == $0.lowercased() }) {
            return true
        }
        if !match.pathExtensionAny.isEmpty, match.pathExtensionAny.contains(where: { ext == $0.lowercased() }) {
            return true
        }
        return false
    }
}

private enum BuiltInRules {
    static let fallback: [ReclaimerRule] = [
        ReclaimerRule(
            id: "fallback.cache",
            title: "Regenerable cache",
            category: "Cache",
            priority: 10,
            safetyClass: .safeAfterCondition,
            actionKind: .deleteCache,
            match: RuleMatchSpec(containsAny: ["/library/caches/"]),
            evidence: ["macOS cache directories are intended for data that can be regenerated."],
            conditions: ["Skip files that are open by a running process."]
        )
    ]
}
