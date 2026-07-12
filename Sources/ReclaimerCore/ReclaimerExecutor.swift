import Foundation

public protocol Trashing: Sendable {
    func trashItem(at url: URL) throws -> URL
}

public struct FileManagerTrasher: Trashing, @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func trashItem(at url: URL) throws -> URL {
        var resultingURL: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
        guard let resultingURL else {
            throw CocoaError(.fileWriteUnknown)
        }
        return resultingURL as URL
    }
}

public struct TrashExecutionResult: Codable, Hashable, Sendable {
    public let originalPath: String
    public let resultingTrashPath: String?
    public let identity: FileIdentity
    public let reclaimedBytes: Int64

    public init(originalPath: String, resultingTrashPath: String?, identity: FileIdentity, reclaimedBytes: Int64) {
        self.originalPath = originalPath
        self.resultingTrashPath = resultingTrashPath
        self.identity = identity
        self.reclaimedBytes = reclaimedBytes
    }
}

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
    private let trasher: Trashing
    private let identityReader: FileIdentityReader

    public init(
        fileManager: FileManager = .default,
        openFileChecker: OpenFileChecking = LsofOpenFileChecker(),
        configuration: ExecutorConfiguration = ExecutorConfiguration(),
        ruleEngine: RuleEngine? = nil,
        trasher: Trashing = FileManagerTrasher(),
        identityReader: FileIdentityReader = FileIdentityReader()
    ) {
        self.fileManager = fileManager
        self.openFileChecker = openFileChecker
        self.configuration = configuration
        self.ruleEngine = ruleEngine
        self.trasher = trasher
        self.identityReader = identityReader
    }

    public func executeAuthorizedTrash(
        plan: ReclaimPlan,
        authorizationID: UUID,
        authorizationRegistry: TrashExecutionAuthorizationRegistry,
        ruleVersion: String,
        userConfirmed: Bool,
        now: Date = Date()
    ) async -> ExecutionReceipt {
        let before = freeBytes()
        let selectedItems = plan.items.filter(\.selected)
        let authorization: TrashExecutionAuthorization

        guard userConfirmed else {
            return authorizedTrashReceipt(
                items: selectedItems,
                reason: .confirmationRequired,
                message: "Trash execution requires explicit user confirmation.",
                ruleVersion: ruleVersion,
                userConfirmed: false,
                beforeFreeBytes: before
            )
        }

        do {
            authorization = try await authorizationRegistry.consume(id: authorizationID, now: now)
        } catch TrashExecutionAuthorizationError.authorizationExpired {
            return authorizedTrashReceipt(
                items: selectedItems,
                reason: .authorizationExpired,
                message: "Trash execution authorization expired; run a new dry run.",
                ruleVersion: ruleVersion,
                userConfirmed: userConfirmed,
                beforeFreeBytes: before
            )
        } catch {
            return authorizedTrashReceipt(
                items: selectedItems,
                reason: .authorizationUnavailable,
                message: "Trash execution authorization is unavailable or was already used.",
                ruleVersion: ruleVersion,
                userConfirmed: userConfirmed,
                beforeFreeBytes: before
            )
        }

        let selectedIDs = selectedItems.map(\.id)
        guard authorization.planID == plan.id,
              authorization.findingIDs == selectedIDs,
              Set(authorization.identities.keys) == Set(selectedIDs) else {
            return authorizedTrashReceipt(
                items: selectedItems,
                reason: .authorizationMismatch,
                message: "Trash execution authorization does not match the current plan selection.",
                ruleVersion: ruleVersion,
                userConfirmed: userConfirmed,
                beforeFreeBytes: before
            )
        }
        guard let session = configuration.currentScanSession,
              session.id == authorization.sessionID,
              session.stage == .reclaimReady,
              session.invalidationReasons.isEmpty,
              session.planDigest == authorization.planID,
              session.dryRunReceiptID == authorization.dryRunReceiptID else {
            return authorizedTrashReceipt(
                items: selectedItems,
                reason: .authorizationMismatch,
                message: "Trash execution authorization no longer matches the current scan session.",
                ruleVersion: ruleVersion,
                userConfirmed: true,
                beforeFreeBytes: before
            )
        }

        let selectedPaths = selectedItems.map { $0.finding.path }
        let knownPaths = plan.items.map { $0.finding.path }
        var actions: [ExecutionActionReceipt] = []
        var errors: [String] = []

        for item in selectedItems {
            let action = executeAuthorizedTrashItem(
                item,
                authorizedIdentity: authorization.identities[item.id],
                selectedPaths: selectedPaths,
                knownPaths: knownPaths
            )
            actions.append(action)
            if action.status == "error" {
                errors.append("\(item.finding.path): \(action.message)")
            }
        }

        return ExecutionReceipt(
            ruleVersion: ruleVersion,
            mode: ExecutionMode.perform.rawValue,
            beforeFreeBytes: before,
            afterFreeBytes: freeBytes(),
            actions: actions,
            userConfirmed: true,
            errors: errors
        )
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

        let selectedPaths = plan.items.filter(\.selected).map { $0.finding.path }
        let knownPaths = plan.items.map { $0.finding.path }
        for item in plan.items where item.selected {
            let action = execute(
                item: item,
                mode: mode,
                userConfirmed: userConfirmed,
                selectedPaths: selectedPaths,
                knownPaths: knownPaths
            )
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
            return "Missing current scan session: destructive perform requires current dry-run authorization."
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

    private func execute(
        item: ReclaimPlanItem,
        mode: ExecutionMode,
        userConfirmed: Bool,
        selectedPaths: [String],
        knownPaths: [String]
    ) -> ExecutionActionReceipt {
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

        let preflightOpenStatus = finalOpenFileStatus(
            for: finding,
            selectedPaths: selectedPaths,
            knownPaths: knownPaths
        )
        if let failure = openFileBlockReason(for: finding, status: preflightOpenStatus) {
            return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "skipped", message: failure)
        }

        guard mode == .perform else {
            let openStatus = finalOpenFileStatus(
                for: finding,
                selectedPaths: selectedPaths,
                knownPaths: knownPaths
            )
            if let failure = openFileBlockReason(for: finding, status: openStatus) {
                return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "skipped", message: failure)
            }
            return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "dry-run", message: "Would perform \(item.proposedAction.label).", reclaimedBytes: item.estimatedImmediateReclaim)
        }
        guard userConfirmed else {
            return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "skipped", message: "Execution requires explicit user confirmation.")
        }
        guard fileManager.fileExists(atPath: url.path) else {
            return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "skipped", message: "Path no longer exists.")
        }
        if let identityFailure = validateFilesystemIdentity(for: item) {
            return identityFailure
        }

        let openStatus = finalOpenFileStatus(
            for: finding,
            selectedPaths: selectedPaths,
            knownPaths: knownPaths
        )
        if let failure = openFileBlockReason(for: finding, status: openStatus) {
            return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "skipped", message: failure)
        }

        switch item.proposedAction {
        case .deleteCache, .trash, .compress, .quarantineHold:
            return ExecutionActionReceipt(
                path: finding.path,
                action: item.proposedAction,
                status: "skipped",
                message: "Automatic filesystem mutation is disabled: macOS does not provide an identity-bound primitive for this action. Review the item and use the manual recovery path instead."
            )
        case .nativeToolCommand, .openGuidance, .reportOnly:
            return ExecutionActionReceipt(path: finding.path, action: item.proposedAction, status: "skipped", message: "Action is guidance/report-only.")
        }
    }

    private func finalOpenFileStatus(
        for finding: Finding,
        selectedPaths: [String],
        knownPaths: [String]
    ) -> OpenFileStatus {
        let url = URL(fileURLWithPath: finding.path)
        if let linkAwareChecker = openFileChecker as? LinkAwareOpenFileChecking {
            return linkAwareChecker.status(for: url, selectedPaths: selectedPaths, knownPaths: knownPaths)
        }
        return openFileChecker.status(for: url)
    }

    private func openFileBlockReason(for finding: Finding, status: OpenFileStatus) -> String? {
        if let linkFailure = status.linkEvidence?.blockReason {
            return linkFailure
        }
        if finding.isDirectory && !status.checkedRecursively {
            return "Recursive open-file check blocked action."
        }
        guard !status.isOpen, status.checkFailed == nil else {
            let scope = status.checkedRecursively ? "Recursive open-file check" : "Open-file check"
            return "\(scope) blocked action."
        }
        return nil
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

    private func validateFilesystemIdentity(for item: ReclaimPlanItem) -> ExecutionActionReceipt? {
        let finding = item.finding
        guard let plannedIdentity = finding.filesystemIdentity else {
            return ExecutionActionReceipt(
                path: finding.path,
                action: item.proposedAction,
                status: "skipped",
                message: "Planned filesystem identity is missing; run a new scan, plan, and dry run."
            )
        }

        let currentIdentity: FilesystemIdentity
        do {
            currentIdentity = try FilesystemIdentity.capture(at: URL(fileURLWithPath: finding.path))
        } catch {
            return ExecutionActionReceipt(
                path: finding.path,
                action: item.proposedAction,
                status: "skipped",
                message: "Current filesystem identity could not be read; perform was blocked."
            )
        }
        guard currentIdentity == plannedIdentity else {
            return ExecutionActionReceipt(
                path: finding.path,
                action: item.proposedAction,
                status: "skipped",
                message: "Filesystem identity or required metadata changed after planning."
            )
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

    private func executeAuthorizedTrashItem(
        _ item: ReclaimPlanItem,
        authorizedIdentity: FileIdentity?,
        selectedPaths: [String],
        knownPaths: [String]
    ) -> ExecutionActionReceipt {
        let finding = item.finding
        guard finding.safetyClass == .autoSafe,
              finding.actionKind == .trash,
              item.proposedAction == .trash else {
            return trashSkip(item, .ineligibleAction, "Only selected auto-safe Trash actions may execute.")
        }
        guard item.conditions.allSatisfy(\.isSatisfied) else {
            return trashSkip(item, .conditionsChanged, "Plan conditions are no longer satisfied.")
        }
        guard let authorizedIdentity else {
            return trashSkip(item, .authorizationMismatch, "Authorization identity is missing for this finding.")
        }

        let url = URL(fileURLWithPath: finding.path).standardizedFileURL
        let parent = url.deletingLastPathComponent()
        guard url.path == authorizedIdentity.standardizedPath,
              url.path != "/",
              parent.path != url.path,
              parent.path != "/" else {
            return trashSkip(item, .pathContainment, "Path is outside the authorized Trash containment boundary.")
        }
        do {
            guard try identityReader.read(at: parent).kind == .directory else {
                return trashSkip(item, .pathContainment, "Authorized parent is not a directory.")
            }
        } catch {
            return trashSkip(item, .pathContainment, "Authorized parent containment could not be verified.")
        }

        let currentIdentity: FileIdentity
        do {
            currentIdentity = try identityReader.read(at: url)
        } catch FileIdentityReaderError.symbolicLink {
            return trashSkip(item, .symbolicLink, "Path changed into a symbolic link after authorization.")
        } catch FileIdentityReaderError.unsupportedFileKind {
            return trashSkip(item, .unsupportedFileType, "Path changed into an unsupported file type after authorization.")
        } catch {
            return trashSkip(item, .pathUnavailable, "Current path identity could not be read.")
        }
        guard currentIdentity.kind == authorizedIdentity.kind else {
            return trashSkip(item, .typeChanged, "Path type changed after authorization.", identity: currentIdentity)
        }
        guard currentIdentity.deviceID == authorizedIdentity.deviceID,
              currentIdentity.fileID == authorizedIdentity.fileID,
              currentIdentity.standardizedPath == authorizedIdentity.standardizedPath else {
            return trashSkip(item, .identityMismatch, "Filesystem identity changed after authorization.", identity: currentIdentity)
        }
        guard currentIdentity.kind == (finding.isDirectory ? .directory : .regularFile) else {
            return trashSkip(item, .typeChanged, "Path type no longer matches the planned finding.", identity: currentIdentity)
        }
        guard !isProtectedTrashPath(url.path) else {
            return trashSkip(item, .protectedPath, "Path is protected by the never-touch policy.", identity: currentIdentity)
        }

        let classification: Classification
        do {
            classification = try activeRuleEngine().classify(
                path: url.path,
                isDirectory: currentIdentity.kind == .directory,
                isSymbolicLink: false
            )
        } catch {
            return trashSkip(item, .classificationChanged, "Rules could not be loaded for final classification.", identity: currentIdentity)
        }
        if classification.safetyClass == .neverTouch || classification.safetyClass == .preserveByDefault {
            return trashSkip(item, .protectedClassification, "Current rule classification protects this path.", identity: currentIdentity)
        }
        guard classification.safetyClass == .autoSafe, classification.actionKind == .trash else {
            return trashSkip(item, .classificationChanged, "Current rule classification is no longer auto-safe Trash.", identity: currentIdentity)
        }

        if configuration.userPathPolicy.matchingRule(for: url.path, kind: .exclude) != nil {
            return trashSkip(item, .userExcluded, "Current user policy excludes this path.", identity: currentIdentity)
        }
        if configuration.userPathPolicy.matchingRule(for: url.path, kind: .protect) != nil {
            return trashSkip(item, .userProtected, "Current user policy protects this path.", identity: currentIdentity)
        }

        let modificationDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let gateFailure = validateCurrentGateEvidence(
            for: item,
            currentModificationDate: modificationDate,
            currentClassification: classification,
            currentIsSymbolicLink: false
        ) {
            return trashSkip(item, .gateFailed, gateFailure.message, identity: currentIdentity)
        }

        let openStatus = finalOpenFileStatus(
            for: finding,
            selectedPaths: selectedPaths,
            knownPaths: knownPaths
        )
        if let message = openFileBlockReason(for: finding, status: openStatus) {
            let reason: TrashExecutionSkipReason = finding.isDirectory || openStatus.checkedRecursively
                ? .recursiveOpenFile
                : .openFile
            return trashSkip(item, reason, message, identity: currentIdentity)
        }

        do {
            let resultingURL = try trasher.trashItem(at: url).standardizedFileURL
            return ExecutionActionReceipt(
                path: finding.path,
                action: .trash,
                status: "done",
                message: "Moved to Trash.",
                reclaimedBytes: 0,
                resultingPath: resultingURL.path,
                fileIdentity: currentIdentity
            )
        } catch {
            return ExecutionActionReceipt(
                path: finding.path,
                action: .trash,
                status: "error",
                message: "Trash operation failed: \(error.localizedDescription)",
                fileIdentity: currentIdentity,
                skipReason: .trashFailed
            )
        }
    }

    private func trashSkip(
        _ item: ReclaimPlanItem,
        _ reason: TrashExecutionSkipReason,
        _ message: String,
        identity: FileIdentity? = nil
    ) -> ExecutionActionReceipt {
        ExecutionActionReceipt(
            path: item.finding.path,
            action: item.proposedAction,
            status: "skipped",
            message: message,
            fileIdentity: identity,
            skipReason: reason
        )
    }

    private func authorizedTrashReceipt(
        items: [ReclaimPlanItem],
        reason: TrashExecutionSkipReason,
        message: String,
        ruleVersion: String,
        userConfirmed: Bool,
        beforeFreeBytes: Int64?
    ) -> ExecutionReceipt {
        ExecutionReceipt(
            ruleVersion: ruleVersion,
            mode: ExecutionMode.perform.rawValue,
            beforeFreeBytes: beforeFreeBytes,
            afterFreeBytes: beforeFreeBytes,
            actions: items.map { trashSkip($0, reason, message) },
            userConfirmed: userConfirmed
        )
    }

    private func freeBytes() -> Int64? {
        guard let values = try? URL(fileURLWithPath: "/System/Volumes/Data").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]) else {
            return nil
        }
        return values.volumeAvailableCapacityForImportantUsage
    }
}
