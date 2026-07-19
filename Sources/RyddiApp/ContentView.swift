import SwiftUI
import ReclaimerCore

struct ContentView: View {
    @ObservedObject var engine: ScanEngine

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "leaf.circle.fill").font(.title).foregroundStyle(.green)
                Text("Ryddi").font(.title2.bold())
                Spacer()
                if engine.isScanning { ProgressView().controlSize(.small) }
            }.padding()

            Divider()

            if engine.items.isEmpty && !engine.isScanning {
                EmptyStateView(engine: engine)
            } else {
                Picker("View", selection: $engine.activePillar) {
                    Text("Clean").tag(0); Text("Offload").tag(1); Text("Control").tag(2)
                }.pickerStyle(.segmented).padding(.horizontal)

                ScrollView {
                    switch engine.activePillar {
                    case 0: CleanPillar(engine: engine)
                    case 1: OffloadPillar(engine: engine)
                    case 2: ControlPillar(engine: engine)
                    default: EmptyView()
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 600)
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    @ObservedObject var engine: ScanEngine

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text("Find space to reclaim").font(.title3)
            Text("Ryddi scans caches, cloud sync folders,\nand bloated programs to free local space.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button(action: { Task { await engine.scanAll() } }) {
                Label("Scan for Space", systemImage: "play.fill")
                    .padding(.horizontal, 24).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }.frame(maxHeight: .infinity)
    }
}

// MARK: - Clean pillar

struct CleanPillar: View {
    @ObservedObject var engine: ScanEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Safe to reclaim").font(.headline)
                    Text(formatBytes(engine.selectedReclaimBytes))
                        .font(.largeTitle.bold()).foregroundStyle(.green)
                }
                Spacer()
                if engine.selectedReclaimBytes > 0 {
                    Button(action: {
                        engine.confirmationTitle = "Reclaim \(formatBytes(engine.selectedReclaimBytes))?"
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
            .padding().background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

            ForEach(Bucket.allCases, id: \.self) { bucket in
                let bucketItems = engine.items.filter { $0.bucket == bucket }
                if !bucketItems.isEmpty {
                    bucketSectionView(bucket: bucket, items: bucketItems)
                }
            }
        }.padding()
    }

    func bucketSectionView(bucket: Bucket, items: [ScanItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(bucket.rawValue) (\(items.count) items)",
                  systemImage: bucket == .safe ? "checkmark.circle.fill"
                  : bucket == .review ? "eye.circle.fill" : "lock.circle.fill")
                .font(.headline)
                .foregroundStyle(bucket == .safe ? .green : bucket == .review ? .yellow : .red)

            ForEach(items) { item in
                HStack {
                    if bucket == .safe {
                        Toggle("", isOn: Binding(
                            get: { engine.selectedIDs.contains(item.id) },
                            set: { s in if s { engine.selectedIDs.insert(item.id) } else { engine.selectedIDs.remove(item.id) } }
                        )).toggleStyle(.checkbox).labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.body)
                        Text(item.ruleTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(formatBytes(item.sizeBytes)).font(.body.monospacedDigit()).foregroundStyle(.secondary)
                }.padding(.vertical, 2)
            }
        }
        .padding()
        .background((bucket == .safe ? Color.green : bucket == .review ? Color.yellow : Color.red)
            .opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Offload pillar

struct OffloadPillar: View {
    @ObservedObject var engine: ScanEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                        Button("Open in Finder") {
                            let url = URL(fileURLWithPath: provider.syncFolderPath)
                            let task = Process()
                            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                            task.arguments = [url.path]
                            try? task.run()
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
                        Text(formatBytes(folder.sizeBytes)).font(.body.monospacedDigit())
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
                            }.menuStyle(.borderlessButton).frame(width: 30)
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
                            Text("Using \(formatBytes(grower.sizeBytes))")
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

// MARK: - Helpers

private func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter().string(fromByteCount: bytes)
}
