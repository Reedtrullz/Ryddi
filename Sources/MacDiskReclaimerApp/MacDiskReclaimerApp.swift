import SwiftUI
import ReclaimerCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

@main
struct MacDiskReclaimerApp: App {
    @State private var statusModel = StatusMenuModel()

    var body: some Scene {
        WindowGroup("Ryddi", id: "dashboard") {
            DashboardView()
                .frame(minWidth: 980, minHeight: 680)
        }
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
    @State private var selectedSection = "Summary"
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
            } else if selectedSection == "LargeOld" {
                LargeOldReviewView(model: model)
            } else if selectedSection == "Duplicates" {
                DuplicateReviewView(model: model)
            } else if selectedSection == "Containers" {
                ContainerInventoryView(model: model)
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
                FindingDetailView(finding: finding, planItem: model.planItem(for: finding.id))
            } else {
                OverviewView(model: model)
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
            Toggle(isOn: Binding(
                get: { model.includeUserRulesInScans },
                set: { model.setIncludeUserRulesInScans($0) }
            )) {
                Label("User Rules", systemImage: "slider.horizontal.3")
            }
            .toggleStyle(.button)
            Button {
                Task { await model.scan() }
            } label: {
                Label("Scan", systemImage: "magnifyingglass")
            }
            Button {
                Task { await model.buildPlan() }
            } label: {
                Label("Plan", systemImage: "checklist")
            }
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
            Button(role: .destructive) {
                showingReclaimConfirmation = true
            } label: {
                Label("Reclaim", systemImage: "trash")
            }
            .disabled(!model.canReclaimSelected)
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
            if model.findings.isEmpty {
                Task { await model.scan() }
            }
            model.loadSavedScopeSets()
            model.loadAudit()
            model.loadHolding()
            model.loadRecovery()
            model.loadHistory()
            model.loadUserPolicy()
            model.refreshAutomation()
            model.refreshPermissions()
        }
    }

    private var sidebar: some View {
        List(selection: $selectedFinding) {
            Section("Overview") {
                Button("Summary") {
                    selectedFinding = nil
                    selectedSection = "Summary"
                }
                Button("Feature Matrix") {
                    selectedFinding = nil
                    selectedSection = "Features"
                }
                Button("Rule Catalog") {
                    selectedFinding = nil
                    selectedSection = "Rules"
                }
                Button("Apps & Leftovers") {
                    selectedFinding = nil
                    selectedSection = "Apps"
                }
                Button("Large & Old Files") {
                    selectedFinding = nil
                    selectedSection = "LargeOld"
                }
                Button("Duplicate Review") {
                    selectedFinding = nil
                    selectedSection = "Duplicates"
                }
                Button("Container Inventory") {
                    selectedFinding = nil
                    selectedSection = "Containers"
                }
                Button("AI Agent Storage") {
                    selectedFinding = nil
                    selectedSection = "Agents"
                }
                Button("Permissions") {
                    selectedFinding = nil
                    selectedSection = "Permissions"
                }
                Button("Active Handles") {
                    selectedFinding = nil
                    selectedSection = "Active"
                }
                Button("Scope Sets") {
                    selectedFinding = nil
                    selectedSection = "Scopes"
                }
                Button("Protections & Exclusions") {
                    selectedFinding = nil
                    selectedSection = "Policy"
                }
                Button("Audit History") {
                    selectedFinding = nil
                    selectedSection = "Audit"
                }
                Button("Recovery Center") {
                    selectedFinding = nil
                    selectedSection = "Recovery"
                }
                Button("Holding Area") {
                    selectedFinding = nil
                    selectedSection = "Holding"
                }
                Button("Automation") {
                    selectedFinding = nil
                    selectedSection = "Automation"
                }
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
                                    selectedSection = "Finding"
                                }
                        }
                    }
                }
            }
        }
        .navigationTitle("Ryddi")
    }
}

struct OverviewView: View {
    let model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Evidence-first reclaim")
                .font(.largeTitle.bold())
            Text("Ryddi is a general Mac disk reclaim assistant with a developer and AI-agent cleanup pack being perfected first.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.isWorking {
                ProgressView("Working...")
            }

            ScanScopePreviewView(plan: model.selectedScopePlan, lastScannedLabel: model.lastScannedScopeLabel)

            if let url = model.lastReportExportURL {
                Text("Latest report: \(url.path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let url = model.lastGrowthReportExportURL {
                Text("Latest growth report: \(url.path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 16) {
                MetricTile(title: "Findings", value: "\(model.findings.count)")
                MetricTile(title: "Auto-safe", value: ByteFormat.string(model.totalBytes(for: .autoSafe)))
                MetricTile(title: "Needs review", value: ByteFormat.string(model.totalReviewBytes))
                MetricTile(title: "Plan reclaim", value: ByteFormat.string(model.plan?.expectedImmediateReclaim ?? 0))
            }

            HStack(spacing: 16) {
                MetricTile(title: "Last scan", value: model.lastScanDate?.formatted(date: .omitted, time: .shortened) ?? "Never")
                MetricTile(title: "Automation", value: model.launchAgentInstalled ? "Plist installed" : "Off")
                MetricTile(title: "Protected", value: ByteFormat.string(model.totalBytes(for: .neverTouch) + model.totalBytes(for: .preserveByDefault)))
                MetricTile(title: "Audit receipts", value: "\(model.recentReceipts.count)")
                MetricTile(title: "Snapshots", value: "\(model.scanSnapshots.count)")
                MetricTile(title: "Duplicate groups", value: "\(model.duplicateReview?.groups.count ?? 0)")
                MetricTile(title: "App leftovers", value: "\(model.appReview?.orphanGroups.count ?? 0)")
                MetricTile(title: "Container reports", value: "\(model.recentContainerInventoryReports.count)")
                MetricTile(title: "Active handles", value: "\(model.activeFileReview?.openCount ?? 0)")
            }

            if let overview = model.overview {
                PermissionCoverageView(report: model.permissionReport)
                AccountingNotesView(notes: overview.accountingNotes)
                DiskMapView(nodes: overview.mapNodes)
                if let report = model.diskDrillDown {
                    DiskDrillDownView(report: report)
                }
                OwnerStorageView(summaries: overview.ownerSummaries)
                GrowthHistoryView(
                    snapshots: model.scanSnapshots,
                    deltas: model.growthDeltas,
                    onExport: { Task { await model.exportGrowthReport() } },
                    onExportRedacted: { Task { await model.exportGrowthReport(pathStyle: .redacted) } }
                )
                TopOffendersView(findings: model.findings, plan: model.plan)
            }

            if let error = model.error {
                Text(error)
                    .foregroundStyle(.red)
            }

            if let plan = model.plan {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Dry-run plan").font(.headline)
                        Spacer()
                        Button {
                            Task { await model.exportPlanReport(plan) }
                        } label: {
                            Label("Export Plan", systemImage: "doc.plaintext")
                        }
                        Button {
                            Task { await model.exportPlanReport(plan, pathStyle: .redacted) }
                        } label: {
                            Label("Redacted", systemImage: "eye.slash")
                        }
                    }
                    HStack {
                        Text("\(plan.items.filter(\.selected).count) selected")
                        Text(ByteFormat.string(plan.expectedImmediateReclaim))
                        Text(model.canReclaimSelected ? "Dry run complete" : "Dry run required")
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    ForEach(plan.dryRunSummary.prefix(12), id: \.self) { line in
                        Text(line).font(.system(.caption, design: .monospaced))
                    }
                    if let receipt = model.lastDryRunReceipt {
                        Divider()
                        Text("Latest dry-run receipt: \(receipt.actions.count) actions, \(receipt.errors.count) errors")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let receipt = model.lastExecutionReceipt {
                        Text("Latest reclaim receipt: \(receipt.actions.count) actions, \(receipt.errors.count) errors")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let url = model.lastPlanReportExportURL {
                        Text("Latest plan report: \(url.path)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            } else {
                ContentUnavailableView("No plan yet", systemImage: "checklist", description: Text("Run Plan to select only low-risk auto-safe findings."))
            }

            Spacer()
        }
        .padding(24)
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
                    MetricTile(title: "Active", value: model.selectedScopePlan.label)
                    MetricTile(title: "Roots", value: "\(model.selectedScopePlan.scopes.count)")
                    MetricTile(title: "Config", value: SavedScopeSetStore().scopeSetURL.lastPathComponent)
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
        ("Choose scan mode", "Shared scope presets cover Developer, General Mac, and All roots, with explicit scope preview and saved custom scope sets before scanning."),
        ("Find space offenders", "Bounded Swift scanner over preset or custom roots with size and permission evidence."),
        ("Classify safety", "Versioned JSON rules produce Auto-safe, Safe after condition, Review required, Preserve by default, and Never touch."),
        ("Inspect rules", "Bundled rules can be reviewed by safety class, action, category, match hints, conditions, recovery, and non-claims."),
        ("Explain every item", "Finding detail shows owner hints, rule matches, evidence, recovery, and conditions."),
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
        ("Schedule maintenance", "Per-user LaunchAgent writes saved report plans, no root helper."),
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

struct AuditHistoryView: View {
    let model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Audit History")
                    .font(.largeTitle.bold())
                Text("Local-only saved plans and execution receipts. Empty history is normal until a plan or dry run is saved.")
                    .foregroundStyle(.secondary)

                SectionBox(title: "Recent Plans") {
                    if model.recentPlans.isEmpty {
                        Text("No saved plans yet.")
                    } else {
                        if let url = model.lastPlanReportExportURL {
                            Text("Latest plan report: \(url.path)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        ForEach(model.recentPlans) { plan in
                            HStack {
                                Text("\(plan.createdAt.formatted()) - \(plan.items.filter(\.selected).count) selected - \(ByteFormat.string(plan.expectedImmediateReclaim))")
                                Spacer()
                                Button("Export") {
                                    Task { await model.exportPlanReport(plan) }
                                }
                                Button("Redacted") {
                                    Task { await model.exportPlanReport(plan, pathStyle: .redacted) }
                                }
                            }
                        }
                    }
                }

                SectionBox(title: "Recent Receipts") {
                    if model.recentReceipts.isEmpty {
                        Text("No receipts yet.")
                    } else {
                        if let url = model.lastReceiptReportExportURL {
                            Text("Latest receipt report: \(url.path)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        ForEach(model.recentReceipts) { receipt in
                            HStack {
                                Text("\(receipt.createdAt.formatted()) - \(receipt.mode) - \(receipt.actions.count) actions")
                                Spacer()
                                Button("Export") {
                                    Task { await model.exportReceiptReport(receipt) }
                                }
                                Button("Redacted") {
                                    Task { await model.exportReceiptReport(receipt, pathStyle: .redacted) }
                                }
                            }
                        }
                    }
                }

                SectionBox(title: "Native Tool Reports") {
                    if model.recentNativeToolReports.isEmpty {
                        Text("No native-tool reports yet.")
                    } else {
                        ForEach(model.recentNativeToolReports) { report in
                            Text("\(report.createdAt.formatted()) - \(report.receipts.count) candidate(s) - \(ByteFormat.string(report.totalBytesUnderNativeReview))")
                        }
                    }
                }

                SectionBox(title: "Container Inventory Reports") {
                    if model.recentContainerInventoryReports.isEmpty {
                        Text("No container inventory reports yet.")
                    } else {
                        ForEach(model.recentContainerInventoryReports) { report in
                            let reclaim = report.dockerReclaimableBytes.map(ByteFormat.string) ?? "unknown reclaim"
                            Text("\(report.createdAt.formatted()) - Docker \(report.docker.status.state.label), Colima \(report.colima.status.state.label) - \(reclaim)")
                        }
                    }
                }

                SectionBox(title: "Active File Reports") {
                    if model.recentActiveFileReviewReports.isEmpty {
                        Text("No active-file reports yet.")
                    } else {
                        ForEach(model.recentActiveFileReviewReports) { report in
                            Text("\(report.createdAt.formatted()) - \(report.openCount) open - \(report.failedCheckCount) failed - \(ByteFormat.string(report.totalBlockedBytes))")
                        }
                    }
                }
            }
            .padding(24)
        }
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

struct AgentStorageReviewView: View {
    let model: DashboardModel

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
                    Button {
                        Task { await model.reviewAgentStorage() }
                    } label: {
                        Label("Review Agents", systemImage: "sparkles.rectangle.stack")
                    }
                    .disabled(model.isWorking)
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
                        AppUninstallPreviewView(preview: preview)
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
    let finding: Finding
    let planItem: ReclaimPlanItem?

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
                }

                SectionBox(title: "What this is") {
                    Text("Scope: \(finding.scopeName)")
                    Text(finding.ownerHint ?? "Unknown owner")
                    Text("Logical: \(ByteFormat.string(finding.logicalSize)); allocated: \(ByteFormat.string(finding.allocatedSize))")
                    Text(finding.storageAccountingNote)
                        .foregroundStyle(.secondary)
                    if let date = finding.modificationDate {
                        Text("Modified: \(date.formatted())")
                    }
                    if let open = finding.openFileStatus {
                        Text(open.isOpen ? "Open by: \(open.processSummary.joined(separator: ", "))" : "Open handles: none")
                    } else {
                        Text("Open handles: not checked yet")
                    }
                    ForEach(finding.ruleMatches, id: \.ruleID) { match in
                        Text("\(match.category): \(match.title) (\(match.ruleID))")
                    }
                }

                SectionBox(title: "Actions") {
                    FindingActionButtons(finding: finding)
                }

                SectionBox(title: "Why this classification") {
                    ForEach(finding.evidence, id: \.self) { evidence in
                        Text("• \(evidence.message)")
                    }
                }

                SectionBox(title: "Recovery and conditions") {
                    if let planItem {
                        ForEach(planItem.conditions, id: \.message) { condition in
                            Text("\(condition.isSatisfied ? "OK" : "Blocked"): \(condition.message)")
                        }
                    } else if finding.ruleMatches.isEmpty {
                        Text("No recovery guidance available; review manually.")
                    } else {
                        ForEach(finding.ruleMatches, id: \.ruleID) { match in
                            if let recovery = match.recovery {
                                Text(recovery)
                            }
                            ForEach(match.conditions, id: \.self) { condition in
                                Text("• \(condition)")
                            }
                        }
                    }
                }

                if let nativeReceipt = NativeToolGuidance.receipt(for: finding) {
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
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } else {
                    let guidance = CleanupGuidance.commands(for: finding)
                    if !guidance.isEmpty {
                        SectionBox(title: "Guidance") {
                            ForEach(guidance, id: \.self) { line in
                                Text(line)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }

                if let planItem {
                    SectionBox(title: "Plan status") {
                        Text(planItem.selected ? "Selected for dry-run/action." : "Not selected automatically.")
                        Text("Estimated immediate reclaim: \(ByteFormat.string(planItem.estimatedImmediateReclaim))")
                    }
                }
            }
            .padding(24)
        }
    }
}

struct AutomationView: View {
    let model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Automation")
                .font(.largeTitle.bold())
            Text("Automation is report-first. Installing the LaunchAgent writes a plist that runs a saved dry-run plan report; it does not load or run until you choose to load it with launchctl.")
                .foregroundStyle(.secondary)

            HStack {
                SafetyBadge(safetyClass: .safeAfterCondition)
                Text(model.launchAgentInstalled ? "LaunchAgent plist installed" : "LaunchAgent plist not installed")
            }

            HStack {
                Button("Install Report Schedule") {
                    model.installSchedule()
                }
                Button("Remove Schedule") {
                    model.removeSchedule()
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
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

            VStack(spacing: 0) {
                TopOffenderHeader()
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

struct LargeOldReviewView: View {
    let model: DashboardModel
    @State private var mode = LargeOldReviewMode.all
    @State private var sort = TopOffenderSort.allocated

    private var report: LargeOldReviewReport {
        model.largeOldReviewReport(mode: mode, sort: sort, limit: 80)
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

                SectionBox(title: "Review Rows") {
                    VStack(spacing: 0) {
                        TopOffenderHeader()
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

struct TopOffenderHeader: View {
    var body: some View {
        HStack {
            Text("Reclaim").frame(width: 86, alignment: .leading)
            Text("Size").frame(width: 86, alignment: .leading)
            Text("Confidence").frame(width: 92, alignment: .leading)
            Text("Safety").frame(width: 150, alignment: .leading)
            Text("Category").frame(width: 130, alignment: .leading)
            Text("Owner").frame(width: 110, alignment: .leading)
            Text("Age").frame(width: 48, alignment: .leading)
            Text("Path")
            Spacer()
            Text("Actions").frame(width: 132, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
    }
}

struct TopOffenderRowView: View {
    let row: TopOffenderRow
    let isSelectedInPlan: Bool

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
            FindingActionButtons(finding: row.finding)
                .frame(width: 132, alignment: .trailing)
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
        .background(.quaternary.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Automation") {
                Text("Scheduled maintenance is report-first. Install the LaunchAgent from the CLI after reviewing a dry run.")
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
    var recentNativeToolReports: [NativeToolReport] = []
    var recentContainerInventoryReports: [ContainerInventoryReport] = []
    var recentActiveFileReviewReports: [ActiveFileReviewReport] = []
    var heldItems: [HeldItem] = []
    var recoveryReport: RecoveryCenterReport = RecoveryCenter.build(heldItems: [], receipts: [])
    var duplicateReview: DuplicateReview?
    var appReview: AppReviewReport?
    var appUninstallPreview: AppUninstallPreview?
    var agentStorageReview: AgentStorageReview?
    var containerInventory: ContainerInventoryReport?
    var activeFileReview: ActiveFileReviewReport?
    var userPathPolicy: UserPathPolicy = .empty
    var lastReportExportURL: URL?
    var lastPlanReportExportURL: URL?
    var lastReceiptReportExportURL: URL?
    var lastGrowthReportExportURL: URL?
    var lastPolicyExportURL: URL?
    var lastScopeSetExportURL: URL?
    var lastScopeSetImportResult: SavedScopeSetImportResult?
    var permissionReport: PermissionAdvisorReport = PermissionAdvisor.report(scopes: DefaultScopes.scopes(for: .developer, includeUnavailable: true))
    var scanSnapshots: [ScanSnapshot] = []
    var growthDeltas: [BucketGrowthDelta] = []
    var isWorking = false
    var lastScanDate: Date?
    var launchAgentInstalled = false
    var error: String?

    var selectedScopePlan: ScanScopePlan {
        if let selectedSavedScopeSet {
            return selectedSavedScopeSet.plan
        }
        return DefaultScopes.plan(for: scanPreset, includeUnavailable: true)
    }

    var selectedSavedScopeSet: SavedScopeSet? {
        guard let selectedSavedScopeSetID else { return nil }
        return savedScopeSets.first { $0.id == selectedSavedScopeSetID }
    }

    var reviewQueueReport: ReviewQueueReport {
        FindingAnalytics.reviewQueueReport(findings: findings, limitPerQueue: 12)
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
        return receipt.actions.allSatisfy { $0.status == "dry-run" } && receipt.errors.isEmpty
    }

    var reclaimConfirmationMessage: String {
        guard let plan else {
            return "No reclaim plan is available."
        }
        return "This will execute \(selectedPlanCount) selected auto-safe action(s), expected immediate reclaim \(ByteFormat.string(plan.expectedImmediateReclaim)). A receipt will be saved locally."
    }

    func setScanPreset(_ preset: ScanScopePreset) {
        guard scanPreset != preset || selectedSavedScopeSetID != nil else { return }
        scanPreset = preset
        selectedSavedScopeSetID = nil
        resetScanState()
        permissionReport = PermissionAdvisor.report(scopes: currentScopes(includeUnavailable: true))
        error = nil
    }

    func setSavedScopeSet(_ id: String?) {
        let normalizedID = id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextID = normalizedID?.isEmpty == true ? nil : normalizedID
        guard selectedSavedScopeSetID != nextID else { return }
        selectedSavedScopeSetID = nextID
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
    }

    private func currentScopes(includeUnavailable: Bool) -> [ScanScope] {
        if let selectedSavedScopeSet {
            return selectedSavedScopeSet.plan.scopes
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
            _ = try ScanHistoryStore().save(overview: result.3)
            loadHistory()
            plan = nil
            lastDryRunReceipt = nil
            lastExecutionReceipt = nil
            lastScanDate = Date()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func buildPlan() async {
        isWorking = true
        defer { isWorking = false }
        let currentFindings = findings
        plan = await Task.detached {
            let builder = PlanBuilder(openFileChecker: LsofOpenFileChecker())
            return builder.buildPlan(from: currentFindings, mode: .autoSafeOnly)
        }.value
        lastDryRunReceipt = nil
        lastExecutionReceipt = nil
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
            let receipt = try await Task.detached {
                let ruleVersion = try RuleEngine.bundled(includingUserRules: includeUserRules).version
                let policy = UserPathPolicyStore().load()
                return ReclaimerExecutor(
                    openFileChecker: LsofOpenFileChecker(),
                    configuration: ExecutorConfiguration(userPathPolicy: policy)
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
        recentPlans = store.recentPlans()
        recentReceipts = store.recentReceipts()
        recentNativeToolReports = store.recentNativeToolReports()
        recentContainerInventoryReports = store.recentContainerInventoryReports()
        recentActiveFileReviewReports = store.recentActiveFileReviewReports()
        loadRecovery()
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
            _ = try AuditStore().save(appUninstallPreview: preview)
            error = nil
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
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
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
            _ = try LaunchAgentManager().install(cliPath: cliPath)
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
        launchAgentInstalled = FileManager.default.fileExists(atPath: LaunchAgentManager().installedPath().path)
    }
}
