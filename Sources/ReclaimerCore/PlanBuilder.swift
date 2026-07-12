import CryptoKit
import Foundation

public enum PlanMode: String, Sendable {
    case autoSafeOnly
    case reviewAll
}

public final class PlanBuilder: @unchecked Sendable {
    private let openFileChecker: OpenFileChecking

    public init(openFileChecker: OpenFileChecking = LsofOpenFileChecker()) {
        self.openFileChecker = openFileChecker
    }

    public func buildPlan(from findings: [Finding], mode: PlanMode = .autoSafeOnly) -> ReclaimPlan {
        let knownPaths = findings.map(\.path)
        let potentialSelectedPaths = findings
            .filter { isSelectionCandidate($0, mode: mode) }
            .map(\.path)
        let initialItems = findings.map { finding -> ReclaimPlanItem in
            let findingWithOpenStatus = finding.withOpenFileStatusIfNeeded(
                openFileChecker: openFileChecker,
                selectedPaths: potentialSelectedPaths,
                knownPaths: knownPaths,
                requiresOpenFileCheck: requiresOpenFileCheck(finding, mode: mode)
            )
            let conditions = conditions(for: findingWithOpenStatus)
            let selected = shouldSelect(findingWithOpenStatus, mode: mode, conditions: conditions)
            let reclaim = selected ? estimatedReclaim(for: findingWithOpenStatus) : 0
            return ReclaimPlanItem(
                finding: findingWithOpenStatus,
                selected: selected,
                proposedAction: findingWithOpenStatus.actionKind,
                conditions: conditions,
                estimatedImmediateReclaim: reclaim
            )
        }
        let items = deduplicateNestedSelections(initialItems)

        let summary = items.map { item in
            let marker = item.selected ? "[selected]" : "[review]"
            return "\(marker) \(item.finding.displayName): \(item.finding.safetyClass.label), \(item.proposedAction.label), \(ByteFormat.string(item.finding.allocatedSize))"
        }

        return ReclaimPlan(
            id: stablePlanID(mode: mode, items: items),
            mode: mode.rawValue,
            items: items,
            dryRunSummary: summary
        )
    }

    private func requiresOpenFileCheck(_ finding: Finding, mode: PlanMode) -> Bool {
        switch mode {
        case .autoSafeOnly:
            return finding.safetyClass == .autoSafe && [.deleteCache, .trash].contains(finding.actionKind)
        case .reviewAll:
            return [.autoSafe, .safeAfterCondition].contains(finding.safetyClass)
                && [.deleteCache, .trash, .compress, .quarantineHold].contains(finding.actionKind)
        }
    }

    private func isSelectionCandidate(_ finding: Finding, mode: PlanMode) -> Bool {
        switch mode {
        case .autoSafeOnly:
            return finding.safetyClass == .autoSafe && [.deleteCache, .trash].contains(finding.actionKind)
        case .reviewAll:
            return [.autoSafe, .safeAfterCondition].contains(finding.safetyClass)
                && [.deleteCache, .trash, .compress, .quarantineHold].contains(finding.actionKind)
        }
    }

    private func shouldSelect(_ finding: Finding, mode: PlanMode, conditions: [PlanCondition]) -> Bool {
        guard conditions.allSatisfy(\.isSatisfied) else { return false }
        switch mode {
        case .autoSafeOnly:
            return finding.safetyClass == .autoSafe && [.deleteCache, .trash].contains(finding.actionKind)
        case .reviewAll:
            return [.autoSafe, .safeAfterCondition].contains(finding.safetyClass)
                && [.deleteCache, .trash, .compress, .quarantineHold].contains(finding.actionKind)
        }
    }

    private func conditions(for finding: Finding) -> [PlanCondition] {
        var conditions: [PlanCondition] = []
        if let open = finding.openFileStatus {
            let requiresRecursiveCheck = finding.isDirectory
            let openConditionKind: PlanConditionKind = requiresRecursiveCheck ? .recursiveOpenFileClear : .openFileClear
            let recursiveEvidenceSatisfied = !requiresRecursiveCheck || open.checkedRecursively
            conditions.append(PlanCondition(
                kind: openConditionKind,
                message: requiresRecursiveCheck ? "No active open file handle in directory tree" : "No active open file handle",
                isSatisfied: !open.isOpen && open.checkFailed == nil && recursiveEvidenceSatisfied
            ))
            if let failure = open.checkFailed {
                conditions.append(PlanCondition(kind: openConditionKind, message: "Open-file check failed: \(failure)", isSatisfied: false))
            }
            if let linkFailure = open.linkEvidence?.blockReason {
                conditions.append(PlanCondition(kind: openConditionKind, message: "Link-aware open-file check failed: \(linkFailure)", isSatisfied: false))
            }
            if requiresRecursiveCheck && !open.checkedRecursively {
                conditions.append(PlanCondition(kind: openConditionKind, message: "Recursive open-file evidence is required for directories", isSatisfied: false))
            }
            if let hardLinkCount = finding.filesystemIdentity?.hardLinkCount,
               hardLinkCount > 1,
               open.linkEvidence == nil {
                conditions.append(PlanCondition(kind: openConditionKind, message: "Hard-link identity evidence is missing", isSatisfied: false))
            }
        }
        if finding.safetyClass == .neverTouch || finding.safetyClass == .preserveByDefault {
            conditions.append(PlanCondition(kind: .userPolicyClear, message: "Path is protected by policy", isSatisfied: false))
        }
        if finding.isSymbolicLink {
            conditions.append(PlanCondition(kind: .notSymbolicLink, message: "Symbolic links require manual review", isSatisfied: false))
        }
        for match in finding.ruleMatches.prefix(1) {
            for gate in match.conditionGates {
                conditions.append(condition(for: gate, finding: finding, match: match))
            }
            for condition in match.conditions {
                let kind = inferredConditionKind(condition)
                let satisfied = match.conditionGates.contains(kind) && isGateSatisfied(kind, finding: finding, match: match)
                conditions.append(PlanCondition(kind: kind, message: condition, isSatisfied: satisfied))
            }
        }
        return conditions
    }

    private func condition(for gate: PlanConditionKind, finding: Finding, match: RuleMatch) -> PlanCondition {
        switch gate {
        case .openFileClear:
            return PlanCondition(kind: gate, message: "Required open-file check is clear", isSatisfied: isGateSatisfied(gate, finding: finding, match: match))
        case .recursiveOpenFileClear:
            return PlanCondition(kind: gate, message: "Required recursive open-file check is clear", isSatisfied: isGateSatisfied(gate, finding: finding, match: match))
        case .userPolicyClear:
            return PlanCondition(kind: gate, message: "No user protection or exclusion blocks this path", isSatisfied: true)
        case .notSymbolicLink:
            return PlanCondition(kind: gate, message: "Path is not a symbolic link", isSatisfied: !finding.isSymbolicLink)
        case .manualReviewRequired:
            return PlanCondition(kind: gate, message: "Manual review required before cleanup", isSatisfied: false)
        case .nativeToolRequired:
            let tool = match.gateEvidence.nativeToolName ?? "native tool"
            return PlanCondition(
                kind: gate,
                message: "Native preview is available through \(tool)",
                isSatisfied: isGateSatisfied(gate, finding: finding, match: match)
            )
        case .appQuitRequired:
            return PlanCondition(kind: gate, message: "Quit the owning app before cleanup", isSatisfied: false)
        case .minimumAgeRequired:
            let ageLabel = match.gateEvidence.minimumAgeDays.map { "\($0)-day" } ?? "configured"
            return PlanCondition(
                kind: gate,
                message: "Minimum \(ageLabel) age requirement is machine-verified",
                isSatisfied: isGateSatisfied(gate, finding: finding, match: match)
            )
        case .finalClassificationRequired:
            return PlanCondition(kind: gate, message: "Final classification will be rechecked at execution", isSatisfied: true)
        }
    }

    private func isGateSatisfied(_ gate: PlanConditionKind, finding: Finding, match: RuleMatch) -> Bool {
        switch gate {
        case .openFileClear:
            guard let open = finding.openFileStatus else { return false }
            return !open.isOpen && open.checkFailed == nil
        case .recursiveOpenFileClear:
            guard let open = finding.openFileStatus else { return false }
            return open.checkedRecursively && !open.isOpen && open.checkFailed == nil
        case .userPolicyClear, .finalClassificationRequired:
            return true
        case .notSymbolicLink:
            return !finding.isSymbolicLink
        case .nativeToolRequired:
            return match.gateEvidence.nativePreviewAvailable
        case .minimumAgeRequired:
            guard let minimumAgeDays = match.gateEvidence.minimumAgeDays else { return false }
            guard let modificationDate = finding.modificationDate else { return false }
            return Date().timeIntervalSince(modificationDate) >= Double(minimumAgeDays) * 86_400
        case .manualReviewRequired, .appQuitRequired:
            return false
        }
    }

    private func inferredConditionKind(_ condition: String) -> PlanConditionKind {
        let lower = condition.lowercased()

        if lower.contains("native") || lower.contains("prefer native") {
            return .nativeToolRequired
        }
        if lower.contains("quit") || lower.contains("running app") {
            return .appQuitRequired
        }
        if lower.contains("stale") || lower.contains("retention") || lower.contains("current-day") || lower.contains("current day") || lower.contains("recent") {
            return .minimumAgeRequired
        }
        if lower.contains("open handle") || lower.contains("open file") || lower.contains("open log") || lower.contains("files open") || lower.contains("files that are open") || lower.contains("open by") || lower.contains("have open handles") {
            return .openFileClear
        }
        return .manualReviewRequired
    }

    private func deduplicateNestedSelections(_ items: [ReclaimPlanItem]) -> [ReclaimPlanItem] {
        var output = items
        var selectedAncestors: [String] = []
        let selectedIndices = items.indices
            .filter { items[$0].selected }
            .sorted { lhs, rhs in
                let lhsPath = standardizedPath(items[lhs].finding.path)
                let rhsPath = standardizedPath(items[rhs].finding.path)
                let lhsDepth = URL(fileURLWithPath: lhsPath).pathComponents.count
                let rhsDepth = URL(fileURLWithPath: rhsPath).pathComponents.count
                if lhsDepth == rhsDepth {
                    return lhsPath < rhsPath
                }
                return lhsDepth < rhsDepth
            }

        for index in selectedIndices {
            let path = standardizedPath(items[index].finding.path)
            if let ancestor = selectedAncestors.first(where: { isDescendant(path, of: $0) }) {
                var conditions = items[index].conditions
                conditions.append(PlanCondition(message: "Already included in selected ancestor: \(ancestor)", isSatisfied: false))
                output[index] = ReclaimPlanItem(
                    finding: items[index].finding,
                    selected: false,
                    proposedAction: items[index].proposedAction,
                    conditions: conditions,
                    estimatedImmediateReclaim: 0
                )
            } else {
                selectedAncestors.append(path)
            }
        }
        return output
    }

    private func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func isDescendant(_ path: String, of ancestor: String) -> Bool {
        guard path != ancestor else { return false }
        let ancestorWithSlash = ancestor.hasSuffix("/") ? ancestor : ancestor + "/"
        return path.hasPrefix(ancestorWithSlash)
    }

    private func estimatedReclaim(for finding: Finding) -> Int64 {
        switch finding.actionKind {
        case .deleteCache, .trash:
            finding.allocatedSize
        case .compress:
            finding.allocatedSize / 2
        case .quarantineHold:
            0
        case .nativeToolCommand, .openGuidance, .reportOnly:
            0
        }
    }

}

private extension Finding {
    func withOpenFileStatusIfNeeded(
        openFileChecker: OpenFileChecking,
        selectedPaths: [String],
        knownPaths: [String],
        requiresOpenFileCheck: Bool
    ) -> Finding {
        let url = URL(fileURLWithPath: path)
        if let linkAwareChecker = openFileChecker as? LinkAwareOpenFileChecking,
           let existingStatus = openFileStatus,
           (existingStatus.linkEvidence == nil || (isDirectory && !existingStatus.checkedRecursively)) {
            return withOpenFileStatus(linkAwareChecker.status(for: url, selectedPaths: selectedPaths, knownPaths: knownPaths))
        }
        if let openFileStatus {
            return withOpenFileStatus(openFileStatus)
        }
        guard requiresOpenFileCheck else { return self }
        if let linkAwareChecker = openFileChecker as? LinkAwareOpenFileChecking {
            return withOpenFileStatus(linkAwareChecker.status(for: url, selectedPaths: selectedPaths, knownPaths: knownPaths))
        }
        return withOpenFileStatus(openFileChecker.status(for: url))
    }
}

private extension PlanBuilder {
    func stablePlanID(mode: PlanMode, items: [ReclaimPlanItem]) -> String {
        let payload = StablePlanPayload(
            mode: mode.rawValue,
            items: items.map(StablePlanItem.init(item:)).sorted()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(payload)) ?? Data(payload.canonicalString.utf8)
        return "plan-\(data.sha256Hex)"
    }

    private struct StablePlanPayload: Codable, Hashable {
        let mode: String
        let items: [StablePlanItem]

        var canonicalString: String {
            ([mode] + items.map(\.canonicalString)).joined(separator: "\u{001e}")
        }
    }

    private struct StablePlanItem: Codable, Hashable, Comparable {
        let path: String
        let selected: Bool
        let actionKind: String
        let safetyClass: String
        let logicalSize: Int64
        let allocatedSize: Int64
        let estimatedImmediateReclaim: Int64
        let isDirectory: Bool
        let isSymbolicLink: Bool
        let modificationTimestamp: TimeInterval?
        let filesystemIdentity: FilesystemIdentity?
        let conditionStates: [String]

        init(item: ReclaimPlanItem) {
            self.path = URL(fileURLWithPath: item.finding.path).standardizedFileURL.path
            self.selected = item.selected
            self.actionKind = item.proposedAction.rawValue
            self.safetyClass = item.finding.safetyClass.rawValue
            self.logicalSize = item.finding.logicalSize
            self.allocatedSize = item.finding.allocatedSize
            self.estimatedImmediateReclaim = item.estimatedImmediateReclaim
            self.isDirectory = item.finding.isDirectory
            self.isSymbolicLink = item.finding.isSymbolicLink
            self.modificationTimestamp = item.finding.modificationDate?.timeIntervalSince1970
            self.filesystemIdentity = item.finding.filesystemIdentity
            self.conditionStates = item.conditions
                .map { "\($0.kind.rawValue)=\($0.isSatisfied ? "true" : "false")" }
                .sorted()
        }

        var canonicalString: String {
            var parts: [String] = []
            parts.append(path)
            parts.append(selected ? "selected" : "review")
            parts.append(actionKind)
            parts.append(safetyClass)
            parts.append(String(logicalSize))
            parts.append(String(allocatedSize))
            parts.append(String(estimatedImmediateReclaim))
            parts.append(isDirectory ? "directory" : "file")
            parts.append(isSymbolicLink ? "symlink" : "not-symlink")
            parts.append(modificationTimestamp.map { String($0) } ?? "no-mtime")
            parts.append(filesystemIdentity?.digestComponent ?? "no-filesystem-identity")
            parts.append(conditionStates.joined(separator: "\u{001f}"))
            return parts.joined(separator: "\u{001f}")
        }

        static func < (lhs: StablePlanItem, rhs: StablePlanItem) -> Bool {
            if lhs.path != rhs.path { return lhs.path < rhs.path }
            if lhs.actionKind != rhs.actionKind { return lhs.actionKind < rhs.actionKind }
            if lhs.selected != rhs.selected { return !lhs.selected && rhs.selected }
            return lhs.canonicalString < rhs.canonicalString
        }
    }
}

private extension Data {
    var sha256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
