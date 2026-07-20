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
                    Text("Clean").tag(0).keyboardShortcut("1")
                    Text("Offload").tag(1).keyboardShortcut("2")
                    Text("Control").tag(2).keyboardShortcut("3")
                    Text("Audit").tag(3).keyboardShortcut("4")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                if engine.isScanning || engine.isAuditing {
                    ProgressView(engine.isAuditing ? "Auditing..." : "Scanning...")
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
        .frame(minWidth: 600, minHeight: 500)
        .onAppear { Task { await engine.scanAll() } }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack {
                    Image(systemName: "leaf.circle.fill").foregroundStyle(.green)
                    Text("Ryddi").font(.headline)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if !engine.items.isEmpty {
                    Button(action: { engine.copyReclaimReport() }) {
                        Label("Copy Report", systemImage: "doc.on.clipboard")
                    }.help("Copy reclaim report to clipboard")
                }
            }
        }
        .navigationTitle("")
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

                Button(action: { Task { await engine.scanAll() } }) {
                    Label("Scan for Space", systemImage: "play.fill")
                        .padding(.horizontal, 24).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)

                if !engine.customPaths.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Custom Paths", systemImage: "folder.badge.plus").font(.headline)
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
            if engine.isEmergency {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Low Disk Space", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline).foregroundStyle(.orange)
                    Text("Less than 10 GB free. Use Emergency Clean to quickly reclaim space.")
                        .font(.caption)
                    Button(action: {
                        engine.confirmationTitle = "Emergency Clean?"
                        engine.confirmationMessage = "All safe items (\(ByteCountFormatter().string(fromByteCount: engine.safeTotalBytes))) will be moved to Trash."
                        engine.confirmationIsDestructive = true
                        engine.pendingAction = { engine.emergencyReclaim() }
                        engine.showConfirmation = true
                    }) {
                        Label("Emergency Clean — reclaim \(ByteCountFormatter().string(fromByteCount: engine.safeTotalBytes))", systemImage: "bolt.fill")
                            .padding(.horizontal, 16).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent).tint(.orange).controlSize(.large)
                }
                .padding()
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            HStack {
                VStack(alignment: .leading) {
                    Text("Safe to reclaim").font(.headline)
                    Text(ByteCountFormatter().string(fromByteCount: engine.selectedReclaimBytes))
                        .font(.largeTitle.bold()).foregroundStyle(.green)
                }
                Spacer()
                if engine.selectedReclaimBytes > 0 {
                    Button(action: {
                        engine.confirmationTitle = "Reclaim \(ByteCountFormatter().string(fromByteCount: engine.selectedReclaimBytes))?"
                        engine.confirmationMessage = "\(engine.selectedIDs.count) items will be moved to Trash."
                        engine.confirmationIsDestructive = true
                        engine.pendingAction = { engine.reclaim() }
                        engine.showConfirmation = true
                    }) {
                        Label("Reclaim", systemImage: "trash")
                            .padding(.horizontal, 20).padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent).tint(.green).controlSize(.large)
                }
            }
            .padding()
            .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

            ForEach(Bucket.allCases, id: \.self) { bucket in
                let bucketItems = engine.items.filter { $0.bucket == bucket }
                if !bucketItems.isEmpty {
                    BucketSectionView(bucket: bucket, items: bucketItems, engine: engine)
                }
            }
        }.padding()
    }
}

struct BucketSectionView: View {
    let bucket: Bucket
    let items: [ScanItem]
    @ObservedObject var engine: ScanEngine

    var body: some View {
        List {
            Section {
                ForEach(items) { item in
                    HStack {
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
                            .accessibilityLabel("Select \(item.name) for reclaim")
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.body)
                                Text(item.ruleTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(ByteCountFormatter().string(fromByteCount: item.sizeBytes))
                            .font(.body.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label("\(bucket.rawValue) (\(items.count) items)",
                      systemImage: bucket == .safe ? "checkmark.circle.fill"
                      : bucket == .review ? "eye.circle.fill" : "lock.circle.fill")
                    .foregroundStyle(bucket == .safe ? .green : bucket == .review ? .yellow : .red)
            }
        }
        .listStyle(.inset)
        .frame(minHeight: min(CGFloat(items.count * 32), 300))
    }
}

// MARK: - Offload pillar

struct OffloadPillar: View {
    @ObservedObject var engine: ScanEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if engine.showDeleteOriginalsPrompt, let source = engine.lastCopiedSource {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Copy Complete", systemImage: "checkmark.circle.fill")
                        .font(.headline).foregroundStyle(.green)
                    Text("\"\(URL(fileURLWithPath: source).lastPathComponent)\" copied to cloud.")
                        .font(.body)
                    Text("\(ByteCountFormatter().string(fromByteCount: engine.lastCopiedBytes)) copied.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button("Show in Finder") {
                            if let dest = engine.lastCopiedDest {
                                NSWorkspace.shared.selectFile(dest, inFileViewerRootedAtPath: "")
                            }
                        }
                        Button("Keep Local Copy") { engine.dismissCopyPrompt() }
                        Button("Delete Local Original", role: .destructive) {
                            engine.confirmationTitle = "Delete local original?"
                            engine.confirmationMessage = "The cloud copy will remain. The local original moves to Trash."
                            engine.confirmationIsDestructive = true
                            engine.pendingAction = { engine.deleteOriginalAfterCopy() }
                            engine.showConfirmation = true
                        }
                    }
                }
                .padding()
                .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            if engine.isCopying {
                HStack { ProgressView().controlSize(.small); Text("Copying...") }
                    .padding(.vertical, 4)
            }

            if !engine.cloudProviders.isEmpty {
                Label("Cloud Sync Folders", systemImage: "externaldrive.fill.badge.icloud").font(.headline)
                ForEach(engine.cloudProviders) { provider in
                    HStack {
                        Image(systemName: provider.icon).foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text(provider.name).font(.body)
                            Text(provider.syncFolderPath)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button("Show in Finder") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: provider.syncFolderPath))
                        }.buttonStyle(.borderless)
                    }.padding(.vertical, 4)
                }
            }

            if !engine.largeLocalFolders.isEmpty {
                Label("Offload to Cloud", systemImage: "arrow.up.to.line").font(.headline)
                Text("Select a folder and a cloud provider to copy files, then delete originals.")
                    .font(.caption).foregroundStyle(.secondary)

                ForEach(engine.largeLocalFolders) { folder in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(folder.name).font(.body)
                            Text(folder.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(ByteCountFormatter().string(fromByteCount: folder.sizeBytes)).font(.body.monospacedDigit())
                        if !engine.cloudProviders.isEmpty {
                            Menu {
                                ForEach(engine.cloudProviders) { provider in
                                    Button("Copy to \(provider.name)") {
                                        engine.confirmationTitle = "Copy to \(provider.name)?"
                                        engine.confirmationMessage = "\"\(folder.name)\" will be copied to \(provider.name). After verifying, delete the local original."
                                        engine.confirmationIsDestructive = false
                                        engine.pendingAction = { engine.copyToCloud(sourcePath: folder.path, provider: provider) }
                                        engine.showConfirmation = true
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .menuStyle(.borderlessButton).frame(width: 30)
                            .disabled(engine.isCopying)
                        }
                    }.padding(.vertical, 4)
                }
            }

            if engine.cloudProviders.isEmpty && engine.largeLocalFolders.isEmpty {
                Text("No cloud sync folders or large local folders detected.")
                    .foregroundStyle(.secondary).padding()
            }
        }.padding()
    }
}

// MARK: - Control pillar

struct ControlPillar: View {
    @ObservedObject var engine: ScanEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if engine.growers.isEmpty {
                Text("No bloated programs detected.").foregroundStyle(.secondary).padding()
            } else {
                Label("Growing Programs", systemImage: "chart.line.uptrend.xyaxis").font(.headline)
                Text("These programs can grow unchecked. Shrink them to reclaim space.")
                    .font(.caption).foregroundStyle(.secondary)

                ForEach(engine.growers) { grower in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(grower.name).font(.body)
                            Text("Using \(ByteCountFormatter().string(fromByteCount: grower.sizeBytes))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if grower.isSafe {
                            Button(grower.action) {
                                engine.confirmationTitle = "\(grower.action)?"
                                engine.confirmationMessage = "This will run: \(grower.command)"
                                engine.confirmationIsDestructive = true
                                engine.pendingAction = { engine.shrinkGrower(grower) }
                                engine.showConfirmation = true
                            }.buttonStyle(.borderedProminent).controlSize(.small)
                        } else {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(grower.action).font(.caption.bold())
                                Text(grower.command).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }.padding(.vertical, 4)
                }
            }
        }.padding()
    }
}
