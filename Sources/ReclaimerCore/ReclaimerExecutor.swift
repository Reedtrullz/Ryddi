import Foundation

public enum ExecutionMode: String, Sendable {
    case dryRun
    case perform
}

public struct ExecutorConfiguration: Sendable {
    public let holdingRoot: URL
    public let userPathPolicy: UserPathPolicy
    public let currentScanSession: ScanSession?

    public init(
        holdingRoot: URL = ExecutorConfiguration.defaultHoldingRoot(),
        userPathPolicy: UserPathPolicy = .empty,
        currentScanSession: ScanSession? = nil
    ) {
        self.holdingRoot = holdingRoot
        self.userPathPolicy = userPathPolicy
        self.currentScanSession = currentScanSession
    }

    public static func defaultHoldingRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["RYDDI_HOLDING_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Ryddi/Holding")
    }
}

public final class ReclaimerExecutor: @unchecked Sendable {
    private let fileManager: FileManager
    private let openFileChecker: OpenFileChecking
    private let configuration: ExecutorConfiguration
    private let ruleEngine: RuleEngine?

    public init(
        fileManager: FileManager = .default,
        openFileChecker: OpenFileChecking = LsofOpenFileChecker(),
        configuration: ExecutorConfiguration = ExecutorConfiguration(),
        ruleEngine: RuleEngine? = nil
    ) {
        self.fileManager = fileManager
        self.openFileChecker = openFileChecker
        self.configuration = configuration
        self.ruleEngine = ruleEngine
    }

    public func execute(
        plan: ReclaimPlan,
        mode: ExecutionMode,
        ruleVersion: String,
        userConfirmed: Bool
    ) -> ExecutionReceipt {
        let before = freeBytes()
        var actions: [ExecutionActionReceipt] = []
        var errors: [String] = []

        if mode == .perform, let staleReason = staleSessionReason(for: plan) {
            let skipped = plan.items
                .filter(\.selected)
                .map {
                    ExecutionActionReceipt(
                        path: $0.finding.path,
                        action: $0.proposedAction,
                        status: "skipped",
                        message: staleReason
                    )
                }
            return ExecutionReceipt(
                ruleVersion: ruleVersion,
                mode: mode.rawValue,
                beforeFreeBytes: before,
                afterFreeBytes: before,
                actions: skipped,
                userConfirmed: userConfirmed,
                errors: [staleReason]
            )
        }

        for item in plan.items where item.selected {
            let action = execute(item: item, mode: mode, userConfirmed: userConfirmed)
            if action.status == "error" {
                errors.append("\(item.finding.path): \(action.message)")
            }
            actions.append(action)
        }

        let after = freeBytes()
        return ExecutionReceipt(
            ruleVersion: ruleVersion,
            mode: mode.rawValue,
            beforeFreeBytes: before,
            afterFreeBytes: after,
            actions: actions,
            userConfirmed: userConfirmed,
            errors: errors
        )
    }

    private func staleSessionReason(for plan: ReclaimPlan) -> String? {
        guard let session = configuration.currentScanSession else {
            return nil
        }
        guard [.dryRunReady, .reclaimReady].contains(session.stage) else {
            return "Stale scan session: current session stage is \(session.stage.rawValue), not dryRunReady/reclaimReady."
        }
        guard session.invalidationReasons.isEmpty else {
            return "Stale scan session: \(session.invalidationReasons.map(\.rawValue).joined(separator: ", "))."
        }
        guard session.planDigest == plan.id else {
            return "Stale scan session: plan digest no longer matches the current plan."
        }
        guard session.dryRunReceiptID != nil else {
            return "Stale scan session: no current dry-run receipt is recorded."
        }
        return nil
    }

    private func execute(item: ReclaimPlanItem, mode: ExecutionMode, userConfirmed: Bool) -> ExecutionActionReceipt {
        let finding = item.finding
        let url = URL(fileURLWithPath: finding.path)

        if let rule = configuration.userPathPolicy.matchingRule(for: finding.path, kind: .exclude) {
            return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "skipped", message: "Blocked by user exclusion rule at \(rule.path).")
        }
        if let rule = configuration.userPathPolicy.matchingRule(for: finding.path, kind: .protect) {
            return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "skipped", message: "Blocked by user protection rule at \(rule.path).")
        }
        guard item.conditions.allSatisfy(\.isSatisfied) else {
            return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "skipped", message: "Plan conditions were not satisfied.")
        }
        guard finding.safetyClass != .neverTouch, finding.safetyClass != .preserveByDefault else {
            return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "skipped", message: "Protected by safety policy.")
        }
        guard !finding.isSymbolicLink else {
            return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "skipped", message: "Symbolic links are never reclaimed automatically.")
        }

        if mode == .perform, let validationFailure = validateCurrentState(for: item) {
            return validationFailure
        }

        let openStatus = openFileChecker.status(for: url)
        guard !openStatus.isOpen, openStatus.checkFailed == nil else {
            let scope = openStatus.checkedRecursively ? "Recursive open-file check" : "Open-file check"
            return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "skipped", message: "\(scope) blocked action.")
        }

        guard mode == .perform else {
            return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "dry-run", message: "Would perform \(item.proposedAction.label).", reclaimedBytes: item.estimatedImmediateReclaim)
        }
        guard userConfirmed else {
            return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "skipped", message: "Execution requires explicit user confirmation.")
        }
        guard fileManager.fileExists(atPath: url.path) else {
            return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "skipped", message: "Path no longer exists.")
        }

        do {
            switch item.proposedAction {
            case .deleteCache:
                guard finding.safetyClass == .autoSafe else {
                    return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "skipped", message: "Direct cache delete requires Auto-safe classification.")
                }
                try fileManager.removeItem(at: url)
                return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "done", message: "Deleted allowlisted cache.", reclaimedBytes: finding.allocatedSize)
            case .trash:
                var trashedURL: NSURL?
                try fileManager.trashItem(at: url, resultingItemURL: &trashedURL)
                return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "done", message: "Moved to Trash.", reclaimedBytes: finding.allocatedSize)
            case .compress:
                try gzip(url: url)
                return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "done", message: "Compressed file with gzip.", reclaimedBytes: finding.allocatedSize / 2)
            case .quarantineHold:
                let target = try holdingURL(for: url)
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: url, to: target)
                try HoldingStore(root: configuration.holdingRoot, fileManager: fileManager).recordHold(source: url, target: target, finding: finding)
                return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "done", message: "Moved to app holding area: \(target.path).")
            case .nativeToolCommand, .openGuidance, .reportOnly:
                return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "skipped", message: "Action is guidance/report-only.")
            }
        } catch {
            return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "error", message: error.localizedDescription)
        }
    }

    private func validateCurrentState(for item: ReclaimPlanItem) -> ExecutionActionReceipt? {
        let finding = item.finding
        let url = URL(fileURLWithPath: finding.path)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "skipped", message: "Path no longer exists.")
        }

        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]) else {
            return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "skipped", message: "Could not re-read filesystem metadata.")
        }

        let currentIsDirectory = values.isDirectory ?? isDirectory.boolValue
        let currentIsSymbolicLink = (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
            || (values.isSymbolicLink ?? false)
        guard !currentIsSymbolicLink else {
            return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "skipped", message: "Path changed into a symbolic link after planning.")
        }
        if let rule = configuration.userPathPolicy.matchingRule(for: url.path, kind: .exclude) {
            return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "skipped", message: "Path is now covered by a user exclusion rule at \(rule.path).")
        }
        if let rule = configuration.userPathPolicy.matchingRule(for: url.path, kind: .protect) {
            return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "skipped", message: "Path is now covered by a user protection rule at \(rule.path).")
        }
        guard currentIsDirectory == finding.isDirectory else {
            return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "skipped", message: "Path type changed after planning.")
        }

        do {
            let engine = try activeRuleEngine()
            let classification = engine.classify(path: url.path, isDirectory: currentIsDirectory, isSymbolicLink: currentIsSymbolicLink)
            guard classification.safetyClass == finding.safetyClass, classification.actionKind == item.proposedAction else {
                return ExecutionActionReceipt(
                    path: finding.path,
                    action: item.proposedAction,
                    status: "skipped",
                    message: "Current rule classification no longer matches the saved plan."
                )
            }
            if let gateFailure = validateCurrentGateEvidence(
                for: item,
                currentModificationDate: values.contentModificationDate,
                currentClassification: classification,
                currentIsSymbolicLink: currentIsSymbolicLink
            ) {
                return gateFailure
            }
        } catch {
            return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "skipped", message: "Could not load rules for final safety check: \(error.localizedDescription)")
        }

        return nil
    }

    private func validateCurrentGateEvidence(
        for item: ReclaimPlanItem,
        currentModificationDate: Date?,
        currentClassification: Classification,
        currentIsSymbolicLink: Bool
    ) -> ExecutionActionReceipt? {
        let finding = item.finding
        let explicitRuleGates = finding.ruleMatches.flatMap(\.conditionGates)
        let explicitPlanConditions = item.conditions
            .map(\.kind)
            .filter { $0 != .manualReviewRequired }
        let plannedGateKinds = Set(explicitRuleGates + explicitPlanConditions)
        guard !plannedGateKinds.isEmpty else {
            return nil
        }

        let plannedPrimaryRuleID = finding.ruleMatches.first?.ruleID
        let currentPrimaryMatch = currentClassification.matches.first

        if plannedGateKinds.contains(.finalClassificationRequired),
           plannedPrimaryRuleID != currentPrimaryMatch?.ruleID {
            return ExecutionActionReceipt(
                path: finding.path,
                action: item.proposedAction,
                status: "skipped",
                message: "Current rule classification no longer matches the saved plan."
            )
        }

        if plannedGateKinds.contains(.minimumAgeRequired) {
            guard let minimumAgeDays = currentPrimaryMatch?.gateEvidence.minimumAgeDays else {
                return ExecutionActionReceipt(
                    path: finding.path,
                    action: item.proposedAction,
                    status: "skipped",
                    message: "Minimum age gate is missing current rule evidence."
                )
            }
            guard let currentModificationDate else {
                return ExecutionActionReceipt(
                    path: finding.path,
                    action: item.proposedAction,
                    status: "skipped",
                    message: "Minimum age gate could not be rechecked from current metadata."
                )
            }
            let currentAge = Date().timeIntervalSince(currentModificationDate)
            guard currentAge >= Double(minimumAgeDays) * 86_400 else {
                return ExecutionActionReceipt(
                    path: finding.path,
                    action: item.proposedAction,
                    status: "skipped",
                    message: "Minimum age gate is no longer satisfied by current metadata."
                )
            }
        }

        if plannedGateKinds.contains(.nativeToolRequired),
           currentPrimaryMatch?.gateEvidence.nativePreviewAvailable != true {
            return ExecutionActionReceipt(
                path: finding.path,
                action: item.proposedAction,
                status: "skipped",
                message: "Native-tool gate is missing current preview evidence."
            )
        }

        if plannedGateKinds.contains(.notSymbolicLink), currentIsSymbolicLink {
            return ExecutionActionReceipt(
                path: finding.path,
                action: item.proposedAction,
                status: "skipped",
                message: "Path changed into a symbolic link after planning."
            )
        }

        if plannedGateKinds.contains(.manualReviewRequired) || plannedGateKinds.contains(.appQuitRequired) {
            return ExecutionActionReceipt(
                path: finding.path,
                action: item.proposedAction,
                status: "skipped",
                message: "Manual review or app-quit gate cannot be satisfied automatically during execution."
            )
        }

        return nil
    }

    private func activeRuleEngine() throws -> RuleEngine {
        if let ruleEngine {
            return ruleEngine
        }
        return try RuleEngine.bundled()
    }

    private func holdingURL(for source: URL) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return configuration.holdingRoot.appendingPathComponent(stamp, isDirectory: true).appendingPathComponent(source.lastPathComponent)
    }

    private func gzip(url: URL) throws {
        guard !url.hasDirectoryPath else {
            throw NSError(domain: "Ryddi", code: 3, userInfo: [NSLocalizedDescriptionKey: "Compression is only supported for files in v1."])
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-kf", url.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "Ryddi", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "gzip exited with status \(process.terminationStatus)."])
        }
    }

    private func freeBytes() -> Int64? {
        guard let values = try? URL(fileURLWithPath: "/System/Volumes/Data").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]) else {
            return nil
        }
        return values.volumeAvailableCapacityForImportantUsage
    }
}
