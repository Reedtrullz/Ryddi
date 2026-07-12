import SwiftUI
import ReclaimerCore
#if os(macOS)
import AppKit
#endif

struct StatusMenuView: View {
    @Bindable var model: DashboardModel
    let scanAction: @MainActor () async -> Void
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
                    Text(model.lastScanDate?.formatted(date: .omitted, time: .shortened) ?? "Not run")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Report findings")
                    Spacer()
                    Text(model.overview.map { "\($0.findingCount)" } ?? "-")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Auto-safe bytes")
                    Spacer()
                    Text(model.overview.map { ByteFormat.string($0.expectedAutoSafeBytes) } ?? "-")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Automation")
                    Spacer()
                    Text(model.launchAgentStatus.installed ? "Installed" : "Off")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            if model.overview != nil {
                Text("Open Ryddi to review")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                    model.refreshAutomation()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Button {
                    Task { await scanAction() }
                } label: {
                    Label("Scan", systemImage: "magnifyingglass")
                }
                .disabled(model.isWorking)
            }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear {
            model.refreshAutomation()
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
