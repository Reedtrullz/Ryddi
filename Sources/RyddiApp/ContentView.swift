import SwiftUI
import AppKit
import ReclaimerCore

struct ContentView: View {
    @ObservedObject var engine: ScanEngine

    var body: some View {
        VStack(spacing: 0) {
            if engine.items.isEmpty && !engine.hasEverScanned {
                EmptyStateView(engine: engine)
            } else {
                Picker("View", selection: $engine.activePillar) {
                    Text("Clean").tag(0)
                    Text("Offload").tag(1)
                    Text("Control").tag(2)
                    Text("Audit").tag(3)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 12)

                if let error = engine.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                if engine.isScanning || engine.isAuditing || engine.isCleaning {
                    ProgressView(engine.isCleaning ? "Moving selected items to Trash..." : engine.isAuditing ? "Auditing..." : "Scanning...")
                        .controlSize(.small).padding(.vertical, 4)
                }

                ScrollView {
                    switch engine.activePillar {
                    case 0: CleanPillar(engine: engine)
                    case 1: OffloadPillar(engine: engine)
                    case 2: ControlPillar(engine: engine)
                    case 3: AuditPillar(engine: engine)
                    default: EmptyView()
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 550)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !engine.items.isEmpty {
                    Button(action: { engine.copyReclaimReport() }) {
                        Label("Copy Report", systemImage: "doc.on.clipboard")
                    }
                    .help("Copy reclaim report to clipboard")
                }
            }
        }
        .navigationTitle("Ryddi")
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    @ObservedObject var engine: ScanEngine

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 64)).foregroundStyle(.green)
            Text("Ryddi").font(.largeTitle.bold())
            Text("Find and reclaim disk space")
                .font(.title3).foregroundStyle(.secondary)
            Text("Scans caches, cloud sync folders, and bloated programs.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)

            if engine.isScanning {
                ProgressView("Scanning your Mac...").controlSize(.large).padding(.top, 8)
            } else {
                if engine.needsFullDiskAccess {
                    VStack(spacing: 6) {
                        Label("Full Disk Access recommended", systemImage: "lock.shield")
                            .foregroundStyle(.orange)
                        Text("Grant in System Settings → Privacy & Security → Full Disk Access")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }

                Button(action: { engine.scanAll() }) {
                    Label("Scan for Space", systemImage: "play.fill")
                        .padding(.horizontal, 24).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Custom Paths", systemImage: "folder.badge.plus").font(.headline)
                    if !engine.customPaths.isEmpty {
                        ForEach(engine.customPaths, id: \.self) { path in
                            HStack {
                                Text(path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                Button(action: { engine.removeCustomPath(path) }) {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove \(path)")
                            }
                        }
                    }
                    Button(action: {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.begin { response in
                            if response == .OK, let url = panel.url {
                                engine.addCustomPath(url.path)
                            }
                        }
                    }) {
                        Label("Add Path", systemImage: "plus.circle")
                    }.buttonStyle(.borderless)
                }
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            if let error = engine.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Clean pillar

struct CleanPillar: View {
    @ObservedObject var engine: ScanEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if engine.items.isEmpty && engine.hasEverScanned {
                ContentUnavailableView {
                    Label("No Selectable Safe Items", systemImage: "checkmark.circle")
                } description: {
                    Text("Ryddi found no unconditional cleanup actions. Review permissions and any Review First results; an empty scan is not proof that the disk is tidy.")
                }
                .padding(.vertical, 20)
            } else if engine.isEmergency {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Low Disk Space", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("Less than 10 GB free. Select the reviewed Safe items, then confirm what moves to Trash.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button(action: { engine.selectAllSafe() }) {
                        Label("Select Safe Items — \(ByteCountFormatter().string(fromByteCount: engine.safeTotalBytes))", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.large)
                }
                .padding(16)
                .background(.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Safe to reclaim").font(.headline)
                    Text(ByteCountFormatter().string(fromByteCount: engine.selectedReclaimBytes))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                }
                Spacer()
                if !engine.safeItems.isEmpty {
                    if engine.selectedIDs.isEmpty {
                        Button("Select All Safe") { engine.selectAllSafe() }
                    } else {
                        Button("Clear Selection") { engine.selectedIDs = [] }
                    }
                }
                if engine.selectedReclaimBytes > 0 {
                    Button(action: {
                        engine.confirmationTitle = "Reclaim \(ByteCountFormatter().string(fromByteCount: engine.selectedReclaimBytes))?"
                        engine.confirmationMessage = "\(engine.selectedIDs.count) items will be moved to Trash."
                        engine.confirmationIsDestructive = true
                        engine.pendingAction = { engine.reclaim() }
                        engine.showConfirmation = true
                    }) {
                        Label("Reclaim", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)
                    .disabled(engine.isCleaning || engine.isScanning)
                }
            }
            .padding(16)
            .background(.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Picker("View", selection: $engine.cleanViewMode) {
                ForEach(CleanViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 180)

            if engine.cleanViewMode == .chart {
                ForEach(Bucket.allCases, id: \.self) { bucket in
                    let bucketItems = engine.items.filter { $0.bucket == bucket }
                    if !bucketItems.isEmpty {
                        CleanChartSection(bucket: bucket, items: bucketItems, engine: engine)
                    }
                }
            } else {
                ForEach(Bucket.allCases, id: \.self) { bucket in
                    let bucketItems = engine.items.filter { $0.bucket == bucket }
                    if !bucketItems.isEmpty {
                        GroupedBucketSectionView(bucket: bucket, items: bucketItems, engine: engine)
                    }
                }
            }
        }.padding()
    }
}

struct GroupedBucketSectionView: View {
    let bucket: Bucket
    let items: [ScanItem]
    @ObservedObject var engine: ScanEngine

    var body: some View {
        let groups = engine.groupedItems(items)
        let formatter = ByteCountFormatter()
        VStack(alignment: .leading, spacing: 8) {
            Label("\(bucket.rawValue) (\(items.count) items, \(groups.count) groups)",
                  systemImage: bucket == .safe ? "checkmark.circle.fill"
                  : bucket == .review ? "eye.circle.fill" : "lock.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(bucket == .safe ? .green : bucket == .review ? .yellow : .red)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            LazyVStack(spacing: 0) {
                ForEach(groups) { group in
                        if group.count == 1, let item = group.items.first {
                            HStack(spacing: 12) {
                                if bucket == .safe {
                                    Toggle(isOn: Binding(
                                        get: { engine.selectedIDs.contains(item.id) },
                                        set: { s in if s { engine.selectedIDs.insert(item.id) } else { engine.selectedIDs.remove(item.id) } }
                                    )) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name).font(.body)
                                            Text(item.ruleTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                } else {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name).font(.body)
                                        Text(item.ruleTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer()
                                Text(formatter.string(fromByteCount: item.sizeBytes))
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        } else {
                            DisclosureGroup(isExpanded: Binding(
                                get: { engine.isGroupExpanded(group.baseName) },
                                set: { engine.setGroupExpanded(group.baseName, expanded: $0) }
                            )) {
                                ForEach(group.items) { item in
                                    HStack(spacing: 12) {
                                        if bucket == .safe {
                                            Toggle(isOn: Binding(
                                                get: { engine.selectedIDs.contains(item.id) },
                                                set: { s in if s { engine.selectedIDs.insert(item.id) } else { engine.selectedIDs.remove(item.id) } }
                                            )) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(item.name).font(.body)
                                                    Text(item.ruleTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                                }
                                            }
                                            .toggleStyle(.checkbox)
                                            .padding(.leading, 20)
                                        } else {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.name).font(.body)
                                                Text(item.ruleTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                            }
                                            .padding(.leading, 20)
                                        }
                                        Spacer()
                                        Text(formatter.string(fromByteCount: item.sizeBytes))
                                            .font(.body.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    if bucket == .safe {
                                        let allSelected = group.items.allSatisfy { engine.selectedIDs.contains($0.id) }
                                        let someSelected = group.items.contains { engine.selectedIDs.contains($0.id) }
                                        Button {
                                            engine.selectGroup(group, selected: !allSelected)
                                        } label: {
                                            Label(
                                                group.baseName,
                                                systemImage: allSelected
                                                    ? "checkmark.square.fill"
                                                    : someSelected ? "minus.square.fill" : "square"
                                            )
                                            .font(.body)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(allSelected ? .green : someSelected ? .yellow : .primary)
                                        .accessibilityLabel(
                                            allSelected
                                                ? "Clear all versions of \(group.baseName)"
                                                : "Select all versions of \(group.baseName)"
                                        )
                                    } else {
                                        Text(group.baseName).font(.body)
                                    }
                                    Spacer()
                                    Text("\(group.count) versions")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(formatter.string(fromByteCount: group.totalSizeBytes))
                                        .font(.body.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    if group.id != groups.last?.id { Divider() }
                }
            }
            .padding(.horizontal, 12)
            .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct CleanChartSection: View {
    let bucket: Bucket
    let items: [ScanItem]
    @ObservedObject var engine: ScanEngine

    var body: some View {
        let groups = engine.groupedItems(items)
        let maxSize = max(groups.first?.totalSizeBytes ?? 1, 1)
        let fmt = ByteCountFormatter()

        VStack(alignment: .leading, spacing: 12) {
            Label("\(bucket.rawValue) (\(items.count) items, \(groups.count) groups)",
                  systemImage: bucket == .safe ? "checkmark.circle.fill"
                  : bucket == .review ? "eye.circle.fill" : "lock.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(bucket == .safe ? .green : bucket == .review ? .yellow : .red)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(groups.prefix(20)) { group in
                    let fraction = Double(group.totalSizeBytes) / Double(maxSize)
                    HStack(spacing: 8) {
                        Text(group.baseName)
                            .font(.caption)
                            .lineLimit(1)
                            .frame(width: 120, alignment: .leading)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(bucket == .safe ? Color.green : bucket == .review ? Color.yellow : Color.red)
                                .frame(width: max(geo.size.width * fraction, 4), height: 14)
                        }
                        .frame(height: 14)
                        Text(fmt.string(fromByteCount: group.totalSizeBytes))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .trailing)
                    }
                    .frame(height: 18)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - Offload pillar

struct OffloadPillar: View {
    @ObservedObject var engine: ScanEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if engine.showCopyComplete, let source = engine.lastCopiedSource {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Copy Complete", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("\"\(URL(fileURLWithPath: source).lastPathComponent)\" was copied into the provider-managed folder.")
                        .font(.body)
                    Text("The original remains in place. Ryddi does not claim that the provider has uploaded the copy.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button("Show in Finder") {
                            if let dest = engine.lastCopiedDest {
                                NSWorkspace.shared.selectFile(dest, inFileViewerRootedAtPath: "")
                            }
                        }
                        Button("Done") { engine.dismissCopyPrompt() }
                    }
                }
                .padding(16)
                .background(.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if engine.isCopying {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Copying to cloud...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            if !engine.cloudProviders.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Cloud Sync Folders", systemImage: "externaldrive.fill.badge.icloud")
                        .font(.headline)
                    ForEach(engine.cloudProviders) { provider in
                        HStack(spacing: 12) {
                            Image(systemName: provider.icon)
                                .foregroundStyle(.blue)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name)
                                    .font(.body)
                                Text(provider.syncFolderPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("Show in Finder") {
                                NSWorkspace.shared.open(URL(fileURLWithPath: provider.syncFolderPath))
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if !engine.largeLocalFolders.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Offload to Cloud", systemImage: "arrow.up.to.line")
                        .font(.headline)
                    Text("Copy a folder into a provider-managed location. Originals always remain in place.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    ForEach(engine.largeLocalFolders) { folder in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.name)
                                    .font(.body)
                                Text(folder.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(ByteCountFormatter().string(fromByteCount: folder.sizeBytes))
                                .font(.body.monospacedDigit())
                            if !engine.cloudProviders.isEmpty {
                                Menu {
                                    ForEach(engine.cloudProviders) { provider in
                                        Button("Copy to \(provider.name)") {
                                            engine.confirmationTitle = "Copy to \(provider.name)?"
                                            engine.confirmationMessage = "\"\(folder.name)\" will be copied to a new folder inside \(provider.name). The original will remain in place."
                                            engine.confirmationIsDestructive = false
                                            engine.pendingAction = { engine.copyToCloud(sourcePath: folder.path, provider: provider) }
                                            engine.showConfirmation = true
                                        }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .menuStyle(.borderlessButton)
                                .frame(width: 32)
                                .disabled(engine.isCopying)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }

            if engine.cloudProviders.isEmpty && engine.largeLocalFolders.isEmpty {
                ContentUnavailableView {
                    Label("No Cloud Folders", systemImage: "externaldrive.badge.icloud")
                } description: {
                    Text("No cloud sync folders or large local folders detected.")
                }
                .padding(.vertical, 20)
            }
        }
        .padding()
    }
}

// MARK: - Control pillar

struct ControlPillar: View {
    @ObservedObject var engine: ScanEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if engine.growers.isEmpty {
                ContentUnavailableView {
                    Label("No Bloated Programs", systemImage: "chart.line.uptrend.xyaxis")
                } description: {
                    Text("No bloated programs detected.")
                }
                .padding(.vertical, 20)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Growing Programs", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.headline)
                    Text("These programs can grow unchecked. Shrink them to reclaim space.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                ForEach(engine.growers) { grower in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(grower.name)
                                .font(.body)
                            Text("Using \(ByteCountFormatter().string(fromByteCount: grower.sizeBytes))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if grower.isSafe {
                            Button(grower.action) {
                                engine.confirmationTitle = "\(grower.action)?"
                                engine.confirmationMessage = "Ryddi will verify that Xcode is closed, then move this exact DerivedData folder to Finder Trash."
                                engine.confirmationIsDestructive = true
                                engine.pendingAction = { engine.shrinkGrower(grower) }
                                engine.showConfirmation = true
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(engine.isCleaning || engine.isScanning)
                        } else {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(grower.action)
                                    .font(.caption.weight(.medium))
                                Text(grower.command)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding()
    }
}
