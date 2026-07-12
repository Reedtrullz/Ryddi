import SwiftUI
import ReclaimerCore

struct GuidedSummaryView: View {
    let model: DashboardModel
    let report: ActionCenterReport
    let navigate: (String) -> Void

    var body: some View {
        SectionBox(title: "Action Center") {
            VStack(alignment: .leading, spacing: 16) {
                statusSummary
                primaryActionPanel
                secondaryActionList
                reclaimBlockedReasons
            }
        }
    }

    private var statusSummary: some View {
        LazyVGrid(columns: DashboardResponsiveGrid.metricColumns, spacing: 12) {
            SummaryStatusTile(
                title: "Disk Status",
                value: model.diskStatus.pressure.label,
                detail: model.diskStatus.statusLine,
                systemImage: "internaldrive"
            )
            SummaryStatusTile(
                title: "Access",
                value: model.permissionReport.coverageLevel.label,
                detail: model.permissionReport.coverageSummary,
                systemImage: "lock.shield"
            )
            SummaryStatusTile(
                title: "Last Session",
                value: sessionStateLabel,
                detail: sessionDetail,
                systemImage: "clock.arrow.circlepath"
            )
        }
        .accessibilityIdentifier(AccessibilityID.flowStatus)
    }

    @ViewBuilder
    private var primaryActionPanel: some View {
        Group {
            if let primary = report.primaryAction {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 16) {
                        actionText(for: primary)
                        Spacer(minLength: 12)
                        actionButton(for: SummaryCommand(action: primary), prominent: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        actionText(for: primary)
                        actionButton(for: SummaryCommand(action: primary), prominent: true)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("No immediate action", systemImage: "checkmark.shield")
                        .font(.title3.weight(.semibold))
                    Text("No current Action Center command is available from the app's saved evidence.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var secondaryActionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Secondary Actions")
                .font(.headline)
            if secondaryCommands.isEmpty {
                Text("No secondary action is available until new scan or review evidence exists.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: DashboardResponsiveGrid.actionColumns, alignment: .leading, spacing: 10) {
                    ForEach(secondaryCommands) { command in
                        actionButton(for: command, prominent: false)
                    }
                }
            }
        }
    }

    private var reclaimBlockedReasons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(canExecuteCoreReclaim ? "Recoverable cleanup is ready" : "Cleanup safety checks")
                .font(.headline)

            if let message = model.trashExecutionMessage {
                Label(message, systemImage: "checkmark.circle")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityID.trashResult)
            }

            ForEach(reclaimBlockReasons, id: \.self) { reason in
                Label(reason, systemImage: "hand.raised")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(reclaimBlockBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    private func actionText(for action: ActionCenterAction) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(action.title, systemImage: iconName(for: action))
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.82)
            Text(action.reason)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if action.estimatedReclaimBytes > 0 || action.count > 0 {
                Text(actionDetail(for: action))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func actionButton(for command: SummaryCommand, prominent: Bool) -> some View {
        if prominent {
            Button(role: command.role) {
                performActionCenterCommand(command)
            } label: {
                Label(command.title, systemImage: command.systemImage)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .center)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isCommandDisabled(command))
            .help(command.reason)
            .accessibilityIdentifier(accessibilityIdentifier(for: command))
        } else {
            Button(role: command.role) {
                performActionCenterCommand(command)
            } label: {
                Label(command.title, systemImage: command.systemImage)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .center)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(isCommandDisabled(command))
            .help(command.reason)
            .accessibilityIdentifier(accessibilityIdentifier(for: command))
        }
    }

    private func accessibilityIdentifier(for command: SummaryCommand) -> String {
        switch command.command {
        case .scan:
            AccessibilityID.summaryScan
        case .plan:
            AccessibilityID.summaryPlan
        case .dryRun:
            AccessibilityID.summaryDryRun
        case .reclaim:
            AccessibilityID.summaryReclaim
        case .actionCenter(let action):
            switch action.kind {
            case .runScan: AccessibilityID.summaryScan
            case .runDryRun: AccessibilityID.summaryDryRun
            case .executeSafePlan: AccessibilityID.summaryReclaim
            case .grantAccess: "summary.permissions-button"
            case .reviewQueue, .quitApp, .useNativeTool: AccessibilityID.summaryManualReview
            }
        case .openReviewQueue:
            AccessibilityID.summaryManualReview
        case .openPermissions:
            "summary.permissions-button"
        case .exportReport:
            "summary.export-button"
        }
    }

    private var secondaryCommands: [SummaryCommand] {
        var commands = report.actions.dropFirst().map { SummaryCommand(action: $0) }
        let coreKinds = Set(report.actions.map(\.kind))

        if !coreKinds.contains(.runScan) {
            commands.append(.standard(
                id: "command.scan",
                title: model.findings.isEmpty ? "Scan" : "Scan Again",
                reason: "Refresh local evidence from the selected scope set.",
                systemImage: "magnifyingglass",
                command: .scan
            ))
        }

        if !model.findings.isEmpty {
            commands.append(.standard(
                id: "command.plan",
                title: "Plan",
                reason: "Build a local safe-maintenance reclaim plan from current findings.",
                systemImage: "checklist",
                command: .plan
            ))
        }

        if model.plan != nil, !coreKinds.contains(.runDryRun) {
            commands.append(.standard(
                id: "command.dry-run",
                title: "Dry Run",
                reason: "Preview the current plan before any reclaim action.",
                systemImage: "play.circle",
                command: .dryRun
            ))
        }

        if !model.findings.isEmpty, !coreKinds.contains(.reviewQueue) {
            commands.append(.standard(
                id: "command.review-queue",
                title: "Open Cleanup Flow",
                reason: "Start with safe cleanup, then resolve app and native-tool blockers without mixing in protected data.",
                systemImage: "arrow.right.circle",
                command: .openReviewQueue
            ))
        }

        if model.permissionReport.coverageLevel != .complete, !coreKinds.contains(.grantAccess) {
            commands.append(.standard(
                id: "command.permissions",
                title: "Open Permissions",
                reason: "Review access coverage before treating scan results as complete.",
                systemImage: "lock.shield",
                command: .openPermissions
            ))
        }

        if model.overview != nil, !model.findings.isEmpty {
            commands.append(.standard(
                id: "command.export-report",
                title: "Export Report",
                reason: "Export redacted evidence without modifying files.",
                systemImage: "square.and.arrow.up",
                command: .exportReport
            ))
        }

        return uniqueCommands(commands)
    }

    private var canExecuteCoreReclaim: Bool {
        model.trashExecutionReadiness.isReady
    }

    private var reclaimBlockReasons: [String] {
        if canExecuteCoreReclaim {
            return [
                model.trashExecutionReadiness.reason,
                "Nothing moves until you review every selected path and confirm the one-time Trash action."
            ]
        }
        var reasons = [model.trashExecutionReadiness.reason]
        reasons += report.actions
            .filter { $0.kind != .executeSafePlan }
            .map(\.reason)
            .filter { !$0.isEmpty }

        if model.overview == nil, model.findings.isEmpty {
            reasons.append("Run a scan before planning cleanup.")
        } else if model.plan == nil {
            reasons.append("Create a plan before reclaiming.")
        } else if model.lastDryRunReceipt == nil {
            reasons.append("Run a dry run against the current plan before reclaiming.")
        }

        return uniqueStrings(reasons).prefix(4).map { $0 }
    }

    private var reclaimBlockBackground: Color {
        canExecuteCoreReclaim ? Color.green.opacity(0.10) : Color.orange.opacity(0.12)
    }

    private var sessionStateLabel: String {
        guard let session = model.actionCenterScanSession else {
            return "Not started"
        }
        switch session.stage {
        case .notStarted: return "Not started"
        case .scanned: return "Scanned"
        case .reviewed: return "Reviewed"
        case .planReady: return "Plan ready"
        case .dryRunReady: return "Dry run ready"
        case .reclaimReady: return "Manual review ready"
        case .executed: return "Executed"
        case .recoveryAvailable: return "Recovery available"
        case .invalidated: return "Invalidated"
        }
    }

    private var sessionDetail: String {
        guard let session = model.actionCenterScanSession else {
            return "No scan evidence loaded"
        }
        let updated = session.updatedAt.formatted(date: .abbreviated, time: .shortened)
        return "\(model.lastScannedScopeLabel ?? model.selectedScopePlan.label) · \(updated)"
    }

    private func actionDetail(for action: ActionCenterAction) -> String {
        var parts: [String] = []
        if action.estimatedReclaimBytes > 0 {
            parts.append(ByteFormat.string(action.estimatedReclaimBytes))
        }
        if action.count > 0 {
            parts.append("\(action.count) item\(action.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    private func performActionCenterCommand(_ command: SummaryCommand) {
        switch command.command {
        case .actionCenter(let action):
            performActionCenterAction(action)
        case .scan:
            Task { await model.scan() }
        case .plan:
            Task { await model.buildPlan() }
        case .dryRun:
            Task { await model.runDryRun() }
        case .reclaim:
            Task { await model.prepareTrashExecution() }
        case .openReviewQueue:
            navigate("Queues")
        case .openPermissions:
            navigate("Permissions")
        case .exportReport:
            Task { await model.exportEvidenceReport(pathStyle: .redacted, redactUserText: true) }
        }
    }

    private func performActionCenterAction(_ action: ActionCenterAction) {
        switch action.kind {
        case .grantAccess:
            navigate("Permissions")
        case .runScan:
            Task { await model.scan() }
        case .reviewQueue:
            if let queueID = ReviewQueueID.parse(action.sourceIDs.first ?? "") {
                model.recordReviewSelection(queueID)
            }
            navigate("Queues")
        case .runDryRun:
            Task { await model.runDryRun() }
        case .executeSafePlan:
            Task { await model.prepareTrashExecution() }
        case .quitApp:
            navigate(action.id.hasPrefix("browser-cache.") ? "Browsers" : "Active")
        case .useNativeTool:
            navigate(action.id.hasPrefix("native-tool-receipt.") ? "Audit" : "Packages")
        }
    }

    private func isCommandDisabled(_ command: SummaryCommand) -> Bool {
        if model.isWorking {
            return true
        }

        switch command.command {
        case .actionCenter(let action):
            return isActionDisabled(action)
        case .scan, .openPermissions:
            return false
        case .plan, .openReviewQueue:
            return model.findings.isEmpty
        case .dryRun:
            return model.plan == nil && model.findings.isEmpty
        case .reclaim:
            return !canExecuteCoreReclaim
        case .exportReport:
            return model.overview == nil || model.findings.isEmpty
        }
    }

    private func isActionDisabled(_ action: ActionCenterAction) -> Bool {
        switch action.kind {
        case .grantAccess, .runScan, .quitApp, .useNativeTool:
            return false
        case .reviewQueue:
            return model.findings.isEmpty
        case .runDryRun:
            return model.plan == nil && model.findings.isEmpty
        case .executeSafePlan:
            return !canExecuteCoreReclaim
        }
    }

    private func iconName(for action: ActionCenterAction) -> String {
        switch action.kind {
        case .grantAccess:
            "lock.shield"
        case .runScan:
            "magnifyingglass"
        case .reviewQueue:
            "tray.full"
        case .runDryRun:
            "play.circle"
        case .executeSafePlan:
            "trash"
        case .quitApp:
            "xmark.app"
        case .useNativeTool:
            "terminal"
        }
    }

    private func uniqueCommands(_ commands: [SummaryCommand]) -> [SummaryCommand] {
        var seen = Set<String>()
        return commands.filter { seen.insert($0.id).inserted }
    }

    private func uniqueStrings(_ strings: [String]) -> [String] {
        var seen = Set<String>()
        return strings.filter { seen.insert($0).inserted }
    }
}

private struct SummaryStatusTile: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator.opacity(0.45), lineWidth: 1)
                )
        }
    }
}

private struct SummaryCommand: Identifiable {
    enum Command {
        case actionCenter(ActionCenterAction)
        case scan
        case plan
        case dryRun
        case reclaim
        case openReviewQueue
        case openPermissions
        case exportReport
    }

    let id: String
    let title: String
    let reason: String
    let systemImage: String
    let role: ButtonRole?
    let command: Command

    init(action: ActionCenterAction) {
        id = action.id
        title = action.title
        reason = action.reason
        systemImage = Self.iconName(for: action.kind)
        role = action.isDestructive ? .destructive : nil
        command = .actionCenter(action)
    }

    static func standard(
        id: String,
        title: String,
        reason: String,
        systemImage: String,
        role: ButtonRole? = nil,
        command: Command
    ) -> SummaryCommand {
        SummaryCommand(
            id: id,
            title: title,
            reason: reason,
            systemImage: systemImage,
            role: role,
            command: command
        )
    }

    private init(
        id: String,
        title: String,
        reason: String,
        systemImage: String,
        role: ButtonRole?,
        command: Command
    ) {
        self.id = id
        self.title = title
        self.reason = reason
        self.systemImage = systemImage
        self.role = role
        self.command = command
    }

    private static func iconName(for kind: ActionCenterActionKind) -> String {
        switch kind {
        case .grantAccess:
            "lock.shield"
        case .runScan:
            "magnifyingglass"
        case .reviewQueue:
            "tray.full"
        case .runDryRun:
            "play.circle"
        case .executeSafePlan:
            "trash"
        case .quitApp:
            "xmark.app"
        case .useNativeTool:
            "terminal"
        }
    }
}
