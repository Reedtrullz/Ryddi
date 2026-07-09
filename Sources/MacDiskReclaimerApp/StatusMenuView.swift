import SwiftUI
import ReclaimerCore
#if os(macOS)
import AppKit
#endif

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
