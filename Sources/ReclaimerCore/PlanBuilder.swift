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
        let initialItems = findings.map { finding -> ReclaimPlanItem in
            let findingWithOpenStatus: Finding
            if let openStatus = finding.openFileStatus {
                findingWithOpenStatus = finding.withOpenStatus(openStatus)
            } else if requiresOpenFileCheck(finding, mode: mode) {
                findingWithOpenStatus = finding.withOpenStatus(openFileChecker.status(for: URL(fileURLWithPath: finding.path)))
            } else {
                findingWithOpenStatus = finding
            }
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

        return ReclaimPlan(mode: mode.rawValue, items: items, dryRunSummary: summary)
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
            conditions.append(PlanCondition(message: "No active open file handle", isSatisfied: !open.isOpen && open.checkFailed == nil))
            if let failure = open.checkFailed {
                conditions.append(PlanCondition(message: "Open-file check failed: \(failure)", isSatisfied: false))
            }
        }
        if finding.safetyClass == .neverTouch || finding.safetyClass == .preserveByDefault {
            conditions.append(PlanCondition(message: "Path is protected by policy", isSatisfied: false))
        }
        if finding.isSymbolicLink {
            conditions.append(PlanCondition(message: "Symbolic links require manual review", isSatisfied: false))
        }
        for match in finding.ruleMatches.prefix(1) {
            for condition in match.conditions {
                conditions.append(PlanCondition(message: condition, isSatisfied: isAutomaticallySatisfiedRuleCondition(condition, finding: finding)))
            }
        }
        return conditions
    }

    private func isAutomaticallySatisfiedRuleCondition(_ condition: String, finding: Finding) -> Bool {
        let lower = condition.lowercased()

        let blockedTerms = [
            "manual",
            "review",
            "stale",
            "retention",
            "current-day",
            "current day",
            "recent",
            "quit",
            "native",
            "running app",
            "unknown profile",
            "versions",
            "sound-library",
            "sound library",
            "after reviewing",
            "before removal",
            "prefer native"
        ]
        if blockedTerms.contains(where: lower.contains) {
            return false
        }

        let mentionsOpenFileGuard = lower.contains("open handle")
            || lower.contains("open file")
            || lower.contains("open log")
            || lower.contains("files open")
            || lower.contains("files that are open")
            || lower.contains("open by")
            || lower.contains("have open handles")

        guard mentionsOpenFileGuard, let open = finding.openFileStatus else {
            return false
        }
        return !open.isOpen && open.checkFailed == nil
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
    func withOpenStatus(_ status: OpenFileStatus) -> Finding {
        Finding(
            id: id,
            scopeName: scopeName,
            path: path,
            displayName: displayName,
            logicalSize: logicalSize,
            allocatedSize: allocatedSize,
            isDirectory: isDirectory,
            isSymbolicLink: isSymbolicLink,
            modificationDate: modificationDate,
            ownerHint: ownerHint,
            safetyClass: safetyClass,
            actionKind: actionKind,
            ruleMatches: ruleMatches,
            evidence: evidence,
            openFileStatus: status
        )
    }
}
