import SwiftUI
import ReclaimerCore

struct DashboardView: View {
    @State private var model = DashboardModel()
    @AppStorage(RyddiAppStorageKey.defaultScanPreset) private var defaultScanPresetRaw = ScanScopePreset.developer.rawValue
    @AppStorage(RyddiAppStorageKey.includeUserRulesByDefault) private var includeUserRulesByDefault = false
    @AppStorage(RyddiAppStorageKey.defaultReportPathStyle) private var defaultReportPathStyleRaw = ReportPathStyle.homeRelative.rawValue
    @AppStorage(RyddiAppStorageKey.redactUserTextByDefault) private var redactUserTextByDefault = false
    @State private var selectedFinding: Finding.ID?
    @SceneStorage("dashboard.selectedSectionID") private var selectedSectionID = DashboardLaunchOptions.initialSectionID
    @State private var showingReclaimConfirmation = false

    var body: some View {
        NavigationSplitView {
            DashboardSidebarView(selection: Binding(
                get: { selectedSection },
                set: { selectSection($0) }
            ))
        } detail: {
            switch selectedSection {
            case .features:
                CapabilityMatrixView()
            case .rules:
                RuleCatalogView()
            case .apps:
                AppReviewView(model: model)
            case .queues:
                ReviewQueuesView(model: model) { finding in
                    selectedFinding = finding.id
                    selectedSectionID = DashboardSection.finding.rawValue
                }
            case .largeOld:
                LargeOldReviewView(model: model)
            case .duplicates:
                DuplicateReviewView(model: model)
            case .downloads:
                DownloadsReviewView(model: model)
            case .browsers:
                BrowserCacheReviewView(model: model)
            case .packages:
                PackageCacheReviewView(model: model) { section in
                    selectedFinding = nil
                    selectedSectionID = DashboardSection.fromLegacyID(section).rawValue
                }
            case .projects:
                ProjectDependencyReviewView(model: model)
            case .deviceBackups:
                DeviceBackupReviewView(model: model)
            case .xcode:
                XcodeReviewView(model: model)
            case .trash:
                TrashReviewView(model: model)
            case .containers:
                ContainerInventoryView(model: model)
            case .remoteTargets:
                RemoteTargetsView(model: model)
            case .agents:
                AgentStorageReviewView(model: model)
            case .permissions:
                PermissionOnboardingView(model: model)
            case .active:
                ActiveFileReviewView(model: model)
            case .scopes:
                SavedScopeSetView(model: model)
            case .policy:
                UserPathPolicyView(model: model)
            case .audit:
                AuditHistoryView(model: model)
            case .recovery:
                RecoveryCenterView(model: model)
            case .holding:
                HoldingView(model: model)
            case .automation:
                AutomationView(model: model)
            case .finding:
                if let finding = model.findings.first(where: { $0.id == selectedFinding }) {
                    FindingDetailView(model: model, finding: finding, planItem: model.planItem(for: finding.id))
                } else {
                    OverviewView(
                        model: model,
                        onReclaim: { showingReclaimConfirmation = true },
                        navigate: selectLegacySection
                    )
                }
            case .summary:
                OverviewView(
                    model: model,
                    onReclaim: { showingReclaimConfirmation = true },
                    navigate: selectLegacySection
                )
            }
        }
        .focusedSceneValue(\.dashboardCommandActions, commandActions)
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
                    exportEvidenceReportUsingDefaults()
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
                .disabled(!model.canReclaimSelected || selectedSection == .remoteTargets)
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
            model.applyStoredSettings(
                defaultScanPresetRaw: defaultScanPresetRaw,
                includeUserRulesByDefault: includeUserRulesByDefault
            )
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

    private var commandActions: DashboardCommandActions {
        DashboardCommandActions(
            canScan: !model.isWorking,
            canPlan: !model.findings.isEmpty && !model.isWorking,
            canDryRun: (model.plan != nil || !model.findings.isEmpty) && !model.isWorking,
            canExport: model.overview != nil && !model.findings.isEmpty && !model.isWorking,
            canReclaim: model.canReclaimSelected && selectedSection != .remoteTargets,
            scan: { Task { await model.scan() } },
            buildPlan: { Task { await model.buildPlan() } },
            dryRun: { Task { await model.runDryRun() } },
            exportReport: exportEvidenceReportUsingDefaults,
            exportRedactedReport: { Task { await model.exportEvidenceReport(pathStyle: .redacted, redactUserText: true) } },
            reclaim: { showingReclaimConfirmation = true },
            openSection: { selectSection($0) }
        )
    }

    private var defaultReportPathStyle: ReportPathStyle {
        ReportPathStyle(rawValue: defaultReportPathStyleRaw) ?? .homeRelative
    }

    private var selectedSection: DashboardSection {
        DashboardSection(rawValue: selectedSectionID) ?? .summary
    }

    private func selectSection(_ section: DashboardSection) {
        selectedFinding = nil
        selectedSectionID = section.rawValue
    }

    private func selectLegacySection(_ sectionID: String) {
        selectSection(DashboardSection.fromLegacyID(sectionID))
    }

    private func exportEvidenceReportUsingDefaults() {
        Task {
            await model.exportEvidenceReport(pathStyle: defaultReportPathStyle, redactUserText: redactUserTextByDefault)
        }
    }
}
