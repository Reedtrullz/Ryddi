import SwiftUI
import RyddiProtectCore
import UniformTypeIdentifiers

struct CloudStorageWorkspaceView: View {
    let model: DashboardModel
    @State private var showMegaFolderPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                providerReadiness

                if let report = model.cloudStorageRootDiscovery {
                    discoveredRoots(report)
                    ForEach(report.candidates) { candidate in
                        if let inventory = model.cloudLocalInventoryReports[candidate.id] {
                            inventorySection(inventory)
                        }
                    }
                    discoveryBoundary(report)
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

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Cloud Storage")
                    .font(.largeTitle.bold())
                Text("Understand how Dropbox, Google Drive, and MEGA use this Mac. Confirm a folder, then review its local footprint without connecting an account or downloading cloud-only files.")
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
            Button("Add MEGA Folder") { showMegaFolderPicker = true }
                .disabled(model.isWorking)
        }
    }

    private var providerReadiness: some View {
        SectionBox(title: "Provider organization lanes") {
            LazyVGrid(columns: DashboardResponsiveGrid.metricColumns, spacing: 12) {
                providerCard("Dropbox", detail: "Local metadata ready; remote read-only adapter next")
                providerCard("Google Drive", detail: "Local metadata ready; Picker-scoped remote access next")
                providerCard("MEGA", detail: "Selected local folders ready; isolated read-only SDK next")
            }
            Text("Available now: bounded local-footprint and old-file review. Duplicate proof remains unavailable locally because Ryddi will not open or hash cloud files and risk hydration.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func discoveredRoots(_ report: CloudStorageRootDiscoveryReport) -> some View {
        SectionBox(title: "Local Sync Folders") {
            if report.candidates.isEmpty {
                ContentUnavailableView(
                    "No supported sync folders found",
                    systemImage: "externaldrive.badge.questionmark",
                    description: Text("Ryddi checked the standard File Provider folder only. You can add a MEGA sync folder explicitly without connecting an account.")
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(report.candidates) { candidate in
                        rootRow(candidate)
                        if candidate.id != report.candidates.last?.id { Divider() }
                    }
                }
            }
            if !report.rejectedSymlinks.isEmpty || !report.unreadableRoots.isEmpty {
                Label(
                    "Skipped \(report.rejectedSymlinks.count) symbolic link(s) and \(report.unreadableRoots.count) unreadable candidate(s).",
                    systemImage: "exclamationmark.shield"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    private func rootRow(_ candidate: CloudStorageRootCandidate) -> some View {
        let isConfirmed = model.confirmedCloudStorageRoots[candidate.id] != nil
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .foregroundStyle(isConfirmed ? .green : .blue)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(candidate.provider.label).font(.headline)
                    Text(isConfirmed ? "Confirmed for this session" : "Confirmation required")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isConfirmed ? .green : .orange)
                }
                Text(candidate.displayName)
                Text(candidate.url.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(candidate.origin == .fileProvider ? "Detected in macOS File Provider storage" : "Selected explicitly as a MEGA sync folder")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Button("Reveal") { PathActions.revealInFinder(candidate.url.path) }
                if isConfirmed {
                    Button("Analyze Metadata") {
                        Task { await model.scanConfirmedCloudStorageRoot(candidate) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isWorking)
                    Button("Unconfirm") { model.unconfirmCloudStorageRoot(candidate) }
                        .disabled(model.isWorking)
                } else {
                    Button("Confirm Folder") { model.confirmCloudStorageRoot(candidate) }
                        .buttonStyle(.bordered)
                        .disabled(model.isWorking)
                }
                if candidate.origin == .userSelected {
                    Button("Forget") { model.forgetSelectedMegaCloudRoot(candidate) }
                        .disabled(model.isWorking)
                }
            }
        }
    }

    private func inventorySection(_ report: CloudLocalInventoryReport) -> some View {
        SectionBox(title: "\(report.root.candidate.provider.label) Local Footprint") {
            HStack {
                Label(
                    report.isComplete ? "Complete within configured bounds" : "Partial inventory",
                    systemImage: report.isComplete ? "checkmark.shield" : "exclamationmark.triangle"
                )
                .foregroundStyle(report.isComplete ? .green : .orange)
                Spacer()
                Text("Metadata only · \(report.scannedEntryCount.formatted()) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: DashboardResponsiveGrid.metricColumns, spacing: 12) {
                metric("Visible logical size", bytes(report.logicalBytes), "File lengths visible locally")
                metric("Allocated on this Mac", bytes(report.allocatedBytes), "Filesystem blocks currently used")
                metric("Files reviewed", report.fileCount.formatted(), "\(report.sharedFileIdentityCount.formatted()) shared hard-link name(s)")
                metric("Zero-block files", report.zeroAllocatedBlockFileCount.formatted(), "May be placeholders or sparse files")
            }

            if !report.issues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(report.issues, id: \.self) { issue in
                        Label(issue.label, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            fileQueue(
                title: "Largest locally allocated files",
                emptyMessage: "No locally allocated regular files were found within the inventory bounds.",
                items: report.largeFiles,
                report: report
            )
            fileQueue(
                title: "Old locally allocated files",
                emptyMessage: "No locally allocated files older than one year were found within the inventory bounds.",
                items: report.staleFiles,
                report: report
            )

            Divider()
            ForEach(report.nonClaims, id: \.self) { note in
                Label(note, systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fileQueue(
        title: String,
        emptyMessage: String,
        items: [CloudLocalFileReview],
        report: CloudLocalInventoryReport
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            if items.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.relativePath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            Text("\(bytes(item.allocatedBytes)) local · \(bytes(item.logicalBytes)) logical · modified \(item.modifiedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Reveal") {
                            PathActions.revealInFinder(report.absoluteURL(for: item).path)
                        }
                    }
                }
            }
        }
    }

    private func discoveryBoundary(_ report: CloudStorageRootDiscoveryReport) -> some View {
        SectionBox(title: "Safety boundary") {
            ForEach(report.nonClaims, id: \.self) { note in
                Label(note, systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func providerCard(_ name: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(name).font(.headline)
            Text("Local inventory ready")
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

    private func metric(_ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, value), countStyle: .file)
    }
}
