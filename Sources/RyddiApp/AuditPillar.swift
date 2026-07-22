import SwiftUI
import AppKit
import ReclaimerCore

struct AuditPillar: View {
    @ObservedObject var engine: ScanEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if engine.isAuditing {
                HStack { ProgressView().controlSize(.small); Text("Auditing...") }
                    .padding(.vertical, 4)
            }

            if let report = engine.auditReport {
                AuditSummaryView(report: report, engine: engine)
                AuditListView(report: report, engine: engine)
            } else {
                EmptyAuditView(engine: engine)
            }
        }
        .padding()
    }
}

private struct AuditSummaryView: View {
    let report: AuditReport
    @ObservedObject var engine: ScanEngine

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Selected to reclaim").font(.headline)
                Text(ByteCountFormatter().string(fromByteCount: engine.selectedAuditBytes))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
            }
            Spacer()
            if engine.selectedAuditBytes > 0 {
                Button(action: {
                    engine.confirmationTitle = "Reclaim \(ByteCountFormatter().string(fromByteCount: engine.selectedAuditBytes))?"
                    engine.confirmationMessage = "\(engine.auditSelectedIDs.count) safe items will be moved to Trash."
                    engine.confirmationIsDestructive = true
                    engine.pendingAction = { engine.reclaimAuditSelection() }
                    engine.showConfirmation = true
                }) {
                    Label("Reclaim", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
                .disabled(engine.isCleaning || engine.isAuditing)
            }
        }
        .padding(16)
        .background(.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

        HStack {
            Text("Requires review: \(ByteCountFormatter().string(fromByteCount: report.needsReviewBytes))")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: { engine.copyAuditReport() }) {
                Label("Copy Report", systemImage: "doc.on.clipboard")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct AuditListView: View {
    let report: AuditReport
    @ObservedObject var engine: ScanEngine

    var body: some View {
        List {
            ForEach(grouped) { group in
                Section {
                    ForEach(group.items) { rec in
                        AuditRow(rec: rec, engine: engine)
                    }
                } header: {
                    Label("\(group.category.rawValue) (\(group.items.count))",
                          systemImage: categoryIcon(for: group.category))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(categoryColor(for: group.category))
                }
                .headerProminence(.increased)
            }
        }
        .listStyle(.inset)
    }

    private func categoryIcon(for category: BloatCategory) -> String {
        switch category {
        case .buildArtifact: return "hammer.fill"
        case .dependencyCache: return "shippingbox.fill"
        case .oldLog: return "doc.text.fill"
        case .oldInstaller: return "archivebox.fill"
        case .aiSessionCache: return "brain.head.profile"
        case .duplicateFile: return "doc.on.doc.fill"
        case .xcodeCruft: return "xcodeproj"
        case .dockerLayer: return "cube.fill"
        case .trashOld: return "trash.fill"
        case .gitBloat: return "arrow.triangle.branch"
        case .largeBinary: return "externaldrive.fill"
        }
    }

    private func categoryColor(for category: BloatCategory) -> Color {
        switch category {
        case .buildArtifact, .dependencyCache: return .blue
        case .oldLog, .oldInstaller: return .orange
        case .aiSessionCache: return .purple
        case .duplicateFile: return .green
        case .xcodeCruft, .dockerLayer, .trashOld: return .secondary
        case .gitBloat, .largeBinary: return .red
        }
    }

    private var grouped: [RecGroup] {
        let sorted = report.recommendations.sorted { $0.impactScore > $1.impactScore }
        let dict = Dictionary(grouping: sorted) { $0.category }
        return dict.map { RecGroup(category: $0.key, items: $0.value) }
            .sorted {
                let lhs = $0.items.first?.impactScore ?? 0
                let rhs = $1.items.first?.impactScore ?? 0
                return lhs == rhs ? $0.category.rawValue < $1.category.rawValue : lhs > rhs
            }
    }
}

private struct RecGroup: Identifiable {
    let category: BloatCategory
    let items: [ReclaimRecommendation]
    var id: BloatCategory { category }
}

private struct AuditRow: View {
    let rec: ReclaimRecommendation
    @ObservedObject var engine: ScanEngine

    var body: some View {
        HStack {
            if rec.safetyScore >= 0.8 && rec.action == .moveToTrash {
                let binding = Binding(
                    get: { engine.auditSelectedIDs.contains(rec.id) },
                    set: { s in
                        if s { engine.auditSelectedIDs.insert(rec.id) }
                        else { engine.auditSelectedIDs.remove(rec.id) }
                    }
                )
                Toggle(isOn: binding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(URL(fileURLWithPath: rec.path).lastPathComponent).font(.body)
                        Text(rec.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .toggleStyle(.checkbox)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(URL(fileURLWithPath: rec.path).lastPathComponent).font(.body)
                    Text(rec.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(ByteCountFormatter().string(fromByteCount: rec.reclaimableBytes))
                .font(.body.monospacedDigit()).foregroundStyle(.secondary)
            Text(safetyLabel)
                .font(.caption2)
                .foregroundStyle(safetyColor)
        }
    }

    private var safetyLabel: String {
        if rec.safetyScore >= 0.8 && rec.action == .moveToTrash { return "Safe" }
        if rec.safetyScore >= 0.5 { return "Review" }
        return "Caution"
    }

    private var safetyColor: Color {
        if rec.safetyScore >= 0.8 && rec.action == .moveToTrash { return .green }
        if rec.safetyScore >= 0.5 { return .orange }
        return .red
    }
}

private struct EmptyAuditView: View {
    @ObservedObject var engine: ScanEngine

    var body: some View {
        VStack(spacing: 12) {
            Text("Deep Audit").font(.title2.bold())
            Text("Analyze a directory to find bloat, categorize it, and rank by safety and impact.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button(action: {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.begin { response in
                    if response == .OK, let url = panel.url {
                        engine.runAudit(path: url.path)
                    }
                }
            }) {
                Label("Choose Folder to Audit", systemImage: "folder.badge.plus")
                    .padding(.horizontal, 24).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
