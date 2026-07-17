import SwiftUI
import ReclaimerCore

struct DashboardView: View {
    @Bindable var model: DashboardModel
    @AppStorage(RyddiAppStorageKey.defaultScanPreset) private var defaultScanPresetRaw = ScanScopePreset.developer.rawValue
    @AppStorage(RyddiAppStorageKey.includeUserRulesByDefault) private var includeUserRulesByDefault = false
    @SceneStorage("dashboard.selectedSectionID") private var selectedSectionID = DashboardLaunchOptions.initialSectionID

    private var selectedDestination: DashboardPrimaryDestination {
        DashboardPrimaryDestination.restoring(selectedSectionID)
    }

    var body: some View {
        NavigationSplitView {
            DashboardSidebarView(selection: Binding(
                get: { selectedDestination },
                set: { selectDestination($0) }
            ))
        } detail: {
            switch selectedDestination {
            case .home:
                HomeView(model: model, navigate: selectDestination)
            case .explore:
                ExploreView(model: model)
            case .history:
                HistoryView(model: model)
            }
        }
        .navigationSplitViewStyle(.balanced)
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
            .pickerStyle(.menu)
            .disabled(model.activeScanRequest != nil)
            .accessibilityIdentifier(AccessibilityID.scanMode)

            Button {
                model.startScan()
            } label: {
                Label(model.latestGuidedMap == nil ? "Scan your Mac" : "Scan Again", systemImage: "magnifyingglass")
            }
            .disabled(model.isWorking)
            .accessibilityIdentifier(AccessibilityID.scan)

            if model.activeScanRequest != nil {
                Button(role: .cancel) {
                    model.cancelScan()
                } label: {
                    Label("Cancel Scan", systemImage: "xmark.circle")
                }
                .accessibilityIdentifier(AccessibilityID.cancelScan)
            }

            scanActivityToolbarItem
        }
        .onAppear {
            model.applyStoredSettings(
                defaultScanPresetRaw: defaultScanPresetRaw,
                includeUserRulesByDefault: includeUserRulesByDefault
            )
            if let e2eScopeRoot = DashboardLaunchOptions.e2eScopeRoot {
                model.configureE2EScope(e2eScopeRoot)
            }
            model.loadSavedScopeSets()
            Task { await model.loadHoldingAndAudit() }
            model.loadHistory()
            model.loadUserPolicy()
            model.refreshAutomation()
            if !DashboardLaunchOptions.isE2EModeRequested || DashboardLaunchOptions.e2eScopeRoot != nil {
                model.refreshPermissions()
            }
            if !DashboardLaunchOptions.isE2EModeRequested {
                model.refreshRemoteTargets()
            }
            model.applyScreenshotDemoIfNeeded()
            if let e2eValidationError = DashboardLaunchOptions.e2eValidationError {
                model.error = e2eValidationError
            }
        }
    }

    private var commandActions: DashboardCommandActions {
        DashboardCommandActions(
            canScan: !model.isWorking,
            startScan: { model.startScan() },
            openDestination: selectDestination
        )
    }

    @ViewBuilder
    private var scanActivityToolbarItem: some View {
        switch model.activity(for: .scan) {
        case .running(_, _, let progress, let message):
            HStack(spacing: 6) {
                if let progress {
                    ProgressView(value: progress).frame(width: 52)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(message).font(.caption).lineLimit(1)
            }
            .accessibilityIdentifier(AccessibilityID.scanProgress)
        case .cancelling:
            ProgressView("Cancelling scan")
                .controlSize(.small)
                .accessibilityIdentifier(AccessibilityID.scanProgress)
        case .idle, .failed:
            EmptyView()
        }
    }

    private func selectDestination(_ destination: DashboardPrimaryDestination) {
        let span = model.diagnostics.begin(.navigation)
        selectedSectionID = destination.rawValue
        model.diagnostics.end(span)
        RyddiLog.window.info("destination=\(destination.rawValue, privacy: .public)")
    }
}
