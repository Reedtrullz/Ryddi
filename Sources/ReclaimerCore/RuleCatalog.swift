import Foundation

public struct RuleCatalogBucket: Codable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

public struct RuleCatalogEntry: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let category: String
    public let priority: Int
    public let safetyClass: SafetyClass
    public let actionKind: ActionKind
    public let matchHints: [String]
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
        matchHints: [String],
        evidence: [String],
        conditions: [String],
        recovery: String?
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.priority = priority
        self.safetyClass = safetyClass
        self.actionKind = actionKind
        self.matchHints = matchHints
        self.evidence = evidence
        self.conditions = conditions
        self.recovery = recovery
    }
}

public struct RuleCatalogSection: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let safetyClass: SafetyClass
    public let guidance: String
    public let rules: [RuleCatalogEntry]

    public init(
        id: String,
        title: String,
        safetyClass: SafetyClass,
        guidance: String,
        rules: [RuleCatalogEntry]
    ) {
        self.id = id
        self.title = title
        self.safetyClass = safetyClass
        self.guidance = guidance
        self.rules = rules
    }
}

public struct RuleCatalogReport: Codable, Hashable, Sendable {
    public let generatedAt: Date
    public let ruleVersion: String
    public let ruleCount: Int
    public let safetySummaries: [RuleCatalogBucket]
    public let actionSummaries: [RuleCatalogBucket]
    public let categorySummaries: [RuleCatalogBucket]
    public let sections: [RuleCatalogSection]
    public let nonClaims: [String]

    public init(
        generatedAt: Date,
        ruleVersion: String,
        ruleCount: Int,
        safetySummaries: [RuleCatalogBucket],
        actionSummaries: [RuleCatalogBucket],
        categorySummaries: [RuleCatalogBucket],
        sections: [RuleCatalogSection],
        nonClaims: [String]
    ) {
        self.generatedAt = generatedAt
        self.ruleVersion = ruleVersion
        self.ruleCount = ruleCount
        self.safetySummaries = safetySummaries
        self.actionSummaries = actionSummaries
        self.categorySummaries = categorySummaries
        self.sections = sections
        self.nonClaims = nonClaims
    }
}

public extension RuleEngine {
    func catalog(generatedAt: Date = Date()) -> RuleCatalogReport {
        let entries = rules.map(RuleCatalogEntry.init(rule:))
        return RuleCatalogReport(
            generatedAt: generatedAt,
            ruleVersion: version,
            ruleCount: entries.count,
            safetySummaries: buckets(entries, by: { $0.safetyClass.label }),
            actionSummaries: buckets(entries, by: { $0.actionKind.label }),
            categorySummaries: buckets(entries, by: { $0.category }),
            sections: SafetyClass.allCases.map { safetyClass in
                RuleCatalogSection(
                    id: safetyClass.rawValue,
                    title: sectionTitle(for: safetyClass),
                    safetyClass: safetyClass,
                    guidance: sectionGuidance(for: safetyClass),
                    rules: entries.filter { $0.safetyClass == safetyClass }
                )
            },
            nonClaims: [
                "The rule catalog explains bundled classification rules; it does not scan files or execute cleanup.",
                "A matching rule is not cleanup permission. Plans, conditions, open-file checks, user policy, and confirmation still apply.",
                "Never-touch and preserve-by-default rules are guardrails; removing matching data manually can still break apps or lose history."
            ]
        )
    }

    private func buckets(_ entries: [RuleCatalogEntry], by key: (RuleCatalogEntry) -> String) -> [RuleCatalogBucket] {
        let grouped = Dictionary(grouping: entries, by: key)
        return grouped.map { name, items in
            RuleCatalogBucket(name: name, count: items.count)
        }
        .sorted {
            if $0.count == $1.count {
                return $0.name < $1.name
            }
            return $0.count > $1.count
        }
    }

    private func sectionTitle(for safetyClass: SafetyClass) -> String {
        switch safetyClass {
        case .autoSafe: "Allowed For Safe Maintenance"
        case .safeAfterCondition: "Safe After Condition"
        case .reviewRequired: "Manual Review"
        case .preserveByDefault: "Preserve By Default"
        case .neverTouch: "Never Touch"
        }
    }

    private func sectionGuidance(for safetyClass: SafetyClass) -> String {
        switch safetyClass {
        case .autoSafe: "Rebuildable cache/temp data that can be proposed for cleanup after plan and open-file checks."
        case .safeAfterCondition: "Likely recoverable data that needs a condition such as app quit, age, retention, or native-tool review."
        case .reviewRequired: "Useful signal only. Ryddi should explain it and leave the decision to the user."
        case .preserveByDefault: "Potentially valuable history, profiles, assets, archives, or app state. Keep unless the user reviews it."
        case .neverTouch: "Credentials, configs, app bundles, active state, or other data Ryddi should not remove automatically."
        }
    }
}

private extension RuleCatalogEntry {
    init(rule: ReclaimerRule) {
        self.init(
            id: rule.id,
            title: rule.title,
            category: rule.category,
            priority: rule.priority,
            safetyClass: rule.safetyClass,
            actionKind: rule.actionKind,
            matchHints: rule.match.catalogHints,
            evidence: rule.evidence,
            conditions: rule.conditions,
            recovery: rule.recovery
        )
    }
}

private extension RuleMatchSpec {
    var catalogHints: [String] {
        var hints: [String] = []
        hints += containsAny.map { "contains: \($0)" }
        hints += suffixAny.map { "suffix: \($0)" }
        hints += basenameAny.map { "basename: \($0)" }
        hints += pathExtensionAny.map { "extension: \($0)" }
        return hints.sorted()
    }
}
