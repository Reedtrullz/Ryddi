import SwiftUI
import ReclaimerCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

private enum RyddiWindowLayout {
    static let minimumContentWidth: CGFloat = 1260
    static let minimumContentHeight: CGFloat = 760
    static let defaultContentWidth: CGFloat = 1480
    static let defaultContentHeight: CGFloat = 940
    static let topOffenderTableMinimumWidth: CGFloat = 1160
}

enum DashboardResponsiveGrid {
    static var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 170, maximum: 320), spacing: 12, alignment: .top)]
    }

    static var actionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 118, maximum: 190), spacing: 10, alignment: .leading)]
    }
}

@main
struct MacDiskReclaimerApp: App {
    @State private var statusModel = StatusMenuModel()

    var body: some Scene {
        WindowGroup("Ryddi", id: "dashboard") {
            DashboardView()
                .frame(
                    minWidth: RyddiWindowLayout.minimumContentWidth,
                    minHeight: RyddiWindowLayout.minimumContentHeight
                )
        }
        .defaultSize(width: RyddiWindowLayout.defaultContentWidth, height: RyddiWindowLayout.defaultContentHeight)
        .windowResizability(.contentMinSize)
        MenuBarExtra {
            StatusMenuView(model: statusModel)
        } label: {
            Label(statusModel.menuTitle, systemImage: statusModel.symbolName)
        }
        .menuBarExtraStyle(.window)
        Settings {
            SettingsView()
        }
    }
}

struct DashboardView: View {
    @State private var model = DashboardModel()
    @State private var selectedFinding: Finding.ID?
    @State private var selectedSection = DashboardLaunchOptions.initialSection
    @State private var showingReclaimConfirmation = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if selectedSection == "Features" {
                CapabilityMatrixView()
            } else if selectedSection == "Rules" {
                RuleCatalogView()
            } else if selectedSection == "Apps" {
                AppReviewView(model: model)
            } else if selectedSection == "Queues" {
                ReviewQueuesView(model: model) { finding in
                    selectedFinding = finding.id
                    selectedSection = "Finding"
                }
            } else if selectedSection == "LargeOld" {
                LargeOldReviewView(model: model)
            } else if selectedSection == "Duplicates" {
                DuplicateReviewView(model: model)
            } else if selectedSection == "Downloads" {
                DownloadsReviewView(model: model)
            } else if selectedSection == "Browsers" {
                BrowserCacheReviewView(model: model)
            } else if selectedSection == "Packages" {
                PackageCacheReviewView(model: model)
            } else if selectedSection == "Projects" {
                ProjectDependencyReviewView(model: model)
            } else if selectedSection == "DeviceBackups" {
                DeviceBackupReviewView(model: model)
            } else if selectedSection == "Xcode" {
                XcodeReviewView(model: model)
            } else if selectedSection == "Trash" {
                TrashReviewView(model: model)
            } else if selectedSection == "Containers" {
                ContainerInventoryView(model: model)
            } else if selectedSection == "RemoteTargets" {
                RemoteTargetsView(model: model)
            } else if selectedSection == "Agents" {
                AgentStorageReviewView(model: model)
            } else if selectedSection == "Permissions" {
                PermissionOnboardingView(model: model)
            } else if selectedSection == "Active" {
                ActiveFileReviewView(model: model)
            } else if selectedSection == "Scopes" {
                SavedScopeSetView(model: model)
            } else if selectedSection == "Policy" {
                UserPathPolicyView(model: model)
            } else if selectedSection == "Audit" {
                AuditHistoryView(model: model)
            } else if selectedSection == "Recovery" {
                RecoveryCenterView(model: model)
            } else if selectedSection == "Holding" {
                HoldingView(model: model)
            } else if selectedSection == "Automation" {
                AutomationView(model: model)
            } else if let finding = model.findings.first(where: { $0.id == selectedFinding }) {
                FindingDetailView(model: model, finding: finding, planItem: model.planItem(for: finding.id))
            } else {
                OverviewView(
                    model: model,
                    onReclaim: { showingReclaimConfirmation = true },
                    navigate: { section in
                        selectedFinding = nil
                        selectedSection = section
                    }
                )
            }
        }
        .toolbar {
            Picker("Scan Mode", selection: Binding(
                get: { model.scanPreset },
                set: { model.setScanPreset($0) }
            )) {
                ForEach(ScanScopePreset.allCases) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)

            Picker("Saved Scope", selection: Binding(
                get: { model.selectedSavedScopeSetID ?? "" },
                set: { model.setSavedScopeSet($0.isEmpty ? nil : $0) }
            )) {
                Text("No saved scope").tag("")
                ForEach(model.savedScopeSets) { set in
                    Text(set.name).tag(set.id)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 190)
            .disabled(model.savedScopeSets.isEmpty)

            Button {
                Task { await model.scan() }
            } label: {
                Label("Scan", systemImage: "magnifyingglass")
            }
            .disabled(model.isWorking)

            Button {
                Task { await model.buildPlan() }
            } label: {
                Label("Plan", systemImage: "checklist")
            }
            .disabled(model.findings.isEmpty || model.isWorking)

            Menu {
                Picker("Template", selection: Binding(
                    get: { model.selectedScopeTemplateID ?? "" },
                    set: { model.setScopeTemplate($0.isEmpty ? nil : $0) }
                )) {
                    Text("No template").tag("")
                    ForEach(model.scopeTemplates) { template in
                        Text(template.name).tag(template.id)
                    }
                }
                Toggle(isOn: Binding(
                    get: { model.includeUserRulesInScans },
                    set: { model.setIncludeUserRulesInScans($0) }
                )) {
                    Label("Include User Rules", systemImage: "slider.horizontal.3")
                }
                Divider()
                Button {
                    Task { await model.runDryRun() }
                } label: {
                    Label("Dry Run", systemImage: "play.circle")
                }
                .disabled(model.plan == nil && model.findings.isEmpty)
                Button {
                    Task { await model.exportEvidenceReport() }
                } label: {
                    Label("Export Report", systemImage: "square.and.arrow.up")
                }
                .disabled(model.overview == nil || model.findings.isEmpty)
                Button {
                    Task { await model.exportEvidenceReport(pathStyle: .redacted, redactUserText: true) }
                } label: {
                    Label("Export Redacted", systemImage: "eye.slash")
                }
                .disabled(model.overview == nil || model.findings.isEmpty)
                Divider()
                Button(role: .destructive) {
                    showingReclaimConfirmation = true
                } label: {
                    Label("Reclaim", systemImage: "trash")
                }
                .disabled(!model.canReclaimSelected || selectedSection == "RemoteTargets")
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
        .confirmationDialog("Reclaim selected auto-safe items?", isPresented: $showingReclaimConfirmation) {
            Button("Reclaim Selected", role: .destructive) {
                Task { await model.reclaimSelected() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.reclaimConfirmationMessage)
        }
        .onAppear {
            model.loadSavedScopeSets()
            model.loadAudit()
            model.loadHolding()
            model.loadRecovery()
            model.loadHistory()
            model.loadUserPolicy()
            model.refreshAutomation()
            model.refreshPermissions()
            model.refreshRemoteTargets()
            model.applyScreenshotDemoIfNeeded()
        }
    }

    private var sidebar: some View {
        List {
            Section("Start") {
                sidebarRow("Summary", systemImage: "gauge.with.dots.needle", section: "Summary")
                sidebarRow("Review Queues", systemImage: "tray.full", section: "Queues")
                sidebarRow("Large & Old Files", systemImage: "archivebox", section: "LargeOld")
            }

            Section("General Mac") {
                sidebarRow("Apps & Leftovers", systemImage: "app.dashed", section: "Apps")
                sidebarRow("Downloads", systemImage: "arrow.down.circle", section: "Downloads")
                sidebarRow("Duplicates", systemImage: "doc.on.doc", section: "Duplicates")
                sidebarRow("Browser Caches", systemImage: "globe", section: "Browsers")
                sidebarRow("Device Backups", systemImage: "iphone", section: "DeviceBackups")
                sidebarRow("Trash", systemImage: "trash", section: "Trash")
            }

            Section("Developer") {
                sidebarRow("Package Caches", systemImage: "shippingbox", section: "Packages")
                sidebarRow("Project Dependencies", systemImage: "folder", section: "Projects")
                sidebarRow("Xcode", systemImage: "hammer", section: "Xcode")
                sidebarRow("Containers", systemImage: "cube.box", section: "Containers")
                sidebarRow("Remote Targets", systemImage: "server.rack", section: "RemoteTargets")
                sidebarRow("AI Agent Storage", systemImage: "brain.head.profile", section: "Agents")
            }

            Section("Trust") {
                sidebarRow("Permissions", systemImage: "lock.shield", section: "Permissions")
                sidebarRow("Active Handles", systemImage: "waveform.path.ecg", section: "Active")
                sidebarRow("Scope Sets", systemImage: "scope", section: "Scopes")
                sidebarRow("Protections", systemImage: "hand.raised", section: "Policy")
                sidebarRow("Audit History", systemImage: "clock.arrow.circlepath", section: "Audit")
                sidebarRow("Recovery Center", systemImage: "arrow.uturn.backward.circle", section: "Recovery")
                sidebarRow("Holding Area", systemImage: "tray", section: "Holding")
                sidebarRow("Automation", systemImage: "calendar.badge.clock", section: "Automation")
                sidebarRow("Rule Catalog", systemImage: "list.bullet.rectangle", section: "Rules")
                sidebarRow("Feature Matrix", systemImage: "square.grid.2x2", section: "Features")
            }

            Section("Review Queues") {
                ForEach(model.queueSummaries) { queue in
                    DisclosureGroup("\(queue.title) (\(queue.count), \(ByteFormat.string(queue.allocatedSize)))") {
                        Text(queue.guidance)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(model.findings(in: queue.queueID)) { finding in
                            FindingRow(finding: finding)
                                .tag(finding.id)
                                .onTapGesture {
                                    selectedFinding = finding.id
                                    selectedSection = "Finding"
                                }
                        }
                    }
                }
            }
        }
        .navigationTitle("Ryddi")
        .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 320)
    }

    private func sidebarRow(_ title: String, systemImage: String, section: String) -> some View {
        Button {
            selectedFinding = nil
            selectedSection = section
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(selectedSection == section ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .listRowBackground(selectedSection == section ? Color.accentColor.opacity(0.16) : Color.clear)
    }
}

enum DashboardLaunchOptions {
    static var isScreenshotDemo: Bool {
        ProcessInfo.processInfo.environment["RYDDI_SCREENSHOT_DEMO"] == "1"
    }

    static var initialSection: String {
        guard isScreenshotDemo else { return "Summary" }
        let raw = ProcessInfo.processInfo.environment["RYDDI_SCREENSHOT_SECTION"] ?? "Summary"
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "queues", "review-queues":
            return "Queues"
        case "packages", "package-cache", "package-caches":
            return "Packages"
        case "agents", "ai-agent-storage":
            return "Agents"
        case "remote", "remote-targets", "remotetargets":
            return "RemoteTargets"
        default:
            return "Summary"
        }
    }
}

struct OverviewView: View {
    let model: DashboardModel
    let onReclaim: () -> Void
    let navigate: (String) -> Void

    private var topRows: [TopOffenderRow] {
        Array(FindingAnalytics.topOffenderTable(findings: model.findings, sort: .allocated, group: .none, limit: 8).rows)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DashboardHeroView(model: model)

                if model.isWorking {
                    ProgressView("Working")
                        .controlSize(.large)
                }

                GuidedSummaryView(
                    model: model,
                    report: model.actionCenterReport,
                    onReclaim: onReclaim,
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

                DashboardPlanPanel(model: model, onReclaim: onReclaim)
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
    let onReclaim: () -> Void
    let navigate: (String) -> Void

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
            Task { await model.scan() }
        }
        DashboardActionButton("Plan", systemImage: "checklist", disabled: model.findings.isEmpty || model.isWorking) {
            Task { await model.buildPlan() }
        }
        DashboardActionButton("Dry Run", systemImage: "play.circle", disabled: (model.plan == nil && model.findings.isEmpty) || model.isWorking) {
            Task { await model.runDryRun() }
        }
        DashboardActionButton("Review Queues", systemImage: "tray.full", disabled: model.findings.isEmpty) {
            navigate("Queues")
        }
        DashboardActionButton("Export", systemImage: "square.and.arrow.up", disabled: model.overview == nil || model.findings.isEmpty || model.isWorking) {
            Task { await model.exportEvidenceReport(pathStyle: .redacted, redactUserText: true) }
        }
        DashboardActionButton("Reclaim", systemImage: "trash", role: .destructive, disabled: !model.canReclaimSelected) {
            onReclaim()
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
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text("Full Disk Access review recommended")
                    .font(.headline)
                Text("\(report.readableCount) of \(report.totalCount) configured scopes are readable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                PathActions.openFullDiskAccessSettings()
            } label: {
                Label("Open Full Disk Access", systemImage: "lock.shield")
            }
            .buttonStyle(.borderedProminent)
            Button {
                onReviewPermissions()
            } label: {
                Label("Review Permissions", systemImage: "arrow.right.circle")
            }
            .buttonStyle(.bordered)
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
}

struct DashboardQueuePanel: View {
    let model: DashboardModel
    let navigate: (String) -> Void

    var body: some View {
        SectionBox(title: "Review Queues") {
            VStack(spacing: 8) {
                ForEach(model.queueSummaries.prefix(6)) { queue in
                    Button {
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
    let onReclaim: () -> Void

    var body: some View {
        SectionBox(title: "Plan") {
            if let plan = model.plan {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        MetricTile(title: "Selected", value: "\(plan.items.filter(\.selected).count)")
                        MetricTile(title: "Expected reclaim", value: ByteFormat.string(plan.expectedImmediateReclaim))
                        MetricTile(title: "Dry run", value: model.canReclaimSelected ? "Clear" : "Needed")
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
                        Button(role: .destructive) {
                            onReclaim()
                        } label: {
                            Label("Reclaim Selected", systemImage: "trash")
                        }
                        .disabled(!model.canReclaimSelected)
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
            ("Plan report", model.lastPlanReportExportURL)
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
                MetricTile(title: "Scan Coverage", value: report.permissionSummary.coverageLevel.label)
                MetricTile(title: "Safe Reclaim", value: ByteFormat.string(report.latestPlanSummary?.expectedImmediateReclaim ?? 0))
                MetricTile(title: "Automation", value: report.automationInstalled ? "Report-only" : "Off")
                MetricTile(title: "Quit First", value: countActions(.quitAppFirst))
                MetricTile(title: "Native Tool", value: countActions(.useNativeTool))
                MetricTile(title: "Valuable History", value: countActions(.protectByDefault))
                MetricTile(title: "Release Trust", value: report.releaseTrustEvidence.state.label)
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
        ("Reclaim safely", "Executor supports Trash, direct cache delete, compression, and app-managed holding area with protected-class refusal."),
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
                        Text("Review what Ryddi can restore directly, what needs Finder Trash review, and what requires native tools or backups.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        model.loadAudit()
                        model.loadHolding()
                        model.loadRecovery()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }

                HStack(spacing: 16) {
                    MetricTile(title: "Recovery items", value: "\(model.recoveryReport.itemCount)")
                    MetricTile(title: "Restorable", value: "\(model.recoveryReport.restorableCount)")
                    MetricTile(title: "Held bytes", value: ByteFormat.string(model.recoveryReport.restorableBytes))
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

                SectionBox(title: "Restorable With Ryddi") {
                    let restorable = model.recoveryReport.items.filter(\.canRestoreWithRyddi)
                    if restorable.isEmpty {
                        Text("No app-held items are currently restorable by Ryddi.")
                    } else {
                        ForEach(restorable) { item in
                            RecoveryItemRow(item: item) {
                                model.restoreRecoveryItem(item)
                            }
                            Divider()
                        }
                    }
                }

                SectionBox(title: "Receipt Guidance") {
                    let guidanceItems = model.recoveryReport.items.filter { !$0.canRestoreWithRyddi }
                    if guidanceItems.isEmpty {
                        Text("No saved receipt actions need recovery guidance.")
                    } else {
                        ForEach(guidanceItems.prefix(30)) { item in
                            RecoveryItemRow(item: item, onRestore: nil)
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
    let onRestore: (() -> Void)?

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
                if let onRestore {
                    Button {
                        onRestore()
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                }
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
                Text("Current: \(currentPath)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Container Inventory")
                            .font(.largeTitle.bold())
                        Text("Read-only Docker and Colima inspection for VM, image, volume, and build-cache decisions.")
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
                        Text("Held items are reversible until restored or expired. Restore refuses to overwrite existing destinations.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Refresh") {
                        model.loadHolding()
                    }
                }

                if model.heldItems.isEmpty {
                    ContentUnavailableView("No held items", systemImage: "archivebox", description: Text("Quarantine-hold actions will appear here."))
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
                                Button("Restore") {
                                    model.restoreHeldItem(item)
                                }
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

struct PackageCacheReviewView: View {
    let model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Package Cache Review")
                            .font(.largeTitle.bold())
                        Text("Review Homebrew, npm, pnpm, Yarn, pip, Cargo, Go, Gradle, Maven, CocoaPods, SwiftPM, and Playwright cache roots separately from config and auth state.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        Task { await model.reviewPackageCaches() }
                    } label: {
                        Label("Review Package Caches", systemImage: "shippingbox")
                    }
                    .disabled(model.isWorking)
                }

                if let report = model.packageCacheReview {
                    let lane = PackageReclaimLaneBuilder.build(from: report)

                    HStack(spacing: 16) {
                        MetricTile(title: "Candidates", value: ByteFormat.string(report.candidateBytes))
                        MetricTile(title: "Allocated", value: ByteFormat.string(report.totalAllocatedSize))
                        MetricTile(title: "Measured items", value: "\(report.itemCount)")
                        MetricTile(title: "Cache roots", value: "\(report.rootSummaries.count)")
                        MetricTile(title: "Protected config", value: "\(report.protectedConfigRoots.count)")
                    }

                    PackageReclaimLaneView(report: lane)

                    SectionBox(title: "By Package Manager") {
                        if report.managerSummaries.isEmpty {
                            Text("No package cache items found in readable cache roots.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(report.managerSummaries) { summary in
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
                                        Text(root.manager.label)
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
                                    Text(root.nativeCleanupHint)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
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
                            Text("No package cache items found in readable cache roots.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Allocated").frame(width: 92, alignment: .leading)
                                    Text("Manager").frame(width: 92, alignment: .leading)
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
                                            Text(item.manager.label)
                                                .frame(width: 92, alignment: .leading)
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

                    SectionBox(title: "Protected Config And Auth Paths") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(report.protectedConfigRoots) { protectedRoot in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(protectedRoot.manager.label)
                                            .font(.caption.weight(.semibold))
                                        Text(protectedRoot.permissionState.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(protectedRoot.path)
                                        .font(.system(.caption2, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                    Text(protectedRoot.note)
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
                    ContentUnavailableView("No package cache review yet", systemImage: "shippingbox", description: Text("Run Package Cache Review to inspect package-manager cache roots without measuring or modifying protected config/auth state."))
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

struct PackageReclaimLaneView: View {
    let report: PackageReclaimLaneReport

    var body: some View {
        SectionBox(title: "Native Preview Lane") {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: DashboardResponsiveGrid.metricColumns, spacing: 12) {
                    MetricTile(title: "Preview scope", value: ByteFormat.string(report.totalPreviewBytes))
                    MetricTile(title: "Managers", value: "\(report.managerReports.count)")
                }

                if report.managerReports.isEmpty {
                    Text("No package manager cache summaries were found.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(report.managerReports) { manager in
                            packageManagerRow(manager)
                            if manager.id != report.managerReports.last?.id {
                                Divider()
                            }
                        }
                    }
                }

                ForEach(report.nonClaims.prefix(2), id: \.self) { note in
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func packageManagerRow(_ manager: PackageReclaimManagerReport) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(manager.managerName)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(ByteFormat.string(manager.cacheBytes))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(manager.explanation)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            commandLine(label: "Preview", command: manager.previewCommand, fallback: "Manual review")
            commandLine(label: "Cleanup", command: manager.cleanupCommand, fallback: "No allowlisted cleanup command")
            ForEach(manager.commandCards) { card in
                packageCommandCard(card)
            }
        }
    }

    private func packageCommandCard(_ card: PackageReclaimCommandCard) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(card.title)
                    .font(.caption2.weight(.semibold))
                Text(card.review == .manualReview ? "Manual review" : "Safe action")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(card.review == .manualReview ? .orange : .green)
                Text(card.role.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(card.argv.joined(separator: " "))
                .font(.system(.caption2, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Text(card.note)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 3)
    }

    private func commandLine(label: String, command: [String], fallback: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(command.isEmpty ? fallback : command.joined(separator: " "))
                .font(.system(.caption2, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

struct ProjectDependencyReviewView: View {
    let model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Project Dependencies")
                            .font(.largeTitle.bold())
                        Text("Review project-local dependencies and build artifacts such as node_modules, .venv, .build, target, Pods, .dart_tool, framework caches, and mobile build output.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        Task { await model.reviewProjectDependencies() }
                    } label: {
                        Label("Review Projects", systemImage: "folder")
                    }
                    .disabled(model.isWorking)
                }

                if let report = model.projectDependencyReview {
                    HStack(spacing: 16) {
                        MetricTile(title: "Candidates", value: ByteFormat.string(report.candidateBytes))
                        MetricTile(title: "Rebuildable", value: ByteFormat.string(report.rebuildableBytes))
                        MetricTile(title: "Needs review", value: ByteFormat.string(report.reviewRequiredBytes))
                        MetricTile(title: "Measured items", value: "\(report.itemCount)")
                        MetricTile(title: "Project roots", value: "\(report.rootSummaries.count)")
                        MetricTile(title: "Workspaces", value: "\(report.workspaceRootCount)")
                        MetricTile(title: "VCS changes", value: "\(report.projectsWithDirtyVCSCount)")
                        MetricTile(title: "Skipped policy", value: "\(report.policySkippedProjects.count)")
                    }

                    HStack(alignment: .top, spacing: 16) {
                        SectionBox(title: "By Ecosystem") {
                            if report.ecosystemSummaries.isEmpty {
                                Text("No project dependency candidates found in readable roots.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(report.ecosystemSummaries) { summary in
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

                        SectionBox(title: "By Kind") {
                            if report.kindSummaries.isEmpty {
                                Text("No project dependency kinds found.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(report.kindSummaries) { summary in
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

                        SectionBox(title: "By VCS") {
                            if report.vcsSummaries.isEmpty {
                                Text("No VCS state was reported.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(report.vcsSummaries) { summary in
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

                        SectionBox(title: "By Policy") {
                            if report.policySummaries.isEmpty {
                                Text("No saved project policies matched measured items.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(report.policySummaries) { summary in
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
                    }

                    HStack(alignment: .top, spacing: 16) {
                        SectionBox(title: "By Tool") {
                            if report.toolSummaries.isEmpty {
                                Text("No project tool evidence was detected.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(report.toolSummaries) { summary in
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

                        SectionBox(title: "Package Scripts") {
                            if report.scriptSummaries.isEmpty {
                                Text("No package.json scripts were accepted for review.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(report.scriptSummaries.prefix(12)) { summary in
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

                        SectionBox(title: "Script Risk") {
                            if report.scriptRiskSummaries.isEmpty {
                                Text("No package.json script command previews were classified.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(report.scriptRiskSummaries) { summary in
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

                        SectionBox(title: "By Workspace") {
                            if report.workspaceSummaries.isEmpty {
                                Text("No workspace or monorepo evidence was detected.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(report.workspaceSummaries.prefix(12)) { summary in
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
                    }

                    SectionBox(title: "Project Roots") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(report.rootSummaries) { root in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(root.permissionState.rawValue)
                                            .font(.caption.weight(.semibold))
                                        Text("\(root.candidateCount) candidate(s)")
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
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Divider()
                            }
                        }
                    }

                    SectionBox(title: "Largest Project Dependency Items") {
                        if report.largestItems.isEmpty {
                            Text("No project dependency candidates found in readable roots.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Allocated").frame(width: 92, alignment: .leading)
                                    Text("Ecosystem").frame(width: 92, alignment: .leading)
                                    Text("Kind").frame(width: 142, alignment: .leading)
                                    Text("VCS").frame(width: 112, alignment: .leading)
                                    Text("Age").frame(width: 70, alignment: .leading)
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
                                            Text(item.ecosystem.label)
                                                .frame(width: 92, alignment: .leading)
                                            Text(item.kind.label)
                                                .frame(width: 142, alignment: .leading)
                                            Text(item.vcsInfo.state.label)
                                                .frame(width: 112, alignment: .leading)
                                            Text(item.ageDays.map { "\($0)d" } ?? "unknown")
                                                .frame(width: 70, alignment: .leading)
                                                .monospacedDigit()
                                            Text(item.path)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                                .textSelection(.enabled)
                                            Spacer()
                                        }
                                        .font(.caption)
                                        Text(item.projectName)
                                            .font(.caption2.weight(.semibold))
                                        if item.toolingInfo.toolName != nil {
                                            Text("\(item.toolingInfo.toolLabel)\(item.toolingInfo.toolSource.map { " from \($0)" } ?? "")")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        if !item.toolingInfo.packageScripts.isEmpty {
                                            Text("Scripts: \(item.toolingInfo.packageScripts.prefix(12).joined(separator: ", "))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        ForEach(item.toolingInfo.scriptReviews.prefix(4)) { review in
                                            Text("Script review: \(review.name) [\(review.risk.label)] \(review.commandPreview)")
                                                .font(.caption2)
                                                .foregroundStyle(review.isCommandHintEligible ? Color.secondary : Color.orange)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        if item.workspaceInfo.isWorkspace {
                                            Text("Workspace: \(item.workspaceInfo.label)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                            if let workspaceRoot = item.workspaceInfo.rootPath {
                                                Text(workspaceRoot)
                                                    .font(.system(.caption2, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                                    .textSelection(.enabled)
                                            }
                                            if !item.workspaceInfo.packagePatterns.isEmpty {
                                                Text("Workspace packages: \(item.workspaceInfo.packagePatterns.prefix(12).joined(separator: ", "))")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                        Text(item.vcsInfo.summary)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        ForEach(item.commandHints.prefix(3), id: \.id) { command in
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("\(command.command) - \(command.purpose)")
                                                if let workingDirectory = command.workingDirectory {
                                                    Text("cwd: \(workingDirectory)")
                                                        .lineLimit(1)
                                                        .truncationMode(.middle)
                                                }
                                                if let context = command.context {
                                                    Text(context)
                                                }
                                            }
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                        }
                                        if let decision = item.projectPolicyDecision {
                                            Text("\(decision.label)\(item.projectPolicyReason.map { ": \($0)" } ?? "")")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
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

                    SectionBox(title: "Protected Project Roots") {
                        if report.protectedProjectRoots.isEmpty {
                            Text("No protected project roots were inferred from candidates.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(report.protectedProjectRoots) { protectedRoot in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(protectedRoot.projectName)
                                            .font(.caption.weight(.semibold))
                                        Text(protectedRoot.projectRootPath)
                                            .font(.system(.caption2, design: .monospaced))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .textSelection(.enabled)
                                        if !protectedRoot.manifestHints.isEmpty {
                                            Text(protectedRoot.manifestHints.joined(separator: ", "))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        if protectedRoot.toolingInfo.toolName != nil {
                                            Text("\(protectedRoot.toolingInfo.toolLabel)\(protectedRoot.toolingInfo.toolSource.map { " from \($0)" } ?? "")")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        if !protectedRoot.toolingInfo.packageScripts.isEmpty {
                                            Text("Scripts: \(protectedRoot.toolingInfo.packageScripts.prefix(12).joined(separator: ", "))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        ForEach(protectedRoot.toolingInfo.scriptReviews.prefix(4)) { review in
                                            Text("Script review: \(review.name) [\(review.risk.label)] \(review.commandPreview)")
                                                .font(.caption2)
                                                .foregroundStyle(review.isCommandHintEligible ? Color.secondary : Color.orange)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        if protectedRoot.workspaceInfo.isWorkspace {
                                            Text("Workspace: \(protectedRoot.workspaceInfo.label)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                            if let workspaceRoot = protectedRoot.workspaceInfo.rootPath {
                                                Text(workspaceRoot)
                                                    .font(.system(.caption2, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                                    .textSelection(.enabled)
                                            }
                                        }
                                        Text("\(protectedRoot.vcsInfo.state.label): \(protectedRoot.vcsInfo.summary)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        if let decision = protectedRoot.projectPolicyDecision {
                                            Text("\(decision.label)\(protectedRoot.projectPolicyReason.map { ": \($0)" } ?? "")")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        Text(protectedRoot.note)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Divider()
                                }
                            }
                        }
                    }

                    SectionBox(title: "Skipped By Policy") {
                        if report.policySkippedProjects.isEmpty {
                            Text("No projects were skipped by saved Project Dependencies policy.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(report.policySkippedProjects) { skipped in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(skipped.projectName) - \(skipped.decision.label)")
                                            .font(.caption.weight(.semibold))
                                        Text(skipped.projectRootPath)
                                            .font(.system(.caption2, design: .monospaced))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .textSelection(.enabled)
                                        if let reason = skipped.reason {
                                            Text(reason)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        if let workspace = skipped.workspaceInfo, workspace.isWorkspace {
                                            Text("Workspace: \(workspace.label)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        Text(skipped.note)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Divider()
                                }
                            }
                        }
                    }

                    SectionBox(title: "Guidance") {
                        ForEach(report.guidance, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
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
                    ContentUnavailableView("No project dependency review yet", systemImage: "folder", description: Text("Run Project Dependencies to inspect project-local dependency and build folders without modifying project files."))
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

struct DeviceBackupReviewView: View {
    let model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Device Backups Review")
                            .font(.largeTitle.bold())
                        Text("Review local iPhone and iPad MobileSync backups as valuable restore points, with size, age, encryption, and metadata evidence.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        Task { await model.reviewDeviceBackups() }
                    } label: {
                        Label("Review Device Backups", systemImage: "iphone")
                    }
                    .disabled(model.isWorking)
                }

                if let report = model.deviceBackupReview {
                    HStack(spacing: 16) {
                        MetricTile(title: "Backups", value: "\(report.backupCount)")
                        MetricTile(title: "Allocated", value: ByteFormat.string(report.totalAllocatedSize))
                        MetricTile(title: "Old review", value: ByteFormat.string(report.staleBackupBytes))
                        MetricTile(title: "Encrypted", value: ByteFormat.string(report.encryptedBackupBytes))
                        MetricTile(title: "Metadata gaps", value: "\(report.missingMetadataCount)")
                    }

                    SectionBox(title: "Backup Root") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(report.permissionState.rawValue)
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text(ByteFormat.string(report.totalAllocatedSize))
                                    .font(.caption.monospacedDigit())
                            }
                            Text(report.rootPath)
                                .font(.system(.caption2, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            ForEach(report.notes, id: \.self) { note in
                                Text(note)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 16) {
                        SectionBox(title: "By Encryption") {
                            if report.encryptionSummaries.isEmpty {
                                Text("No backup encryption evidence yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(report.encryptionSummaries) { summary in
                                        HStack {
                                            Text(summary.name)
                                            Spacer()
                                            Text("\(summary.backupCount)")
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

                        SectionBox(title: "By Metadata") {
                            if report.metadataSummaries.isEmpty {
                                Text("No backup metadata evidence yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(report.metadataSummaries) { summary in
                                        HStack {
                                            Text(summary.name)
                                            Spacer()
                                            Text("\(summary.backupCount)")
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
                    }

                    SectionBox(title: "Largest Device Backups") {
                        if report.largestBackups.isEmpty {
                            Text("No device backups found at the configured root.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Allocated").frame(width: 92, alignment: .leading)
                                    Text("Encryption").frame(width: 96, alignment: .leading)
                                    Text("Metadata").frame(width: 86, alignment: .leading)
                                    Text("Age").frame(width: 70, alignment: .leading)
                                    Text("Backup")
                                    Spacer()
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                ForEach(report.largestBackups.prefix(40)) { backup in
                                    Divider()
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(ByteFormat.string(backup.allocatedSize))
                                                .frame(width: 92, alignment: .leading)
                                                .monospacedDigit()
                                            Text(backup.encryptionState.label)
                                                .frame(width: 96, alignment: .leading)
                                            Text(backup.metadataState.label)
                                                .frame(width: 86, alignment: .leading)
                                            Text(backup.ageDays.map { "\($0)d" } ?? "unknown")
                                                .frame(width: 70, alignment: .leading)
                                                .monospacedDigit()
                                            Text(backup.displayName)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                            Spacer()
                                        }
                                        .font(.caption)
                                        Text(backup.path)
                                            .font(.system(.caption2, design: .monospaced))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .textSelection(.enabled)
                                        Text(backup.recommendation)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
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
                                .fixedSize(horizontal: false, vertical: true)
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
                    ContentUnavailableView("No device backup review yet", systemImage: "iphone", description: Text("Run Device Backups Review to inspect MobileSync backup size, age, encryption, and metadata without modifying backups."))
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

struct XcodeReviewView: View {
    let model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Xcode Review")
                            .font(.largeTitle.bold())
                        Text("Review Xcode build caches, archives, device support, simulator state, runtimes, logs, and protected developer settings separately.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        Task { await model.reviewXcode() }
                    } label: {
                        Label("Review Xcode", systemImage: "hammer")
                    }
                    .disabled(model.isWorking)
                }

                if let report = model.xcodeReview {
                    HStack(spacing: 16) {
                        MetricTile(title: "Rebuildable", value: ByteFormat.string(report.rebuildableCacheBytes))
                        MetricTile(title: "Needs review", value: ByteFormat.string(report.reviewRequiredBytes))
                        MetricTile(title: "Simulator state", value: ByteFormat.string(report.simulatorStateBytes))
                        MetricTile(title: "Measured items", value: "\(report.itemCount)")
                        MetricTile(title: "Xcode roots", value: "\(report.rootSummaries.count)")
                    }

                    SectionBox(title: "By Xcode Kind") {
                        if report.kindSummaries.isEmpty {
                            Text("No Xcode items found in readable roots.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(report.kindSummaries) { summary in
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

                    SectionBox(title: "Xcode Roots") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(report.rootSummaries) { root in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(root.kind.label)
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
                                    Text(root.nativeCleanupHint)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(root.note)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Divider()
                            }
                        }
                    }

                    SectionBox(title: "Largest Xcode Items") {
                        if report.largestItems.isEmpty {
                            Text("No Xcode items found in readable roots.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Allocated").frame(width: 92, alignment: .leading)
                                    Text("Kind").frame(width: 142, alignment: .leading)
                                    Text("Age").frame(width: 70, alignment: .leading)
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
                                            Text(item.kind.label)
                                                .frame(width: 142, alignment: .leading)
                                            Text(item.ageDays.map { "\($0)d" } ?? "unknown")
                                                .frame(width: 70, alignment: .leading)
                                                .monospacedDigit()
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

                    SectionBox(title: "Protected Xcode Developer State") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(report.protectedStateRoots) { protectedRoot in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(protectedRoot.permissionState.rawValue)
                                        .font(.caption.weight(.semibold))
                                    Text(protectedRoot.path)
                                        .font(.system(.caption2, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                    Text(protectedRoot.note)
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
                                .fixedSize(horizontal: false, vertical: true)
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
                    ContentUnavailableView("No Xcode review yet", systemImage: "hammer", description: Text("Run Xcode Review to inspect developer caches, archives, device support, simulator state, and protected Xcode settings without modifying files."))
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

struct AppReviewView: View {
    let model: DashboardModel
    @State private var includeSystemApps = false
    @State private var includeOrphans = true
    @State private var showSkipped = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Apps & Leftovers")
                            .font(.largeTitle.bold())
                        Text("Review installed apps, related support files, heuristic orphan candidates, and manual uninstall previews. Related files stay review-only.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        Task { await model.reviewApps(includeSystemApps: includeSystemApps, includeOrphans: includeOrphans) }
                    } label: {
                        Label("Review Apps", systemImage: "app.dashed")
                    }
                    .disabled(model.isWorking)
                }

                HStack {
                    Toggle("Include system apps", isOn: $includeSystemApps)
                        .toggleStyle(.switch)
                    Toggle("Include orphan candidates", isOn: $includeOrphans)
                        .toggleStyle(.switch)
                }

                if let report = model.appReview {
                    HStack(spacing: 16) {
                        MetricTile(title: "Installed apps", value: "\(report.installedApps.count)")
                        MetricTile(title: "Related groups", value: "\(report.installedAppGroups.count)")
                        MetricTile(title: "Orphan groups", value: "\(report.orphanGroups.count)")
                        MetricTile(title: "Review bytes", value: ByteFormat.string(report.reviewBytes))
                    }

                    SectionBox(title: "Review Notes") {
                        ForEach(report.notes, id: \.self) { note in
                            Text(note)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let preview = model.appUninstallPreview {
                        AppUninstallPreviewView(preview: preview, model: model)
                    }

                    SectionBox(title: "Installed Apps With Related Files") {
                        if report.installedAppGroups.isEmpty {
                            Text("No installed-app related files matched the current threshold.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(report.installedAppGroups.prefix(20)) { group in
                                AppReviewGroupView(group: group) {
                                    Task { await model.previewAppUninstall(group: group) }
                                }
                            }
                        }
                    }

                    SectionBox(title: "Orphan Candidates") {
                        if report.orphanGroups.isEmpty {
                            Text("No orphan candidates matched the current options.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(report.orphanGroups.prefix(20)) { group in
                                AppReviewGroupView(group: group)
                            }
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
                    ContentUnavailableView("No app review yet", systemImage: "app.dashed", description: Text("Run an app review to inspect installed-app support files and possible leftovers."))
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
    @State private var confirmTrash = false

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

                    Button(role: .destructive) {
                        confirmTrash = true
                    } label: {
                        Label("Move App To Trash", systemImage: "trash")
                    }
                    .disabled(model.isWorking || !model.canTrashPreviewedApp)
                    .help("Move only the selected app bundle to Trash after a clean dry run.")
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
        .confirmationDialog("Move app bundle to Trash?", isPresented: $confirmTrash) {
            Button("Move App To Trash", role: .destructive) {
                Task { await model.trashPreviewedApp() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only \(preview.selectedApp.displayName).app is moved. Related support files stay review-only.")
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

struct FindingRow: View {
    let finding: Finding

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(finding.displayName)
                    .lineLimit(1)
                Text(ByteFormat.string(finding.allocatedSize))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SafetyBadge(safetyClass: finding.safetyClass)
        }
    }
}

struct FindingDetailView: View {
    let model: DashboardModel
    let finding: Finding
    let planItem: ReclaimPlanItem?
    @State private var pendingNativeCommand: NativeToolCommand?

    private var explanation: FindingExplanationReport {
        FindingExplanationBuilder.build(for: finding)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(finding.displayName)
                    .font(.largeTitle.bold())
                Text(finding.path)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    SafetyBadge(safetyClass: finding.safetyClass)
                    Text(finding.actionKind.label)
                    Text(ByteFormat.string(finding.allocatedSize))
                    Text(finding.reviewNextAction.label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                SectionBox(title: "Summary") {
                    Text(explanation.summary)
                    Text(explanation.cleanupPermission)
                        .foregroundStyle(.secondary)
                    Text(explanation.removalEffect)
                        .foregroundStyle(.secondary)
                }

                SectionBox(title: "What this is") {
                    ForEach(explanation.whatThisIs, id: \.self) { line in
                        Text(line)
                            .foregroundStyle(line.hasPrefix("Accounting") ? Color.secondary : Color.primary)
                    }
                }

                SectionBox(title: "Actions") {
                    FindingActionButtons(finding: finding)
                }

                SectionBox(title: "Why this classification") {
                    ForEach(explanation.whyMatched, id: \.self) { line in
                        Text("- \(line)")
                    }
                }

                SectionBox(title: "Risk and exact action") {
                    Text(explanation.riskSummary)
                    Text(explanation.exactAction)
                    Text(explanation.cleanupPermission)
                        .foregroundStyle(.secondary)
                }

                SectionBox(title: "Recovery and conditions") {
                    ForEach(explanation.recovery, id: \.self) { line in
                        Text(line)
                    }
                    if !explanation.conditions.isEmpty {
                        Divider()
                    }
                    ForEach(explanation.conditions, id: \.self) { line in
                        Text("- \(line)")
                            .foregroundStyle(.secondary)
                    }
                }

                if let nativeReceipt = explanation.nativeToolReceipt {
                    SectionBox(title: "Native tool receipt preview") {
                        Text(nativeReceipt.message)
                            .foregroundStyle(.secondary)
                        ForEach(nativeReceipt.commands) { command in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(command.command)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                Text("\(command.risk.label) • \(command.requiresReview ? "review first" : "inspect")")
                                    .font(.caption)
                                    .foregroundStyle(command.risk == .destructive ? .red : .secondary)
                                Text(command.purpose)
                                Text("Expected effect: \(command.expectedEffect)")
                                    .foregroundStyle(.secondary)
                                if let workingDirectory = command.workingDirectory {
                                    Text("Working directory: \(workingDirectory)")
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                }
	                                if let context = command.context {
	                                    Text(context)
	                                        .foregroundStyle(.secondary)
	                                }
	                                let performBlockReason = model.nativePerformBlockReason(receipt: nativeReceipt, command: command)
	                                HStack {
	                                    Button {
	                                        Task { await model.runNativeToolCommand(receipt: nativeReceipt, command: command, perform: false) }
	                                    } label: {
	                                        Label("Dry Run", systemImage: "doc.text.magnifyingglass")
	                                    }
	                                    if performBlockReason == nil {
	                                        Button {
	                                            pendingNativeCommand = command
	                                        } label: {
	                                            Label("Run", systemImage: "terminal")
	                                        }
	                                    }
	                                }
	                                if let performBlockReason {
	                                    Text(performBlockReason)
	                                        .font(.caption)
	                                        .foregroundStyle(.secondary)
	                                        .fixedSize(horizontal: false, vertical: true)
	                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } else {
                    if !explanation.guidanceCommands.isEmpty {
                        SectionBox(title: "Guidance") {
                            ForEach(explanation.guidanceCommands, id: \.self) { line in
                                Text(line)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }

                SectionBox(title: "Next steps") {
                    ForEach(explanation.nextSteps, id: \.self) { line in
                        Text(line)
                    }
                    Divider()
                    ForEach(explanation.nonClaims, id: \.self) { note in
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let planItem {
                    SectionBox(title: "Plan status") {
                        Text(planItem.selected ? "Selected for dry-run/action." : "Not selected automatically.")
                        Text("Estimated immediate reclaim: \(ByteFormat.string(planItem.estimatedImmediateReclaim))")
                        ForEach(planItem.conditions, id: \.message) { condition in
                            Text("\(condition.isSatisfied ? "OK" : "Blocked"): \(condition.message)")
                                .foregroundStyle(condition.isSatisfied ? Color.secondary : Color.orange)
                        }
                    }
                }
            }
            .padding(24)
        }
        .confirmationDialog(
            "Run native command?",
            isPresented: Binding(
                get: { pendingNativeCommand != nil },
                set: { if !$0 { pendingNativeCommand = nil } }
            ),
            presenting: pendingNativeCommand
        ) { command in
            Button("Run \(command.command)", role: .destructive) {
                if let nativeReceipt = explanation.nativeToolReceipt {
                    Task { await model.runNativeToolCommand(receipt: nativeReceipt, command: command, perform: true) }
                }
                pendingNativeCommand = nil
            }
            Button("Cancel", role: .cancel) {
                pendingNativeCommand = nil
            }
        } message: { command in
            Text("Ryddi will execute exactly this native-tool command and save a local receipt: \(command.command)")
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
                Button("Remove Schedule") {
                    model.removeSchedule()
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
                Text("\(report.readableCount) of \(report.totalCount) expected scopes readable")
                    .font(.headline)
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

struct PermissionOnboardingView: View {
    let model: DashboardModel
    private var walkthrough: PermissionWalkthrough {
        PermissionWalkthroughBuilder.build(report: model.permissionReport)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Permissions")
                    .font(.largeTitle.bold())
                Text("Ryddi can still scan in degraded mode. This page shows what macOS currently lets it read and what evidence is missing.")
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    MetricTile(title: "Coverage", value: model.permissionReport.coverageLevel.label)
                    MetricTile(title: "Readable", value: "\(model.permissionReport.readableCount)/\(model.permissionReport.totalCount)")
                    MetricTile(title: "Denied", value: "\(model.permissionReport.deniedCount)")
                    MetricTile(title: "Missing", value: "\(model.permissionReport.missingCount)")
                }

                PermissionAccessHelperPanel(
                    report: model.permissionReport,
                    onRefresh: { model.refreshPermissions() }
                )

                SectionBox(title: "Next Steps") {
                    ForEach(model.permissionReport.recommendedActions, id: \.self) { action in
                        Text(action)
                    }
                    Button {
                        PathActions.openFullDiskAccessSettings()
                    } label: {
                        Label("Open Full Disk Access Settings", systemImage: "lock.shield")
                    }
                    .help("Open macOS Privacy & Security settings for Full Disk Access")
                }

                SectionBox(title: "First-run Walkthrough") {
                    ForEach(walkthrough.steps) { step in
                        PermissionWalkthroughStepRow(step: step)
                        if step.id != walkthrough.steps.last?.id {
                            Divider()
                        }
                    }
                }

                SectionBox(title: "Scope Readback") {
                    ForEach(model.permissionReport.scopeSummaries) { scope in
                        HStack(alignment: .firstTextBaseline) {
                            Text(scope.permissionState.rawValue)
                                .font(.caption.bold())
                                .foregroundStyle(scope.permissionState == .readable ? .green : .orange)
                                .frame(width: 78, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(scope.name)
                                    .font(.headline)
                                Text(scope.path)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                Text(scope.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        Divider()
                    }
                }

                SectionBox(title: "Non-claims") {
                    ForEach(model.permissionReport.nonClaims, id: \.self) { note in
                        Text(note)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
        }
    }
}

struct PermissionAccessHelperPanel: View {
    let report: PermissionAdvisorReport
    let onRefresh: () -> Void

    private var unavailableScopes: [ScopeAccessSummary] {
        report.unavailableScopes.sorted { lhs, rhs in
            if lhs.permissionState != rhs.permissionState {
                return lhs.permissionState.rawValue < rhs.permissionState.rawValue
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        SectionBox(title: "Access Helper") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        PathActions.openFullDiskAccessSettings()
                    } label: {
                        Label("Open Full Disk Access", systemImage: "lock.shield")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Open macOS Privacy & Security settings for Full Disk Access")

                    Button {
                        PathActions.revealApplicationInFinder()
                    } label: {
                        Label("Reveal Ryddi", systemImage: "app.dashed")
                    }
                    .help("Reveal the installed app so it can be added to Full Disk Access if missing.")

                    Button {
                        PathActions.copyText(PathActions.applicationPath)
                    } label: {
                        Label("Copy App Path", systemImage: "doc.on.doc")
                    }
                    .help(PathActions.applicationPath)

                    Spacer()

                    Button {
                        onRefresh()
                    } label: {
                        Label("Refresh Coverage", systemImage: "arrow.clockwise")
                    }
                    .help("Re-check which configured scopes are currently readable.")
                }
                .buttonStyle(.bordered)

                Text("macOS requires you to grant Full Disk Access manually. Add or enable Ryddi, return here, then refresh coverage or run a fresh scan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if unavailableScopes.isEmpty {
                    Label("All configured scopes are readable in the current scope plan.", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Restricted or missing scopes")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(unavailableScopes.prefix(8)) { scope in
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
                        if unavailableScopes.count > 8 {
                            Text("\(unavailableScopes.count - 8) more scope(s)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
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
    let findings: [Finding]
    let plan: ReclaimPlan?
    @State private var sort = TopOffenderSort.allocated
    @State private var group = TopOffenderGroup.none

    private var table: TopOffenderTable {
        FindingAnalytics.topOffenderTable(findings: findings, sort: sort, group: group, limit: 80)
    }

    private var displayedRows: [TopOffenderRow] {
        Array(table.rows.prefix(14))
    }

    private var displayedSections: [TopOffenderGroupSection] {
        table.sections.map { section in
            TopOffenderGroupSection(group: section.group, key: section.key, title: section.title, rows: Array(section.rows.prefix(8)))
        }
    }

    private var selectedPlanIDs: Set<Finding.ID> {
        Set(plan?.items.filter(\.selected).map { $0.finding.id } ?? [])
    }

    var body: some View {
        SectionBox(title: "Top Offenders") {
            HStack(spacing: 12) {
                Picker("Sort", selection: $sort) {
                    ForEach(TopOffenderSort.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)

                Picker("Group", selection: $group) {
                    ForEach(TopOffenderGroup.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)

                Spacer()
            }

            HStack(spacing: 10) {
                MetricTile(title: "Rows", value: "\(table.rowCount)")
                MetricTile(title: "Estimated Reclaim", value: ByteFormat.string(table.estimatedImmediateReclaim))
                MetricTile(title: "Allocated", value: ByteFormat.string(table.allocatedSize))
            }

            TopOffenderTableScrollContainer {
                if group == .none {
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

            ForEach(table.nonClaims, id: \.self) { note in
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ReviewQueuesView: View {
    let model: DashboardModel
    let onOpenFinding: (Finding) -> Void
    @State private var selectedQueue = ReviewQueueID.safeMaintenance

    private var report: ReviewQueueReport {
        model.reviewQueueReport
    }

    private var detailReport: ReviewQueueDetailReport {
        FindingAnalytics.reviewQueueDetailReport(
            findings: model.findings,
            queueID: selectedQueue,
            limit: 80
        )
    }

    private var selectedPlanIDs: Set<Finding.ID> {
        Set(model.plan?.items.filter(\.selected).map { $0.finding.id } ?? [])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Review Queues")
                            .font(.largeTitle.bold())
                        Text("Work through scan results by cleanup intent before making a dry-run plan.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Queue", selection: Binding(
                        get: { selectedQueue },
                        set: { queue in
                            selectedQueue = queue
                            model.recordReviewSelection(queue)
                        }
                    )) {
                        ForEach(ReviewQueueID.allCases) { queue in
                            Label(queue.title, systemImage: symbol(for: queue))
                                .tag(queue)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 240)
                }

                HStack(spacing: 12) {
                    MetricTile(title: "Queued", value: "\(report.totalCount)")
                    MetricTile(title: "Allocated", value: ByteFormat.string(report.totalAllocatedSize))
                    MetricTile(title: "Estimated Reclaim", value: ByteFormat.string(report.estimatedImmediateReclaim))
                    MetricTile(title: "Selected Queue", value: "\(detailReport.count)")
                    MetricTile(title: "Queue Bytes", value: ByteFormat.string(detailReport.allocatedSize))
                }

                if model.findings.isEmpty {
                    ContentUnavailableView("No scan yet", systemImage: "tray", description: Text("Run Scan to populate review queues."))
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        SectionBox(title: "Queues") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(report.queues) { queue in
                                    Button {
                                        selectedQueue = queue.queueID
                                        model.recordReviewSelection(queue.queueID)
                                    } label: {
                                        ReviewQueueSummaryRow(queue: queue, isSelected: selectedQueue == queue.queueID)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .frame(minWidth: 260)
                        }

                        SectionBox(title: detailReport.title) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(detailReport.guidance)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                HStack(spacing: 12) {
                                    MetricTile(title: "Rows Shown", value: "\(detailReport.rowCount)/\(detailReport.count)")
                                    MetricTile(title: "Reclaim", value: ByteFormat.string(detailReport.estimatedImmediateReclaim))
                                    MetricTile(title: "Risk", value: detailReport.highestRiskClass?.label ?? "-")
                                    MetricTile(title: "Dominant", value: detailReport.dominantCategory)
                                }

                                if detailReport.rows.isEmpty {
                                    ContentUnavailableView("No findings in this queue", systemImage: "checkmark.circle", description: Text("This scan did not produce matching rows."))
                                } else {
                                    TopOffenderTableScrollContainer(includesDetailAction: true) {
                                        ForEach(detailReport.rows) { row in
                                            TopOffenderRowView(
                                                row: row,
                                                isSelectedInPlan: selectedPlanIDs.contains(row.finding.id),
                                                onOpenDetail: onOpenFinding
                                            )
                                        }
                                    }
                                }

                                Divider()
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Non-Claims")
                                        .font(.headline)
                                    ForEach(detailReport.nonClaims, id: \.self) { note in
                                        Text(note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
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
    }

    private func symbol(for queue: ReviewQueueID) -> String {
        switch queue {
        case .safeMaintenance: "checkmark.shield"
        case .quitAppFirst: "pause.circle"
        case .useNativeTool: "terminal"
        case .valuableHistory: "archivebox"
        case .personalAppAssets: "person.crop.square"
        case .unknown: "questionmark.circle"
        }
    }
}

struct ReviewQueueSummaryRow: View {
    let queue: ReviewQueueSummary
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(queue.title)
                        .font(.headline)
                    Spacer()
                    Text(ByteFormat.string(queue.allocatedSize))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Count")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("\(queue.count)")
                            .font(.caption.monospacedDigit())
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bytes")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(ByteFormat.string(queue.allocatedSize))
                            .font(.caption.monospacedDigit())
                    }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next action")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(reviewQueueNextAction.label)
                        .font(.caption)
                }
                Text("Why blocked")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(reviewQueueBlockedReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(queue.guidance)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        }
    }

    private var symbol: String {
        switch queue.queueID {
        case .safeMaintenance: "checkmark.shield"
        case .quitAppFirst: "pause.circle"
        case .useNativeTool: "terminal"
        case .valuableHistory: "archivebox"
        case .personalAppAssets: "person.crop.square"
        case .unknown: "questionmark.circle"
        }
    }

    private var reviewQueueNextAction: ReviewNextAction {
        switch queue.queueID {
        case .safeMaintenance: .safeMaintenance
        case .quitAppFirst: .quitAppFirst
        case .useNativeTool: .useNativeTool
        case .valuableHistory: .archiveCandidate
        case .personalAppAssets: .protectByDefault
        case .unknown: .reviewInFinder
        }
    }

    private var reviewQueueBlockedReason: String {
        switch queue.queueID {
        case .safeMaintenance:
            queue.estimatedImmediateReclaim > 0
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

struct LargeOldReviewView: View {
    let model: DashboardModel
    @State private var mode = LargeOldReviewMode.all
    @State private var sort = TopOffenderSort.allocated

    private var report: LargeOldReviewReport {
        model.largeOldReviewReport(mode: mode, sort: sort, limit: 80)
    }

    private var archiveReport: ArchiveReviewReport {
        model.archiveReviewReport(mode: mode, sort: sort, limit: 40)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Large & Old Files")
                    .font(.largeTitle.bold())
                Spacer()
                Picker("Mode", selection: $mode) {
                    ForEach(LargeOldReviewMode.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                Picker("Sort", selection: $sort) {
                    Text("Allocated").tag(TopOffenderSort.allocated)
                    Text("Logical").tag(TopOffenderSort.logical)
                    Text("Age").tag(TopOffenderSort.age)
                    Text("Category").tag(TopOffenderSort.category)
                    Text("Owner").tag(TopOffenderSort.owner)
                    Text("Safety").tag(TopOffenderSort.safety)
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 12) {
                MetricTile(title: "Items", value: "\(report.totalCount)")
                MetricTile(title: "Allocated", value: ByteFormat.string(report.totalAllocatedSize))
                MetricTile(title: "Large", value: "\(report.largeCount)")
                MetricTile(title: "Old", value: "\(report.oldCount)")
                MetricTile(title: "Protected", value: ByteFormat.string(report.protectedBytes))
            }

            if model.findings.isEmpty {
                ContentUnavailableView("No scan yet", systemImage: "doc.text.magnifyingglass", description: Text("Run Scan to build a large and old file review."))
            } else if report.rows.isEmpty {
                ContentUnavailableView("No large or old review rows", systemImage: "checkmark.circle", description: Text("No current findings matched the selected review mode."))
            } else {
                HStack(alignment: .top, spacing: 14) {
                    ReviewSummaryList(title: "Signals", summaries: report.kindSummaries)
                    ReviewSummaryList(title: "Categories", summaries: Array(report.categorySummaries.prefix(6)))
                    ReviewSummaryList(title: "Safety", summaries: report.safetySummaries)
                }

                ArchiveCandidatePanel(
                    report: archiveReport,
                    onExport: { Task { await model.exportArchiveReview(mode: mode, sort: sort) } },
                    onExportRedacted: { Task { await model.exportArchiveReview(mode: mode, sort: sort, pathStyle: .redacted) } }
                )

                if let url = model.lastArchiveReviewExportURL {
                    Text("Latest archive review: \(url.path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                SectionBox(title: "Review Rows") {
                    TopOffenderTableScrollContainer {
                        ForEach(report.rows) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                TopOffenderRowView(row: row.row, isSelectedInPlan: false)
                                Text(row.reviewReason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 10)
                            }
                        }
                    }
                }
            }

            SectionBox(title: "Non-Claims") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(report.nonClaims, id: \.self) { note in
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let error = model.error {
                Text(error)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(24)
    }
}

struct ArchiveCandidatePanel: View {
    let report: ArchiveReviewReport
    let onExport: () -> Void
    let onExportRedacted: () -> Void

    var body: some View {
        SectionBox(title: "Archive Candidates") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    MetricTile(title: "Candidates", value: "\(report.candidateCount)")
                    MetricTile(title: "Archive", value: ByteFormat.string(report.archiveCandidateBytes))
                    MetricTile(title: "Trash Review", value: ByteFormat.string(report.trashReviewBytes))
                    MetricTile(title: "Cleanup Plan", value: ByteFormat.string(report.cleanupPlanBytes))
                    MetricTile(title: "Blocked", value: ByteFormat.string(report.blockedBytes))
                }

                HStack {
                    ForEach(report.recommendationSummaries.prefix(6)) { summary in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.name)
                                .font(.caption.weight(.semibold))
                            Text("\(summary.count) item(s), \(ByteFormat.string(summary.allocatedSize))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 110, alignment: .leading)
                    }
                    Spacer()
                    Button {
                        onExport()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        onExportRedacted()
                    } label: {
                        Label("Redacted", systemImage: "eye.slash")
                    }
                }

                if report.rows.isEmpty {
                    Text("No archive candidates matched the selected large/old review mode.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Recommendation").frame(width: 120, alignment: .leading)
                            Text("Size").frame(width: 86, alignment: .leading)
                            Text("Age").frame(width: 48, alignment: .leading)
                            Text("Safety").frame(width: 150, alignment: .leading)
                            Text("Path")
                            Spacer()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        ForEach(report.rows.prefix(8)) { row in
                            Divider()
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(row.recommendation.label)
                                        .frame(width: 120, alignment: .leading)
                                    Text(ByteFormat.string(row.allocatedSize))
                                        .frame(width: 86, alignment: .leading)
                                    Text(row.ageDays.map { "\($0)d" } ?? "-")
                                        .frame(width: 48, alignment: .leading)
                                        .foregroundStyle(.secondary)
                                    SafetyBadge(safetyClass: row.safetyClass)
                                        .frame(width: 150, alignment: .leading)
                                    Text(row.path)
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                    Spacer()
                                }
                                Text(row.rationale)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }

                ForEach(report.nonClaims.prefix(2), id: \.self) { note in
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ReviewSummaryList: View {
    let title: String
    let summaries: [BucketSummary]

    var body: some View {
        SectionBox(title: title) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(summaries) { summary in
                    HStack {
                        Text(summary.name)
                            .lineLimit(1)
                        Spacer()
                        Text(ByteFormat.string(summary.allocatedSize))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.caption)
                }
            }
            .frame(minWidth: 180)
        }
    }
}

struct TopOffenderTableScrollContainer<Rows: View>: View {
    var includesDetailAction = false
    @ViewBuilder let rows: Rows

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(spacing: 0) {
                TopOffenderHeader(includesDetailAction: includesDetailAction)
                rows
            }
            .frame(minWidth: RyddiWindowLayout.topOffenderTableMinimumWidth, alignment: .leading)
        }
    }
}

struct TopOffenderHeader: View {
    var includesDetailAction = false

    var body: some View {
        HStack {
            Text("Reclaim").frame(width: 86, alignment: .leading)
            Text("Size").frame(width: 86, alignment: .leading)
            Text("Confidence").frame(width: 92, alignment: .leading)
            Text("Safety").frame(width: 150, alignment: .leading)
            Text("Category").frame(width: 130, alignment: .leading)
            Text("Owner").frame(width: 110, alignment: .leading)
            Text("Next").frame(width: 124, alignment: .leading)
            Text("Age").frame(width: 48, alignment: .leading)
            Text("Path")
            Spacer()
            Text("Actions").frame(width: includesDetailAction ? 164 : 132, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
    }
}

struct TopOffenderRowView: View {
    let row: TopOffenderRow
    let isSelectedInPlan: Bool
    let onOpenDetail: ((Finding) -> Void)?

    init(
        row: TopOffenderRow,
        isSelectedInPlan: Bool,
        onOpenDetail: ((Finding) -> Void)? = nil
    ) {
        self.row = row
        self.isSelectedInPlan = isSelectedInPlan
        self.onOpenDetail = onOpenDetail
    }

    var body: some View {
        Divider()
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ByteFormat.string(row.estimatedImmediateReclaim))
                    .foregroundStyle(row.estimatedImmediateReclaim > 0 ? .green : .secondary)
                Text(row.reclaimabilityLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 86, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(ByteFormat.string(row.allocatedSize))
                Text(ByteFormat.string(row.logicalSize))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 86, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.confidence.label)
                    .foregroundStyle(confidenceColor)
                if isSelectedInPlan {
                    Text("In plan")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            .frame(width: 92, alignment: .leading)
            SafetyBadge(safetyClass: row.safetyClass)
                .frame(width: 150, alignment: .leading)
            Text(row.category)
                .frame(width: 130, alignment: .leading)
                .lineLimit(1)
            Text(row.ownerName)
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)
            Text(row.nextAction.label)
                .font(.caption)
                .foregroundStyle(nextActionColor)
                .frame(width: 124, alignment: .leading)
                .lineLimit(1)
            Text(row.ageDays.map { "\($0)d" } ?? "-")
                .frame(width: 48, alignment: .leading)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName)
                    .lineLimit(1)
                Text(row.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            HStack(spacing: 4) {
                if let onOpenDetail {
                    Button {
                        onOpenDetail(row.finding)
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .help("Open evidence detail")
                }
                FindingActionButtons(finding: row.finding)
            }
            .buttonStyle(.borderless)
            .frame(width: onOpenDetail == nil ? 132 : 164, alignment: .trailing)
        }
        .padding(.vertical, 7)
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

struct FindingActionButtons: View {
    let finding: Finding

    var body: some View {
        HStack(spacing: 4) {
            Button {
                PathActions.copyPath(finding.path)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy path")

            Button {
                PathActions.revealInFinder(finding.path)
            } label: {
                Image(systemName: "folder")
            }
            .help("Reveal in Finder")

            Button {
                PathActions.quickLook(finding.path)
            } label: {
                Image(systemName: "eye")
            }
            .help("Quick Look")

            Button {
                PathActions.openTerminal(at: finding.path, isDirectory: finding.isDirectory)
            } label: {
                Image(systemName: "terminal")
            }
            .help("Open Terminal here")
        }
        .buttonStyle(.borderless)
    }
}

struct DuplicateFileActionButtons: View {
    let file: DuplicateFile

    var body: some View {
        HStack(spacing: 4) {
            Button {
                PathActions.copyPath(file.path)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy path")

            Button {
                PathActions.revealInFinder(file.path)
            } label: {
                Image(systemName: "folder")
            }
            .help("Reveal in Finder")

            Button {
                PathActions.quickLook(file.path)
            } label: {
                Image(systemName: "eye")
            }
            .help("Quick Look")

            Button {
                PathActions.openTerminal(at: file.path, isDirectory: false)
            } label: {
                Image(systemName: "terminal")
            }
            .help("Open Terminal here")
        }
        .buttonStyle(.borderless)
    }
}

struct AppReviewItemActionButtons: View {
    let item: AppReviewItem

    var body: some View {
        HStack(spacing: 4) {
            Button {
                PathActions.copyPath(item.path)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy path")

            Button {
                PathActions.revealInFinder(item.path)
            } label: {
                Image(systemName: "folder")
            }
            .help("Reveal in Finder")

            Button {
                PathActions.quickLook(item.path)
            } label: {
                Image(systemName: "eye")
            }
            .help("Quick Look")

            Button {
                PathActions.openTerminal(at: item.path, isDirectory: item.isDirectory)
            } label: {
                Image(systemName: "terminal")
            }
            .help("Open Terminal here")
        }
        .buttonStyle(.borderless)
    }
}

struct DownloadsReviewItemActionButtons: View {
    let item: DownloadsReviewItem

    var body: some View {
        HStack(spacing: 4) {
            Button {
                PathActions.copyPath(item.path)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy path")

            Button {
                PathActions.revealInFinder(item.path)
            } label: {
                Image(systemName: "folder")
            }
            .help("Reveal in Finder")

            Button {
                PathActions.quickLook(item.path)
            } label: {
                Image(systemName: "eye")
            }
            .help("Quick Look")

            Button {
                PathActions.openTerminal(at: item.path, isDirectory: item.isDirectory)
            } label: {
                Image(systemName: "terminal")
            }
            .help("Open Terminal here")
        }
        .buttonStyle(.borderless)
    }
}

struct AppUninstallCandidateActionButtons: View {
    let candidate: AppUninstallCandidate

    var body: some View {
        HStack(spacing: 4) {
            Button {
                PathActions.copyPath(candidate.path)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy path")

            Button {
                PathActions.revealInFinder(candidate.path)
            } label: {
                Image(systemName: "folder")
            }
            .help("Reveal in Finder")

            Button {
                PathActions.quickLook(candidate.path)
            } label: {
                Image(systemName: "eye")
            }
            .help("Quick Look")

            Button {
                PathActions.openTerminal(at: candidate.path, isDirectory: candidate.isDirectory)
            } label: {
                Image(systemName: "terminal")
            }
            .help("Open Terminal here")
        }
        .buttonStyle(.borderless)
    }
}

enum PathActions {
    static var applicationPath: String {
        #if os(macOS)
        Bundle.main.bundleURL.path
        #else
        ""
        #endif
    }

    static func copyPath(_ path: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        #endif
    }

    static func copyText(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    static func revealInFinder(_ path: String) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        #endif
    }

    static func revealApplicationInFinder() {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        #endif
    }

    static func quickLook(_ path: String) {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-p", path]
        try? process.run()
        #endif
    }

    static func openTerminal(at path: String, isDirectory: Bool) {
        #if os(macOS)
        let target = isDirectory ? path : URL(fileURLWithPath: path).deletingLastPathComponent().path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", target]
        try? process.run()
        #endif
    }

    static func openFullDiskAccessSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

struct SafetyBadge: View {
    let safetyClass: SafetyClass

    var body: some View {
        Text(safetyClass.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch safetyClass {
        case .autoSafe: .green
        case .safeAfterCondition: .blue
        case .reviewRequired: .orange
        case .preserveByDefault: .purple
        case .neverTouch: .red
        }
    }
}

struct SectionBox<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
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

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Automation") {
                Text("Scheduled maintenance is report-first. Preview from the CLI or install the selected scope from Automation after reviewing a dry run.")
            }
            Section("Privacy") {
                Text("No paths, filenames, app lists, or cleanup history leave this Mac.")
            }
        }
        .padding()
        .frame(width: 520)
    }
}

struct StatusMenuView: View {
    @Bindable var model: StatusMenuModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ryddi")
                        .font(.headline)
                    Text(model.diskStatus.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                DiskPressureBadge(pressure: model.diskStatus.pressure)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(model.diskStatus.statusLine)
                    .font(.title3.bold())
                Text(model.diskStatus.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Last report scan")
                    Spacer()
                    Text(model.lastReportDate?.formatted(date: .omitted, time: .shortened) ?? "Not run")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Report findings")
                    Spacer()
                    Text(model.lastOverview.map { "\($0.findingCount)" } ?? "-")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Auto-safe bytes")
                    Spacer()
                    Text(model.lastOverview.map { ByteFormat.string($0.expectedAutoSafeBytes) } ?? "-")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Automation")
                    Spacer()
                    Text(model.launchAgentInstalled ? "Installed" : "Off")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            if model.isWorking {
                ProgressView("Working...")
            }

            if let error = model.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button {
                    openWindow(id: "dashboard")
                    #if os(macOS)
                    NSApp.activate(ignoringOtherApps: true)
                    #endif
                } label: {
                    Label("Open", systemImage: "macwindow")
                }

                Button {
                    model.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Button {
                    Task { await model.runReportScan() }
                } label: {
                    Label("Scan", systemImage: "magnifyingglass")
                }
                .disabled(model.isWorking)
            }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear {
            model.refresh()
        }
    }
}

struct DiskPressureBadge: View {
    let pressure: DiskPressureLevel

    var body: some View {
        Text(pressure.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch pressure {
        case .healthy: .green
        case .warning: .orange
        case .critical: .red
        case .unknown: .gray
        }
    }
}

@MainActor
@Observable
final class StatusMenuModel {
    var diskStatus: DiskStatusSnapshot = DiskStatusReader().snapshot()
    var lastOverview: ScanOverview?
    var lastReportDate: Date?
    var launchAgentInstalled = false
    var isWorking = false
    var error: String?

    var menuTitle: String {
        guard let freeBytes = diskStatus.displayFreeBytes else {
            return "Ryddi"
        }
        return "Ryddi \(ByteFormat.string(freeBytes))"
    }

    var symbolName: String {
        switch diskStatus.pressure {
        case .healthy: "externaldrive.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    func refresh() {
        diskStatus = DiskStatusReader().snapshot()
        launchAgentInstalled = FileManager.default.fileExists(atPath: LaunchAgentManager().installedPath().path)
        error = nil
    }

    func runReportScan() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await Task.detached {
                let scopes = DefaultScopes.scopes(for: .developer, includeUnavailable: true)
                let scanner = try FileScanner(openFileChecker: NoOpenFilesChecker())
                let findings = scanner.scan(scopes: scopes, options: ScanOptions(includeOpenFileStatus: false))
                let overview = FindingAnalytics.overview(findings: findings, scopes: scopes)
                _ = try ScanHistoryStore().save(overview: overview)
                return overview
            }.value
            lastOverview = result
            lastReportDate = Date()
            refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

@MainActor
@Observable
final class DashboardModel {
    var findings: [Finding] = []
    var scanScopes: [ScanScope] = []
    var scanPreset: ScanScopePreset = .developer
    var selectedScopeTemplateID: String?
    var savedScopeSets: [SavedScopeSet] = []
    var selectedSavedScopeSetID: String?
    var includeUserRulesInScans = false
    var lastScannedScopeLabel: String?
    var overview: ScanOverview?
    var diskDrillDown: DiskDrillDownReport?
    var plan: ReclaimPlan?
    var lastDryRunReceipt: ExecutionReceipt?
    var lastExecutionReceipt: ExecutionReceipt?
    var recentPlans: [ReclaimPlan] = []
    var recentReceipts: [ExecutionReceipt] = []
    var auditStoreSummary: AuditStoreSummary?
    var auditPrunePlan: AuditPrunePlan?
    var auditPruneReceipt: AuditPruneReceipt?
    var recentNativeToolReports: [NativeToolReport] = []
    var recentNativeToolExecutionReceipts: [NativeToolExecutionReceipt] = []
    var recentContainerInventoryReports: [ContainerInventoryReport] = []
    var recentRemoteProbeReports: [RemoteProbeReport] = []
    var recentRemoteScanReports: [RemoteScanReport] = []
    var recentRemoteDogfoodReports: [RemoteDogfoodReport] = []
    var recentActiveFileReviewReports: [ActiveFileReviewReport] = []
    var recentTrashReviewReports: [TrashReviewReport] = []
    var recentDownloadsReviewReports: [DownloadsReviewReport] = []
    var recentBrowserCacheReviewReports: [BrowserCacheReviewReport] = []
    var recentPackageCacheReviewReports: [PackageCacheReviewReport] = []
    var recentProjectDependencyReviewReports: [ProjectDependencyReviewReport] = []
    var recentDeviceBackupReviewReports: [DeviceBackupReviewReport] = []
    var recentXcodeReviewReports: [XcodeReviewReport] = []
    var recentAppUninstallReceipts: [AppUninstallExecutionReceipt] = []
    var heldItems: [HeldItem] = []
    var recoveryReport: RecoveryCenterReport = RecoveryCenter.build(heldItems: [], receipts: [])
    var duplicateReview: DuplicateReview?
    var appReview: AppReviewReport?
    var appUninstallPreview: AppUninstallPreview?
    var lastAppUninstallDryRunReceipt: AppUninstallExecutionReceipt?
    var lastAppUninstallReceipt: AppUninstallExecutionReceipt?
    var agentStorageReview: AgentStorageReview?
    var agentRetentionReport: AgentRetentionReport?
    var containerInventory: ContainerInventoryReport?
    var remoteTargets: [RemoteTargetReference] = []
    var remoteTargetInput = ""
    var remoteProbeReport: RemoteProbeReport?
    var remoteScanReport: RemoteScanReport?
    var remoteGrowthReport: RemoteGrowthReport?
    var remoteDogfoodReport: RemoteDogfoodReport?
    var currentRemoteDogfoodReport: RemoteDogfoodReport? {
        guard let dogfood = remoteDogfoodReport else { return nil }
        guard let scan = remoteScanReport else { return dogfood }
        return dogfood.target.id == scan.target.id ? dogfood : nil
    }
    var activeFileReview: ActiveFileReviewReport?
    var trashReview: TrashReviewReport?
    var downloadsReview: DownloadsReviewReport?
    var browserCacheReview: BrowserCacheReviewReport?
    var packageCacheReview: PackageCacheReviewReport?
    var projectDependencyReview: ProjectDependencyReviewReport?
    var deviceBackupReview: DeviceBackupReviewReport?
    var xcodeReview: XcodeReviewReport?
    var userPathPolicy: UserPathPolicy = .empty
    var lastReportExportURL: URL?
    var lastPlanReportExportURL: URL?
    var lastReceiptReportExportURL: URL?
    var lastGrowthReportExportURL: URL?
    var lastArchiveReviewExportURL: URL?
    var lastRemoteReportExportURL: URL?
    var lastRemoteGrowthReportExportURL: URL?
    var lastRemoteDogfoodReportExportURL: URL?
    var lastPolicyExportURL: URL?
    var lastScopeSetExportURL: URL?
    var lastScopeSetImportResult: SavedScopeSetImportResult?
    var diskStatus: DiskStatusSnapshot = DiskStatusReader().snapshot()
    var permissionReport: PermissionAdvisorReport = PermissionAdvisor.report(scopes: DefaultScopes.scopes(for: .developer, includeUnavailable: true))
    var scanSnapshots: [ScanSnapshot] = []
    var growthDeltas: [BucketGrowthDelta] = []
    var isWorking = false
    var lastScanDate: Date?
    var launchAgentInstalled = false
    var launchAgentStatus: LaunchAgentStatus = LaunchAgentManager().status()
    var error: String?
    var currentScanSession: ScanSession?
    var reviewedQueueID: ReviewQueueID?

    var selectedScopePlan: ScanScopePlan {
        if let selectedSavedScopeSet {
            return selectedSavedScopeSet.plan
        }
        if let selectedScopeTemplate {
            return selectedScopeTemplate.plan
        }
        return DefaultScopes.plan(for: scanPreset, includeUnavailable: true)
    }

    var currentAppUninstallReceipt: AppUninstallExecutionReceipt? {
        lastAppUninstallReceipt ?? lastAppUninstallDryRunReceipt
    }

    var canTrashPreviewedApp: Bool {
        guard let preview = appUninstallPreview,
              let receipt = lastAppUninstallDryRunReceipt,
              receipt.previewID == preview.id else {
            return false
        }
        return receipt.status == "dry-run"
            && receipt.errors.isEmpty
            && preview.bundleCandidate.disposition == .trashPreview
    }

    var scopeTemplates: [ScopeTemplate] {
        ScopeTemplateCatalog.all(includeUnavailable: true)
    }

    var selectedScopeTemplate: ScopeTemplate? {
        guard let selectedScopeTemplateID else { return nil }
        return try? ScopeTemplateCatalog.find(selectedScopeTemplateID, includeUnavailable: true)
    }

    var selectedSavedScopeSet: SavedScopeSet? {
        guard let selectedSavedScopeSetID else { return nil }
        return savedScopeSets.first { $0.id == selectedSavedScopeSetID }
    }

    var reviewQueueReport: ReviewQueueReport {
        FindingAnalytics.reviewQueueReport(findings: findings, limitPerQueue: 12)
    }

    var trustReadinessReport: TrustReadinessReport {
        TrustReadinessBuilder.build(
            diskStatus: diskStatus,
            permissionSummary: permissionReport,
            findings: findings,
            latestPlan: plan ?? recentPlans.first,
            latestReceipt: lastExecutionReceipt ?? lastDryRunReceipt ?? recentReceipts.first,
            automationInstalled: launchAgentStatus.installed,
            signingState: "App runtime; verify signed and notarized releases with the manifest",
            releaseTrustEvidence: ReleaseTrustEvidenceLoader.load()
        )
    }

    var guidedWorkflowReport: GuidedWorkflowReport {
        GuidedWorkflowBuilder.build(
            input: GuidedWorkflowInput(
                diskStatus: diskStatus,
                permissionSummary: permissionReport,
                findings: findings,
                latestPlan: plan ?? recentPlans.first,
                latestReceipt: lastExecutionReceipt ?? lastDryRunReceipt ?? recentReceipts.first,
                trustReadiness: trustReadinessReport
            )
        )
    }

    var actionCenterReport: ActionCenterReport {
        let scanSessionHistory = actionCenterScanSessionHistory
        return ActionCenterBuilder.build(
            input: ActionCenterInput(
                permissionReport: permissionReport,
                latestScanSession: actionCenterScanSession ?? scanSessionHistory.sessions.first,
                findings: findings,
                currentPlan: plan,
                latestExecutionReceipt: lastDryRunReceipt ?? lastExecutionReceipt,
                reviewQueueReport: reviewQueueReport,
                activeFileReviewReport: activeFileReview,
                browserCacheReport: browserCacheReview,
                packageCacheReport: packageCacheReview,
                latestNativeToolExecutionReceipt: recentNativeToolExecutionReceipts.first,
                sessionHistoryWarnings: scanSessionHistory.warnings
            )
        )
    }

    private var actionCenterScanSessionHistory: AuditStoreScanSessionListResult {
        (try? AuditStore().listScanSessionsResult(limit: 1)) ?? AuditStoreScanSessionListResult(sessions: [], warnings: [])
    }

    var actionCenterScanSession: ScanSession? {
        if let currentScanSession {
            return currentScanSession
        }
        return fallbackActionCenterScanSession
    }

    private var fallbackActionCenterScanSession: ScanSession? {
        guard overview != nil || !findings.isEmpty || plan != nil || lastDryRunReceipt != nil || lastExecutionReceipt != nil else {
            return nil
        }

        let updatedAt = lastExecutionReceipt?.createdAt
            ?? lastDryRunReceipt?.createdAt
            ?? plan?.createdAt
            ?? lastScanDate
            ?? Date()
        let hasFindingEvidence = overview != nil || !findings.isEmpty

        return ScanSession(
            id: "app-summary-\(actionCenterSessionStage.rawValue)",
            createdAt: lastScanDate ?? updatedAt,
            updatedAt: updatedAt,
            appVersion: actionCenterAppVersion,
            ruleVersion: actionCenterRuleVersion,
            preset: actionCenterPreset,
            scopeDigest: actionCenterScopeDigest,
            policyDigest: actionCenterPolicyDigest,
            findingDigest: hasFindingEvidence ? actionCenterFindingDigest : nil,
            planDigest: plan?.id,
            dryRunReceiptID: nil,
            executionReceiptID: lastExecutionReceipt?.id,
            stage: actionCenterSessionStage
        )
    }

    private var actionCenterSessionStage: ScanSessionStage {
        if lastExecutionReceipt != nil {
            return .executed
        }
        if lastDryRunReceipt != nil {
            return .dryRunReady
        }
        if plan != nil {
            return .planReady
        }
        if reviewedQueueID != nil {
            return .reviewed
        }
        return .scanned
    }

    private var actionCenterScopeDigest: String {
        ScanSessionEvidenceBuilder.scopeDigest(
            appVersion: actionCenterAppVersion,
            ruleVersion: actionCenterRuleVersion,
            preset: actionCenterPreset,
            scopes: actionCenterScopes,
            userPathPolicy: userPathPolicy
        )
    }

    private var actionCenterPolicyDigest: String {
        ScanSessionEvidenceBuilder.policyDigest(
            preset: actionCenterPreset,
            userPathPolicy: userPathPolicy
        )
    }

    private var actionCenterFindingDigest: String {
        ScanSessionEvidenceBuilder.findingDigest(
            appVersion: actionCenterAppVersion,
            ruleVersion: actionCenterRuleVersion,
            preset: actionCenterPreset,
            scopes: actionCenterScopes,
            userPathPolicy: userPathPolicy,
            findings: findings
        )
    }

    private var actionCenterScopes: [ScanScope] {
        scanScopes.isEmpty ? selectedScopePlan.scopes : scanScopes
    }

    private var actionCenterPreset: ScanScopePreset {
        selectedScopePlan.preset ?? scanPreset
    }

    private var actionCenterAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "app-runtime"
    }

    private var actionCenterRuleVersion: String {
        includeUserRulesInScans ? "app-runtime+user-rules" : "app-runtime"
    }

    func recordReviewSelection(_ queueID: ReviewQueueID, updatedAt: Date = Date()) {
        guard overview != nil || !findings.isEmpty else { return }
        reviewedQueueID = queueID
        currentScanSession = sessionForCurrentFindings(updatedAt: updatedAt)
            .recordReviewSelection(findingDigest: actionCenterFindingDigest, updatedAt: updatedAt)
    }

    private func recordScanSession(updatedAt: Date) throws {
        reviewedQueueID = nil
        let session = freshScanSession(updatedAt: updatedAt)
            .recordScan(findingDigest: actionCenterFindingDigest, updatedAt: updatedAt)
        currentScanSession = session
        try AuditStore().saveScanSession(session)
    }

    private func recordPlanSession(_ plan: ReclaimPlan, updatedAt: Date = Date()) {
        currentScanSession = sessionForCurrentFindings(updatedAt: updatedAt)
            .recordPlan(planDigest: plan.id, updatedAt: updatedAt)
    }

    private func recordDryRunSession(_ receipt: ExecutionReceipt, updatedAt: Date? = nil) {
        guard let plan else { return }
        let transitionDate = updatedAt ?? receipt.createdAt
        currentScanSession = sessionForCurrentFindings(updatedAt: transitionDate)
            .recordPlan(planDigest: plan.id, updatedAt: transitionDate)
            .recordDryRunReceipt(receipt, updatedAt: transitionDate)
    }

    private func recordExecutionSession(_ receipt: ExecutionReceipt, updatedAt: Date? = nil) {
        let transitionDate = updatedAt ?? receipt.createdAt
        currentScanSession = sessionForCurrentFindings(updatedAt: transitionDate)
            .recordExecutionReceipt(receipt, updatedAt: transitionDate)
    }

    private func sessionForCurrentFindings(updatedAt: Date) -> ScanSession {
        if let currentScanSession,
           currentScanSession.scopeDigest == actionCenterScopeDigest,
           currentScanSession.ruleVersion == actionCenterRuleVersion,
           currentScanSession.policyDigest == actionCenterPolicyDigest,
           currentScanSession.findingDigest == actionCenterFindingDigest,
           currentScanSession.stage != .invalidated {
            return currentScanSession
        }
        return freshScanSession(updatedAt: updatedAt)
            .recordScan(findingDigest: actionCenterFindingDigest, updatedAt: updatedAt)
    }

    private func freshScanSession(updatedAt: Date) -> ScanSession {
        ScanSession(
            id: currentScanSession?.id ?? "app-session-\(UUID().uuidString)",
            createdAt: currentScanSession?.createdAt ?? lastScanDate ?? updatedAt,
            updatedAt: updatedAt,
            appVersion: actionCenterAppVersion,
            ruleVersion: actionCenterRuleVersion,
            preset: actionCenterPreset,
            scopeDigest: actionCenterScopeDigest,
            policyDigest: actionCenterPolicyDigest,
            stage: .notStarted
        )
    }

    var queueSummaries: [ReviewQueueSummary] {
        reviewQueueReport.queues
    }

    var totalReviewBytes: Int64 {
        findings
            .filter { [.safeAfterCondition, .reviewRequired, .preserveByDefault].contains($0.safetyClass) }
            .reduce(0) { $0 + $1.allocatedSize }
    }

    var selectedPlanCount: Int {
        plan?.items.filter(\.selected).count ?? 0
    }

    var canReclaimSelected: Bool {
        guard let plan, selectedPlanCount > 0 else { return false }
        guard let receipt = lastDryRunReceipt, receipt.mode == ExecutionMode.dryRun.rawValue else { return false }
        guard receipt.createdAt >= plan.createdAt else { return false }
        guard dryRunReceiptMatchesCurrentSession(plan: plan, receipt: receipt) else { return false }
        return receipt.actions.allSatisfy { $0.status == "dry-run" } && receipt.errors.isEmpty
    }

    private func dryRunReceiptMatchesCurrentSession(plan: ReclaimPlan, receipt: ExecutionReceipt) -> Bool {
        guard let currentScanSession else { return false }
        guard [.dryRunReady, .reclaimReady].contains(currentScanSession.stage) else { return false }
        return currentScanSession.planDigest == plan.id
            && currentScanSession.dryRunReceiptID == receipt.id
    }

    var reclaimConfirmationMessage: String {
        guard let plan else {
            return "No reclaim plan is available."
        }
        return "This will execute \(selectedPlanCount) selected auto-safe action(s), expected immediate reclaim \(ByteFormat.string(plan.expectedImmediateReclaim)). A receipt will be saved locally."
    }

    func setScanPreset(_ preset: ScanScopePreset) {
        guard scanPreset != preset || selectedSavedScopeSetID != nil || selectedScopeTemplateID != nil else { return }
        scanPreset = preset
        selectedScopeTemplateID = nil
        selectedSavedScopeSetID = nil
        resetScanState()
        permissionReport = PermissionAdvisor.report(scopes: currentScopes(includeUnavailable: true))
        error = nil
    }

    func setScopeTemplate(_ id: String?) {
        let normalizedID = id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextID = normalizedID?.isEmpty == true ? nil : normalizedID
        guard selectedScopeTemplateID != nextID || selectedSavedScopeSetID != nil else { return }
        selectedScopeTemplateID = nextID
        selectedSavedScopeSetID = nil
        if nextID != nil, selectedScopeTemplate == nil {
            selectedScopeTemplateID = nil
            error = "Built-in scope template is no longer available."
        } else {
            error = nil
        }
        resetScanState()
        permissionReport = PermissionAdvisor.report(scopes: currentScopes(includeUnavailable: true))
    }

    func setSavedScopeSet(_ id: String?) {
        let normalizedID = id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextID = normalizedID?.isEmpty == true ? nil : normalizedID
        guard selectedSavedScopeSetID != nextID || selectedScopeTemplateID != nil else { return }
        selectedSavedScopeSetID = nextID
        selectedScopeTemplateID = nil
        if nextID != nil, selectedSavedScopeSet == nil {
            selectedSavedScopeSetID = nil
            error = "Saved scope set is no longer available."
        } else {
            error = nil
        }
        resetScanState()
        permissionReport = PermissionAdvisor.report(scopes: currentScopes(includeUnavailable: true))
    }

    func setIncludeUserRulesInScans(_ include: Bool) {
        guard includeUserRulesInScans != include else { return }
        includeUserRulesInScans = include
        resetScanState()
        error = nil
    }

    private func resetScanState() {
        findings = []
        scanScopes = []
        overview = nil
        diskDrillDown = nil
        plan = nil
        agentStorageReview = nil
        lastDryRunReceipt = nil
        lastExecutionReceipt = nil
        lastScannedScopeLabel = nil
        currentScanSession = nil
        reviewedQueueID = nil
    }

    private func currentScopes(includeUnavailable: Bool) -> [ScanScope] {
        if let selectedSavedScopeSet {
            return selectedSavedScopeSet.plan.scopes
        }
        if let selectedScopeTemplateID,
           let plan = try? ScopeTemplateCatalog.plan(reference: selectedScopeTemplateID, includeUnavailable: includeUnavailable) {
            return plan.scopes
        }
        return DefaultScopes.scopes(for: scanPreset, includeUnavailable: includeUnavailable)
    }

    func totalBytes(for safetyClass: SafetyClass) -> Int64 {
        findings.filter { $0.safetyClass == safetyClass }.reduce(0) { $0 + $1.allocatedSize }
    }

    func findings(in queueID: ReviewQueueID) -> [Finding] {
        FindingAnalytics.reviewQueueRows(findings: findings, queueID: queueID)
            .map(\.finding)
    }

    func largeOldReviewReport(
        mode: LargeOldReviewMode = .all,
        sort: TopOffenderSort = .allocated,
        limit: Int = 80
    ) -> LargeOldReviewReport {
        FindingAnalytics.largeOldReviewReport(findings: findings, mode: mode, sort: sort, limit: limit)
    }

    func archiveReviewReport(
        mode: LargeOldReviewMode = .all,
        sort: TopOffenderSort = .allocated,
        limit: Int = 40,
        pathStyle: ReportPathStyle = .full
    ) -> ArchiveReviewReport {
        ArchiveReviewBuilder.build(
            findings: findings,
            mode: mode,
            sort: sort,
            limit: limit,
            privacy: ReportPrivacyOptions(pathStyle: pathStyle)
        )
    }

    func scan() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let scopePlan = selectedScopePlan
            let includeUserRules = includeUserRulesInScans
            let result = try await Task.detached {
                let scopes = scopePlan.scopes
                let policy = UserPathPolicyStore().load()
                let scanner = try FileScanner(
                    ruleEngine: try RuleEngine.bundled(includingUserRules: includeUserRules),
                    openFileChecker: NoOpenFilesChecker()
                )
                let findings = scanner.scan(
                    scopes: scopes,
                    options: ScanOptions(includeOpenFileStatus: false, userPathPolicy: policy)
                )
                let overview = FindingAnalytics.overview(findings: findings, scopes: scopes)
                let drillDown = DiskDrillDownBuilder.build(findings: findings, scopes: scopes, maxDepth: 3, childLimit: 8)
                return (scopePlan.label, scopes, findings, overview, drillDown, policy, PermissionAdvisor.report(scopeSummaries: overview.scopeSummaries))
            }.value
            lastScannedScopeLabel = result.0
            scanScopes = result.1
            findings = result.2
            overview = result.3
            diskDrillDown = result.4
            userPathPolicy = result.5
            permissionReport = result.6
            diskStatus = DiskStatusReader().snapshot()
            _ = try ScanHistoryStore().save(overview: result.3)
            loadHistory()
            plan = nil
            lastDryRunReceipt = nil
            lastExecutionReceipt = nil
            lastScanDate = Date()
            try recordScanSession(updatedAt: lastScanDate ?? Date())
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func buildPlan() async {
        isWorking = true
        defer { isWorking = false }
        let currentFindings = findings
        let builtPlan = await Task.detached {
            let builder = PlanBuilder(openFileChecker: LsofOpenFileChecker())
            return builder.buildPlan(from: currentFindings, mode: .autoSafeOnly)
        }.value
        plan = builtPlan
        lastDryRunReceipt = nil
        lastExecutionReceipt = nil
        recordPlanSession(builtPlan)
        error = nil
    }

    func runDryRun() async {
        isWorking = true
        defer { isWorking = false }
        do {
            if plan == nil {
                await buildPlan()
            }
            guard let plan else { return }
            let includeUserRules = includeUserRulesInScans
            let session = currentScanSession
            let receipt = try await Task.detached {
                let ruleVersion = try RuleEngine.bundled(includingUserRules: includeUserRules).version
                let policy = UserPathPolicyStore().load()
                return ReclaimerExecutor(
                    openFileChecker: LsofOpenFileChecker(),
                    configuration: ExecutorConfiguration(userPathPolicy: policy, currentScanSession: session)
                )
                    .execute(
                    plan: plan,
                    mode: .dryRun,
                    ruleVersion: ruleVersion,
                    userConfirmed: false
                )
            }.value
            lastDryRunReceipt = receipt
            lastExecutionReceipt = nil
            recordDryRunSession(receipt)
            _ = try AuditStore().save(plan: plan)
            _ = try AuditStore().save(receipt: receipt)
            loadAudit()
            loadRecovery()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reclaimSelected() async {
        guard canReclaimSelected, let currentPlan = plan else {
            error = "Run a clean dry run before reclaiming selected items."
            return
        }

        isWorking = true
        defer { isWorking = false }
        do {
            let includeUserRules = includeUserRulesInScans
            let receipt = try await Task.detached {
                let ruleVersion = try RuleEngine.bundled(includingUserRules: includeUserRules).version
                let policy = UserPathPolicyStore().load()
                return ReclaimerExecutor(
                    openFileChecker: LsofOpenFileChecker(),
                    configuration: ExecutorConfiguration(userPathPolicy: policy)
                )
                    .execute(
                        plan: currentPlan,
                        mode: .perform,
                        ruleVersion: ruleVersion,
                        userConfirmed: true
                    )
            }.value
            lastExecutionReceipt = receipt
            recordExecutionSession(receipt)
            _ = try AuditStore().save(receipt: receipt)
            loadAudit()
            loadHolding()
            loadRecovery()
            error = receipt.errors.isEmpty ? nil : receipt.errors.joined(separator: "\n")
            let scopePlan = selectedScopePlan
            let refreshedIncludeUserRules = includeUserRulesInScans
            let refreshed = try await Task.detached {
                let scopes = scopePlan.scopes
                let policy = UserPathPolicyStore().load()
                let scanner = try FileScanner(
                    ruleEngine: try RuleEngine.bundled(includingUserRules: refreshedIncludeUserRules),
                    openFileChecker: NoOpenFilesChecker()
                )
                let findings = scanner.scan(
                    scopes: scopes,
                    options: ScanOptions(includeOpenFileStatus: false, userPathPolicy: policy)
                )
                let overview = FindingAnalytics.overview(findings: findings, scopes: scopes)
                let drillDown = DiskDrillDownBuilder.build(findings: findings, scopes: scopes, maxDepth: 3, childLimit: 8)
                return (scopePlan.label, scopes, findings, overview, drillDown, policy, PermissionAdvisor.report(scopeSummaries: overview.scopeSummaries))
            }.value
            lastScannedScopeLabel = refreshed.0
            scanScopes = refreshed.1
            findings = refreshed.2
            overview = refreshed.3
            diskDrillDown = refreshed.4
            userPathPolicy = refreshed.5
            permissionReport = refreshed.6
            _ = try ScanHistoryStore().save(overview: refreshed.3)
            loadHistory()
            plan = nil
            lastDryRunReceipt = nil
            lastScanDate = Date()
            try recordScanSession(updatedAt: lastScanDate ?? Date())
        } catch {
            self.error = error.localizedDescription
        }
    }

    func exportEvidenceReport(pathStyle: ReportPathStyle = .full, redactUserText: Bool = false) async {
        guard let currentOverview = overview, !findings.isEmpty else {
            error = "Run a scan before exporting an evidence report."
            return
        }

        isWorking = true
        defer { isWorking = false }
        do {
            let currentFindings = findings
            let currentScopes = scanScopes
            let currentPolicy = userPathPolicy
            let url = try await Task.detached {
                let report = EvidenceReportBuilder.build(
                    overview: currentOverview,
                    findings: currentFindings,
                    scopes: currentScopes,
                    diskStatus: DiskStatusReader().snapshot(),
                    userPathPolicy: currentPolicy,
                    privacy: ReportPrivacyOptions(pathStyle: pathStyle, redactUserText: redactUserText)
                )
                return try ReportStore().save(report: report)
            }.value
            lastReportExportURL = url
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func exportPlanReport(_ plan: ReclaimPlan, pathStyle: ReportPathStyle = .full) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let url = try await Task.detached {
                let report = ReclaimPlanReportBuilder.build(
                    plan: plan,
                    privacy: ReportPrivacyOptions(pathStyle: pathStyle)
                )
                return try ReportStore().save(planReport: report)
            }.value
            lastPlanReportExportURL = url
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func exportReceiptReport(_ receipt: ExecutionReceipt, pathStyle: ReportPathStyle = .full) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let url = try await Task.detached {
                let report = ExecutionReceiptReportBuilder.build(
                    receipt: receipt,
                    privacy: ReportPrivacyOptions(pathStyle: pathStyle)
                )
                return try ReportStore().save(executionReceiptReport: report)
            }.value
            lastReceiptReportExportURL = url
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func exportGrowthReport(pathStyle: ReportPathStyle = .full) async {
        guard scanSnapshots.count >= 2 else {
            error = "Run at least two scans before exporting a growth report."
            return
        }

        isWorking = true
        defer { isWorking = false }
        do {
            let current = scanSnapshots[0]
            let previous = scanSnapshots[1]
            let url = try await Task.detached {
                let report = GrowthReportBuilder.build(
                    previous: previous,
                    current: current,
                    group: .category,
                    privacy: ReportPrivacyOptions(pathStyle: pathStyle)
                )
                return try ReportStore().save(growthReport: report)
            }.value
            lastGrowthReportExportURL = url
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func exportArchiveReview(mode: LargeOldReviewMode = .all, sort: TopOffenderSort = .allocated, pathStyle: ReportPathStyle = .full) async {
        guard !findings.isEmpty else {
            error = "Run a scan before exporting an archive review."
            return
        }

        isWorking = true
        defer { isWorking = false }
        do {
            let currentFindings = findings
            let url = try await Task.detached {
                let report = ArchiveReviewBuilder.build(
                    findings: currentFindings,
                    mode: mode,
                    sort: sort,
                    limit: 80,
                    privacy: ReportPrivacyOptions(pathStyle: pathStyle)
                )
                return try ReportStore().save(archiveReviewReport: report)
            }.value
            lastArchiveReviewExportURL = url
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func exportUserPathPolicy() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let url = try await Task.detached {
                let document = UserPathPolicyStore().exportDocument()
                return try ReportStore().save(userPathPolicyDocument: document)
            }.value
            lastPolicyExportURL = url
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadSavedScopeSets() {
        let previousSelection = selectedSavedScopeSetID
        savedScopeSets = SavedScopeSetStore().list()
        if let previousSelection, !savedScopeSets.contains(where: { $0.id == previousSelection }) {
            selectedSavedScopeSetID = nil
            resetScanState()
        }
        if overview == nil {
            permissionReport = PermissionAdvisor.report(scopes: currentScopes(includeUnavailable: true))
        }
    }

    func saveCurrentScopeSet(name: String, summary: String?) {
        do {
            let planToSave = selectedScopePlan
            let set = try SavedScopeSetStore().upsert(
                name: name,
                paths: planToSave.scopes.map(\.root.path),
                summary: summary
            )
            savedScopeSets = SavedScopeSetStore().list()
            selectedScopeTemplateID = nil
            selectedSavedScopeSetID = set.id
            resetScanState()
            permissionReport = PermissionAdvisor.report(scopes: currentScopes(includeUnavailable: true))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func saveScopeTemplate(_ template: ScopeTemplate) {
        do {
            let set = try SavedScopeSetStore().upsert(
                name: template.name,
                paths: template.scopes.map(\.root.path),
                summary: template.summary
            )
            savedScopeSets = SavedScopeSetStore().list()
            selectedScopeTemplateID = nil
            selectedSavedScopeSetID = set.id
            resetScanState()
            permissionReport = PermissionAdvisor.report(scopes: currentScopes(includeUnavailable: true))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func removeSavedScopeSet(_ set: SavedScopeSet) {
        do {
            _ = try SavedScopeSetStore().remove(reference: set.id)
            if selectedSavedScopeSetID == set.id {
                selectedSavedScopeSetID = nil
                resetScanState()
            }
            savedScopeSets = SavedScopeSetStore().list()
            permissionReport = PermissionAdvisor.report(scopes: currentScopes(includeUnavailable: true))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func importSavedScopeSets(from url: URL, replace: Bool) {
        do {
            let result = try SavedScopeSetStore().importDocument(from: url, merge: !replace)
            lastScopeSetImportResult = result
            loadSavedScopeSets()
            error = nil
        } catch {
            lastScopeSetImportResult = nil
            self.error = error.localizedDescription
        }
    }

    func exportSavedScopeSets() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let url = try await Task.detached {
                let document = try SavedScopeSetStore().exportDocument()
                return try ReportStore().save(savedScopeSetDocument: document)
            }.value
            lastScopeSetExportURL = url
            error = nil
        } catch {
            lastScopeSetExportURL = nil
            self.error = error.localizedDescription
        }
    }

    func checkActiveHandles() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let baseFindings = findings
            let scopePlan = selectedScopePlan
            let includeUserRules = includeUserRulesInScans
            let report = try await Task.detached {
                let sourceFindings: [Finding]
                if baseFindings.isEmpty {
                    let scopes = scopePlan.scopes
                    let policy = UserPathPolicyStore().load()
                    let scanner = try FileScanner(
                        ruleEngine: try RuleEngine.bundled(includingUserRules: includeUserRules),
                        openFileChecker: NoOpenFilesChecker()
                    )
                    sourceFindings = scanner.scan(
                        scopes: scopes,
                        options: ScanOptions(includeOpenFileStatus: false, userPathPolicy: policy)
                    )
                } else {
                    sourceFindings = baseFindings
                }
                return ActiveFileReviewScanner(openFileChecker: LsofOpenFileChecker()).review(
                    findings: sourceFindings,
                    options: ActiveFileReviewOptions(limit: 80)
                )
            }.value
            activeFileReview = report
            applyActiveFileStatuses(from: report)
            _ = try AuditStore().save(activeFileReviewReport: report)
            loadAudit()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadAudit() {
        let store = AuditStore()
        auditStoreSummary = store.summary()
        recentPlans = store.recentPlans()
        recentReceipts = store.recentReceipts()
        recentNativeToolReports = store.recentNativeToolReports()
        recentNativeToolExecutionReceipts = store.recentNativeToolExecutionReceipts()
        recentContainerInventoryReports = store.recentContainerInventoryReports()
        recentRemoteProbeReports = store.recentRemoteProbeReports()
        recentRemoteScanReports = store.recentRemoteScanReports()
        recentRemoteDogfoodReports = store.recentRemoteDogfoodReports()
        if remoteProbeReport == nil {
            remoteProbeReport = recentRemoteProbeReports.first
        }
        if remoteScanReport == nil {
            remoteScanReport = recentRemoteScanReports.first
        }
        syncRemoteDogfoodReport()
        if
            let currentRemoteScan = recentRemoteScanReports.first,
            let previousRemoteScan = store.latestPreviousRemoteScanReport(
                forConcreteTarget: currentRemoteScan.target,
                excludingReportID: currentRemoteScan.id
            )
        {
            remoteGrowthReport = RemoteGrowthReportBuilder.build(
                previous: previousRemoteScan,
                current: currentRemoteScan,
                limit: 10
            )
        } else {
            remoteGrowthReport = nil
        }
        recentActiveFileReviewReports = store.recentActiveFileReviewReports()
        recentTrashReviewReports = store.recentTrashReviewReports()
        recentDownloadsReviewReports = store.recentDownloadsReviewReports()
        recentBrowserCacheReviewReports = store.recentBrowserCacheReviewReports()
        recentPackageCacheReviewReports = store.recentPackageCacheReviewReports()
        recentProjectDependencyReviewReports = store.recentProjectDependencyReviewReports()
        recentDeviceBackupReviewReports = store.recentDeviceBackupReviewReports()
        recentXcodeReviewReports = store.recentXcodeReviewReports()
        recentAppUninstallReceipts = store.recentAppUninstallReceipts()
        loadRecovery()
    }

    func previewAuditPrune() {
        let store = AuditStore()
        let policy = AuditRetentionPolicy(olderThanDays: 90, keepRecent: 20)
        let plan = store.prunePlan(policy: policy)
        auditPrunePlan = plan
        auditPruneReceipt = try? store.prune(plan: plan, dryRun: true)
        auditStoreSummary = store.summary()
    }

    func confirmAuditPrune() {
        guard let plan = auditPrunePlan else {
            previewAuditPrune()
            return
        }
        do {
            auditPruneReceipt = try AuditStore().prune(plan: plan, dryRun: false)
            auditPrunePlan = nil
            loadAudit()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadHolding() {
        heldItems = HoldingStore().list()
        loadRecovery()
    }

    func loadRecovery() {
        recoveryReport = RecoveryCenter.build(heldItems: heldItems, receipts: recentReceipts)
    }

    func loadHistory() {
        let store = ScanHistoryStore()
        scanSnapshots = store.recent(limit: 8)
        growthDeltas = store.latestGrowthDeltas(group: .category, limit: 8)
    }

    func loadUserPolicy() {
        userPathPolicy = UserPathPolicyStore().load()
    }

    func refreshPermissions() {
        if let overview {
            permissionReport = PermissionAdvisor.report(scopeSummaries: overview.scopeSummaries)
        } else {
            permissionReport = PermissionAdvisor.report(scopes: currentScopes(includeUnavailable: true))
        }
    }

    func addUserPathRule(path: String, kind: UserPathPolicyKind, reason: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try UserPathPolicyStore().add(path: path, kind: kind, reason: reason)
            userPathPolicy = UserPathPolicyStore().load()
            error = nil
            if !findings.isEmpty {
                isWorking = false
                await scan()
                isWorking = true
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func removeUserPathRule(_ rule: UserPathRule) async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try UserPathPolicyStore().remove(path: rule.path, kind: rule.kind)
            userPathPolicy = UserPathPolicyStore().load()
            error = nil
            if !findings.isEmpty {
                isWorking = false
                await scan()
                isWorking = true
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func scanDuplicates(includePreserveByDefault: Bool = false) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let currentScopes = scanScopes.isEmpty
                ? self.currentScopes(includeUnavailable: false)
                : scanScopes
            duplicateReview = try await Task.detached {
                try DuplicateReviewScanner().scan(
                    scopes: currentScopes,
                    options: DuplicateReviewOptions(
                        minimumFileSize: 5_000_000,
                        maximumDepth: 5,
                        maximumFilesToHash: 2_000,
                        includePreserveByDefault: includePreserveByDefault
                    )
                )
            }.value
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reviewTrash() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let report = await Task.detached {
                TrashReviewScanner().review(
                    options: TrashReviewOptions(limit: 50, measurementDepth: 8)
                )
            }.value
            trashReview = report
            _ = try AuditStore().save(trashReviewReport: report)
            loadAudit()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reviewDownloads() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let report = await Task.detached {
                DownloadsReviewScanner().review(
                    options: DownloadsReviewOptions(limit: 80, oldDays: 90, measurementDepth: 6)
                )
            }.value
            downloadsReview = report
            _ = try AuditStore().save(downloadsReviewReport: report)
            loadAudit()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reviewBrowserCaches() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let report = await Task.detached {
                BrowserCacheReviewScanner().review(
                    options: BrowserCacheReviewOptions(limit: 80, measurementDepth: 7, includeMissingRoots: true)
                )
            }.value
            browserCacheReview = report
            _ = try AuditStore().save(browserCacheReviewReport: report)
            loadAudit()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reviewPackageCaches() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let report = await Task.detached {
                PackageCacheReviewScanner().review(
                    options: PackageCacheReviewOptions(limit: 80, measurementDepth: 7, includeMissingRoots: true)
                )
            }.value
            packageCacheReview = report
            _ = try AuditStore().save(packageCacheReviewReport: report)
            loadAudit()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reviewProjectDependencies() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let report = await Task.detached {
                ProjectDependencyReviewScanner().review(
                    options: ProjectDependencyReviewOptions(
                        limit: 80,
                        oldDays: 90,
                        maximumSearchDepth: 6,
                        measurementDepth: 8,
                        includeMissingRoots: true,
                        includeVCSStatus: true,
                        projectPolicy: ProjectDependencyPolicyStore().load()
                    )
                )
            }.value
            projectDependencyReview = report
            _ = try AuditStore().save(projectDependencyReviewReport: report)
            loadAudit()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reviewDeviceBackups() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let report = await Task.detached {
                DeviceBackupReviewScanner().review(
                    options: DeviceBackupReviewOptions(limit: 80, oldDays: 180, measurementDepth: 12)
                )
            }.value
            deviceBackupReview = report
            _ = try AuditStore().save(deviceBackupReviewReport: report)
            loadAudit()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reviewXcode() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let report = await Task.detached {
                XcodeReviewScanner().review(
                    options: XcodeReviewOptions(limit: 80, oldDays: 180, measurementDepth: 10, includeMissingRoots: true)
                )
            }.value
            xcodeReview = report
            _ = try AuditStore().save(xcodeReviewReport: report)
            loadAudit()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reviewApps(includeSystemApps: Bool = false, includeOrphans: Bool = true) async {
        isWorking = true
        defer { isWorking = false }
        do {
            appReview = try await Task.detached {
                try AppReviewScanner().scan(
                    options: AppReviewOptions(
                        includeSystemApplications: includeSystemApps,
                        includeOrphanCandidates: includeOrphans,
                        minimumRelatedSize: 10_000_000,
                        measurementDepth: 3
                    )
                )
            }.value
            appUninstallPreview = nil
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func previewAppUninstall(group: AppReviewGroup) async {
        guard let report = appReview else {
            error = "Run an app review before building an uninstall preview."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let selector = AppUninstallSelector(
                appPath: group.appPath,
                bundleIdentifier: group.bundleIdentifier,
                displayName: group.ownerName
            )
            let preview = try await Task.detached {
                try AppUninstallPreviewBuilder.build(report: report, selector: selector)
            }.value
            appUninstallPreview = preview
            lastAppUninstallDryRunReceipt = nil
            lastAppUninstallReceipt = nil
            _ = try AuditStore().save(appUninstallPreview: preview)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func dryRunAppUninstall() async {
        guard let preview = appUninstallPreview else {
            error = "Build an uninstall preview before running an app uninstall dry run."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let receipt = await Task.detached {
                let policy = UserPathPolicyStore().load()
                let allowedRoots = AppReviewOptions().appRoots
                return AppUninstallExecutor(
                    openFileChecker: LsofOpenFileChecker(),
                    configuration: AppUninstallExecutorConfiguration(userPathPolicy: policy, allowedAppRoots: allowedRoots)
                )
                    .execute(preview: preview, mode: .dryRun, userConfirmed: false)
            }.value
            lastAppUninstallDryRunReceipt = receipt
            lastAppUninstallReceipt = nil
            _ = try AuditStore().save(appUninstallReceipt: receipt)
            loadAudit()
            error = receipt.status == "dry-run" ? nil : receipt.message
        } catch {
            self.error = error.localizedDescription
        }
    }

    func trashPreviewedApp() async {
        guard canTrashPreviewedApp, let preview = appUninstallPreview else {
            error = "Run a clean app uninstall dry run before moving the app bundle to Trash."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let receipt = await Task.detached {
                let policy = UserPathPolicyStore().load()
                let allowedRoots = AppReviewOptions().appRoots
                return AppUninstallExecutor(
                    openFileChecker: LsofOpenFileChecker(),
                    configuration: AppUninstallExecutorConfiguration(userPathPolicy: policy, allowedAppRoots: allowedRoots)
                )
                    .execute(preview: preview, mode: .perform, userConfirmed: true)
            }.value
            lastAppUninstallReceipt = receipt
            _ = try AuditStore().save(appUninstallReceipt: receipt)
            loadAudit()
            error = receipt.status == "done" ? nil : receipt.message
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reviewAgentStorage() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let includeUserRules = includeUserRulesInScans
            agentStorageReview = try await Task.detached {
                let scopes = DefaultScopes.aiAgentStorage(includeUnavailable: false)
                let policy = UserPathPolicyStore().load()
                let scanner = try FileScanner(
                    ruleEngine: try RuleEngine.bundled(includingUserRules: includeUserRules),
                    openFileChecker: NoOpenFilesChecker()
                )
                let findings = scanner.scan(
                    scopes: scopes,
                    options: ScanOptions(
                        minimumFindingSize: 1,
                        maximumFindingDepth: 3,
                        measurementDepth: 7,
                        includeOpenFileStatus: false,
                        userPathPolicy: policy
                    )
                )
                return AgentStorageReviewBuilder.build(findings: findings, scopes: scopes, limit: 80)
            }.value
            agentRetentionReport = nil
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reviewAgentRetention(profile: AgentRetentionProfile) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let includeUserRules = includeUserRulesInScans
            let existingReview = agentStorageReview
            let result = try await Task.detached { () -> (AgentStorageReview, AgentRetentionReport) in
                let review: AgentStorageReview
                if let existingReview {
                    review = existingReview
                } else {
                    let scopes = DefaultScopes.aiAgentStorage(includeUnavailable: false)
                    let policy = UserPathPolicyStore().load()
                    let scanner = try FileScanner(
                        ruleEngine: try RuleEngine.bundled(includingUserRules: includeUserRules),
                        openFileChecker: NoOpenFilesChecker()
                    )
                    let findings = scanner.scan(
                        scopes: scopes,
                        options: ScanOptions(
                            minimumFindingSize: 1,
                            maximumFindingDepth: 3,
                            measurementDepth: 7,
                            includeOpenFileStatus: false,
                            userPathPolicy: policy
                        )
                    )
                    review = AgentStorageReviewBuilder.build(findings: findings, scopes: scopes, limit: 80)
                }
                let retentionReport = AgentRetentionBuilder.build(review: review, profile: profile, limit: 80)
                return (review, retentionReport)
            }.value
            agentStorageReview = result.0
            agentRetentionReport = result.1
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

	    func runNativeToolCommand(receipt: NativeToolReceipt, command: NativeToolCommand, perform: Bool) async {
	        isWorking = true
	        defer { isWorking = false }
	        do {
	            let includeUserRules = includeUserRulesInScans
	            let selection = NativeToolCommandSelection(receipt: receipt, command: command)
	            if perform, let reason = nativePerformBlockReason(selection: selection) {
	                error = reason
	                return
	            }
	            let executionReceipt = try await Task.detached {
	                let ruleVersion = try RuleEngine.bundled(includingUserRules: includeUserRules).version
	                return NativeToolExecutor().execute(
	                    selection: selection,
	                    mode: perform ? .perform : .dryRun,
                    ruleVersion: ruleVersion,
                    userConfirmed: perform
                )
            }.value
            _ = try AuditStore().save(nativeToolExecutionReceipt: executionReceipt)
            loadAudit()
            error = executionReceipt.errors.isEmpty ? nil : executionReceipt.message
        } catch {
            self.error = error.localizedDescription
	        }
	    }

	    func nativePerformBlockReason(receipt: NativeToolReceipt, command: NativeToolCommand) -> String? {
	        nativePerformBlockReason(selection: NativeToolCommandSelection(receipt: receipt, command: command))
	    }

	    private func nativePerformBlockReason(selection: NativeToolCommandSelection) -> String? {
	        if let reason = NativeToolExecutor.performBlockReason(for: selection.command) {
	            return reason
	        }
	        if NativeToolExecutor.savedDryRunReceiptExists(
	            authorizing: selection,
	            in: recentNativeToolExecutionReceipts
	        ) {
	            return nil
	        }
	        return "Run requires a saved dry-run receipt for this native command and finding. Use Dry Run first."
	    }

	    func inspectContainers() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let report = await Task.detached {
                ContainerInventoryScanner().inspect()
            }.value
            containerInventory = report
            _ = try AuditStore().save(containerInventoryReport: report)
            loadAudit()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func refreshRemoteTargets() {
        remoteTargets = RemoteTargetResolver().targets()
        if remoteTargetInput.isEmpty, let first = remoteTargets.first {
            remoteTargetInput = first.input
        }
    }

    func probeRemoteTarget() async {
        let targetInput = remoteTargetInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetInput.isEmpty else {
            error = "Enter an SSH alias or host before probing."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let report = try await Task.detached {
                let target = try RemoteTargetResolver().resolve(targetInput)
                return RemoteProbeBuilder(target: target).probe()
            }.value
            remoteProbeReport = report
            _ = try AuditStore().save(remoteProbeReport: report)
            loadAudit()
            error = report.commands.contains { $0.exitCode == 0 } ? nil : "Remote probe did not reach the target with read-only SSH commands."
        } catch {
            self.error = error.localizedDescription
        }
    }

    func scanRemoteTarget() async {
        let targetInput = remoteTargetInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetInput.isEmpty else {
            error = "Enter an SSH alias or host before scanning."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let report = try await Task.detached {
                let target = try RemoteTargetResolver().resolve(targetInput)
                return RemoteScanBuilder(target: target).scan(preset: .vpsGeneral)
            }.value
            remoteScanReport = report
            syncRemoteDogfoodReport()
            _ = try AuditStore().save(remoteScanReport: report)
            loadAudit()
            error = report.commands.contains { $0.exitCode == 0 } ? nil : "Remote scan did not reach the target with read-only SSH commands."
        } catch {
            self.error = error.localizedDescription
        }
    }

    func exportRemoteRedactedReport() async {
        guard let report = remoteScanReport else {
            error = "Run a remote scan before exporting a remote report."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let url = try await Task.detached {
                let privacy = ReportPrivacyOptions(pathStyle: .redacted)
                let markdown = RemoteReportBuilder.build(report: report, privacy: privacy).markdown
                let root = ReportStore.defaultRoot()
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let url = root.appendingPathComponent("remote-report-\(report.id).md")
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                return url
            }.value
            lastRemoteReportExportURL = url
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func exportRemoteRedactedGrowthReport() async {
        let store = AuditStore()
        guard
            let current = recentRemoteScanReports.first,
            let previous = store.latestPreviousRemoteScanReport(forConcreteTarget: current.target, excludingReportID: current.id),
            remoteGrowthReport != nil
        else {
            error = "Remote growth export needs at least two saved remote scans."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let url = try await Task.detached {
                let privacy = ReportPrivacyOptions(pathStyle: .redacted)
                let redacted = RemoteGrowthReportBuilder.build(
                    previous: previous,
                    current: current,
                    limit: 25,
                    privacy: privacy
                )
                let root = ReportStore.defaultRoot()
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let url = root.appendingPathComponent("remote-growth-\(current.id).md")
                try redacted.markdown.write(to: url, atomically: true, encoding: .utf8)
                return url
            }.value
            lastRemoteGrowthReportExportURL = url
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func exportRemoteDogfoodReportFromAudit() async {
        guard let scan = recentRemoteScanReports.first else {
            error = "Remote dogfood export needs at least one saved remote scan."
            return
        }
        let store = AuditStore()
        let probe = store.latestRemoteProbeReport(forConcreteTarget: scan.target)
        let previous = store.latestPreviousRemoteScanReport(forConcreteTarget: scan.target, excludingReportID: scan.id)
        isWorking = true
        defer { isWorking = false }
        do {
            let report = RemoteDogfoodReportBuilder.build(
                probe: probe,
                scan: scan,
                growth: previous.map {
                    RemoteGrowthReportBuilder.build(
                        previous: $0,
                        current: scan,
                        privacy: ReportPrivacyOptions(pathStyle: .redacted)
                    )
                },
                privacy: ReportPrivacyOptions(pathStyle: .redacted)
            )
            let url = try await Task.detached {
                let root = ReportStore.defaultRoot()
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let url = root.appendingPathComponent("remote-dogfood-\(report.id).md")
                try report.markdown.write(to: url, atomically: true, encoding: .utf8)
                return url
            }.value
            remoteDogfoodReport = report
            lastRemoteDogfoodReportExportURL = url
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func syncRemoteDogfoodReport() {
        guard let scan = remoteScanReport else {
            if remoteDogfoodReport == nil {
                remoteDogfoodReport = recentRemoteDogfoodReports.first
            }
            return
        }
        remoteDogfoodReport = AuditStore().latestRemoteDogfoodReport(forConcreteTarget: scan.target)
    }

    func restoreHeldItem(_ item: HeldItem) {
        do {
            _ = try HoldingStore().restore(id: item.id)
            loadHolding()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func restoreRecoveryItem(_ item: RecoveryCenterItem) {
        guard let holdingID = item.holdingID else {
            error = "Only app-held recovery items can be restored by Ryddi."
            return
        }
        do {
            _ = try HoldingStore().restore(id: holdingID)
            loadHolding()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func planItem(for findingID: Finding.ID) -> ReclaimPlanItem? {
        plan?.items.first { $0.finding.id == findingID }
    }

    private func applyActiveFileStatuses(from report: ActiveFileReviewReport) {
        var statusByPath: [String: OpenFileStatus] = [:]
        for item in report.items {
            if let status = item.finding.openFileStatus {
                statusByPath[item.finding.path] = status
            }
        }
        guard !statusByPath.isEmpty else { return }
        findings = findings.map { finding in
            if let status = statusByPath[finding.path] {
                return finding.withOpenFileStatus(status)
            }
            return finding
        }
    }

    func installSchedule() {
        do {
            let bundledCLI = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/reclaimer")
            let cliPath = FileManager.default.isExecutableFile(atPath: bundledCLI.path)
                ? bundledCLI.path
                : (Bundle.main.executableURL?.path ?? "/usr/local/bin/reclaimer")
            let selection: ScheduledScopeSelection
            if let selectedSavedScopeSetID {
                selection = ScheduledScopeSelection(savedScopeSet: selectedSavedScopeSetID)
            } else if let selectedScopeTemplateID {
                selection = ScheduledScopeSelection(template: selectedScopeTemplateID)
            } else {
                selection = ScheduledScopeSelection(preset: scanPreset)
            }
            let schedule = ScheduleConfiguration(scopeSelection: selection)
            _ = try LaunchAgentManager().install(cliPath: cliPath, schedule: schedule)
            refreshAutomation()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func removeSchedule() {
        do {
            try LaunchAgentManager().uninstall()
            refreshAutomation()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func refreshAutomation() {
        launchAgentStatus = LaunchAgentManager().status()
        launchAgentInstalled = launchAgentStatus.installed
        diskStatus = DiskStatusReader().snapshot()
    }
}
