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
                operationFeedback
                setupGuide
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

    private var setupGuide: some View {
        SectionBox(title: "Set up local cloud review") {
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    "Ryddi reviews folders already configured by each provider's Mac app. It does not sign in to your cloud account yet.",
                    systemImage: "person.crop.circle.badge.exclamationmark"
                )
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

                setupStep(
                    1,
                    title: "Set up the provider on this Mac",
                    detail: "Install and sign in to Dropbox, Google Drive, or MEGA using the provider's own Mac app."
                )
                setupStep(
                    2,
                    title: "Choose what stays local",
                    detail: "Provider settings decide which files are downloaded. Ryddi will not hydrate cloud-only placeholders."
                )
                setupStep(
                    3,
                    title: "Return here and review",
                    detail: "Use Discover Folders for Dropbox and Google Drive. For MEGA, use Add MEGA Folder and choose the exact local sync folder."
                )
            }
        }
        .accessibilityIdentifier("cloud-footprint.setup-guide")
    }

    private func setupStep(_ number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number.formatted())
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(title). \(detail)")
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                headerCopy
                Spacer(minLength: 20)
                headerActions
            }
            VStack(alignment: .leading, spacing: 12) {
                headerCopy
                headerActions
            }
        }
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cloud Footprint")
                .font(.largeTitle.bold())
            Text("Review what Dropbox, Google Drive, and MEGA currently allocate on this Mac. Ryddi does not connect an account, organize remote files, or download cloud-only content.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headerActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                discoverFoldersButton
                addMegaFolderButton
            }
            VStack(alignment: .leading, spacing: 8) {
                discoverFoldersButton
                addMegaFolderButton
            }
        }
    }

    private var discoverFoldersButton: some View {
        Button {
            Task { await model.discoverCloudStorageRoots() }
        } label: {
            Label("Discover Folders", systemImage: "magnifyingglass")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.isWorking)
        .accessibilityIdentifier("cloud-footprint.discover")
    }

    private var addMegaFolderButton: some View {
        Button("Add MEGA Folder") { showMegaFolderPicker = true }
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(model.isWorking)
            .accessibilityIdentifier("cloud-footprint.add-mega")
    }

    @ViewBuilder
    private var operationFeedback: some View {
        if let operation = model.cloudFootprintOperation {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(operation.message)
                    .font(.callout.weight(.medium))
                Spacer()
                Button("Stop", role: .cancel) {
                    model.cancelCloudFootprintOperation()
                }
                .disabled(operation == .cancelling)
                .accessibilityIdentifier("cloud-footprint.cancel")
            }
            .padding(12)
            .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityIdentifier("cloud-footprint.operation-status")
        } else if model.isWorking {
            Label("Another Ryddi task is running. Finish it before starting a cloud review.", systemImage: "hourglass")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if let message = model.cloudFootprintMessage {
            Label(message, systemImage: "checkmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier("cloud-footprint.result")
        }

        if let error = model.cloudFootprintError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier("cloud-footprint.error")
        }
    }

    private var providerReadiness: some View {
        SectionBox(title: "What works today") {
            LazyVGrid(columns: DashboardResponsiveGrid.metricColumns, spacing: 12) {
                providerCard("Dropbox", detail: "Review a confirmed local File Provider folder")
                providerCard("Google Drive", detail: "Review a confirmed local File Provider folder")
                providerCard("MEGA", detail: "Review a folder you select explicitly")
            }
            DisclosureGroup("Provider roadmap and current limits") {
                Text("Remote account organization is not connected in this version. Duplicate proof also remains unavailable locally because Ryddi will not open or hash cloud files and risk hydration.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
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
                    .accessibilityIdentifier("cloud-footprint.analyze.\(candidate.id)")
                    Button("Unconfirm") { model.unconfirmCloudStorageRoot(candidate) }
                        .disabled(model.isWorking)
                } else {
                    Button("Confirm Folder") { model.confirmCloudStorageRoot(candidate) }
                        .buttonStyle(.bordered)
                        .disabled(model.isWorking)
                        .accessibilityIdentifier("cloud-footprint.confirm.\(candidate.id)")
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
            DisclosureGroup("Technical limits") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(report.nonClaims, id: \.self) { note in
                        Label(note, systemImage: "lock.shield")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 6)
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
                                .font(.caption)
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
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(report.nonClaims, id: \.self) { note in
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 6)
        } label: {
            Label("Discovery safety boundary", systemImage: "lock.shield")
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private func providerCard(_ name: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(name).font(.headline)
            Text("Local review ready")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
            Text(detail)
                .font(.caption)
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
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, value), countStyle: .file)
    }
}
