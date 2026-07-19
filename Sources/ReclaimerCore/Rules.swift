import Foundation

public struct Evidence: Codable, Hashable, Sendable {
    public let kind: String
    public let message: String

    public init(kind: String, message: String) {
        self.kind = kind; self.message = message
    }
}

public struct RuleGateEvidence: Codable, Hashable, Sendable {
    public let minimumAgeDays: Int?
    public let retentionPolicy: String?
    public let retentionDays: Int?
    public let nativeToolName: String?
    public let nativePreviewAvailable: Bool

    public init(
        minimumAgeDays: Int? = nil,
        retentionPolicy: String? = nil,
        retentionDays: Int? = nil,
        nativeToolName: String? = nil,
        nativePreviewAvailable: Bool = false
    ) {
        self.minimumAgeDays = minimumAgeDays
        self.retentionPolicy = retentionPolicy
        self.retentionDays = retentionDays
        self.nativeToolName = nativeToolName
        self.nativePreviewAvailable = nativePreviewAvailable
    }
}

public enum PlanConditionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case openFileClear
    case recursiveOpenFileClear
    case userPolicyClear
    case notSymbolicLink
    case manualReviewRequired
    case nativeToolRequired
    case appQuitRequired
    case minimumAgeRequired
    case finalClassificationRequired
}

public struct RuleMatch: Codable, Hashable, Sendable {
    public let ruleID: String
    public let title: String
    public let category: String
    public let safetyClass: SafetyClass
    public let actionKind: ActionKind
    public let evidence: [String]
    public let conditions: [String]
    public let conditionGates: [PlanConditionKind]
    public let gateEvidence: RuleGateEvidence
    public let recovery: String?

    public init(
        ruleID: String,
        title: String,
        category: String,
        safetyClass: SafetyClass,
        actionKind: ActionKind,
        evidence: [String],
        conditions: [String] = [],
        conditionGates: [PlanConditionKind] = [],
        gateEvidence: RuleGateEvidence = RuleGateEvidence(),
        recovery: String? = nil
    ) {
        self.ruleID = ruleID
        self.title = title
        self.category = category
        self.safetyClass = safetyClass
        self.actionKind = actionKind
        self.evidence = evidence
        self.conditions = conditions
        self.conditionGates = conditionGates
        self.gateEvidence = gateEvidence
        self.recovery = recovery
    }
}

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
    public let conditionGates: [PlanConditionKind]
    public let gateEvidence: RuleGateEvidence
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
        conditionGates: [PlanConditionKind] = [],
        gateEvidence: RuleGateEvidence = RuleGateEvidence(),
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
        self.conditionGates = conditionGates
        self.gateEvidence = gateEvidence
        self.recovery = recovery
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case category
        case priority
        case safetyClass
        case actionKind
        case match
        case evidence
        case conditions
        case conditionGates
        case gateEvidence
        case recovery
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.category = try container.decode(String.self, forKey: .category)
        self.priority = try container.decode(Int.self, forKey: .priority)
        self.safetyClass = try container.decode(SafetyClass.self, forKey: .safetyClass)
        self.actionKind = try container.decode(ActionKind.self, forKey: .actionKind)
        self.match = try container.decode(RuleMatchSpec.self, forKey: .match)
        self.evidence = try container.decode([String].self, forKey: .evidence)
        self.conditions = try container.decodeIfPresent([String].self, forKey: .conditions) ?? []
        self.conditionGates = try container.decodeIfPresent([PlanConditionKind].self, forKey: .conditionGates) ?? []
        self.gateEvidence = try container.decodeIfPresent(RuleGateEvidence.self, forKey: .gateEvidence) ?? RuleGateEvidence()
        self.recovery = try container.decodeIfPresent(String.self, forKey: .recovery)
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
        let url = bundledRulesURL()
        guard let url else {
            return RuleEngine(version: "fallback-1", rules: BuiltInRules.fallback)
        }
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(ReclaimerRuleFile.self, from: data)
        return RuleEngine(version: file.version, rules: file.rules)
    }

    static func bundledRulesURL(fileManager: FileManager = .default) -> URL? {
        bundledRulesURL(candidateRoots: bundledRuleCandidateRoots(), fileManager: fileManager)
    }

    static func bundledRulesURL(candidateRoots: [URL], fileManager: FileManager = .default) -> URL? {
        let bundleNames = ["Ryddi_ReclaimerCore.bundle", "MacDiskReclaimer_ReclaimerCore.bundle"]
        var seen: Set<String> = []

        for root in candidateRoots {
            let standardizedRoot = root.standardizedFileURL
            var candidates = [standardizedRoot.appendingPathComponent("rules.json")]
            candidates.append(contentsOf: bundleNames.map {
                standardizedRoot
                    .appendingPathComponent($0, isDirectory: true)
                    .appendingPathComponent("rules.json")
            })
            candidates.append(contentsOf: bundleNames.map {
                standardizedRoot
                    .appendingPathComponent($0, isDirectory: true)
                    .appendingPathComponent("Contents/Resources/rules.json")
            })

            for candidate in candidates {
                let path = candidate.standardizedFileURL.path
                guard seen.insert(path).inserted else { continue }
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue {
                    return candidate
                }
            }
        }

        return nil
    }

    private static func bundledRuleCandidateRoots() -> [URL] {
        var roots: [URL] = []
        func add(_ url: URL?) {
            guard let url else { return }
            roots.append(url.standardizedFileURL)
        }
        func addAncestorRoots(startingAt url: URL) {
            var cursor = url.standardizedFileURL
            for _ in 0..<8 {
                add(cursor)
                add(cursor.appendingPathComponent("Resources", isDirectory: true))
                add(cursor.appendingPathComponent("Contents/Resources", isDirectory: true))

                let parent = cursor.deletingLastPathComponent()
                if parent.path == cursor.path { break }
                cursor = parent
            }
        }

        add(Bundle.main.resourceURL)
        add(Bundle.main.bundleURL)
        add(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true))
        addAncestorRoots(startingAt: Bundle.main.bundleURL)

        for bundle in Bundle.allBundles {
            add(bundle.resourceURL)
            add(bundle.bundleURL)
            add(bundle.bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true))
            addAncestorRoots(startingAt: bundle.bundleURL)
        }

        for argument in CommandLine.arguments where !argument.isEmpty {
            let url = URL(fileURLWithPath: argument).standardizedFileURL
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                addAncestorRoots(startingAt: isDirectory.boolValue ? url : url.deletingLastPathComponent())
            }
        }

        return roots
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
                    conditionGates: rule.conditionGates,
                    gateEvidence: rule.gateEvidence,
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
