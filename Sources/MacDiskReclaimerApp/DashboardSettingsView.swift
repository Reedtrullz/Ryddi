import SwiftUI
import ReclaimerCore

enum RyddiAppStorageKey {
    static let defaultScanPreset = "ryddi.defaultScanPreset"
    static let includeUserRulesByDefault = "ryddi.includeUserRulesByDefault"
    static let defaultReportPathStyle = "ryddi.defaultReportPathStyle"
    static let redactUserTextByDefault = "ryddi.redactUserTextByDefault"
}

struct DashboardSettingsView: View {
    @Bindable var model: DashboardModel
    @Bindable var updates: RyddiUpdateController
    @AppStorage(RyddiAppStorageKey.defaultScanPreset) private var defaultScanPresetRaw = ScanScopePreset.developer.rawValue
    @AppStorage(RyddiAppStorageKey.includeUserRulesByDefault) private var includeUserRulesByDefault = false
    @AppStorage(RyddiAppStorageKey.defaultReportPathStyle) private var defaultReportPathStyleRaw = ReportPathStyle.homeRelative.rawValue
    @AppStorage(RyddiAppStorageKey.redactUserTextByDefault) private var redactUserTextByDefault = false

    var body: some View {
        TabView {
            Form {
                Picker("Default scan mode", selection: $defaultScanPresetRaw) {
                    ForEach(ScanScopePreset.allCases) { preset in
                        Text(preset.label).tag(preset.rawValue)
                    }
                }

                Toggle("Include user rules by default", isOn: $includeUserRulesByDefault)
            }
            .tabItem {
                Label("Scanning", systemImage: "magnifyingglass")
            }

            Form {
                Picker("Default report paths", selection: $defaultReportPathStyleRaw) {
                    ForEach(ReportPathStyle.allCases, id: \.rawValue) { style in
                        Text(style.label).tag(style.rawValue)
                    }
                }

                Toggle("Redact user-entered text by default", isOn: $redactUserTextByDefault)
            }
            .tabItem {
                Label("Privacy", systemImage: "hand.raised")
            }

            Form {
                Text("Scheduled work is report-only. Ryddi does not run unattended destructive cleanup.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tabItem {
                Label("Automation", systemImage: "calendar.badge.clock")
            }

            Form {
                Toggle("Automatically check for updates", isOn: $updates.automaticallyChecksForUpdates)

                Button("Update to Latest Version") {
                    updates.updateToLatestVersion()
                }
                .disabled(!updates.canCheckForUpdates)

                Text("Ryddi checks its signed update feed in the background. Installing an update always requires a trusted, signed release and your confirmation.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tabItem {
                Label("Updates", systemImage: "arrow.triangle.2.circlepath")
            }

            AdvancedSettingsView(model: model)
                .tabItem {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                }
        }
        .frame(minWidth: 760, idealWidth: 920, minHeight: 560, idealHeight: 680)
        .scenePadding()
    }
}

private struct AdvancedSettingsView: View {
    @Bindable var model: DashboardModel
    @State private var section: DashboardSection = .permissions

    private let sections: [DashboardSection] = [
        .permissions, .scopes, .policy, .automation, .rules,
        .apps, .downloads, .duplicates, .browsers, .deviceBackups,
        .packages, .projects, .xcode, .containers, .agents,
        .remoteTargets, .active, .holding, .features
    ]

    var body: some View {
        NavigationSplitView {
            List(sections, selection: $section) { item in
                Label(item.title, systemImage: item.systemImage)
                    .tag(item)
            }
            .navigationTitle("Advanced")
        } detail: {
            Group {
                switch section {
                case .permissions: PermissionOnboardingView(model: model)
                case .scopes: SavedScopeSetView(model: model)
                case .policy: UserPathPolicyView(model: model)
                case .automation: AutomationView(model: model)
                case .rules: RuleCatalogView()
                case .apps: AppReviewView(model: model)
                case .downloads: DownloadsReviewView(model: model)
                case .duplicates: DuplicateReviewView(model: model)
                case .browsers: BrowserCacheReviewView(model: model)
                case .deviceBackups: DeviceBackupReviewView(model: model)
                case .packages:
                    PackageCacheReviewView(model: model) { raw in
                        section = DashboardSection.fromLegacyID(raw)
                    }
                case .projects: ProjectDependencyReviewView(model: model)
                case .xcode: XcodeReviewView(model: model)
                case .containers: ContainerInventoryView(model: model)
                case .agents: AgentStorageReviewView(model: model)
                case .remoteTargets: RemoteTargetsView(model: model)
                case .active: ActiveFileReviewView(model: model)
                case .holding: HoldingView(model: model)
                case .features: CapabilityMatrixView()
                default:
                    ContentUnavailableView("Choose an advanced tool", systemImage: "slider.horizontal.3")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
