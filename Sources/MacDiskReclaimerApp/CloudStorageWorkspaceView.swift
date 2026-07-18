import SwiftUI
import RyddiProtectCore
import UniformTypeIdentifiers

struct CloudStorageWorkspaceView: View {
    let model: DashboardModel
    @State private var showMegaFolderPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cloud Storage")
                            .font(.largeTitle.bold())
                        Text("Find local Dropbox, Google Drive, and MEGA folders now; organize remote inventories later without giving cleanup authority to a provider connection.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        Task { await model.discoverCloudStorageRoots() }
                    } label: {
                        Label("Discover Folders", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isWorking)
                    Button("Add MEGA Folder") {
                        showMegaFolderPicker = true
                    }
                    .disabled(model.isWorking)
                }

                providerReadiness

                if let report = model.cloudStorageRootDiscovery {
                    SectionBox(title: "Local Sync Folders") {
                        if report.candidates.isEmpty {
                            ContentUnavailableView(
                                "No supported sync folders found",
                                systemImage: "externaldrive.badge.questionmark",
                                description: Text("Ryddi checked the standard File Provider folder only. You can keep using cloud providers without connecting them to Ryddi.")
                            )
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(report.candidates) { candidate in
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: "externaldrive.connected.to.line.below")
                                            .foregroundStyle(.blue)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(candidate.provider.label)
                                                .font(.headline)
                                            Text(candidate.displayName)
                                            Text(candidate.url.path)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                                .textSelection(.enabled)
                                            Text("Needs confirmation before protection or organization guidance")
                                                .font(.caption)
                                                .foregroundStyle(.orange)
                                        }
                                        Spacer()
                                        Button("Reveal") { PathActions.revealInFinder(candidate.url.path) }
                                    }
                                    if candidate.id != report.candidates.last?.id { Divider() }
                                }
                            }
                        }
                    }

                    SectionBox(title: "Safety boundary") {
                        ForEach(report.nonClaims, id: \.self) { note in
                            Label(note, systemImage: "lock.shield")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Discover cloud folders",
                        systemImage: "externaldrive.connected.to.line.below",
                        description: Text("Discovery is user-started and shallow. It does not open files, hydrate placeholders, or contact Dropbox, Google Drive, or MEGA.")
                    )
                    .frame(minHeight: 220)
                }
            }
            .padding(24)
        }
        .fileImporter(
            isPresented: $showMegaFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task { await model.discoverCloudStorageRoots(userSelectedMegaRoots: urls) }
        }
    }

    private var providerReadiness: some View {
        SectionBox(title: "Provider organization lanes") {
            LazyVGrid(columns: DashboardResponsiveGrid.metricColumns, spacing: 12) {
                providerCard("Dropbox", detail: "Read-only metadata adapter next")
                providerCard("Google Drive", detail: "User-selected Picker scope next")
                providerCard("MEGA", detail: "Custom local folder ready; isolated read-only SDK next")
            }
            Text("Planned review queues: large files, old files, and cryptographic-hash duplicate groups. Matching names or sizes alone will never be treated as duplicate proof.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func providerCard(_ name: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(name).font(.headline)
            Text("Local discovery ready")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }
}
