import SwiftUI
import ReclaimerCore
#if os(macOS)
import AppKit
#endif

@main
struct MacDiskReclaimerApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .frame(minWidth: 980, minHeight: 680)
        }
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
            } else if selectedSection == "Audit" {
                AuditHistoryView(model: model)
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
            model.loadAudit()
            model.loadHolding()
            model.refreshAutomation()
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
                Button("Audit History") {
                    selectedFinding = nil
                    selectedSection = "Audit"
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
                    DisclosureGroup("\(queue.title) (\(queue.count), \(ByteFormat.string(queue.bytes)))") {
                        Text(queue.guidance)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(model.findings(in: queue.title)) { finding in
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
            Text("The first build focuses on developer and AI-agent storage: Codex, Docker/Colima, Xcode, package caches, browser caches, and stale temp data.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.isWorking {
                ProgressView("Working...")
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
                MetricTile(title: "Held items", value: "\(model.heldItems.count)")
            }

            if let overview = model.overview {
                PermissionCoverageView(overview: overview)
                AccountingNotesView(notes: overview.accountingNotes)
                TopOffendersView(findings: model.findings, plan: model.plan)
            }

            if let error = model.error {
                Text(error)
                    .foregroundStyle(.red)
            }

            if let plan = model.plan {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Dry-run plan").font(.headline)
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
                }
            } else {
                ContentUnavailableView("No plan yet", systemImage: "checklist", description: Text("Run Plan to select only low-risk auto-safe findings."))
            }

            Spacer()
        }
        .padding(24)
    }
}

struct CapabilityMatrixView: View {
    private let rows = [
        ("Find space offenders", "Bounded Swift scanner over developer/agent scopes with size and permission evidence."),
        ("Classify safety", "Versioned JSON rules produce Auto-safe, Safe after condition, Review required, Preserve by default, and Never touch."),
        ("Explain every item", "Finding detail shows owner hints, rule matches, evidence, recovery, and conditions."),
        ("Protect active files", "Plan/executor run open-file checks and skip active paths."),
        ("Plan before action", "CLI and app build dry-run plans; automation is report-first."),
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
                Text("The MVP focuses on developer and AI-agent bloat while keeping review and reversibility ahead of one-click cleanup.")
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
                        ForEach(model.recentPlans) { plan in
                            Text("\(plan.createdAt.formatted()) - \(plan.items.filter(\.selected).count) selected - \(ByteFormat.string(plan.expectedImmediateReclaim))")
                        }
                    }
                }

                SectionBox(title: "Recent Receipts") {
                    if model.recentReceipts.isEmpty {
                        Text("No receipts yet.")
                    } else {
                        ForEach(model.recentReceipts) { receipt in
                            Text("\(receipt.createdAt.formatted()) - \(receipt.mode) - \(receipt.actions.count) actions")
                        }
                    }
                }
            }
            .padding(24)
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

                let guidance = CleanupGuidance.commands(for: finding)
                if !guidance.isEmpty {
                    SectionBox(title: "Native guidance") {
                        ForEach(guidance, id: \.self) { line in
                            Text(line)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
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

enum TopOffenderSort: String, CaseIterable, Identifiable {
    case allocated = "Allocated"
    case logical = "Logical"
    case age = "Age"
    case risk = "Risk"
    case category = "Category"
    case scope = "Scope"

    var id: String { rawValue }
}

struct PermissionCoverageView: View {
    let overview: ScanOverview

    private var readable: Int {
        overview.scopeSummaries.filter { $0.permissionState == .readable }.count
    }

    private var blocked: [ScopeAccessSummary] {
        overview.scopeSummaries.filter { [.denied, .missing].contains($0.permissionState) }
    }

    var body: some View {
        SectionBox(title: "Permission Coverage") {
            HStack {
                Text("\(readable) of \(overview.scopeSummaries.count) expected scopes readable")
                    .font(.headline)
                Spacer()
                Text(blocked.isEmpty ? "Full scan coverage for configured scopes" : "\(blocked.count) unavailable")
                    .foregroundStyle(blocked.isEmpty ? .green : .orange)
            }
            Text("Ryddi works in degraded mode when some paths are missing or restricted. Full Disk Access can improve coverage, but cleanup still remains local and review-driven.")
                .foregroundStyle(.secondary)
            ForEach(blocked.prefix(6)) { scope in
                Text("\(scope.permissionState.rawValue): \(scope.name) - \(scope.message)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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

struct TopOffendersView: View {
    let findings: [Finding]
    let plan: ReclaimPlan?
    @State private var sort = TopOffenderSort.allocated

    private var sortedFindings: [Finding] {
        findings.sorted { lhs, rhs in
            switch sort {
            case .logical:
                return compare(lhs.logicalSize, rhs.logicalSize, lhs.path, rhs.path)
            case .age:
                return compare(Int64(lhs.ageInDays() ?? -1), Int64(rhs.ageInDays() ?? -1), lhs.path, rhs.path)
            case .risk:
                if lhs.safetyClass.riskRank == rhs.safetyClass.riskRank {
                    return lhs.allocatedSize > rhs.allocatedSize
                }
                return lhs.safetyClass.riskRank < rhs.safetyClass.riskRank
            case .category:
                if lhs.primaryCategory == rhs.primaryCategory {
                    return lhs.allocatedSize > rhs.allocatedSize
                }
                return lhs.primaryCategory < rhs.primaryCategory
            case .scope:
                if lhs.scopeName == rhs.scopeName {
                    return lhs.allocatedSize > rhs.allocatedSize
                }
                return lhs.scopeName < rhs.scopeName
            case .allocated:
                return compare(lhs.allocatedSize, rhs.allocatedSize, lhs.path, rhs.path)
            }
        }
    }

    var body: some View {
        SectionBox(title: "Top Offenders") {
            Picker("Sort", selection: $sort) {
                ForEach(TopOffenderSort.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(spacing: 0) {
                HStack {
                    Text("Size").frame(width: 92, alignment: .leading)
                    Text("Safety").frame(width: 150, alignment: .leading)
                    Text("Category").frame(width: 130, alignment: .leading)
                    Text("Age").frame(width: 56, alignment: .leading)
                    Text("Path")
                    Spacer()
                    Text("Actions").frame(width: 132, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)

                ForEach(sortedFindings.prefix(14)) { finding in
                    Divider()
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ByteFormat.string(finding.allocatedSize))
                            Text(ByteFormat.string(finding.logicalSize))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 92, alignment: .leading)
                        SafetyBadge(safetyClass: finding.safetyClass)
                            .frame(width: 150, alignment: .leading)
                        Text(finding.primaryCategory)
                            .frame(width: 130, alignment: .leading)
                        Text(finding.ageInDays().map { "\($0)d" } ?? "-")
                            .frame(width: 56, alignment: .leading)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.displayName)
                                .lineLimit(1)
                            Text(finding.path)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        FindingActionButtons(finding: finding)
                            .frame(width: 132, alignment: .trailing)
                    }
                    .padding(.vertical, 7)
                }
            }
        }
    }

    private func compare(_ lhsValue: Int64, _ rhsValue: Int64, _ lhsPath: String, _ rhsPath: String) -> Bool {
        if lhsValue == rhsValue {
            return lhsPath < rhsPath
        }
        return lhsValue > rhsValue
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

enum PathActions {
    static func copyPath(_ path: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
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

struct QueueSummary: Identifiable {
    var id: String { title }
    let title: String
    let count: Int
    let bytes: Int64
    let guidance: String
}

@MainActor
@Observable
final class DashboardModel {
    var findings: [Finding] = []
    var scanScopes: [ScanScope] = []
    var overview: ScanOverview?
    var plan: ReclaimPlan?
    var lastDryRunReceipt: ExecutionReceipt?
    var lastExecutionReceipt: ExecutionReceipt?
    var recentPlans: [ReclaimPlan] = []
    var recentReceipts: [ExecutionReceipt] = []
    var heldItems: [HeldItem] = []
    var isWorking = false
    var lastScanDate: Date?
    var launchAgentInstalled = false
    var error: String?

    var queueSummaries: [QueueSummary] {
        [
            queue("Safe Maintenance", guidance: "Auto-safe cache/temp candidates selected only after open-file checks."),
            queue("Quit App First", guidance: "Likely rebuildable, but owner apps should be quit before cleanup."),
            queue("Use Native Tool", guidance: "Container/package-manager state should be handled by native cleanup commands."),
            queue("Valuable History", guidance: "Transcripts and assistant history may contain useful provenance."),
            queue("Personal/App Assets", guidance: "Creative, media, profile, and app-managed assets stay preserve-by-default."),
            queue("Unknown", guidance: "Anything unmatched or ambiguous remains report-only.")
        ]
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

    func totalBytes(for safetyClass: SafetyClass) -> Int64 {
        findings.filter { $0.safetyClass == safetyClass }.reduce(0) { $0 + $1.allocatedSize }
    }

    func findings(in queue: String) -> [Finding] {
        findings.filter { finding in
            switch queue {
            case "Safe Maintenance": finding.safetyClass == .autoSafe
            case "Quit App First": finding.safetyClass == .safeAfterCondition && finding.actionKind != .nativeToolCommand
            case "Use Native Tool": finding.actionKind == .nativeToolCommand
            case "Valuable History": finding.safetyClass == .preserveByDefault && finding.ownerHint == "Codex"
            case "Personal/App Assets": finding.safetyClass == .preserveByDefault && finding.ownerHint != "Codex"
            default: finding.safetyClass == .reviewRequired || finding.ruleMatches.isEmpty
            }
        }
    }

    func scan() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await Task.detached {
                let scopes = DefaultScopes.developerAgentBloat(includeUnavailable: true)
                let scanner = try FileScanner(openFileChecker: NoOpenFilesChecker())
                let findings = scanner.scan(scopes: scopes, options: ScanOptions(includeOpenFileStatus: false))
                return (scopes, findings, FindingAnalytics.overview(findings: findings, scopes: scopes))
            }.value
            scanScopes = result.0
            findings = result.1
            overview = result.2
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
            let receipt = try await Task.detached {
                let ruleVersion = try RuleEngine.bundled().version
                return ReclaimerExecutor(openFileChecker: LsofOpenFileChecker())
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
            let receipt = try await Task.detached {
                let ruleVersion = try RuleEngine.bundled().version
                return ReclaimerExecutor(openFileChecker: LsofOpenFileChecker())
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
            error = receipt.errors.isEmpty ? nil : receipt.errors.joined(separator: "\n")
            let refreshed = try await Task.detached {
                let scopes = DefaultScopes.developerAgentBloat(includeUnavailable: true)
                let scanner = try FileScanner(openFileChecker: NoOpenFilesChecker())
                let findings = scanner.scan(scopes: scopes, options: ScanOptions(includeOpenFileStatus: false))
                return (scopes, findings, FindingAnalytics.overview(findings: findings, scopes: scopes))
            }.value
            scanScopes = refreshed.0
            findings = refreshed.1
            overview = refreshed.2
            plan = nil
            lastDryRunReceipt = nil
            lastScanDate = Date()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadAudit() {
        let store = AuditStore()
        recentPlans = store.recentPlans()
        recentReceipts = store.recentReceipts()
    }

    func loadHolding() {
        heldItems = HoldingStore().list()
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

    func planItem(for findingID: Finding.ID) -> ReclaimPlanItem? {
        plan?.items.first { $0.finding.id == findingID }
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

    private func queue(_ title: String, guidance: String) -> QueueSummary {
        let queueFindings = findings(in: title)
        return QueueSummary(
            title: title,
            count: queueFindings.count,
            bytes: queueFindings.reduce(0) { $0 + $1.allocatedSize },
            guidance: guidance
        )
    }
}
