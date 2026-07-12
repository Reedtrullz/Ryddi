import SwiftUI
import ReclaimerCore

struct ReviewQueuesView: View {
    let model: DashboardModel
    let onOpenFinding: (Finding) -> Void
    let onNavigate: (DashboardSection) -> Void
    @State private var selectedQueue: ReviewQueueID
    @AppStorage(RyddiAppStorageKey.defaultReportPathStyle) private var defaultReportPathStyleRaw = ReportPathStyle.homeRelative.rawValue
    @AppStorage(RyddiAppStorageKey.redactUserTextByDefault) private var redactUserTextByDefault = false

    init(
        model: DashboardModel,
        onOpenFinding: @escaping (Finding) -> Void,
        onNavigate: @escaping (DashboardSection) -> Void
    ) {
        self.model = model
        self.onOpenFinding = onOpenFinding
        self.onNavigate = onNavigate
        _selectedQueue = State(initialValue: model.reviewedQueueID ?? .safeMaintenance)
    }

    private var report: ReviewQueueReport {
        model.reviewQueueReport
    }

    private var detailReport: ReviewQueueDetailReport {
        model.reviewQueueDetailReport(for: selectedQueue, limit: 40)
    }

    private var selectedPlanIDs: Set<Finding.ID> {
        Set(model.plan?.items.filter(\.selected).map { $0.finding.id } ?? [])
    }

    private var defaultReportPathStyle: ReportPathStyle {
        ReportPathStyle(rawValue: defaultReportPathStyleRaw) ?? .homeRelative
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        reviewQueueTitle
                        Spacer()
                        queuePicker
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        reviewQueueTitle
                        queuePicker
                    }
                }

                LazyVGrid(columns: DashboardResponsiveGrid.metricColumns, alignment: .leading, spacing: 12) {
                    ReviewQueueMetricCard(systemImage: "square.stack.3d.up", title: "Queued", value: "\(report.totalCount)", detail: "findings")
                    ReviewQueueMetricCard(systemImage: "folder", title: "Allocated", value: ByteFormat.string(report.totalAllocatedSize), detail: "reviewed")
                    ReviewQueueMetricCard(systemImage: "arrow.down.to.line.compact", title: "Estimated Reclaim", value: ByteFormat.string(report.estimatedImmediateReclaim), detail: "subject to checks", color: .green)
                    ReviewQueueMetricCard(systemImage: "target", title: "Selected Queue", value: "\(detailReport.count)", detail: detailReport.title, color: selectedQueue.reviewQueueAccentColor)
                    ReviewQueueMetricCard(systemImage: "doc.text.magnifyingglass", title: "Queue Bytes", value: ByteFormat.string(detailReport.allocatedSize), detail: "in selection")
                }

                if model.findings.isEmpty {
                    ContentUnavailableView("No scan yet", systemImage: "tray", description: Text("Run Scan to build your cleanup flow."))
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            ReviewQueueRail(
                                queues: report.queues,
                                selectedQueue: $selectedQueue,
                                onSelect: { model.recordReviewSelection($0) }
                            )
                            .frame(width: 300)

                            ReviewQueueDecisionPanel(
                                detailReport: detailReport,
                                selectedPlanIDs: selectedPlanIDs,
                                isWorking: model.isWorking,
                                hasFindings: !model.findings.isEmpty,
                                hasOverview: model.overview != nil,
                                canRunDryRun: model.plan != nil || !model.findings.isEmpty,
                                onBuildPlan: { Task { await model.buildPlan() } },
                                onDryRun: { Task { await model.runDryRun() } },
                                onExport: exportEvidenceReportUsingDefaults,
                                onOpenWorkflow: openSelectedQueueWorkflow,
                                onOpenFinding: onOpenFinding
                            )
                            .frame(width: 760)

                            Spacer(minLength: 0)
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            ReviewQueueRail(
                                queues: report.queues,
                                selectedQueue: $selectedQueue,
                                onSelect: { model.recordReviewSelection($0) }
                            )
                            ReviewQueueDecisionPanel(
                                detailReport: detailReport,
                                selectedPlanIDs: selectedPlanIDs,
                                isWorking: model.isWorking,
                                hasFindings: !model.findings.isEmpty,
                                hasOverview: model.overview != nil,
                                canRunDryRun: model.plan != nil || !model.findings.isEmpty,
                                onBuildPlan: { Task { await model.buildPlan() } },
                                onDryRun: { Task { await model.runDryRun() } },
                                onExport: exportEvidenceReportUsingDefaults,
                                onOpenWorkflow: openSelectedQueueWorkflow,
                                onOpenFinding: onOpenFinding
                            )
                        }
                    }
                }

                if let error = model.error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
        }
        .accessibilityIdentifier(AccessibilityID.cleanupFlow)
    }

    private func exportEvidenceReportUsingDefaults() {
        Task {
            await model.exportEvidenceReport(pathStyle: defaultReportPathStyle, redactUserText: redactUserTextByDefault)
        }
    }

    private func openSelectedQueueWorkflow() {
        switch selectedQueue {
        case .safeMaintenance:
            Task { await model.buildPlan() }
        case .quitAppFirst:
            onNavigate(.active)
        case .useNativeTool:
            let category = detailReport.dominantCategory.lowercased()
            onNavigate(category.contains("container") || category.contains("vm") ? .containers : .packages)
        case .valuableHistory:
            onNavigate(.largeOld)
        case .personalAppAssets:
            onNavigate(.policy)
        case .unknown:
            if let finding = detailReport.rows.first?.finding {
                onOpenFinding(finding)
            }
        }
    }

    private var reviewQueueTitle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cleanup Flow")
                .font(.largeTitle.bold())
            Text("Start with safe cleanup, handle app or tool blockers next, and keep valuable data outside cleanup plans.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var queuePicker: some View {
        HStack(spacing: 8) {
            Text("Queue")
                .foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { selectedQueue },
                set: { queue in
                    selectedQueue = queue
                    model.recordReviewSelection(queue)
                }
            )) {
                ForEach(ReviewQueueID.allCases) { queue in
                    Label(queue.title, systemImage: queue.reviewQueueSymbol)
                        .tag(queue)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 240)
        }
    }
}

struct ReviewQueueMetricCard: View {
    let systemImage: String
    let title: String
    let value: String
    let detail: String
    var color: Color = .accentColor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
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

struct ReviewQueueRail: View {
    let queues: [ReviewQueueSummary]
    @Binding var selectedQueue: ReviewQueueID
    let onSelect: (ReviewQueueID) -> Void

    var body: some View {
        SectionBox(title: "Your next steps") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(CleanupFlowStage.allCases) { stage in
                    VStack(alignment: .leading, spacing: 4) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stage.title)
                                .font(.caption.weight(.semibold))
                            Text(stage.guidance)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 10)

                        ForEach(queues.filter { $0.queueID.cleanupFlowStage == stage }) { queue in
                            Button {
                                selectedQueue = queue.queueID
                                modelRecordSelection(queue.queueID)
                            } label: {
                                ReviewQueueSummaryRow(queue: queue, isSelected: selectedQueue == queue.queueID)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(AccessibilityID.queue(queue.queueID))
                        }
                    }
                }
            }
            .accessibilityIdentifier("review-queues.list")
        }
    }

    private func modelRecordSelection(_ queueID: ReviewQueueID) {
        onSelect(queueID)
    }
}

struct ReviewQueueDecisionPanel: View {
    let detailReport: ReviewQueueDetailReport
    let selectedPlanIDs: Set<Finding.ID>
    let isWorking: Bool
    let hasFindings: Bool
    let hasOverview: Bool
    let canRunDryRun: Bool
    let onBuildPlan: () -> Void
    let onDryRun: () -> Void
    let onExport: () -> Void
    let onOpenWorkflow: () -> Void
    let onOpenFinding: (Finding) -> Void

    var body: some View {
        SectionBox(title: "Queue Workspace") {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider()
                metrics
                nextAction

                if detailReport.rows.isEmpty {
                    ContentUnavailableView("No findings in this queue", systemImage: "checkmark.circle", description: Text("This scan did not produce matching rows."))
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    ReviewQueueFindingTable(
                        rows: detailReport.rows,
                        selectedPlanIDs: selectedPlanIDs,
                        onOpenFinding: onOpenFinding
                    )
                }

                ReviewQueueEvidenceFooter(detailReport: detailReport)
            }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                headerText
                Spacer()
                statusPills
            }

            VStack(alignment: .leading, spacing: 10) {
                headerText
                statusPills
            }
        }
    }

    private var headerText: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: detailReport.queueID.reviewQueueSymbol)
                .font(.title3)
                .foregroundStyle(detailReport.queueID.reviewQueueAccentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(detailReport.title)
                    .font(.title3.bold())
                Text(detailReport.guidance)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusPills: some View {
        HStack(spacing: 8) {
            ReviewQueueStatusPill(text: detailReport.queueID.reviewQueueNextAction.label, color: detailReport.queueID.reviewQueueAccentColor)
            ReviewQueueStatusPill(text: detailReport.highestRiskClass?.label ?? "No risk", color: safetyColor)
            ReviewQueueStatusPill(text: "\(detailReport.rowCount)/\(detailReport.count) shown", color: .secondary)
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: DashboardResponsiveGrid.metricColumns, alignment: .leading, spacing: 10) {
            ReviewQueueMetricCard(systemImage: "number", title: "Count", value: "\(detailReport.count)", detail: "items", color: detailReport.queueID.reviewQueueAccentColor)
            ReviewQueueMetricCard(systemImage: "arrow.down.to.line.compact", title: "Reclaim", value: ByteFormat.string(detailReport.estimatedImmediateReclaim), detail: "estimate", color: .green)
            ReviewQueueMetricCard(systemImage: "exclamationmark.triangle", title: "Risk", value: detailReport.highestRiskClass?.label ?? "-", detail: "highest class", color: safetyColor)
            ReviewQueueMetricCard(systemImage: "tag", title: "Dominant", value: detailReport.dominantCategory, detail: detailReport.dominantAction?.label ?? "mixed")
        }
    }

    private var nextAction: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                nextActionText
                Spacer()
                actionButtons
            }

            VStack(alignment: .leading, spacing: 12) {
                nextActionText
                actionButtons
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(detailReport.queueID.reviewQueueAccentColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(detailReport.queueID.reviewQueueAccentColor.opacity(0.2), lineWidth: 1)
                )
        }
    }

    private var nextActionText: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal")
                .foregroundStyle(detailReport.queueID.reviewQueueAccentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text("Next action")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(detailReport.queueID.reviewQueueNextAction.label)
                    .font(.headline)
                Text(detailReport.queueID.reviewQueueNextAction.guidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            switch detailReport.queueID.cleanupFlowStage {
            case .safeCleanup:
                Button(action: onBuildPlan) {
                    Label("Build Safe Plan", systemImage: "checklist")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasFindings || isWorking)

                Button(action: onDryRun) {
                    Label("Dry Run", systemImage: "play.circle")
                }
                .buttonStyle(.bordered)
                .disabled(!canRunDryRun || isWorking)
            case .needsAction:
                Button(action: onOpenWorkflow) {
                    Label(detailReport.queueID.cleanupFlowActionLabel, systemImage: detailReport.queueID.cleanupFlowActionSymbol)
                }
                .buttonStyle(.borderedProminent)
                .disabled(detailReport.rows.isEmpty || isWorking)
            case .keepOrInspect:
                Button(action: onOpenWorkflow) {
                    Label(detailReport.queueID.cleanupFlowActionLabel, systemImage: detailReport.queueID.cleanupFlowActionSymbol)
                }
                .buttonStyle(.borderedProminent)
                .disabled(detailReport.rows.isEmpty || isWorking)
            }

            Button(action: onExport) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .disabled(!hasOverview || !hasFindings || isWorking)
        }
    }

    private var safetyColor: Color {
        switch detailReport.highestRiskClass {
        case .autoSafe: .green
        case .safeAfterCondition: .blue
        case .reviewRequired: .orange
        case .preserveByDefault: .purple
        case .neverTouch: .red
        case nil: .secondary
        }
    }
}

struct ReviewQueueFindingTable: View {
    let rows: [TopOffenderRow]
    let selectedPlanIDs: Set<Finding.ID>
    let onOpenFinding: (Finding) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ReviewQueueFindingHeader()
            ForEach(rows) { row in
                ReviewQueueFindingRow(
                    row: row,
                    isSelectedInPlan: selectedPlanIDs.contains(row.finding.id),
                    onOpenFinding: onOpenFinding
                )
            }
        }
    }
}

struct ReviewQueueFindingHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Reclaim").frame(width: 86, alignment: .leading)
            Text("Size").frame(width: 78, alignment: .leading)
            Text("Safety").frame(width: 112, alignment: .leading)
            Text("Owner").frame(width: 108, alignment: .leading)
            Text("Path").frame(maxWidth: .infinity, alignment: .leading)
            Text("Actions").frame(width: 132, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
    }
}

struct ReviewQueueFindingRow: View {
    let row: TopOffenderRow
    let isSelectedInPlan: Bool
    let onOpenFinding: (Finding) -> Void

    var body: some View {
        Divider()
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ByteFormat.string(row.estimatedImmediateReclaim))
                    .foregroundStyle(row.estimatedImmediateReclaim > 0 ? .green : .secondary)
                    .monospacedDigit()
                Text(row.reclaimabilityLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 86, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(ByteFormat.string(row.allocatedSize))
                    .lineLimit(1)
                Text(ByteFormat.string(row.logicalSize))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 78, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                SafetyBadge(safetyClass: row.safetyClass)
                Text(row.confidence.label + (isSelectedInPlan ? " • in plan" : ""))
                    .font(.caption2)
                    .foregroundStyle(confidenceColor)
                    .lineLimit(1)
            }
            .frame(width: 112, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.category)
                    .lineLimit(1)
                Text(row.ownerName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 108, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName)
                    .lineLimit(1)
                Text(row.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(row.nextAction.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(nextActionColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                Button {
                    onOpenFinding(row.finding)
                } label: {
                    Image(systemName: "info.circle")
                }
                .help("Open evidence detail")
                FindingActionButtons(finding: row.finding)
            }
            .buttonStyle(.borderless)
            .frame(width: 132, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }

    private var confidenceColor: Color {
        switch row.confidence {
        case .high: .green
        case .conditional: .blue
        case .review: .orange
        case .protected: .purple
        case .blocked: .red
        }
    }

    private var nextActionColor: Color {
        switch row.nextAction {
        case .safeMaintenance: .green
        case .quitAppFirst: .orange
        case .useNativeTool: .blue
        case .reviewInFinder, .archiveCandidate: .secondary
        case .protectByDefault, .doNotTouch: .red
        }
    }
}

struct ReviewQueueStatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct ReviewQueueEvidenceFooter: View {
    let detailReport: ReviewQueueDetailReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    blockedExplanation
                    Divider()
                    nonClaims
                }

                VStack(alignment: .leading, spacing: 14) {
                    blockedExplanation
                    nonClaims
                }
            }
        }
    }

    private var blockedExplanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Why blocked", systemImage: "lock.shield")
                .font(.headline)
            Text(detailReport.queueID.reviewQueueBlockedReason(estimatedImmediateReclaim: detailReport.estimatedImmediateReclaim))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                ReviewQueueBullet("Open-file checks, permissions, and dry-run receipts still decide what can enter a cleanup plan.")
                ReviewQueueBullet("The queue label is review evidence, not cleanup permission.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nonClaims: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Non-Claims")
                .font(.headline)
            ForEach(detailReport.nonClaims, id: \.self) { note in
                ReviewQueueBullet(note)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReviewQueueBullet: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ReviewQueueSummaryRow: View {
    let queue: ReviewQueueSummary
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : queue.queueID.reviewQueueAccentColor)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(queue.queueID.reviewQueueAccentColor.opacity(isSelected ? 0.95 : 0.14))
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(queue.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(queue.count) items")
                    Text("•")
                    Text(reviewQueueNextAction.label)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(ByteFormat.string(queue.allocatedSize))
                    .font(.caption.monospacedDigit().weight(.semibold))
                Text(ByteFormat.string(queue.estimatedImmediateReclaim))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(queue.estimatedImmediateReclaim > 0 ? .green : .secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? queue.queueID.reviewQueueAccentColor.opacity(0.18) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(rowBorderColor, lineWidth: isSelected ? 1 : 0)
                )
        }
        .contentShape(Rectangle())
        .help("\(queue.title): \(reviewQueueBlockedReason)")
    }

    private var symbol: String {
        queue.queueID.reviewQueueSymbol
    }

    private var reviewQueueNextAction: ReviewNextAction {
        queue.queueID.reviewQueueNextAction
    }

    private var reviewQueueBlockedReason: String {
        queue.queueID.reviewQueueBlockedReason(estimatedImmediateReclaim: queue.estimatedImmediateReclaim)
    }

    private var rowBorderColor: Color {
        isSelected
            ? queue.queueID.reviewQueueAccentColor.opacity(0.28)
            : Color(nsColor: .separatorColor).opacity(0.18)
    }
}

private extension ReviewQueueID {
    var reviewQueueSymbol: String {
        switch self {
        case .safeMaintenance: "checkmark.shield"
        case .quitAppFirst: "pause.circle"
        case .useNativeTool: "terminal"
        case .valuableHistory: "archivebox"
        case .personalAppAssets: "person.crop.square"
        case .unknown: "questionmark.circle"
        }
    }

    var reviewQueueAccentColor: Color {
        switch self {
        case .safeMaintenance: .blue
        case .quitAppFirst: .orange
        case .useNativeTool: .blue
        case .valuableHistory: .purple
        case .personalAppAssets: .purple
        case .unknown: .secondary
        }
    }

    var reviewQueueNextAction: ReviewNextAction {
        switch self {
        case .safeMaintenance: .safeMaintenance
        case .quitAppFirst: .quitAppFirst
        case .useNativeTool: .useNativeTool
        case .valuableHistory: .archiveCandidate
        case .personalAppAssets: .protectByDefault
        case .unknown: .reviewInFinder
        }
    }

    var cleanupFlowActionLabel: String {
        switch self {
        case .safeMaintenance: "Build Safe Plan"
        case .quitAppFirst: "Review Active Apps"
        case .useNativeTool: "Open Native Cleanup"
        case .valuableHistory: "Review Archives"
        case .personalAppAssets: "Review Protections"
        case .unknown: "Inspect Largest Item"
        }
    }

    var cleanupFlowActionSymbol: String {
        switch self {
        case .safeMaintenance: "checklist"
        case .quitAppFirst: "xmark.app"
        case .useNativeTool: "terminal"
        case .valuableHistory: "archivebox"
        case .personalAppAssets: "hand.raised"
        case .unknown: "magnifyingglass"
        }
    }

    func reviewQueueBlockedReason(estimatedImmediateReclaim: Int64) -> String {
        switch self {
        case .safeMaintenance:
            estimatedImmediateReclaim > 0
                ? "Blocked until this selection has a matching clean dry-run receipt."
                : "No auto-safe reclaim bytes are selected in this queue yet."
        case .quitAppFirst:
            "Open-file or owner-app evidence must clear before this can enter a safe plan."
        case .useNativeTool:
            "Tool-owned storage needs its native cleanup flow; Ryddi will not infer permission from the row label."
        case .valuableHistory:
            "History and archive candidates need manual value review before cleanup."
        case .personalAppAssets:
            "Personal and app assets stay preserve-first unless explicit evidence reclassifies them."
        case .unknown:
            "Ambiguous findings need manual inspection before any cleanup plan."
        }
    }
}
