import SwiftUI
import ReclaimerCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct OverviewView: View {
    let model: DashboardModel
    let navigate: (String) -> Void

    private var topRows: [TopOffenderRow] {
        Array(model.presentationSnapshot?.topOffenders.rows.prefix(8) ?? [])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DashboardHeroView(model: model)

                if model.isWorking {
                    ProgressView("Working")
                        .controlSize(.large)
                }
                if model.isUpdatingPresentation {
                    ProgressView("Updating results")
                        .controlSize(.small)
                }

                GuidedSummaryView(
                    model: model,
                    report: model.actionCenterReport,
                    navigate: navigate
                )

                if model.permissionReport.needsFullDiskAccessReview || model.permissionReport.unknownCount > 0 {
                    PermissionAccessBanner(
                        report: model.permissionReport,
                        onReviewPermissions: { navigate("Permissions") }
                    )
                }

                if let error = model.error {
                    DashboardAlert(message: error, systemImage: "exclamationmark.triangle.fill")
                }

                LazyVGrid(columns: DashboardResponsiveGrid.metricColumns, spacing: 12) {
                    MetricTile(title: "Findings", value: "\(model.findings.count)")
                    MetricTile(title: "Auto-safe", value: ByteFormat.string(model.totalBytes(for: .autoSafe)))
                    MetricTile(title: "Needs review", value: ByteFormat.string(model.totalReviewBytes))
                    MetricTile(title: "Plan reclaim", value: ByteFormat.string(model.plan?.expectedImmediateReclaim ?? 0))
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        DashboardQueuePanel(model: model, navigate: navigate)
                            .frame(minWidth: 330)
                        DashboardReviewLauncher(model: model, navigate: navigate)
                            .frame(minWidth: 330)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        DashboardQueuePanel(model: model, navigate: navigate)
                        DashboardReviewLauncher(model: model, navigate: navigate)
                    }
                }

                if !topRows.isEmpty {
                    SectionBox(title: "Largest Current Findings") {
                        TopOffenderTableScrollContainer {
                            ForEach(topRows) { row in
                                TopOffenderRowView(row: row, isSelectedInPlan: model.plan?.items.contains { $0.finding.id == row.finding.id && $0.selected } ?? false)
                            }
                        }
                        HStack {
                            Spacer()
                            Button {
                                navigate("LargeOld")
                            } label: {
                                Label("Open Large & Old Files", systemImage: "archivebox")
                            }
                        }
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        TrustReadinessCardsView(
                            report: model.trustReadinessReport,
                            onReviewPermissions: { navigate("Permissions") }
                        )
                        ScanScopePreviewView(plan: model.selectedScopePlan, lastScannedLabel: model.lastScannedScopeLabel)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        TrustReadinessCardsView(
                            report: model.trustReadinessReport,
                            onReviewPermissions: { navigate("Permissions") }
                        )
                        ScanScopePreviewView(plan: model.selectedScopePlan, lastScannedLabel: model.lastScannedScopeLabel)
                    }
                }

                if let overview = model.overview {
                    PermissionCoverageView(report: model.permissionReport)
                    GrowthHistoryView(
                        snapshots: model.scanSnapshots,
                        deltas: model.growthDeltas,
                        onExport: { Task { await model.exportGrowthReport() } },
                        onExportRedacted: { Task { await model.exportGrowthReport(pathStyle: .redacted) } }
                    )
                    OwnerStorageView(summaries: overview.ownerSummaries)
                }

                DashboardPlanPanel(model: model)
                DashboardRecentExports(model: model)
            }
            .padding(24)
            .frame(maxWidth: 1220, alignment: .leading)
        }
    }
}

struct DashboardHeroView: View {
    let model: DashboardModel

    var body: some View {
        SectionBox(title: "Disk Status") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    diskSummary
                    Spacer(minLength: 16)
                    heroMetrics
                        .frame(minWidth: 190, alignment: .trailing)
                }

                VStack(alignment: .leading, spacing: 14) {
                    diskSummary
                    heroMetrics
                }
            }
        }
    }

    private var diskSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(model.diskStatus.statusLine)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.82)
                    .lineLimit(1)
                Text(model.diskStatus.pressure.label)
                    .font(.headline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(pressureColor)
                    .background(pressureColor.opacity(0.18), in: Capsule())
            }
            Text(model.diskStatus.path)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Text("Last scan \(model.lastScanDate?.formatted(date: .omitted, time: .shortened) ?? "not run")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var heroMetrics: some View {
        VStack(alignment: .trailing, spacing: 8) {
            MetricInline(title: "Coverage", value: model.permissionReport.coverageLevel.label)
            MetricInline(title: "Automation", value: model.launchAgentStatus.installed ? "Report-only" : "Off")
            MetricInline(title: "Audit", value: auditSummary)
        }
    }

    private var auditSummary: String {
        guard let summary = model.auditStoreSummary else { return "Not loaded" }
        return "\(summary.totalKnownFileCount) files"
    }

    private var pressureColor: Color {
        switch model.diskStatus.pressure {
        case .healthy: .green
        case .warning: .orange
        case .critical: .red
        case .unknown: .secondary
        }
    }
}

struct DashboardActionStrip: View {
    let model: DashboardModel
    let navigate: (String) -> Void
    @AppStorage(RyddiAppStorageKey.defaultReportPathStyle) private var defaultReportPathStyleRaw = ReportPathStyle.homeRelative.rawValue
    @AppStorage(RyddiAppStorageKey.redactUserTextByDefault) private var redactUserTextByDefault = false

    private var defaultReportPathStyle: ReportPathStyle {
        ReportPathStyle(rawValue: defaultReportPathStyleRaw) ?? .homeRelative
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                actionButtons
            }

            LazyVGrid(columns: DashboardResponsiveGrid.actionColumns, alignment: .leading, spacing: 10) {
                actionButtons
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        DashboardActionButton("Scan", systemImage: "magnifyingglass", prominent: true, disabled: model.isWorking) {
            model.startScan()
        }
        .accessibilityIdentifier("summary.scan-button")
        DashboardActionButton("Plan", systemImage: "checklist", disabled: model.findings.isEmpty || model.isWorking) {
            Task { await model.buildPlan() }
        }
        .accessibilityIdentifier("summary.plan-button")
        DashboardActionButton("Dry Run", systemImage: "play.circle", disabled: (model.plan == nil && model.findings.isEmpty) || model.isWorking) {
            Task { await model.runDryRun() }
        }
        .accessibilityIdentifier("summary.dry-run-button")
        DashboardActionButton("Cleanup Flow", systemImage: "arrow.right.circle", disabled: model.findings.isEmpty) {
            navigate("Queues")
        }
        .accessibilityIdentifier("summary.manual-review-button")
        DashboardActionButton("Export", systemImage: "square.and.arrow.up", disabled: model.overview == nil || model.findings.isEmpty || model.isWorking) {
            exportEvidenceReportUsingDefaults()
        }
    }

    private func exportEvidenceReportUsingDefaults() {
        Task {
            await model.exportEvidenceReport(pathStyle: defaultReportPathStyle, redactUserText: redactUserTextByDefault)
        }
    }
}

struct DashboardActionButton: View {
    let title: String
    let systemImage: String
    let role: ButtonRole?
    let prominent: Bool
    let disabled: Bool
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        prominent: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.prominent = prominent
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        if prominent {
            Button(role: role, action: action) {
                Label(title, systemImage: systemImage)
                    .frame(minWidth: 88)
            }
            .buttonStyle(.borderedProminent)
            .disabled(disabled)
            .controlSize(.large)
        } else {
            Button(role: role, action: action) {
                Label(title, systemImage: systemImage)
                    .frame(minWidth: 88)
            }
            .buttonStyle(.bordered)
            .disabled(disabled)
            .controlSize(.large)
        }
    }
}

struct PermissionAccessBanner: View {
    let report: PermissionAdvisorReport
    let onReviewPermissions: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                bannerIcon
                bannerCopy
                Spacer(minLength: 12)
                bannerButtons
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    bannerIcon
                    bannerCopy
                }
                bannerButtons
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                )
        }
    }

    private var bannerIcon: some View {
        Image(systemName: "lock.shield")
            .font(.title3)
            .foregroundStyle(.orange)
            .frame(width: 28)
    }

    private var bannerCopy: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(report.needsFullDiskAccessReview ? "Full Disk Access review recommended" : "Permission coverage needs refresh")
                .font(.headline)
            Text(report.coverageSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bannerButtons: some View {
        LazyVGrid(columns: DashboardResponsiveGrid.actionColumns, alignment: .leading, spacing: 10) {
            Button {
                PathActions.openFullDiskAccessSettings()
            } label: {
                Label("Open Full Disk Access", systemImage: "lock.shield")
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            Button {
                onReviewPermissions()
            } label: {
                Label("Review Permissions", systemImage: "arrow.right.circle")
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: 390, alignment: .leading)
    }
}

struct DashboardQueuePanel: View {
    let model: DashboardModel
    let navigate: (String) -> Void

    var body: some View {
        SectionBox(title: "Cleanup Flow") {
            VStack(spacing: 8) {
                ForEach(model.queueSummaries.prefix(6)) { queue in
                    Button {
                        model.recordReviewSelection(queue.queueID)
                        navigate("Queues")
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(queue.title)
                                .font(.headline)
                            Spacer()
                            Text("\(queue.count)")
                                .font(.headline.monospacedDigit())
                            Text(ByteFormat.string(queue.allocatedSize))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }
}

struct DashboardReviewLauncher: View {
    let model: DashboardModel
    let navigate: (String) -> Void

    var body: some View {
        SectionBox(title: "Quick Reviews") {
            VStack(spacing: 8) {
                ReviewLaunchRow(title: "Downloads", value: model.downloadsReview.map { ByteFormat.string($0.reviewCandidateBytes) } ?? "-", systemImage: "arrow.down.circle") {
                    Task {
                        await model.reviewDownloads()
                        navigate("Downloads")
                    }
                }
                ReviewLaunchRow(title: "Browser Caches", value: model.browserCacheReview.map { ByteFormat.string($0.candidateBytes) } ?? "-", systemImage: "globe") {
                    Task {
                        await model.reviewBrowserCaches()
                        navigate("Browsers")
                    }
                }
                ReviewLaunchRow(title: "Package Caches", value: model.packageCacheReview.map { ByteFormat.string($0.candidateBytes) } ?? "-", systemImage: "shippingbox") {
                    Task {
                        await model.reviewPackageCaches()
                        navigate("Packages")
                    }
                }
                ReviewLaunchRow(title: "Project Dependencies", value: model.projectDependencyReview.map { ByteFormat.string($0.candidateBytes) } ?? "-", systemImage: "folder") {
                    Task {
                        await model.reviewProjectDependencies()
                        navigate("Projects")
                    }
                }
                ReviewLaunchRow(title: "Trash", value: model.trashReview.map { ByteFormat.string($0.totalAllocatedSize) } ?? "-", systemImage: "trash") {
                    Task {
                        await model.reviewTrash()
                        navigate("Trash")
                    }
                }
            }
            .disabled(model.isWorking)
        }
    }
}

struct ReviewLaunchRow: View {
    let title: String
    let value: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Divider()
    }
}

struct DashboardPlanPanel: View {
    let model: DashboardModel

    var body: some View {
        SectionBox(title: "Plan") {
            if let plan = model.plan {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        MetricTile(title: "Selected", value: "\(plan.items.filter(\.selected).count)")
                        MetricTile(title: "Expected reclaim", value: ByteFormat.string(plan.expectedImmediateReclaim))
                        MetricTile(title: "Dry run", value: model.lastDryRunReceipt?.errors.isEmpty == true ? "Recorded" : "Needed")
                        MetricTile(title: "Errors", value: "\(model.lastDryRunReceipt?.errors.count ?? 0)")
                    }
                    ForEach(plan.dryRunSummary.prefix(8), id: \.self) { line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    HStack {
                        Button {
                            Task { await model.runDryRun() }
                        } label: {
                            Label("Dry Run", systemImage: "play.circle")
                        }
                        Button {
                            Task { await model.exportPlanReport(plan, pathStyle: .redacted) }
                        } label: {
                            Label("Export Redacted Plan", systemImage: "eye.slash")
                        }
                        Label("Manual Finder removal required", systemImage: "hand.raised")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack {
                    Label("No plan built", systemImage: "checklist")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await model.buildPlan() }
                    } label: {
                        Label("Build Plan", systemImage: "checklist")
                    }
                    .disabled(model.findings.isEmpty || model.isWorking)
                }
            }
        }
    }
}

struct DashboardRecentExports: View {
    let model: DashboardModel

    var body: some View {
        let exports = [
            ("Evidence report", model.lastReportExportURL),
            ("Growth report", model.lastGrowthReportExportURL),
            ("Archive review", model.lastArchiveReviewExportURL),
            ("Plan report", model.lastPlanReportExportURL),
            ("Diagnostic summary", model.lastDiagnosticExportURL)
        ].compactMap { label, url in
            url.map { (label, $0) }
        }

        if !exports.isEmpty {
            SectionBox(title: "Recent Exports") {
                ForEach(exports, id: \.1) { label, url in
                    HStack {
                        Text(label)
                            .font(.caption.weight(.semibold))
                        Text(url.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}

struct DashboardAlert: View {
    let message: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
            Text(message)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct MetricInline: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .font(.caption)
    }
}

struct TrustReadinessCardsView: View {
    let report: TrustReadinessReport
    let onReviewPermissions: () -> Void

    var body: some View {
        SectionBox(title: "Trust Readiness") {
            LazyVGrid(columns: DashboardResponsiveGrid.metricColumns, spacing: 12) {
                MetricTile(title: "Disk Pressure", value: report.diskStatus.pressure.label)
                MetricTile(title: "Scan Coverage", value: report.scanCoverage?.state.label ?? report.permissionSummary.coverageLevel.label)
                MetricTile(title: "Safe Reclaim", value: ByteFormat.string(report.latestPlanSummary?.expectedImmediateReclaim ?? 0))
                MetricTile(title: "Automation", value: report.automationInstalled ? "Report-only" : "Off")
                MetricTile(title: "Quit First", value: countActions(.quitAppFirst))
                MetricTile(title: "Native Tool", value: countActions(.useNativeTool))
                MetricTile(title: "Valuable History", value: countActions(.protectByDefault))
                MetricTile(title: "Signature", value: report.runtimeReleaseTrustReport?.signatureSummary ?? "Loading...")
                MetricTile(title: "Gatekeeper", value: report.runtimeReleaseTrustReport?.gatekeeperSummary ?? "Loading...")
                MetricTile(title: "External Manifest", value: report.runtimeReleaseTrustReport?.externalManifestSummary ?? "Loading...")
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(report.recommendedActions.prefix(5)) { action in
                    TrustReadinessActionRow(
                        action: action,
                        symbol: symbol(for: action.severity),
                        color: color(for: action.severity),
                        onReviewPermissions: onReviewPermissions
                    )
                }
            }
        }
    }

    private func countActions(_ action: ReviewNextAction) -> String {
        let count = report.nextActionCounts[action.rawValue] ?? 0
        return count == 0 ? "0" : "\(count)"
    }

    private func symbol(for severity: TrustReadinessSeverity) -> String {
        switch severity {
        case .ready: "checkmark.circle"
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .blocked: "xmark.octagon"
        }
    }

    private func color(for severity: TrustReadinessSeverity) -> Color {
        switch severity {
        case .ready: .green
        case .info: .blue
        case .warning: .orange
        case .blocked: .red
        }
    }
}

struct TrustReadinessActionRow: View {
    let action: TrustReadinessAction
    let symbol: String
    let color: Color
    let onReviewPermissions: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 6) {
                Text(action.title)
                    .font(.caption.weight(.semibold))
                Text(action.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if action.id == "permissions.review-full-disk-access" {
                    HStack(spacing: 8) {
                        Button {
                            PathActions.openFullDiskAccessSettings()
                        } label: {
                            Label("Open Full Disk Access", systemImage: "lock.shield")
                        }
                        Button {
                            onReviewPermissions()
                        } label: {
                            Label("Review Permissions", systemImage: "arrow.right.circle")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
}

struct ScanScopePreviewView: View {
    let plan: ScanScopePlan
    let lastScannedLabel: String?

    var body: some View {
        SectionBox(title: "Scan Scope") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    MetricTile(title: "Mode", value: plan.label)
                    MetricTile(title: "Roots", value: "\(plan.scopes.count)")
                    MetricTile(title: "Last scanned", value: lastScannedLabel ?? "Never")
                }
                Text(plan.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(plan.scopes.prefix(10)) { scope in
                    HStack(alignment: .firstTextBaseline) {
                        Text(scope.name)
                            .font(.caption.weight(.semibold))
                            .frame(width: 190, alignment: .leading)
                        Text(scope.root.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                if plan.scopes.count > 10 {
                    Text("\(plan.scopes.count - 10) more root(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(plan.nonClaims.prefix(2), id: \.self) { note in
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct SavedScopeSetView: View {
    let model: DashboardModel
    @State private var newName = ""
    @State private var newSummary = ""
    @State private var replaceOnImport = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Scope Sets")
                    .font(.largeTitle.bold())
                Text("Reusable scan roots for general Mac cleanup, project-specific review, and developer maintenance.")
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    MetricTile(title: "Saved", value: "\(model.savedScopeSets.count)")
                    MetricTile(title: "Templates", value: "\(model.scopeTemplates.count)")
                    MetricTile(title: "Active", value: model.selectedScopePlan.label)
                    MetricTile(title: "Roots", value: "\(model.selectedScopePlan.scopes.count)")
                    MetricTile(title: "Config", value: SavedScopeSetStore().scopeSetURL.lastPathComponent)
                }

                SectionBox(title: "Built-In Templates") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Templates are guided scan roots for common general-cleaner and developer-cleaner reviews. Use one directly, or save it as a local scope set before customizing.")
                            .foregroundStyle(.secondary)
                        ForEach(model.scopeTemplates) { template in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(template.name)
                                            .font(.headline)
                                        Text("\(template.group) - \(template.recommendedUse)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        model.setScopeTemplate(template.id)
                                    } label: {
                                        Label(model.selectedScopeTemplateID == template.id ? "Selected" : "Use", systemImage: "scope")
                                    }
                                    .disabled(model.selectedScopeTemplateID == template.id)
                                    Button {
                                        model.saveScopeTemplate(template)
                                    } label: {
                                        Label("Save Copy", systemImage: "plus")
                                    }
                                }
                                Text(template.summary)
                                    .foregroundStyle(.secondary)
                                Text("\(template.scopes.count) root(s)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                            Divider()
                        }
                        ForEach(ScopeTemplateCatalog.defaultNonClaims, id: \.self) { note in
                            Text(note)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                SectionBox(title: "Create From Current Scope") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            TextField("Name", text: $newName)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 260)
                            TextField("Summary", text: $newSummary)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                model.saveCurrentScopeSet(name: newName, summary: newSummary)
                                if model.error == nil {
                                    newName = ""
                                    newSummary = ""
                                }
                            } label: {
                                Label("Save", systemImage: "plus")
                            }
                            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        ScanScopeMiniList(scopes: model.selectedScopePlan.scopes)
                    }
                }

                SectionBox(title: "Import And Export") {
                    HStack(spacing: 12) {
                        Button {
                            importSavedScopeSets()
                        } label: {
                            Label("Import JSON", systemImage: "square.and.arrow.down")
                        }
                        Toggle("Replace", isOn: $replaceOnImport)
                            .toggleStyle(.checkbox)
                        Button {
                            Task { await model.exportSavedScopeSets() }
                        } label: {
                            Label("Export JSON", systemImage: "square.and.arrow.up")
                        }
                        .disabled(model.savedScopeSets.isEmpty)
                        Button {
                            #if os(macOS)
                            NSWorkspace.shared.activateFileViewerSelecting([SavedScopeSetStore().scopeSetURL])
                            #endif
                        } label: {
                            Label("Reveal File", systemImage: "folder")
                        }
                        .disabled(model.savedScopeSets.isEmpty)
                    }
                    .buttonStyle(.bordered)

                    if let result = model.lastScopeSetImportResult {
                        Text("Imported \(result.importedSetCount) set(s), final saved sets: \(result.finalSetCount).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let url = model.lastScopeSetExportURL {
                        Text(url.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    ForEach(SavedScopeSetDocument.defaultNonClaims, id: \.self) { note in
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if model.savedScopeSets.isEmpty {
                    ContentUnavailableView("No saved scope sets", systemImage: "folder.badge.plus", description: Text("Choose a preset or scan roots, then save the current scope for reuse."))
                } else {
                    ForEach(model.savedScopeSets) { set in
                        SectionBox(title: set.name) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(set.summary ?? "Saved custom scan scope set with explicit local roots.")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button {
                                        model.setSavedScopeSet(set.id)
                                    } label: {
                                        Label(model.selectedSavedScopeSetID == set.id ? "Selected" : "Use", systemImage: "scope")
                                    }
                                    .disabled(model.selectedSavedScopeSetID == set.id)
                                    Button(role: .destructive) {
                                        model.removeSavedScopeSet(set)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                                HStack {
                                    Text("Updated \(set.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                    Text(set.id)
                                        .font(.caption2.monospaced())
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                ScanScopeMiniList(scopes: set.scopes)
                            }
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
        .onAppear {
            model.loadSavedScopeSets()
        }
    }

    private func importSavedScopeSets() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a Ryddi saved scope set JSON file."
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        model.importSavedScopeSets(from: url, replace: replaceOnImport)
        #endif
    }
}

struct ScanScopeMiniList: View {
    let scopes: [ScanScope]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(scopes.prefix(12)) { scope in
                HStack(alignment: .firstTextBaseline) {
                    Text(scope.name)
                        .font(.caption.weight(.semibold))
                        .frame(width: 190, alignment: .leading)
                    Text(scope.root.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            if scopes.count > 12 {
                Text("\(scopes.count - 12) more root(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CapabilityMatrixView: View {
    private let rows = [
        ("Choose scan mode", "Shared presets, built-in templates, and saved custom scope sets cover Developer, General Mac, All, and guided review roots before scanning."),
        ("Find space offenders", "Bounded Swift scanner over preset or custom roots with size and permission evidence."),
        ("Classify safety", "Versioned JSON rules produce Auto-safe, Safe after condition, Review required, Preserve by default, and Never touch."),
        ("Inspect rules", "Bundled rules can be reviewed by safety class, action, category, match hints, conditions, recovery, and non-claims."),
        ("Explain every item", "Finding detail shows owner hints, rule matches, evidence, recovery, and conditions."),
        ("Review everyday storage", "Downloads, browser caches, package caches, device backups, and Trash have report-only lanes with local audit records."),
        ("Review duplicates", "Local content hashes group identical regular files as manual review signals, never cleanup actions."),
        ("Review apps & leftovers", "Installed app support files and orphan candidates are surfaced as guidance, not uninstall actions."),
        ("Inventory containers", "Read-only Docker and Colima inspection records images, volumes, build cache estimates, profiles, and command outcomes."),
        ("Review AI agent storage", "Codex, Claude, Cursor, Windsurf, and Ollama roots are bucketed into reclaimable cache, quit-first data, valuable history, protected state, and manual review."),
        ("Explain permissions", "Coverage advisor shows readable, denied, missing, and unknown scopes with Full Disk Access guidance and non-claims."),
        ("Honor user policy", "Local exclusions hide noisy paths from scans; protections keep paths visible but blocked from cleanup."),
        ("Export reports", "Local Markdown evidence, plan, and receipt reports capture scan coverage, proposed actions, saved outcomes, path privacy controls, and non-claims."),
        ("Protect active files", "Plan/executor run open-file checks, active-handle review surfaces process names, and active paths are skipped."),
        ("Plan before action", "CLI and app build dry-run plans; automation is report-first."),
        ("Export receipts", "Saved dry-run and execution receipts can be exported as local Markdown reports with action counts and non-claims."),
        ("Manual cleanup evidence", "Ryddi keeps core filesystem actions report-first and opens reviewed items for manual Finder recovery."),
        ("Schedule maintenance", "Per-user LaunchAgent writes report-only plans for the selected preset, template, or saved scope set, no root helper."),
        ("Keep audit trail", "Plans and receipts are stored locally under Application Support."),
        ("Protect personal value", "Codex history, browser profiles, GarageBand/Logic assets, documents, credentials, and VM/container state are preserve/never-touch by default.")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Feature Matrix")
                    .font(.largeTitle.bold())
                Text("The MVP is developer-first, but the product model is a general Mac cleaner that keeps review and reversibility ahead of one-click cleanup.")
                    .foregroundStyle(.secondary)

                ForEach(rows, id: \.0) { title, solution in
                    SectionBox(title: title) {
                        Text(solution)
                    }
                }
            }
            .padding(24)
        }
    }
}

struct RuleCatalogView: View {
    @State private var catalogResult: Result<RuleCatalogReport, Error> = Result { try RuleEngine.bundled().catalog() }
    @State private var userRuleDocumentResult: Result<UserRulePackDocument, Error> = Result { try UserRulePackStore().loadDocument() }
    @State private var userRuleCatalogResult: Result<RuleCatalogReport, Error> = Result { try RuleEngine.bundled(includingUserRules: true).catalog() }
    @State private var userRulePreview: UserRulePackPreview?
    @State private var userRuleImportResult: UserRulePackImportResult?
    @State private var lastUserRuleExportURL: URL?
    @State private var userRuleError: String?

    var body: some View {
        ScrollView {
            switch catalogResult {
            case .success(let catalog):
                VStack(alignment: .leading, spacing: 16) {
                    Text("Rule Catalog")
                        .font(.largeTitle.bold())
                    HStack(spacing: 16) {
                        MetricTile(title: "Version", value: catalog.ruleVersion)
                        MetricTile(title: "Rules", value: "\(catalog.ruleCount)")
                        MetricTile(title: "User rules", value: "\(userRuleCount)")
                        MetricTile(title: "Safety buckets", value: "\(catalog.safetySummaries.count)")
                        MetricTile(title: "Categories", value: "\(catalog.categorySummaries.count)")
                    }

                    SectionBox(title: "Local User Rules") {
                        switch userRuleDocumentResult {
                        case .success(let document):
                            HStack(spacing: 12) {
                                Button {
                                    previewUserRulePack()
                                } label: {
                                    Label("Preview JSON", systemImage: "doc.text.magnifyingglass")
                                }

                                Button {
                                    importPreviewedUserRulePack()
                                } label: {
                                    Label("Import Preview", systemImage: "square.and.arrow.down")
                                }
                                .disabled(userRulePreview?.isImportable != true)

                                Button {
                                    exportUserRulePack()
                                } label: {
                                    Label("Export Rules", systemImage: "square.and.arrow.up")
                                }
                                .disabled(document.rules.isEmpty)

                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([UserRulePackStore().rulePackURL])
                                } label: {
                                    Label("Reveal File", systemImage: "folder")
                                }
                                .disabled(document.rules.isEmpty)
                            }
                            .buttonStyle(.bordered)

                            HStack {
                                MetricTile(title: "Installed", value: "\(document.rules.count)")
                                MetricTile(title: "Rule file", value: UserRulePackStore().rulePackURL.lastPathComponent)
                                MetricTile(title: "Included by default", value: "No")
                            }

                            switch userRuleCatalogResult {
                            case .success(let combinedCatalog):
                                HStack {
                                    Text("Combined catalog")
                                    Spacer()
                                    Text("\(combinedCatalog.ruleCount) rules")
                                        .monospacedDigit()
                                }
                                .font(.caption)
                            case .failure(let error):
                                Text(error.localizedDescription)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            if let result = userRuleImportResult {
                                Text("Imported \(result.importedRuleCount) rule(s), final local rules: \(result.finalRuleCount). User rules remain opt-in per scan.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let url = lastUserRuleExportURL {
                                Text(url.path)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            ForEach(document.nonClaims, id: \.self) { note in
                                Text(note)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        case .failure(let error):
                            Text(error.localizedDescription)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if let error = userRuleError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    if let preview = userRulePreview {
                        SectionBox(title: "Rule Pack Preview") {
                            HStack(spacing: 16) {
                                MetricTile(title: "Importable", value: preview.isImportable ? "Yes" : "No")
                                MetricTile(title: "Accepted", value: "\(preview.acceptedRuleCount)")
                                MetricTile(title: "Rejected", value: "\(preview.rejectedRuleCount)")
                                MetricTile(title: "Total", value: "\(preview.ruleCount)")
                            }
                            Text(preview.sourcePath)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            if preview.issues.isEmpty {
                                Text("Validation: no issues")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(preview.issues) { issue in
                                    let scope = issue.ruleID.map { " \($0)" } ?? ""
                                    Text("\(issue.severity.rawValue)\(scope): \(issue.message)")
                                        .font(.caption)
                                        .foregroundStyle(issue.severity == .error ? .red : .orange)
                                }
                            }
                            ForEach(preview.document.rules.prefix(12)) { rule in
                                ruleRow(rule, source: "Preview")
                                Divider()
                            }
                            if preview.document.rules.count > 12 {
                                Text("\(preview.document.rules.count - 12) more preview rule(s)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    SectionBox(title: "Safety Summary") {
                        ForEach(catalog.safetySummaries) { summary in
                            HStack {
                                Text(summary.name)
                                Spacer()
                                Text("\(summary.count)")
                                    .monospacedDigit()
                            }
                            .font(.caption)
                        }
                    }

                    SectionBox(title: "Action Summary") {
                        ForEach(catalog.actionSummaries) { summary in
                            HStack {
                                Text(summary.name)
                                Spacer()
                                Text("\(summary.count)")
                                    .monospacedDigit()
                            }
                            .font(.caption)
                        }
                    }

                    ForEach(catalog.sections.filter { !$0.rules.isEmpty }) { section in
                        SectionBox(title: section.title) {
                            Text(section.guidance)
                                .foregroundStyle(.secondary)
                            ForEach(section.rules) { rule in
                                ruleRow(rule)
                                Divider()
                            }
                        }
                    }

                    SectionBox(title: "Non-claims") {
                        ForEach(catalog.nonClaims, id: \.self) { note in
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(24)
            case .failure(let error):
                ContentUnavailableView("Rule catalog unavailable", systemImage: "exclamationmark.triangle", description: Text(error.localizedDescription))
                    .padding(24)
            }
        }
    }

    private var userRuleCount: Int {
        switch userRuleDocumentResult {
        case .success(let document): document.rules.count
        case .failure: 0
        }
    }

    private func ruleRow(_ rule: RuleCatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(rule.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(rule.actionKind.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(rule.id)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Text("\(rule.category) - \(rule.source) - priority \(rule.priority)")
                .font(.caption)
            if !rule.matchHints.isEmpty {
                Text("Match: \(rule.matchHints.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !rule.conditions.isEmpty {
                Text("Conditions: \(rule.conditions.joined(separator: " | "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let recovery = rule.recovery, !recovery.isEmpty {
                Text("Recovery: \(recovery)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }

    private func ruleRow(_ rule: ReclaimerRule, source: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(rule.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(rule.actionKind.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(rule.id)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Text("\(rule.category) - \(source) - priority \(rule.priority)")
                .font(.caption)
            Text("Match: \(rule.match.appCatalogSummary)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if !rule.conditions.isEmpty {
                Text("Conditions: \(rule.conditions.joined(separator: " | "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let recovery = rule.recovery, !recovery.isEmpty {
                Text("Recovery: \(recovery)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }

    private func refreshUserRuleState() {
        catalogResult = Result { try RuleEngine.bundled().catalog() }
        userRuleDocumentResult = Result { try UserRulePackStore().loadDocument() }
        userRuleCatalogResult = Result { try RuleEngine.bundled(includingUserRules: true).catalog() }
    }

    private func previewUserRulePack() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a Ryddi user rule pack JSON file to preview before importing."
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            userRulePreview = try UserRulePackStore().preview(from: url)
            userRuleImportResult = nil
            userRuleError = nil
        } catch {
            userRulePreview = nil
            userRuleImportResult = nil
            userRuleError = error.localizedDescription
        }
        #endif
    }

    private func importPreviewedUserRulePack() {
        guard let preview = userRulePreview else {
            userRuleError = "Preview a rule pack before importing."
            return
        }
        guard preview.isImportable else {
            userRuleError = "This rule pack has validation errors and cannot be imported."
            return
        }
        do {
            userRuleImportResult = try UserRulePackStore().importDocument(
                from: URL(fileURLWithPath: preview.sourcePath),
                merge: true
            )
            refreshUserRuleState()
            userRuleError = nil
        } catch {
            userRuleImportResult = nil
            userRuleError = error.localizedDescription
        }
    }

    private func exportUserRulePack() {
        do {
            let document = try UserRulePackStore().exportDocument()
            lastUserRuleExportURL = try ReportStore().save(userRulePackDocument: document)
            userRuleError = nil
        } catch {
            lastUserRuleExportURL = nil
            userRuleError = error.localizedDescription
        }
    }
}

private extension RuleMatchSpec {
    var appCatalogSummary: String {
        var hints: [String] = []
        hints += containsAny.map { "contains: \($0)" }
        hints += suffixAny.map { "suffix: \($0)" }
        hints += basenameAny.map { "basename: \($0)" }
        hints += pathExtensionAny.map { "extension: \($0)" }
        return hints.isEmpty ? "none" : hints.sorted().joined(separator: ", ")
    }
}

struct RecoveryCenterView: View {
    let model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recovery Center")
                            .font(.largeTitle.bold())
                        Text("Review prior cleanup evidence and use Finder for held-item recovery, Trash review, and other manual recovery paths.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task {
                            await model.loadHoldingAndAudit()
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }

                HStack(spacing: 16) {
                    let holdingItems = model.recoveryReport.items.filter { $0.holdingID != nil }
                    MetricTile(title: "Recovery items", value: "\(model.recoveryReport.itemCount)")
                    MetricTile(title: "Holding records", value: "\(holdingItems.count)")
                    MetricTile(title: "Held bytes", value: ByteFormat.string(holdingItems.reduce(0) { $0 + $1.bytes }))
                }

                SectionBox(title: "By State") {
                    if model.recoveryReport.stateSummaries.isEmpty {
                        Text("No recovery evidence yet.")
                    } else {
                        ForEach(model.recoveryReport.stateSummaries) { summary in
                            HStack {
                                Text(summary.state.label)
                                Spacer()
                                Text(ByteFormat.string(summary.bytes))
                                    .foregroundStyle(.secondary)
                                Text("\(summary.count)")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                SectionBox(title: "Holding Records") {
                    let holdingItems = model.recoveryReport.items.filter { $0.holdingID != nil }
                    if holdingItems.isEmpty {
                        Text("No holding records are currently available for manual Finder recovery.")
                    } else {
                        ForEach(holdingItems) { item in
                            RecoveryItemRow(item: item)
                            Divider()
                        }
                    }
                }

                SectionBox(title: "Receipt Guidance") {
                    let guidanceItems = model.recoveryReport.items.filter { $0.holdingID == nil }
                    if guidanceItems.isEmpty {
                        Text("No saved receipt actions need recovery guidance.")
                    } else {
                        ForEach(guidanceItems.prefix(30)) { item in
                            RecoveryItemRow(item: item)
                            Divider()
                        }
                    }
                }

                SectionBox(title: "Non-claims") {
                    ForEach(model.recoveryReport.nonClaims, id: \.self) { note in
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = model.error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
        }
    }
}

struct RecoveryItemRow: View {
    let item: RecoveryCenterItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                    Text(item.state.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(ByteFormat.string(item.bytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let originalPath = item.originalPath {
                Text("Original: \(originalPath)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            if let currentPath = item.currentPath {
                HStack {
                    Text("Current: \(currentPath)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        PathActions.revealInFinder(currentPath)
                    } label: {
                        Label("Reveal in Trash", systemImage: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal the moved item in Finder")
                }
            }
            if let receiptID = item.receiptID {
                Text("Receipt: \(receiptID)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Text(item.message)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(item.guidance.prefix(2), id: \.self) { guidance in
                Text(guidance)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ActiveFileReviewView: View {
    let model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Active Handles")
                            .font(.largeTitle.bold())
                        Text("Open-file blockers for cleanup-relevant candidates.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await model.checkActiveHandles() }
                    } label: {
                        Label("Check", systemImage: "lock.open")
                    }
                    .disabled(model.isWorking)
                }

                if model.isWorking {
                    ProgressView("Checking active handles...")
                }

                if let report = model.activeFileReview {
                    HStack(spacing: 16) {
                        MetricTile(title: "Candidates", value: "\(report.candidateCount)")
                        MetricTile(title: "Checked", value: "\(report.checkedCount)")
                        MetricTile(title: "Open", value: "\(report.openCount)")
                        MetricTile(title: "Failed", value: "\(report.failedCheckCount)")
                        MetricTile(title: "Blocked bytes", value: ByteFormat.string(report.totalBlockedBytes))
                    }

                    if report.truncated {
                        Text("Checked the first \(report.checkedCount) candidates by size.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    SectionBox(title: "Open Handle Blockers") {
                        if report.items.isEmpty {
                            Text("No blockers found in the checked candidates.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(report.items) { item in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(item.state.label)
                                            .font(.headline)
                                        Text(ByteFormat.string(item.finding.allocatedSize))
                                            .foregroundStyle(.secondary)
                                        if item.finding.openFileStatus?.checkedRecursively == true {
                                            Label("Recursive", systemImage: "folder.badge.gearshape")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        SafetyBadge(safetyClass: item.finding.safetyClass)
                                    }
                                    Text(item.finding.path)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                    if !item.processSummary.isEmpty {
                                        Text("Open by: \(item.processSummary.joined(separator: ", "))")
                                            .font(.caption)
                                    }
                                    if let failure = item.checkFailed {
                                        Text(failure)
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                    ForEach(item.guidance, id: \.self) { line in
                                        Text(line)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    FindingActionButtons(finding: item.finding)
                                }
                                Divider()
                            }
                        }
                    }

                    SectionBox(title: "Non-Claims") {
                        ForEach(report.nonClaims, id: \.self) { note in
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ContentUnavailableView("No active-file report", systemImage: "lock.open", description: Text("Run Check after a scan."))
                }
            }
            .padding(24)
        }
    }
}

struct ContainerInventoryView: View {
    let model: DashboardModel
    @State private var pendingBuildCacheCleanup = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Container Inventory")
                            .font(.largeTitle.bold())
                        Text("See what can be reclaimed safely without raw-deleting Colima's VM disk or unique container data.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await model.inspectContainers() }
                    } label: {
                        Label("Inspect", systemImage: "shippingbox")
                    }
                    .disabled(model.isWorking)
                }

                if model.isWorking {
                    ProgressView("Inspecting containers...")
                }

                if let report = model.containerInventory {
                    HStack(spacing: 16) {
                        MetricTile(title: "Docker", value: report.docker.status.state.label)
                        MetricTile(title: "Reclaim estimate", value: report.dockerReclaimableBytes.map(ByteFormat.string) ?? "Unknown")
                        MetricTile(title: "Images", value: "\(report.docker.images.count)")
                        MetricTile(title: "Volumes", value: "\(report.docker.volumes.count)")
                        MetricTile(title: "Colima profiles", value: "\(report.colima.profiles.count)")
                    }

                    ContainerReclaimGuidanceView(
                        report: report,
                        onPreview: {
                            guard let action = report.dockerBuildCacheAction else { return }
                            Task {
                                await model.runNativeToolCommand(
                                    receipt: action.receipt,
                                    command: action.command,
                                    perform: false
                                )
                            }
                        },
                        onReclaim: { pendingBuildCacheCleanup = true }
                    )

                    SectionBox(title: "Docker Storage") {
                        Text(report.docker.status.message)
                            .foregroundStyle(.secondary)
                        if report.docker.storage.isEmpty {
                            Text("No Docker storage rows were available.")
                        } else {
                            ForEach(report.docker.storage) { bucket in
                                HStack {
                                    Text(bucket.type)
                                        .frame(width: 130, alignment: .leading)
                                    Text(bucket.sizeText)
                                        .frame(width: 92, alignment: .leading)
                                    Text(bucket.reclaimableText)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .font(.system(.body, design: .monospaced))
                            }
                        }
                    }

                    SectionBox(title: "Docker Objects") {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Containers").font(.headline)
                                if report.docker.containers.isEmpty {
                                    Text("No containers reported.").foregroundStyle(.secondary)
                                } else {
                                    ForEach(report.docker.containers.prefix(8)) { container in
                                        Text("\(container.name) - \(container.status) - \(container.sizeText)")
                                            .lineLimit(1)
                                    }
                                }
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Images").font(.headline)
                                if report.docker.images.isEmpty {
                                    Text("No images reported.").foregroundStyle(.secondary)
                                } else {
                                    ForEach(report.docker.images.prefix(8)) { image in
                                        Text("\(image.repository):\(image.tag) - \(image.sizeText)")
                                            .lineLimit(1)
                                    }
                                }
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Volumes").font(.headline)
                                if report.docker.volumes.isEmpty {
                                    Text("No volumes reported.").foregroundStyle(.secondary)
                                } else {
                                    ForEach(report.docker.volumes.prefix(8)) { volume in
                                        Text("\(volume.name) - \(volume.driver)")
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }

                    SectionBox(title: "Colima Profiles") {
                        Text(report.colima.status.message)
                            .foregroundStyle(.secondary)
                        if report.colima.profiles.isEmpty {
                            Text("No Colima profiles were reported.")
                        } else {
                            ForEach(report.colima.profiles) { profile in
                                let details = [
                                    profile.status,
                                    profile.runtime,
                                    profile.architecture,
                                    profile.cpu.map { "\($0) CPU" },
                                    profile.memory,
                                    profile.disk
                                ]
                                .compactMap { $0 }
                                .joined(separator: ", ")
                                Text("\(profile.name): \(details)")
                            }
                        }
                    }

                    SectionBox(title: "Read-only Command Outcomes") {
                        ForEach((report.docker.commands + report.colima.commands), id: \.id) { command in
                            CommandOutcomeRow(command: command)
                        }
                    }

                    SectionBox(title: "Non-claims") {
                        ForEach(report.nonClaims, id: \.self) { note in
                            Text("• \(note)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ContentUnavailableView("No container inventory yet", systemImage: "shippingbox", description: Text("Run Inspect to collect read-only Docker and Colima status."))
                }

                if let error = model.error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
        }
        .confirmationDialog(
            "Reclaim Docker build cache?",
            isPresented: $pendingBuildCacheCleanup
        ) {
            Button("Preview + reclaim build cache", role: .destructive) {
                guard let action = model.containerInventory?.dockerBuildCacheAction else { return }
                Task {
                    await model.runNativeToolCommand(
                        receipt: action.receipt,
                        command: action.command,
                        perform: true
                    )
                    await model.inspectContainers()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Ryddi will first refresh Docker's read-only inventory, then run docker builder prune --force. Containers, images, volumes, Colima profiles, and the VM disk remain untouched.")
        }
    }
}

private struct ContainerReclaimAction {
    let receipt: NativeToolReceipt
    let command: NativeToolCommand
}

private extension ContainerInventoryReport {
    var buildCacheBucket: DockerStorageBucket? {
        docker.storage.first { $0.type == "Build Cache" }
    }

    var dockerBuildCacheAction: ContainerReclaimAction? {
        guard docker.status.state == .available,
              let buildCacheBucket,
              (buildCacheBucket.reclaimableBytes ?? 0) > 0 else {
            return nil
        }
        let action = NativeMaintenanceAction.dockerBuilderPrune
        let command = NativeToolCommand(
            id: action.rawValue,
            command: action.performInvocation.displayCommand,
            purpose: "Remove only Docker build cache that Docker currently considers unused.",
            risk: .reclaim,
            requiresReview: true,
            expectedEffect: "Docker removes unused build-cache records; active containers, images, volumes, and Colima profiles remain untouched.",
            context: "Ryddi binds execution to a fresh read-only Docker context and inventory preview."
        )
        let receipt = NativeToolReceipt(
            findingPath: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".colima", isDirectory: true).path,
            displayName: "Docker build cache",
            category: "Containers",
            allocatedSize: buildCacheBucket.sizeBytes ?? 0,
            safetyClass: .safeAfterCondition,
            actionKind: .nativeToolCommand,
            status: "review-required",
            message: "Docker reports \(buildCacheBucket.reclaimableText) of build cache as reclaimable. Preview the exact native action before deciding.",
            commands: [command],
            nonClaims: action.nonClaims
        )
        return ContainerReclaimAction(receipt: receipt, command: command)
    }
}

private struct ContainerReclaimGuidanceView: View {
    let report: ContainerInventoryReport
    let onPreview: () -> Void
    let onReclaim: () -> Void

    var body: some View {
        SectionBox(title: "What you can reclaim") {
            VStack(alignment: .leading, spacing: 12) {
                if let bucket = report.buildCacheBucket,
                   let reclaimable = bucket.reclaimableBytes,
                   reclaimable > 0 {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "hammer.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Unused Docker build cache")
                                .font(.headline)
                            Text("Docker reports \(ByteFormat.string(reclaimable)) reclaimable out of \(bucket.sizeText). This is the only container storage Ryddi can reclaim from here.")
                                .foregroundStyle(.secondary)
                            Text("Actual APFS free-space gain is measured after the action and may differ from Docker's estimate.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            actionButtons
                        }
                        VStack(alignment: .leading) {
                            actionButtons
                        }
                    }
                } else if report.docker.status.state == .available {
                    Label("Docker does not currently report unused build cache to reclaim.", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    Label("Start Docker or Colima, then inspect again to separate reclaimable build cache from protected working data.", systemImage: "pause.circle")
                        .foregroundStyle(.secondary)
                }

                Divider()
                Label("Keep by default: images, containers, volumes, Colima profiles, and VM disks can contain unique project or database state.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actionButtons: some View {
        Group {
            Button("Preview cleanup", action: onPreview)
                .buttonStyle(.bordered)
            Button("Preview + reclaim build cache", action: onReclaim)
                .buttonStyle(.borderedProminent)
        }
    }
}

struct CommandOutcomeRow: View {
    let command: ToolCommandSnapshot

    var body: some View {
        let exitText = command.exitCode.map { String($0) } ?? "-"
        VStack(alignment: .leading, spacing: 3) {
            Text(command.command)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            Text(command.status + " - exit " + exitText)
                .font(.caption)
                .foregroundStyle(command.status == "ok" ? Color.secondary : Color.orange)
            if let error = command.launchError {
                Text(error)
                    .foregroundStyle(.secondary)
            } else if let stderr = command.stderrPreview.first {
                Text(stderr)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct UserPathPolicyView: View {
    let model: DashboardModel
    @State private var path = ""
    @State private var reason = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Protections & Exclusions")
                    .font(.largeTitle.bold())

                SectionBox(title: "Add Rule") {
                    TextField("Path", text: $path)
                        .textFieldStyle(.roundedBorder)
                    TextField("Reason", text: $reason)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button {
                            add(.protect)
                        } label: {
                            Label("Protect", systemImage: "lock.shield")
                        }
                        .disabled(trimmedPath.isEmpty || model.isWorking)

                        Button {
                            add(.exclude)
                        } label: {
                            Label("Exclude", systemImage: "eye.slash")
                        }
                        .disabled(trimmedPath.isEmpty || model.isWorking)
                    }
                }

                HStack(spacing: 16) {
                    MetricTile(title: "Protected", value: "\(model.userPathPolicy.rules(kind: .protect).count)")
                    MetricTile(title: "Excluded", value: "\(model.userPathPolicy.rules(kind: .exclude).count)")
                    MetricTile(title: "Policy file", value: UserPathPolicyStore().policyURL.lastPathComponent)
                }

                SectionBox(title: "Portability") {
                    HStack {
                        Button {
                            Task { await model.exportUserPathPolicy() }
                        } label: {
                            Label("Export Policy", systemImage: "square.and.arrow.up")
                        }
                        .disabled(model.isWorking)

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([UserPathPolicyStore().policyURL])
                        } label: {
                            Label("Reveal Policy File", systemImage: "folder")
                        }
                        .disabled(model.isWorking || model.userPathPolicy.rules.isEmpty)
                    }
                    if let url = model.lastPolicyExportURL {
                        Text(url.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                policySection(kind: .protect)
                policySection(kind: .exclude)

                if let error = model.error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
        }
    }

    private var trimmedPath: String {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add(_ kind: UserPathPolicyKind) {
        let newPath = trimmedPath
        let newReason = trimmedReason
        path = ""
        reason = ""
        Task {
            await model.addUserPathRule(path: newPath, kind: kind, reason: newReason)
        }
    }

    @ViewBuilder
    private func policySection(kind: UserPathPolicyKind) -> some View {
        SectionBox(title: kind.label) {
            let rules = model.userPathPolicy.rules(kind: kind)
            if rules.isEmpty {
                Text("No entries.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rules) { rule in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rule.path)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                if let reason = rule.reason {
                                    Text(reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                Task { await model.removeUserPathRule(rule) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .help("Remove rule")
                            .disabled(model.isWorking)
                        }
                    }
                }
            }
        }
    }
}

struct HoldingView: View {
    let model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Holding Area")
                            .font(.largeTitle.bold())
                        Text("Holding records stay for manual Finder recovery.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Refresh") {
                        model.loadHolding()
                    }
                }

                if model.heldItems.isEmpty {
                    ContentUnavailableView("No held items", systemImage: "archivebox", description: Text("Existing holding records appear here for manual Finder recovery."))
                } else {
                    ForEach(model.heldItems) { item in
                        SectionBox(title: item.displayName) {
                            Text(item.id)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            Text("Held: \(item.heldPath)")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            Text("Original: \(item.originalPath ?? "unknown")")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            HStack {
                                Text(ByteFormat.string(item.allocatedSize))
                                Text(item.heldAt?.formatted() ?? "unknown date")
                                Spacer()
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.heldPath)])
                                } label: {
                                    Label("Reveal in Finder", systemImage: "folder")
                                }
                                .help("Reveal held item in Finder")
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

struct DuplicateReviewView: View {
    let model: DashboardModel
    @State private var includePreserveByDefault = false
    @State private var showSkipped = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Duplicate Review")
                            .font(.largeTitle.bold())
                        Text("Identical regular files are grouped with local content hashes. Ryddi does not choose winners, delete duplicates, or add them to reclaim plans.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        Task { await model.scanDuplicates(includePreserveByDefault: includePreserveByDefault) }
                    } label: {
                        Label("Scan Duplicates", systemImage: "rectangle.on.rectangle")
                    }
                    .disabled(model.isWorking)
                }

                Toggle("Include preserve-by-default files", isOn: $includePreserveByDefault)
                    .toggleStyle(.switch)
                    .help("Include documents, media, and other protected review data. Credentials and never-touch paths remain excluded.")

                if let report = model.duplicateReview {
                    HStack(spacing: 16) {
                        MetricTile(title: "Groups", value: "\(report.groups.count)")
                        MetricTile(title: "Files", value: "\(report.duplicateFileCount)")
                        MetricTile(title: "Apparent review bytes", value: ByteFormat.string(report.apparentDuplicateBytes))
                        MetricTile(title: "Skipped", value: "\(report.skipped.count)")
                    }

                    SectionBox(title: "Review Notes") {
                        ForEach(report.notes, id: \.self) { note in
                            Text(note)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if report.groups.isEmpty {
                        ContentUnavailableView("No duplicate groups", systemImage: "checkmark.circle", description: Text("No identical-file groups matched the current duplicate review options."))
                    } else {
                        ForEach(report.groups.prefix(20)) { group in
                            DuplicateGroupBox(group: group)
                        }
                    }

                    Toggle("Show skipped paths", isOn: $showSkipped)
                        .toggleStyle(.switch)
                    if showSkipped {
                        SectionBox(title: "Skipped Or Excluded") {
                            if report.skipped.isEmpty {
                                Text("No skipped paths were reported.")
                            } else {
                                ForEach(report.skipped.prefix(80), id: \.self) { line in
                                    Text(line)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("No duplicate review yet", systemImage: "rectangle.on.rectangle", description: Text("Run a duplicate scan to build a review-only list of identical regular files."))
                }

                if let error = model.error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
        }
    }
}

struct DownloadsReviewView: View {
    let model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Downloads Review")
                            .font(.largeTitle.bold())
                        Text("Review old downloads, installers, archives, and app bundles. Ryddi classifies candidates and saves evidence; Finder remains the place to move, archive, or Trash files.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        Task { await model.reviewDownloads() }
                    } label: {
                        Label("Review Downloads", systemImage: "tray.and.arrow.down")
                    }
                    .disabled(model.isWorking)
                }

                if let report = model.downloadsReview {
                    HStack(spacing: 16) {
                        MetricTile(title: "Review candidates", value: ByteFormat.string(report.reviewCandidateBytes))
                        MetricTile(title: "Installers/apps", value: ByteFormat.string(report.installerBytes))
                        MetricTile(title: "Archives", value: ByteFormat.string(report.archiveBytes))
                        MetricTile(title: "Old", value: ByteFormat.string(report.oldCandidateBytes))
                        MetricTile(title: "Permission", value: report.permissionState.rawValue)
                    }

                    SectionBox(title: "Downloads Root") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(report.rootPath)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            HStack {
                                Button {
#if os(macOS)
                                    NSWorkspace.shared.open(URL(fileURLWithPath: report.rootPath))
#endif
                                } label: {
                                    Label("Open In Finder", systemImage: "folder")
                                }
                                Spacer()
                            }
                            ForEach(report.notes, id: \.self) { note in
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    SectionBox(title: "By Kind") {
                        if report.kindSummaries.isEmpty {
                            Text("No Downloads entries found at the configured root.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(report.kindSummaries) { summary in
                                    HStack {
                                        Text(summary.kind.label)
                                        Spacer()
                                        Text("\(summary.itemCount)")
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                        Text(ByteFormat.string(summary.allocatedSize))
                                            .frame(width: 90, alignment: .trailing)
                                            .monospacedDigit()
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }

                    SectionBox(title: "By Workflow") {
                        if report.workflowSummaries.isEmpty {
                            Text("No workflow buckets were recorded for this Downloads review.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(report.workflowSummaries) { summary in
                                    HStack {
                                        Text(summary.workflow.label)
                                        Spacer()
                                        Text("\(summary.itemCount)")
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                        Text(ByteFormat.string(summary.allocatedSize))
                                            .frame(width: 90, alignment: .trailing)
                                            .monospacedDigit()
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }

                    SectionBox(title: "Largest Downloads Items") {
                        if report.largestItems.isEmpty {
                            Text("No Downloads items found at the configured root.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Allocated").frame(width: 92, alignment: .leading)
                                    Text("Kind").frame(width: 116, alignment: .leading)
                                    Text("Workflow").frame(width: 118, alignment: .leading)
                                    Text("Next").frame(width: 112, alignment: .leading)
                                    Text("Age").frame(width: 64, alignment: .leading)
                                    Text("Path")
                                    Spacer()
                                    Text("Actions").frame(width: 132, alignment: .trailing)
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                ForEach(report.largestItems.prefix(40)) { item in
                                    Divider()
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(ByteFormat.string(item.allocatedSize))
                                                .frame(width: 92, alignment: .leading)
                                                .monospacedDigit()
                                            Text(item.kind.label)
                                                .frame(width: 116, alignment: .leading)
                                            Text(item.workflow.label)
                                                .frame(width: 118, alignment: .leading)
                                            Text(item.nextAction.label)
                                                .foregroundStyle(.secondary)
                                                .frame(width: 112, alignment: .leading)
                                            Text(item.ageDays.map { "\($0)d" } ?? "unknown")
                                                .frame(width: 64, alignment: .leading)
                                            Text(item.path)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                                .textSelection(.enabled)
                                            Spacer()
                                            DownloadsReviewItemActionButtons(item: item)
                                                .frame(width: 132, alignment: .trailing)
                                        }
                                        .font(.caption)
                                        Text(item.recommendation)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        if let step = item.workflowSteps.first {
                                            Text("Workflow: \(step)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                    }

                    SectionBox(title: "Guidance") {
                        ForEach(report.guidance, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SectionBox(title: "Non-Claims") {
                        ForEach(report.nonClaims, id: \.self) { note in
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    ContentUnavailableView("No Downloads review yet", systemImage: "tray.and.arrow.down", description: Text("Run Downloads Review to inspect installers, archives, old downloads, and other space candidates without moving anything."))
                }

                if let error = model.error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
        }
    }
}

struct BrowserCacheReviewView: View {
    let model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Browser Cache Review")
                            .font(.largeTitle.bold())
                        Text("Review browser cache roots separately from browser profiles, cookies, bookmarks, history, passwords, extensions, and sync state.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        Task { await model.reviewBrowserCaches() }
                    } label: {
                        Label("Review Browser Caches", systemImage: "globe")
                    }
                    .disabled(model.isWorking)
                }

                if let report = model.browserCacheReview {
                    HStack(spacing: 16) {
                        MetricTile(title: "Candidates", value: ByteFormat.string(report.candidateBytes))
                        MetricTile(title: "Allocated", value: ByteFormat.string(report.totalAllocatedSize))
                        MetricTile(title: "Measured items", value: "\(report.itemCount)")
                        MetricTile(title: "Cache roots", value: "\(report.rootSummaries.count)")
                        MetricTile(title: "Protected profiles", value: "\(report.protectedProfileRoots.count)")
                    }

                    SectionBox(title: "Runtime Status") {
                        if report.runtimeSummaries.isEmpty {
                            Text("No browser runtime state was available for the inspected cache or profile roots.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(report.runtimeSummaries) { summary in
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(summary.browser.label)
                                                .font(.caption.weight(.semibold))
                                            Text(summary.state.label)
                                                .font(.caption)
                                                .foregroundStyle(summary.state == .running ? .orange : .secondary)
                                            Spacer()
                                            if !summary.matchedProcessNames.isEmpty {
                                                Text(summary.matchedProcessNames.prefix(2).joined(separator: ", "))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.tail)
                                            }
                                        }
                                        Text(summary.note)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        if let firstGuidance = summary.guidance.first {
                                            Text(firstGuidance)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    Divider()
                                }
                            }
                        }
                    }

                    SectionBox(title: "By Browser") {
                        if report.browserSummaries.isEmpty {
                            Text("No browser cache items found in readable cache roots.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(report.browserSummaries) { summary in
                                    HStack {
                                        Text(summary.name)
                                        Spacer()
                                        Text("\(summary.itemCount)")
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                        Text(ByteFormat.string(summary.allocatedSize))
                                            .frame(width: 90, alignment: .trailing)
                                            .monospacedDigit()
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }

                    SectionBox(title: "Cache Roots") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(report.rootSummaries) { root in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(root.browser.label)
                                            .font(.caption.weight(.semibold))
                                        Text(root.permissionState.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(ByteFormat.string(root.allocatedSize))
                                            .font(.caption.monospacedDigit())
                                    }
                                    Text(root.rootPath)
                                        .font(.system(.caption2, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                    Text(root.note)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Divider()
                            }
                        }
                    }

                    SectionBox(title: "Largest Cache Items") {
                        if report.largestItems.isEmpty {
                            Text("No browser cache items found in readable cache roots.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Allocated").frame(width: 92, alignment: .leading)
                                    Text("Browser").frame(width: 82, alignment: .leading)
                                    Text("Kind").frame(width: 122, alignment: .leading)
                                    Text("Path")
                                    Spacer()
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                ForEach(report.largestItems.prefix(40)) { item in
                                    Divider()
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(ByteFormat.string(item.allocatedSize))
                                                .frame(width: 92, alignment: .leading)
                                                .monospacedDigit()
                                            Text(item.browser.label)
                                                .frame(width: 82, alignment: .leading)
                                            Text(item.kind.label)
                                                .frame(width: 122, alignment: .leading)
                                            Text(item.path)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                                .textSelection(.enabled)
                                            Spacer()
                                        }
                                        .font(.caption)
                                        Text(item.recommendation)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                    }

                    SectionBox(title: "Protected Profile Roots") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(report.protectedProfileRoots) { profile in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(profile.browser.label)
                                            .font(.caption.weight(.semibold))
                                        Text(profile.permissionState.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(profile.path)
                                        .font(.system(.caption2, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                    Text(profile.note)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Divider()
                            }
                        }
                    }

                    SectionBox(title: "Guidance") {
                        ForEach(report.guidance, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SectionBox(title: "Non-Claims") {
                        ForEach(report.nonClaims, id: \.self) { note in
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    ContentUnavailableView("No browser cache review yet", systemImage: "globe", description: Text("Run Browser Cache Review to inspect browser cache roots without measuring or modifying protected profile state."))
                }

                if let error = model.error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
        }
    }
}

struct TrashReviewView: View {
    let model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Trash Review")
                            .font(.largeTitle.bold())
                        Text("Review what is currently sitting in the user Trash. Ryddi reports size and guidance; Finder remains the place to restore or empty items.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        Task { await model.reviewTrash() }
                    } label: {
                        Label("Review Trash", systemImage: "trash")
                    }
                    .disabled(model.isWorking)
                }

                if let report = model.trashReview {
                    HStack(spacing: 16) {
                        MetricTile(title: "Allocated", value: ByteFormat.string(report.totalAllocatedSize))
                        MetricTile(title: "Logical", value: ByteFormat.string(report.totalLogicalSize))
                        MetricTile(title: "Measured items", value: "\(report.itemCount)")
                        MetricTile(title: "Permission", value: report.permissionState.rawValue)
                    }

                    SectionBox(title: "Trash Root") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(report.rootPath)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            HStack {
                                Button {
#if os(macOS)
                                    NSWorkspace.shared.open(URL(fileURLWithPath: report.rootPath))
#endif
                                } label: {
                                    Label("Open In Finder", systemImage: "folder")
                                }
                                Spacer()
                            }
                            ForEach(report.notes, id: \.self) { note in
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    SectionBox(title: "Largest Trash Items") {
                        if report.largestItems.isEmpty {
                            Text("No Trash items found at the configured root.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Allocated").frame(width: 92, alignment: .leading)
                                    Text("Items").frame(width: 56, alignment: .leading)
                                    Text("Next").frame(width: 112, alignment: .leading)
                                    Text("Modified").frame(width: 92, alignment: .leading)
                                    Text("Path")
                                    Spacer()
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                ForEach(report.largestItems.prefix(30)) { item in
                                    Divider()
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(ByteFormat.string(item.allocatedSize))
                                                .frame(width: 92, alignment: .leading)
                                                .monospacedDigit()
                                            Text("\(item.itemCount)")
                                                .frame(width: 56, alignment: .leading)
                                            Text(item.nextAction.label)
                                                .foregroundStyle(.secondary)
                                                .frame(width: 112, alignment: .leading)
                                            Text(item.modificationDate?.formatted(date: .numeric, time: .omitted) ?? "unknown")
                                                .frame(width: 92, alignment: .leading)
                                            Text(item.path)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                                .textSelection(.enabled)
                                            Spacer()
                                        }
                                        .font(.caption)
                                        if let firstGuidance = item.guidance.first {
                                            Text(firstGuidance)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                    }

                    SectionBox(title: "Guidance") {
                        ForEach(report.guidance, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SectionBox(title: "Non-Claims") {
                        ForEach(report.nonClaims, id: \.self) { note in
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    ContentUnavailableView("No Trash review yet", systemImage: "trash", description: Text("Run Trash Review to inspect the current user Trash without emptying it."))
                }

                if let error = model.error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
        }
    }
}

struct AgentStorageReviewView: View {
    let model: DashboardModel
    @State private var retentionProfile: AgentRetentionProfile = .balanced

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AI Agent Storage")
                            .font(.largeTitle.bold())
                        Text("Focused review for Codex, Claude, Cursor, Windsurf, and Ollama storage, with valuable sessions and protected state separated from cache and log churn.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        Button {
                            Task { await model.reviewAgentStorage() }
                        } label: {
                            Label("Review Agents", systemImage: "sparkles.rectangle.stack")
                        }
                        .disabled(model.isWorking)

                        HStack(spacing: 8) {
                            Picker("Retention profile", selection: $retentionProfile) {
                                ForEach(AgentRetentionProfile.allCases) { profile in
                                    Text(profile.label).tag(profile)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 300)

                            Button {
                                Task { await model.reviewAgentRetention(profile: retentionProfile) }
                            } label: {
                                Label("Retention Report", systemImage: "calendar.badge.clock")
                            }
                            .disabled(model.isWorking)
                        }
                    }
                }

                if model.isWorking {
                    ProgressView("Reviewing agent storage...")
                }

                if let report = model.agentStorageReview {
                    HStack(spacing: 16) {
                        MetricTile(title: "Agent items", value: "\(report.itemCount)")
                        MetricTile(title: "Reviewed", value: ByteFormat.string(report.totalBytes))
                        MetricTile(title: "Reclaimable", value: ByteFormat.string(report.reclaimableBytes))
                        MetricTile(title: "Protected", value: ByteFormat.string(report.protectedBytes))
                    }

                    SectionBox(title: "Buckets") {
                        if report.bucketSummaries.isEmpty {
                            Text("No agent storage matched the current roots.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(report.bucketSummaries) { summary in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(summary.bucket.label)
                                            .font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text("\(ByteFormat.string(summary.bytes)) - \(summary.count) item(s)")
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(summary.bucket.guidance)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Divider()
                            }
                        }
                    }

                    SectionBox(title: "Owners") {
                        if report.ownerSummaries.isEmpty {
                            Text("No agent owners were detected.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(report.ownerSummaries) { summary in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(summary.owner)
                                            .font(.subheadline.weight(.semibold))
                                        Text(summary.dominantBucket.label)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(ByteFormat.string(summary.reclaimableBytes))
                                        .foregroundStyle(.green)
                                    Text(ByteFormat.string(summary.protectedBytes))
                                        .foregroundStyle(.secondary)
                                    Text(ByteFormat.string(summary.bytes))
                                        .monospacedDigit()
                                }
                            }
                        }
                    }

                    SectionBox(title: "Top Agent Items") {
                        if report.items.isEmpty {
                            Text("No agent items were detected.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(report.items.prefix(30)) { item in
                                AgentStorageItemRow(item: item)
                                Divider()
                            }
                        }
                    }

                    if let retentionReport = model.agentRetentionReport {
                        let preview = AgentRetentionPlanBuilder.build(report: retentionReport, matchingFindings: model.findings)

                        SectionBox(title: "Retention Report") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 16) {
                                    MetricTile(title: "Profile", value: retentionReport.profile.label)
                                    MetricTile(title: "Cleanup", value: ByteFormat.string(retentionReport.cleanupCandidateBytes))
                                    MetricTile(title: "Compress", value: ByteFormat.string(retentionReport.compressionCandidateBytes))
                                    MetricTile(title: "Protected", value: ByteFormat.string(retentionReport.protectedBytes))
                                }
                                Text(retentionReport.profileSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                AgentRetentionPlanPreviewView(preview: preview)
                                if !retentionReport.summaries.isEmpty {
                                    ForEach(retentionReport.summaries) { summary in
                                        HStack {
                                            Text(summary.recommendation.label)
                                                .font(.subheadline.weight(.semibold))
                                            Spacer()
                                            Text("\(ByteFormat.string(summary.bytes)) - \(summary.count) item(s)")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Divider()
                                ForEach(retentionReport.recommendations.prefix(20)) { recommendation in
                                    AgentRetentionRecommendationRow(recommendation: recommendation)
                                    Divider()
                                }
                                ForEach(retentionReport.nonClaims, id: \.self) { note in
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    SectionBox(title: "Non-Claims") {
                        ForEach(report.nonClaims, id: \.self) { note in
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ContentUnavailableView("No agent review yet", systemImage: "sparkles.rectangle.stack", description: Text("Run an agent storage review to separate cache churn from sessions, memories, config, and model state."))
                }

                if let error = model.error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
        }
    }
}

struct AgentStorageItemRow: View {
    let item: AgentStorageItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(ByteFormat.string(item.allocatedSize))
                    .monospacedDigit()
            }
            HStack {
                Text(item.owner)
                Text(item.bucket.label)
                Text(item.safetyClass.label)
                Text(item.actionKind.label)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(item.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            if let guidance = item.guidance.first {
                Text(guidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !item.ruleIDs.isEmpty {
                Text("Rules: \(item.ruleIDs.prefix(3).joined(separator: ", "))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AgentRetentionPlanPreviewView: View {
    let preview: AgentRetentionPlanPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: DashboardResponsiveGrid.metricColumns, spacing: 12) {
                MetricTile(title: "Plan preview", value: ByteFormat.string(preview.selectedBytes))
                MetricTile(title: "Plan items", value: "\(preview.plan.items.filter(\.selected).count)")
                MetricTile(title: "Review/keep", value: ByteFormat.string(preview.reviewBytes))
                MetricTile(title: "Protected", value: ByteFormat.string(preview.protectedBytes))
            }

            if preview.plan.items.isEmpty {
                Text("No retention-eligible agent findings matched the current scan for cleanup planning.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(preview.plan.items.prefix(4), id: \.finding.id) { item in
                    HStack {
                        Text(item.selected ? "Selected" : "Blocked")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(item.selected ? .green : .secondary)
                            .frame(width: 64, alignment: .leading)
                        Text(ByteFormat.string(item.finding.allocatedSize))
                            .font(.caption.monospacedDigit())
                            .frame(width: 88, alignment: .leading)
                        Text(item.finding.path)
                            .font(.system(.caption2, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
            }

            ForEach(preview.nonClaims.prefix(2), id: \.self) { note in
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct AgentRetentionRecommendationRow: View {
    let recommendation: AgentRetentionRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(recommendation.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(ByteFormat.string(recommendation.allocatedSize))
                    .monospacedDigit()
            }
            HStack {
                Text(recommendation.owner)
                Text(recommendation.recommendation.label)
                Text(recommendation.bucket.label)
                if let ageDays = recommendation.ageDays {
                    Text("\(ageDays)d old")
                } else {
                    Text("age unknown")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(recommendation.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Text(recommendation.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let firstStep = recommendation.nextSteps.first {
                Text(firstStep)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AppReviewGroupView: View {
    let group: AppReviewGroup
    var previewUninstall: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.ownerName)
                        .font(.headline)
                    Text(group.bundleIdentifier ?? group.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Text(ByteFormat.string(group.totalAllocatedSize))
                    .monospacedDigit()
                SafetyBadge(safetyClass: group.highestRiskClass)
                if group.isInstalled, previewUninstall != nil {
                    Button {
                        previewUninstall?()
                    } label: {
                        Label("Preview Uninstall", systemImage: "trash")
                    }
                    .help("Build a manual uninstall preview. This does not remove the app or related files.")
                }
            }
            if let appPath = group.appPath {
                Text(appPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            ForEach(group.notes.prefix(1), id: \.self) { note in
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(group.items.prefix(8)) { item in
                    Divider()
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName)
                                .lineLimit(1)
                            Text(item.path)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Text(item.category)
                            .foregroundStyle(.secondary)
                        Text(item.nextAction.label)
                            .foregroundStyle(.secondary)
                        Text(ByteFormat.string(item.allocatedSize))
                            .monospacedDigit()
                        SafetyBadge(safetyClass: item.safetyClass)
                        AppReviewItemActionButtons(item: item)
                    }
                    .padding(.vertical, 7)
                }
                if group.items.count > 8 {
                    Text("\(group.items.count - 8) more item(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct AppUninstallPreviewView: View {
    let preview: AppUninstallPreview
    let model: DashboardModel

    var body: some View {
        SectionBox(title: "Uninstall Preview") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(preview.selectedApp.displayName)
                            .font(.headline)
                        Text(preview.selectedApp.bundleIdentifier ?? preview.selectedApp.id)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    MetricTile(title: "Trash preview", value: ByteFormat.string(preview.explicitTrashPreviewBytes))
                    MetricTile(title: "Related review", value: ByteFormat.string(preview.relatedReviewBytes))
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preview.bundleCandidate.displayName)
                            .lineLimit(1)
                        Text(preview.bundleCandidate.path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Text(preview.bundleCandidate.disposition.label)
                        .foregroundStyle(.secondary)
                    Text(ByteFormat.string(preview.bundleCandidate.allocatedSize))
                        .monospacedDigit()
                    SafetyBadge(safetyClass: preview.bundleCandidate.safetyClass)
                    AppUninstallCandidateActionButtons(candidate: preview.bundleCandidate)
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await model.dryRunAppUninstall() }
                    } label: {
                        Label("Dry Run Trash", systemImage: "doc.text.magnifyingglass")
                    }
                    .disabled(model.isWorking || preview.bundleCandidate.disposition != .trashPreview)
                    .help("Create an app-uninstall receipt without moving the app bundle.")

                    Label("Manual Finder removal required", systemImage: "hand.raised")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Automatic app-bundle Trash is disabled until an identity-bound macOS primitive is available.")
                }

                if let receipt = model.currentAppUninstallReceipt {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Latest uninstall receipt")
                            .font(.headline)
                        Text("\(receipt.createdAt.formatted()) - \(receipt.mode) - \(receipt.status)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text(receipt.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ForEach(preview.bundleCandidate.guidance.prefix(2), id: \.self) { guidance in
                    Text(guidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !preview.relatedItems.isEmpty {
                    Divider()
                    Text("Related files stay review-only")
                        .font(.headline)
                    ForEach(preview.relatedItems.prefix(6)) { item in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayName)
                                    .lineLimit(1)
                                Text(item.path)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            Text(item.category)
                                .foregroundStyle(.secondary)
                            Text(ByteFormat.string(item.allocatedSize))
                                .monospacedDigit()
                            SafetyBadge(safetyClass: item.safetyClass)
                            AppReviewItemActionButtons(item: item)
                        }
                    }
                    if preview.relatedItems.count > 6 {
                        Text("\(preview.relatedItems.count - 6) more related item(s)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(preview.nonClaims.prefix(3), id: \.self) { note in
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct DuplicateGroupBox: View {
    let group: DuplicateGroup

    var body: some View {
        SectionBox(title: "Duplicate Group") {
            HStack {
                Text(ByteFormat.string(group.apparentDuplicateBytes))
                    .font(.headline)
                Text("apparent duplicate bytes")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(group.files.count) files")
                Text(ByteFormat.string(group.logicalSize))
            }
            Text(group.id)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            ForEach(group.notes, id: \.self) { note in
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(group.files) { file in
                    Divider()
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.displayName)
                                .lineLimit(1)
                            Text(file.path)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Text(ByteFormat.string(file.allocatedSize))
                            .monospacedDigit()
                        SafetyBadge(safetyClass: file.safetyClass)
                        DuplicateFileActionButtons(file: file)
                    }
                    .padding(.vertical, 7)
                }
            }
        }
    }
}

struct AutomationView: View {
    let model: DashboardModel

    private var scheduledScopeText: String {
        if let set = model.selectedSavedScopeSet {
            return "Saved scope set: \(set.name)"
        }
        if let template = model.selectedScopeTemplate {
            return "Template: \(template.name)"
        }
        return "Preset: \(model.scanPreset.label)"
    }

    private var scheduledCommandText: String {
        if let set = model.selectedSavedScopeSet {
            return "reclaimer plan --json --save-audit --scope-set \(set.id)"
        }
        if let template = model.selectedScopeTemplate {
            return "reclaimer plan --json --save-audit --template \(template.id)"
        }
        return "reclaimer plan --json --save-audit --preset \(model.scanPreset.rawValue)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Automation")
                .font(.largeTitle.bold())
            Text("Automation is report-first. Installing the LaunchAgent writes a plist for the current scan scope; it does not load or run until you choose to load it with launchctl.")
                .foregroundStyle(.secondary)
            Text("Scheduled work is report-only.")
                .font(.headline)
                .foregroundStyle(.blue)

            HStack {
                SafetyBadge(safetyClass: .safeAfterCondition)
                Text(model.launchAgentInstalled ? "LaunchAgent plist installed" : "LaunchAgent plist not installed")
            }

            HStack {
                MetricTile(title: "Scheduled scope", value: scheduledScopeText)
                MetricTile(title: "Scheduled report", value: model.launchAgentStatus.reportKind.label)
                MetricTile(title: "Default time", value: model.launchAgentStatus.nextScheduledTimeDisplay)
            }

            HStack {
                Button("Install Current Scope Schedule") {
                    model.installSchedule()
                }
                Button {
                    model.revealScheduleInFinder()
                } label: {
                    Label("Reveal Schedule", systemImage: "folder")
                }
            }

            SectionBox(title: "Report command") {
                Text(scheduledCommandText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Text("Scheduled scopes select where Ryddi looks. They do not grant cleanup permission or enable unattended deletion.")
                    .foregroundStyle(.secondary)
            }

            SectionBox(title: "Status") {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                    automationStatusRow("Installed", model.launchAgentStatus.installed ? "yes" : "no")
                    automationStatusRow("Loaded Check", model.launchAgentStatus.loadedState)
                    automationStatusRow("Last Log", model.launchAgentStatus.lastLogPath)
                    automationStatusRow("Scope", model.launchAgentStatus.scopeSummary)
                    automationStatusRow("Report Kind", model.launchAgentStatus.reportKind.label)
                }
                Divider()
                ForEach(model.launchAgentStatus.nonClaims, id: \.self) { note in
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SectionBox(title: "Manual load command") {
                Text("launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.reidar.ryddi.agent.plist")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Text("The app does not auto-load the job because report scheduling is still something the user should explicitly activate.")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(24)
    }

    private func automationStatusRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
        .font(.caption)
    }
}

struct MetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
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

struct PermissionCoverageView: View {
    let report: PermissionAdvisorReport

    var body: some View {
        SectionBox(title: "Permission Coverage") {
            HStack {
                Text(report.coverageSummary)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(report.coverageLevel.label)
                    .foregroundStyle(permissionColor(report.coverageLevel))
            }
            Text(report.recommendedActions.first ?? "Ryddi works in degraded mode when some paths are missing or restricted.")
                .foregroundStyle(.secondary)
            Button {
                PathActions.openFullDiskAccessSettings()
            } label: {
                Label("Open Full Disk Access Settings", systemImage: "lock.shield")
            }
            .help("Open macOS Privacy & Security settings for Full Disk Access")
            ForEach(report.unavailableScopes.prefix(6)) { scope in
                Text("\(scope.permissionState.rawValue): \(scope.name) - \(scope.message)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PermissionAccessHelperPanel: View {
    let report: PermissionAdvisorReport
    let onRefresh: () -> Void
    @State private var relaunchFailureMessage: String?

    private var blockingScopes: [ScopeAccessSummary] {
        report.blockingUnavailableScopes.sorted { lhs, rhs in
            if lhs.permissionState != rhs.permissionState {
                return lhs.permissionState.rawValue < rhs.permissionState.rawValue
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var optionalMissingScopes: [ScopeAccessSummary] {
        report.optionalUnavailableScopes.sorted { lhs, rhs in
            if lhs.permissionState != rhs.permissionState {
                return lhs.permissionState.rawValue < rhs.permissionState.rawValue
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        SectionBox(title: "Access Helper") {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: DashboardResponsiveGrid.actionColumns, alignment: .leading, spacing: 10) {
                    permissionButton("Open Full Disk Access", systemImage: "lock.shield", prominent: true) {
                        PathActions.openFullDiskAccessSettings()
                    }
                    .accessibilityIdentifier("permissions.open-full-disk-access")
                    .help("Open macOS Privacy & Security settings for Full Disk Access")

                    permissionButton("Reveal Ryddi", systemImage: "app.dashed") {
                        PathActions.revealApplicationInFinder()
                    }
                    .help("Reveal the installed app so it can be added to Full Disk Access if missing.")

                    permissionButton("Copy App Path", systemImage: "doc.on.doc") {
                        PathActions.copyText(PathActions.applicationPath)
                    }
                    .help(PathActions.applicationPath)

                    permissionButton("Refresh Access", systemImage: "arrow.clockwise") {
                        onRefresh()
                    }
                    .help("Refresh Coverage by repeating each configured scope operation.")

                    permissionButton("Relaunch Ryddi", systemImage: "arrow.trianglehead.clockwise") {
                        Task {
                            let result = await PathActions.relaunchApplication()
                            if case .failure(let failure) = result {
                                relaunchFailureMessage = failure.message
                            }
                        }
                    }
                    .help("Relaunch Ryddi after changing macOS privacy settings.")
                }

                Text(accessHelperCopy)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if blockingScopes.isEmpty && optionalMissingScopes.isEmpty {
                    Label("All configured scopes are readable in the current scope plan.", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    if !blockingScopes.isEmpty {
                        permissionScopeList(
                            title: "Access blockers",
                            scopes: blockingScopes,
                            overflowText: "more access blocker(s)"
                        )
                    }
                    if !optionalMissingScopes.isEmpty {
                        permissionScopeList(
                            title: "Optional missing roots",
                            scopes: optionalMissingScopes,
                            overflowText: "more optional missing root(s)"
                        )
                    }
                }
            }
        }
        .alert(
            "Relaunch Failed",
            isPresented: Binding(
                get: { relaunchFailureMessage != nil },
                set: { if !$0 { relaunchFailureMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                relaunchFailureMessage = nil
            }
        } message: {
            Text(relaunchFailureMessage ?? "Ryddi is still running.")
        }
    }

    private var accessHelperCopy: String {
        if report.needsFullDiskAccessReview {
            return "macOS requires you to change Full Disk Access manually. Add or enable Ryddi, then refresh access. Relaunching Ryddi may be required before the new setting affects these operations."
        }
        if !blockingScopes.isEmpty {
            return "Some configured operations failed. Refresh access to retry them; relaunching Ryddi may be required after changing macOS privacy settings."
        }
        if !optionalMissingScopes.isEmpty {
            return "No denied scopes are visible. Missing paths are usually optional tool or app data that has not been created on this Mac."
        }
        return "No denied, unknown, or missing scopes are visible for the current scope plan."
    }

    @ViewBuilder
    private func permissionButton(_ title: String, systemImage: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Label(title, systemImage: systemImage)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .center)
        }
        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private func permissionScopeList(title: String, scopes: [ScopeAccessSummary], overflowText: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(scopes.prefix(8)) { scope in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(scope.permissionState.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(scope.permissionState == .denied ? .orange : .secondary)
                        .frame(width: 58, alignment: .leading)
                    Text(scope.name)
                        .font(.caption.weight(.semibold))
                        .frame(width: 150, alignment: .leading)
                    Text(scope.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            if scopes.count > 8 {
                Text("\(scopes.count - 8) \(overflowText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PermissionWalkthroughStepRow: View {
    let step: PermissionWalkthroughStep

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(step.status.label)
                    .font(.caption.bold())
                    .foregroundStyle(permissionStepColor(step.status))
                    .frame(width: 104, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.title)
                        .font(.headline)
                    Text(step.detail)
                        .foregroundStyle(.secondary)
                }
            }

            if !step.affectedScopes.isEmpty {
                Text(step.affectedScopes.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 104)
            }

            HStack {
                if step.settingsURL != nil {
                    Button {
                        PathActions.openFullDiskAccessSettings()
                    } label: {
                        Label(step.actionLabel ?? "Open Settings", systemImage: "lock.shield")
                    }
                    .help("Open macOS Privacy & Security settings for Full Disk Access")
                }
                if let command = step.command {
                    Button {
                        PathActions.copyText(command)
                    } label: {
                        Label("Copy Command", systemImage: "doc.on.doc")
                    }
                    .help(command)
                }
            }
            .padding(.leading, 104)
        }
    }
}

func permissionColor(_ level: PermissionCoverageLevel) -> Color {
    switch level {
    case .complete: .green
    case .degraded: .orange
    case .blocked: .red
    }
}

func permissionStepColor(_ status: PermissionWalkthroughStepStatus) -> Color {
    switch status {
    case .done: .green
    case .recommended: .orange
    case .optional: .secondary
    case .blocked: .red
    }
}

struct AccountingNotesView: View {
    let notes: [String]

    var body: some View {
        SectionBox(title: "APFS Accounting") {
            ForEach(notes, id: \.self) { note in
                Text(note)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct DiskMapView: View {
    let nodes: [DiskMapNode]

    private var total: Int64 {
        max(1, nodes.reduce(0) { $0 + $1.allocatedSize })
    }

    var body: some View {
        SectionBox(title: "Visual Map") {
            Text("Category sizes use allocated bytes. Map nodes are informational; cleanup still requires review, dry run, and receipts.")
                .foregroundStyle(.secondary)

            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(nodes.prefix(10)) { node in
                        HStack(spacing: 10) {
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.quaternary.opacity(0.35))
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(color(for: node).opacity(0.75))
                                    .frame(width: max(6, width * CGFloat(Double(node.allocatedSize) / Double(total))))
                            }
                            .frame(height: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(node.name)
                                    .lineLimit(1)
                                Text("\(ByteFormat.string(node.allocatedSize)) • \(node.count) item(s)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 210, alignment: .leading)
                        }
                    }
                }
            }
            .frame(height: CGFloat(min(nodes.count, 10)) * 36)
        }
    }

    private func color(for node: DiskMapNode) -> Color {
        if node.isReclaimable { return .green }
        switch node.safetyClass {
        case .autoSafe: return .green
        case .safeAfterCondition: return .blue
        case .reviewRequired: return .orange
        case .preserveByDefault: return .purple
        case .neverTouch: return .red
        case nil: return .gray
        }
    }
}

struct DiskDrillDownView: View {
    let report: DiskDrillDownReport

    var body: some View {
        SectionBox(title: "Disk Drilldown") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Hierarchical scan findings by allocated size. Parent rows include descendant bytes; use this for navigation, not as additive reclaim math.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 16) {
                    MetricTile(title: "Nodes", value: "\(report.nodeCount)")
                    MetricTile(title: "Allocated", value: ByteFormat.string(report.totalAllocatedSize))
                    MetricTile(title: "Depth", value: "\(report.maxDepth)")
                }

                if report.rootNodes.isEmpty {
                    Text("No drill-down nodes were produced for this scan.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(report.rootNodes.prefix(6)) { node in
                            DiskDrillDownNodeView(node: node)
                        }
                    }
                }

                ForEach(report.nonClaims.prefix(2), id: \.self) { note in
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct DiskDrillDownNodeView: View {
    let node: DiskDrillDownNode

    var body: some View {
        if node.children.isEmpty {
            nodeRow
                .padding(.vertical, 3)
        } else {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(node.children) { child in
                        DiskDrillDownNodeView(node: child)
                            .padding(.leading, 12)
                    }
                    if node.omittedChildCount > 0 {
                        Text("\(node.omittedChildCount) more child item(s), \(ByteFormat.string(node.omittedAllocatedSize)) omitted by the display limit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 12)
                    }
                }
            } label: {
                nodeRow
                    .padding(.vertical, 3)
            }
        }
    }

    private var nodeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(ByteFormat.string(node.allocatedSize))
                    .font(.caption.monospacedDigit())
                    .frame(width: 92, alignment: .leading)
                Text(node.displayName.isEmpty ? node.path : node.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(node.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                SafetyBadge(safetyClass: node.safetyClass)
            }
            HStack(spacing: 8) {
                Text(node.actionKind.label)
                if let owner = node.ownerHint {
                    Text(owner)
                }
                Text(node.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
        }
    }
}

struct OwnerStorageView: View {
    let summaries: [OwnerStorageSummary]

    private var total: Int64 {
        max(1, summaries.reduce(0) { $0 + $1.allocatedSize })
    }

    var body: some View {
        SectionBox(title: "Top Owners") {
            if summaries.isEmpty {
                Text("No ownership summary is available for this scan.")
                    .foregroundStyle(.secondary)
            } else {
                GeometryReader { proxy in
                    let width = max(proxy.size.width, 1)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(summaries.prefix(8)) { summary in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 10) {
                                    Image(systemName: icon(for: summary))
                                        .foregroundStyle(color(for: summary))
                                        .frame(width: 18)
                                    Text(summary.ownerName)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(ByteFormat.string(summary.allocatedSize))
                                        .font(.subheadline.monospacedDigit())
                                }

                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(.quaternary.opacity(0.35))
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(color(for: summary).opacity(0.75))
                                        .frame(width: max(6, width * CGFloat(Double(summary.allocatedSize) / Double(total))))
                                }
                                .frame(height: 12)

                                HStack(spacing: 10) {
                                    Text(summary.dominantCategory)
                                    Text("\(summary.count) item(s)")
                                    Text("safe \(ByteFormat.string(summary.expectedAutoSafeBytes))")
                                    Text("review \(ByteFormat.string(summary.reviewBytes))")
                                    Text("protected \(ByteFormat.string(summary.protectedBytes))")
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            }
                        }
                    }
                }
                .frame(height: CGFloat(min(summaries.count, 8)) * 66)
            }
        }
    }

    private func color(for summary: OwnerStorageSummary) -> Color {
        if summary.isReclaimable { return .green }
        switch summary.safetyClass {
        case .autoSafe: return .green
        case .safeAfterCondition: return .blue
        case .reviewRequired: return .orange
        case .preserveByDefault: return .purple
        case .neverTouch: return .red
        case nil: return .gray
        }
    }

    private func icon(for summary: OwnerStorageSummary) -> String {
        if summary.isReclaimable { return "checkmark.circle" }
        switch summary.safetyClass {
        case .autoSafe: return "checkmark.circle"
        case .safeAfterCondition: return "pause.circle"
        case .reviewRequired: return "magnifyingglass.circle"
        case .preserveByDefault: return "archivebox"
        case .neverTouch: return "lock.shield"
        case nil: return "questionmark.circle"
        }
    }
}

struct GrowthHistoryView: View {
    let snapshots: [ScanSnapshot]
    let deltas: [BucketGrowthDelta]
    let onExport: () -> Void
    let onExportRedacted: () -> Void

    var body: some View {
        SectionBox(title: "Growth History") {
            if snapshots.count < 2 {
                Text("Run another scan to compare growth. Snapshots are local-only and stored under Application Support.")
                    .foregroundStyle(.secondary)
            } else {
                let current = snapshots[0]
                let previous = snapshots[1]
                HStack {
                    Text("Compared \(previous.createdAt.formatted()) to \(current.createdAt.formatted()).")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        onExport()
                    } label: {
                        Label("Export Growth", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    Button {
                        onExportRedacted()
                    } label: {
                        Label("Redacted", systemImage: "eye.slash")
                    }
                }
                ForEach(deltas.prefix(8)) { delta in
                    HStack {
                        Text(delta.name)
                            .lineLimit(1)
                        Spacer()
                        Text(delta.deltaAllocatedSize >= 0 ? "+\(ByteFormat.string(delta.deltaAllocatedSize))" : ByteFormat.string(delta.deltaAllocatedSize))
                            .foregroundStyle(delta.deltaAllocatedSize >= 0 ? .orange : .green)
                            .monospacedDigit()
                    }
                    .font(.caption)
                }
            }
        }
    }
}

struct TopOffendersView: View {
    let model: DashboardModel

    private var table: TopOffenderTable? {
        model.presentationSnapshot?.topOffenders
    }

    private var displayedRows: [TopOffenderRow] {
        Array(table?.rows.prefix(14) ?? [])
    }

    private var displayedSections: [TopOffenderGroupSection] {
        (table?.sections ?? []).map { section in
            TopOffenderGroupSection(group: section.group, key: section.key, title: section.title, rows: Array(section.rows.prefix(8)))
        }
    }

    private var selectedPlanIDs: Set<Finding.ID> {
        Set(model.plan?.items.filter(\.selected).map { $0.finding.id } ?? [])
    }

    var body: some View {
        SectionBox(title: "Top Offenders") {
            HStack(spacing: 12) {
                Picker("Sort", selection: Binding(
                    get: { model.presentationTopOffenderSort },
                    set: { sort in
                        Task {
                            await model.setTopOffenderPresentation(
                                sort: sort,
                                group: model.presentationTopOffenderGroup
                            )
                        }
                    }
                )) {
                    ForEach(TopOffenderSort.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)

                Picker("Group", selection: Binding(
                    get: { model.presentationTopOffenderGroup },
                    set: { group in
                        Task {
                            await model.setTopOffenderPresentation(
                                sort: model.presentationTopOffenderSort,
                                group: group
                            )
                        }
                    }
                )) {
                    ForEach(TopOffenderGroup.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)

                Spacer()
            }

            if let table {
                HStack(spacing: 10) {
                    MetricTile(title: "Rows", value: "\(table.rowCount)")
                    MetricTile(title: "Estimated Reclaim", value: ByteFormat.string(table.estimatedImmediateReclaim))
                    MetricTile(title: "Allocated", value: ByteFormat.string(table.allocatedSize))
                }
            }

            TopOffenderTableScrollContainer {
                if model.presentationTopOffenderGroup == .none {
                    ForEach(displayedRows) { row in
                        TopOffenderRowView(row: row, isSelectedInPlan: selectedPlanIDs.contains(row.finding.id))
                    }
                } else {
                    ForEach(displayedSections) { section in
                        Divider()
                        HStack {
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                            Text("\(section.count) item(s)")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(ByteFormat.string(section.estimatedImmediateReclaim))
                                .foregroundStyle(section.estimatedImmediateReclaim > 0 ? .green : .secondary)
                                .monospacedDigit()
                            Text(ByteFormat.string(section.allocatedSize))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                        ForEach(section.rows) { row in
                            TopOffenderRowView(row: row, isSelectedInPlan: selectedPlanIDs.contains(row.finding.id))
                        }
                    }
                }
            }

            ForEach(table?.nonClaims ?? [], id: \.self) { note in
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
