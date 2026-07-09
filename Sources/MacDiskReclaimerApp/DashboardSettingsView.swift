import SwiftUI
import ReclaimerCore

enum RyddiAppStorageKey {
    static let defaultScanPreset = "ryddi.defaultScanPreset"
    static let includeUserRulesByDefault = "ryddi.includeUserRulesByDefault"
    static let defaultReportPathStyle = "ryddi.defaultReportPathStyle"
    static let redactUserTextByDefault = "ryddi.redactUserTextByDefault"
}

struct DashboardSettingsView: View {
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
        }
        .frame(width: 520, height: 300)
        .scenePadding()
    }
}
