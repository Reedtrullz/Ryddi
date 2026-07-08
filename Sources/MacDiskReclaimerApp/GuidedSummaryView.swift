import SwiftUI
import ReclaimerCore

struct GuidedSummaryView: View {
    let model: DashboardModel
    let report: GuidedWorkflowReport
    let onReclaim: () -> Void
    let navigate: (String) -> Void

    var body: some View {
        SectionBox(title: "Next Safe Action") {
            VStack(alignment: .leading, spacing: 14) {
                primaryAction
                safetyTotals
            }
        }
    }

    private var primaryAction: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                primaryActionText
                Spacer(minLength: 12)
                actionButtons
            }

            VStack(alignment: .leading, spacing: 12) {
                primaryActionText
                actionButtons
            }
        }
    }

    private var primaryActionText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(report.primaryAction.title, systemImage: iconName(for: report.primaryAction.kind))
                .font(.title3.weight(.semibold))
                .lineLimit(2)
            Text(report.explanation)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if report.primaryAction.estimatedBytes > 0 {
                Text("Estimated scope: \(ByteFormat.string(report.primaryAction.estimatedBytes))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var actionButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                primaryButton
                secondaryButtons
            }

            VStack(alignment: .leading, spacing: 10) {
                primaryButton
                secondaryButtons
            }
        }
    }

    private var primaryButton: some View {
        Button(role: report.primaryAction.isDestructive ? .destructive : nil) {
            performGuidedAction(report.primaryAction.kind)
        } label: {
            Label(report.primaryAction.title, systemImage: iconName(for: report.primaryAction.kind))
                .frame(minWidth: 148)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isActionDisabled(report.primaryAction.kind))
    }

    @ViewBuilder
    private var secondaryButtons: some View {
        ForEach(report.secondaryActions, id: \.self) { action in
            Button(role: action.isDestructive ? .destructive : nil) {
                performGuidedAction(action.kind)
            } label: {
                Label(action.title, systemImage: iconName(for: action.kind))
                    .frame(minWidth: 132)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isActionDisabled(action.kind))
        }
    }

    private var safetyTotals: some View {
        LazyVGrid(columns: DashboardResponsiveGrid.metricColumns, spacing: 12) {
            MetricTile(title: ReviewNextAction.safeMaintenance.label, value: bytes(for: .safeMaintenance))
            MetricTile(title: ReviewNextAction.quitAppFirst.label, value: bytes(for: .quitAppFirst))
            MetricTile(title: ReviewNextAction.useNativeTool.label, value: bytes(for: .useNativeTool))
            MetricTile(title: "Review/Archive", value: reviewArchiveBytes)
            MetricTile(title: ReviewNextAction.protectByDefault.label, value: bytes(for: .protectByDefault))
            MetricTile(title: ReviewNextAction.doNotTouch.label, value: bytes(for: .doNotTouch))
        }
    }

    private var reviewArchiveBytes: String {
        let bytes = report.safetyTotals[.reviewInFinder, default: 0]
            + report.safetyTotals[.archiveCandidate, default: 0]
        return ByteFormat.string(bytes)
    }

    private func bytes(for action: ReviewNextAction) -> String {
        ByteFormat.string(report.safetyTotals[action, default: 0])
    }

    private func performGuidedAction(_ kind: GuidedWorkflowActionKind) {
        switch kind {
        case .openPermissions:
            navigate("Permissions")
        case .runScan:
            Task { await model.scan() }
        case .openReviewQueues:
            navigate("Queues")
        case .createSafePlan:
            Task { await model.buildPlan() }
        case .runDryRun:
            Task { await model.runDryRun() }
        case .reclaimSafely:
            onReclaim()
        case .exportReport:
            Task { await model.exportEvidenceReport(pathStyle: .redacted, redactUserText: true) }
        case .openRecovery:
            navigate("Recovery")
        }
    }

    private func isActionDisabled(_ kind: GuidedWorkflowActionKind) -> Bool {
        if model.isWorking {
            return true
        }
        switch kind {
        case .openPermissions, .runScan, .openRecovery:
            return false
        case .openReviewQueues:
            return model.findings.isEmpty
        case .createSafePlan:
            return model.findings.isEmpty
        case .runDryRun:
            return model.plan == nil && model.findings.isEmpty
        case .reclaimSafely:
            return !model.canReclaimSelected
        case .exportReport:
            return model.overview == nil || model.findings.isEmpty
        }
    }

    private func iconName(for kind: GuidedWorkflowActionKind) -> String {
        switch kind {
        case .openPermissions:
            "lock.shield"
        case .runScan:
            "magnifyingglass"
        case .openReviewQueues:
            "tray.full"
        case .createSafePlan:
            "checklist"
        case .runDryRun:
            "play.circle"
        case .reclaimSafely:
            "trash"
        case .exportReport:
            "square.and.arrow.up"
        case .openRecovery:
            "arrow.uturn.backward.circle"
        }
    }
}
