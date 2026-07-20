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
        HStack {
            VStack(alignment: .leading) {
                Text("Safe to reclaim").font(.headline)
                Text(ByteCountFormatter().string(fromByteCount: report.safeToReclaimBytes))
                    .font(.largeTitle.bold()).foregroundStyle(.green)
            }
            Spacer()
            if report.safeToReclaimBytes > 0 {
                Button(action: {
                    engine.confirmationTitle = "Reclaim \(ByteCountFormatter().string(fromByteCount: report.safeToReclaimBytes))?"
                    engine.confirmationMessage = "\(engine.auditSelectedIDs.count) safe items will be moved to Trash."
                    engine.confirmationIsDestructive = true
                    engine.pendingAction = { engine.reclaimAuditSelection() }
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

        HStack {
            Text("Requires review: \(ByteCountFormatter().string(fromByteCount: report.needsReviewBytes))")
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: { engine.copyAuditReport() }) {
                Label("Copy Report", systemImage: "doc.on.clipboard")
            }
        }
        .padding(.horizontal)
    }
}

private struct AuditListView: View {
    let report: AuditReport
    @ObservedObject var engine: ScanEngine

    var body: some View {
        List {
            ForEach(grouped) { group in
                Section(group.category.rawValue + " (\(group.items.count))") {
                    ForEach(group.items) { rec in
                        AuditRow(rec: rec, engine: engine)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var grouped: [RecGroup] {
        let sorted = report.recommendations.sorted { $0.impactScore > $1.impactScore }
        let dict = Dictionary(grouping: sorted) { $0.category }
        return dict.map { RecGroup(category: $0.key, items: $0.value) }
            .sorted { $0.items.first?.impactScore ?? 0 > $1.items.first?.impactScore ?? 0 }
    }
}

private struct RecGroup: Identifiable {
    let id = UUID()
    let category: BloatCategory
    let items: [ReclaimRecommendation]
}

private struct AuditRow: View {
    let rec: ReclaimRecommendation
    @ObservedObject var engine: ScanEngine

    var body: some View {
        HStack {
            if rec.safetyScore >= 0.8 {
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
        rec.safetyScore >= 0.8 ? "High" : rec.safetyScore >= 0.5 ? "Med" : "Low"
    }

    private var safetyColor: Color {
        rec.safetyScore >= 0.8 ? .green : rec.safetyScore >= 0.5 ? .yellow : .red
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
